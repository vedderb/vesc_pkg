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
	float erpmfactor = fmaxf(1, lerp(0, config->wheelslip_scaleerpm, config->wheelslip_scaleaccel, 1, m->abs_erpm));
	bool erpm_check;
	bool start_condition1 = false;
	bool start_condition2 = false;
	traction->last_accel_rate = traction->accel_rate;
	traction->accel_rate = m->accel_history[m->accel_idx] - m->accel_history[m->last_accel_idx];
	
	// Conditons to end traction control
	if (state->wheelslip) {
		if (rt->current_time - traction->timeron > .3) {		// Time out at 300ms
			traction_dbg->debug4 = 3000;
			deactivate_traction(m, traction, state, rt, traction_dbg);
		} else {
			//This section determines if the wheel is acted on by outside forces by detecting acceleration direction change
			if (traction->highaccelon2) { 
				if (sign(traction->accelstartval) != sign(m->accel_history[m->accel_idx])) { 
				// First we identify that the wheel has deccelerated due to traciton control, switching the sign
					traction->highaccelon2 = false;				
					traction_dbg->debug1 = rt->current_time - traction->timeron;
				} else if (rt->current_time - traction->timeron > .18) {	// Time out at 150ms if wheel does not deccelerate
					traction_dbg->debug4 = 1800;
					deactivate_traction(m, traction, state, rt, traction_dbg);
				}
			} else if (sign(m->accel_history[m->accel_idx])!= sign(m->accel_history[m->last_accel_idx])) { 
			// Next we check to see if accel direction changes again from outside forces 
				traction_dbg->debug4 = 3333; //m->accel_history[m->last_accel_idx];
				deactivate_traction(m, traction, state, rt, traction_dbg);
			}
			
			//This section determines if the wheel is acted on by outside forces by detecting acceleration magnitude
			if (traction->highaccelon1) {		
				if (sign(traction->accelstartval) * m->acceleration < traction->slowed_accel) {	
				// First we identify that the wheel has deccelerated due to traciton control
					traction->highaccelon1 = false;
					traction_dbg->debug7 = rt->current_time - traction->timeron;
				} else if (rt->current_time - traction->timeron > .2) {	// Time out at 200ms if wheel does not deccelerate
					traction_dbg->debug4 = 2000;
					deactivate_traction(m, traction, state, rt, traction_dbg);
				}
			} else if (fabsf(traction->accel_rate - traction->last_accel_rate) > traction->end_accel_rate) { 
			// If accel increases by a value higher than margin, the wheel is acted on by outside forces so we presumably have traction again
				traction_dbg->debug4 = traction->accel_rate - traction->last_accel_rate;
				deactivate_traction(m, traction, state, rt, traction_dbg);
			}

			//If we wheelslipped backwards we just need to know the wheel is travelling forwards again
			if (traction->reverse_wheelslip && m->erpm_sign == m->erpm_sign_soft) {
				traction_dbg->debug4 = 2222;
				deactivate_traction(m, traction, state, rt, traction_dbg);
			}
		}
	}	
	
	if (m->erpm_sign == sign(m->erpm_history[m->last_erpm_idx])) { 	// We check sign to make sure erpm is increasing or has changed direction. 
		if (m->abs_erpm > fabsf(m->erpm_history[m->last_erpm_idx])) {
			erpm_check = true;
			start_condition1 = sign(m->current) * m->acceleration > traction->start_accel * erpmfactor;
		} else {erpm_check = false;} 					//If the erpm suddenly decreased without changing sign that is a false positive. Do not enter traction control.
	} else if (sign(m->erpm_sign_soft) != sign(m->accel_history[m->accel_idx])) {		// The wheel has changed direction and if these are the same sign we do not want traciton conrol because we likely just landed with high wheel spin
		erpm_check = true;
		traction->reverse_wheelslip = true;
		start_condition1 = sign(m->current) * m->acceleration > traction->start_accel * erpmfactor;
		start_condition2 = sign(m->current) * m->accel_history[m->accel_idx] > traction->start_accel * erpmfactor * 1.5; //use a faster reaction if wheel changes direction
	} else {erpm_check = false;}

	// Initiate traction control
	if ((start_condition1 || start_condition2) && 									// The wheel has broken free indicated by abnormally high acceleration in the direction of motor current
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
		
		//Debug Section
		traction_dbg->debug2 = start_condition2 ? erpmfactor * 1.5 : erpmfactor;
		traction_dbg->debug6 = start_condition2 ? m->accel_history[m->accel_idx] : m->acceleration;
		traction_dbg->debug9 = m->erpm;
		traction_dbg->debug3 = m->erpm_history[m->last_erpm_idx];
		traction_dbg->debug1 = 0;
		traction_dbg->debug4 = 0;
		traction_dbg->debug8 = 0;
		if (rt->current_time - traction_dbg->aggregate_timer > 5) { // Aggregate the number of drop activations in 5 seconds
			traction_dbg->aggregate_timer = rt->current_time;
			traction_dbg->debug5 = 0;
		}
		traction_dbg->debug5 += 1;
	}
}

void reset_traction(TractionData *traction, State *state) {
	state->wheelslip = false;
	traction->reverse_wheelslip = false;
}

void deactivate_traction(MotorData *m, TractionData *traction, State *state, RuntimeData *rt, TractionDebug *traction_dbg) {
	state->wheelslip = false;
	traction->timeroff = rt->current_time;
	traction->reverse_wheelslip = false;
	traction_dbg->debug8 = m->acceleration;
}

void configure_traction(TractionData *traction, tnt_config *config){
	float hertz = config->hertz;
	traction->start_accel = 1.0 * config->wheelslip_accelstart / hertz * 1000.0;
	traction->slowed_accel = 1.0 * config->wheelslip_accelend / hertz * 1000.0;
	traction->end_accel_rate = 1.0 * (float)config->wheelslip_margin / (hertz * hertz) * 1000000.0;
}
