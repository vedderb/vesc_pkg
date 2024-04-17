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

#include "high_current.h"
#include "vesc_c_if.h"

void check_surge(data *d){
	//Start Surge Code
	//Initialize Surge Cycle
	if ((d->motor.current_avg * d->motor.erpm_sign > d->surge.start_current) && 	//High current condition 
	     (d->surge.high_current) && 						//If overcurrent is triggered this satifies traction control, min erpm, braking, centering and direction
	     (d->motor.duty_cycle < 0.8) &&						//Prevent surge when pushing top speed
	     (d->current_time - d->surge.timer > 0.7)) {				//Not during an active surge period			
		d->surge.timer = d->current_time; 					//Reset surge timer
		d->surge.state = true; 							//Indicates we are in the surge cycle of the surge period
		d->surge.setpoint = d->setpoint;					//Records setpoint at the start of surge because surge changes the setpoint
		d->surge.new_duty_cycle = d->motor.erpm_sign * d->motor.duty_cycle;
		
		//Debug Data Section
		d->debug13 = d->proportional;				
		d->debug5 = 0;
		d->debug16 = 0;
		d->debug18 = 0;
		d->debug17 = d->motor.current_avg;
		d->debug14 = 0;
		d->debug15 = d->surge.start_current;
		d->debug19 = d->motor.duty_cycle;
	}
	
	//Conditions to stop surge and increment the duty cycle
	if (d->surge.state){	
		d->surge.new_duty_cycle += d->motor.erpm_sign * d->surge.ramp_rate; 	
		if((d->current_time - d->surge.timer > 0.5) ||								//Outside the surge cycle portion of the surge period
		 (-1 * (d->surge.setpoint - d->pitch_angle) * d->motor.erpm_sign > d->tnt_conf.surge_maxangle) ||	//Limit nose up angle based on the setpoint at start of surge because surge changes the setpoint
		 (d->state.wheelslip)) {										//In traction control		
			d->surge = false;
			d->surge.state_off = true;								//Identifies the end of surge to change the setpoint back to before surge 
			d->pid_value = VESC_IF->mc_get_tot_current_directional_filtered();			//This allows a smooth transition to PID current control
			
			//Debug Data Section
			d->debug5 = d->current_time - d->surge.timer;						//Register how long the surge cycle lasted
			d->debug18 = d->motor.duty_cycle - d->debug19;						//Added surge duty
			d->debug14 = d->debug18 / (d->current_time - d->surge.timer) * 100;			//Surge ramp rate
			if (d->current_time - d->surge.timer >= 0.5) {						//End condition
				d->debug16 = 111;
			} else if (-1 * (d->surge.setpoint - d->pitch_angle) * d->motor.erpm_sign > d->tnt_conf.surge_maxangle){
				d->debug16 = d->pitch_angle;
			} else if (d->state.wheelslip){
				d->debug16 = 222;
			}
		}
	}
}

void check_current(data *d){
	float scale_start_current = lerp(d->tnt_conf.surge_scaleduty/100, .95, d->tnt_conf.surge_startcurrent, d->tnt_conf.surge_start_hd_current, d->motor.duty_cycle);
	d->surge.start_current = min(d->tnt_conf.surge_startcurrent, scale_start_current); 
	if ((d->motor.current_avg * d->motor.erpm_sign > d->surge.start_current - d->tnt_conf.overcurrent_margin) && 	//High current condition 
	     (!d->state.braking_pos) && 											//Not braking
	     (!d->state.wheelslip) &&											//Not during traction control
	     (d->motor.abs_erpm > d->tnt_conf.surge_minerpm) &&								//Above the min erpm threshold
	     (d->motor.erpm_sign_check) &&										//Prevents surge if direction has changed rapidly, like a situation with hard brake and wheelslip
	     (d->state.sat != SAT_CENTERING)) { 									//Not during startup
		// High current, just haptic buzz don't actually limit currents
		d->surge.high_current = true;
		if (d->current_time - d->surge.high_current_timer < d->tnt_conf.overcurrent_period) {			//Limit haptic buzz duration
			d->surge.high_current_buzz = true;
		} else {d->surge.high_current_buzz = false;}
	} else { 
		d->surge.high_current_buzz = false;
		d->surge.high_current = false;
		d->surge.high_current_timer = d->current_time; 
	} 
}

