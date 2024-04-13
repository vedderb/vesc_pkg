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
#include "utils.h"

float pitch_kp_select(float abs_prop_smooth, KpArray *k) {
	float kp_mod = 0;
	float kp_min = 0;
	float scale_angle_min = 0;
	float scale_angle_max = 1;
	float kp_max = 0;
	int i = k->count;
	//Determine the correct current to use based on prop_smooth
	while (i >= 0) {
		if (abs_prop_smooth>= k->pitch_kp[i][0]) {
			kp_min = k->pitch_kp[i][1];
			scale_angle_min = k->pitch_kp[i][0];
			if (i == k->count) { //if we are at the highest current only use highest kp
				kp_max = k->pitch_kp[i][1];
				scale_angle_max = 90;
			} else {
				kp_max = k->pitch_kp[i+1][1];
				scale_angle_max = k->pitch_kp[i+1][0];
			}
			i=-1;
		}
		i--;
	}
	
	//Scale the kp values according to prop_smooth
	kp_mod = lerp(scale_angle_min, scale_angle_max, kp_min, kp_max, abs_prop_smooth);
	return kp_mod;
}

KpArray pitch_kp_configure(const tnt_config *config, int mode){
	//initialize current and pitch arrays	
	struct KpArray k;
	if (mode==1) {
		float pitch_current[7][2] = {
		{0, 0}, //reserved for kp0 assigned at the end
		{config->tnt_conf.pitch1, config->tnt_conf.current1},
		{config->tnt_conf.pitch2, config->tnt_conf.current2},
		{config->tnt_conf.pitch3, config->tnt_conf.current3},
		{config->tnt_conf.pitch4, config->tnt_conf.current4},
		{config->tnt_conf.pitch5, config->tnt_conf.current5},
		{config->tnt_conf.pitch6, config->tnt_conf.current6},
		};
	} else if (mode ==2) {
		float pitch_current[7][2] = {
		{0, 0}, //reserved for kp0 assigned at the end
		{config->tnt_conf.brakepitch1, config->tnt_conf.brakecurrent1},
		{config->tnt_conf.brakepitch2, config->tnt_conf.brakecurrent2},
		{config->tnt_conf.brakepitch3, config->tnt_conf.brakecurrent3},
		{config->tnt_conf.brakepitch4, config->tnt_conf.brakecurrent4},
		{config->tnt_conf.brakepitch5, config->tnt_conf.brakecurrent5},
		{config->tnt_conf.brakepitch6, config->tnt_conf.brakecurrent6},
		};
	}
	//Check for current inputs
	k->count=0;
	int i = 1;
	while (i <= 6){
		if (pitch_current[i][1]!=0 && pitch_current[i][0]>pitch_current[i-1][0]) {
			k->count = i;
			k->pitch_kp[i][0]=pitch_current[i][0];
			if (config->tnt_conf.pitch_kp_input) {
				k->pitch_kp[i][1]=pitch_current[i][1];
			} else {k->pitch_kp[i][1]=pitch_current[i][1]/pitch_current[i][0];}
		} else { i=7; }
		i++;
	}
	//Check kp0 for an appropriate value, prioritizing kp1
	if (k->count > 0) {
		if (k->pitch_kp[1][1]<config->tnt_conf.kp0) {
			k->pitch_kp[0][1]= k->pitch_kp[1][1];
		} else { k->pitch_kp[0][1] = config->tnt_conf.kp0; }
	} else if (k->count == 0 && k->pitch_kp[0][1]==0) { //If no currents 
		k->pitch_kp[0][1] = 5; //If no kp use 5
	} else { k->pitch_kp[0][1] = config->tnt_conf.kp0; }

	return k;
}
