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

#include "drop.h"
#include <math.h>
#include "utils_tnt.h"

void check_drop(DropData *drop, MotorData *m, RuntimeData *rt, State *state, DropDebug *drop_dbg){
	apply_angle_drop(drop, rt);
	//Conditions to engage drop
	if ((drop->accel_z < drop->z_limit) && 						// Compare accel z to drop limit with reduction for pitch and roll.
	 //   (state->sat != SAT_CENTERING) && 						// Not during startup
	    drop->last_accel_z - drop->accel_z >  - drop->min_diff &&  					// check that we are constantly dropping but allow for some noise
	    (rt->current_time - drop->timeroff > 0.5)) {				// Don't re-enter drop state for duration 	
		drop->count += 1;
		if (drop->count > drop->count_limit) { //&& 						// Counter used to reduce nuisance trips 
			if (!drop->active) { 						// Set the on timer only once per drop
				drop->timeron = rt->current_time; 	
				drop_dbg->debug4 = drop->accel_z;
				//drop_dbg->setpoint = rt->setpoint;
				if (rt->current_time - drop_dbg->aggregate_timer > 5) { // Aggregate the number of drop activations in 5 seconds
					drop_dbg->aggregate_timer = rt->current_time;
					drop_dbg->debug5 = 0;
				}
				drop_dbg->debug5 += 1;
			}
			drop->active = true;
		}
	} else { drop->count = 0; }							// reset
	
	// Conditions to end drop
	if (drop->active == true) {				
		drop_dbg->debug4 = min(drop_dbg->debug4, drop->accel_z); 	//record the lowest accel
		if (fabsf(m->accel_avg) > drop->motor_limit) { 	//Fastest reaction is hall sensor
			drop_deactivate(drop, drop_dbg, rt);
			drop_dbg->debug3 = m->accel_avg * drop->hertz / 1000;
		} else if (drop->last_accel_z - drop->accel_z <=  - drop->min_diff) {		// for fastest landing reaction with accelerometer check that we are still dropping
			drop_deactivate(drop, drop_dbg, rt);
			drop_dbg->debug3 = drop->accel_z;
		} else if (drop->accel_z > drop->z_limit) {
			drop_deactivate(drop, drop_dbg, rt);
			drop_dbg->debug3 = drop->accel_z;
		}
	}
	drop->last_accel_z = drop->accel_z;
}

void configure_drop(DropData *drop, const tnt_config *config){
	//drop->tiltback_step_size = config->tiltback_drop_speed / config->hertz;
	drop->z_limit = 0.95; // config->drop_z_accel;	// Value of accel z to initiate drop. A drop of about 6" / .1s produces about 0.9 accel y (normally 1)
	drop->motor_limit = 1000.0 * 10.0 / config->hertz; //ends drop via motor acceleration config->drop_motor_accel
	drop->count_limit = 10.0 * config->hertz / 832; //config->drop_count_limit;
	//drop->z_highlimit = config->drop_z_highaccel;
	drop->hertz = config->hertz;
	drop->min_diff = 0.0001;
}

void reset_drop(DropData *drop){
	drop->active = false;
	drop->deactivate = false;
	drop->count = 0;
	drop->accel_z = 1;
	drop->last_accel_z = 1;
	drop->applied_correction = 1;
	drop->timeroff = 0;
}

void drop_deactivate(DropData *drop, DropDebug *drop_dbg, RuntimeData *rt){
	drop->active = false;
	drop->deactivate = true;
	drop->timeroff = rt->current_time;
	drop->count = 0;
	drop_dbg->debug7 = drop->timeroff - drop->timeron;
	drop_dbg->debug6 = rt->pitch_angle;
	drop_dbg->max_time = max(drop_dbg->max_time, drop_dbg->debug7);
}

void apply_angle_drop(DropData *drop, RuntimeData *rt){
	float angle_correction = max(.1, min(10, 1 / (cosf(deg2rad(rt->roll_angle)) * cosf(deg2rad(rt->pitch_angle)))));		// Accel z is naturally reduced by the pitch and roll angles, so use geometry to compensate
	if (drop->applied_correction < angle_correction) {								// Accel z acts slower than pitch and roll so we need to delay accel z reduction as necessary
		drop->applied_correction = angle_correction ;							// Roll or pitch are increasing. Do not delay
	} else {
		ema(&drop->applied_correction, .001 * 832 / drop->hertz, angle_correction);			// Roll or pitch decreasing. Delay to allow accelerometer to keep pace	
	}
	drop->accel_z = rt->accel[2] * drop->applied_correction;
	/* TODO Another method that incorporates all accelerations but needs work on delay.
	float rad_pitch = deg2rad(rt->pitch_angle);
	float rad_roll =deg2rad(rt->roll_angle);
	float angle_factor = cosf(drop->pitch_delay) * cosf(drop->roll_delay);
	if (drop->last_angle_factor > angle_factor) {					// Accel z acts slower than pitch and roll so we need to delay accel z reduction as necessary
		drop->pitch_delay = rad_pitch;						// Roll or pitch are increasing. Do not delay
		drop->roll_delay = rad_roll;	
	} else {
		drop->pitch_delay = drop->pitch_delay* (1 - .001) + rad_pitch * .001;		// Roll or pitch decreasing. Delay to allow accelerometer to keep pace	
		drop->roll_delay = drop->roll_delay* (1 - .001) + rad_roll * .001;	
	}
	drop->last_angle_factor = angle_factor;

	drop->accel_z =  rt->accel[2] * angle_factor +  
		fabsf(rt->accel[1] * sinf(drop->roll_delay)) +  
		fabsf(rt->accel[0] * sinf(drop->pitch_delay)) ; */
}
