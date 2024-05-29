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

void yaw_reset(YawData *yaw, YawDebugData *yaw_dbg);
void calc_yaw_change(YawData *yaw, float yaw_angle, YawDebugData *yaw_dbg);
float erpm_scale(float lowvalue, float highvalue, float lowscale, float highscale, float abs_erpm); 
