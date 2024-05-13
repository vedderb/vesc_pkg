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

#include "remote_input.h"
#include "utils_tnt.h"
#include <math.h>

void apply_stickytilt(RemoteData *r, StickyTiltData *s, float current_avg, float *input_tiltback_target){ 
	// Monitor the throttle to start sticky tilt
	if ((fabsf(r->throttle_val) - fabsf(s->last_throttle_val) > .001) || // If the throttle is travelling away from center
	   (fabsf(r->throttle_val) > 0.95)) {					// Or close to max
		s->max_value = sign(r->throttle_val) * max(fabsf(r->throttle_val), fabsf(s->max_value)); // Monitor the maximum throttle value
	}
	
	// Check for conditions to start stop and swap sticky tilt
	if ((r->throttle_val == 0) && 					// The throttle is at the center
	   (fabsf(s->max_value) > 0.01)) { 				// And a throttle action just happened
		if ((!s->deactivate) && 				// Don't apply sticky tilt if we just left sticky tilt
		   (fabsf(s->max_value) < .95)) { 			//Check that we have not pushed beyond this limit
			if (s->active) {				//if sticky tilt is activated, switch values
				if (((fabsf(current_avg) < s->hold_current) &&
				   (fabsf(s->value) == s->high_value)) ||			//If we are val2 we must be below max current to change
				   (fabsf(s->value) == s->low_value)) {				//If we are at val1 the current restriction is not required to change
					s->value = sign(s->max_value) * ((fabsf(s->value) == s->low_value) ? s->high_value : s->low_value); //switch sticky tilt values from 1 to 2
				}
			} else { //else apply sticky tilt value 1
				s->active = true;
				s->value = sign(s->max_value) * s->low_value; // Apply val 1 for initial sticky tilt application							
			} 
		}
		s->deactivate = false; // We can turn off this flag after 1 cycle of throttle ==0. Avoids getting stuck on sticky tilt when turning sticky tilt off
		s->max_value = 0; // Reset
	}
	
	if (s->active) { 	//Apply sticky tilt. Check for exit condition
		//Apply sticky tilt value or throttle values higher than sticky tilt value
		if ((sign(r->inputtilt_interpolated) == sign(*input_tiltback_target)) || (r->throttle_val == 0)) { 	// If the throttle is at zero or pushed to the direction of the sticky tilt value. 
			if (fabsf(s->value) >= fabsf(*input_tiltback_target)) { 						// If sticky tilt value greater than throttle value keep at sticky value
				*input_tiltback_target = s->value; // apply our sticky tilt value
			} 
		} else {  												//else we will apply the normal throttle value calculated at the beginning of apply_inputtilt() in the opposite direction of sticky tilt and exit sticky tilt
			s->deactivate = true;
			s->active = false;
		}
	}
	s->last_throttle_val = r->throttle_val;
}

void apply_inputtilt(RemoteData *r, float input_tiltback_target){ 
	float input_tiltback_target_diff = input_tiltback_target - r->inputtilt_interpolated;

	if (r->smoothing_factor > 0) { // Smoothen changes in tilt angle by ramping the step size
		float smoothing_factor = 0.02;
		for (int i = 1; i < r->smoothing_factor; i++) {
			smoothing_factor /= 2;
		}

		float smooth_center_window = 1.5 + (0.5 * r->smoothing_factor); // Sets the angle away from Target that step size begins ramping down
		if (fabsf(input_tiltback_target_diff) < smooth_center_window) { // Within X degrees of Target Angle, start ramping down step size
			r->ramped_step_size = (smoothing_factor * r->step_size * (input_tiltback_target_diff / 2)) + ((1 - smoothing_factor) * r->ramped_step_size); // Target step size is reduced the closer to center you are (needed for smoothly transitioning away from center)
			float centering_step_size = min(fabsf(r->ramped_step_size), fabsf(input_tiltback_target_diff / 2) * r->step_size) * sign(input_tiltback_target_diff); // Linearly ramped down step size is provided as minimum to prevent overshoot
			if (fabsf(input_tiltback_target_diff) < fabsf(centering_step_size)) {
				r->inputtilt_interpolated = input_tiltback_target;
			} else {
				r->inputtilt_interpolated += centering_step_size;
			}
		} else { // Ramp up step size until the configured tilt speed is reached
			r->ramped_step_size = (smoothing_factor * r->step_size * sign(input_tiltback_target_diff)) + ((1 - smoothing_factor) * r->ramped_step_size);
			r->inputtilt_interpolated += r->ramped_step_size;
		}
	} else { // Constant step size; no smoothing
		if (fabsf(input_tiltback_target_diff) < r->step_size){
			r->inputtilt_interpolated = input_tiltback_target;
		} else {
			r->inputtilt_interpolated += r->step_size * sign(input_tiltback_target_diff);
		}
	}
}

void update_remote(tnt_config *config, RemoteData *r) {
	// UART/PPM Remote Throttle 
	bool remote_connected = false;
	float servo_val = 0;
	switch (config->inputtilt_remote_type) {
	case (INPUTTILT_PPM):
		servo_val = VESC_IF->get_ppm();
		remote_connected = VESC_IF->get_ppm_age() < 1;
		break;
	case (INPUTTILT_UART): ; // Don't delete ";", required to avoid compiler error with first line variable init
		remote_state remote = VESC_IF->get_remote_state();
		servo_val = remote.js_y;
		remote_connected = remote.age_s < 1;
		break;
	case (INPUTTILT_NONE):
		break;
	}

	if (!remote_connected) {
		servo_val = 0;
	} else {
		// Apply Deadband
		float deadband = config->inputtilt_deadband;
		if (fabsf(servo_val) < deadband) {
			servo_val = 0.0;
		} else {
			servo_val = sign(servo_val) * (fabsf(servo_val) - deadband) / (1 - deadband);
		}
		// Invert Throttle
		servo_val *= (config->inputtilt_invert_throttle ? -1.0 : 1.0);
	}
	r->throttle_val = servo_val;
}

void configure_remote_features(tnt_config *config, RemoteData *r, StickyTiltData *s) {
	r->smoothing_factor = config->inputtilt_smoothing_factor;
	r->step_size = 1.0 * config->inputtilt_speed / config->hertz;
	r->ramped_step_size = 0;
	s->low_value = config->stickytiltval1; // Value that defines where tilt will stick for both nose up and down. Can be made UI input later.
	s->high_value = config->stickytiltval2; // Value of 0 or above max disables. Max value <=  r->angle_limit. 
	s->hold_current = config->stickytilt_holdcurrent;
}

void reset_remote(RemoteData *r, StickyTiltData *s){
	s->active = false;
	r->inputtilt_interpolated = 0;
}
