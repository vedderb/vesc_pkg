# VESC X3 Bridge ESP

Bridges a Ninebot X3-series dashboard (G3/ZT3/GT3) to a VESC motor
controller, using stock VESC Express firmware plus a LispBM script instead
of custom firmware. Requires the companion **VESC X3 Bridge** PCB --
this package will refuse to install on any other board

Installing this package uploads `code_esp.lisp` (dashboard-facing status
emulation, lights, profile-switch relay, battery relay) to VESC Express,
plus its companion settings page -- appears as a new tab once installed
and connected.

## Settings page

A live status card at the top shows current speed, the active profile's
speed limit, motor temperature, voltage, current, and indicator/rear
light state, refreshed periodically from Express.

**Display Settings**
- **Disable profile switching** -- blocks the dashboard's ride-mode 
  selection from changing the VESC's speed limit.
- **Freeze Battery Percentage under 11%** -- floors the battery percentage 
  reported to the dashboard at 11%, bypassing whatever the dashboard 
  itself does at low battery.
- **Bypass Speed limit warning** -- when riding over the active profile's 
  speed limit, briefly flashes the dashboard's displayed speed down to 
  1 km/h so the dashboard's own built-in overspeed warning never 
  triggers. On by default; turn it off to let the dashboard behave 
  natively. Purely cosmetic either way, never touches actual VESC 
  speed/current limits.

**Light Control**
- **Underglow on park** -- turns on the underglow output while the 
  vehicle is parked and the rear light is in its steady "on" state.
- **Enable charge light** -- toggles whether the rear light shows the 
  charging-breathing indication. On by default.

**BMS Mode**
- **Use VESC BMS** (default) -- Express reports battery data itself.
- **Use Ninebot BMS/JBD2X3Bridge** -- Express stays quiet on the battery 
  frame, letting a real BMS own it.

**Reload from Express** / **Save to Express** buttons at the bottom sync 
the page against the connected board

## This is only half the bridge

This package and the **VESC X3 Bridge STM** package need each
other -- neither is useful installed alone. VESC X3 Bridge STM
goes on the VESC that owns throttle input, a different physical device
than VESC Express, so this package (which only targets Express) can't
install it. Multi-motor setups also need a slave-variant script on the
additional motor(s) -- see the
VESC X3 Bridge STM package's README.

## Change Log
1.0 Initial release
