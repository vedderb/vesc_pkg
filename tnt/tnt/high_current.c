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
#include "utils_tnt.h"

void check_surge(MotorData *m, SurgeData *surge, State *state, RuntimeData *rt, tnt_config *config, SurgeDebug *surge_dbg){
	//Start Surge Code
	//Initialize Surge Cycle
	if ((m->current_avg * m->erpm_sign > surge->start_current) && 	//High current condition 
	     (surge->high_current) && 							//If overcurrent is triggered this satifies traction control, min erpm, braking, centering and direction
	     (m->duty_cycle < 0.8) &&						//Prevent surge when pushing top speed
	     (rt->current_time - surge->timer > 0.7)) {					//Not during an active surge period			
		surge->timer = rt->current_time; 					//Reset surge timer
		surge->active = true; 							//Indicates we are in the surge cycle of the surge period
		surge->setpoint = rt->setpoint;						//Records setpoint at the start of surge because surge changes the setpoint
		surge->new_duty_cycle = m->erpm_sign * m->duty_cycle;
		
		//Debug Data Section
		surge_dbg->debug1 = rt->proportional;				
		surge_dbg->debug2 = m->current_avg;
		surge_dbg->debug3 = surge->start_current;
		surge_dbg->debug4 = m->duty_cycle;
		surge_dbg->debug5 = 0;
		surge_dbg->debug6 = 0;
		surge_dbg->debug7 = 0;
		surge_dbg->debug8 = 0;
	}
	
	//Conditions to stop surge and increment the duty cycle
	if (surge->active){	
		surge->new_duty_cycle += m->erpm_sign * surge->ramp_rate; 	
		if((rt->current_time - surge->timer > 0.5) ||								//Outside the surge cycle portion of the surge period
		 (-1 * (surge->setpoint - rt->pitch_angle) * m->erpm_sign > config->surge_maxangle) ||	//Limit nose up angle based on the setpoint at start of surge because surge changes the setpoint
		 (state->wheelslip)) {										//In traction control		
			surge->active = false;
			surge->deactivate = true;								//Identifies the end of surge to change the setpoint back to before surge 
			rt->pid_value = VESC_IF->mc_get_tot_current_directional_filtered();			//This allows a smooth transition to PID current control
			
			//Debug Data Section
			surge_dbg->debug7 = rt->current_time - surge->timer;						//Register how long the surge cycle lasted
			surge_dbg->debug5 = m->duty_cycle - surge_dbg->debug4;						//Added surge duty
			surge_dbg->debug8 = surge_dbg->debug5/ (rt->current_time - surge->timer) * 100;			//Surge ramp rate
			if (rt->current_time - surge->timer >= 0.5) {						//End condition
				surge_dbg->debug6 = 111;
			} else if (-1 * (surge->setpoint - rt->pitch_angle) * m->erpm_sign > config->surge_maxangle){
				surge_dbg->debug6 = rt->pitch_angle;
			} else if (state->wheelslip){
				surge_dbg->debug6 = 222;
			}
		}
	}
}

void check_current(MotorData *m, SurgeData *surge, State *state, RuntimeData *rt, tnt_config *config) {
	float scale_start_current = lerp(surge_scaleduty/100, .95, config->surge_startcurrent, config->surge_start_hd_current, m->duty_cycle);
	surge->start_current = min(config->surge_startcurrent, scale_start_current); 
	if ((m->current_avg * m->erpm_sign > surge->start_current - config->overcurrent_margin) && 	//High current condition 
	     (!state->braking_pos) && 								//Not braking
	     (!state->wheelslip) &&									//Not during traction control
	     (m->abs_erpm > surge_minerpm) &&								//Above the min erpm threshold
	     (m->erpm_sign_check) &&									//Prevents surge if direction has changed rapidly, like a situation with hard brake and wheelslip
	     (state->sat != SAT_CENTERING)) { 							//Not during startup
		// High current, just haptic buzz don't actually limit currents
		surge->high_current = true;
		if (rt->current_time - surge->high_current_timer < config->overcurrent_time) {		//Limit haptic buzz duration
			surge->high_current_buzz = true;
		} else {surge->high_current_buzz = false;}
	} else { 
		surge->high_current_buzz = false;
		surge->high_current = false;
		surge->high_current_timer = rt->current_time; 
	} 
}

void configure_surge(SurgeData *surge, tnt_config *config){
	surge->ramp_rate =  config->surge_duty / 100 / config->hertz;
	surge->tiltback_step_size = config->tiltback_surge_speed / config->hertz;
}

void reset_surge(SurgeData *surge){
	surge->active = false;
	surge->deactivate = false;
	surge->high_current = false;
	surge->high_current_buzz = false;
	surge->high_current_timer = 0;
}
