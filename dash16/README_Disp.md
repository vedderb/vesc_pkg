# Dash16

VESC Labs Dash16 UI.

## Settings

The package page in VESC Tool exposes options that were previously compile-time constants: units for speed and temperature, the number of drive modes, and short and long press actions for both buttons.

Drive mode values live in `dash_esc`. The display sends the mode and the controller applies it.

Values are stored in eeprom and applied immediately. `config.lisp` still holds the defaults, written on a fresh install or whenever the settings version changes.

## Running without dash_esc

If no `dash_esc` frame arrives for three seconds the display falls back to reading standard CAN status frames directly. The Controller section can force either mode and shows which is live.

Speed, duty, voltage, input current and both temperatures still work, and a VESC BMS is read directly for charge and pack temperature. Watt hours, amp hours, odometer, range, efficiency, fault names, IMU pitch, average and peak current, cruise control, turn signals, high beam and kickstand do not. Trip becomes distance since the controller booted.

Drive modes need `dash_esc`. The mode still changes on screen and is broadcast, but nothing applies it.

## Building

    VESC_TOOL="/path/to/vesc_tool" ./build.sh

Builds from a comment-stripped copy, since the lisp partition stores source.

## Not yet tested

This package has never been run on hardware. The port follows Dash35B where the hardware allows, but the display is a different size with a different button count, so treat the drawing and the button behaviour as unverified.

## Changelog

**Version 2.2 (2026-09-10)**
* Settings are read from eeprom on every boot again. They were only read on the first boot after installing, so a setting changed later was stored but not applied until something else was changed

**Version 2.1**

* Settings page in the package UI: units, drive mode count, and short and long press actions for both buttons
* Unit selection converts speed, distance, efficiency and max speed. `settings-units-speeds` was set but no view read it, so units did nothing
* Reads standard CAN status frames directly when `dash_esc` is absent, detected after three seconds of silence
* Drive mode values live in `dash_esc` rather than here, so there is one place to set them
* Removed config entries that had no consumers
* `build.sh` builds from a comment-stripped copy

**Version 1.0**

* Initial Release

