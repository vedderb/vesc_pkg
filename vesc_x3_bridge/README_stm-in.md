# VESC X3 Bridge STM

VESC-side half of the VESC X3 Bridge project, which bridges a
Ninebot X3-series dashboard (G3/ZT3/GT3) to a VESC motor controller.
Install this on the **VESC that owns throttle input** -- a different
physical device than VESC Express, which is covered by the separate
"VESC X3 Bridge ESP" package. Works on any VESC motor
controller, not just the companion PCB.

## What it does

- Listens to the dashboard's throttle/brake/mode CAN message directly and 
  drives the motor via ADC override -- no physical throttle wiring needed. 
- Handles cruise control and park-mode zeroing the same way the dashboard's own drive modes expect.
- Registers itself (CAN id, motor poles, wheel diameter, battery %, 
  voltage, motor temperature) with the VESC X3 Bridge ESP 
  package, and applies the speed-limit profile Express relays back, 
  computed from this VESC's own motor configuration. 

## Required VESC Tool settings before use

Both of these are hard requirements, not optional -- without them the
script runs with no effect and no error:

1. **App Settings -> General -> App to Use: ADC**
2. **App Settings -> General -> ADC Control Type: "Current No Reverse
   Brake ADC2"**

No physical throttle needs to be wired to the ADC pins -- this script's
overrides replace the real ADC reading once the app is active.

## Multi-motor setups

Additional motors need VESC's own Multi ESC over CAN feature enabled here
on this master VESC (App Settings -> General -> Multi ESC over CAN,
configured in VESC Tool, not scripted) plus the separate **VESC X3
Bridge STM Slave** package installed on each additional motor's VESC,
which only handles speed-limit sync.

If VESC Express's controller id isn't the default (2), edit
`express-can-id` at the top of `code_stm.lisp` to match.

## This is only half the bridge

This package and the Express-side **VESC X3 Bridge ESP**
package need each other -- neither is useful installed alone. The
Express-side package still needs to be installed separately on VESC
Express for dashboard status emulation, lights, and the settings page.

## Change Log
1.0 Initial release
