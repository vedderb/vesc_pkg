# legacy_dc_dpv VESC Package

This add-on to Vedder's VESC motor control software is designed for older scuba Dive Propulsion Vehicles that have brushed DC motors and reed switch triggers. Examples are older Gavin, Silent Submerge or Hollis H-160 DPVs.

It incorporates the following features

- **Double-click start:** means no more accidental starts.
- **Speed Control:** Instead of a single speed, this package allows for up to 8 user-defined speeds. Click twice to speed up and once to speed down.
- **Soft Start:** When starting the DPV, speed ramps up slowly so there is less impact on your crotch strap.
- **Start Speed:** Select which speed you want to start scooting at. 
- **Jump Speed:** Select a different speed (like full speed) to start at if you click three times.
- **Variable Battery Voltage:** You can replace your DPVs battery with a higher voltage one. This controller can reduce the voltage.

## Hardware Requirements

- A legacy DPV like a Silent Submerge, Gavin, Hollis H-160 or a similar type that has a DC motor and reed switch trigger.
- A VESC compatible motor controller with suitable voltage and amperage capability. For example a Flipsky Mini6.7 Pro.
- A computer or a phone or laptop with a USB A adapter to program the hardware.
- Something to use as an enclosure for the controller board. This could be as simple as a plastic box 5cm x 8cm x 3m inside dimensions with zip ties to connect it to something inside the DPV.

## Skills Required

- You will need to strip and connect wires which may require soldering or crimping connectors.
- The ability to fashion a suitable enclosure for the hardware. This may require cutting, drilling or gluing.
- Basic computer skills.
- Basic electrical understanding.

## Tools Required

- Wire cutters, possibly crimpers, and/or a soldering iron.
- An electrical multi-meter would be handy to verify the voltages being sent to the DPV motor before connecting it. It is also handy to check battery voltage and wire continuity.
- Basic tools, like screwdrivers, hex wrenches, wrench or nut driver... what ever is needed to disconnect and reconnect wires in your DPV.

## Software Required

- VESC-Tool is required to configure the VESC controller and load the **legacy_dc_dpv** package. This is free software available from (https://vesc-project.com/vesc_tool)
- **legacy_dc_dpv** VESC Package (this one.)

## Overview

We have a few steps:

1. Create physical connections to the DPV components and the VESC controller.
2. Connect USB cable to the VESC Controller.
3. Update firmware.
4. Install **legacy_dc_dpv** package.
5. Change VESC controller settings.
6. Test.

## Physical connection

The conversion process involves disconnecting the original control hardware. For a Silent Submerge or Gavin that hardware is an electric relay located on top of the motor under a clear shield. For a H-160, it's a motor control PCB also located on top of the motor, under a T-brace and clear shield. These need to be removed to expose the motor terminals. Locate the reed switch wires and prepare them to connect to the new controller.

Connect the two outside motor wires from the VESC controller to the DPV motor terminals. Cover the middle VESC controller motor wire with a cap or tape to ensure it doesn't short out.

Connect the reed switch wires to the VESC controller, one wire goes to the pin labelled GND and the other goes to the pin labelled ADC1.

Connect the battery to the battery wires on the VESC controller, with positive going to the red wire and negative going to the black wire. It's best to use a connector, like a Anderson Powerpole or XT connector, so you can disconnect it as needed.

Once the VESC controller is connected to the motor, battery, and reed switch you need to program it. To program it connect a USB cable from your PC to the VESC controller and run **vesc-tool* on your PC.

![VESC Controller Wiring](assets/vesc_controller_wiring.png)


## Connecting to the VESC Controller

Connecting should be easy. Connect the USB cable from the PC to the VESC controller and connect the VESC controller to the DPV battery.

In **vesc-tool** select **Connection** from the menu on the left.
The port should be auto-detected and already displayed. If not see if it is listed in the drop-down.
Click **Autoconnect** at the bottom.


## Update the firmware

We should use this time to ensure the most recent VESC firmware is installed on the VESC hardware.

To update VESC firmware:

In **vesc-tool** select **Firmware** from the menu on the left.
Click the **Download Latest** near the top-right of the window. This will take a minute or two.
Choose a suitable hardware option from the **Hardware Version** list.
Then choose the firmware listed on the right (probably **VESC_default.bin**),
At the lower right of the window, locate the down-arrow symbol button ![Update firmware button](assets/update_firmware_icon.png). If you hover your mouse over it will show *Update firmware on the connected VESC*. Click this button.
Allow the process to complete, about a minute or two, and ensure the VESC controller stays powered the entire time. Unplugging it could brick the device.
After a couple of minutes, attempt to re-connect.

## Install the legacy_dc_dpv package

We must now install the **legacy_dc_dpv*  package on the VESC controller.

To install it:

Ensure you are connected to the VESC controller as described in previous sections,
Select **VESC Packages** from the menu on the left,
Select the **Load Custom** tab near the top of the window,
Click the file folder icon ![File Folder Icon](assets/choose_file_icon.png) to the right of the **Load Package** field and use the file dialog to locate the downloaded package file.
Click the **Install** icon ![Install Icon](assets/install_package_icon.png) beside the file folder icon.

This will only take a few seconds to complete.

# Configure VESC Settings

## Motor Configuration

### Motor Settings Menu

#### General Sub-Menu

- <u>General Tab</u>
  - <b>Motor Type</b>: *DC*
- <u>Current Tab</u>
  - <b>Motor Current Max</b>: 30 A (Set to something suitable to your motor/fuse)
- <u>Voltage Tab</u>
  - <b>Battery Voltage Cutoff Start</b>: Calculate this based on your battery chemistry and number of cells
  - <b>Battery Voltage Cutoff End</b>: Calculate this based on your battery chemistry and number of cells. This table may help

      | Battery Chemistry  | Voltage Cutoff Start  | Voltage Cutoff End  |
      | :--- | ---: | ---: |
      | Sealed Lead Acid (24V)  |  11.8 |  11.5 |
      | Lithium-Ion (25.6V)  |  23.8 |  21.7 |
      | Lithium-Iron (25.6V)  |  20 |  19.2 |

- <u>Temperature Tab</u>
  - <b>Motor Temperature Sensor Type</b>: *Disabled*
- <u>BMS Tab</u>
  - <b>BMS Type</b>: *None*
- <u>Advanced Tab</u>
  - <b>Maximum Duty Cycle</b>: *100%*

#### Additional Info Sub-Menu

- <u>Setup Tab</u>
  - <b>Battery Type</b>: Set to match the chemistry of your battery
  - <b>Battery Cells Series</b>: Set this to match your battery (Lead Acid would be 12 cells for 24V, Li-ion would be 7 cells for 25.55V, Li-Iron would be 8 cells for 25.6V)
  - <b>Battery Capacity</b>: Set to the rated capacity of your battery
  - <b>Motor No Load Current</b>: Run your DPV in air on high speed, watch the gauge in vesc-tool and set this to twice that amount

### App Settings Menu

#### General Sub-Menu

- <u>General Tab</u>
  - <b>App to Use</b>: *No App*

Now we need to save these settings to the VESC controller, to do that:

Locate the icon at the far right of the window that has a down-arrow and an 'M' ![Write Motor Config Icon](assets/write_motor_config_icon.png). If you hover the mouse over this it will say **Write Motor Configuration**, click this icon.
Locate the icon at the far right of the window that has a down-arrow and an 'A' ![Write App Icon](assets/write_app_config_icon.png). If you hover the mouse over this it will say **Write app Configuration**=, click this icon.


## Testing

We should testing the final configuration. If you prefer you can connect a voltmeter to the VESC controller motor leads instead of the actual motor. Reading the voltages before connecting a motor can confirm both the polarity and that the voltages are suitable for the motor. This is most important if you have a battery voltage greater than the motor's rating.

1. Pull the trigger twice quickly. Check that the propeller is spinning in the correct direction.
2. While running, click on the trigger twice to test speed up.
3. Whlie running, click on the trigger once to test speed down.
4. Release the trigger, the propeller will stop. 

