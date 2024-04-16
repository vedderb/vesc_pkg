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

#include "proportional_gain.h"
#include "utils_tnt.h"

float angle_kp_select(float angle, const KpArray *k) {
	float kp_mod, kp_min, kp_max, scale_angle_min, scale_angle_max;
	int i = k->count;
	//Determine the correct kp to use based on angle
	while (i >= 0) {
		if (angle>= k->angle_kp[i][0]) {
			kp_min = k->angle_kp[i][1];
			scale_angle_min = k->angle_kp[i][0];
			if (i == k->count) { //if we are at the highest current only use highest kp
				kp_max = k->angle_kp[i][1];
				scale_angle_max = 90;
			} else {
				kp_max = k->angle_kp[i+1][1];
				scale_angle_max = k->angle_kp[i+1][0];
			}
			i=-1;
		}
		i--;
	}
	
	//Interpolate the kp values according to angle
	kp_mod = lerp(scale_angle_min, scale_angle_max, kp_min, kp_max, angle);
	return kp_mod;
}

void pitch_kp_configure(const tnt_config *config, KpArray *k, int mode){
	float pitch_current[7][2] = { //Accel curve
	{0, 0}, //reserved for kp0 assigned at the end
	{config->pitch1, config->current1},
	{config->pitch2, config->current2},
	{config->pitch3, config->current3},
	{config->pitch4, config->current4},
	{config->pitch5, config->current5},
	{config->pitch6, config->current6},
	};
	float kp0 = config->kp0;
	bool kp_input = config->pitch_kp_input;
	
	if (mode==2) { //Brake curve
		float temp_pitch_current[7][2] = {
		{0, 0}, //reserved for kp0 assigned at the end
		{config->brakepitch1, config->brakecurrent1},
		{config->brakepitch2, config->brakecurrent2},
		{config->brakepitch3, config->brakecurrent3},
		{config->brakepitch4, config->brakecurrent4},
		{config->brakepitch5, config->brakecurrent5},
		{config->brakepitch6, config->brakecurrent6},
		};
		for (int x = 0; x <= 6; x++) {
			for (int y = 0; y <= 1; y++) {
				pitch_current[x][y] = temp_pitch_current[x][y];
			}
		}
		kp0 = config->brake_kp0;
		kp_input = config->pitch_kp_input_brake;
	}

	//Check for current inputs
	int i = 1;
	while (i <= 6){
		if (pitch_current[i][1]!=0 && pitch_current[i][0]>pitch_current[i-1][0]) {
			k->count = i;
			k->angle_kp[i][0]=pitch_current[i][0];
			if (kp_input) {
				k->angle_kp[i][1]=pitch_current[i][1];
			} else {k->angle_kp[i][1]=pitch_current[i][1]/pitch_current[i][0];}
		} else { i=7; }
		i++;
	}
	
	//Check kp0 for an appropriate value, prioritizing kp1
	if (k->angle_kp[1][1] !=0) {
		if (k->angle_kp[1][1] < kp0) {
			k->angle_kp[0][1]= k->angle_kp[1][1]; //If we have a kp1 check to see if it is less than kp0 else reduce kp0
		} else { k->angle_kp[0][1] = kp0; } //If less than kp1 it is OK
	} else if (kp0 == 0) { //If no currents and no kp0
		k->angle_kp[0][1] = 5; //default 5
	} else { k->angle_kp[0][1] = kp0; }//passes all checks, it is ok 
}

void angle_kp_reset(KpArray *k) {
	//necessary only for the pitch kparray
	for (int x = 0; x <= 6; x++) {
		for (int y = 0; y <= 1; y++) {
			k->angle_kp[x][y] = 0;
		}
	}
	k->count = 0;
}

void roll_kp_configure(const tnt_config *config, KpArray *k, int mode){
	float accel_roll_kp[7][2] = { //Accel curve
	{0, 0}, //reserved for kp0 assigned at the end
	{config->roll1, config->roll_kp1},
	{config->roll2, config->roll_kp2},
	{config->roll3, config->roll_kp3},
	{0, 0},
	{0, 0},
	{0, 0},
	};
	
	float brake_roll_kp[7][2] = { //Brake Curve
	{0, 0}, //reserved for kp0 assigned at the end
	{config->brkroll1, config->brkroll_kp1},
	{config->brkroll2, config->brkroll_kp2},
	{config->brkroll3, config->brkroll_kp3},
	{0, 0},
	{0, 0},
	{0, 0},
	};	

	for (int x = 0; x <= 6; x++) {
		for (int y = 0; y <= 1; y++) {
			k->angle_kp[x][y] = (mode==2) ? brake_roll_kp[x][y] : accel_roll_kp[x][y];
		}
	}
	
	if (k->angle_kp[1][1]<k->angle_kp[2][1] && k->angle_kp[1][0]<k->angle_kp[2][0]) {
		if (k->angle_kp[2][1]<k->angle_kp[3][1] && k->angle_kp[2][0]<k->angle_kp[3][0]) {
			k->count = 3;
		} else {k->count = 2;}
	} else if (k->angle_kp[1][1] >0 && k->angle_kp[1][0]>0) {
		k->count = 1;
	} else {k->count = 0;}
}
