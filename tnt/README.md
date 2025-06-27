# Trick and Trail VESC Package
by Mike Silberstein (send questions, comments, requests to izzyvesc@gmail.com)

Trick and Trail Package was developed based on Float Package 1.2 by Surfdado and Nico for self-balanced boards. It departs from the traditional PID control scheme that is rooted in the balance robot design. This is replaced with a user defined, current output curve that is based on board pitch. This allows for an infinite number of throttle/braking curves that gives the user the ability to truly tune the board how they want.

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
* High Duty FOC Tone - high speed warning.
* High Current FOC Tone - instant, high torque warning.

### Default Settings
Default settings are based on 20s battery, Hypercore (Future Motion motor), and Little Focer v3.1 set up. Here are more details on the default settings:

* Pitch Tune - The default pitch tune is a simple beginner tune using only TNT Cfg->Acceleration kp0, kp rate, current 1 and pitch 1.
  * For a trick or trail tune you will want a lower kp0 and gradually increasing pitch angles and currents.
  * See TNT Cfg->Braking for an example trail riding tune.
* Roll Tune - The default roll tune is very loose and moderate for easy, deep carving.
  * To make the roll tighter and more race-like, decrease Level 2 Roll Angle.
  * To make the tune less aggressive decrease Roll Kp.
  * To make the tune less agile at low speed reduce the low speed maximum scaler.
  * To adjust the agility at high speed change the high speed maximum scaler.
* Yaw Tune - The default yaw tune is loose and moderately aggressive
  * To make the yaw tighter and more race-like, decrease Level 1 and Level 2 Yaw Angles.
  * To make the tune less aggressive decrease Yaw Kp.
* High Current
  * High current conditions are based on 150 peak amps, 30 battery amps, and hypercore motor.
  * Changes must be made for higher current motors like the cannoncore and superflux.
* Surge 
  * Disabled by default for safety.
  * Set your high current section first.
* Traction Control
  * Decrease Transition Condition and increase End Condition for looser landings and less wheel spin.
  * Increase ERPM filter frequnecy for a faster response, decrease to control wheel spin for longer air time.
  * Traction Braking disabled by default.
* FOC Play Tones
  * Disabled by default because of potential issues with Absolute Max Motor Current. See warning in the help text.
  * Riders with cannoncore or superflux motors should set high current conditions before using high current FOC tones.

For more instructions on setting up your board please refer to the [Set Up Guide.](https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide) https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide

## Change Log
### 1.6
* **This version requires 6.05+ firmware to fuction properly**
* _Features_
  * New Feature - Yaw Rate Kp in the Yaw menu
    * New math handling the IMU gyro changes the nose stiffness behavior of Pitch Rate Kp and new feature Yaw Rate Kp
    * Added New parameters Yaw Rate Kp and Yaw Rate Braking Kp
    * Higher Pitch Rate Kp increases the stiffness of the nose under all conditions
    * Higher Yaw Rate Kp will increase nose stiffness while applying yaw (i.e. carving)
    * Yaw Rate Kp of 1 produces the pre-1.6 gyro behaviour.
    * Yaw Rate Kp of 0 removes yaw stiffness.
  * Traction Control
    * Added feature Tracking ERPM to better differentiate rider speed from motor ERPM
    * Added Tracking ERPM Rate Limit parameter limits the rate that Tracking ERPM can change
    * Added Tracking ERPM Exclusion Rate parameter excludes high acceleration rates from Tracking ERPM
    * Added Tracking ERPM Margin parameter defines the difference between actual ERPM and Tracking ERPM before traction control will engage
    * Default Start Acceleration changed to 35 ERPM/ms
    * Default ERPM Filter Frequency to 25 Hz
    * Replaced Start Condition with Track ERPM in AppUI debug
  * AppUI Overhaul
    * Removed tune debug
    * Added pitch, roll. stability, and current debugs
    * Added yaw rate and yaw rate current demand to yaw debug
    * Added last drop time 
    * New trip data
      * Removed power average
      * Added distance in miles
      * Added max carve chain (minimum yaw change 100 deg/s, every 3 seconds)
      * Added carves per mile
      * Added average yaw during carves
      * Added average roll during carves
      * Added air time counter
      * Added max air time
      * Added toggle to TNT Cfg->Specs, Reset Trip Data on Write, to do so when activated
  * Traction Control Braking
    * Added parameter Off Delay, which keeps traction braking active after the off signal has been receive for smoother downhill traction control
    * 0 by default, 5 ms recommended
* _Fixes/Improvements_
  * Renamed 'inputtilt_interpolated' to 'setpoint' in the remote variables
  * Yaw
    * Added a hard coded correction factor to yaw change to account for higher yaw change that resulted at higher package loop frequencies
  * Surge
    * Reduced default max angle to 1.5 and setpoint margin to 2.5 to produce a nose lift that is easier to handle

### 1.5
* **This version requires 6.05 firmware to fuction properly**
* _Fixes/Improvements_
  * Testing and support for higher package loop frequencies.
    * Traction Control Start Acceleration help text updated.
    * Traction Control Scale ERPM help text updated.
    * High Current Filter Frequency help text updated.
    * Changed parameter name Specs->Loop Rate to Package Loop Frequency. Updated help text.
  * Traction Control Braking
    * Added new conditions to engage traction control braking
      * Vq and Iq comparison to confirm FOC braking
      * Battery current less than zero to confirm regeneration
    * Removed start and end delay parameters as they are no longer required
    * Changed AppUI debug to show battery current and end conditions after 1 second of engagement
    * Added new end condtions to AppUI debug
  * Traction Control
    * Changed default start acceleration from 29 ERPM/ms to 50 ERPM/ms to allow for higher package loop frequencies by default.
    * Added Hold Period configurable parameter which allows the user to control the period between traction control engagements
  * Surge/High Current
    * Added Current Filter Frequency parameter to allow the user to change the low pass filter frequency on motor current which is necessary for for higher package loop frequencies
    * Changed default Current Filter Frequency from 3 to 5 Hz.
    * Changed default Min ERPM for surge from 1500 to 2000.
  * Increased the voltage threshold that designates a charging situation from 0.1V to 0.3V to avoid nuisance activations
  * AppUI will now display the stop condition as TRACTN CTRL if traction control is active when the board is deactivated

### 1.4
* **This version requires 6.05 firmware to fuction properly**
* **Version 1.4 parameters are not compatible with v1.3 and will be set to default. Screenshot your tunes to save.**
* _Features_
  * New Feature - Traction Control Braking (beta)
    * Utilizes VESC 'set brake' fuction to apply brake current with no wheel spin
    * Parameter that allows traction braking only when a minimum nose down angle is requested via remote
    * Parameter for minimum ERPM
  * Traction Control Improvements
    * Added low pass filter to ERPM which is used to calculate motor acceleration.
    * New parameter to adjust low pass filter frequency.
    * Now End Conditions consist of Transition, End and Hold conditions
    * Absolute value of motor acceleration must be less than Transition Condition to allow end condition
    * Absolute value of motor acceleration must be greater than End Condition to end traction control
    * Absolute value of motor acceleration must be less than Hold Condition to allow another traction control engagement.
    * New parameter allows for the termination of traction control when a pitch angle threshold is met.
    * Removed intermediate time outs and changed traction control to 1 second time out.
    * Added conditions for traction braking.
  * FOC Play Tones
    * FOC play tones now replaces haptic buzz.
    * Available in the Safety Alerts menu.
    * Be sure to read the warnings in the help text concerning Abs Max Current.
    * New parameters allow for frequency and voltage (volume) adjustment for high current and high duty tones
    * Beeper is now replaced with FOC play tones with the following alerts implemented
      * Duty cycle within 10% of tiltback duty cycle- fast triple beep, ascending pitch
      * High voltage - slow triple beep, ascending pitch
      * Low voltage - slow triple beep, descending pitch
      * High motor temp - slow triple beep, single pitch
      * High fet temp - slow triple beep, single pitch
      * New feature fet/motor temp recovery, when 10 degrees below tiltback temperature- fast triple beep, ascending pitch
      * New features Mid/Low Range Warnings - slow triple beep, descending pitch
      * Footpad disengaged above 2000 ERPM - continuous single pitch
      * On write configuration - fast triple beep, single pitch (only when idle)
      * Idle beeper after 30 minutes - slow double beep, single pitch
      * New feature charged alert - slow double beep, single pitch
    * New parameter to adjust beeper volume.
    * Added more Last Beep Reasons to AppUI to identify the new beep features.
  * Simple Start now has a configurable delay after the board has been disengaged, Simple Start Delay, in Startup
  * Quick Stop now has an on/off toggle, configurable ERPM and pitch angle, in Stop
* _Fixes/Improvements_
  * Continued code refactoring
  * Changed default pitch tune to Pitch Kp0=20, Pitch Kp Rate=0.6, Pitch 1 Current=100, Pitch 1=3.
  * Renamed menu Safety Tiltback/Alerts to Safety Alerts and reorganized
    * High voltage and low voltage thresholds moved from Specs to Safety Alerts
    * Enable beep on sensor fault moved from Specs to Safety Alerts
    * Enable beep (general) moved from Specs to Safety Alerts
  * Footpad sensor ADC1 and ADC2 voltage thresholds moved to Startup menu.
  * Added a list of end conditions to AppUI for Surge and Traction Control debugs.
  * Added a timer to AppUI to show the last time Traction Control Braking was used.
  * Increased ERPM required to engage idle brake to 10.

### 1.3
* **Version 1.3 parameters are not compatible with v1.2 and will be set to default. Screenshot your tunes to save.**
* Code refactored thanks to contributions from Lukas Hrazky, author of Refloat.
* _Features_
  * Yaw
    * Yaw kp curves, similar to the roll kp curves, modify the current output based on yaw input.
    * Instead of using angle, like pitch and roll, yaw is measured in angle change per second (how quickly you rotate the board).
    * Minimum ERPM limits yaw response at low speeds.
    * New Yaw menu next to Roll
    * New debug section in AppUI is toggled in Specs tab, allows for accurate yaw tuning.
  * Traction control overhaul
    * Changed traction control inputs/outputs for motor acceleration to ERPM/ms from ERPM/cycle.
    * Changed the minimum delay between traction control activations from 200ms to 20ms
    * Added a new end condition to handle an edge case that would not exit traction control correctly.
    * Remove drop condition from traction control deactivation conditions.
    * Changed the names of parameters to Start Condition and End Condition. Previously, Wheelslip Acceleration Trigger and Wheelslip Margin.
    * End condition can now be negative.
    * Removed parameter Wheelslip Acceleration End.
    * New debug output in AppUI counts how many traction control activations in the last 5 seconds.
    * Changed timeouts from 500ms for traction control, 180ms for transition condition 1, and 200ms for transition condition 2 to 300ms, 210ms, and 220ms respectively.
  * Dynamic Stability
    * Added new parameter Ramp Rate Down. Default 5.0 %/s. Prevents nose dip feeling when reducing speed.
  * Roll
    * Added high speed scaling section to increase or decrease roll kp at higher speeds.
* _Fixes/Improvements_
  * Some parameters changed to integers to reduce packet size.
  * Some features and parameters were removed to make room for new features.
    * Haptic buzz for temperature and voltage
    * Haptic buzz for duty and current is now on/off. Audible2 is the haptic type.
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
    * Overcurrent haptic buzz modified to be instantaneous instead of continuous. Now called High Current.
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
