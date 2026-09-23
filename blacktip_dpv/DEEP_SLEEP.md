# Deep Sleep — MK5 only

This optional feature is **disabled by default**. It requires all of the following:

- a Flipsky Mini V6 MK5 controller (detected VESC hardware name 60&#95;MK5);
- stable VESC firmware 7.00, or a 7.00 beta build numbered 2 or newer;
- the phantom-button hardware modification below; and
- the **Enable five-click deep shutdown (MK5 only)** checkbox in Battery Configuration.

## Video

[Watch the Deep Sleep setup and operation video](https://www.youtube.com/watch?v=jHv2DCvL-u0).

## Operation

Five rapid trigger clicks while the motor is off show the power-off symbol and play four descending tones (high, medium-high, medium-low and low) before switching the controller into true hardware-off mode. The tones use the configured beep volume, so the visual confirmation remains available when sound is disabled. The command is ignored while the motor is commanded to run. After shutdown, spin the propeller to wake the controller. The modified controller also starts in the off state after fresh battery insertion and must be woken by spinning the propeller.

The existing 'go to sleep after 5 hours of inactivity' setting (`OFF&#95;AFTER&#95;5H`) setting remains the fallback when manual shutdown is forgotten. On one measured example unit, hardware-off current was approximately **18–20 µA**. The modification is reversible: remove the batteries, remove the jumper, and insulate/reassemble the connector as it was originally.

## Phantom-button jumper modification

1. Remove both batteries before opening or touching the scooter.
2. Open the motor assembly using the [existing disassembly instructions](./README.md#installation-steps).
3. Locate the MK5 three-wire power-button connector near the bottom of the ESC.
4. Identify its cavities by wire colour, not by left/right position, because connector orientation can be reversed:
    - **BLACK:** ground
    - **RED:** power-button LED connection
    - **YELLOW:** shutdown-button sense
5. Insert a short, insulated and mechanically secure jumper between the connector cavities attached to **BLACK** and **YELLOW**.
6. Leave **RED** completely unconnected.
7. Ensure no bare conductor can contact the red terminal, controller, plate or enclosure.
8. With the jumper inserted, fit heat-shrink tubing around the header/connector to insulate and retain it.
9. Secure the jumper so vibration cannot loosen it or allow it to rattle.
10. Reassemble the unit before installing batteries.

![Phantom button jumper between the black and yellow wires](https://raw.githubusercontent.com/vedderb/vesc_pkg/main/blacktip_dpv/assets/phantom_button_jumper.png)

> **Warning:** Hardware modifications are undertaken at the owner's risk. Complete and validate the dry bench test before relying on the DPV, and complete additional dry testing before any in-water test.

## Required dry bench-test checklist

1. Upgrade to stable firmware 7.00 (or 7.00 BETA 2 or newer) and confirm the version on the package **Home** tab.
2. Install the jumper with batteries removed.
3. Insert batteries: the controller should remain in hardware-off state, and the motor must not start.
4. Spin the propeller by hand: the controller should wake normally.
5. Read these hardware-modification instructions, then enable the five-click checkbox.
6. Wake the scooter, leave the motor stopped and perform five rapid clicks: the power-off symbol and descending tones should play before the controller switches off and remains off.
7. Confirm five clicks do nothing when the checkbox is disabled.
8. Confirm the shutdown command is ignored while forward or reverse operation is active.
9. Complete additional dry tests before any in-water test.

## Optional additional testing

- Temporarily select OFF&#95;AFTER&#95;1M, verify that an idle controller shuts down and remains off, and restore OFF&#95;AFTER&#95;5H immediately afterwards.
- Where suitable test equipment is available, measure off-state current.
