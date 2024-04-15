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

float pitch_kp_select(float abs_prop_smooth, KpArray k) {
	float kp_mod = 0;
	float kp_min = 0;
	float scale_angle_min = 0;
	float scale_angle_max = 1;
	float kp_max = 0;
	int i = k.count;
	//Determine the correct current to use based on prop_smooth
	while (i >= 0) {
		if (abs_prop_smooth>= k.pitch_kp[i][0]) {
			kp_min = k.pitch_kp[i][1];
			scale_angle_min = k.pitch_kp[i][0];
			if (i == k.count) { //if we are at the highest current only use highest kp
				kp_max = k.pitch_kp[i][1];
				scale_angle_max = 90;
			} else {
				kp_max = k.pitch_kp[i+1][1];
				scale_angle_max = k.pitch_kp[i+1][0];
			}
			i=-1;
		}
		i--;
	}
	
	//Scale the kp values according to prop_smooth
	kp_mod = lerp(scale_angle_min, scale_angle_max, kp_min, kp_max, abs_prop_smooth);
	return kp_mod;
}

void pitch_kp_configure(const tnt_config *config, KpArray *k, int mode){
	//initialize current and pitch arrays	
	float kp0 = config->kp0;
	bool kp_input = config->pitch_kp_input;
	
	float pitch_current[7][2] = { //Accel curve
	{0, 0}, //reserved for kp0 assigned at the end
	{config->pitch1, config->current1},
	{config->pitch2, config->current2},
	{config->pitch3, config->current3},
	{config->pitch4, config->current4},
	{config->pitch5, config->current5},
	{config->pitch6, config->current6},
	};
	
	float temp_pitch_current[7][2] = { //Brake Curve
	{0, 0}, //reserved for kp0 assigned at the end
	{config->brakepitch1, config->brakecurrent1},
	{config->brakepitch2, config->brakecurrent2},
	{config->brakepitch3, config->brakecurrent3},
	{config->brakepitch4, config->brakecurrent4},
	{config->brakepitch5, config->brakecurrent5},
	{config->brakepitch6, config->brakecurrent6},
	};

	if (mode==2) { //Brake curve
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
			k->pitch_kp[i][0]=pitch_current[i][0];
			if (kp_input) {
				k->pitch_kp[i][1]=pitch_current[i][1];
			} else {k->pitch_kp[i][1]=pitch_current[i][1]/pitch_current[i][0];}
		} else { i=7; }
		i++;
	}
	//Check kp0 for an appropriate value, prioritizing kp1
	if (k->pitch_kp[1][1] !=0) {
		if (k->pitch_kp[1][1] < kp0) {
			k->pitch_kp[0][1]= k->pitch_kp[1][1]; //If we have a kp1 check to see if it is less than kp0 else reduce kp0
		} else { k->pitch_kp[0][1] = kp0; } //If less than kp1 it is OK
	} else if (k->pitch_kp[0][1]==0) { //If no currents and no kp0
		k->pitch_kp[0][1] = 5; //default 5
	} else { k->pitch_kp[0][1] = kp0; }//passes all checks, it is ok 
}

void pitch_kp_reset(KpArray *k) {
	for (int x = 0; x <= 6; x++) {
		for (int y = 0; y <= 1; y++) {
			k->pitch_kp[x][y] = 0;
		}
	}
	k->count = 0;
}
