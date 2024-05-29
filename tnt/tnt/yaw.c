// Copyright 2024 Michael Silberstein
// This code was originally written by the authors of Float package and 
// modifed for this package
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

#include "yaw.h"
#include "utils_tnt.h"
#include <math.h>

void calc_yaw_change(YawData *yaw, float yaw_angle, YawDebugData *yaw_dbg){ 
	float new_change = yaw_angle - yaw->last_angle;
	if ((new_change == 0) || // Exact 0's only happen when the IMU is not updating between loops
	    (fabsf(new_change) > 100)) { // yaw flips signs at 180, ignore those changes
		new_change = yaw->last_change;
	}
	yaw->last_change = new_change;
	yaw->last_angle = yaw_angle;
	yaw->change = yaw->change * 0.8 + 0.2 * (new_change);
	yaw->abs_change = fabsf(yaw->change);
	yaw_dbg->debug1 = yaw->change;
}

void yaw_reset(YawData *yaw, YawDebugData *yaw_dbg){ 
	yaw->last_angle = 0;
	yaw->last_change = 0;
	yaw->abs_change = 0;
	yaw_dbg->debug2 = 0;
}

float erpm_scale(float lowvalue, float highvalue, float lowscale, float highscale, float abs_erpm){ 
	float scaler = lerp(lowvalue, highvalue, lowscale, highscale, abs_erpm);
	if (lowscale < highscale) {
		scaler = min(max(scaler, lowscale), highscale);
	else { scaler = max(min(scaler, lowscale), highscale); }
	return scaler;
}

