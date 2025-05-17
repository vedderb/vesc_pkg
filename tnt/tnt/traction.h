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
#include "motor_data_tnt.h"
#include "state_tnt.h"
#include "pid.h"

typedef struct {
	float timeron;       	 	//Timer from the start of wheelslip
	float timeroff;      		//Timer from the end of high motor acceleration
	float accelstartval;		//Starting value to engage wheelslip
	bool highaccelon1;		//Flag that indicates acceleration direction has changed
	bool highaccelon2;		//Flag that indicates acceleration direction has changed
	bool reverse_wheelslip; 	//Wheelslip in the braking position
	float start_accel;		//acceleration that triggers wheelslip
	float slowed_accel;		//Trigger that shows traction control is working
	float end_accel;
	float hold_accel;
	bool end_accel_hold;
	float erpm_rate_limit;
	float erpm_limited;
	float erpm_exclusion_rate;
} TractionData;

typedef struct {
	float debug1;
	float debug2;
	float debug3;
	int debug4;
	float debug5;
	float debug6;
	float debug7;
	float debug8;
	float debug9;
	float aggregate_timer;
	float freq_factor;
	float max_time;
	uint32_t bonks_total;
} TractionDebug;

typedef struct {
	float timeron;       	 	
	float timeroff;      		
	bool active;
	bool last_active;
} BrakingData;

typedef struct {
	float debug1;
	float debug2;
	float debug3;
	int debug4;
	int debug5;
	float debug6;
	float debug7;
	float debug8;
	float debug9;
	float aggregate_timer;
	float freq_factor;
} BrakingDebug;

void check_traction(MotorData *m, TractionData *traction, State *state, tnt_config *config, PidData *p, TractionDebug *traction_dbg);
void reset_traction(TractionData *traction, State *state, BrakingData *braking);
void deactivate_traction(TractionData *traction, State *state, TractionDebug *traction_dbg, float abs_erpm, float exit);
void configure_traction(TractionData *traction, BrakingData *braking, tnt_config *config, TractionDebug *traction_dbg, BrakingDebug *braking_dbg);
void check_traction_braking(BrakingData *braking, MotorData *m, State *state, tnt_config *config, float inputtilt_interpolated, PidData *pid, BrakingDebug *braking_dbg);
void rate_limit_erpm(MotorData *m, TractionData *traction);
