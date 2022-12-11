/*
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

#ifndef DATATYPES_H_
#define DATATYPES_H_

#include <stdint.h>
#include <stdbool.h>

typedef enum {
	NONE = 0,
	UART,
	PPM
} FLOAT_INPUTTILT_REMOTE_TYPE;

typedef struct {
	float float_version;
	float kp;
	float ki;
	float kd;
	float kp2;
	float ki2;
	float kd2;
	float mahony_kp;
	uint16_t hertz;
	uint16_t loop_time_filter;
	float fault_pitch;
	float fault_roll;
	float fault_duty;
	float fault_adc1;
	float fault_adc2;
	uint16_t fault_delay_pitch;
	uint16_t fault_delay_roll;
	uint16_t fault_delay_switch_half;
	uint16_t fault_delay_switch_full;
	uint16_t fault_adc_half_erpm;
	bool fault_is_dual_switch;
	bool fault_darkride_enabled;
	bool fault_reversestop_enabled;
	float tiltback_duty_angle;
	float tiltback_duty_speed;
	float tiltback_duty;
	float tiltback_hv_angle;
	float tiltback_hv_speed;
	float tiltback_hv;
	float tiltback_lv_angle;
	float tiltback_lv_speed;
	float tiltback_lv;
	float tiltback_return_speed;
	float tiltback_constant;
	uint16_t tiltback_constant_erpm;
	float tiltback_variable;
	float tiltback_variable_max;
	FLOAT_INPUTTILT_REMOTE_TYPE inputtilt_remote_type;
	float inputtilt_speed;
	float inputtilt_angle_limit;
	bool inputtilt_invert_throttle;
	float inputtilt_deadband;
	float noseangling_speed;
	float startup_pitch_tolerance;
	float startup_roll_tolerance;
	float startup_speed;
	float startup_click_current;
	float deadzone;
	float brake_current;
	uint16_t brake_timeout;
	float ki_limit;
	uint16_t kd_pt1_lowpass_frequency;
	uint16_t kd_pt1_highpass_frequency;
	float booster_angle;
	float booster_ramp;
	float booster_current;
	float torquetilt_start_current;
	float torquetilt_angle_limit;
	float torquetilt_on_speed;
	float torquetilt_off_speed;
	float torquetilt_strength;
	float torquetilt_strength_regen;
	float torquetilt_filter;
	float atr_strength_up;
	float atr_strength_down;
	float atr_torque_offset;
	float atr_speed_boost;
	float atr_angle_limit;
	float atr_on_speed;
	float atr_off_speed;
	float atr_response_boost;
	float atr_transition_boost;
	float atr_filter;
	float atr_amps_accel_ratio;
	float atr_amps_decel_ratio;
	float braketilt_strength;
	float braketilt_lingering;
	float turntilt_strength;
	float turntilt_angle_limit;
	float turntilt_start_angle;
	uint16_t turntilt_start_erpm;
	float turntilt_speed;
	uint16_t turntilt_erpm_boost;
	uint16_t turntilt_erpm_boost_end;
	int turntilt_yaw_aggregate;
	bool is_buzzer_enabled;
} float_config;

// DATATYPES_H_
#endif
