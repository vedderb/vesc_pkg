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

typedef struct {
	float timer;				//Timer to monitor surge cycle and period
	bool state;				//Identifies surge state which drives duty to max
	float new_duty_cycle;			//Used to ramp duty cycle
	bool state_off;				//Used to identify when setpoint should return to nowmal
	float tiltback_step_size;		//Speed that the board returns to setpoint
	float setpoint;				//Setpoint allowed by surge
	float start_current;			//Current that starts surge
	float ramp_rate;			//Duty cycle ramp rate
	bool high_current;			//A state below surge current by amount, overcurrent margin
	float high_current_timer;		//Limits the duration of haptic buzz
	bool high_current_buzz;			//A state that allows haptic buzz during high current
} SurgeData;

void check_current(data *d);
void check_surge(data *d);
