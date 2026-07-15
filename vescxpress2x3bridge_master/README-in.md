# VESCXPRESS2X3Bridge VESC

VESC-side half of the VESCXPRESS2X3Bridge project, which bridges a
Ninebot X3-series dashboard (G3/ZT3/GT3) to a VESC motor controller.
Install this on the **VESC that owns throttle input** -- a different
physical device than VESC Express, which is covered by the separate
"VESCXPRESS2X3Bridge Express" package. Works on any VESC motor
controller, not just the companion PCB.

## What it does

- Listens to the dashboard's throttle/brake/mode CAN message directly and 
  drives the motor via ADC override -- no physical throttle wiring needed. 
- Handles cruise control and park-mode zeroing the same way the dashboard's own drive modes expect.
- Registers itself (CAN id, motor poles, wheel diameter, battery %, 
  voltage, motor temperature) with the VESCXPRESS2X3Bridge Express 
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

Additional motors need VESC's own CAN-follower feature (configured in
VESC Tool, not scripted) plus a separate slave-variant script that only
handles speed-limit sync (not included in this package).

If VESC Express's controller id isn't the default (2), edit
`express-can-id` at the top of `vesc-side-master.lisp` to match.

## This is only half the bridge

This package and the Express-side **VESCXPRESS2X3Bridge Express**
package need each other -- neither is useful installed alone. The
Express-side package still needs to be installed separately on VESC
Express for dashboard status emulation, lights, and the settings page.

PCB design files (open source): https://github.com/Finnn-glitch/VESCXPRESS2X3Bridge_PCB

## Change Log
1.0 Initial release
