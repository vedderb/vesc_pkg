# Trick and Trail VESC Package
by Mike Silberstein (send questions, comments, requests to izzyvesc@gmail.com)

Trick and Trail Package was developed based on Float Package 1.2 by Surfdado and Niko for self-balanced boards. It departs from the traditional PID control scheme that is rooted in the balance robot design. This is replaced with a user defined, current output curve that is based on board pitch. This allows for an infinite number of throttle/braking curves that gives the user the ability to truly tune the board how they want.

[READ THE WIKI](https://github.com/Izzygit/TrickandTrailReleases/wiki) https://github.com/Izzygit/TrickandTrailReleases/wiki

### Features
 * Current output defined by a series of points, input by the user
 * Alternative proportional gain user inputs
 * Roll kp curves for acceleration and braking
 * Roll kp modification for low speeds
 * Surge
 * Traction control
 * Sticky tilt

### Default Settings
Default settings are based on 15s Hypercore (Future Motion motor) board set up. The default settings are what I ride for trails. The exceptions are surge and traction control which are disabled by default. These are more advanced behaviors that should be tuned by the user. For more instructions on setting up your board please refer to the [Set Up Guide.](https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide) https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide

## Change Log
