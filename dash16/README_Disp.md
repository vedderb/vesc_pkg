# Dash16

VESC Labs Dash16 UI.

**Note**  
Version 2.4 goes with Dash ESC 2.4. The drive mode, the status banners and the logging button all need it.

**Note**  
Button action numbers changed in 2.4 so that they match the other dashes. Existing button settings are converted when the package is installed, so buttons keep doing what they did.

## Settings

Settings are on the package page and stored in eeprom, applied without a reinstall. The Editing selector at the top picks one section at a time.

**Live page**  
Four readings, two by two, each from one of 18 sources.

**Display**  
Boot splash, status strip icons and the battery bar colour. With the whole top strip switched off the VESC logo and the gear selector move up into it.

**Pages**  
Which pages the page button cycles through, and how many drive modes.

**Hardware**  
Units, backlight brightness, the controller mode, and lever calibration.

**Buttons**  
Short and long press actions for both buttons. Reverse is only taken below 3 km/h, the way a car will not select R while rolling. One of the actions starts and stops logging on the controller.

config.lisp still holds the defaults, written on a fresh install or when the settings version changes.

Drive mode values live in dash_esc. The display sends the mode and the controller applies it.

## The lever

The lever is read on the display and sent to the controller as ADC2, so it needs no wiring of its own. The controller must use an ADC control type that reads ADC2, and Current Reverse ADC2 Brake Button is recommended. The Hardware section shows the live voltage and the resulting position so the range can be set against the actual hardware.

## Running without dash_esc

If no dash_esc frame arrives for three seconds the display reads the standard CAN status frames directly. The Controller section can force either mode and shows which is live.

Speed, duty, voltage, input current and both temperatures still work, and a VESC BMS is read for charge and pack temperature. Watt hours, amp hours, odometer, range, efficiency, fault names, pitch, cruise, turn signals, high beam and kickstand are not in any status frame. Trip becomes distance since the controller booted.

Drive modes need dash_esc. The mode still changes on screen and is broadcast, but nothing applies it.

## Status banners

The display shows a banner across the middle when the controller reports something that makes what is on the rest of the screen misleading.

**SERVICE** means drive profiles are suspended on the controller. The mode shown means nothing while that is set, and neutral is not holding the throttle shut.

**MOTOR CONFIG BAD** means the controller's stored motor parameters cannot describe a real motor, so it will not run at all. The controller suspends its drive profile by itself in that state so the motor can be detected again.

## Changelog

**Version 2.4 (2026-09-13)**
* Logo shown at startup, can be turned off under Display
* Drive mode follows the controller, so two displays always agree on it
* Button action to start and stop logging on the controller
* Banner while the controller has drive profiles suspended, or while its motor configuration cannot describe a real motor
* Button action numbers now match the other dashes, existing settings are converted on install

**Version 2.3 (2026-09-10)**
* Load settings correctly on boot
* Fix bug where some values are shown as 0

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
