/*
    Copyright 2019 - 2022 Mitch Lustig
	Copyright 2022 Benjamin Vedder	benjamin@vedder.se

	This file is part of the VESC firmware.

	The VESC firmware is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    The VESC firmware is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "vesc_c_if.h"

#include "conf/datatypes.h"
#include "conf/confparser.h"
#include "conf/confxml.h"
#include "conf/buffer.h"

#include <math.h>
#include <string.h>

HEADER

// Can
#define MAX_CAN_AGE		0.1
#define MAX_CAN_DEVS	2

// Return the sign of the argument. -1.0 if negative, 1.0 if zero or positive.
#define SIGN(x)				(((x) < 0.0) ? -1.0 : 1.0)

#define DEG2RAD_f(deg)		((deg) * (float)(M_PI / 180.0))
#define RAD2DEG_f(rad) 		((rad) * (float)(180.0 / M_PI))

// Data type (Value 5 was removed, and can be reused at a later date, but i wanted to preserve the current value's numbers for UIs)
typedef enum {
	STARTUP = 0,
	RUNNING = 1,
	RUNNING_TILTBACK_DUTY = 2,
	RUNNING_TILTBACK_HIGH_VOLTAGE = 3,
	RUNNING_TILTBACK_LOW_VOLTAGE = 4,
	FAULT_ANGLE_PITCH = 6,
	FAULT_ANGLE_ROLL = 7,
	FAULT_SWITCH_HALF = 8,
	FAULT_SWITCH_FULL = 9,
	FAULT_DUTY = 10,
	FAULT_STARTUP = 11
} BalanceState;

typedef enum {
	CENTERING = 0,
	TILTBACK_DUTY,
	TILTBACK_HV,
	TILTBACK_LV,
	TILTBACK_NONE
} SetpointAdjustmentType;

typedef enum {
	OFF = 0,
	HALF,
	ON
} SwitchState;

typedef struct{
	float a0, a1, a2, b1, b2;
	float z1, z2;
} Biquad;

typedef enum {
	BQ_LOWPASS,
	BQ_HIGHPASS
} BiquadType;

// This is all persistent state of the application, which will be allocated in init. It
// is put here because variables can only be read-only when this program is loaded
// in flash without virtual memory in RAM (as all RAM already is dedicated to the
// main firmware and managed from there). This is probably the main limitation of
// loading applications in runtime, but it is not too bad to work around.
typedef struct {
	lib_thread thread; // Balance Thread

	balance_config balance_conf;

	// Config values
	float loop_time_seconds;
	float startup_step_size;
	float tiltback_duty_step_size, tiltback_hv_step_size, tiltback_lv_step_size, tiltback_return_step_size;
	float torquetilt_on_step_size, torquetilt_off_step_size, turntilt_step_size;
	float tiltback_variable, tiltback_variable_max_erpm, noseangling_step_size;

	// Runtime values read from elsewhere
	float pitch_angle, last_pitch_angle, roll_angle, abs_roll_angle, abs_roll_angle_sin, last_gyro_y;
	float gyro[3];
	float duty_cycle, abs_duty_cycle;
	float erpm, abs_erpm, avg_erpm;
	float motor_current;
	float motor_position;
	float adc1, adc2;
	SwitchState switch_state;

	// Rumtime state values
	BalanceState state;
	float proportional, integral, derivative, proportional2, integral2, derivative2;
	float last_proportional, abs_proportional;
	float pid_value;
	float setpoint, setpoint_target, setpoint_target_interpolated;
	float noseangling_interpolated;
	float torquetilt_filtered_current, torquetilt_target, torquetilt_interpolated;
	Biquad torquetilt_current_biquad;
	float turntilt_target, turntilt_interpolated;
	SetpointAdjustmentType setpointAdjustmentType;
	float yaw_proportional, yaw_integral, yaw_derivative, yaw_last_proportional, yaw_pid_value, yaw_setpoint;
	float current_time, last_time, diff_time, loop_overshoot; // Seconds
	float filtered_loop_overshoot, loop_overshoot_alpha, filtered_diff_time;
	float fault_angle_pitch_timer, fault_angle_roll_timer, fault_switch_timer, fault_switch_half_timer, fault_duty_timer; // Seconds
	float d_pt1_lowpass_state, d_pt1_lowpass_k, d_pt1_highpass_state, d_pt1_highpass_k;
	float motor_timeout_seconds;
	float brake_timeout; // Seconds

	// Debug values
	int debug_render_1, debug_render_2;
	int debug_sample_field, debug_sample_count, debug_sample_index;
	int debug_experiment_1, debug_experiment_2, debug_experiment_3, debug_experiment_4, debug_experiment_5, debug_experiment_6;
} data;

// Function Prototypes
static void set_current(data *d, float current, float yaw_current);
static void configure(data *d);

// Utility Functions
static float biquad_process(Biquad *biquad, float in) {
    float out = in * biquad->a0 + biquad->z1;
    biquad->z1 = in * biquad->a1 + biquad->z2 - biquad->b1 * out;
    biquad->z2 = in * biquad->a2 - biquad->b2 * out;
    return out;
}

static void biquad_config(Biquad *biquad, BiquadType type, float Fc) {
	float K = tanf(M_PI * Fc);	// -0.0159;
	float Q = 0.707; // maximum sharpness (0.5 = maximum smoothness)
	float norm = 1 / (1 + K / Q + K * K);
	if (type == BQ_LOWPASS) {
		biquad->a0 = K * K * norm;
		biquad->a1 = 2 * biquad->a0;
		biquad->a2 = biquad->a0;
	}
	else if (type == BQ_HIGHPASS) {
		biquad->a0 = 1 * norm;
		biquad->a1 = -2 * biquad->a0;
		biquad->a2 = biquad->a0;
	}
	biquad->b1 = 2 * (K * K - 1) * norm;
	biquad->b2 = (1 - K / Q + K * K) * norm;
}

static void biquad_reset(Biquad *biquad) {
	biquad->z1 = 0;
	biquad->z2 = 0;
}

static void configure(data *d) {
	// Set calculated values from config
	d->loop_time_seconds = 1.0 / d->balance_conf.hertz;

	d->motor_timeout_seconds = d->loop_time_seconds * 20; // Times 20 for a nice long grace period

	d->startup_step_size = d->balance_conf.startup_speed / d->balance_conf.hertz;
	d->tiltback_duty_step_size = d->balance_conf.tiltback_duty_speed / d->balance_conf.hertz;
	d->tiltback_hv_step_size = d->balance_conf.tiltback_hv_speed / d->balance_conf.hertz;
	d->tiltback_lv_step_size = d->balance_conf.tiltback_lv_speed / d->balance_conf.hertz;
	d->tiltback_return_step_size = d->balance_conf.tiltback_return_speed / d->balance_conf.hertz;
	d->torquetilt_on_step_size = d->balance_conf.torquetilt_on_speed / d->balance_conf.hertz;
	d->torquetilt_off_step_size = d->balance_conf.torquetilt_off_speed / d->balance_conf.hertz;
	d->turntilt_step_size = d->balance_conf.turntilt_speed / d->balance_conf.hertz;
	d->noseangling_step_size = d->balance_conf.noseangling_speed / d->balance_conf.hertz;

	// Init Filters
	if (d->balance_conf.loop_time_filter > 0) {
		d->loop_overshoot_alpha = 2.0 * M_PI * ((float)1.0 / (float)d->balance_conf.hertz) *
				(float)d->balance_conf.loop_time_filter / (2.0 * M_PI * (1.0 / (float)d->balance_conf.hertz) *
						(float)d->balance_conf.loop_time_filter + 1.0);
	}

	if (d->balance_conf.kd_pt1_lowpass_frequency > 0) {
		float dT = 1.0 / d->balance_conf.hertz;
		float RC = 1.0 / ( 2.0 * M_PI * d->balance_conf.kd_pt1_lowpass_frequency);
		d->d_pt1_lowpass_k =  dT / (RC + dT);
	}

	if (d->balance_conf.kd_pt1_highpass_frequency > 0) {
		float dT = 1.0 / d->balance_conf.hertz;
		float RC = 1.0 / ( 2.0 * M_PI * d->balance_conf.kd_pt1_highpass_frequency);
		d->d_pt1_highpass_k =  dT / (RC + dT);
	}

	if (d->balance_conf.torquetilt_filter > 0) { // Torquetilt Current Biquad
		float Fc = d->balance_conf.torquetilt_filter / d->balance_conf.hertz;
		biquad_config(&d->torquetilt_current_biquad, BQ_LOWPASS, Fc);
	}

	// Variable nose angle adjustment / tiltback (setting is per 1000erpm, convert to per erpm)
	d->tiltback_variable = d->balance_conf.tiltback_variable / 1000;
	if (d->tiltback_variable > 0) {
		d->tiltback_variable_max_erpm = fabsf(d->balance_conf.tiltback_variable_max / d->tiltback_variable);
	} else {
		d->tiltback_variable_max_erpm = 100000;
	}

	// Reset loop time variables
	d->last_time = 0.0;
	d->filtered_loop_overshoot = 0.0;
}

static void reset_vars(data *d) {
	// Clear accumulated values.
	d->integral = 0;
	d->last_proportional = 0;
	d->integral2 = 0;
	d->yaw_integral = 0;
	d->yaw_last_proportional = 0;
	d->d_pt1_lowpass_state = 0;
	d->d_pt1_highpass_state = 0;
	// Set values for startup
	d->setpoint = d->pitch_angle;
	d->setpoint_target_interpolated = d->pitch_angle;
	d->setpoint_target = 0;
	d->noseangling_interpolated = 0;
	d->torquetilt_target = 0;
	d->torquetilt_interpolated = 0;
	d->torquetilt_filtered_current = 0;
	biquad_reset(&d->torquetilt_current_biquad);
	d->turntilt_target = 0;
	d->turntilt_interpolated = 0;
	d->setpointAdjustmentType = CENTERING;
	d->yaw_setpoint = 0;
	d->state = RUNNING;
	d->current_time = 0;
	d->last_time = 0;
	d->diff_time = 0;
	d->brake_timeout = 0;
}

static float get_setpoint_adjustment_step_size(data *d) {
	switch(d->setpointAdjustmentType){
		case (CENTERING):
			return d->startup_step_size;
		case (TILTBACK_DUTY):
			return d->tiltback_duty_step_size;
		case (TILTBACK_HV):
			return d->tiltback_hv_step_size;
		case (TILTBACK_LV):
			return d->tiltback_lv_step_size;
		case (TILTBACK_NONE):
			return d->tiltback_return_step_size;
		default:
			;
	}
	return 0;
}

// Fault checking order does not really matter. From a UX perspective, switch should be before angle.
static bool check_faults(data *d, bool ignoreTimers){
	// Check switch
	// Switch fully open
	if (d->switch_state == OFF) {
		if((1000.0 * (d->current_time - d->fault_switch_timer)) > d->balance_conf.fault_delay_switch_full || ignoreTimers){
			d->state = FAULT_SWITCH_FULL;
			return true;
		}
	} else {
		d->fault_switch_timer = d->current_time;
	}

	// Switch partially open and stopped
	if(!d->balance_conf.fault_is_dual_switch) {
		if((d->switch_state == HALF || d->switch_state == OFF) && d->abs_erpm < d->balance_conf.fault_adc_half_erpm){
			if ((1000.0 * (d->current_time - d->fault_switch_half_timer)) > d->balance_conf.fault_delay_switch_half || ignoreTimers){
				d->state = FAULT_SWITCH_HALF;
				return true;
			}
		} else {
			d->fault_switch_half_timer = d->current_time;
		}
	}

	// Check pitch angle
	if (fabsf(d->pitch_angle) > d->balance_conf.fault_pitch) {
		if ((1000.0 * (d->current_time - d->fault_angle_pitch_timer)) > d->balance_conf.fault_delay_pitch || ignoreTimers) {
			d->state = FAULT_ANGLE_PITCH;
			return true;
		}
	} else {
		d->fault_angle_pitch_timer = d->current_time;
	}

	// Check roll angle
	if (fabsf(d->roll_angle) > d->balance_conf.fault_roll) {
		if ((1000.0 * (d->current_time - d->fault_angle_roll_timer)) > d->balance_conf.fault_delay_roll || ignoreTimers) {
			d->state = FAULT_ANGLE_ROLL;
			return true;
		}
	} else {
		d->fault_angle_roll_timer = d->current_time;
	}

	// Check for duty
	if (d->abs_duty_cycle > d->balance_conf.fault_duty){
		if ((1000.0 * (d->current_time - d->fault_duty_timer)) > d->balance_conf.fault_delay_duty || ignoreTimers) {
			d->state = FAULT_DUTY;
			return true;
		}
	} else {
		d->fault_duty_timer = d->current_time;
	}

	return false;
}

static void calculate_setpoint_target(data *d) {
	if (d->setpointAdjustmentType == CENTERING && d->setpoint_target_interpolated != d->setpoint_target) {
		// Ignore tiltback during centering sequence
		d->state = RUNNING;
	} else if (d->abs_duty_cycle > d->balance_conf.tiltback_duty) {
		if (d->erpm > 0) {
			d->setpoint_target = d->balance_conf.tiltback_duty_angle;
		} else {
			d->setpoint_target = -d->balance_conf.tiltback_duty_angle;
		}
		d->setpointAdjustmentType = TILTBACK_DUTY;
		d->state = RUNNING_TILTBACK_DUTY;
	} else if (d->abs_duty_cycle > 0.05 && VESC_IF->mc_get_input_voltage_filtered() > d->balance_conf.tiltback_hv) {
		if (d->erpm > 0){
			d->setpoint_target = d->balance_conf.tiltback_hv_angle;
		} else {
			d->setpoint_target = -d->balance_conf.tiltback_hv_angle;
		}

		d->setpointAdjustmentType = TILTBACK_HV;
		d->state = RUNNING_TILTBACK_HIGH_VOLTAGE;
	} else if (d->abs_duty_cycle > 0.05 && VESC_IF->mc_get_input_voltage_filtered() < d->balance_conf.tiltback_lv) {
		if (d->erpm > 0) {
			d->setpoint_target = d->balance_conf.tiltback_lv_angle;
		} else {
			d->setpoint_target = -d->balance_conf.tiltback_lv_angle;
		}

		d->setpointAdjustmentType = TILTBACK_LV;
		d->state = RUNNING_TILTBACK_LOW_VOLTAGE;
	} else {
		d->setpointAdjustmentType = TILTBACK_NONE;
		d->setpoint_target = 0;
		d->state = RUNNING;
	}
}

static void calculate_setpoint_interpolated(data *d) {
	if (d->setpoint_target_interpolated != d->setpoint_target) {
		// If we are less than one step size away, go all the way
		if (fabsf(d->setpoint_target - d->setpoint_target_interpolated) < get_setpoint_adjustment_step_size(d)) {
			d->setpoint_target_interpolated = d->setpoint_target;
		} else if (d->setpoint_target - d->setpoint_target_interpolated > 0) {
			d->setpoint_target_interpolated += get_setpoint_adjustment_step_size(d);
		} else {
			d->setpoint_target_interpolated -= get_setpoint_adjustment_step_size(d);
		}
	}
}

static void apply_noseangling(data *d){
	// Nose angle adjustment, add variable then constant tiltback
	float noseangling_target = 0;
	if (fabsf(d->erpm) > d->tiltback_variable_max_erpm) {
		noseangling_target = fabsf(d->balance_conf.tiltback_variable_max) * SIGN(d->erpm);
	} else {
		noseangling_target = d->tiltback_variable * d->erpm;
	}

	if (d->erpm > d->balance_conf.tiltback_constant_erpm) {
		noseangling_target += d->balance_conf.tiltback_constant;
	} else if (d->erpm < -d->balance_conf.tiltback_constant_erpm){
		noseangling_target += -d->balance_conf.tiltback_constant;
	}

	if (fabsf(noseangling_target - d->noseangling_interpolated) < d->noseangling_step_size) {
		d->noseangling_interpolated = noseangling_target;
	} else if (noseangling_target - d->noseangling_interpolated > 0) {
		d->noseangling_interpolated += d->noseangling_step_size;
	} else {
		d->noseangling_interpolated -= d->noseangling_step_size;
	}

	d->setpoint += d->noseangling_interpolated;
}

static void apply_torquetilt(data *d) {
	// Filter current (Biquad)
	if (d->balance_conf.torquetilt_filter > 0) {
		d->torquetilt_filtered_current = biquad_process(&d->torquetilt_current_biquad, d->motor_current);
	} else {
		d->torquetilt_filtered_current = d->motor_current;
	}

	// Wat is this line O_o
	// Take abs motor current, subtract start offset, and take the max of that with 0 to get the current above our start threshold (absolute).
	// Then multiply it by "power" to get our desired angle, and min with the limit to respect boundaries.
	// Finally multiply it by sign motor current to get directionality back
	d->torquetilt_target = fminf(fmaxf((fabsf(d->torquetilt_filtered_current) - d->balance_conf.torquetilt_start_current), 0) *
			d->balance_conf.torquetilt_strength, d->balance_conf.torquetilt_angle_limit) * SIGN(d->torquetilt_filtered_current);

	float step_size;
	if ((d->torquetilt_interpolated - d->torquetilt_target > 0 && d->torquetilt_target > 0) ||
			(d->torquetilt_interpolated - d->torquetilt_target < 0 && d->torquetilt_target < 0)) {
		step_size = d->torquetilt_off_step_size;
	} else {
		step_size = d->torquetilt_on_step_size;
	}

	if (fabsf(d->torquetilt_target - d->torquetilt_interpolated) < step_size) {
		d->torquetilt_interpolated = d->torquetilt_target;
	} else if (d->torquetilt_target - d->torquetilt_interpolated > 0) {
		d->torquetilt_interpolated += step_size;
	} else {
		d->torquetilt_interpolated -= step_size;
	}

	d->setpoint += d->torquetilt_interpolated;
}

static void apply_turntilt(data *d) {
	// Calculate desired angle
	d->turntilt_target = d->abs_roll_angle_sin * d->balance_conf.turntilt_strength;

	// Apply cutzone
	if (d->abs_roll_angle < d->balance_conf.turntilt_start_angle) {
		d->turntilt_target = 0;
	}

	// Disable below erpm threshold otherwise add directionality
	if (d->abs_erpm < d->balance_conf.turntilt_start_erpm) {
		d->turntilt_target = 0;
	} else {
		d->turntilt_target *= SIGN(d->erpm);
	}

	// Apply speed scaling
	if (d->abs_erpm < d->balance_conf.turntilt_erpm_boost_end) {
		d->turntilt_target *= 1 + ((d->balance_conf.turntilt_erpm_boost / 100.0f) *
				(d->abs_erpm / d->balance_conf.turntilt_erpm_boost_end));
	} else {
		d->turntilt_target *= 1 + (d->balance_conf.turntilt_erpm_boost / 100.0f);
	}

	// Limit angle to max angle
	if (d->turntilt_target > 0) {
		d->turntilt_target = fminf(d->turntilt_target, d->balance_conf.turntilt_angle_limit);
	} else {
		d->turntilt_target = fmaxf(d->turntilt_target, -d->balance_conf.turntilt_angle_limit);
	}

	// Move towards target limited by max speed
	if (fabsf(d->turntilt_target - d->turntilt_interpolated) < d->turntilt_step_size) {
		d->turntilt_interpolated = d->turntilt_target;
	} else if (d->turntilt_target - d->turntilt_interpolated > 0) {
		d->turntilt_interpolated += d->turntilt_step_size;
	} else {
		d->turntilt_interpolated -= d->turntilt_step_size;
	}

	d->setpoint += d->turntilt_interpolated;
}

static float apply_deadzone(data *d, float error){
	if (d->balance_conf.deadzone == 0) {
		return error;
	}

	if (error < d->balance_conf.deadzone && error > -d->balance_conf.deadzone) {
		return 0;
	} else if(error > d->balance_conf.deadzone) {
		return error - d->balance_conf.deadzone;
	} else {
		return error + d->balance_conf.deadzone;
	}
}

static void brake(data *d) {
	// Brake timeout logic
	if (d->balance_conf.brake_timeout > 0 && (d->abs_erpm > 1 || d->brake_timeout == 0)) {
		d->brake_timeout = d->current_time + d->balance_conf.brake_timeout;
	}

	if (d->brake_timeout != 0 && d->current_time > d->brake_timeout) {
		return;
	}

	// Reset the timeout
	VESC_IF->timeout_reset();

	// Set current
	VESC_IF->mc_set_brake_current(d->balance_conf.brake_current);

	if (d->balance_conf.multi_esc) {
		for (int i = 0;i < MAX_CAN_DEVS;i++) {
			can_status_msg *msg = VESC_IF->can_get_status_msg_index(i);
			if (msg->id >= 0 && VESC_IF->ts_to_age_s(msg->rx_time) < MAX_CAN_AGE) {
				VESC_IF->can_set_current_brake(msg->id, d->balance_conf.brake_current);
			}
		}
	}
}

static void set_current(data *d, float current, float yaw_current){
	// Limit current output to configured max output (does not account for yaw_current)
	if (current > 0 && current > VESC_IF->get_cfg_float(CFG_PARAM_l_current_max)) {
		current = VESC_IF->get_cfg_float(CFG_PARAM_l_current_max);
	} else if(current < 0 && current < VESC_IF->get_cfg_float(CFG_PARAM_l_current_min)) {
		current = VESC_IF->get_cfg_float(CFG_PARAM_l_current_min);
	}

	// Reset the timeout
	VESC_IF->timeout_reset();

	// Set current
	if (d->balance_conf.multi_esc) {
		// Set the current delay
		VESC_IF->mc_set_current_off_delay(d->motor_timeout_seconds);

		// Set Current
		VESC_IF->mc_set_current(current + yaw_current);

		// Can bus
		for (int i = 0;i < MAX_CAN_DEVS;i++) {
			can_status_msg *msg = VESC_IF->can_get_status_msg_index(i);

			if (msg->id >= 0 && VESC_IF->ts_to_age_s(msg->rx_time) < MAX_CAN_AGE) {
				// Assume 2 motors, i don't know how to steer 3 anyways
				VESC_IF->can_set_current_off_delay(msg->id, current - yaw_current, d->motor_timeout_seconds);
			}
		}
	} else {
		// Set the current delay
		VESC_IF->mc_set_current_off_delay(d->motor_timeout_seconds);
		// Set Current
		VESC_IF->mc_set_current(current);
	}
}

static void balance_thd(void *arg) {
	data *d = (data*)arg;

	while (!VESC_IF->should_terminate()) {
		// Update times
		d->current_time = VESC_IF->system_time();
		if (d->last_time == 0) {
			d->last_time = d->current_time;
		}

		d->diff_time = d->current_time - d->last_time;
		d->filtered_diff_time = 0.03 * d->diff_time + 0.97 * d->filtered_diff_time; // Purely a metric
		d->last_time = d->current_time;

		if (d->balance_conf.loop_time_filter > 0) {
			d->loop_overshoot = d->diff_time - (d->loop_time_seconds - roundf(d->filtered_loop_overshoot));
			d->filtered_loop_overshoot = d->loop_overshoot_alpha * d->loop_overshoot + (1.0 - d->loop_overshoot_alpha) * d->filtered_loop_overshoot;
		}

		// Read values for GUI
		d->motor_current = VESC_IF->mc_get_tot_current_directional_filtered();
		d->motor_position = VESC_IF->mc_get_pid_pos_now();

		// Set "last" values to previous loops values
		d->last_pitch_angle = d->pitch_angle;
		d->last_gyro_y = d->gyro[1];

		// Get the values we want
		d->pitch_angle = RAD2DEG_f(VESC_IF->imu_get_pitch());
		d->roll_angle = RAD2DEG_f(VESC_IF->imu_get_roll());
		d->abs_roll_angle = fabsf(d->roll_angle);
		d->abs_roll_angle_sin = sinf(DEG2RAD_f(d->abs_roll_angle));
		VESC_IF->imu_get_gyro(d->gyro);
		d->duty_cycle = VESC_IF->mc_get_duty_cycle_now();
		d->abs_duty_cycle = fabsf(d->duty_cycle);
		d->erpm = VESC_IF->mc_get_rpm();
		d->abs_erpm = fabsf(d->erpm);
		if (d->balance_conf.multi_esc) {
			d->avg_erpm = d->erpm;
			for (int i = 0;i < MAX_CAN_DEVS;i++) {
				can_status_msg *msg = VESC_IF->can_get_status_msg_index(i);
				if (msg->id >= 0 && VESC_IF->ts_to_age_s(msg->rx_time) < MAX_CAN_AGE) {
					d->avg_erpm += msg->rpm;
				}
			}

			d->avg_erpm = d->avg_erpm / 2.0; // Assume 2 motors, i don't know how to steer 3 anyways
		}

		d->adc1 = VESC_IF->io_read_analog(VESC_PIN_ADC1);
		d->adc2 = VESC_IF->io_read_analog(VESC_PIN_ADC2); // Returns -1.0 if the pin is missing on the hardware
		if (d->adc2 < 0.0) {
			d->adc2 = 0.0;
		}

		// Calculate switch state from ADC values
		if (d->balance_conf.fault_adc1 == 0 && d->balance_conf.fault_adc2 == 0){ // No Switch
			d->switch_state = ON;
		} else if (d->balance_conf.fault_adc2 == 0) { // Single switch on ADC1
			if (d->adc1 > d->balance_conf.fault_adc1) {
				d->switch_state = ON;
			} else {
				d->switch_state = OFF;
			}
		} else if (d->balance_conf.fault_adc1 == 0) { // Single switch on ADC2
			if (d->adc2 > d->balance_conf.fault_adc2) {
				d->switch_state = ON;
			} else {
				d->switch_state = OFF;
			}
		} else { // Double switch
			if (d->adc1 > d->balance_conf.fault_adc1 && d->adc2 > d->balance_conf.fault_adc2) {
				d->switch_state = ON;
			} else if (d->adc1 > d->balance_conf.fault_adc1 || d->adc2 > d->balance_conf.fault_adc2) {
				if (d->balance_conf.fault_is_dual_switch) {
					d->switch_state = ON;
				} else {
					d->switch_state = HALF;
				}
			} else {
				d->switch_state = OFF;
			}
		}

		// Control Loop State Logic
		switch(d->state) {
		case (STARTUP):
				// Disable output
				brake(d);
				if (VESC_IF->imu_startup_done()) {
					reset_vars(d);
					d->state = FAULT_STARTUP; // Trigger a fault so we need to meet start conditions to start
				}
				break;

		case (RUNNING):
		case (RUNNING_TILTBACK_DUTY):
		case (RUNNING_TILTBACK_HIGH_VOLTAGE):
		case (RUNNING_TILTBACK_LOW_VOLTAGE):
			// Check for faults
			if (check_faults(d, false)) {
				break;
			}

			// Calculate setpoint and interpolation
			calculate_setpoint_target(d);
			calculate_setpoint_interpolated(d);
			d->setpoint = d->setpoint_target_interpolated;
			apply_noseangling(d);
			apply_torquetilt(d);
			apply_turntilt(d);

			// Do PID maths
			d->proportional = d->setpoint - d->pitch_angle;

			// Apply deadzone
			d->proportional = apply_deadzone(d, d->proportional);

			// Resume real PID maths
			d->integral = d->integral + d->proportional;
			d->derivative = d->last_pitch_angle - d->pitch_angle;

			// Apply I term Filter
			if (d->balance_conf.ki_limit > 0 && fabsf(d->integral * d->balance_conf.ki) > d->balance_conf.ki_limit) {
				d->integral = d->balance_conf.ki_limit / d->balance_conf.ki * SIGN(d->integral);
			}

			// Apply D term filters
			if (d->balance_conf.kd_pt1_lowpass_frequency > 0) {
				d->d_pt1_lowpass_state = d->d_pt1_lowpass_state + d->d_pt1_lowpass_k * (d->derivative - d->d_pt1_lowpass_state);
				d->derivative = d->d_pt1_lowpass_state;
			}

			if (d->balance_conf.kd_pt1_highpass_frequency > 0){
				d->d_pt1_highpass_state = d->d_pt1_highpass_state + d->d_pt1_highpass_k * (d->derivative - d->d_pt1_highpass_state);
				d->derivative = d->derivative - d->d_pt1_highpass_state;
			}

			d->pid_value = (d->balance_conf.kp * d->proportional) + (d->balance_conf.ki * d->integral) + (d->balance_conf.kd * d->derivative);

			if (d->balance_conf.pid_mode == BALANCE_PID_MODE_ANGLE_RATE_CASCADE) {
				d->proportional2 = d->pid_value - d->gyro[1];
				d->integral2 = d->integral2 + d->proportional2;
				d->derivative2 = d->last_gyro_y - d->gyro[1];

				// Apply I term Filter
				if (d->balance_conf.ki_limit > 0 && fabsf(d->integral2 * d->balance_conf.ki2) > d->balance_conf.ki_limit) {
					d->integral2 = d->balance_conf.ki_limit / d->balance_conf.ki2 * SIGN(d->integral2);
				}

				d->pid_value = (d->balance_conf.kp2 * d->proportional2) +
						(d->balance_conf.ki2 * d->integral2) + (d->balance_conf.kd2 * d->derivative2);
			}

			d->last_proportional = d->proportional;

			// Apply Booster
			d->abs_proportional = fabsf(d->proportional);
			if (d->abs_proportional > d->balance_conf.booster_angle) {
				if (d->abs_proportional - d->balance_conf.booster_angle < d->balance_conf.booster_ramp) {
					d->pid_value += (d->balance_conf.booster_current * SIGN(d->proportional)) *
							((d->abs_proportional - d->balance_conf.booster_angle) / d->balance_conf.booster_ramp);
				} else {
					d->pid_value += d->balance_conf.booster_current * SIGN(d->proportional);
				}
			}

			if (d->balance_conf.multi_esc) {
				// Calculate setpoint
				if (d->abs_duty_cycle < .02) {
					d->yaw_setpoint = 0;
				} else if (d->avg_erpm < 0) {
					d->yaw_setpoint = (-d->balance_conf.roll_steer_kp * d->roll_angle) +
							(d->balance_conf.roll_steer_erpm_kp * d->roll_angle * d->avg_erpm);
				} else {
					d->yaw_setpoint = (d->balance_conf.roll_steer_kp * d->roll_angle) +
							(d->balance_conf.roll_steer_erpm_kp * d->roll_angle * d->avg_erpm);
				}

				// Do PID maths
				d->yaw_proportional = d->yaw_setpoint - d->gyro[2];
				d->yaw_integral = d->yaw_integral + d->yaw_proportional;
				d->yaw_derivative = d->yaw_proportional - d->yaw_last_proportional;

				d->yaw_pid_value = (d->balance_conf.yaw_kp * d->yaw_proportional) +
						(d->balance_conf.yaw_ki * d->yaw_integral) + (d->balance_conf.yaw_kd * d->yaw_derivative);

				if (d->yaw_pid_value > d->balance_conf.yaw_current_clamp) {
					d->yaw_pid_value = d->balance_conf.yaw_current_clamp;
				} else if (d->yaw_pid_value < -d->balance_conf.yaw_current_clamp) {
					d->yaw_pid_value = -d->balance_conf.yaw_current_clamp;
				}

				d->yaw_last_proportional = d->yaw_proportional;
			}

			// Output to motor
			set_current(d, d->pid_value, d->yaw_pid_value);
			break;

		case (FAULT_ANGLE_PITCH):
		case (FAULT_ANGLE_ROLL):
		case (FAULT_SWITCH_HALF):
		case (FAULT_SWITCH_FULL):
		case (FAULT_STARTUP):
			// Check for valid startup position and switch state
			if (fabsf(d->pitch_angle) < d->balance_conf.startup_pitch_tolerance &&
					fabsf(d->roll_angle) < d->balance_conf.startup_roll_tolerance && d->switch_state == ON) {
				reset_vars(d);
				break;
			}

			// Disable output
			brake(d);
			break;

		case (FAULT_DUTY):
			// We need another fault to clear duty fault.
			// Otherwise duty fault will clear itself as soon as motor pauses, then motor will spool up again.
			// Rendering this fault useless.
			check_faults(d, true);

			// Disable output
			brake(d);
			break;
		}

		// Debug outputs
//		app_balance_sample_debug();
//		app_balance_experiment();

		// Delay between loops
		VESC_IF->sleep_us((uint32_t)((d->loop_time_seconds - roundf(d->filtered_loop_overshoot)) * 1000000.0));
	}
}

static float app_balance_get_debug(int index) {
	data *d = (data*)ARG;

	switch(index){
		case(1):
			return d->motor_position;
		case(2):
			return d->setpoint;
		case(3):
			return d->torquetilt_filtered_current;
		case(4):
			return d->derivative;
		case(5):
			return d->last_pitch_angle - d->pitch_angle;
		case(6):
			return d->motor_current;
		case(7):
			return d->erpm;
		case(8):
			return d->abs_erpm;
		case(9):
			return d->loop_time_seconds;
		case(10):
			return d->diff_time;
		case(11):
			return d->loop_overshoot;
		case(12):
			return d->filtered_loop_overshoot;
		case(13):
			return d->filtered_diff_time;
		case(14):
			return d->integral;
		case(15):
			return d->integral * d->balance_conf.ki;
		case(16):
			return d->integral2;
		case(17):
			return d->integral2 * d->balance_conf.ki2;
		default:
			return 0;
	}
}

static void send_realtime_data(data *d){
	int32_t ind = 0;
	uint8_t send_buffer[50];
//	send_buffer[ind++] = COMM_GET_DECODED_BALANCE;
	buffer_append_float32_auto(send_buffer, d->pid_value, &ind);
	buffer_append_float32_auto(send_buffer, d->pitch_angle, &ind);
	buffer_append_float32_auto(send_buffer, d->roll_angle, &ind);
	buffer_append_float32_auto(send_buffer, d->diff_time, &ind);
	buffer_append_float32_auto(send_buffer, d->motor_current, &ind);
	buffer_append_float32_auto(send_buffer, app_balance_get_debug(d->debug_render_1), &ind);
	buffer_append_uint16(send_buffer, d->state, &ind);
	buffer_append_uint16(send_buffer, d->switch_state, &ind);
	buffer_append_float32_auto(send_buffer, d->adc1, &ind);
	buffer_append_float32_auto(send_buffer, d->adc2, &ind);
	buffer_append_float32_auto(send_buffer, app_balance_get_debug(d->debug_render_2), &ind);
	VESC_IF->send_app_data(send_buffer, ind);
}

// Handler for incoming app commands
static void on_command_recieved(unsigned char *buffer, unsigned int len) {
	data *d = (data*)ARG;

	if(len > 0){
		uint8_t command = buffer[0];
		if(command == 0x01){
			send_realtime_data(d);
		}else{
			VESC_IF->printf("Unknown command received %d", command);
		}
	}
}

// Register get_debug as a lisp extension
static lbm_value ext_bal_dbg(lbm_value *args, lbm_uint argn) {
	if (argn != 1 || !VESC_IF->lbm_is_number(args[0])) {
		return VESC_IF->lbm_enc_sym_eerror;
	}

	return VESC_IF->lbm_enc_float(app_balance_get_debug(VESC_IF->lbm_dec_as_i32(args[0])));
}

// These functions are used to send the config page to VESC Tool
// and to make persistent read and write work
static int get_cfg(uint8_t *buffer, bool is_default) {
	data *d = (data*)ARG;
	balance_config *cfg = VESC_IF->malloc(sizeof(balance_config));

	*cfg = d->balance_conf;

	if (is_default) {
		confparser_set_defaults_balance_config(cfg);
	}

	int res = confparser_serialize_balance_config(buffer, cfg);
	VESC_IF->free(cfg);

	return res;
}

static bool set_cfg(uint8_t *buffer) {
	data *d = (data*)ARG;
	bool res = confparser_deserialize_balance_config(buffer, &(d->balance_conf));

	// Store to EEPROM
	if (res) {
		uint32_t ints = sizeof(balance_config) / 4 + 1;
		uint32_t *buffer = VESC_IF->malloc(ints * sizeof(uint32_t));
		bool write_ok = true;
		memcpy(buffer, &(d->balance_conf), sizeof(balance_config));
		for (uint32_t i = 0;i < ints;i++) {
			eeprom_var v;
			v.as_u32 = buffer[i];
			if (!VESC_IF->store_eeprom_var(&v, i + 1)) {
				write_ok = false;
				break;
			}
		}

		VESC_IF->free(buffer);

		if (write_ok) {
			eeprom_var v;
			v.as_u32 = BALANCE_CONFIG_SIGNATURE;
			VESC_IF->store_eeprom_var(&v, 0);
		}

		configure(d);
	}

	return res;
}

static int get_cfg_xml(uint8_t **buffer) {
	// Note: As the address of data_balance_config_ is not known
	// at compile time it will be relative to where it is in the
	// linked binary. Therefore we add PROG_ADDR to it so that it
	// points to where it ends up on the STM32.
	*buffer = data_balance_config_ + PROG_ADDR;
	return DATA_BALANCE_CONFIG__SIZE;
}

// Called when code is stopped
static void stop(void *arg) {
	data *d = (data*)arg;
	VESC_IF->set_app_data_handler(NULL);
	VESC_IF->conf_custom_clear_configs();
	VESC_IF->request_terminate(d->thread);
	VESC_IF->printf("Balance App Terminated");
	VESC_IF->free(d);
}

INIT_FUN(lib_info *info) {
	INIT_START

	data *d = VESC_IF->malloc(sizeof(data));
	memset(d, 0, sizeof(data));
	
	if (!d) {
		VESC_IF->printf("Out of memory!");
		return false;
	}

	// Read config from EEPROM if signature is correct
	eeprom_var v;
	uint32_t ints = sizeof(balance_config) / 4 + 1;
	uint32_t *buffer = VESC_IF->malloc(ints * sizeof(uint32_t));
	bool read_ok = VESC_IF->read_eeprom_var(&v, 0);
	if (read_ok && v.as_u32 == BALANCE_CONFIG_SIGNATURE) {
		for (uint32_t i = 0;i < ints;i++) {
			if (!VESC_IF->read_eeprom_var(&v, i + 1)) {
				read_ok = false;
				break;
			}
			buffer[i] = v.as_u32;
		}
	} else {
		read_ok = false;
	}
	
	if (read_ok) {
		memcpy(&(d->balance_conf), buffer, sizeof(balance_config));
	} else {
		confparser_set_defaults_balance_config(&(d->balance_conf));
	}
	
	VESC_IF->free(buffer);

	info->stop_fun = stop;	
	info->arg = d;
	
	VESC_IF->conf_custom_add_config(get_cfg, set_cfg, get_cfg_xml);

	configure(d);

	d->thread = VESC_IF->spawn(balance_thd, 2048, "Balance Main", d);

	VESC_IF->set_app_data_handler(on_command_recieved);
	VESC_IF->lbm_add_extension("ext-balance-dbg", ext_bal_dbg);

	return true;
}

