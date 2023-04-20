# IzzFLOAT
My personal changes to the VESC Float Package

Version 1.0.0.1

- Updated to v1.0 FLOAT package
- Migrated turn boost, sticky tilt and surge behaviors
- TURN TILT ENTRIES NO LONGER EFFECT SURGE. Hard-coded all surge user entries to my perferred values for safety and simplicity. 
  - Start Angle Speed = 50 degrees/s
  - Start Differential = 3 degrees
  - Current Margin = 1.3
- Changed surge minimum angle to initialize to Start Differential to smooth out transition from braking to surge.

Version 0.9.1.1

- Replaces traditional pitch booster with roll based booster, Turn Boost

Version 0.9.1.0

- Adds surge behavior with differential pitch trigger (https://pev.dev/t/im-excited-to-bring-you-surge-behavior-in-izzfloat-package/730)

Version 0.9.0.1

- Adds sticky tilt input with hardcoded value of 3.0 (https://pev.dev/t/i-made-my-first-feature-sticky-input-tilt-for-your-remote/687)



<H2>Readme from FLOAT</H2>

A balance vehicle package specifically tailored for one wheeled skateboards, as invented by Ben Smither in 2007: http://www.robosys.co.uk/

Includes all the basics such as PID control, ATR, and Turntilt - but also has popular features such as remote support,  dirty landings, push start, and many more. See help text in the tool/app for details on any feature.

Now includes Quicksaves in the AppUI!

<H3><font color=yellow>NEW USERS: DO NOT LOAD UNTIL YOU'VE CONFIGURED MOTOR AND IMU!!!</font></H3>

After loading do not forget to configure your details in the Specs tab: voltages and ADC values (default assumes 15s pack and 3.0V ADC cutoffs).

Once you've adjusted your voltages the default tune should provide you with a well behaving, rideable board. If it acts weird it's most likely a motor configuration or IMU calibration issue!

<H2>DISCLAIMER</H2>

This package is not endorsed by the vesc-project. Use at your own risk.

<H2>CREDITS</H2>

Based on Mitch Lustig's original Balance Package, but specifically tailored for one wheeled skateboards.

Ported by Nico Aleman, heavily based on SurfDado's ATR Firmware: https://pev.dev/t/atr-firmware-101/43

Removed unneeded parameters, added new features and behaviors and a more user-friendly configuration menu with usable default/min/max values and informative Help text.

<H2>RELEASE NOTES</H2>

Release Changelogs: https://pev.dev/t/float-package-changelogs/499

<H3>BUILD INFO</H3>

Source code can be found here: https://github.com/NicoAleman/vesc_pkg-float

#### &nbsp;
#### Build Info
