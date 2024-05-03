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

typedef enum {
	HAPTIC_BUZZ_NONE = 0,
	HAPTIC_BUZZ_AUDIBLE1,
	HAPTIC_BUZZ_AUDIBLE2,
	HAPTIC_BUZZ_AUDIBLE3,
	HAPTIC_BUZZ_VIBRATING1,
	HAPTIC_BUZZ_VIBRATING2,
	HAPTIC_BUZZ_VIBRATING3,
	HAPTIC_BUZZ_ALTERNATING
} HAPTIC_BUZZ_TYPE;

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
	float rollkp_higherpm;
	float rollkp_lowerpm;
	float rollkp_maxscale;
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
	float yaw_minerpm;
	float yaw_higherpm;
	float yaw_lowerpm;
	float yaw_maxscale;
	bool is_surge_enabled;
	float surge_startcurrent;
	float surge_start_hd_current;
	float surge_scaleduty;
	float surge_pitchmargin;
	float surge_maxangle;
	float surge_minerpm;
	float surge_duty;
	float tiltback_surge_speed;
	bool is_traction_enabled;
	float wheelslip_margin;
	float wheelslip_accelstart;
	float wheelslip_accelend;
	float wheelslip_scaleaccel;
	float wheelslip_scaleerpm;
	bool is_drop_enabled;
	float drop_z_accel;
	float drop_z_highaccel;
	uint16_t drop_count_limit;
	float drop_motor_accel;
	float tiltback_drop_speed;
	bool enable_speed_stability;
	bool enable_throttle_stability;
	float stabl_pitch_max_scale;
	float stabl_rate_max_scale;
	float stabl_min_erpm;
	float stabl_max_erpm;
	float stabl_ramp;
	uint16_t hertz;
	float fault_pitch;
	float fault_roll;
	float fault_adc1;
	float fault_adc2;
	uint16_t fault_delay_pitch;
	uint16_t fault_delay_switch_half;
	uint16_t fault_delay_switch_full;
	uint16_t fault_adc_half_erpm;
	bool fault_is_dual_switch;
	bool fault_moving_fault_disabled;
	float tiltback_duty_angle;
	float tiltback_duty_speed;
	float tiltback_duty;
	float tiltback_hv_angle;
	float tiltback_hv_speed;
	float tiltback_hv;
	float tiltback_lv_angle;
	float tiltback_lv_speed;
	float tiltback_lv;
	float tiltback_ht_angle;
	float tiltback_ht_speed;
	float tiltback_return_speed;
	float tiltback_constant;
	uint16_t tiltback_constant_erpm;
	int haptic_buzz_intensity;
	int haptic_buzz_min;
	HAPTIC_BUZZ_TYPE haptic_buzz_current;
	INPUTTILT_REMOTE_TYPE inputtilt_remote_type;
	float inputtilt_speed;
	float inputtilt_angle_limit;
	uint16_t inputtilt_smoothing_factor;
	bool inputtilt_invert_throttle;
	float inputtilt_deadband;
	float stickytiltval1;
	float stickytiltval2;
	bool is_stickytilt_enabled;
	uint16_t stickytilt_holdcurrent;
	float noseangling_speed;
	float startup_pitch_tolerance;
	float startup_speed;
	bool startup_simplestart_enabled;
	bool startup_pushstart_enabled;
	bool startup_dirtylandings_enabled;
	float brake_current;
	int overcurrent_margin;
	float overcurrent_period;
	bool is_beeper_enabled;
	bool is_dutybeep_enabled;
	bool is_footbeep_enabled;
	bool is_tunedebug_enabled;
	bool is_surgedebug_enabled;
	bool is_tcdebug_enabled;
	bool is_dropdebug_enabled;
	bool is_yawdebug_enabled;
} tnt_config;

// DATATYPES_H_
#endif
