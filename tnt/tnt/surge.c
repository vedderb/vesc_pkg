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

#include "surge.h"
#include "vesc_c_if.h"
#include "utils_tnt.h"
#include <math.h>

void check_surge(MotorData *m, SurgeData *surge, State *state, RuntimeData *rt, PidData *p, float setpoint, SurgeDebug *surge_dbg){
	//Start Surge Code
	//Initialize Surge Cycle
	if ((m->current_filtered * m->erpm_sign > surge->start_current) && 		//High current condition 
	    (surge->high_current) && 							//If overcurrent is triggered this satifies traction control, min erpm, braking, centering and direction
	    (m->duty_cycle < 0.8) &&							//Prevent surge when pushing top speed
	    (rt->current_time - surge->timer > 0.7)) {					//Not during an active surge period
		surge->timer = rt->current_time; 					//Reset surge timer
		state->surge_active = true; 							//Indicates we are in the surge cycle of the surge period
		surge->setpoint = setpoint;						//Records setpoint at the start of surge because surge changes the setpoint
		surge->new_duty_cycle = m->erpm_sign * m->duty_cycle;
		
		//Debug Data Section
		surge_dbg->debug1 = p->proportional;				
		surge_dbg->debug2 = m->current_filtered;
		surge_dbg->debug3 = surge->start_current;
		surge_dbg->debug4 = m->duty_cycle;
		surge_dbg->debug5 = 0;
		surge_dbg->debug6 = 0;
		surge_dbg->debug7 = 0;
		surge_dbg->debug8 = 0;
	}
	
	//Conditions to stop surge and increment the duty cycle
	if (state->surge_active){	
		surge->new_duty_cycle += m->erpm_sign * surge->ramp_rate; 	
		if((rt->current_time - surge->timer > 0.5) ||						//Outside the surge cycle portion of the surge period
		    (-1 * (surge->setpoint - rt->pitch_angle) * m->erpm_sign > surge->maxangle) ||	//Limit nose up angle based on the setpoint at start of surge because surge changes the setpoint
		    (state->braking_active) ||								//In traction braking
		    (state->wheelslip)) {								//In traction control		
			state->surge_active = false;
			state->surge_deactivate = true;							//Identifies the end of surge to change the setpoint back to before surge 
			p->pid_value = VESC_IF->mc_get_tot_current_directional_filtered();		//This allows a smooth transition to PID current control
			
			//Debug Data Section
			surge_dbg->debug7 = rt->current_time - surge->timer;					//Register how long the surge cycle lasted
			surge_dbg->debug5 = m->duty_cycle - surge_dbg->debug4;					//Added surge duty
			surge_dbg->debug8 = surge_dbg->debug5/ (rt->current_time - surge->timer) * 100;		//Surge ramp rate
			if (rt->current_time - surge->timer >= 0.5) {						//End condition
				surge_dbg->debug6 = 111;
			} else if (-1 * (surge->setpoint - rt->pitch_angle) * m->erpm_sign > surge->maxangle){
				surge_dbg->debug6 = rt->pitch_angle;
			} else if (state->wheelslip){
				surge_dbg->debug6 = 222;
			}
		}
	}
}

void check_current(MotorData *m, SurgeData *surge, State *state, tnt_config *config, ToneData *tone, ToneConfig *toneconfig) {
	float scale_start_current = lerp(1.0 * config->surge_scaleduty / 100.0, .95, config->surge_startcurrent, config->surge_start_hd_current, m->duty_cycle);
	surge->start_current = fminf(config->surge_startcurrent, scale_start_current); 
	if ((m->current_filtered * m->erpm_sign > surge->start_current - config->overcurrent_margin) && 	//High current condition 
	     (!state->braking_pos_smooth) && 									//Not braking
	     (!state->wheelslip) &&										//Not during traction control
	     (m->abs_erpm > config->surge_minerpm) &&								//Above the min erpm threshold
	     (m->erpm_sign_check) &&										//Prevents surge if direction has changed rapidly, like a situation with hard brake and wheelslip
	     (state->sat != SAT_CENTERING)) { 									//Not during startup
		// High current, just haptic buzz don't actually limit currents
		if (!surge->high_current)
			play_tone(tone, toneconfig, TONE_CURRENT);
		surge->high_current = true;
	} else { surge->high_current = false; } 
}

void configure_surge(SurgeData *surge, tnt_config *config){
	surge->ramp_rate = 1.0 * config->surge_duty / 100.0 / config->hertz;
	surge->maxangle = config->surge_maxangle;
}

void reset_surge(SurgeData *surge){
	surge->high_current = false;
	surge->high_current_buzz = false;
	surge->high_current_timer = 0;
}
