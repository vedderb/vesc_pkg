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
#include "conf/datatypes.h"
#include "vesc_c_if.h"
#include <stdint.h>
#include <stdbool.h>
#include "runtime.h"
#include "traction.h"

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


void configure_ride_tracking(RideTrackData *ridetrack, tnt_config *config);
void reset_ride_tracking(RideTrackData *ridetrack);
void rest_timer(RideTrackData *ridetrack, RuntimeData *rt);
void ride_timer(RideTrackData *ridetrack, RuntimeData *rt);
void reset_ride_tracking_on_configure(RideTrackData *ridetrack, tnt_config *config, TractionDebugData *traction_dbg);
void ride_tracking_update(RideTrackData *ridetrack, RuntimeData *rt, YawData *yaw);
void carve_tracking(RuntimeData *rt, YawData *yaw, RideTrackData *ridetrack);
