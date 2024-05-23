# Trick and Trail VESC Package
by Mike Silberstein (send questions, comments, requests to izzyvesc@gmail.com)

Trick and Trail Package was developed based on Float Package 1.2 by Surfdado and Niko for self-balanced boards. It departs from the traditional PID control scheme that is rooted in the balance robot design. This is replaced with a user defined, current output curve that is based on board pitch. This allows for an infinite number of throttle/braking curves that gives the user the ability to truly tune the board how they want.

This package has been improved thanks to the contributions of Lukas Hrazky with Refloat.

[READ THE WIKI](https://github.com/Izzygit/TrickandTrailReleases/wiki) https://github.com/Izzygit/TrickandTrailReleases/wiki

### Features
* Pitch Tune - Current output defined by a series of points, input by the user.
* Roll Tune - for acceleration and braking, to improve board response.
* Yaw Tune - for acceleration and braking, to improve board response.
* Surge - high current response to help prevent nosedives.
* Traction Control - reduce free spin in the air. 
* Sticky Tilt - accurate, manual board level control with a remote.
* Dynamic Stability - faster board response at higher speeds or with a remote.
* Alternative proportional gain user inputs for pitch.
* Optional independent brake curve for pitch.
* High Duty Haptic Buzz - high speed warning.
* High Current Haptic Buzz - instant, high torque warning.

### Default Settings
Default settings are based on 20s battery, Hypercore (Future Motion motor), and Little Focer v3.1 set up. These are the setting I ride for trails. The one exception is surge which is disabled. Here are more details on the default settings:
* Pitch Tune - Loose close to the setpoint but tightens quickly at high pitch angles.
  * For a street tune you will want the tune to be tighter close to the setpoint. Increase Kp0, Pitch 1 kp, and Pitch 2 kp. You could also decrease Pitch 1 and Pitch 2 angles.
  * For a trick tune you may want it to be looser at higher pitch angles. Increase Pitch 3 angle or decrease Pitch 3 Kp.
* Roll Tune - The current roll tune is loose and moderately aggressive
  * To make the roll tighter and more race-like, decrease Level 1 and Level 2 Roll Angles.
  * To make the tune less agressive decrease Roll Kp.
* Yaw Tune - The current yaw tune is loose and moderately aggresive
  * To make the yaw tighter and more race-like, decrease Level 1 and Level 2 Yaw Angles.
  * To make the tune less agressive decrease Yaw Kp.
* High Current
  * High current conditions based on 150 peak amps, 30 battery amps, and hypercore motor.
  * Changes must be made for higher current motors like the cannoncore and superflux.
* Surge 
  * Disabled by default for safety.
* Traction Control
  * Should work well for most boards. Light riders on powerful boards may need to increase Start Condition to prevent nuisance trips.
* Haptic Buzz
  * Activated for high duty and high current
  * Riders with cannoncore or superflux motors may opt to disable high current haptic buzz until you correct the high current conditions.

For more instructions on setting up your board please refer to the [Set Up Guide.](https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide) https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide

## Change Log
### 1.3
* **Version 1.3 parameters are not compatible with v1.2 and will be set to default. Screenshot your tunes to save.**
* Code refactored thanks to contributions from Lukas Hrazky, author of Refloat.
* _Features_
  * Yaw
    * Yaw kp curves, similar to the roll kp curves, modify the current ouput based on yaw input.
    * Instead of using angle, like pitch and roll, yaw is measured in angle change per second (how quickly you rotate the board).
    * Minimum erpm limits yaw response at low speeds.
    * New Yaw menu next to Roll
    * New debug section in AppUI is toggled in Specs tab allows for accurate yaw tuning.
  * Traction control overhaul
    * Changed traction control inputs/outputs for motor acceleration to ERPM/ms from ERPM/cycle.
    * Changed the minimum delay between traction control activations from 200ms to 20ms
    * Added a new end condition to handle an edge case that would not exit traction control correctly.
    * Remove drop condition from traction control deactivation conditions.
    * Changed the names of the parameters to Start Condition, End Condition, and Transtion Condition.
    * Transition condition can now be negative.
    * End condition is now based on acceleration rate in ERPM/ms^2 for improved performance.
    * New debug ouput in AppUI counts how many traction control activations in the last 5 seconds.
  * Dynamic Stability
    * Added new parameter Ramp Rate Down. Default 5.0 %/s
* _Fixes/Improvements_
  * Some parameters changed to integers to reduce packet size.
  * Some features and parameters were removed to make room for new features.
    * Haptic buzz for temperature and voltage
    * Haptic buzz for duty and current is now on/off. Vibrating1 is the haptic type.
    * Startup roll angle hard coded to 45 degrees.
    * Fault delay roll is now the same as fault delay pitch, called fault delay angle.
    * Feature start up clicks is no longer available.
  * Fixed a bug that would prevent high current haptic buzz if surge was engaged.
  * AppUI now displays the following for state:
    * when idle... "READY-" and last stop/fault reason
    * when running... "RUNNING-" and tiltback reason
    * in traction control/wheelslip... "WHEELSLIP"
  * Readme format updated for 6.05
  * Sticky tilt no longer "remembers" tilt angle after dismount. Resets setpoint to zero every time.

 
### 1.2
* **Version 1.2 parameters are not compatible with v1.1 and will be set to default. Screenshot your tunes to save.**
* _Features_
  * Haptic Buzz
    * Adopted haptic buzz implementation from Float Package 2.0
    * Overcurrent haptic buzz modifed to be instantaneous instead of continuous. Now called High Current.
    * High Current haptic buzz now has a user input duration to limit continuous buzz in high current situations.
    * BMS haptic buzz not implemented yet.
  * New Section "High Current" in Tune Modifiers
    * Allows the user to configure the maximum current of the motor
    * Adjust max current for higher duty cycles
    * Haptic buzz will activate at a user input margin from max current, if high current haptic buzz is enabled
    * Surge will activate at the max current, if surge is enabled
    * User input minimum ERPM implemented to prevent surge and/or haptic buzz in low speed situations.
  * Surge Overhaul
    * Changed surge trigger from pitch differential to high current, configured in the High Current section
    * Changed surge end condition to be based on a user input pitch to allow more flexible and stronger surges.
    * Adjustable surge ramp rate for more powerful boards.
  * AppUI Overhaul
    * Debug Overhaul
      * New options on Specs tab allow for different debug text on the AppUI screen.
      * Traction control debug
      * Surge debug
      * Tune debug. This includes pitch kp, stability, and roll kp information previously under Tune
    * New Trip data replaces Tune
      * Monitors board state to determine when the board is idle and displays ride vs rest time.
      * Ride/rest time is used to correct RT data for better ride data including current, speed and power averages.
    * Added last beep reason from Float Package 1.2 to AppUI screen
* _Fixes/Improvements_
  * Dynamic stability now works while riding switch
  * Fixed a bug originating in 1.1 that prevented traction control while riding switch
  * **Default settings are now based on 20S Hypercore configuration (30A battery, 150A peak)**

### 1.1
* **Version 1.1 parameters are not compatible with v1.0 and will be set to default. Screenshot your tunes to save.**
* _Features_
  * Dynamic Stability
    * Increase pitch current and pitch rate response (kp rate) at higher speeds or with remote control.
    * Found in the tune modifiers menu.
    * Speed stability enabled by default
    * Enabling remote control stability disables remote tilt.
    * New indicators on AppUI for relative stability (0-100%) and the added kp and kp rate from stability applied to the pitch response.
  * Independent braking curve
    * New menu "Brake".
    * Disabled by default.
    * Uses the same layout and logic as the acceleration menu.
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
