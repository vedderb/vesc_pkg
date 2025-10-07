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

#include "setpoint.h"
#include "utils_tnt.h"
#include "vesc_c_if.h"
#include <math.h>

void setpoint_configure(SetpointData *s, tnt_config *config) {
	//Setpoint Adjustment
	s->startup_step_size = 1.0 * config->startup_speed / config->hertz;
	s->tiltback_duty_step_size = 1.0 * config->tiltback_duty_speed / config->hertz;
	s->tiltback_hv_step_size = 1.0 * config->tiltback_hv_speed / config->hertz;
	s->tiltback_lv_step_size = 1.0 * config->tiltback_lv_speed / config->hertz;
	s->tiltback_return_step_size = 1.0 * config->tiltback_return_speed / config->hertz;
	s->tiltback_ht_step_size = 1.0 * config->tiltback_ht_speed / config->hertz;
	s->noseangling_step_size = 1.0 * config->noseangling_speed / config->hertz;
	s->tiltback_duty = 1.0 * config->tiltback_duty / 100.0;
	s->surge_tiltback_step_size = 1.0 * config->tiltback_surge_speed / config->hertz;

	// Feature: Dirty Landings
	s->startup_pitch_trickmargin = config->startup_dirtylandings_enabled ? 10 : 0;
}

void setpoint_reset(SetpointData *s, tnt_config *config, RuntimeData *rt) {
	// Set values for startup
	s->setpoint_target_interpolated = rt->pitch_angle;
	s->setpoint_target = 0;
	s->startup_pitch_tolerance = config->startup_pitch_tolerance;
	s->setpoint = rt->pitch_angle;
}

float get_setpoint_adjustment_step_size(SetpointData *s, State *state) {
	switch (state->sat) {
	case (SAT_NONE):
		return s->tiltback_return_step_size;
	case (SAT_CENTERING):
		return s->startup_step_size;
	case (SAT_PB_DUTY):
		return s->tiltback_duty_step_size;
	case (SAT_PB_HIGH_VOLTAGE):
		return s->tiltback_hv_step_size;
	case (SAT_PB_TEMPERATURE):
		return s->tiltback_ht_step_size;
	case (SAT_PB_LOW_VOLTAGE):
		return s->tiltback_lv_step_size;
	case (SAT_UNSURGE):
		return s->surge_tiltback_step_size;
	case (SAT_SURGE):
		return 25; 				//"as fast as possible", extremely large step size 
	default:
		return 0;
	}
}

void calculate_setpoint_interpolated(SetpointData *s, State *state) {
    if (s->setpoint_target_interpolated != s->setpoint_target) {
        rate_limitf(
            &s->setpoint_target_interpolated,
            s->setpoint_target,
            get_setpoint_adjustment_step_size(s, state) 
	);
    }
}

void apply_noseangling(SetpointData *s, MotorData *motor, tnt_config *config) {
	float noseangling_target = 0;
	if (motor->abs_erpm > config->tiltback_constant_erpm) {
		noseangling_target += config->tiltback_constant * motor->erpm_sign;
	}

	rate_limitf(&s->noseangling_interpolated, noseangling_target, s->noseangling_step_size);

	s->setpoint += s->noseangling_interpolated;
}

void calculate_setpoint_target(SetpointData *spd, State *state, MotorData *motor, RuntimeData *rt, 
    tnt_config *config, float proportional) {
	float input_voltage = VESC_IF->mc_get_input_voltage_filtered();
	
	if (input_voltage < config->tiltback_hv) {
		spd->tb_highvoltage_timer = rt->current_time;
	}

	if (state->wheelslip) {
		state->sat = SAT_NONE;
	} else if (state->surge_deactivate) { 
		spd->setpoint_target = 0;
		state->sat = SAT_UNSURGE;
		if (spd->setpoint_target_interpolated < 0.1 && spd->setpoint_target_interpolated > -0.1) { 	// End surge_off once we are close to 0 
			state->surge_deactivate = false;
		}
	} else if (state->surge_active) {
		if (proportional * motor->erpm_sign < config->surge_pitchmargin) {				//As the nose of the board rises
			spd->setpoint_target = rt->pitch_angle + config->surge_pitchmargin * motor->erpm_sign;	//move setpoint to maintain pitchmargin
			state->sat = SAT_SURGE;
		}
	} else if (motor->duty_cycle > spd->tiltback_duty) {
		if (motor->erpm > 0) {
			spd->setpoint_target = config->tiltback_duty_angle;
		} else {
			spd->setpoint_target = -config->tiltback_duty_angle;
		}
		state->sat = SAT_PB_DUTY;
	} else if (motor->duty_cycle > 0.05 && input_voltage > config->tiltback_hv) {
		if (((rt->current_time - spd->tb_highvoltage_timer) > .5) ||
		   (input_voltage > config->tiltback_hv + 1)) {
		// 500ms have passed or voltage is another volt higher, time for some tiltback
			if (motor->erpm > 0) {
				spd->setpoint_target = config->tiltback_hv_angle;
			} else {
				spd->setpoint_target = -config->tiltback_hv_angle;
			}
	
			state->sat = SAT_PB_HIGH_VOLTAGE;
		} else {
			// The rider has 500ms to react to the triple-beep, or maybe it was just a short spike
			state->sat = SAT_NONE;
		}
	} else if (VESC_IF->mc_temp_fet_filtered() > motor->mc_max_temp_fet) {
		if (VESC_IF->mc_temp_fet_filtered() > (motor->mc_max_temp_fet + 1)) {
			if (motor->erpm > 0) {
				spd->setpoint_target = config->tiltback_ht_angle;
			} else {
				spd->setpoint_target = -config->tiltback_ht_angle;
			}
			state->sat = SAT_PB_TEMPERATURE;
		} else {
			// The rider has 1 degree Celsius left before we start tilting back
			state->sat = SAT_NONE;
		}
	} else if (VESC_IF->mc_temp_motor_filtered() > motor->mc_max_temp_mot) {
		if (VESC_IF->mc_temp_motor_filtered() > (motor->mc_max_temp_mot + 1)) {
			if (motor->erpm > 0) {
				spd->setpoint_target = config->tiltback_ht_angle;
			} else {
				spd->setpoint_target = -config->tiltback_ht_angle;
			}
			state->sat = SAT_PB_TEMPERATURE;
		} else {
			// The rider has 1 degree Celsius left before we start tilting back
			state->sat = SAT_NONE;
		}
	} else if (motor->duty_cycle > 0.05 && input_voltage < config->tiltback_lv) {
		float abs_motor_current = fabsf(motor->current_filtered);
		float vdelta = 1.0 * config->tiltback_lv - input_voltage;
		float ratio = vdelta * 20 / abs_motor_current;
		// When to do LV tiltback:
		// a) we're 2V below lv threshold
		// b) motor current is small (we cannot assume vsag)
		// c) we have more than 20A per Volt of difference (we tolerate some amount of vsag)
		if ((vdelta > 2) || (abs_motor_current < 5) || (ratio > 1)) {
			if (motor->erpm > 0) {
				spd->setpoint_target = config->tiltback_lv_angle;
			} else {
				spd->setpoint_target = -config->tiltback_lv_angle;
			}
			state->sat = SAT_PB_LOW_VOLTAGE;
		} else {
			state->sat = SAT_NONE;
			spd->setpoint_target = 0;
		}
	} else if (state->sat != SAT_CENTERING || spd->setpoint_target_interpolated == spd->setpoint_target) {
        	// Normal running
         	state->sat = SAT_NONE;
	        spd->setpoint_target = 0;
	}
}
