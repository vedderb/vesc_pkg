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

static void check_traction(data *d){
	float erpmfactor = d->tnt_conf.wheelslip_scaleaccel - min(d->tnt_conf.wheelslip_scaleaccel - 1, (d->tnt_conf.wheelslip_scaleaccel -1) * ( d->motor.abs_erpm / d->tnt_conf.wheelslip_scaleerpm));
	bool erpm_check;
	
	// Conditons to end traction control
	if (d->state.wheelslip) {
		if (d->current_time - d->drop.timeroff < 0.5) {		// Drop has ended recently
			d->state.wheelslip = false;
			d->traction.timeroff = d->current_time;
			d->debug4 = 6666;
			d->debug8 = d->motor.acceleration;
		} else	if (d->current_time - d->traction.timeron > .5) {		// Time out at 500ms
			d->state.wheelslip = false;
			d->traction.timeroff = d->current_time;
			d->debug4 = 5000;
			d->debug8 = d->motor.acceleration;
		} else {
			//This section determines if the wheel is acted on by outside forces by detecting acceleration direction change
			if (d->traction.highaccelon2) { 
				if (sign(d->traction.accelstartval) != sign(d->motor.accel_history[d->motor.accel_idx])) { 
				// First we identify that the wheel has deccelerated due to traciton control, switching the sign
					d->traction.highaccelon2 = false;				
					d->debug1 = d->current_time - d->traction.timeron;
				} else if (d->current_time - d->traction.timeron > .18) {	// Time out at 150ms if wheel does not deccelerate
					d->state.wheelslip = false;
					d->traction.timeroff = d->current_time;
					d->debug4 = 1800;
					d->debug8 = d->motor.acceleration;
				}
			} else if (sign(d->motor.accel_history[d->motor.accel_idx])!= sign(d->motor.accel_history[d->motor.last_accel_idx])) { 
			// Next we check to see if accel direction changes again from outside forces 
				d->state.wheelslip = false;
				d->traction.timeroff = d->current_time;
				d->debug4 = d->motor.accel_history[d->motor.last_accel_idx];
				d->debug8 = d->motor.accel_history[d->motor.accel_idx];	
			}
			//This section determines if the wheel is acted on by outside forces by detecting acceleration magnitude
			if (d->state.wheelslip) { // skip this if we are already out of wheelslip to preserve debug values
				if (d->traction.highaccelon1) {		
					if (sign(d->traction.accelstartval) * d->motor.acceleration < d->tnt_conf.wheelslip_accelend) {	
					// First we identify that the wheel has deccelerated due to traciton control
						d->traction.highaccelon1 = false;
						d->debug7 = d->current_time - d->traction.timeron;
					} else if (d->current_time - d->traction.timeron > .2) {	// Time out at 200ms if wheel does not deccelerate
						d->state.wheelslip = false;
						d->traction.timeroff = d->current_time;
						d->debug4 = 2000;
						d->debug8 = d->motor.acceleration;
					}
				} else if (fabsf(d->motor.acceleration) > d->tnt_conf.wheelslip_margin) { 
				// If accel increases by a value higher than margin, the wheel is acted on by outside forces so we presumably have traction again
					d->state.wheelslip = false;
					d->traction.timeroff = d->current_time;
					d->debug4 = 2222;
					d->debug8 = d->motor.acceleration;		
				}
			}
		}
	}	
	if (sign(d->motor.erpm) == sign(d->motor.erpm_history[d->motor.last_erpm_idx])) { // We check sign to make sure erpm is increasing or has changed direction. 
		if (d->motor.abs_erpm > fabsf(d->motor.erpm_history[d->motor.last_erpm_idx])) {
			erpm_check = true;
		} else {erpm_check = false;} //If the erpm suddenly decreased without changing sign that is a false positive. Do not enter traction control.
	} else if (sign(d->motor.erpm_sign_soft) != sign(d->motor.acceleration)) { // The wheel has changed direction and if these are the same sign we do not want traciton conrol because we likely just landed with high wheel spin
		erpm_check = true;
	} else {erpm_check = false;}
		
		
	// Initiate traction control
	if ((sign(d->motor.current) * d->motor.acceleration > d->tnt_conf.wheelslip_accelstart * erpmfactor) && 	// The wheel has broken free indicated by abnormally high acceleration in the direction of motor current
	   (!d->state.wheelslip) &&									// Not in traction control
	   (sign(d->motor.current) == sign(d->motor.accel_history[d->motor.accel_idx])) &&				// a more precise condition than the first for current dirrention and erpm - last erpm
	   (!d->braking_pos) &&							// Do not apply for braking because once we lose traction braking the erpm will change direction and the board will consider it acceleration anyway
	   (d->current_time - d->traction.timeroff > .2) && 						// Did not recently wheel slip.
	   (erpm_check)) {
		d->state.wheelslip = true;
		d->traction.accelstartval = d->motor.acceleration;
		d->traction.highaccelon1 = true; 	
		d->traction.highaccelon2 = true; 	
		d->traction.timeron = d->current_time;
		d->debug6 = d->motor.acceleration;
		d->debug3 = d->motor.erpm_history[d->motor.last_erpm_idx];
		d->debug1 = 0;
		d->debug2 = erpmfactor;
		d->debug4 = 0;
		d->debug8 = 0;
		d->debug9 = d->motor.erpm;
	}
}

static void check_drop(data *d){
	float accel_z_reduction = cosf(deg2rad(d->roll_angle)) * cosf(deg2rad(d->pitch_angle));		// Accel z is naturally reduced by the pitch and roll angles, so use geometry to compensate
	if (d->applied_accel_z_reduction > accel_z_reduction) {							// Accel z acts slower than pitch and roll so we need to delay accel z reduction as necessary
		d->applied_accel_z_reduction = accel_z_reduction ;						// Roll or pitch are increasing. Do not delay
	} else {
		d->applied_accel_z_reduction = d->applied_accel_z_reduction * .999 + accel_z_reduction * .001;	// Roll or pitch decreasing. Delay to allow accel z to keep pace	
	}
	d->drop.limit = 0.92;	// Value of accel z to initiate drop. A drop of about 6" / .1s produces about 0.9 accel y (normally 1)
	if ((d->accel[2] < d->drop.limit * d->applied_accel_z_reduction) && 	// Compare accel z to drop limit with reduction for pitch and roll.
	    (d->last_accel_z >= d->accel[2]) &&  			// for fastest landing reaction check that we are still dropping
	    (d->current_time - d->drop.timeroff > 0.5)) {	// Don't re-enter drop state for duration 	
		d->drop.count += 1;
		if (d->drop.count > 5) {			// Counter used to reduce nuisance trips
			d->drop.state = true;
			if (d->current_time - d->drop.timeron > 3) { // Set the on timer only if it is well past what is normal so it only sets once
				d->drop.timeron = d->current_time;
			}
		}
	} else if (d->drop.state == true) {		// If any conditions are not met while in drop state, exit drop state
		d->drop.state = false;
		d->drop.timeroff = d->current_time;
		d->drop.count = 0;		// reset
	} else {
		d->drop.state = false;		// Out of drop state by default
		d->drop.count = 0;		// reset
	}
}
