# Wheel-E - System Change Document

## Background

This VESC package (Refloat/Wheel-E) was originally developed for onewheels and self-balancing skateboards. This change adapts it for use in a **self-balancing electric bike** in the style of the Future Motion Antic and The Float Life WFB.

The bike balances on its **rear wheel only**, with the front wheel lifted (wheelie). The fore-aft pitch axis and PID loop are identical to the onewheel use case — no IMU axis changes were needed. Lateral (left/right) balance is handled by the rider; the controller does not attempt to compensate for roll.

---

## Change Specification (as provided)

### 1. Throttle and brake inputs
- **ADC1** = analog throttle, **ADC2** = analog brake
- Raw ADC voltages are first smoothed with a configurable IIR low-pass filter (`throttle_adc_filter`)
- Each ADC channel is then mapped from voltage to a 0–1 (0-100%) range using the following calibration points:
  - `voltage_min` → 0 (0% current)
  - `voltage_center` → 0.5 (50% current) (Only ADC1)
  - `voltage_max` → 1 (100% current)
  - Piecewise linear interpolation between min↔center (0–0.5) and center↔max (0.5–1.0)
  - Values at or below min clamp to 0; values at or above max clamp to 1
- Each ADC channel has an `invert` boolean that flips the mapping (min→1, max→0)
- ADC1 and ADC2 are combined into a single `throttle_val` in the range -1 to +1:
  - Brake (ADC2) has absolute priority: any non-zero brake produces a negative value
  - Throttle (ADC1) only contributes when brake is exactly 0
- `throttle_val` is multiplied by the Motor Cfg max current or brake current to produce a current command
- A configurable current deadband (`throttle_current_deadband`, default 1A) suppresses commands below the deadband to prevent ADC noise from energizing the motor
- Brake current is never applied at standstill (`abs_erpm ≤ 100`) to avoid heating the motor with DC current when there is no back-EMF to regenerate
- `throttle_val` is exposed as a realtime data item for UI display

### 1a. Brake lever feathering (ADC2 ramp)
- Digital brake levers (on/off switches) produce a step from 0 to 100% the moment they close. To avoid an abrupt current step, the mapped ADC2 value is ramped up over `throttle_brake_ramp_time` seconds
- The ramp tracks the raw `adc2_mapped` value upward at `1 / (ramp_time × hertz)` per loop tick
- **Release is always instant**: when the lever is released (`adc2_mapped` drops), `adc2_mapped` follows immediately with no ramp
- Setting `throttle_brake_ramp_time = 0` disables the ramp (instant apply and release)
- The ramp is computed inside `footpad_sensor_filter_and_map()` and stored in `FootpadSensor.adc2_mapped`; the instantaneous raw value is kept in a local `_adc2_mapped` variable and is not stored on the struct

### 1b. Brake lever current scaling
- The brake lever (ADC2) commands a brake current scaled as a percentage of the motor config's **Motor Current Brake Max** (`l_current_min`)
- `throttle_brake_percent` (0–100 %) sets the maximum brake force at full lever travel; 100 % = full `current_min`
- Brake current is suppressed to zero at standstill (`abs_erpm ≤ 100`) to avoid wasting battery heating a stationary motor

### 1c. Regen braking on throttle release
- When the throttle is at zero (within deadband) and the wheel is spinning (`abs_erpm > 100`), a configurable regen current is applied
- `throttle_regen_percent` (0–100 %) sets the regen strength as a percentage of the motor config's **Motor Current Brake Max** (`l_current_min`)
- Setting `throttle_regen_percent = 0` disables regen on release entirely (default)
- While spinning, the brake current regenerates energy back into the battery; at standstill the guard prevents the zero-regen case from applying a holding current

### 2. Wheelie entry and exit

The `wheelie_button_mode` setting controls how the balance loop is engaged and disengaged. The optional button connects to the **TX pin** (one leg to TX, other to GND; firmware uses the internal pull-up — no resistor needed).

| Mode | Entry | Exit on brake | Exit on button |
|---|---|---|---|
| `WHEELIE_BTN_NONE` | Automatic when pitch ≥ `wheelie_target_pitch − startup_pitch_tolerance`; instant snap-in | Respects `wheelie_exit_rate` ramp | — |
| `WHEELIE_BTN_DOWN` | Automatic; same pitch threshold; instant snap-in | Instant | Button press (rising edge); respects `wheelie_exit_rate` ramp |
| `WHEELIE_BTN_HOLD` | Button press (rising edge); pitch threshold **ignored**; ramps via `wheelie_entry_rate` | Instant | Button released; respects `wheelie_exit_rate` ramp |

_Note: The upper two modes are similar to Antic behaviour and the latter is similar to WFB._

- Example auto-entry: target = 25°, tolerance = 4° → balance loop engages at 21°
- **Re-entry hysteresis**: after any exit, re-entry is blocked until pitch drops back below `startup_pitch_tolerance`. Brake active always blocks entry.
- **Rolling guard (`WHEELIE_BTN_HOLD` only)**: button-triggered entry also requires `abs_erpm > 100`, so an accidental press while stationary can't engage a wheelie.
- **Pitch-lead clamp (`WHEELIE_BTN_HOLD` only)**: while the entry ramp is active, the setpoint is capped to `imu.balance_pitch + max_lead`, regardless of `wheelie_entry_rate`. `max_lead` is derived from the rider's own settings rather than a fixed value: `clamp(startup_pitch_tolerance × 2, 0, wheelie_target_pitch × 0.4)` (e.g. tolerance = 4°, target = 25° → 8° lead). This stops the setpoint from racing ahead of the rider's actual pitch if the button is held without leaning in, which previously could build up a large PID error and cause a sudden lurch once the setpoint (or the bike) caught up or the button was released.
- **Integral reset on clamped exit**: if the pitch-lead clamp ever engaged during a wheelie attempt (rider held the button without leaning in), the accumulated PID integral (`pid.i`) is zeroed at the start of a ramped exit, so the stale error doesn't keep driving torque throughout the exit ramp. Well-tracked wheelies where the clamp never engages are unaffected, and instant exits (button-release on `WHEELIE_BTN_DOWN`, or any brake exit) are unaffected since the PID stops immediately there regardless.
- Throttle (ADC1) does **not** drive the motor directly while in wheelie/balance mode; only leaning affects speed. Optionally, it can instead modulate the runtime pitch angle target — see **2a** below.

### 2a. Throttle-controlled wheelie angle (`wheelie_throttle_angle`)

- `wheelie_throttle_angle` (°, default `0`, range `-10` to `+10`) lets the rider fine-tune the balance pitch target in real time by twisting the throttle, instead of it being purely fixed at `wheelie_target_pitch`.
- Applied in `refloat_thd()`, directly to `d->setpoint` right after `d->setpoint = d->setpoint_target_interpolated;` — the same pattern used by the remote/input-tilt offset immediately below it — rather than through `calculate_setpoint_target()`'s `setpoint_target`:
  `setpoint = setpoint_target_interpolated + wheelie_throttle_angle × adc1_mapped`
- This is deliberate: `setpoint_target` changes are rate-limited each iteration by `get_setpoint_adjustment_speed()`, which in the normal-running (`SAT_NONE`) case returns `tiltback_return_speed` (default `1 °/s`). Routing the throttle offset through `setpoint_target` would make it crawl toward the new angle at that slow pushback-recovery rate (multiple seconds to move a few degrees) instead of responding instantly to throttle movement.
- The mapped throttle value (`footpad.adc1_mapped`, 0–1) is scaled linearly: `adc1_mapped = 0` (throttle released) → no offset; `adc1_mapped = 1` (throttle fully twisted) → the full `wheelie_throttle_angle` is added, with no ramping — the offset tracks the throttle 1:1 every control loop iteration.
- A positive value raises the nose further as the throttle is twisted; a negative value lowers it.
- Setting `wheelie_throttle_angle = 0` (the default) disables the feature entirely — `setpoint` is exactly `setpoint_target_interpolated`, matching prior behaviour.
- This only changes the **runtime** `setpoint`; the stored `wheelie_target_pitch` config value and `setpoint_target`/`setpoint_target_interpolated` ramping are never modified.
- The offset is skipped while `wheelie_exiting` so it doesn't fight the exit ramp back to 0°.
- The applied offset is also stored in `d->wheelie_throttle_offset` and exposed as a realtime data item, so the UI's HUD throttle gauge can show it directly (see `ui.qml.in` entry below) instead of displaying a frozen throttle value while wheelieing.


### 3. Safety / rider presence
- No footpad/rider-presence detection — the bike should have an emergency-stop safety leash (deadman switch) like outboard motors.
- Footpad thresholds should be set to 0 in config to bypass all footpad logic

### 4. Cruise control
- Press the cruise button (connected to **RX pin**, active low, same wiring as the wheelie button) to enter cruise at the current speed
- Entry requires `abs_erpm > 100`, so a press while stationary is ignored
- A PI speed controller maintains that speed by adjusting motor current
- Press the cruise button again, or touch the brake (any ADC2 input), to exit cruise and return to normal throttle
- Cruise is only available from `STATE_THROTTLE` — it is impossible to enter cruise while in wheelie mode
- The feature must be enabled via `cruise_enabled`; the RX pin is not configured when disabled

### 5. 2WD — CAN forwarding to a second VESC
- A second VESC (e.g. driving the front wheel) can be driven in parallel by forwarding motor commands over the CAN bus
- `can_forward_id` sets the CAN controller ID of the slave VESC; setting it to **0 disables forwarding** entirely
- Commands are forwarded **only in `STATE_THROTTLE` and `STATE_CRUISE`** — not in `STATE_RUNNING` (wheelie balance mode). The front wheel is not driven during a wheelie.
- When the state transitions out of throttle/cruise (e.g. into wheelie), an explicit `can_set_current(id, 0)` is sent immediately so the slave does not coast at the last commanded current until its own safety timeout fires
- The following commands are mirrored to the slave:
  - `can_set_current()` / `can_set_current_off_delay()` — normal traction current
  - `can_set_current_brake()` — regen braking current
  - `can_set_duty(0)` — parking brake (phase-shorting)
- Both VESCs must be on the same CAN bus; set the slave's CAN ID in its own App Cfg

---

## Rationale

### Why the existing PID loop is reused unchanged
The onewheel and this rear-wheel-balance bike share the same physical problem: balancing a single contact point on a fore-aft pitch axis. The Mahony filter, PID gains, ATR, TorqueTilt, BrakeTilt, and booster all apply directly. Only the **target setpoint** changes (from 0° to `wheelie_target_pitch`).

### Why a separate `STATE_THROTTLE` rather than using `STATE_READY`
`STATE_READY` has logic that constantly checks for engage conditions (pitch tolerance, footpad state) and can run an RC idle move. A dedicated `STATE_THROTTLE` state gives the normal riding mode a clean, unambiguous identity in the state machine and avoids coupling with onewheel-specific startup conditions. It also makes the motor control layer aware that the motor should be actively driven (no parking brake).

### Why `setpoint_target = wheelie_target_pitch` not 0 during running
The original code sets `setpoint_target = 0` in the `SAT_NONE` (normal running) branch. For a bike balanced at ~20°, the PID would immediately try to pitch the bike back to level (0°). Changing the normal running target to `wheelie_target_pitch` means the balance loop holds the configured wheelie angle as its equilibrium.

### Why `balance_current` is seeded into `throttle_current` on exit
When the balance loop is running, it has wound up a `balance_current` value that represents the steady-state motor drive needed to maintain speed at the wheelie angle. If that is discarded on exit, the motor output drops to zero and the bike decelerates sharply before the ADC2 regen ramps back in.

Seeding `d->throttle_current = d->balance_current` before returning to `STATE_THROTTLE` means the motor output continues from the live balance value rather than dropping to zero. Since ADC2 is already > 0.05 (it triggered the exit), the brake input is immediately active. The ADC input filter (`throttle_adc_filter`) smooths the transition from the seeded value toward the new ADC-derived target.

A forced negative exit-brake pulse is not needed: the PID was already applying positive drive to hold the wheelie, so simply stopping that drive (and letting gravity do its work) is sufficient for the nose to come down. The regen current requested via ADC2 decelerates the bike on top of that.

### Why ADC values bypass the existing footpad threshold logic
`footpad_sensor_update()` converts the raw ADC float into an enumerated `FootpadSensorState` (NONE / LEFT / RIGHT / BOTH) by comparing to configured thresholds. This discards the analog value. For throttle and brake control, the raw `adc1` and `adc2` floats on the `FootpadSensor` struct are read directly in `STATE_THROTTLE`, before the thresholding step discards them.

Setting `fault_adc1 = 0` and `fault_adc2 = 0` in config causes `footpad_sensor_update()` to always return `FS_BOTH`, satisfying any remaining footpad checks in `can_engage()` and `check_faults()`, while the raw float values are still available for throttle/brake use.

### Why a separate `STATE_CRUISE` rather than a flag inside `STATE_THROTTLE`
A dedicated state makes the cruise behaviour explicit and unambiguous in the state machine. It avoids interleaving cruise PI logic with ADC throttle/brake logic in `STATE_THROTTLE`, and it ensures that wheelie entry (which is only checked in `STATE_THROTTLE`) is impossible while cruising. It also makes the motor control layer treat `STATE_CRUISE` consistently alongside `STATE_THROTTLE` for parking brake purposes.

### Why a PI controller (no D term) for cruise
The derivative term is omitted because `motor.speed` is derived from encoder data and is noisy enough that D amplifies measurement noise into current spikes. The motor's own inertia and the integrator together provide sufficient disturbance rejection for speed holding.

### Why ADC deadband is voltage-domain with a current-domain cutoff
Each ADC channel uses a voltage calibration for deadband and range mapping. Voltages at or below `voltage_min` read as 0%; voltages at or above `voltage_max` read as 100%. This makes the deadband boundaries explicit in hardware voltage terms and independent of the current scaling. ADC1 has an additional `voltage_center` point for better throttle control. Set the center higher to have more resolution at low throttle, or lower for a more aggressive throttle response.

On top of this, a configurable current deadband (`throttle_current_deadband`) suppresses final current commands below the deadband. This catches residual ADC noise that survives the voltage mapping and prevents it from energizing the motor. The default is 1A.

---

## Files Changed

### `src/state.h`
- Added `STATE_THROTTLE = 4` and `STATE_CRUISE = 5` to the `RunState` enum
- Declared `void state_throttle(State *state)` and `void state_cruise(State *state)`

### `src/state.c`
- Implemented `state_throttle()`: sets state to `STATE_THROTTLE`, clears `sat`, `stop_condition`, and `wheelslip`
- Implemented `state_cruise()`: sets state to `STATE_CRUISE`, clears `sat`, `stop_condition`, and `wheelslip`
- `state_compat()` reports `STATE_THROTTLE` and `STATE_CRUISE` as legacy `RUNNING` (`1`)

### Legacy state compatibility
`state_compat()` supplies the original Float protocol used by the deprecated `GET_RTDATA` and `GET_ALLDATA` commands and by LCM status messages. Its state field is four bits wide and all codes `0` through `15` are already assigned, so it cannot distinguish the two bike riding states. Both therefore use legacy `RUNNING` (`1`).

The current realtime-data protocol sends the internal state in bits 26-24 of `state_flags`; it preserves the distinct `STATE_THROTTLE` (`4`) and `STATE_CRUISE` (`5`) values for the Wheel-E UI.

### `src/conf/datatypes.h`
- Added fields to `RefloatConfig` (before `CfgMeta meta`):

| Field | Type | Default | Description |
|---|---|---|---|
| `wheelie_enabled` | `bool` | true | Master on/off switch for wheelie mode. When false, entry (button or pitch-triggered) is blocked and an in-progress wheelie exits immediately back to `STATE_THROTTLE` |
| `wheelie_target_pitch` | `float` | 25° | Pitch angle the balance loop holds in wheelie mode |
| `wheelie_entry_rate` | `float` | 0 °/s | Rate to ramp setpoint up to target on entry; 0 = instant; values 1–19 are clamped to 20 °/s minimum |
| `wheelie_entry_rate_factor` | `float` | 0 °/s per km/h | Speed-dependent adjustment: effective entry rate = `wheelie_entry_rate + abs(speed_kmh) × factor`; clamped to 0 |
| `wheelie_exit_rate` | `float` | 0 °/s | Rate to ramp setpoint down to 0° on exit; 0 = instant; values 1–19 are clamped to 20 °/s minimum |
| `wheelie_exit_rate_factor` | `float` | 0 °/s per km/h | Speed-dependent adjustment: effective exit rate = `wheelie_exit_rate + abs(speed_kmh) × factor`; clamped to 0 |
| `wheelie_button_mode` | `WheelieButtonMode` | None | How the button on TX/SCL interacts with wheelie entry/exit |
| `wheelie_throttle_angle` | `float` | 0° | Max angle added to `wheelie_target_pitch` at full throttle (`adc1_mapped`), scaled linearly; 0 = disabled; can be negative |
| `cruise_enabled` | `bool` | false | Enables cruise control and configures RX pin as pull-up input |
| `cruise_kp` | `float` | 2.0 A/(km/h) | Proportional gain for cruise PI controller |
| `cruise_ki` | `float` | 0.5 A/(km/h·s) | Integral gain for cruise PI controller |
| `throttle_current_deadband` | `float` | 1.0A | Current commands below this are suppressed to zero |
| `throttle_brake_percent` | `float` | 50 % | Max brake force from ADC2 lever as % of motor config brake current limit |
| `throttle_brake_ramp_time` | `float` | 0.2 s | Time to ramp ADC2 from 0 to full when lever is pressed; 0 = instant |
| `throttle_ramp_time` | `float` | 0 s | Time to ramp ADC1 throttle from 0 to full when applied; release is instant; 0 = no ramp |
| `throttle_speed_limit` | `float` | 0 km/h | Soft speed limit: throttle current fades out approaching it; brake/regen unaffected; also clamps cruise target; 0 = disabled |
| `throttle_speed_fade` | `float` | 3 km/h | Speed range below the limit over which throttle current fades to zero |
| `throttle_regen_percent` | `float` | 0 % | Regen brake strength on throttle release as % of motor config brake current limit; 0 = disabled |
| `throttle_adc1_voltage_min` | `float` | 0.5V | ADC1 voltage mapping to 0% current |
| `throttle_adc1_voltage_center` | `float` | 1.65V | ADC1 voltage mapping to 50% current |
| `throttle_adc1_voltage_max` | `float` | 3.2V | ADC1 voltage mapping to 100% current |
| `throttle_adc1_invert` | `bool` | false | Invert ADC1 so min voltage maps to 100% and max to 0% |
| `throttle_adc2_voltage_min` | `float` | 0.5V | ADC2 voltage mapping to 0% current |
| `throttle_adc2_voltage_max` | `float` | 3.2V | ADC2 voltage mapping to 100% current |
| `throttle_adc2_invert` | `bool` | false | Invert ADC2 so min voltage maps to 100% and max to 0% |
| `throttle_adc_filter` | `float` | 0.1 | IIR low-pass filter coefficient for raw ADC voltages (0 = off, 0.99 = heavy) |
| `can_forward_id` | `uint8_t` | 0 | CAN ID of the slave VESC to forward motor commands to; 0 = disabled |

### `src/conf/conf_default.h`
- Added `CFG_DFLT_CRUISE_ENABLED` (0), `CFG_DFLT_CRUISE_KP` (2.0), `CFG_DFLT_CRUISE_KI` (0.5)

### `src/conf/confparser.c`
- Serialization, deserialization, and defaults for `cruise_enabled`, `cruise_kp`, `cruise_ki` (inserted after `wheelie_button_mode`)
- Config signature bumped by 1 to invalidate stale EEPROM configs

### `src/conf/settings.xml`
- Added full parameter definitions for all new fields (type, range, step, unit, description)
- Added serialization order entries after `remote_throttle_grace_period`
- Added a new **Bike** subgroup under the **General** group with four UI separator sections:
  - **Throttle mode**: `throttle_current_deadband`, `throttle_adc1_voltage_min`, `throttle_adc1_voltage_center`, `throttle_adc1_voltage_max`, `throttle_adc1_invert`, `throttle_adc2_voltage_min`, `throttle_adc2_voltage_max`, `throttle_adc2_invert`, `throttle_adc_filter`
  - **Wheelie mode**: `wheelie_enabled`, `wheelie_target_pitch`, `wheelie_entry_rate`, `wheelie_entry_rate_factor`, `wheelie_exit_rate`, `wheelie_exit_rate_factor`, `wheelie_button_mode`, `wheelie_throttle_angle`
  - **Cruise control**: `cruise_enabled`, `cruise_kp`, `cruise_ki`
  - **Slave VESC (2WD)**: `can_forward_id`
- Default of `fault_adc1` and `fault_adc2` changed from `2` to `0` so footpad switch logic is disabled out of the box
- Renamed the config page from "Refloat Cfg" to "Wheel-E Cfg" and the "Refloat Package Details" separator to "Package Details"
- Hid board-only options from the UI by commenting them out of `<Grouping>` (the parameters remain in `<Params>` and `<SerOrder>`, so the config layout is unchanged and they keep their defaults):
  - **Startup**: `startup_simplestart_enabled`, `startup_pushstart_enabled`, `startup_dirtylandings_enabled`, and the **Holding** section (`parking_brake_mode`, `brake_current`)
  - **Stop**: the **Switches** and **Features** sections (`fault_delay_switch_half`, `fault_delay_switch_full`, `fault_adc_half_erpm`, `fault_is_dual_switch`, `fault_moving_fault_disabled`, `enable_quickstop`, `fault_darkride_enabled`, `fault_reversestop_enabled`)
  - **Remote**: the whole subgroup

### `src/data.h`
- Added `float throttle_current` to the `Data` struct — holds the current output in `STATE_THROTTLE`
- Added `float throttle_adc1_filtered` and `float throttle_adc2_filtered` — IIR-filtered raw ADC voltages
- Added `float throttle_adc1_mapped` and `float throttle_adc2_mapped` — calibrated 0–1 values after min/center/max mapping and optional inversion
- Added `float throttle_val` — combined throttle/brake value (-1 to +1) exposed to UI via realtime data
- Added `bool wheelie_entry_armed` — hysteresis flag preventing immediate wheelie re-entry after a brake exit
- Added `bool wheelie_exiting` — flag indicating the wheelie exit ramp is in progress
- Added `bool wheelie_entering` — flag indicating the wheelie entry ramp is in progress
- Added `float wheelie_exit_step_size` — precomputed degrees-per-iteration from `wheelie_exit_rate` used as a gate for whether exit ramp is active
- Added `bool wheelie_btn_pressed` — current debounced state of the button on TX pin (true = pressed)
- Added `bool wheelie_btn_prev` — previous button state, used for rising-edge detection
- Added `bool cruise_btn_pressed` / `cruise_btn_prev` — state of the cruise button on RX pin
- Added `float cruise_target_speed` — speed (km/h) captured when cruise was activated
- Added `float cruise_pid_i` — running integral accumulator for cruise PI controller (amps)
- Added `float wheelie_throttle_offset` — the runtime offset currently added to the wheelie setpoint by throttle twist (`wheelie_throttle_angle * adc1_mapped`); 0 when not wheelieing or when the throttle isn't twisted, exposed to the UI via realtime data

### `src/rt_data.h`
- Added `S(throttle_val)` to the `RT_DATA_ITEMS` macro — sends `d->throttle_val` as a realtime data item to the UI
- Added `S(wheelie_throttle_offset)` to the `RT_DATA_RUNTIME_ITEMS` macro — sends `d->wheelie_throttle_offset` as a realtime data item, only while `STATE_RUNNING` (reads as `NaN` otherwise, so the UI never shows a stale value)

### `src/motor_control.h` / `src/motor_control.c`
- Added `uint8_t can_forward_id` to `MotorControl` — stores the configured CAN ID from config
- Added `uint8_t can_forward` to `MotorControl` — runtime effective value; set to `can_forward_id` only when state is `STATE_THROTTLE` or `STATE_CRUISE`, otherwise 0
- `motor_control_configure()` copies `config->can_forward_id` into `mc->can_forward_id`
- `motor_control_apply()` evaluates state each call and sets `mc->can_forward` accordingly. When the effective ID transitions from non-zero to zero, an explicit `can_set_current(prev_id, 0.0f)` is sent to stop the slave immediately
- All existing motor command paths check `if (mc->can_forward > 0)` and mirror the same command to the slave via the corresponding `VESC_IF->can_set_*` function
- `motor_control_apply()`: `STATE_THROTTLE` and `STATE_CRUISE` are now treated alongside `STATE_RUNNING` in the parking brake logic — parking brake is deactivated and current commands are passed through normally
- Added `brake_current_requested` / `requested_brake_current` fields to `MotorControl`
- Added `motor_control_request_brake_current()`: sets the new fields; `motor_control_apply()` routes these to `VESC_IF->mc_set_brake_current()` (positive value, signed-current path bypassed) so regen never drives the motor in reverse

### `src/main.c`

#### `calculate_setpoint_target()` — normal running setpoint
```c
// Before:
d->setpoint_target = 0;

// After:
d->setpoint_target = d->float_conf.wheelie_target_pitch;
```
The balance equilibrium is now the configured wheelie angle, not level. (The throttle-controlled runtime offset, `wheelie_throttle_angle`, is applied separately, directly to `d->setpoint` — see **2a** above and the `refloat_thd()` entry below — rather than here, so it isn't rate-limited by `tiltback_return_speed`.)

#### `STATE_STARTUP` transition
```c
// Before: → STATE_READY
// After:  → STATE_THROTTLE
```
After IMU calibration, the bike goes directly to normal riding mode. There is no waiting-for-engage step.

#### `STATE_RUNNING` — fault exit redirect
After `check_faults()` stops the balance loop (e.g., pitch fault from landing), the state machine previously landed in `STATE_READY`. For the bike it redirects to `STATE_THROTTLE` with `throttle_current` zeroed so the motor is released cleanly rather than carrying through whatever current the balance loop was commanding.

#### `STATE_RUNNING` — wheelie exit on brake
When the brake is pressed (ADC2 mapped > 0), the exit behaviour depends on `wheelie_exit_rate`:

**With exit ramp (`wheelie_exit_rate` > 0):** The balance loop stays active but `setpoint_target` is set to 0°. Each loop iteration the effective exit rate is computed as `wheelie_exit_rate + abs(motor.speed) × wheelie_exit_rate_factor` (clamped to ≥ 0), then divided by `hertz` to get the per-iteration step size. A minimum of 20 °/s is enforced at configure time to prevent dangerously slow exits from misconfigured or stale values. Once the interpolated setpoint reaches ≤ `startup_pitch_tolerance`, the state transitions to `STATE_THROTTLE` with a bumpless handover.

On button-triggered entry (Hold mode), `wheelie_entry_rate` and `wheelie_entry_rate_factor` are used instead: the setpoint ramps up from the current pitch to `wheelie_target_pitch` at the computed entry rate.

**Without ramp (rate = 0):** Instant transition.

```c
// Wheelie exit: brake pressed on ADC2 -> begin exit sequence.
// DOWN and HOLD modes always exit instantly on brake regardless of exit rate.
// NONE mode respects the exit ramp if configured.
if (d->footpad.adc2_mapped > 0.0f && !d->wheelie_exiting) {
    bool instant_brake_exit = d->float_conf.wheelie_button_mode == WHEELIE_BTN_DOWN ||
        d->float_conf.wheelie_button_mode == WHEELIE_BTN_HOLD;
    if (d->wheelie_exit_step_size > 0.0f && !instant_brake_exit) {
        // Start ramping the setpoint down to 0
        d->wheelie_entering = false;
        d->wheelie_exiting = true;
        d->setpoint_target = 0;
    } else {
        // Instant exit
        state_throttle(&d->state);
        d->throttle_current = d->balance_current;
        d->wheelie_entry_armed = false;
        d->wheelie_entering = false;
        break;
    }
}

// Button-triggered exit (DOWN: press, HOLD: release)
if (!d->wheelie_exiting) {
    bool btn_exit = false;
    if (d->float_conf.wheelie_button_mode == WHEELIE_BTN_DOWN) {
        btn_exit = d->wheelie_btn.pressed && !d->wheelie_btn.prev;
    } else if (d->float_conf.wheelie_button_mode == WHEELIE_BTN_HOLD) {
        btn_exit = !d->wheelie_btn.pressed;
    }
    if (btn_exit) {
        if (d->wheelie_exit_step_size > 0.0f) {
            d->wheelie_entering = false;
            d->wheelie_exiting = true;
            d->setpoint_target = 0;
        } else {
            state_throttle(&d->state);
            d->throttle_current = d->balance_current;
            d->wheelie_entry_armed = false;
            d->wheelie_entering = false;
            break;
        }
    }
}

// Wheelie exit ramp: once setpoint has reached entry threshold, transition to throttle
if (d->wheelie_exiting && d->setpoint_target_interpolated <= d->float_conf.startup_pitch_tolerance) {
    state_throttle(&d->state);
    d->throttle_current = d->balance_current;
    d->wheelie_entry_armed = false;
    d->wheelie_exiting = false;
    break;
}
```

During the ramp, `calculate_setpoint_target()` skips overwriting `setpoint_target` back to `wheelie_target_pitch` when `wheelie_exiting` is true. The `rate_limitf` step size is computed dynamically each iteration from `wheelie_exit_rate + abs(motor.speed) × wheelie_exit_rate_factor` (or the entry equivalents when `wheelie_entering` is true), replacing the normal `get_setpoint_adjustment_step_size()` result.

#### ADC filtering and mapping

ADC filtering and piecewise min/center/max mapping runs every cycle **before** the state machine switch, so the mapped values (`d->throttle_adc1_mapped`, `d->throttle_adc2_mapped`) are available in both `STATE_THROTTLE` and `STATE_RUNNING`. Raw ADC voltages are smoothed with an IIR low-pass filter, then mapped through per-channel min/center/max calibration to a 0–1 range with optional inversion.

#### New `STATE_THROTTLE` case

The pre-computed mapped values are combined into a single `throttle_val` (-1 to +1) where brake has absolute priority. The final current command is suppressed below a configurable deadband to prevent ADC noise from energizing the motor. Brake current is never applied at standstill.

```c
case STATE_THROTTLE: {
    // adc2_mapped is the ramped brake lever value (see footpad_sensor.c).
    if (d->footpad.adc2_mapped > 0.0f) {
        d->throttle_val = -d->footpad.adc2_mapped;
    } else {
        d->throttle_val = clampf(d->footpad.adc1_mapped, 0.0f, 1.0f);
    }
    float current = 0.0f;
    if (d->throttle_val < 0) {
        // Only apply brake current while spinning to avoid heating a stationary motor
        if (d->motor.abs_erpm > 100) {
            current = d->throttle_val *
                (d->float_conf.throttle_brake_percent / 100.0f) * d->motor.current_min;
        }
    } else if (d->throttle_val > 0) {
        current = d->throttle_val * d->motor.current_max;
    }
    // set current request. Ignore current below deadband
    float deadband = d->float_conf.throttle_current_deadband;
    if (current < -deadband) {
        motor_control_request_brake_current(&d->motor_control, -current);
        d->throttle_current = 0;
    } else if (current > deadband) {
        motor_control_request_current(&d->motor_control, current);
        d->throttle_current = current;
    } else if (d->float_conf.throttle_regen_percent > 0 && d->motor.abs_erpm > 100) {
        // Regen brake when throttle is at zero and wheel is still spinning
        float regen_current =
            d->motor.current_min * (d->float_conf.throttle_regen_percent / 100.0f);
        motor_control_request_brake_current(&d->motor_control, regen_current);
    } else {
        motor_control_request_current(&d->motor_control, 0.0f);
    }

    // Wheelie re-entry hysteresis: pitch must drop below threshold before
    // we allow re-entering wheelie, preventing immediate re-engage after
    // a brief brake tap.
    if (!d->wheelie_entry_armed) {
        if (d->imu.balance_pitch < d->float_conf.startup_pitch_tolerance) {
            d->wheelie_entry_armed = true;
        }
    }

    // Wheelie entry: Hold mode triggers immediately on button press (rising edge),
    // regardless of current pitch. None and Down use pitch-based auto-entry.
    // Brake active always blocks entry.
    if (d->footpad.adc2_mapped == 0.0f && d->wheelie_entry_armed &&
        d->float_conf.wheelie_button_mode == WHEELIE_BTN_HOLD && d->wheelie_btn.pressed &&
        !d->wheelie_btn.prev) {
        engage(d);
        d->setpoint_target = d->float_conf.wheelie_target_pitch;
        d->balance_current = d->throttle_current;
        if (d->float_conf.wheelie_entry_rate > 0.0f) {
            d->wheelie_entering = true;
        }
    } else if (d->footpad.adc2_mapped == 0.0f && d->wheelie_entry_armed &&
               (d->float_conf.wheelie_button_mode == WHEELIE_BTN_NONE ||
                d->float_conf.wheelie_button_mode == WHEELIE_BTN_DOWN) &&
               d->imu.balance_pitch >= (d->float_conf.wheelie_target_pitch -
                                        d->float_conf.startup_pitch_tolerance)) {
        engage(d);
        d->setpoint_target = d->float_conf.wheelie_target_pitch;
        d->balance_current = d->throttle_current;
    }

    // Cruise control entry: rising edge of cruise button
    if (d->float_conf.cruise_enabled && d->cruise_btn.pressed && !d->cruise_btn.prev) {
        d->cruise_target_speed = d->motor.speed;
        d->cruise_pid_i = 0;
        state_cruise(&d->state);
        break;
    }
    break;
}
```

**Regen braking:** Brake current is routed through `motor_control_request_brake_current()`, which calls `mc_set_brake_current()` with a positive value. This always regenerates energy regardless of motor direction and cannot reverse the motor. Using `mc_set_current()` with a negative value would instead command reverse torque.

**Brake priority:** ADC2 (brake) has absolute priority over ADC1 (throttle). Any non-zero brake input produces a negative `throttle_val`, which maps to regen current. Throttle only contributes when the brake mapped value is exactly zero.

**Current deadband:** Both throttle and brake current commands below `throttle_current_deadband` (default 1A) are suppressed to zero. This prevents residual ADC voltage on an unused input from producing a small but nonzero current command that would keep the motor energized.

#### New `STATE_CRUISE` case

On a rising edge of the cruise button (from `STATE_THROTTLE`), `cruise_target_speed` is set to `motor.speed` (km/h) and the integrator is zeroed. Each loop iteration:

```c
float cruise_error = d->cruise_target_speed - d->motor.speed;
d->cruise_pid_i += cruise_error * d->float_conf.cruise_ki / d->float_conf.hertz;

float i_max = d->motor.current_max;
if (d->cruise_pid_i > i_max) {
    d->cruise_pid_i = i_max;
} else if (d->cruise_pid_i < -i_max) {
    d->cruise_pid_i = -i_max;
}

float cruise_current = cruise_error * d->float_conf.cruise_kp + d->cruise_pid_i;

if (cruise_current > d->motor.current_max) {
    cruise_current = d->motor.current_max;
} else if (cruise_current < -d->motor.current_max) {
    cruise_current = -d->motor.current_max;
}
```

Positive output → `motor_control_request_current()`. Negative output → `motor_control_request_brake_current()` (regen, cannot reverse). Near-zero output (within `throttle_current_deadband`) → zero.

Exit conditions checked first each cycle: any brake touch (`adc2_mapped > 0`) or rising edge of cruise button → `state_throttle()`, `throttle_current = 0`.

#### Bumpless transfer on wheelie entry

`engage()` calls `reset_runtime_vars()`, which zeros both `balance_current` and the PID state. Without correction this causes a current step from whatever `throttle_current` was down to 0A the instant the balance loop takes over, producing an immediate deceleration kick.

`throttle_current` is updated every cycle in `STATE_THROTTLE` to the actual current being commanded: set to the computed forward current when throttle is active, and zeroed when the brake is active (a negative seed would fight the wheelie). This keeps `throttle_current` a live reflection of the motor output at the moment of entry.

The fix seeds `balance_current` from `throttle_current` immediately after `engage()` returns. Because `STATE_RUNNING` integrates `balance_current` with an 0.8/0.2 IIR (`balance_current = balance_current * 0.8 + new_current * 0.2`), starting from the live throttle value gives the PID integral time to wind up to the correct steady-state current before the seed decays. No I-term preload is required — the seeded `balance_current` provides enough continuity.

The PID setpoint itself is not an issue: `reset_runtime_vars()` seeds `setpoint` and `setpoint_target_interpolated` to the **current** pitch, so the first PID error is near zero regardless of how far the target pitch is from the entry pitch. The centering ramp (`SAT_CENTERING`) then moves the setpoint toward `wheelie_target_pitch` at `startup_step_size`.

### `ui.qml.in`

- Added `readonly property int s_Throttle: 4` and `readonly property int s_Cruise: 5` state constants
- Added `[s_Throttle, "THROTTLE"]` and `[s_Cruise, "CRUISE"]` to `pkgStateToString` — displays the correct label in the state indicator
- Added `s_Throttle` and `s_Cruise` to the `pkgStateIsError` exclusion list — neither state is treated as a fault
- Added `["throttle_val", ...]` to the realtime data item map — the combined throttle/brake value (-1 to +1) is plotted in the live data graph
- Added `["wheelie_throttle_offset", ...]` to the realtime data item map — plotted in the "pitch" scaling group alongside `setpoint`
- Added `throttleGauge`: a dial widget in the HUD that reads `state.rtData["throttle_val"]` and displays throttle/brake percentage on a ±100% dial labelled "throttle"
- `throttleGauge` switches modes while in wheelie mode (`state.pkgState === state.s_Running`): the dial shows `state.rtData["wheelie_throttle_offset"]` on a fixed ±10° scale (matching the `wheelie_throttle_angle` setting bounds) instead of the throttle percentage, reading 0° when the throttle isn't twisted, and the label changes from "throttle" to "angle mode"
- Rebranded user-facing text from "Refloat" / "board" to "Wheel-E" / "bike" (page name, dialogs, enable/disable buttons, backup labels, log prefixes)
- Replaced the onewheel board pitch visualiser with a **bike SVG** (`pitchBikeFramePath`, `pitchBikeForkPath`, `pitchBikeSeatPath`, `pitchBikeWheel1Path`, `pitchBikeWheel2Path`) — the bike shape rotates with pitch in the same canvas, showing front and rear wheels, frame, fork, and seat drawn with inline SVG paths

### Why wheelie re-entry uses hysteresis
Without hysteresis, a brief brake tap exits wheelie mode (`STATE_RUNNING` → `STATE_THROTTLE`) but the pitch is still near the entry tolerance. On the very next control loop iteration the entry condition is met again and the bike immediately re-enters wheelie, making it impossible to exit with a short brake press.

The fix adds a `wheelie_entry_armed` flag:
1. On wheelie exit (brake press), the flag is cleared (`false`)
2. While `false`, the wheelie entry check is skipped regardless of pitch
3. The flag is re-armed (`true`) only when pitch drops below `startup_pitch_tolerance` (near level)
4. On startup, the flag is initialized to `true` via `reset_runtime_vars()` so the first entry works

This forces the rider to bring the front wheel down past the tolerance before wheelie mode can engage again, giving a clean and intentional transition.

---

## Configuration Checklist

When deploying on a bike, set the following in the VESC Tool UI:

|Path| Parameter | Recommended value | Reason |
|---|---|---|---|
|Wheel-E Cfg → Specs | ADC1 Switch Voltage (`fault_adc1`) | `0` (default) | Disables footpad switch logic; ADC1 raw value still readable for throttle |
|Wheel-E Cfg → Specs | ADC2 Switch Voltage (`fault_adc2`) | `0` (default) | Disables footpad switch logic; ADC2 raw value still readable for brake |
|App Cfg → General | App to use | `No App` | Disables the VESC built in ADC app. Prevents interference with the current commands. Alternatively set to `UART` |
|Motor Cfg → General → Current | Max current | Safe value | This is the max motor current. Set this low when you start to tune to prevent damage |
|Wheel-E Cfg → Bike | Wheelie Target Pitch (`wheelie_target_pitch`) | Tune per bike | Physical balance point — start at 25° and adjust |
|Wheel-E Cfg → Bike | Wheelie Entry Rate (`wheelie_entry_rate`) | `0` or `30-90` | °/s to ramp setpoint up on entry; 0 = instant; minimum 20 °/s enforced for non-zero values |
|Wheel-E Cfg → Bike | Wheelie Entry Rate Factor (`wheelie_entry_rate_factor`) | `0` | °/s added per km/h of bike speed during entry ramp |
|Wheel-E Cfg → Bike | Wheelie Exit Rate (`wheelie_exit_rate`) | `0` or `30-90` | °/s to ramp setpoint down on exit; 0 = instant; minimum 20 °/s enforced for non-zero values |
|Wheel-E Cfg → Bike | Wheelie Exit Rate Factor (`wheelie_exit_rate_factor`) | `0` | °/s added per km/h of bike speed during exit ramp |
|Wheel-E Cfg → Bike | Wheelie Button Mode (`wheelie_button_mode`) | `None` | Button on TX pin: None / Down / Hold |
|Wheel-E Cfg → Bike | Wheelie Throttle Angle (`wheelie_throttle_angle`) | `0` | Max degrees added to the wheelie target by twisting the throttle; 0 = disabled |
|Wheel-E Cfg → Bike | Throttle Current Deadband (`throttle_current_deadband`) | `1.0` | Current commands below this (A) are suppressed to zero |
|Wheel-E Cfg → Bike | Brake Lever Strength (`throttle_brake_percent`) | `50` | Max brake current as % of motor config brake current limit; 100 % = full braking |
|Wheel-E Cfg → Bike | Brake Lever Ramp Time (`throttle_brake_ramp_time`) | `0.2` | Seconds to ramp from 0 to max brake on lever press; 0 = instant (useful for analog levers) |
|Wheel-E Cfg → Bike | Throttle Ramp Time (`throttle_ramp_time`) | `0` | Seconds to ramp from 0 to full throttle when applied; release is instant; 0 = no ramp |
|Wheel-E Cfg → Bike | Regen Brake Strength (`throttle_regen_percent`) | `0` | % of motor config brake current limit applied as regen when throttle is released; 0 = disabled |
|Wheel-E Cfg → Bike | Throttle ADC1 Voltage Min (`throttle_adc1_voltage_min`) | `0.5` | ADC1 voltage at 0% throttle; adjust to match hardware rest voltage |
|Wheel-E Cfg → Bike | Throttle ADC1 Voltage Center (`throttle_adc1_voltage_center`) | `1.65` | ADC1 voltage at 50% current |
|Wheel-E Cfg → Bike | Throttle ADC1 Voltage Max (`throttle_adc1_voltage_max`) | `3.2` | ADC1 voltage at 100% throttle; adjust to match hardware full-scale |
|Wheel-E Cfg → Bike | Throttle ADC1 Invert (`throttle_adc1_invert`) | `false` | Flip ADC1 direction if wired in reverse |
|Wheel-E Cfg → Bike | Brake ADC2 Voltage Min (`throttle_adc2_voltage_min`) | `0.5` | ADC2 voltage at 0% brake |
|Wheel-E Cfg → Bike | Brake ADC2 Voltage Max (`throttle_adc2_voltage_max`) | `3.2` | ADC2 voltage at 100% brake |
|Wheel-E Cfg → Bike | Brake ADC2 Invert (`throttle_adc2_invert`) | `false` | Flip ADC2 direction if wired in reverse |
|Wheel-E Cfg → Bike | Throttle ADC Filter (`throttle_adc_filter`) | `0.1` | Low-pass filter strength for raw ADC voltages; 0 = off, higher = smoother but more lag |
|Wheel-E Cfg → Startup → Tolerances | Startup Pitch Axis Angle Tolerance (`startup_pitch_tolerance`) | `2–6°` | Smaller = later entry (less time to catch); larger = earlier but may trigger unintentionally |
|Wheel-E Cfg → Stop | Pitch Axis Fault Cutoff (`fault_pitch`) | Tune per bike | Must be above wheelie angle to avoid spurious pitch faults during balance |
|Wheel-E Cfg → Bike → Cruise control | Enable Cruise Control (`cruise_enabled`) | `true` | Must be on for RX pin to be configured and cruise to be available |
|Wheel-E Cfg → Bike → Cruise control | Cruise Control KP (`cruise_kp`) | `2.0` | Start here; increase if speed response is sluggish |
|Wheel-E Cfg → Bike → Cruise control | Cruise Control KI (`cruise_ki`) | `0.5` | Start here; increase if steady-state speed error persists on hills |
|Wheel-E Cfg → Bike → Slave VESC (2WD) | CAN Forward ID (`can_forward_id`) | `0` | Set to the CAN ID of the slave VESC to enable 2WD forwarding; 0 = disabled |

---

## State Machine Diagram

```
STARTUP
   │ (IMU ready)
   ▼
 ┌─────────────────────────────────────────────────────────┐
 │  Every cycle (before switch):                           │
 │    IIR low-pass filter on raw ADC voltages              │
 │    ADC1 → piecewise mapped (min/center/max → 0..1)      │
 │    ADC2 → piecewise mapped (min/max → 0..1)             │
 │    TX pin read → wheelie_btn (if mode ≠ None)           │
 └─────────────────────────────────────────────────────────┘
   │
   ▼
STATE_THROTTLE ◄────────────────────────────────────────────────────────────────────┐
   │  ADC1 = throttle, ADC2 = brake (brake has priority)                            │
   │  Current deadband: |current| < deadband → 0                                    │
   │  Re-entry blocked until pitch < tolerance AND brake not active                 │
   │                                                                                │
   ├── cruise button (RX) pressed ──► STATE_CRUISE ─┐                               │
   │     (captures motor.speed, zeroes integrator)  │                               │
   │                                                ├── cruise button pressed ─────►│
   │                                                └── adc2_mapped > 0 ───────────►│
   │                                                                                │
   │ [mode: None / Down]  pitch ≥ (target − tolerance) AND re-entry armed           │
   │                      AND adc2_mapped == 0                                      │
   │ [mode: Hold]         TX button pressed (rising edge) AND re-entry armed        │
   │                      AND adc2_mapped == 0                                      │
   ▼                                                                                │
STATE_RUNNING (wheelie balance loop)                                                │
   │  pitch PID holds wheelie_target_pitch                                          │
   │  Throttle/brake inputs ignored for speed control                               │
   │                                                                                │
   ├── adc2_mapped > 0 [mode: Down / Hold] ──────────────────── instant exit ──────►│
   │                                                                                │
   ├── adc2_mapped > 0 [mode: None] ─────┐                                          │
   │                                     ├─ exit_rate > 0: ramps → 0°, exits ──────►│
   │                                     └─ exit_rate = 0: instant exit ───────────►│
   │                                                                                │
   ├── TX button pressed  [mode: Down]  ──┐                                         │
   │   TX button released [mode: Hold]  ──┤ exit_rate > 0: ramps → 0°, exits ──────►│
   │                                      └ exit_rate = 0: instant exit ───────────►│
   │                                                                                │
   └── fault (pitch/roll/temp/voltage) ────────────────────────────────────────────►┘
```
