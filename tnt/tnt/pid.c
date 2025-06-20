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

#include "pid.h"
#include "utils_tnt.h"
#include <math.h>
#include "vesc_c_if.h"

float angle_kp_select(float angle, const KpArray *k) {
	float kp_mod = 0;
	float kp_min = 0;
	float scale_angle_min = 0;
	float scale_angle_max = 1;
	float kp_max = 0;
	int i = k->count;
	//Determine the correct kp to use based on angle
	while (i >= 0) {
		if (angle>= k->angle_kp[i][0]) {
			kp_min = k->angle_kp[i][1];
			scale_angle_min = k->angle_kp[i][0];
			if (i == k->count) { //if we are at the highest current only use highest kp
				kp_max = k->angle_kp[i][1];
				scale_angle_max = 90;
			} else {
				kp_max = k->angle_kp[i+1][1];
				scale_angle_max = k->angle_kp[i+1][0];
			}
			i=-1;
		}
		i--;
	}
	
	//Interpolate the kp values according to angle
	kp_mod = lerp(scale_angle_min, scale_angle_max, kp_min, kp_max, angle);
	return kp_mod;
}

void pitch_kp_configure(const tnt_config *config, KpArray *k, int mode){
	float pitch_current[7][2] = { //Accel curve
	{0, 0}, //reserved for kp0 assigned at the end
	{config->pitch1, config->current1},
	{config->pitch2, config->current2},
	{config->pitch3, config->current3},
	{config->pitch4, config->current4},
	{config->pitch5, config->current5},
	{config->pitch6, config->current6},
	};
	float kp0 = config->kp0;
	bool kp_input = config->pitch_kp_input;
	k->kp_rate = config->kp_rate;

	if (mode==2) { //Brake curve
		float temp_pitch_current[7][2] = {
		{0, 0}, //reserved for kp0 assigned at the end
		{config->brakepitch1, config->brakecurrent1},
		{config->brakepitch2, config->brakecurrent2},
		{config->brakepitch3, config->brakecurrent3},
		{config->brakepitch4, config->brakecurrent4},
		{config->brakepitch5, config->brakecurrent5},
		{config->brakepitch6, config->brakecurrent6},
		};
		for (int x = 0; x <= 6; x++) {
			for (int y = 0; y <= 1; y++) {
				pitch_current[x][y] = temp_pitch_current[x][y];
			}
		}
		kp0 = config->brake_kp0;
		k->kp_rate = config->brakekp_rate;
	}

	//Check for current inputs
	int i = 1;
	while (i <= 6){
		if (pitch_current[i][1]!=0 && pitch_current[i][0]>pitch_current[i-1][0]) {
			k->count = i;
			k->angle_kp[i][0]=pitch_current[i][0];
			if (kp_input) {
				k->angle_kp[i][1]=pitch_current[i][1];
			} else {k->angle_kp[i][1]=pitch_current[i][1]/pitch_current[i][0];}
		} else { i=7; }
		i++;
	}
	
	//Check kp0 for an appropriate value, prioritizing kp1
	if (k->angle_kp[1][1] !=0) {
		if (k->angle_kp[1][1] < kp0) {
			k->angle_kp[0][1]= k->angle_kp[1][1]; //If we have a kp1 check to see if it is less than kp0 else reduce kp0
		} else { k->angle_kp[0][1] = kp0; } //If less than kp1 it is OK
	} else if (kp0 == 0) { //If no currents and no kp0
		k->angle_kp[0][1] = 5; //default 5
	} else { k->angle_kp[0][1] = kp0; }//passes all checks, it is ok 
}

void angle_kp_reset(KpArray *k) {
	//necessary only for the pitch kparray
	for (int x = 0; x <= 6; x++) {
		for (int y = 0; y <= 1; y++) {
			k->angle_kp[x][y] = 0;
		}
	}
	k->count = 0;
}

void roll_kp_configure(const tnt_config *config, KpArray *k, int mode){
	float accel_roll_kp[7][2] = { //Accel curve
	{0, 0}, 
	{config->roll1, config->roll_kp1},
	{config->roll2, config->roll_kp2},
	{config->roll3, config->roll_kp3},
	{0, 0},
	{0, 0},
	{0, 0},
	};
	
	float brake_roll_kp[7][2] = { //Brake Curve
	{0, 0}, 
	{config->brkroll1, config->brkroll_kp1},
	{config->brkroll2, config->brkroll_kp2},
	{config->brkroll3, config->brkroll_kp3},
	{0, 0},
	{0, 0},
	{0, 0},
	};	

	for (int x = 0; x <= 6; x++) {
		for (int y = 0; y <= 1; y++) {
			k->angle_kp[x][y] = (mode==2) ? brake_roll_kp[x][y] : accel_roll_kp[x][y];
		}
	}
	
	if (k->angle_kp[1][1]<k->angle_kp[2][1] && k->angle_kp[1][0]<k->angle_kp[2][0]) {
		if (k->angle_kp[2][1]<k->angle_kp[3][1] && k->angle_kp[2][0]<k->angle_kp[3][0]) {
			k->count = 3;
		} else {k->count = 2;}
	} else if (k->angle_kp[1][1] >0 && k->angle_kp[1][0]>0) {
		k->count = 1;
	} else {k->count = 0;}
}

void yaw_kp_configure(const tnt_config *config, KpArray *k, int mode){
	float accel_yaw_kp[7][2] = { //Accel curve
	{0, 0}, 
	{config->yaw1 / config->hertz, config->yaw_kp1},
	{config->yaw2 / config->hertz, config->yaw_kp2},
	{config->yaw3 / config->hertz, config->yaw_kp3},
	{0, 0},
	{0, 0},
	{0, 0},
	};
	
	float brake_yaw_kp[7][2] = { //Brake Curve
	{0, 0}, 
	{config->brkyaw1 / config->hertz, config->brkyaw_kp1},
	{config->brkyaw2 / config->hertz, config->brkyaw_kp2},
	{config->brkyaw3 / config->hertz, config->brkyaw_kp3},
	{0, 0},
	{0, 0},
	{0, 0},
	};	

	for (int x = 0; x <= 6; x++) {
		for (int y = 0; y <= 1; y++) {
			k->angle_kp[x][y] = (mode==2) ? brake_yaw_kp[x][y] : accel_yaw_kp[x][y];
		}
	}
	k->kp_rate = (mode==2) ? (1 - config->yaw_rate_kp) * config->kp_rate : (1 - config->yaw_rate_brake_kp) * config->brakekp_rate;
	
	if (k->angle_kp[1][1]<k->angle_kp[2][1] && k->angle_kp[1][0]<k->angle_kp[2][0]) {
		if (k->angle_kp[2][1]<k->angle_kp[3][1] && k->angle_kp[2][0]<k->angle_kp[3][0]) {
			k->count = 3;
		} else {k->count = 2;}
	} else if (k->angle_kp[1][1] >0 && k->angle_kp[1][0]>0) {
		k->count = 1;
	} else {k->count = 0;}
}

float erpm_scale(float lowvalue, float highvalue, float lowscale, float highscale, float abs_erpm){ 
	float scaler = lerp(lowvalue, highvalue, lowscale, highscale, abs_erpm);
	if (lowscale < highscale) {
		scaler = min(max(scaler, lowscale), highscale);
	} else { scaler = max(min(scaler, lowscale), highscale); }
	return scaler;
}

void apply_stability(PidData *p, float abs_erpm, float inputtilt_interpolated, tnt_config *config) {
	float speed_stabl_mod = 0;
	float throttle_stabl_mod = 0;	
	float stabl_mod = 0;
	if (config->enable_throttle_stability) {
		throttle_stabl_mod = fabsf(inputtilt_interpolated) / config->inputtilt_angle_limit; 	//using inputtilt_interpolated allows the use of sticky tilt and inputtilt smoothing
	}
	if (config->enable_speed_stability && abs_erpm > 1.0 * config->stabl_min_erpm) {		
		speed_stabl_mod = fminf(1 ,										// Do not exceed the max value.				
				lerp(config->stabl_min_erpm, config->stabl_max_erpm, 0, 1, abs_erpm));
	}
	stabl_mod = fmaxf(speed_stabl_mod,throttle_stabl_mod);
	float step_size = stabl_mod > p->stabl ? p->stabl_step_size_up : p->stabl_step_size_down;
	rate_limitf(&p->stabl, stabl_mod, step_size); 
	p->stability_kp = 1 + p->stabl * config->stabl_pitch_max_scale / 100; //apply dynamic stability for pitch kp
	p->stability_kprate = 1 + p->stabl * config->stabl_rate_max_scale / 100;
}

void check_brake_kp(PidData *p, State *state, tnt_config *config, KpArray *roll_brake_kp, KpArray *yaw_brake_kp) {
	p->brake_roll = roll_brake_kp->count!=0 && state->braking_pos;
	p->brake_pitch = config->brake_curve && state->braking_pos;
	p->brake_yaw = yaw_brake_kp->count!=0 && state->braking_pos;
}

float roll_erpm_scale(PidData *p, State *state, float abs_erpm, KpArray *roll_accel_kp, tnt_config *config) {
	//Apply ERPM Scale
	float erpmscale = 1;
	if ((p->brake_roll && abs_erpm < 750) ||
		state->sat == SAT_CENTERING) { 				
		// If we want to actually stop at low speed reduce kp to 0
		erpmscale = 0;
	} else if (roll_accel_kp->count!=0 && abs_erpm < config->rollkp_higherpm) { 
		erpmscale = 1 + erpm_scale(config->rollkp_lowerpm, config->rollkp_higherpm, config->rollkp_maxscale / 100.0, 0, abs_erpm);
	} else if (roll_accel_kp->count!=0 && abs_erpm > config->roll_hs_lowerpm) { 
		erpmscale = 1 + erpm_scale(config->roll_hs_lowerpm, config->roll_hs_higherpm, 0, config->roll_hs_maxscale / 100.0, abs_erpm);
	}
	return erpmscale;
}

void reset_pid(PidData *p, PidDebug *pid_dbg) {
	p->pid_value = 0;
	p->pid_mod = 0;
	p->roll_pid_mod = 0;
	p->yaw_pid_mod = 0;
	p->stabl = 0;
	p->prop_smooth = 0;
	p->abs_prop_smooth = 0;
	p->softstart_pid_limit = 0;
	pid_dbg->debug16 = 0;
}

void apply_soft_start(PidData *p, float mc_current_max) {
	if (p->softstart_pid_limit < mc_current_max) {
		p->pid_mod = fminf(fabsf(p->pid_mod), p->softstart_pid_limit) * sign(p->pid_mod);
		p->softstart_pid_limit += p->softstart_step_size;
	}
}

void configure_pid(PidData *p, tnt_config *config) {
	//Dynamic Stability
	p->stabl_step_size_up = 1.0 * config->stabl_ramp / 100.0 / config->hertz;
	p->stabl_step_size_down = 1.0 * config->stabl_ramp_down / 100.0 / config->hertz;
	
	// Feature: Soft Start
	p->softstart_step_size = 100.0 / config->hertz;
}


float apply_pitch_kp(KpArray *accel_kp, KpArray *brake_kp, PidData *p, PidDebug *pid_dbg) {
	//Select and Apply Pitch kp  
	float kp_mod, new_pid_value;
	kp_mod = angle_kp_select(p->abs_prop_smooth, 
		p->brake_pitch ? brake_kp : accel_kp);
	pid_dbg->debug1 = p->brake_pitch ? -kp_mod : kp_mod;
	pid_dbg->debug8 = (p->stability_kp - 1) * kp_mod;  //stability contribution to pitch kp
	pid_dbg->debug13 = pid_dbg->debug8 * p->proportional; // pitch demand from stability
	pid_dbg->debug12 = kp_mod * p->proportional; // pitch demand without stability
	kp_mod *= p->stability_kp;
	new_pid_value = p->proportional * kp_mod;

	return new_pid_value;
}

float apply_kp_rate(KpArray *accel_kp, KpArray *brake_kp, PidData *p, PidDebug *pid_dbg) {
	float pid_mod = 0;
	float kp_rate = p->brake_pitch ? brake_kp->kp_rate : accel_kp->kp_rate;	
	pid_dbg->debug10 = kp_rate;
	pid_mod = kp_rate 
	return pid_mod;
}

float apply_roll_kp(KpArray *roll_accel_kp, KpArray *roll_brake_kp, PidData *p, int erpm_sign, float abs_roll_angle, float roll_erpm_scale, PidDebug *pid_dbg) {
	// Select Roll Kp
	float rollkp = 0;
	float pid_mod = 0;
	rollkp = angle_kp_select(abs_roll_angle, 
		p->brake_roll ? roll_brake_kp : roll_accel_kp);
	pid_dbg->debug16 = max(abs_roll_angle, pid_dbg->debug16);
	
	//ERPM Scale
	rollkp *= roll_erpm_scale;
	pid_dbg->debug2 = p->brake_roll ? -rollkp : rollkp;	

	//Apply Roll Boost
	p->roll_pid_mod = .99 * p->roll_pid_mod + .01 * rollkp * fabsf(p->new_pid_value) * erpm_sign; 	//always act in the direciton of travel
	pid_mod += p->roll_pid_mod;
	pid_dbg->debug18 =  p->roll_pid_mod;
	return pid_mod;
}

float yaw_erpm_scale(PidData *p, State *state, float abs_erpm, tnt_config *config) {
	float yaw_erpm_scale = ((p->brake_yaw && abs_erpm < 750) || 
		abs_erpm < config->yaw_minerpm || 
		state->sat == SAT_CENTERING) ? 0 : 1;
	return yaw_erpm_scale;
}


float apply_yaw_kp(KpArray *yaw_accel_kp, KpArray *yaw_brake_kp, PidData *p, float erpm_sign, float abs_change, float yaw_erpm_scale, YawDebugData *yaw_dbg) {
	//Select Yaw Kp
	float yawkp = 0;
	float pid_mod = 0;
	yawkp = angle_kp_select(abs_change, 
		p->brake_yaw ? yaw_brake_kp : yaw_accel_kp);
	
	//Apply ERPM Scale
	yawkp *= yaw_erpm_scale;
	yaw_dbg->debug5 = yaw_erpm_scale;
	yaw_dbg->debug4 = p->brake_yaw ? -yawkp : yawkp;
	yaw_dbg->debug2 = fmaxf(yaw_dbg->debug2, yawkp);
	
	//Apply Yaw Boost
	p->yaw_pid_mod = .99 * p->yaw_pid_mod + .01 * yawkp * fabsf(p->new_pid_value) * erpm_sign; 	//always act in the direciton of travel
	pid_mod += p->yaw_pid_mod;
	yaw_dbg->debug6 = p->yaw_pid_mod;

	return pid_mod;
}

void brake(float current, RuntimeData *rt, MotorData *motor) {
	// Brake timeout logic
	float brake_timeout_length = 1;  // Brake Timeout hard-coded to 1s
	if (fabsf(motor->abs_erpm) > 10 || rt->brake_timeout == 0)
		rt->brake_timeout = rt->current_time + brake_timeout_length;

	if (rt->current_time > rt->brake_timeout)
	    return;

	VESC_IF->timeout_reset();
	VESC_IF->mc_set_brake_current(current);
}

void set_current(float current, RuntimeData *rt ) {
	VESC_IF->timeout_reset();
	VESC_IF->mc_set_current_off_delay(rt->motor_timeout_s);
	VESC_IF->mc_set_current(current);
}

void set_dutycycle(float dutycycle, RuntimeData *rt){
	// Limit duty output to configured max output
	if (dutycycle >  VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty)) {
		dutycycle = VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty);
	} else if(dutycycle < 0 && dutycycle < -VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty)) {
		dutycycle = -VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty);
	}
	
	VESC_IF->timeout_reset();
	VESC_IF->mc_set_current_off_delay(rt->motor_timeout_s);
	VESC_IF->mc_set_duty(dutycycle); 
}

void set_brake(float current,  RuntimeData *rt) {
	VESC_IF->timeout_reset();
	VESC_IF->mc_set_current_off_delay(rt->motor_timeout_s);
	VESC_IF->mc_set_brake_current(current);
}

// Fault checking order does not really matter. From a UX perspective, switch should be before angle.
bool check_faults(MotorData *motor, FootpadSensor *fs, RuntimeData *rt, State *state, float inputtilt_interpolated, tnt_config *config) {
        bool disable_switch_faults = config->fault_moving_fault_disabled &&
            // Rolling forward (not backwards!)
            motor->erpm > (config->fault_adc_half_erpm * 2) &&
            // Not tipped over
            fabsf(rt->roll_angle) < 40;

        // Check switch
        // Switch fully open
        if (fs->state == FS_NONE) {
            if (!disable_switch_faults) {
                if ((1000.0 * (rt->current_time - rt->fault_switch_timer)) >
                    config->fault_delay_switch_full) {
					    state_stop(state, 
							state->wheelslip && config->is_traction_enabled ? STOP_TRACTN_CTRL : 
							STOP_SWITCH_FULL);
					    return true;
                }
                // low speed (below 6 x half-fault threshold speed):
                else if ((motor->abs_erpm < config->fault_adc_half_erpm * 6) &&
                    (1000.0 * (rt->current_time - rt->fault_switch_timer) >
                    config->fault_delay_switch_half)) {
                    	state_stop(state, 
			    			state->wheelslip && config->is_traction_enabled ? STOP_TRACTN_CTRL : 
			    			STOP_SWITCH_FULL);
                    return true;
                }
            }
    		if ((motor->abs_erpm < config->quickstop_erpm) && (fabsf(rt->true_pitch_angle) > config->quickstop_angle) && 
                (fabsf(inputtilt_interpolated) < 30) && 
				(config->is_quickstop_enabled) &&
                (sign(rt->true_pitch_angle) ==  motor->erpm_sign)) {
    				state_stop(state, 
			    		state->wheelslip && config->is_traction_enabled ? STOP_TRACTN_CTRL : 
						STOP_QUICKSTOP);
    				return true;
    		}
        } else {
            rt->fault_switch_timer = rt->current_time;
        }

        // Switch partially open and stopped
        if (!config->fault_is_dual_switch) {
            if (!is_engaged(fs, rt, config) && motor->abs_erpm < config->fault_adc_half_erpm) {
                if ((1000.0 * (rt->current_time - rt->fault_switch_half_timer)) >
                    config->fault_delay_switch_half) {
        				state_stop(state, 
			    			state->wheelslip && config->is_traction_enabled ? STOP_TRACTN_CTRL : 
							STOP_SWITCH_HALF);
                    	return true;
                }
            } else {
                rt->fault_switch_half_timer = rt->current_time;
            }
        }

        // Check roll angle
        if (fabsf(rt->roll_angle) > config->fault_roll) {
            if ((1000.0 * (rt->current_time - rt->fault_angle_roll_timer)) >
                config->fault_delay_pitch) {
                	state_stop(state, 
			    		state->wheelslip && config->is_traction_enabled ? STOP_TRACTN_CTRL : 
						STOP_ROLL);
                	return true;
            }
        } else {
            rt->fault_angle_roll_timer = rt->current_time;
        }
        
	
	    // Check pitch angle
	    if (fabsf(rt->pitch_angle) > config->fault_pitch && fabsf(inputtilt_interpolated) < 30) {
	        if ((1000.0 * (rt->current_time - rt->fault_angle_pitch_timer)) >
	            config->fault_delay_pitch) {
	    			state_stop(state, 
				    	state->wheelslip && config->is_traction_enabled ? STOP_TRACTN_CTRL : 
						STOP_PITCH);
	            	return true;
	        }
	    } else {
	        rt->fault_angle_pitch_timer = rt->current_time;
	    }

    return false;
}

void calculate_proportional(RuntimeData *rt, PidData *pid, float setpoint) {
	pid->proportional = setpoint - rt->pitch_angle;
	pid->prop_smooth = setpoint - rt->pitch_smooth_kalman;
	pid->abs_prop_smooth = fabsf(pid->prop_smooth);
}
