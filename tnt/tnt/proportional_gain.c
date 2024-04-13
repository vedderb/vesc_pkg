// Copyright 2024 Michael Silberstein
//
// This file is part of the Refloat VESC package.
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

static float select_kp(float abs_prop_smooth, float pitch[], float kp[], int current_count) {
	float kp_mod = 0;
	float kp_min = 0;
	float scale_angle_min = 0;
	float scale_angle_max = 1;
	float kp_max = 0;
	int i = current_count;
	//Determine the correct current to use based on prop_smooth
	while (i >= 0) {
		if (abs_prop_smooth>= pitch[i]) {
			kp_min = kp[i];
			scale_angle_min = pitch[i];
			if (i == current_count) { //if we are at the highest current only use highest kp
				kp_max = kp[i];
				scale_angle_max = 90;
			} else {
				kp_max = kp[i+1];
				scale_angle_max = pitch[i+1];
			}
			i=-1;
		}
		i--;
	}
	
	//Scale the kp values according to d->prop_smooth
	kp_mod = ((kp_max - kp_min) / (scale_angle_max - scale_angle_min)) * d->abs_prop_smooth			//linear scaling mx
			+ (kp_max - ((kp_max - kp_min) / (scale_angle_max - scale_angle_min)) * scale_angle_max); 	//+b
	}
	return kp_mod;
}

//initialize current and pitch arrays for acceleration
	d->pitch[0] = 0;
	d->pitch[1] = d->tnt_conf.pitch1;
	d->pitch[2] = d->tnt_conf.pitch2;
	d->pitch[3] = d->tnt_conf.pitch3;
	d->pitch[4] = d->tnt_conf.pitch4;
	d->pitch[5] = d->tnt_conf.pitch5;
	d->pitch[6] = d->tnt_conf.pitch6;
	d->current[0] = 0;
	d->current[1] = d->tnt_conf.current1;
	d->current[2] = d->tnt_conf.current2;
	d->current[3] = d->tnt_conf.current3;
	d->current[4] = d->tnt_conf.current4;
	d->current[5] = d->tnt_conf.current5;
	d->current[6] = d->tnt_conf.current6;
	//Check for current inputs
	d->current_count=0;
	int i = 1;
	while (i <= 6){
		if (d->current[i]!=0 && d->pitch[i]>d->pitch[i-1]) {
			d->current_count = i;
			if (d->tnt_conf.pitch_kp_input) {
				d->kp[i]=d->current[i];
			} else {d->kp[i]=d->current[i]/d->pitch[i];}
		} else { i=7; }
		i++;
	}
	//Check kp0 for an appropriate value, prioritizing kp1
	if (d->current_count > 0) {
		if (d->kp[1]<d->tnt_conf.kp0) {
			d->kp[0]= d->kp[1];
		} else { d->kp[0] = d->tnt_conf.kp0; }
	} else { d->kp[0] = d->tnt_conf.kp0; }
	
	if (d->current_count == 0 && d->kp[0]==0) { //If no currents 
		d->kp[0] = 5; //If no kp use 5
	}
