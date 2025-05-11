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
	float last_accel_z;
	float accel[3];
	float abs_roll_angle;
 	float true_pitch_angle;
	float gyro[3];
	float pitch_smooth; // Low Pass Filter
	Biquad pitch_biquad; // Low Pass Filter
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
	uint8_t imu_counter;
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
} YawDebugData;

typedef struct {
	float rest_time;
	float last_rest_time;
	float ride_time;
	float last_ride_time;
	bool run_flag;
	float min_yaw_change;
	float yaw_timer;
	int8_t last_yaw_sign;
	int8_t yaw_sign;
	float carve_timer;
	uint32_t carve_chain;
	uint32_t carves_total;
	uint32_t max_carve_chain;
	float carves_mile;
	float distance;
	float efficiency;
	float speed_avg;
	float current_avg;
	float power_avg;
	float reset_mileage;
	float max_roll_temp;
	float max_roll;
	float max_roll_avg;
	float max_yaw_temp;
	float max_yaw;
	float max_yaw_avg;
} RideTrackData;

void runtime_data_update(RuntimeData *rt);
void apply_pitch_filters(RuntimeData *rt, tnt_config *config);
void calc_yaw_change(YawData *yaw, float yaw_angle, YawDebugData *yaw_dbg);
void reset_runtime(RuntimeData *rt, YawData *yaw, YawDebugData *yaw_dbg);
void configure_runtime(RuntimeData *rt, tnt_config *config);
void rest_timer(RideTrackData *ridetrack, RuntimeData *rt);
void ride_timer(RideTrackData *ridetrack, RuntimeData *rt);
void check_odometer(RuntimeData *rt);
void configure_ride_tracking(RideTrackData *ridetrack, tnt_config *config);
void reset_ride_tracking(RideTrackData *ridetrack, tnt_config *config);
void ride_tracking_update(RideTrackData *ridetrack, RuntimeData *rt, YawData *yaw);
void carve_tracking(RuntimeData *rt, YawData *yaw, RideTrackData *ridetrack);
