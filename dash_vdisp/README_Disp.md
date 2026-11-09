# Dash VDisp

Dash UI for the older Trampa display, the 320x240 panel with four buttons that the **VDisp** package is written for.

This is a separate package from VDisp and does not replace it. Both are for the same display, so install one or the other. VDisp keeps its own UI and can carry on as it is; this one gives that hardware the same layout and settings as Dash35B and Dash16, re-cut for the smaller panel and for the display's ST7789 wiring and GPIO backlight.

**Note**  
Version 2.4 goes with Dash ESC 2.4. The drive mode, the status banners and the logging button all need it.

**Note**  
The layout has been re-cut for this panel and checked on the bench, but has had little time on a vehicle, so expect rough edges.

## Settings

Settings are on the package page and stored in eeprom, applied without a reinstall. The Editing selector at the top picks one section at a time.

**Live page**  
Four readings, two by two, each from one of 18 sources, with its own colour or a green to red ramp across a range.

**Display**  
Accent and text colour, boot splash, status strip icons and the battery bar colour.

**Pages**  
Which pages button 0 cycles through, and how many drive modes.

**Hardware**  
Units, warning thresholds, backlight and the controller mode. The backlight is driven from a GPIO on this display, so it is on or off with no brightness control.

**Buttons**  
Short and long press actions for all four buttons. Short presses are overridden while the on-display settings page is open so it can always be navigated. One of the actions starts and stops logging on the controller.

config.lisp still holds the defaults, written on a fresh install or when the settings version changes.

Drive mode values live in dash_esc. The controller holds the mode and reports it, so every display connected to it shows the same one.

## Running without dash_esc

If no dash_esc frame arrives for three seconds the display reads the standard CAN status frames directly. Speed, duty, voltage, input current and both temperatures still work, and a VESC BMS is read for charge and the cell page. Watt hours, amp hours, odometer, range, efficiency, fault names, pitch, cruise, turn signals, high beam and kickstand are not in any status frame. Trip becomes distance since the controller booted.

Drive modes need dash_esc.

## Status banners

The display shows a banner across the middle when the controller reports something that makes what is on the rest of the screen misleading.

**SERVICE** means drive profiles are suspended on the controller. The mode shown means nothing while that is set, and neutral is not holding the throttle shut.

**MOTOR CONFIG BAD** means the controller's stored motor parameters cannot describe a real motor, so it will not run at all. The controller suspends its drive profile by itself in that state so the motor can be detected again.

## Changelog

**Version 2.4 (2026-09-13)**

* Initial release
* Dash35B UI re-cut for the 320x240 panel: status strip, battery bar, speed dial and pages
* Boot animation from the VDisp package, kept as it was
* Backlight is on or off, matching the GPIO this display uses, so there is no brightness setting
* Long press on the power button sleeps the display
