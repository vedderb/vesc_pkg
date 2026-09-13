# Dash ESC

CAN-server for the VESC Labs [Dash16](https://www.vesclabs.com/product/vesc-dash-16l/) and [Dash35B](https://www.vesclabs.com/product/vesc-dash-35b/) displays. This package should be installed on the ESC on the CAN-bus that provides data for the Dash. This package also implements the drive modes, cruise control and maps the analog lever to ADC2 on the ADC app.

**Note**  
Version 2.4 goes with the 2.4 Dash packages.

**Note**  
To use cruise control it needs to be enabled in APP ADC.

**Note**  
To use reverse APP ADC needs to use the mode **Current Reverse Button** or **Current Reverse ADC2 Brake Button**. On the Dash16 **Current Reverse ADC2 Brake Button** is recommended as it allows using the lever on the dash as a brake while enabling the reverse mode.

## Logging

A display button can start and stop logging, using the settings already on this page. The display shows Log Started or Log Stopped when the controller reports the change, so it says what actually happened rather than what the button asked for.

The log is closed when a display reports that power is about to go, as well as on the controller's own shutdown, so the last records are not lost when the bike is switched off at the display.

## Servicing

Drive modes work by scaling the motor current, so anything the controller measures with current is measured wrong while a mode is applied. Motor detection is the usual case: in neutral the scale is zero and the motor will not turn at all, and in a drive mode it completes but stores values that were measured at part current.

Tick **Suspend drive profiles** on this page before detecting a motor or writing configuration. The configured limits become the live ones, and the displays show SERVICE while it is set. It clears itself at the next power cycle.

If the stored motor parameters cannot describe a real motor, the profile is suspended without being asked and the displays show MOTOR CONFIG BAD. That is what lets the motor be detected again. The profile goes back when a drive mode is selected, so recovering is just: detect, then pick a mode.

**Capture these limits as the baseline** records the limits to restore whenever a display goes away or the profile is suspended. Press it once the controller is configured the way you want it.

## Changelog

**Version 2.4 (2026-09-13)**
* Drive profile is written when it changes rather than ten times a second, so it no longer fights anything else writing configuration
* Configured limits are restored when no display is present, so a motor can be detected without a power cycle first
* Drive profile is suspended automatically while the stored motor parameters cannot describe a real motor, and can be suspended from this page for servicing
* Drive mode is held here and reported to the displays, so two displays can no longer disagree about it
* Configuration is not stored on shutdown unless the real limits are known
* Logging can be started and stopped from a display button

**Version 2.1 (2026-09-04)**
* Trap proc-sid

**Version 1.4 (2026-08-01)**
* Use native lib for setting profile
* Detach button in all modes

**Version 1.3 (2026-07-18)**
* Better multi-ESC support

**Version 1.2 (2026-07-14)**
* New app UI
* Configurable mode settings in UI

**Version 1.1 (2026-07-14)**
* Cruise control support
* Reverse support

**Version 1.0 (2026-07-03)**

* Initial Release
