# Scooter Dashboard Support

[Scooter Dashboard Support on GitHub](https://github.com/lucidnx/Scooter%5FDashboard%5FSupport)

For VESC-based controllers. Connect a Xiaomi or Ninebot dashboard to a VESC
controller. Speed modes, secret modes, lock with alarm, fully remappable
button/lever gestures, cruise control, rear light,
BMS support and a live remote-control dashboard - all configured from a phone-friendly UI
and stored on the ESC.

## ⚠️ Disclaimer

**Use at your own risk.** This is community software provided **as-is, without any warranty**
of any kind, express or implied. It controls a moving vehicle - a bug, misconfiguration, or
hardware fault could cause **loss of motor power, unintended acceleration or braking, or
failure of the lock, alarm, or cruise features**, potentially resulting in a crash, injury,
or damage.

By installing or using this package you accept **full responsibility** for it. The authors
and contributors accept **no liability** for any damage, injury, or loss arising from its use.

- **Test everything on a stand, wheels off the ground, before riding** - especially throttle,
  brake, mode limits, lock/unlock, and cruise control.
- **Cruise control is experimental** - verify the throttle/brake cancel works reliably before
  trusting it, and try it first at low speed on open ground.
- Set your motor current, battery, and temperature limits correctly in VESC Tool; this package
  does not protect your hardware from bad configuration.
- Riding a modified scooter may be illegal on public roads in your jurisdiction and may void
  warranties. Wear appropriate safety gear.

If you don't accept these terms, don't install it.

## 🛠️ Functions

One package for everything - the model is stored on the ESC and selected in the UI:

- **G30** - Ninebot G30 dashboard
- **M365/1S/PRO2** - Xiaomi M365, 1S, Essential and PRO 2 dashboards
- **G2** - Ninebot Max G2 dashboard. **Untested** - no G2 hardware has run it yet
- **Slave** - secondary ESC in a dual setup, only runs the CAN code server

### 🛞 Speed modes
- Three modes (Eco / Drive / Sport) plus three **secret** modes, each with its own speed,
  current, watts, field weakening and overmodulation
- **Current %** is a percentage of your Motor Current Max, capped at 100%; **Overmodulation**
  is floored at 1.0, so neither can overdrive the motor
- Each parameter has its own apply toggle - unchecked parameters never touch your motor
  config, so you can keep your own field weakening setup
- Selectable startup mode

### 🎛️ Gestures
Lock, mode switching, headlight, secret mode and leaving secret mode are fully remappable:

- **Lever combination** - any mix of Brake / Throttle to hold, or none
- **Button presses** - 1-5, or **No** to fire from the levers alone after half a second
- **Locked** - restrict a gesture to the locked state only
- **Secret** turns the three secret modes on and off. While secret is on, the Modes gesture
  cycles the secret Eco / Drive / Sport set instead of the normal one
- **Secret OFF** is a second, separate gesture that can only ever *leave* secret mode - it
  does nothing when secret is already off, so it is a way out that cannot turn it on by
  mistake
- **Speed limit** - gestures stop working above **Disable Gestures above** in Setup. The
  default is 0.1 km/h, which means standstill only; raise it and you can change modes, the
  headlight or secret mode while riding. **Lock** and **power off** are the exceptions - they
  are never accepted with the wheel turning, whatever that is set to
- A gesture whose combination does not include a lever still needs that lever released to
  match, so let go of the throttle for those
- Turning the scooter on always works, regardless of mapping

### 🔒 Lock & alarm
- Motor braked when pushed, alarm with beeping and optional siren on gyro or wheel movement
- Configurable thresholds and volume, and an optional "Disable Secret when Locked"

### 🚀 Cruise control (experimental)
- Hold a steady speed with the throttle for the configured delay and the scooter keeps it
- **Cancels on any throttle or brake press** and your live lever takes over the same instant.
  It does not cancel on speed alone, so a bumpy road or traction control cannot drop it
- Arms only inside a configurable **min/max speed window** (default 5 - 100 km/h)
- The Setup switch is a **master switch**: with it off, cruise cannot be turned on from the
  Control tab, an app or a gesture

### 📱 Control tab
- Live speed dial with a power sub-dial that scales to the active mode's watt limit times
  the number of controllers on the bus, and a battery bar carrying charge in the middle
  with estimated range at whichever end is one solid colour
- **Four readouts** under the bar. Hold one to pick what it shows: voltage, battery or
  motor current, controller, motor or battery temperature, battery %, uptime or trip
  distance. Temperatures flash red above their warning thresholds
- A disabled function reads as off: with cruise or secret switched off in Setup, its button
  greys out and stops responding rather than sitting there coloured
- Buttons for power, lock/unlock, headlight, secret, cruise and mode selection

### 🔗 Third-party app support
**NineDash**, **m365 Tools** and the **official Segway Ninebot app** connect over the
dashboard's own BLE module, so no extra hardware or wiring is needed. Tested on a G30,
including pairing.

- **Live data** - speed, battery %, voltage, current, power, temperature, odometer, trip
  distance and time, average speed, range, error and alarm codes
- **Controls** - lock/unlock, headlight, rear light, cruise, speed mode, secret, buzzer and
  "find my scooter". Apps have no headlight, secret or speed-mode control of their own, so
  three of theirs are borrowed: **KERS** selects the speed mode, **Walk mode** toggles
  secret, **Direct power control** toggles the headlight
- **Battery screen** is populated on Xiaomi - the BMS is emulated
- **Shutdown from the app** switches the dashboard off, refused above walking pace
- **App pairing PIN** - set your own 6-digit code in Setup. The package answers it, but
  none of the three apps above ever asks: they treat a headlight state change as the
  pairing confirmation instead, so the code is there for an app that wants it
- Can be turned off in **Setup -> Miscellaneous** for the sharpest possible throttle response

### 💡 Lights
- **Auto headlight** at power on
- **Rear / brake light** on the servo pin: dim tail light following the headlight (or always
  on), full or blinking brake light while braking. **Tail Light Brightness** sets how dim,
  in ten steps from 10 to 100%
- **Headlight and tail light off when locked**, each on its own switch, restored on unlock

### 🖥️ Dashboard
- **Idle display** - while standing still the dash speed readout shows battery %, pack
  voltage, controller or motor temperature instead. Set separately for normal and secret modes
- **BMS battery %** - a reporting VESC BMS supplies the percentage, and its pack
  temperature raises the dash warning outside a hot and a cold limit you set
- **Use Imperial Units** - dash speed, every speed setting and every temperature switch
  between km/h with °C and mph with °F
- **Temperature warning icon** with configurable thresholds
- **Faults reach the dashboard** - the controller's own fault code goes into the dash's
  error field, so the display flashes it. The number is a **VESC** fault code shown by a
  dashboard that reads it against the scooter's own table, so read it as a VESC one
- **Ninebot Max G2** - the handlebar **horn** sounds the dash buzzer, and **holding the turn
  signal button** for three seconds toggles cruise control
- A long button press turns the dashboard off

### 💾 Backup
- **Export** in Setup puts every saved setting on the clipboard as a short block of
  text - paste it into a note, a file or a message to keep it
- **Import** takes that text back, fills in every field, and waits for you to press
  Save. The model is not part of a backup, since it belongs to the unit
- VESC Tool gives a package no way to write a file on the phone or the desktop, so a
  backup travels as text rather than as a download
- ⚠️ **Installing a new version returns every setting to its default**, so export
  before you update and import afterwards. The model is kept, and the light
  compensation calibration has to be run again

### 🎚️ Throttle & brake
- **Software ADC** per channel - take throttle from the dashboard and leave brake on a lever
  wired to the ADC pin, or the other way round
- **Light compensation** - the headlight sags throttle/brake voltage non-linearly, so this
  applies an affine correction (offset + gain) rather than a flat offset. A guided wizard in
  Setup measures it. The motor stays disengaged throughout, so **no stand is needed**
- **Motor start speed** (kick-start)

### 🔌 Dashboard power control
- **ADC1** or **ADC2** switches the dashboard's supply through a MOSFET: **3.3 V on the
  chosen pin while the scooter is on, 0 V when it is off**
- Because the pin stays low until the script runs, the dashboard no longer shows error 10
  while the VESC boots
- Off by default. The chosen pin is detached from the ADC app, so it stops working as a lever
  input - on ADC2 that costs the brake, on ADC1 the throttle, unless that lever comes from
  the dashboard. The UI warns in red when it does

### 🛡️ Robustness
- **Dash link watchdog** - if the dashboard goes quiet mid-ride the package stops driving the
  ADC override and drops cruise, so the controller's own command timeout releases throttle
  and brake. The window follows the measured frame rate, so connecting an app cannot trip it
- **CAN slaves are told to stop** with the master, rather than holding their last command
  until it times out
- **App traffic never delays the levers** - replies are composed in advance and carried
  inside the dash reply the controller was going to send anyway
- Hardened UART frame parsing and supervised reader threads
- Runs from flash; settings stored on the ESC with versioned automatic migrations

## 📋 Requirements

- **VESC firmware 7.00**, from https://vesc-project.com/
- **A VESC controller.** Not every unit works - if yours misbehaves, that is worth reporting
- **A supported dashboard** - Xiaomi M365 / 1S / Essential / PRO 2, or Ninebot G30 or Max G2

## 🔧 Setup

### 📦 Install

1. Connect to your VESC in VESC Tool and install this package
   (**VESC Packages -> Load Custom -> select the .vescpkg**, or from the package store once listed).
2. **Install the package on every VESC unit.** On dual-motor setups, switch to the second
   unit via **CAN forwarding** and install it there too - each unit runs its own copy.
3. Open the package UI (**Navigation Bar -> App UI**), go to the **Setup** tab and select
   the model **for each unit**:
   - the unit wired to the dashboard gets its dashboard model (**G30**, **M365/1S/PRO2**
     or **G2**),
   - every other unit gets **Slave**.
4. Press **Save** - the script restarts with the chosen model. The model is stored per unit.
5. Configure everything else in the **General**, **Modes** and **Setup** tabs and press **Save**.

**Updating:** just install the new package over the old one - your settings are kept and
migrated automatically. To go back to defaults, use the **Reset** button in the UI - that
takes the model back to **Slave** as well, so pick it again afterwards.

### ⚙️ Required VESC configuration

The package feeds the throttle and brake from the dashboard into the VESC's ADC app, so a
few controller settings must be set (in VESC Tool, not the package UI):

**On the dashboard unit (master):**

- **App Settings -> General -> App to Use = `ADC`**
- **App Settings -> ADC -> General -> Control Type = `Current No Reverse Brake ADC2`**
- **App Settings -> ADC -> General -> Multiple VESCs Over CAN = `True`** (dual-motor setups)
- **App Settings -> ADC -> General -> Negative Ramping Time = `0.00 s`** - the dashboard
  already sends the lever position ten to forty times a second, so a second ramp on top of
  it only delays what the rider asked for
- **App Settings -> ADC -> General -> Update Rate = `1000 Hz`** - the package overrides the
  ADC input as each dash frame arrives, and a slow update rate makes the app read a stale
  override between frames
- Keep **Software ADC** enabled in the package **Setup** tab (default) - the dashboard
  supplies throttle/brake over UART; the package overrides the ADC app inputs. Throttle
  and brake are switchable separately, so you can take one from the dashboard and leave
  the other on a lever wired to the ADC pin.
- For accurate battery % and range, set your pack under
  **Motor Settings -> Additional Info -> Battery**: type, cell count and Ah.

**On every other unit (slave):**

- **App Settings -> General -> App to Use = `No App`** - a running ADC app on the slave
  fights the master's commands and causes stuttering.

**Lever detection (throttle/brake "pressed"):**

- **App Settings -> ADC -> Mapping -> `ADC1 Start voltage` / `ADC2 Start voltage`** define
  where the levers start responding. The package reuses exactly these values to decide when
  a lever counts as pressed - for gestures, the brake light and cruise cancel - so there is
  no separate deadband to configure. Map your levers properly in VESC Tool and everything
  else follows.

**For cruise control (optional):**

- **App Settings -> ADC -> Buttons -> enable `Cruise Control`** (leave it *not* inverted).
  The package uses the VESC's built-in cruise button, so this must be on.

**For the rear / brake light (optional):**

- **App Settings -> General -> enable `Servo Output`**. The light is driven as PWM on the
  SERVO/PPM pin, and that pin stays dead until this is enabled - the package can look
  correctly configured and still produce no light without it.
- Make sure **App to Use** is not `PPM` (or `PPM and UART`), which would claim the same pin
  as an input. With `ADC` (as above) the pin is free to drive the light.

After changing controller settings, write the configuration to each unit and power-cycle.

### 🔌 Wiring

| Qty | Part |
|---|---|
| 1 | Capacitor 220 µF, 25 V, low ESR, 105 °C, electrolytic, THT, ±20% |
| 1 | Capacitor 1 µF, 50 V, X7R, ceramic, THT, ±10% |
| 1 | Resistor 1 kΩ, 0.25 W, THT |
| 1 | Clip-on ferrite, 5 mm inner diameter - *optional* |

ℹ️ **Both capacitors are optional** - the connection works without them. They are
there to stop **phantom button presses**, where the scooter reacts to presses
nobody made. The **220 µF** across **5V and GND** is a reservoir for current
spikes, and the **1 µF** across the **green button line and GND** keeps noise off
it. If you get phantom presses, fit them; if you never do, you can leave them out.

Nothing goes on the yellow UART line. Fit the capacitors as close to the dashboard
as the wiring allows. The electrolytic is polarised: its **marked leg is the minus
and goes to GND**, getting that backwards will destroy it. The ferrite clips over
the whole bundle anywhere along its length.

#### Rear / brake light (optional)

Driven from the **servo/PPM pin** through an N-channel MOSFET (PWM at 200 Hz - dim tail
light, full brightness brake light).
Wiring by [Zodiak1993](https://github.com/Zodiak1993/vesc%5Fm365%5Fdash).

Two things must both be set or the light stays dark:

1. **VESC Tool -> App Settings -> General -> `Servo Output` = enabled**
2. **Setup tab -> `Tail Light Output (Servo/PPM)`** - the master switch. With it off the servo/PPM
   pin is never touched, so it stays free for something else

> ⚠️ **Check what your VESC's 5V output can supply before wiring it this way.**
> The dashboard runs from that rail, and a rear/brake light or headlight draws
> from the same one. On some VESCs it is not enough for all of it. If yours is
> marginal, power the lights (and/or the dashboard) from a separate step-down
> converter off the main battery instead, sharing a common ground with the VESC.

**Which leg is which.** Hold the MOSFET with the printed face towards you and the
legs pointing down:

| Leg | | Connects to |
|---|---|---|
| 1 - left | Gate | servo output, plus the 10 kΩ down to GND |
| 2 - middle | Drain | the tail light's negative wire |
| 3 - right | Source | GND |

The metal tab is internally connected to leg 2 (Drain), so treat it as live and
don't let it touch anything.

#### Dashboard power control (optional)

Switches the step-down converter that feeds the dashboard, with a P-channel MOSFET
on the battery side driven from ADC1 or ADC2 - 3.3 V on that pin while the scooter
is on, 0 V when it is off. The optocoupler keeps the pack away from the VESC's
3.3 V pin, and the two sides share nothing at all - the step-down's ground goes
straight to the battery, both optocoupler pins sit on VESC GND.

Set **Setup tab -> `Dashboard Power Pin`** to whichever pin you wired, and leave
that channel's software ADC off.

| Part | | |
|---|---|---|
| Q1 | IRF9540N | P-channel, source to the battery, drain to the step-down |
| U1 | PC357 | optocoupler, isolates the 3.3 V pin from the pack |
| D2 | BZX79-C10 | clamps the gate to 10 V below the source |
| R1 | 10 kΩ | holds the gate at the source, so the default is off |
| R2 | 27 kΩ | gate pull-down through the optocoupler |
| R3 | 220 Ω | LED current from the 3.3 V pin |

> ⚠️ **These values are for a 15S pack.** R1 and R2 divide the pack voltage to set
> how hard the MOSFET is driven, so a different cell count needs different
> resistors - too low and the MOSFET only partly turns on and overheats.
>
> **Ceiling is 80 V, and the optocoupler sets it.** While the MOSFET is off its
> collector sits at the full pack voltage, which is the PC357's limit - so **above
> 18S the optocoupler has to change too**, not just the resistors. The IRF9540N
> itself is good to 100 V.

The MOSFET's tab is the Drain and sits at battery voltage - treat it as live.

## 🙏 Thanks

- **Izuna, AKA13 and Netzpfuscher** - the original VESC dashboard scripts this package
  builds on
- **[Zodiak1993](https://github.com/Zodiak1993/vesc%5Fm365%5Fdash)** - rear/brake light wiring
  and the BMS, overmodulation and cruise-control ideas
- **[Benjamin Vedder](https://github.com/vedderb)** - VESC, VESC Tool, LispBM and the
  CAN code-server library
- **[Koxx3](https://github.com/Koxx3/SmartESC%5FSTM32%5Fv2)** - reference work for Xiaomi ESCs
- The **scooterhacking.org** community for guides and testing

## 🔗 See Also

`https://github.com/Koxx3/SmartESC_STM32_v2` (VESC firmware for Xiaomi ESCs)
