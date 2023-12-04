# Trick and Trail VESC Package
by Mike Silberstein (send questions, comments, requests to izzyvesc@gmail.com)

Trick and Trail Package was developed based on Float Package 1.2 by Surfdado and Niko for self-balanced boards. It departs from the traditional PID control scheme that is rooted in the balance robot design. This is replaced with a user defined, current output curve that is based on board pitch. This allows for an infinite number of throttle/braking curves that gives the user the ability to truly tune the board how they want.

[READ THE WIKI](https://github.com/Izzygit/TrickandTrailReleases/wiki) https://github.com/Izzygit/TrickandTrailReleases/wiki

### Features
 * Current output defined by a series of points, input by the user
 * Alternative proportional gain user inputs
 * Optional independent brake curve
 * Roll kp curves for acceleration and braking
 * Roll kp modification for low speeds
 * Surge
 * Traction control
 * Sticky tilt
 * Dynamic Stability

### Default Settings
Default settings are based on 15s Hypercore (Future Motion motor) board set up. The default settings are what I ride for trails. The exceptions are surge and traction control which are disabled by default. These are more advanced behaviors that should be tuned by the user. For more instructions on setting up your board please refer to the [Set Up Guide.](https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide) https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide

## Change Log
### 1.1
 * **Version 1.1 parameters are not compatible with v1.0 and will be set to default. Screenshot your tunes to save.**
 * _Features_
   *  Dynamic Stability
       *  Increase pitch current and pitch rate response (kp rate) at higher speeds or with remote control.
       *  Found in the tune modifiers menu.
       *  Speed stability enabled by default
       *  Enabling remote control stability disables remote tilt.
       *  New indicators on AppUI for relative stability (0-100%) and the added kp and kp rate from stability applied to the pitch response.
   * Independent braking curve
     *  New menu "Brake".
     *  Disabled by default.
     *  Uses the same layout and logic as the acceleration menu.
 * _Fixes/Improvements_
   * Changed name of "Pitch" menu to "Acceleration".
   * Changed name of "Surge / Traction Control" menu to "Tune Modifiers"
   * Removed limitations on pitch current and kp that only allowed increasing values. Now decreasing or negative values are allowed. Pitch must still be increasing.
   * Added a significant digit to the first two pitch values on the acceleration and brake curves for more precision.
   * Reorganized the AppUI screen.
   * Cleaned up AppUI to remove unused quicksave buttons.
   * Updated traction control to remove false start scenario.
### 1.0
 * Initial release.
