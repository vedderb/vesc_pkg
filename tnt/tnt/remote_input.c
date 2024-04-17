// Copyright 2024 Michael Silberstein
//
// This file is part of the VESC package.
//
// This VESC package is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This VESC package is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.

static void apply_inputtilt(data *d){ // Input Tiltback
	float input_tiltback_target;
	 
	// Scale by Max Angle
	input_tiltback_target = d->throttle_val * d->tnt_conf.inputtilt_angle_limit;
	
	//Sticky Tilt Input Start	
	if (d->tnt_conf.is_stickytilt_enabled) { 
		float stickytilt_val1 = d->tnt_conf.stickytiltval1; // Value that defines where tilt will stick for both nose up and down. Can be made UI input later.
		float stickytilt_val2 = d->tnt_conf.stickytiltval2; // Value of 0 or above max disables. Max value <=  d->tnt_conf.inputtilt_angle_limit. 
		//Val1 is the default value and value 2 is the step up value that engages when you flick the throttle toward sitcky tilt direction while engaged at val1 (but not to max)
		
		// Monitor the throttle to start sticky tilt
		if ((fabsf(d->throttle_val) - fabsf(d->last_throttle_val) > .001) || // If the throttle is travelling away from center
		   (fabsf(d->throttle_val) > 0.95)) {					// Or close to max
			d->stickytilt_maxval = sign(d->throttle_val) * max(fabsf(d->throttle_val), fabsf(d->stickytilt_maxval)); // Monitor the maximum throttle value
		}
		// Check for conditions to start stop and swap sticky tilt
		if ((d->throttle_val == 0) && // The throttle is at the center
		   (fabsf(d->stickytilt_maxval) > 0.01)) { // And a throttle action just happened
			if ((!d->stickytiltoff) && // Don't apply sticky tilt if we just left sticky tilt
			   (fabsf(d->stickytilt_maxval) < .95)) { //Check that we have not pushed beyond this limit
				if (d->stickytilton) {//if sticky tilt is activated, switch values
					if (((fabsf(d->motor.current_avg) < d->tnt_conf.stickytilt_holdcurrent) &&
					   (fabsf(d->stickytilt_val) == stickytilt_val2)) ||				//If we are val2 we must be below max current to change
					   (fabsf(d->stickytilt_val) == stickytilt_val1)) {				//If we are at val1 the current restriction is not required
						d->stickytilt_val = sign(d->stickytilt_maxval) * ((fabsf(d->stickytilt_val) == stickytilt_val1) ? stickytilt_val2 : stickytilt_val1); //switch sticky tilt values from 1 to 2
					}
				} else { //else apply sticky tilt value 1
					d->stickytilton = true;
					d->stickytilt_val = sign(d->stickytilt_maxval) * stickytilt_val1; // Apply val 1 for initial sticky tilt application							
				} 
			}
			d->stickytiltoff = false; // We can turn off this flag after 1 cycle of throttle ==0. Avoids getting stuck on sticky tilt when turning sticky tilt off
			d->stickytilt_maxval = 0; // Reset
		}
		
		if (d->stickytilton) { 	//Apply sticky tilt. Check for exit condition
			//Apply sticky tilt value or throttle values higher than sticky tilt value
			if ((sign(d->inputtilt_interpolated) == sign(input_tiltback_target)) || (d->throttle_val == 0)) { // If the throttle is at zero or pushed to the direction of the sticky tilt value. 
				if (fabsf(d->stickytilt_val) >= fabsf(input_tiltback_target)) { // If sticky tilt value greater than throttle value keep at sticky value
					input_tiltback_target = d->stickytilt_val; // apply our sticky tilt value
				} //else we will apply the normal throttle value calculated at the beginning of apply_inputtilt() in the direction of sticky tilt
			} else {  //else we will apply the normal throttle value calculated at the beginning of apply_inputtilt() in the opposite direction of sticky tilt and exit sticky tilt
				d->stickytiltoff = true;
				d->stickytilton = false;
			}
		}
		d->last_throttle_val = d->throttle_val;
	}
	//Sticky Tilt Input End
	
	float input_tiltback_target_diff = input_tiltback_target - d->inputtilt_interpolated;

	if (d->tnt_conf.inputtilt_smoothing_factor > 0) { // Smoothen changes in tilt angle by ramping the step size
		float smoothing_factor = 0.02;
		for (int i = 1; i < d->tnt_conf.inputtilt_smoothing_factor; i++) {
			smoothing_factor /= 2;
		}

		float smooth_center_window = 1.5 + (0.5 * d->tnt_conf.inputtilt_smoothing_factor); // Sets the angle away from Target that step size begins ramping down
		if (fabsf(input_tiltback_target_diff) < smooth_center_window) { // Within X degrees of Target Angle, start ramping down step size
			d->inputtilt_ramped_step_size = (smoothing_factor * d->inputtilt_step_size * (input_tiltback_target_diff / 2)) + ((1 - smoothing_factor) * d->inputtilt_ramped_step_size); // Target step size is reduced the closer to center you are (needed for smoothly transitioning away from center)
			float centering_step_size = min(fabsf(d->inputtilt_ramped_step_size), fabsf(input_tiltback_target_diff / 2) * d->inputtilt_step_size) * sign(input_tiltback_target_diff); // Linearly ramped down step size is provided as minimum to prevent overshoot
			if (fabsf(input_tiltback_target_diff) < fabsf(centering_step_size)) {
				d->inputtilt_interpolated = input_tiltback_target;
			} else {
				d->inputtilt_interpolated += centering_step_size;
			}
		} else { // Ramp up step size until the configured tilt speed is reached
			d->inputtilt_ramped_step_size = (smoothing_factor * d->inputtilt_step_size * sign(input_tiltback_target_diff)) + ((1 - smoothing_factor) * d->inputtilt_ramped_step_size);
			d->inputtilt_interpolated += d->inputtilt_ramped_step_size;
		}
	} else { // Constant step size; no smoothing
		if (fabsf(input_tiltback_target_diff) < d->inputtilt_step_size){
		d->inputtilt_interpolated = input_tiltback_target;
	} else {
		d->inputtilt_interpolated += d->inputtilt_step_size * sign(input_tiltback_target_diff);
	}
	}
	if (!d->tnt_conf.enable_throttle_stability) {
		d->rt.setpoint += d->inputtilt_interpolated;
	}
}