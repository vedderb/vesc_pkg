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

float apply_kalman(float in, float in_rate, float out, float diff_time, KalmanFilter *k){
    // KasBot V2  -  Kalman filter module - http://www.x-firm.com/?page_id=145
    // Modified by Kristian Lauszus
    // See my blog post for more information: http://blog.tkjelectronics.dk/2012/09/a-practical-approach-to-kalman-filter-and-how-to-implement-it
    // Discrete Kalman filter time update equations - Time Update ("Predict")
    // Update xhat - Project the state ahead
	// Step 1
	float rate = in_rate / 131 - k->bias; 
	out += dt * rate;
	// Update estimation error covariance - Project the error covariance ahead
	// Step 2 
	k->P00 += dt * (dt * k->P11 - k->P01 - k->P10 + k->Q_angle);
	k->P01 -= dt * k->P11;
	k->P10 -= dt * k->P11;
	k->P11 += k->Q_bias * dt;
	// Discrete Kalman filter measurement update equations - Measurement Update ("Correct")
	// Step 4
	float S = k->P00 + k->R_measure; // Estimate error
	// Calculate Kalman gain
	// Step 5
	float K0 = k->P00 / S; // Kalman gain - This is a 2x1 vector
	float K1 = k->P10 / S;
	// Calculate angle and bias - Update estimate with measurement zk (newAngle)
	// Step 3
	float y = in - out; // Angle difference
	// Step 6
	out += K0 * y;
	k->bias += K1 * y;
	// Calculate estimation error covariance - Update the error covariance
	// Step 7
	float P00_temp = k->P00;
	float P01_temp = k->P01;
	k->P00 -= K0 * P00_temp;
	k->P01 -= K0 * P01_temp;
	k->P10 -= K1 * P00_temp;
	k->P11 -= K1 * P01_temp;

	return out;
}

void configure_kalman(const tnt_config *config, KalmanFilter *k) {
	float Q_angle = d->tnt_conf.kalman_factor1/10000;
	float Q_bias = d->tnt_conf.kalman_factor2/10000;
	float R_measure = d->tnt_conf.kalman_factor3/100000;
}

void reset_kalman(KalmanFilter *k) {
	k->P00 = 0;
	k->P01 = 0;
	k->P10 = 0;
	k->P11 = 0;
	k->bias = 0;
}
