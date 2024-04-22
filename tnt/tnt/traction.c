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

#include "traction.h"
#include <math.h>
#include "utils_tnt.h"

void check_traction(MotorData *m, TractionData *traction, State *state, RuntimeData *rt, tnt_config *config, TractionDebug *traction_dbg){
	float erpmfactor = config->wheelslip_scaleaccel - min(config->wheelslip_scaleaccel - 1, (config->wheelslip_scaleaccel -1) * ( m->abs_erpm / config->wheelslip_scaleerpm));
	bool erpm_check;
	
	// Conditons to end traction control
	if (state->wheelslip) {
		if (rt->current_time - traction->timeron > .5) {		// Time out at 500ms
			state->wheelslip = false;
			traction->timeroff = rt->current_time;
			traction_dbg->debug4 = 5000;
			traction_dbg->debug8 = m->acceleration;
		} else {
			//This section determines if the wheel is acted on by outside forces by detecting acceleration direction change
			if (traction->highaccelon2) { 
				if (sign(traction->accelstartval) != sign(m->accel_history[m->accel_idx])) { 
				// First we identify that the wheel has deccelerated due to traciton control, switching the sign
					traction->highaccelon2 = false;				
					traction_dbg->debug1 = rt->current_time - traction->timeron;
				} else if (rt->current_time - traction->timeron > .18) {	// Time out at 150ms if wheel does not deccelerate
					state->wheelslip = false;
					traction->timeroff = rt->current_time;
					traction_dbg->debug4 = 1800;
					traction_dbg->debug8 = m->acceleration;
				}
			} else if (sign(m->accel_history[m->accel_idx])!= sign(m->accel_history[m->last_accel_idx])) { 
			// Next we check to see if accel direction changes again from outside forces 
				state->wheelslip = false;
				traction->timeroff = rt->current_time;
				traction_dbg->debug4 = m->accel_history[m->last_accel_idx];
				traction_dbg->debug8 = m->accel_history[m->accel_idx];	
			}
			//This section determines if the wheel is acted on by outside forces by detecting acceleration magnitude
			if (state->wheelslip) { // skip this if we are already out of wheelslip to preserve debug values
				if (traction->highaccelon1) {		
					if (sign(traction->accelstartval) * m->acceleration < config->wheelslip_accelend) {	
					// First we identify that the wheel has deccelerated due to traciton control
						traction->highaccelon1 = false;
						traction_dbg->debug7 = rt->current_time - traction->timeron;
					} else if (rt->current_time - traction->timeron > .2) {	// Time out at 200ms if wheel does not deccelerate
						state->wheelslip = false;
						traction->timeroff = rt->current_time;
						traction_dbg->debug4 = 2000;
						traction_dbg->debug8 = m->acceleration;
					}
				} else if (fabsf(m->acceleration) > config->wheelslip_margin) { 
				// If accel increases by a value higher than margin, the wheel is acted on by outside forces so we presumably have traction again
					state->wheelslip = false;
					traction->timeroff = rt->current_time;
					traction_dbg->debug4 = 2222;
					traction_dbg->debug8 = m->acceleration;		
				}
			}
		}
	}	
	
	if (m->abs_erpm == sign(m->erpm_history[m->last_erpm_idx])) { 	// We check sign to make sure erpm is increasing or has changed direction. 
		if (m->abs_erpm > fabsf(m->erpm_history[m->last_erpm_idx])) {
			erpm_check = true;
		} else {erpm_check = false;} 					//If the erpm suddenly decreased without changing sign that is a false positive. Do not enter traction control.
	} else if (sign(m->erpm_sign_soft) != sign(m->acceleration)) {		// The wheel has changed direction and if these are the same sign we do not want traciton conrol because we likely just landed with high wheel spin
		erpm_check = true;
	} else {erpm_check = false;}
		
		
	// Initiate traction control
	if ((sign(m->current) * m->acceleration > config->wheelslip_accelstart * erpmfactor) && 	// The wheel has broken free indicated by abnormally high acceleration in the direction of motor current
	   (!state->wheelslip) &&									// Not in traction control
	   (sign(m->current) == sign(m->accel_history[m->accel_idx])) &&				// a more precise condition than the first for current direction and erpm - last erpm
	   (!state->braking_pos) &&									// Do not apply for braking because once we lose traction braking the erpm will change direction and the board will consider it acceleration anyway
	   (rt->current_time - traction->timeroff > .02) && 						// Did not recently wheel slip.
	   (erpm_check)) {
		state->wheelslip = true;
		traction->accelstartval = m->acceleration;
		traction->highaccelon1 = true; 	
		traction->highaccelon2 = true; 	
		traction->timeron = rt->current_time;
		traction_dbg->debug6 = m->acceleration;
		traction_dbg->debug3 = m->erpm_history[m->last_erpm_idx];
		traction_dbg->debug1 = 0;
		traction_dbg->debug2 = erpmfactor;
		traction_dbg->debug4 = 0;
		traction_dbg->debug8 = 0;
		traction_dbg->debug9 = m->erpm;
	}
}


