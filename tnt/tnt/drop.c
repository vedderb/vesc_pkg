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
	//Detects high acceleration to prevent drop in pump track situations
	if (drop->accel_z > drop->z_highlimit) {
		drop->highcount += 1;
		if (drop->highcount > drop->count_limit) {
			drop->high_accel_timer = rt->current_time;
		}	
	}
	
	//Conditions to engage drop
	if ((drop->accel_z < drop->z_limit) && 						// Compare accel z to drop limit with reduction for pitch and roll.
	    (rt->last_accel_z >= rt->accel[2]) &&  					// check that we are constantly dropping
	    (state->sat != SAT_CENTERING) && 						// Not during startup
	    (rt->current_time - drop->timeroff > 0.02)) {				// Don't re-enter drop state for duration 	
		drop->count += 1;
		if (drop->count == 1) {
			drop_dbg->temp_timeron = rt->current_time;
		}
		
		if (drop->count > drop->count_limit) {					// Counter used to reduce nuisance trips
			if (rt->current_time - drop->high_accel_timer > 0.5) {			// Have not experienced high accel recently
				if (!drop->active) { 						// Set the on timer only once per drop
					drop->timeron = drop_dbg->temp_timeron;
					//drop_dbg->debug5 = drop->applied_correction;
					drop_dbg->debug4 = drop->accel_z;
				}
				drop->active = true;
				drop_dbg->debug4 = min(drop_dbg->debug4, drop->accel_z); 	//record the lowest accel
			} else { 
				drop_dbg->debug1 = rt->current_time; 				//Update to indicate recent drop prevention
				drop->count = 0
			}				
		}
	} else { drop->count = 0; }							// reset
	
	// Conditions to end drop
	if (drop->active == true) {					
		if (fabsf(m->acceleration) > drop->motor_limit) { 	//Fastest reaction is hall sensor
			drop_deactivate(drop, drop_dbg, rt);
			drop_dbg->debug3 = m->acceleration;
		} else if (rt->last_accel_z <= rt->accel[2]) {		// for fastest landing reaction with accelerometer check that we are still dropping
			drop_deactivate(drop, drop_dbg, rt);
			drop_dbg->debug3 = rt->accel[2];
		}
	}
}

void configure_drop(DropData *drop, const tnt_config *config){
	drop->tiltback_step_size = config->tiltback_drop_speed / config->hertz;
	drop->z_limit = config->drop_z_accel;	// Value of accel z to initiate drop. A drop of about 6" / .1s produces about 0.9 accel y (normally 1)
	drop->motor_limit = config->drop_motor_accel; //ends drop via motor acceleration
	drop->count_limit = config->drop_count_limit;
	drop->z_highlimit = config->drop_z_highaccel;
}

void reset_drop(DropData *drop){
	drop->active = false;
	drop->deactivate = false;
	drop->count = 0;
}

void drop_deactivate(DropData *drop, DropDebug *drop_dbg, RuntimeData *rt){
	drop->active = false;
	drop->deactivate = true;
	drop->timeroff = rt->current_time;
	drop->count = 0;
	drop_dbg->debug7 = drop->timeroff - drop_dbg->temp_timeron;
	drop_dbg->debug6 = rt->proportional;
}

void apply_angle_drop(DropData *drop, RuntimeData *rt){
	float angle_correction = 1 / (cosf(deg2rad(rt->roll_angle)) * cosf(deg2rad(rt->pitch_angle)));			// Accel z is naturally reduced by the pitch and roll angles, so use geometry to compensate
	if (drop->applied_correction < angle_correction) {								// Accel z acts slower than pitch and roll so we need to delay accel z reduction as necessary
		drop->applied_correction = angle_correction ;							// Roll or pitch are increasing. Do not delay
	} else {
		drop->applied_correction = drop->applied_correction * (1 - .001) + angle_correction * .001;		// Roll or pitch decreasing. Delay to allow accelerometer to keep pace	
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
