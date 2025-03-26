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
	INPUTTILT_NONE = 0,
	INPUTTILT_UART,
	INPUTTILT_PPM
} INPUTTILT_REMOTE_TYPE;

typedef struct {
	float version;
	float disable_pkg;
	float kp0;
	float current1;
	float current2;
	float current3;
	float current4;
	float current5;
	float current6;
	float pitch1;
	float pitch2;
	float pitch3;
	float pitch4;
	float pitch5;
	float pitch6;
	bool pitch_kp_input;
	float mahony_kp;
	float kp_rate;
	float pitch_filter;
	float kalman_factor1;
	float kalman_factor2;
	float kalman_factor3;
	bool brake_curve;
	float brake_kp0;
	float brakekp_rate;
	float brakecurrent1;
	float brakecurrent2;
	float brakecurrent3;
	float brakecurrent4;
	float brakecurrent5;
	float brakecurrent6;
	float brakepitch1;
	float brakepitch2;
	float brakepitch3;
	float brakepitch4;
	float brakepitch5;
	float brakepitch6;
	bool pitch_kp_input_brake;
	float roll_kp1;
	float roll_kp2;
	float roll_kp3;
	float roll1;
	float roll2;
	float roll3;
	float brkroll_kp1;
	float brkroll_kp2;
	float brkroll_kp3;
	float brkroll1;
	float brkroll2;
	float brkroll3;
	uint16_t rollkp_higherpm;
	uint16_t roll_hs_higherpm;
	uint16_t rollkp_lowerpm;
	uint16_t roll_hs_lowerpm;
	uint16_t rollkp_maxscale;
	int8_t roll_hs_maxscale;
	float yaw_kp1;
	float yaw_kp2;
	float yaw_kp3;
	float yaw1;
	float yaw2;
	float yaw3;
	float brkyaw_kp1;
	float brkyaw_kp2;
	float brkyaw_kp3;
	float brkyaw1;
	float brkyaw2;
	float brkyaw3;
	uint16_t yaw_minerpm;
	bool is_surge_enabled;
	uint16_t surge_startcurrent;
	uint16_t surge_start_hd_current;
	uint16_t surge_scaleduty;
	float surge_pitchmargin;
	float surge_maxangle;
	uint16_t surge_minerpm;
	uint16_t surge_duty;
	float current_filter;
	uint16_t tiltback_surge_speed;
	bool is_traction_enabled;
	uint16_t wheelslip_accelstart;
	uint16_t wheelslip_accelslowed;
	uint8_t wheelslip_accelend;
	uint16_t wheelslip_scaleaccel;
	uint16_t wheelslip_scaleerpm;
	uint8_t wheelslip_filter_freq;
	uint8_t wheelslip_max_angle;
	uint8_t wheelslip_accelhold;
	uint8_t wheelslip_resettime;
	bool is_tc_braking_enabled;
	int8_t tc_braking_angle;
	uint16_t tc_braking_min_erpm;	
	bool enable_speed_stability;
	bool enable_throttle_stability;
	uint16_t stabl_pitch_max_scale;
	uint16_t stabl_rate_max_scale;
	uint16_t stabl_min_erpm;
	uint16_t stabl_max_erpm;
	uint16_t stabl_ramp;
	uint16_t stabl_ramp_down;
	uint16_t hertz;
	uint16_t fault_pitch;
	uint16_t fault_roll;
	float fault_adc1;
	float fault_adc2;
	uint16_t fault_delay_pitch;
	uint16_t fault_delay_switch_half;
	uint16_t fault_delay_switch_full;
	uint16_t fault_adc_half_erpm;
	bool fault_is_dual_switch;
	bool fault_moving_fault_disabled;
	bool is_quickstop_enabled;
	uint16_t quickstop_erpm;
	uint8_t quickstop_angle;
	uint16_t tiltback_duty_angle;
	uint16_t tiltback_duty_speed;
	uint16_t tiltback_duty;
	uint16_t tiltback_hv_angle;
	uint16_t tiltback_hv_speed;
	float tiltback_hv;
	uint16_t tiltback_lv_angle;
	uint16_t tiltback_lv_speed;
	float tiltback_lv;
	float midvolt_warning;
	float lowvolt_warning;
	uint16_t tiltback_ht_angle;
	uint16_t tiltback_ht_speed;
	uint16_t tiltback_return_speed;
	float tiltback_constant;
	uint16_t tiltback_constant_erpm;
	bool haptic_buzz_current;
	uint16_t tone_freq_high_current;
	float tone_volt_high_current;
	bool haptic_buzz_duty;
	uint16_t tone_freq_high_duty;
	float tone_volt_high_duty;
	float beep_voltage;
	INPUTTILT_REMOTE_TYPE inputtilt_remote_type;
	uint16_t inputtilt_speed;
	float inputtilt_angle_limit;
	uint16_t inputtilt_smoothing_factor;
	bool inputtilt_invert_throttle;
	uint8_t inputtilt_deadband;
	float stickytiltval1;
	float stickytiltval2;
	bool is_stickytilt_enabled;
	uint16_t stickytilt_holdcurrent;
	uint8_t noseangling_speed;
	float startup_pitch_tolerance;
	uint16_t startup_speed;
	bool startup_simplestart_enabled;
	bool startup_pushstart_enabled;
	bool startup_dirtylandings_enabled;
	float simple_start_delay;
	uint16_t brake_current;
	uint16_t overcurrent_margin;
	float overcurrent_period;
	bool is_beeper_enabled;
	bool is_dutybeep_enabled;
	bool is_footbeep_enabled;
	bool is_tunedebug_enabled;
	bool is_surgedebug_enabled;
	bool is_tcdebug_enabled;
	bool is_yawdebug_enabled;
	bool is_brakingdebug_enabled;
} tnt_config;

// DATATYPES_H_
#endif
