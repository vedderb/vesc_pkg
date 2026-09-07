# Dash16

VESC Labs Dash16 UI.

**Note**  
Version 2.1 is a large change and adds a lot. It has been run on the bench but not ridden, so expect some rough edges.

## Settings

Settings are on the package page and stored in eeprom, applied without a reinstall. The Editing selector at the top picks one section at a time.

**Live page**  
Four readings, two by two, each from one of 18 sources.

**Display**  
Status strip icons and the battery bar colour. With the whole top strip switched off the VESC logo and the gear selector move up into it.

**Pages**  
Which pages the page button cycles through, and how many drive modes.

**Hardware**  
Units, backlight brightness, the controller mode, and lever calibration.

**Buttons**  
Short and long press actions for both buttons. Reverse is only taken below 3 km/h, the way a car will not select R while rolling.

config.lisp still holds the defaults, written on a fresh install or when the settings version changes.

Drive mode values live in dash_esc. The display sends the mode and the controller applies it.

## The lever

The lever is read on the display and sent to the controller as ADC2, so it needs no wiring of its own. The controller must use an ADC control type that reads ADC2, and Current Reverse ADC2 Brake Button is recommended. The Hardware section shows the live voltage and the resulting position so the range can be set against the actual hardware.

## Running without dash_esc

If no dash_esc frame arrives for three seconds the display reads the standard CAN status frames directly. The Controller section can force either mode and shows which is live.

Speed, duty, voltage, input current and both temperatures still work, and a VESC BMS is read for charge and pack temperature. Watt hours, amp hours, odometer, range, efficiency, fault names, pitch, cruise, turn signals, high beam and kickstand are not in any status frame. Trip becomes distance since the controller booted.

Drive modes need dash_esc. The mode still changes on screen and is broadcast, but nothing applies it.

## Changelog

**Version 2.1 (2026-09-04)**
* Settings page, stored in eeprom and applied without a reinstall
* Live page with four configurable readings
* Unit selection now converts speed, distance, efficiency and temperature
* Configurable status strip icons, and the logo and gear selector move up when the strip is empty
* Colour the battery bar by charge
* Backlight brightness
* Lever calibration with a live readout
* Read standard CAN status frames when dash_esc is absent
* Configurable button actions, including selecting reverse from any gear at a stop

**Version 1.0 (2026-07-03)**

* Initial Release
