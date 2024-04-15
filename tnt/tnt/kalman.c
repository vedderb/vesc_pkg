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

#include "kalman.h"

static void apply_kalman(data *d){
    // KasBot V2  -  Kalman filter module - http://www.x-firm.com/?page_id=145
    // Modified by Kristian Lauszus
    // See my blog post for more information: http://blog.tkjelectronics.dk/2012/09/a-practical-approach-to-kalman-filter-and-how-to-implement-it
    // Discrete Kalman filter time update equations - Time Update ("Predict")
    // Update xhat - Project the state ahead
	float Q_angle = d->tnt_conf.kalman_factor1/10000;
	float Q_bias = d->tnt_conf.kalman_factor2/10000;
	float R_measure = d->tnt_conf.kalman_factor3/100000;
	// Step 1
	float rate = d->gyro[1] / 131 - d->bias; 
	d->pitch_smooth_kalman += d->diff_time * rate;
	// Update estimation error covariance - Project the error covariance ahead
	// Step 2 
	d->P00 += d->diff_time * (d->diff_time * d->P11 - d->P01 - d->P10 + Q_angle);
	d->P01 -= d->diff_time * d->P11;
	d->P10 -= d->diff_time * d->P11;
	d->P11 += Q_bias * d->diff_time;
	// Discrete Kalman filter measurement update equations - Measurement Update ("Correct")
	// Step 4
	float S = d->P00 + R_measure; // Estimate error
	// Calculate Kalman gain
	// Step 5
	float K0 = d->P00 / S; // Kalman gain - This is a 2x1 vector
	float K1 = d->P10 / S;
	// Calculate angle and bias - Update estimate with measurement zk (newAngle)
	// Step 3
	float y = d->pitch_smooth - d->pitch_smooth_kalman; // Angle difference
	// Step 6
	d->pitch_smooth_kalman += K0 * y;
	d->bias += K1 * y;
	// Calculate estimation error covariance - Update the error covariance
	// Step 7
	float P00_temp = d->P00;
	float P01_temp = d->P01;
	d->P00 -= K0 * P00_temp;
	d->P01 -= K0 * P01_temp;
	d->P10 -= K1 * P00_temp;
	d->P11 -= K1 * P01_temp;
}