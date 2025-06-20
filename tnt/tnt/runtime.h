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

#pragma once
#include "biquad.h"
#include "kalman.h"
#include "conf/datatypes.h"
#include "vesc_c_if.h"
#include <stdint.h>
#include <stdbool.h>

typedef struct { //Run time values used in various features
	float pitch_angle;
	float roll_angle;
	float yaw_angle;
	float current_time;
	float accel[3];
	float abs_roll_angle;
 	float true_pitch_angle;
	float gyro[3];
	float gyro_y;
	float gyro_z;
	float pitch_smooth; // Low Pass Filter
	Biquad pitch_biquad; // Low Pass Filter
	float gyro_y_smooth; // Low Pass Filter
	Biquad gyro_y_biquad; // Low Pass Filter
	KalmanFilter pitch_kalman; // Kalman Filter
	float pitch_smooth_kalman; // Kalman Filter
	float diff_time, last_time;
	ATTITUDE_INFO m_att_ref; // Feature: True Pitch / Yaw
	bool brake_pitch, brake_roll, brake_yaw;
	float disengage_timer, nag_timer;
	uint32_t loop_time_us;
	float motor_timeout_s;
	float odo_timer;
	int odometer_dirty;
	uint64_t odometer;
	float brake_timeout;
	float fault_angle_pitch_timer, fault_angle_roll_timer, fault_switch_timer, fault_switch_half_timer; // Seconds
	float imu_rate_factor;
} RuntimeData;

typedef struct {
	float last_angle;
	float last_change;
	float change;
	float abs_change;
	float aggregate;
} YawData;

typedef struct {
	float debug1; //change
	float debug2; //max kp
	float debug3; //kp unscaled
	float debug4; //kp scaled
	float debug5; //erpm scaler
	float debug6; // yaw angle current
} YawDebugData;

void runtime_data_update(RuntimeData *rt);
void apply_pitch_filters(RuntimeData *rt, tnt_config *config);
void calc_yaw_change(YawData *yaw, RuntimeData *rt, YawDebugData *yaw_dbg, int hertz);
void reset_runtime(RuntimeData *rt, YawData *yaw, YawDebugData *yaw_dbg);
void configure_runtime(RuntimeData *rt, tnt_config *config);
void check_odometer(RuntimeData *rt);
