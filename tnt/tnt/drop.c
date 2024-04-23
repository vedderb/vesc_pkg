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
	float accel_z_reduction = cosf(deg2rad(rt->roll_angle)) * cosf(deg2rad(rt->pitch_angle));			// Accel z is naturally reduced by the pitch and roll angles, so use geometry to compensate
	if (drop->applied_accel_z_reduction > accel_z_reduction) {							// Accel z acts slower than pitch and roll so we need to delay accel z reduction as necessary
		drop->applied_accel_z_reduction = accel_z_reduction ;							// Roll or pitch are increasing. Do not delay
	} else {
		drop->applied_accel_z_reduction = drop->applied_accel_z_reduction * .999 + accel_z_reduction * .001;	// Roll or pitch decreasing. Delay to allow accelerometer to keep pace	
	}
	
	if ((rt->accel[2] < drop->z_limit * drop->applied_accel_z_reduction) && 	// Compare accel z to drop limit with reduction for pitch and roll.
	    (rt->last_accel_z >= rt->accel[2]) &&  					// check that we are still dropping
	    (state->sat != SAT_CENTERING) && 						//Not during startup
	    (rt->current_time - drop->timeroff > 0.02)) {				// Don't re-enter drop state for duration 	
		drop->count += 1;
		if (drop->count > drop->count_limit) {					// Counter used to reduce nuisance trips
			if (!drop->active) { 						// Set the on timer only once per drop
				drop->timeron = rt->current_time;
				drop_dbg->debug5 = rt->pitch_angle;
			}
			drop->active = true;
			drop_dbg->debug4 = min(drop_dbg->debug4, rt->accel[2]); 	//record the lowest accel
		}
	} else { drop->count = 0; }							// reset
	
	if (drop->active == true) {					
		if (fabsf(m->acceleration) > drop->motor_limit) { 	//Fastest reaction is hall sensor
			drop_deactivate(&drop);
			drop_dbg->debug1 = m->acceleration;
		} else if (rt->last_accel_z <= rt->accel[2]) {		// for fastest landing reaction with accelerometer check that we are still dropping
			drop_deactivate(&drop);
			drop_dbg->debug1 = rt->accel[2];
		}
	}

}

void configure_drop(DropData *drop, tnt_config *config){
	drop->tiltback_step_size = config->tiltback_drop_speed / config->hertz;
	drop->z_limit = config->drop_z_accel;	// Value of accel z to initiate drop. A drop of about 6" / .1s produces about 0.9 accel y (normally 1)
	drop->motor_limit = config->drop_motor_accel; //ends drop via motor acceleration
	drop->count_limit = config->drop_count_limit;
}

void reset_drop(DropData *drop){
	drop->active = false;
	drop->deactivate = false;
	drop->count = 0;
}

void drop_deactivate(DropData *drop, DropDebug *drop_dbg){
	drop->active = false;
	drop->deactivate = true;
	drop->timeroff = rt->current_time;
	drop_dbg->debug3 = drop->count;
	drop->count = 0;
	drop_dbg->debug2 = drop->timeroff - drop->timeron;
	drop_dbg->debug6 = rt->pitch_angle;
}
