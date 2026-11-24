# Wheel-E - VESC Package
Wheel-E is a VESC Package for electric mini-bikes with a wheelie mode. The package is a fork of [ReFloat](https://github.com/lukash/refloat) used in self-balancing skateboards.

## Functionality summary
* A "THROTTLE" state used when riding on two wheels. Using ADC1 for throttle and ADC2 for brake.
* A "WHEELIE" state which is the same as "RUNNING" state on onewheels, but with a different angle setpoint.
    * This mode is triggered when the pitch value gets close to the angle setpoint, or the optional button is pressed.
    * It exits back to "THROTTLE" when pressing the brake, or or the optional button is pressed or released
* The IU displays a mini-bike and throttle/brake gauge instead of footpads.
* Configurable parameters for the angle setpoint, throttle/brake current, and state transition thresholds.

## Hardware requirements
* VESC with IMU and ADC inputs
* Motor with hall sensors
* Analog trottle
* Analog or digital brake
* _Optional: Button between TX and GND which can be used to enter and/or exit wheelie mode._
* _Optional: Button between RX and GND which can be used for cruise control._

## Configuration
* Configure as a onewheel (Use tutorials for onewheels, not bikes. IMU and Motor calibration is required before installing/enabling Wheel-E!)
* Put the bike on a stable surfce, wheel off the groung before installing/enabling Wheel-E.
* Configure parameters under Wheel-E Cfg -> Bike.
* Disable the foot sensors by setting ADC Switch voltage to 0v (Wheel-E Cfg -> Spec -> ADC1&2 Switch voltage: `0.0v`)
* Make sure that the built in ADC app is not enabled. (App Cfg -> General -> App to Use: `No App` or `UART`)
* To be safe, start with low motor current setting! (Motor Cfg -> General -> Current -> Motor Current Max)

## Disclaimer
**Use at your own risk!** Electric vehicles are inherently dangerous, authors of this package shall not be liable for any damage or harm caused by errors in the software. Not endorsed by the VESC project.

## Credits
Wheel-E package author: Henrik Buestad

Refloat package author: Lukáš Hrázký

Original Float package authors: Mitch Lustig, Dado Mista, Nico Aleman

## Downloads and Changelogs
[https://github.com/buestad/wheel-e/releases](https://github.com/buestad/wheel-e/releases)
