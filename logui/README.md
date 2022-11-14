# LogUI

This package can be used for logging data to CAN-connected log devices such as the VESC Express. When installed it provides a QML-page in VESC Tool where logging can be configured, started and stopped. There is also a lisp-script that handles the logging.

After a log is started it can be stopped with the stop-button or when a shutdown even it detected (from e.g. a power button). The log will also be stopped if the input voltage drops below 9V. The automatic stop is done in order to prevent data corruption on the SD-card when the power goes down.

## Data Selection

The following data can be selected for logging:

* **GNSS Position**
	- This relies on a GNSS receiver being connected to the logger. The log will not start until a valid position is available. That means if the log is started indoors or without a GNSS-receiver connected it will never start.
* **Local Values**
    - Such as input voltage, currents, ah and wh counters, speed , temperatures etc.
* **CAN Values**
    - Selecting this option will monitor the CAN-bus when the log is started and add fields for all devices that are detected then. Then when the log is running it will keep updating the fields for those devices. If no CAN-devices are seen when the log is started they will also not be added to the log. For motor controllers with the VESC firmware to show up, CAN status messages must be activated in the App Settings.
* **BMS Values**
	- If BMS-values are selected, they will be added to the log if a BMS is detected at the time the log is started. Otherwise the log will run without BMS values.

### Logger CAN ID

The ID of the logger on the CAN-bus. Setting id to -1 will send log data to the log analysis page in the desktop version of VESC Tool.

### Log Rate

Rate at which data is logged in Hz.

## Button Functions

The UI has three buttons with the following functions:

### Start

Start the log now with the settings above.

### Stop

Stop the ongoing log if any.

### Save Config

Save the log settings. If "Start logging at boot" is checked a log will be started automatically every boot with the settings above.