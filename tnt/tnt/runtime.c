// Copyright 2024 Lukas Hrazky
//
// This file is part of the Refloat VESC package.
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
#include "kalman.h"

void runtime_data_update(RuntimeData *rt) {
	// Update times
	rt->current_time = VESC_IF->system_time();
	if (rt->last_time == 0) {
		rt->last_time = rt->current_time;
	}
	rt->diff_time = rt->current_time - rt->last_time;
	rt->last_time = rt->current_time;
	
	// Get the IMU Values
	rt->roll_angle = rad2deg(VESC_IF->imu_get_roll());
	rt->abs_roll_angle = fabsf(rt->roll_angle);
	rt->true_pitch_angle = rad2deg(VESC_IF->ahrs_get_pitch(&rt->m_att_ref)); // True pitch is derived from the secondary IMU filter running with kp=0.2
	rt->pitch_angle = rad2deg(VESC_IF->imu_get_pitch());
	VESC_IF->imu_get_gyro(rt->gyro);
	VESC_IF->imu_get_accel(rt->accel); //Used for drop detection
	rt->yaw_angle = rad2deg(VESC_IF->ahrs_get_yaw(&rt->m_att_ref));
}

void apply_pitch_filters(RuntimeData *rt, tnt_config *config){
	//Apply low pass and Kalman filters to pitch
	if (config->pitch_filter > 0) {
		rt->pitch_smooth = biquad_process(&rt->pitch_biquad, rt->pitch_angle);
	} else {rt->pitch_smooth = rt->pitch_angle;}
	if (config->kalman_factor1 > 0) {
		 apply_kalman(rt->pitch_smooth, rt->gyro[1], &rt->pitch_smooth_kalman, rt->diff_time, &rt->pitch_kalman);
	} else {rt->pitch_smooth_kalman = rt->pitch_smooth;}
}

void calc_yaw_change(YawData *yaw, RuntimeData *rt, YawDebugData *yaw_dbg, int hertz){ 
	//float new_change = (rt->yaw_angle - yaw->last_angle) / rt->imu_rate_factor;
	//if ((new_change == 0) || // Exact 0's only happen when the IMU is not updating between loops
	//    (fabsf(new_change) > 100)) { // yaw flips signs at 180, ignore those changes
	//	new_change = yaw->last_change;
	//}
	//if (sign(rt->yaw_angle) != sign(yaw->last_angle)) // yaw flips signs at 180, ignore those changes
	//	new_change = yaw->last_change;

	//yaw->last_change = new_change;
	//yaw->last_angle = rt->yaw_angle;
	//ema(&yaw->change, 0.2 * 832 / hertz, new_change); //originally configured for 0.2 at 832 Hz
	yaw->change = rt->gyro[2];
	yaw->abs_change = fabsf(yaw->change);
	yaw_dbg->debug1 = yaw->change;
	yaw_dbg->debug3 = fmaxf(yaw->abs_change, yaw_dbg->debug3);
}

void reset_runtime(RuntimeData *rt, YawData *yaw, YawDebugData *yaw_dbg) {
	//Low pass pitch filter
	rt->pitch_smooth = rt->pitch_angle;
	biquad_reset(&rt->pitch_biquad);
	
	//Kalman filter
	reset_kalman(&rt->pitch_kalman);
	rt->pitch_smooth_kalman = rt->pitch_angle;

	//Yaw
	yaw->last_angle = rad2deg(VESC_IF->ahrs_get_yaw(&rt->m_att_ref));
	yaw->last_change = 0;
	yaw->abs_change = 0;
	yaw_dbg->debug2 = 0;
	yaw_dbg->debug3 = 0;
	
	rt->brake_timeout = 0;
}

void configure_runtime(RuntimeData *rt, tnt_config *config) {
	// This timer is used to determine how long the board has been disengaged / idle. subtract 1 second to prevent the haptic buzz disengage click on "write config"
	rt->disengage_timer = rt->current_time - 1;

	// Loop time in microseconds
	rt->loop_time_us = 1e6 / config->hertz;

	// Loop time in seconds times 20 for a nice long grace period
	rt->motor_timeout_s = 20.0f / config->hertz;
	
	//Pitch Biquad Configure
	biquad_configure(&rt->pitch_biquad, BQ_LOWPASS, 1.0 * config->pitch_filter / config->hertz); 

	//Pitch Kalman Configure
	configure_kalman(config, &rt->pitch_kalman);

	//Yaw change correction factor
	rt->imu_rate_factor = lerp(832, 10000, 1, 2, config->hertz);
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
