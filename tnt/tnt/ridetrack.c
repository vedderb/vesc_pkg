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

#include "ridetrack.h"
#include "utils_tnt.h"
#include <math.h>

void configure_ride_tracking(RideTrackData *ridetrack, tnt_config *config) {
	ridetrack->min_yaw_change = 100.0f / config->hertz;
}

void reset_ride_tracking(RideTrackData *ridetrack) {
	ridetrack->carve_chain = 0;
	ridetrack->yaw_sign = 0;
}

void ride_timer(RideTrackData *ridetrack, RuntimeData *rt){
	if(ridetrack->run_flag) { //First trigger run flag and reset last ride time
		ridetrack->ride_time += rt->current_time - ridetrack->last_ride_time;
	}
	ridetrack->run_flag = true;
	ridetrack->last_ride_time = rt->current_time;
}

void rest_timer(RideTrackData *ridetrack, RuntimeData *rt){
	if(!ridetrack->run_flag) { //First trigger run flag and reset last rest time
		ridetrack->rest_time += rt->current_time - ridetrack->last_rest_time;
	}
	ridetrack->run_flag = false;
	ridetrack->last_rest_time = rt->current_time;
}

void reset_ride_tracking_on_configure(RideTrackData *ridetrack, tnt_config *config, TractionDebug *traction_dbg) {
	if (config->is_resettripdata_enabled) {
		ridetrack->carves_total = 0;
		ridetrack->max_carve_chain = 0;
		ridetrack->ride_time = 0;
		ridetrack->rest_time = 0;
		ridetrack->reset_mileage = VESC_IF->mc_get_distance_abs() * 0.000621;
		VESC_IF->mc_get_amp_hours(true);
		VESC_IF->mc_get_amp_hours_charged(true);
		VESC_IF->mc_get_watt_hours(true);
		VESC_IF->mc_get_watt_hours_charged(true);
		VESC_IF->mc_stat_reset();
		ridetrack->max_roll_temp = 0;
		ridetrack->max_roll = 0;
		ridetrack->max_roll_avg = 0;
		ridetrack->max_yaw_temp = 0;
		ridetrack->max_yaw = 0;
		ridetrack->max_yaw_avg = 0;
		traction_dbg->max_time = 0;
		traction_dbg->bonks_total = 0;
	}
}

void ride_tracking_update(RideTrackData *ridetrack, RuntimeData *rt, YawData *yaw, tnt_config *config) {
	carve_tracking(rt, yaw, ridetrack, config);
	float corr_factor;
	if (ridetrack->ride_time > 0) {
		corr_factor =  ridetrack->ride_time / (ridetrack->rest_time + ridetrack->ride_time);
	} else {corr_factor = 1;}
	ridetrack->distance = VESC_IF->mc_get_distance_abs() * 0.000621 - ridetrack->reset_mileage;
	ridetrack->speed_avg = VESC_IF->mc_stat_speed_avg() * 3.6 * .621 * corr_factor;
	ridetrack->current_avg = VESC_IF->mc_stat_current_avg() * corr_factor;
	ridetrack->power_avg = VESC_IF->mc_stat_power_avg() * corr_factor;
	ridetrack->efficiency = ridetrack->distance < 0.001 ? 0 : (VESC_IF->mc_get_watt_hours(false) - VESC_IF->mc_get_watt_hours_charged(false)) / (ridetrack->distance);
}

void carve_tracking(RuntimeData *rt, YawData *yaw, RideTrackData *ridetrack, tnt_config *config) {
	//Apply a minimum yaw change and time yaw change is applied to filter out noise
	if (yaw->abs_change < ridetrack->min_yaw_change) {
		ridetrack->yaw_timer = rt->current_time;
	} else if (rt->current_time - ridetrack->yaw_timer > .005) {
		ridetrack->yaw_sign = sign(yaw->change);

		// Track the change in yaw change sign to determine carves
		if (ridetrack->last_yaw_sign != ridetrack->yaw_sign){ 
			ridetrack->carve_timer = rt->current_time; //reset time out every yaw change
			if (ridetrack->last_yaw_sign != 0) //don't include the first turn
				ridetrack->carve_chain++;
			if (ridetrack->carve_chain > 1) { //require 3 turns to be included in carve total
				ridetrack->carves_total++;
				ridetrack->max_roll_avg = (ridetrack->max_roll_avg * (ridetrack->carves_total -1) + ridetrack->max_roll_temp) / ridetrack->carves_total;
				ridetrack->max_yaw_avg = (ridetrack->max_yaw_avg * (ridetrack->carves_total -1) + ridetrack->max_yaw_temp) / ridetrack->carves_total;
				ridetrack->max_roll = fmaxf( ridetrack->max_roll, ridetrack->max_roll_temp);
				ridetrack->max_yaw = fmaxf( ridetrack->max_yaw, ridetrack->max_yaw_temp);
				ridetrack->max_roll_temp = 0;
				ridetrack->max_yaw_temp = 0;
			}
		}
	}
	
	//Time out of 3 seconds if a yaw change is not initiated
	if (rt->current_time - ridetrack->carve_timer > 3) {
		ridetrack->carve_chain = 0;
		ridetrack->yaw_sign = 0;
	} else {
		ridetrack->max_carve_chain = fmaxf(ridetrack->max_carve_chain, ridetrack->carve_chain);
		ridetrack->max_yaw_temp = fmaxf( ridetrack->max_yaw_temp, yaw->abs_change > 1500.0 / config->hertz ? 0 : yaw->abs_change);
		ridetrack->max_roll_temp = fmaxf( ridetrack->max_roll_temp, rt->abs_roll_angle);
	}
	ridetrack->last_yaw_sign = ridetrack->yaw_sign;
	ridetrack->carves_mile = ridetrack->carves_total / ridetrack->distance;
}
