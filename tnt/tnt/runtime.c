// Copyright 2024 Michael Silberstein
//
// This file is part of the Trick and Trail VESC package.
//
// Refloat VESC package is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// Refloat VESC package is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.

#include "runtime.h"
#include "vesc_c_if.h"
#include <math.h>
#include "utils_tnt.h"
#include "biquad.h"

void runtime_data_update(RuntimeData *rt) {
	// Update times
	rt->current_time = VESC_IF->system_time();
	if (rt->last_time == 0) {
		rt->last_time = rt->current_time;
	}
	rt->diff_time = rt->current_time - rt->last_time;
	rt->last_time = rt->current_time;
}

void imu_data_update(RuntimeData *rt) {	
	// Get the IMU Values
	float roll_rad = VESC_IF->imu_get_roll();
	float sin_roll = sinf(roll_rad);
	float cos_roll = cosf(roll_rad);
	rt->roll_angle = rad2deg(roll_rad);
	rt->abs_roll_angle = fabsf(rt->roll_angle);
	rt->true_pitch_angle = rad2deg(VESC_IF->ahrs_get_pitch(&rt->m_att_ref)); // True pitch is derived from the secondary IMU filter running with kp=0.2
	rt->pitch_angle = rad2deg(VESC_IF->imu_get_pitch());
	VESC_IF->imu_get_gyro(rt->gyro);
	rt->gyro_y = rt->gyro[1]; // where y is "up" and "down" relative to the IMU
	rt->gyro_turning = sin_roll * sin_roll * rt->gyro[1] - cos_roll * sin_roll * rt->gyro[2]; //the gyro imparted to the y direction from turning the board
	rt->yaw_angle = rad2deg(VESC_IF->imu_get_yaw());
	rt->gyro_yaw = cos_roll * rt->gyro[2] + sin_roll * rt->gyro[1]; // yaw relative to level
}

void apply_filters(RuntimeData *rt, tnt_config *config){
	//Apply low pass and Kalman filters to pitch
	if (config->pitch_filter > 0) 
		rt->pitch_smooth = biquad_process(&rt->pitch_biquad, rt->pitch_angle);
	else
		rt->pitch_smooth = rt->pitch_angle;
	
	if (config->gyro_filter > 0) 
		rt->gyro_y_smooth = biquad_process(&rt->gyro_y_biquad, rt->gyro_y);
	else
		rt->gyro_y_smooth = rt->gyro_y;
}

void calc_yaw_change(YawData *yaw, RuntimeData *rt, YawDebugData *yaw_dbg){ 
	ema(&yaw->change, rt->yaw_ema_factor, rt->gyro_yaw);
	yaw->abs_change = fabsf(yaw->change);
	yaw_dbg->debug1 = yaw->change;
	yaw_dbg->debug3 = fmaxf(yaw->abs_change, yaw_dbg->debug3);
}

void reset_runtime(RuntimeData *rt, YawData *yaw, YawDebugData *yaw_dbg) {
	//Low pass pitch filter
	rt->pitch_smooth = rt->pitch_angle;
	biquad_reset(&rt->pitch_biquad);

	//Yaw
	yaw->abs_change = 0;
	yaw_dbg->debug2 = 0;
	yaw_dbg->debug3 = 0;
	
	rt->brake_timeout = 0;

	biquad_reset(&rt->gyro_y_biquad);
	rt->gyro_y_smooth = 0;
}

void configure_runtime(RuntimeData *rt, tnt_config *config) {
	// This timer is used to determine how long the board has been disengaged / idle. subtract 1 second to prevent the haptic buzz disengage click on "write config"
	rt->disengage_timer = rt->current_time - 1;

	// Loop time in microseconds
	rt->imu_sample_rate = VESC_IF->get_cfg_int(CFG_PARAM_IMU_sample_rate);
	rt->loop_rate = max(rt->imu_sample_rate, config->hertz);// If the IMU is faster than the user configured pkg loop rate, use the IMU rate
	rt->imu_loop_time_us = 1e6 / rt->imu_sample_rate;
	rt->loop_time_us = 1e6 / rt->loop_rate; 

	// Loop time in seconds times 20 for a nice long grace period
	rt->motor_timeout_s = 20.0f / rt->loop_rate;
	
	//Pitch Biquad Configure
	biquad_configure(&rt->pitch_biquad, BQ_LOWPASS, min(1, 1.0f * config->pitch_filter / rt->imu_sample_rate)); 
	
	// EMA Filter Factor for Current Output
	rt->ema_factor = min(1 , config->ema_factor * 832.0f / rt->loop_rate);

	//Gyro Y Biquad Configure
	biquad_configure(&rt->gyro_y_biquad, BQ_NOTCH,  max(0.02f, min(0.1f, 1.0f * config->gyro_filter / rt->imu_sample_rate)));

	// EMA Filter Factor for Yaw Change
	rt->yaw_ema_factor = min(1 , 100.0f / rt->loop_rate);
}

void check_odometer(RuntimeData *rt) { 
	//check_odometer: see if we need to write back the odometer during fault state
	// Make odometer persistent if we've gone 200m or more
	if (rt->odometer_dirty > 0) {
		float stored_odo = VESC_IF->mc_get_odometer();
		if ((stored_odo > rt->odometer + 200) || (stored_odo < rt->odometer - 10000)) {
			if (rt->odometer_dirty == 1) {
				// Wait 10 seconds before writing to avoid writing if immediately continuing to ride
				rt->odo_timer = rt->current_time;
				rt->odometer_dirty++;
			}
			else if ((rt->current_time - rt->odo_timer) > 10) {
				VESC_IF->store_backup_data();
				rt->odometer = VESC_IF->mc_get_odometer();
				rt->odometer_dirty = 0;
			}
		}
	}
}
