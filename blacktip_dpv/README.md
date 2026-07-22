# Improved Software for Dive Xtras Scooters

![Blacktip DPV Logo](https://raw.githubusercontent.com/vedderb/vesc_pkg/main/blacktip_dpv/assets/shark_with_laser.png)

**Version:** 1.4.1

## License

This software is released under the GPL-3.0 License. See the [LICENSE](https://github.com/vedderb/vesc_pkg/blob/main/LICENSE) file for details.

## About

This is a comprehensive, feature-rich package for Dive Xtras scooters (Blacktip and CudaX) running VESC motor controllers.

This package gives your DPV advanced features like Smart Cruise control, enhanced safety features, and extensive customization options.

## Supported Hardware

**Dive Xtras Blacktip:**

- first generation (Flipsky 4.10 based)
- second generation (Flipsky 6.0 based)
- third generation (Flipsky 6.0 MK5 based, with Bluetooth)

**Dive Xtras CudaX:**

- first generation (Flipsky 6.0 based)
- second generation (Flipsky 6.0 MK5 based, with Bluetooth)

**Scroll down for [installation instructions](#installation).**

## Instructions

Some videos showing the basic commands to control Smart Cruise while diving:

- [basic commands](https://youtu.be/oFRCwuKf2qQ)
- [manually enabling and disabling Smart Cruise](https://youtu.be/riwqB_mttLM)

---

## What's New in Version 1.4.1

Bugfix release:

- **Fix: Stuck display in 'off' state** — After the scooter shuts off the display, a transient I2C fault could silently drop the display-off command, leaving the last frame latched on the panel. Fixed by clearing the framebuffer first (so even a partially-delivered write leaves the panel blank) and by retrying the display-off command so that a single dropped transaction cannot keep the display lit indefinitely.

## What's New in Version 1.4.0

New feature release:

- **Battery imbalance detection** — The scooter now monitors the midpoint balance wire and warns when one of the two battery packs is significantly more depleted than the other. A flashing low-battery icon for slot 1 or slot 2 appears on the display, identifying which pack needs attention so a depleting cell cannot go unnoticed mid-dive. Enabled by default; threshold and balance-wire ADC multiplier are configurable from the Battery Settings dialog. See the [Battery Imbalance Detection](#battery-imbalance-detection) section below for full details.
- **Battery state-of-charge correction** — When imbalance detection is active, the displayed battery percentage and capacity beeps reflect the weaker pack rather than the pack average, so the SOC indicator stays honest as the packs diverge.
- **Battery display fixes** — Minor cosmetic fixes to the battery indicator frames so they render consistently across all display rotations.

## What's New in Version 1.3.1

Compatibility fix release for VESC firmware 7.00:

- **Fix: Cold-boot dark display** — The display stayed completely dark after power-cycling the scooter. Root cause: VESC firmware 7.00 has a bug where the first I2C message sent after the bus is initialised on a cold boot is silently dropped. The HT16K33 display controller never received its oscillator-enable command and stayed dormant. Fixed by sending the oscillator-enable command twice at startup; the first write is absorbed by the firmware bug, the second reaches the controller.
- **Fix: Package crash on second and subsequent boots** — VESC 7.00 re-evaluates package source on every boot but persists the flash heap from the previous session. The previous `move-to-flash` approach conflicted with this and caused an abort before any threads were spawned, leaving the display dark and the motor unresponsive. Switched to the `@const-start` / `@const-end` block syntax, which is the correct mechanism for VESC 7.00 and later.

## What's New in Version 1.3.0

- Updates to work with the latest VESC firmware (7.00).

## What's New in Version 1.2.1

- Patch fix for startup sound/battery beep overlap: When the battery is not full, the battery status beeps now wait until the startup tune has finished playing, so the two sounds no longer overlap
- Fix for a bug in the Battery Settings dialog, preventing settings from being updated when saving

## What's New in Version 1.2.0

New features and critical bug fix:

- **Startup Sound**: Added a distinctive musical theme that plays on power-up. When battery is full (>75%, 3 bars), only the startup sound plays; otherwise it's followed by the battery level beeps
- **Critical Smart Cruise Fix**: Fixed a bug where the motor could stop unexpectedly while in Smart Cruise mode with the timer bar still counting down. This occurred when tapping the trigger to reset the timer, due to a missing watchdog reset in the click-counting state

## Features

### Smart Cruise Control

The headline feature of this package—Smart Cruise allows hands-free operation with configurable timeout and visual feedback.

**Enabling Smart Cruise:**

- **Triple click while running forward** toggles Smart Cruise on/off
- When active, display shows **"C"** to confirm engagement
- Optionally enable **auto-engage** mode to activate Smart Cruise automatically after maintaining the same speed for a configurable duration

**Smart Cruise Timer Bar:**

- Visual countdown indicator using 8 LEDs at the bottom of the display
- LEDs turn off left-to-right as time counts down, showing remaining time at a glance
- When nearing timeout, display changes to **"C?"**, the scooter slows down and plays a distinctive warning beep

**Speed Adjustments During Smart Cruise:**

- **Long hold (>0.5s), release, then tap**: Speed down
- **Long hold (>0.5s), release, then double-tap**: Speed up
- **Short tap (no hold)**: Reset timer only
- **Triple tap**: Disable Smart Cruise

**Smart Cruise Timeout:**

- Configurable timeout period (default 60 seconds, adjustable via app)
- Warning mode triggers at timeout showing "C?" with slowdown to 80% speed
- Additional 5-second grace period to re-engage with any trigger action
- Completely disables if no action taken after grace period

### Triple Click Jump Speed

- **Triple click when stopped** starts the scooter at your preset jump speed
- Default is speed 6 (overdrive), fully customizable via app
- Perfect for quickly getting to your preferred cruising speed

### Quadruple Click Reverse Gears

- **Quadruple click (4 clicks) when stopped** enters reverse mode
- Two reverse speeds available:
  - **"Untangle"**: Slow speed for carefully freeing tangled lines
  - **"Reverse"**: Faster speed for backing out of tight spaces
- Use normal speed shifting (tap/double-tap) to switch between reverse speeds
- Release trigger to stop, double-click to return to forward speeds
- Can be enabled/disabled in the app

### Slow Speed Restart

Prevents unexpected speed jumps after stopping in low speeds:

- If you stop at a speed below your start speed, restart resumes at that same speed
- Ideal for sensitive environments like caves, wrecks, or around marine life
- Shifting to speeds above start speed clears this setting
- Returns to normal start speed behavior

### Thirds Battery Display

Professional dive planning tool for managing battery capacity:

- Hold trigger for 10 seconds to activate (audible warble confirms)
- Display shows three bars representing thirds of remaining capacity
- Audible warning when you've used one-third of capacity
- Perfect for implementing rule-of-thirds dive planning
- Can be reset at any point during the dive to recalculate from current battery level

### Battery Capacity Beeps

Audio feedback for battery level when visibility is poor:

- Enable beeps to hear battery capacity without looking at display
- Helpful in dark or murky water conditions
- Adjustable volume levels (0-5)
- Can be enabled/disabled independently

### Battery Imbalance Detection

Detects when one of the two series battery packs becomes significantly more depleted than the other — a condition that can otherwise be masked by the overall pack voltage and lead to an unexpectedly early shutdown mid-dive:

- Continuously monitors the midpoint balance wire while the scooter is at rest
- When the difference between the two packs exceeds the configured threshold, the display flashes a dedicated warning icon identifying **slot 1** or **slot 2** as the depleted pack
- The warning is shown continuously when the motor is off and flashes briefly every few seconds while the motor is running, so it does not obscure the speed or Smart Cruise display
- Warning stays latched until the pack is actually re-balanced (i.e. charged), so a momentary recovery cannot hide a persistent imbalance
- Displayed battery percentage and capacity beeps are scaled to the weaker pack when detection is enabled, keeping the SOC indicator honest as the packs diverge
- Enabled by default with a 2.00 V threshold (suitable for stock hardware); both the threshold and the balance-wire ADC multiplier are configurable from the Battery Settings dialog
- **Disable only when using a custom battery pack with an on-board BMS that manages cell balancing independently**

### Startup Sound

A distinctive musical theme plays on power-up to confirm successful initialization:

- Plays automatically when the scooter is turned on
- When battery is full (3 bars, >75%), only the startup sound plays
- When battery is not full (<75%), the startup sound is followed by battery level beeps
- Volume matches your configured beep volume setting

### Trigger Click Beeps

Training and feedback feature for learning click patterns:

- Each click pattern (single, double, triple, etc.) produces a unique tone
- Single click: 2500 Hz
- Double click: 3000 Hz
- Triple click: 3500 Hz
- Quadruple click: 4000 Hz
- Smart Cruise warning: Distinctive warble pattern
- Helps new divers learn the scooter's control system
- Can be enabled/disabled in the app

### Speed Ramp Rate

Customize acceleration characteristics:

- Adjustable via app to suit your diving style
- Lower values = slower, smoother acceleration (ideal for videography)
- Higher values = faster acceleration (ideal for tech diving)
- Range: 100-10000 ERPM/s (default: 5000)

### Safe Start

Enhanced safety feature preventing accidental prop engagement:

- Detects if prop is blocked during startup
- Stops motor immediately if resistance detected
- Audible beep confirms safe start activation
- Adds zero time to normal startup when prop is clear
- Can be enabled/disabled in the app
- Especially useful when children or untrained individuals might access the scooter

### Bluetooth App Integration

Full access to all features via the VESC mobile app on iOS or Android devices:

- Real-time monitoring of battery, temperature, and RPM
- Configure all settings without connecting to a PC
- Visual interface for speed configuration and feature toggles
- Save settings directly to the scooter

### Latest VESC Firmware (7.00) Compatibility

- Compatible with VESC firmware 7.00 and later
- Benefits from continuous VESC ecosystem improvements
- Ensures optimal motor control and efficiency
- Silent, smooth operation with latest FOC algorithms

### Display Features

- Real-time speed indicator (1-9 for forward speeds)
- Battery percentage display
- "C" indicator when Smart Cruise is active
- "C?" indicator when Smart Cruise nearing expiry
- 8-LED timer bar showing Smart Cruise countdown
- Rotating display support for different mounting orientations
- Battery level indicators (full, thirds mode, percentage)
- Per-slot low-battery warning icons (slot 1 / slot 2) for battery imbalance
- Error code display for diagnostics

## Improvements Over Original Software

This package includes substantial improvements over the original [V1.50 Dive Xtras Poseidon](https://dive-xtras.zendesk.com/hc/en-us/articles/22561137269908-Reset-Blacktip-Software) software:

### New Features Added

- ✅ **Smart Cruise Control** — Complete hands-free cruising system with auto-engage option
- ✅ **Smart Cruise Visual Timer Bar** — 8-LED countdown display showing remaining time
- ✅ **Smart Cruise Warning Mode** — "C?" display and beep when approaching timeout
- ✅ **Refined Speed Control Logic** — Requires long hold before tap to change speed in Smart Cruise mode
- ✅ **Intelligent Beep System** — Warning beeps for important events, silent timer resets
- ✅ **Battery Calculation Method** — Choice between voltage-based or Ah-based calculation
- ✅ **Auto-engage Smart Cruise** — Automatic activation after maintaining constant speed
- ✅ **Battery Imbalance Detection** — Per-pack monitoring via the midpoint balance wire, with a latched on-display warning and SOC correction when one pack is significantly more depleted than the other

### Bug Fixes

- ✅ **EEPROM Wear Protection** — Prevents unnecessary writes, dramatically extending EEPROM life
- ✅ **Settings Persistence** — All configuration changes properly saved and restored
- ✅ **Display Timeout Handling** — Speed number disappears after timeout but timer bar persists
- ✅ **LED Sequence Correction** — Timer bar LEDs turn off in correct order (left to right)
- ✅ **State Machine Improvements** — More reliable state transitions and click detection
- ✅ **Division-by-Zero Protection** — Guards against invalid timeout configurations
- ✅ **Memory Optimization** — Reduced stack usage and optimized variable management

### Enhanced Functionality

- ✅ **Better Click Detection** — Improved timing windows for reliable multi-click recognition
- ✅ **Display Caching** — Reduces I2C traffic for better performance and reliability
- ✅ **Comprehensive Debug Logging** — Easier troubleshooting and development
- ✅ **Code Documentation** — Extensively commented codebase for maintainability
- ✅ **Modular Architecture** — Cleaner separation of concerns for easier updates

### General Improvements

- ✅ **Runs on the latest (7.00) VESC release** — Smoother running with latest FOC algorithms, improved safety features

---

## Installation

### Requirements

- Dive Xtras Blacktip or CudaX scooter
- the latest 'blacktip\_dpv.vescpkg' file from [GitHub](https://github.com/mikeller/vesc_pkg/releases) or the latest official Package Store in VESC Tool
- VESC Tool (PC) or VESC mobile app (iOS/Android), version 7.00 or higher from [VESC Project](https://vesc-project.com/vesc_tool)
- USB cable (for models without Bluetooth)

### Installation Steps

1. **Identify your hardware model:**

**Blacktip generations:**

- **First generation** (Flipsky 4.10 based): Has a short USB cable with type A connector at the motor end
- **Second generation** (Flipsky 6.0 based): No USB cable visible, and no Bluetooth capability\*
- **Third generation** (Flipsky 6.0 MK5 based): Supports Bluetooth connectivity

**CudaX generations:**

- **First generation** (Flipsky 6.0 based): No Bluetooth capability
- **Second generation** (Flipsky 6.0 MK5 based): Supports Bluetooth connectivity

2. **Connect to Scooter:**

**USB:**

**Blacktip First Generation:**

- use an 'USB extension' cable to connect the type A connector on the motor end to your PC
- install batteries to power up the scooter

**Blacktip Second Generation:**

- remove the four screws holding the metal plate on top of the motor assembly
- carefully lift the metal plate to expose the VESC controller mounted on the underside of it
- remove the rubber plug covering the micro USB port on the VESC
- connect a micro USB cable from the VESC to your PC
- install batteries to power up the scooter

**CudaX First Generation:**

- remove the rubber plug covering the micro USB port on the VESC
- connect a micro USB cable from the VESC to your PC
- install batteries to power up the scooter

**Blacktip Third Generation and CudaX Second Generation:**

- install batteries to power up the scooter
- use 'Scan BLE' in the first tab of the VESC Tool or the VESC mobile app to find and connect to your scooter via Bluetooth

3. **Update the VESC firmware:**

(only needed if the firmware version shown in the VESC Tool or VESC mobile app is below 7.00)

- **VESC Tool (PC):**

- Go to the "Firmware" tab
- Click the 'arrow down' button to install the firmware

- **VESC Mobile App:**

- Navigate to the firmware section
- Click the "arrow down" icon to install the firmware

4. **Install Package:**

- **VESC Tool (PC):**

- Go to the "VESC Packages" tab, then the "Load Custom" sub-tab
- Click the "load file" icon and select "blacktip\_dpv.vescpkg"
- Click "Install" and wait for completion

- **VESC Mobile App:**

- Navigate to the packages section
- Click "..."
- Select "Install Package"
- Choose "blacktip\_dpv.vescpkg"
- Confirm installation

5. **Reset to defaults:**

- **This absolutely required after firmware updates or a fresh install.** If you miss it your scooter will not work properly.
- Make sure to check your custom settings before the reset, and then restore them
- In the VESC Tool or Mobile App go to "Settings" / "Scooter Hardware Configuration"
- Make sure the correct model and hardware version is selected
- Click "Reset Defaults"

6. **Verify Installation:**

- The scooter should show the startup splash screen to confirm successful installation
- Check that the custom UI appears in the app
- Configure to suit your preferences
- Test basic functionality in a safe environment

\* this model can be upgraded with a Bluetooth module to enable Bluetooth connectivity, see [these instructions](https://github.com/vedderb/vesc_pkg/blob/main/blacktip_dpv/BLUETOOTH_UPGRADE.md)

### First-Time Configuration

After installation, configure these essential settings:

1. **Scooter Type:**

- Select Blacktip or CudaX in the Hardware Configuration

2. **Battery Settings:**

- Set battery cell count (typically 10S for 36V systems)
- Configure battery capacity (Ah)
- Choose calculation method (voltage or Ah-based)
- Set cutoff voltages

3. **Speed Configuration:**

- Set your preferred start speed (default: 3)
- Configure jump speed (default: 6)
- Adjust individual speed values if needed

4. **Feature Enable/Disable:**

- Enable/disable Smart Cruise
- Enable/disable reverse gears
- Enable/disable safe start
- Configure beep preferences

5. **Smart Cruise Settings:**

- Set Smart Cruise timeout (default: 60 seconds)
- Enable/disable auto-engage
- Set auto-engage delay if enabled (default: 10 seconds)

## Configuration

All settings are accessible through the VESC mobile app or VESC Tool:

### Speed Settings

- **Start Speed:** Speed the scooter starts at (1-9)
- **Jump Speed:** Speed for triple-click start (1-9)
- **Individual Speed Values:** Fine-tune each speed's RPM
- **Speed Ramp Rate:** Acceleration rate (100-10000 ERPM/s)

### Smart Cruise Settings

- **Enable Smart Cruise:** Toggle the feature on/off
- **Smart Cruise Timeout:** How long before warning mode (5-255 seconds)
- **Auto-engage:** Automatically enable Smart Cruise
- **Auto-engage Delay:** Time at constant speed before auto-engage (5-255 seconds)

### Reverse Settings

- **Enable Reverse:** Toggle reverse gears on/off
- **Reverse Speed:** Speed for "Reverse" mode (separate from Untangle)

### Battery Settings

- **Battery Type:** Li-ion, LiPo, LiFePO4, etc.
- **Cell Count:** Number of cells in series (typically 10S)
- **Battery Capacity:** Total Ah rating
- **Calculation Method:** Voltage-based or Ah-based
- **Cutoff Voltages:** Start and end cutoff voltages
- **Enable Battery Imbalance Detection:** Toggle the imbalance warning (default: on)
- **Imbalance Warning Threshold:** Per-pack voltage difference that triggers the warning (0.25 – 2.00 V, default: 2.00 V)
- **Balance-wire ADC Multiplier:** Scales the balance-wire pin voltage to the lower-pack voltage (5.0 – 25.5x, default: 16.2x for stock hardware). To fine-tune, enable Debug Logging and compare the periodic `Balance:` log line's `lower(slot2)` reading against a multimeter measurement at the slot-2 battery terminals.

### Display & Beeper Settings

- **Battery Beeps:** Enable/disable capacity beeps
- **Beep Volume:** 0-5 volume level
- **Display Brightness:** Adjust LED brightness
- **Display Rotation:** 0°, 90°, 180°, 270°
- **Trigger Click Beeps:** Enable/disable click feedback beeps

### Safety Settings

- **Safe Start:** Enable/disable blocked prop detection

### Hardware Configuration

- **Scooter Type:** Blacktip or CudaX (affects display and pinout)

## Support

### Getting Help

For issues, questions, or feature requests:

- **GitHub Issues:** [Report bugs or request features](https://github.com/mikeller/vesc_pkg/issues)
- **Documentation:** See [DEVELOPMENT.md](https://github.com//vedderb/vesc_pkg/blob/main/blacktip_dpv/DEVELOPMENT.md) for technical details

### Before Reporting Issues

1. Ensure you're running the latest version
2. Check that your VESC firmware is version 7.00 or higher
3. Verify your settings are properly saved
4. Try resetting to default settings to isolate the issue
5. Enable the debug log and check it in VESC Tool (LispBM Scripting tab)

## Contributing

Contributions are welcome! Whether you're fixing bugs, adding features, or improving documentation, your help is appreciated.

---

**Dive safely and enjoy your enhanced scooter** 🦈⚡
