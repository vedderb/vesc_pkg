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
#include "runtime.h"

void check_traction(MotorData *m, TractionData *traction, State *state, tnt_config *config, PidData *p, TractionDebug *traction_dbg){
	float erpmfactor = fmaxf(1, lerp(0, config->wheelslip_scaleerpm, config->wheelslip_scaleaccel, 1, m->abs_erpm));
	bool start_condition1 = false;
	bool start_condition2 = false;
	float current_time = VESC_IF->system_time();
	rate_limit_erpm(m, traction);
	traction_dbg->debug2 = traction->erpm_limited;
	
	// Conditions to end traction control
	if (state->wheelslip) {
		if (current_time - traction->timeron > 1) {		// Time out at 1s
			deactivate_traction(traction, state, traction_dbg, m->abs_erpm, 5);
		} else if (fabsf(p->proportional) > config->wheelslip_max_angle) {
			deactivate_traction(traction, state, traction_dbg, m->abs_erpm, 4);
		} else if (state->braking_active) {
			deactivate_traction(traction, state, traction_dbg, m->abs_erpm, 6);
		} else {
			//This section determines if the wheel is acted on by outside forces by detecting acceleration direction change
			if (traction->highaccelon1) { 
				if (sign(traction->accelstartval) != sign(m->accel_filtered))
				// First we identify that the wheel has deccelerated due to traciton control, switching the sign
					traction->highaccelon1 = false;				
			} else if (sign(m->accel_filtered)!= sign(m->last_accel_filtered)) { 
			// Next we check to see if accel direction changes again from outside forces 
				deactivate_traction(traction, state, traction_dbg, m->abs_erpm, 1);
			}
			
			//This section determines if the wheel is acted on by outside forces by detecting acceleration magnitude
			if (traction->highaccelon2) {
				if (fabsf(m->accel_avg) < traction->slowed_accel) 	
					traction->highaccelon2 = false;		// First we identify that the wheel has deccelerated
			} else if (fabsf(m->accel_avg) > traction->end_accel) {
			// Next we check to see if accel magnitude increases from outside forces 
				deactivate_traction(traction, state, traction_dbg, m->abs_erpm, 2);
			}

			//If we wheelslipped backwards we just need to know the wheel is travelling forwards again
			if (traction->reverse_wheelslip && 
			    m->erpm_sign_check) {
				deactivate_traction(traction, state, traction_dbg, m->abs_erpm, 3);
			}
		}
	} else { //Start conditions and traciton control activation
		if (traction->end_accel_hold) { //Do not allow start conditions if we are in hold
			traction->end_accel_hold = fabsf(m->accel_avg) > traction->hold_accel; //deactivate hold when below the threshold acceleration
		} else { //Start conditions
			//Check motor erpm and acceleration to determine the correct detection condition to use if any
			if (m->erpm_sign == sign(m->erpm_at_accel_start)) { 								//Check sign of the motor at the start of acceleration 
				if (m->erpm_sign != sign(traction->erpm_limited)) {
					start_condition2 = sign(m->current) * m->accel_avg > traction->start_accel * erpmfactor &&	// The wheel has broken free indicated by abnormally high acceleration in the direction of motor current
			   		    !state->braking_pos_smooth && !state->braking_active;					// Do not apply for braking 				
				} else if (m->abs_erpm > fabsf(traction->erpm_limited) + config->wheelslip_erpm_margin) { 			//If signs the same check for magnitude increase
					start_condition1 = sign(m->current) * m->accel_avg > traction->start_accel * erpmfactor &&	// The wheel has broken free indicated by abnormally high acceleration in the direction of motor current
			  		    !state->braking_pos_smooth && !state->braking_active;					// Do not apply for braking 								
				} 
			} else if (sign(m->erpm_sign_soft) != sign(m->accel_avg)) {						// If the motor is back spinning engage but don't allow wheelslip on landing
				start_condition2 = sign(m->current) * m->accel_avg > traction->start_accel * erpmfactor &&	// The wheel has broken free indicated by abnormally high acceleration in the direction of motor current
			   	    !state->braking_pos_smooth && !state->braking_active;					// Do not apply for braking 
			}
		}
		
		// Initiate traction control
		if ((start_condition1 || start_condition2) && 			// Conditions false by default
		   ((current_time - traction->timeroff) * 1000 > config->wheelslip_resettime)) {	// Did not recently wheel slip.
			state->wheelslip = true;
			traction->accelstartval = m->accel_avg;
			traction->highaccelon1 = true;
			traction->highaccelon2 = true;
			traction->timeron = current_time;
			if (start_condition2)
				traction->reverse_wheelslip = true;

			//Debug Section
			if (current_time - traction_dbg->aggregate_timer > 5) { // Aggregate the number of drop activations in 5 seconds
				traction_dbg->aggregate_timer = current_time;
				traction_dbg->debug5 = 0;
				//traction_dbg->debug2 = erpmfactor;		//only record the first traction loss for some debug variables
				traction_dbg->debug6 = traction->erpm_limited;		//m->accel_avg / traction_dbg->freq_factor; 
				traction_dbg->debug9 = m->erpm;
				traction_dbg->debug3 = m->erpm_at_accel_start;
				traction_dbg->debug4 = 0;
				traction_dbg->debug8 = 0;
			}

			traction_dbg->debug5 += 1; // count number of traction losses
		}
	}
}

void reset_traction(TractionData *traction, State *state, BrakingData *braking) {
	state->wheelslip = false;
	traction->reverse_wheelslip = false;
	traction->end_accel_hold = false;
	braking->active = false; 
	braking->last_active = false;
}

void deactivate_traction(TractionData *traction, State *state, TractionDebug *traction_dbg, float abs_erpm, float exit) {
	state->wheelslip = false;
	traction->timeroff = VESC_IF->system_time();
	traction->reverse_wheelslip = false;
	traction->end_accel_hold = true; //activate high accel hold to prevent traction control
	if (traction_dbg->debug5 == 1) //only save the first activation duration
		traction_dbg->debug8 = traction->timeroff - traction->timeron;
	if (traction_dbg->debug4 > 10000) 
		traction_dbg->debug4 = traction_dbg->debug4 % 10000;
	traction_dbg->debug4 = traction_dbg->debug4 * 10 + exit; //aggregate the last traction deactivations
	
	if (exit == 2 && traction_dbg->debug8 > 0.05)
		traction_dbg->bonks_total++;
	if (exit > 0 && abs_erpm < 12000)	
		traction_dbg->max_time = max(traction_dbg->max_time, time);
}

void configure_traction(TractionData *traction, BrakingData *braking, tnt_config *config, TractionDebug *traction_dbg, BrakingDebug *braking_dbg){
	traction->start_accel = 1000.0 * config->wheelslip_accelstart / config->hertz; //convert from erpm/ms to erpm/cycle
	traction->slowed_accel = 1000.0 * config->wheelslip_accelslowed / config->hertz;
	traction->end_accel = 1000.0 * config->wheelslip_accelend / config->hertz;
	traction->hold_accel = 1000.0 * config->wheelslip_accelhold / config->hertz;
	traction_dbg->freq_factor = 1000.0 / config->hertz;
	braking_dbg->freq_factor = traction_dbg->freq_factor;
	traction->erpm_rate_limit = 1000.0 * config->wheelslip_erpm_rate_limit / config->hertz;
	traction->erpm_exclusion_rate = 1000.0 * config->wheelslip_erpm_exclusion_rate / config->hertz;
}

void check_traction_braking(BrakingData *braking, MotorData *m, State *state, tnt_config *config,
    float inputtilt_interpolated, PidData *pid, BrakingDebug *braking_dbg){
	float current_time = VESC_IF->system_time();
	braking_dbg->debug2 = m->i_batt;

	//Check that conditions for traciton braking are satisfied and add to counter
	if (state->braking_pos_smooth &&						// braking position active, IMU
	    m->erpm_sign * pid->new_pid_value < 0 &&					// braking current demand, IMU
	    m->i_batt < 0 &&								// Regeration current delivered to the battery
	    m->duty_cycle > 0 &&							// avoid transtion to active balancing
	    sign(m->vq) != sign(m->iq) &&						// braking, FOC
	    -inputtilt_interpolated * m->erpm_sign_soft >= config->tc_braking_angle && 	// Minimum nose down angle from remote, can be 0
	    !(state->wheelslip && config->is_traction_enabled) &&			// not currently in traction control
	    m->abs_erpm > config->tc_braking_min_erpm) {				// Minimum speed threshold
		state->braking_active = true;
		
		//Debug Section
		if (current_time - braking_dbg->aggregate_timer > 5) { // Reset these values after we have not braked for a few seconds
			braking_dbg->debug5 = 0;
			braking_dbg->debug8 = 0;
			braking_dbg->debug6 = 0;
			braking_dbg->debug4 = 0;
			braking_dbg->debug1 = 0;
			braking_dbg->debug3 = m->abs_erpm;
			braking_dbg->debug9 = 0;
		}
		braking_dbg->aggregate_timer = current_time;
		if (!braking->last_active) // Just entered traction braking, reset
			braking->timeron = current_time;
		braking_dbg->debug6 = max(braking_dbg->debug6, fabsf(m->accel_avg / braking_dbg->freq_factor));
		braking_dbg->debug9 = max(braking_dbg->debug9, m->abs_erpm);
		braking_dbg->debug3 = min(braking_dbg->debug3, m->abs_erpm);	
		braking_dbg->debug8 = current_time - braking->timeron + braking_dbg->debug1; //running on time tracker
	} else { 
		state->braking_active = false; 

		//Debug Section
		if (braking->last_active) {
			braking->timeroff = current_time;
			braking_dbg->debug1 += braking->timeroff - braking->timeron; //sum all activation times
			braking_dbg->debug8 = braking_dbg->debug1; //deactivated on time tracker
		
			if (braking_dbg->debug4 > 10000)  //Save 5 of the most recent deactivation reasons
				braking_dbg->debug4 = braking_dbg->debug4 % 10000;
			
			if (-inputtilt_interpolated * m->erpm_sign < config->tc_braking_angle) {
				braking_dbg->debug4 = braking_dbg->debug4 * 10 + 1;
			} else if (m->i_batt >= 0) {
				braking_dbg->debug4 = braking_dbg->debug4 * 10 + 2;
			} else if (m->duty_cycle <= 0) {
				braking_dbg->debug4 = braking_dbg->debug4 * 10 + 3;
			} else if (sign(m->vq) == sign(m->iq)) {
				braking_dbg->debug4 = braking_dbg->debug4 * 10 + 4;
			} else if (m->abs_erpm < config->tc_braking_min_erpm) {
				braking_dbg->debug4 = braking_dbg->debug4 * 10 + 5;
			} else if (!state->braking_pos_smooth) {
				braking_dbg->debug4 = braking_dbg->debug4 * 10 + 6;
			} else if (m->erpm_sign * pid->new_pid_value >= 0) {
				braking_dbg->debug4 = braking_dbg->debug4 * 10 + 7;
			}

			if (braking_dbg->debug5 > 10000)  //Save 5 of the most recent deactivation reasons
				braking_dbg->debug5 = braking_dbg->debug5 % 10000;

			if (braking->timeroff - braking->timeron > 1) //Only save end conditions from braking period greater than 1 seconds
				braking_dbg->debug5 = braking_dbg->debug5 * 10 + braking_dbg->debug4 % 10;
		}
	}
	braking->last_active = state->braking_active;
}

void rate_limit_erpm(MotorData *m, TractionData *traction) {
	//ERPM limited attempts to better estimate longitudinal velocity by limiting the rate of change and not changing when acceleration is too high.
	rate_limitf(&traction->erpm_limited, m->erpm, m->accel_avg > traction->erpm_exclusion_rate ? 0 : traction->erpm_rate_limit); 
}
