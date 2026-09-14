# Wheelie Assist — by [3ShulMotors](https://3shulmotors.com)

A self-balancing wheelie limiter / assist for VESC-based light electric
vehicles (Sur-Ron / Talaria-class bikes and similar). Hold throttle, let the
front come up, and the controller settles the bike toward a target wheelie
angle instead of looping out.

**Version 1.0.0**

## Before you install — IMU calibration (required)

The assist trusts the IMU pitch angle directly, so set up the IMU first, with
the controller mounted in its final position:

1. In VESC Tool open **Welcome & Wizards → IMU Setup → Orientation**.
2. Run the orientation setup so that, with the bike upright and level, the
   **pitch reads about 0°** and **increases as the front wheel lifts**.
3. Confirm the live pitch matches the bike before arming.

If the sign ends up backwards you can also flip it with the **Invert pitch
sign** option in this app.

## How it works

The controller reads pitch and pitch-rate from the IMU and shapes the throttle
in the rear-wheel-up region:

- **Front down** — full, normal throttle. The assist stays out of the way.
- **Past the start angle** — throttle is faded out as the nose rises, with
  pitch-rate damping to take out the bounce.
- **At the ceiling angle** — a gentle reverse (pull-down) current eases the
  bike back toward the target instead of letting it flip.

## Tuning

You can adjust everything two ways:

- **In the app** — right here on this VESC Tool page. Move a slider, then press
  **Write & Save** to store it on the controller.
- **On the fly** — with a **3ShulMotors smart display**, which sets the same
  values over CAN while you ride.

**Parameters**

- **Throttle fade start** — angle where throttle starts fading out (deg)
- **Balance ceiling** — target / hard-cap angle; pull-down engages past this (deg)
- **Pitch-rate damping** — resists fast nose movement (anti-bounce)
- **Max pull-down current** — strength of the reverse current (0 to 1)
- **Gyro low-pass** — smoothing on the pitch-rate signal (0 to 1)
- **Invert pitch sign** — flip if the IMU is mounted the other way

Arm / disarm with the **Arm** toggle in this app or from the display — the
assist always boots disarmed.

The live readout shows pitch, pitch-rate, output and armed state. Before
riding, confirm the pitch reads **positive as the nose lifts**.

## Requirements

- An **IMU** (`get-imu-rpy` / `get-imu-gyro`).
- An **ADC throttle** on ADC1.
- **`l_min_erpm` set below 0** in the motor config — the pull-down needs reverse
  current, otherwise the bike can only be limited by cutting throttle.

## Display / CAN

A **3ShulMotors smart display** can read and set every parameter, **arm and
disarm** the assist, and show a live feed of pitch, armed state and output
current — all over CAN, so you can dial in the wheelie angle and arm it on the
fly without a laptop. Get the display at
[3shulmotors.com](https://3shulmotors.com).

A display is **optional**: once tuned and saved, the bike runs the assist on its
own with nothing connected.

## Safety

The assist boots **disarmed** every time and will not touch the motor until you
arm it — from the app's *Toggle Arm* button or the display. Normal throttle
works while disarmed.

This commands motor current directly. **Test on a stand first**, confirm the
pitch sign and arming behaviour, and start with a low *Max pull-down current*.
Riding behaviour is the user's responsibility.

## Disclaimer — no liability

This software is provided **"as is", without warranty of any kind**. It commands
motor current directly and can cause sudden or unexpected vehicle behaviour,
loss of control, crashes, property damage, injury or death. You install,
configure and use it **entirely at your own risk**.

**3ShulMotors accepts no liability whatsoever** for any loss, damage, injury or
death to any person, vehicle or property arising from the installation,
configuration or use of this package. By installing or using it you accept full
responsibility for the outcome and agree that 3ShulMotors and its contributors
are not liable for any damages of any kind.

## License

GPL-3.0, consistent with the VESC firmware and VESC Tool.
