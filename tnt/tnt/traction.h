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
#include "runtime.h"

typedef struct {
	float timeron;       	 	//Timer from the start of wheelslip
	float timeroff;      		//Timer from the end of high motor acceleration
	float accelstartval;		//Starting value to engage wheelslip
	bool highaccelon1;		//Flag that indicates acceleration magnitude has reduced
	bool highaccelon2;		//Flag that indicates acceleration direction has changed
	float lasterpm;			//ERPM before wheelslip
	float erpm;			//ERPM once wheelslip engaged
	bool reverse_wheelslip; 	//Wheelslip in the braking position
	float start_accel;		//acceleration that triggers wheelslip
	float slowed_accel;		//Trigger that shows traction control is working
	float end_accel;		//acceleration that indications traciton is regained
} TractionData;

typedef struct {
	float debug1;
	float debug2;
	float debug3;
	float debug4;
	float debug5;
	float debug6;
	float debug7;
	float debug8;
	float debug9;
	float aggregate_timer;
} TractionDebug;

void check_traction(MotorData *m, TractionData *traction, State *state, RuntimeData *rt, tnt_config *config, TractionDebug *traction_dbg);
void reset_traction(TractionData *traction, State *state);
void deactivate_traction(MotorData *m, TractionData *traction, State *state, RuntimeData *rt, TractionDebug *traction_dbg);
void configure_traction(TractionData *traction, tnt_config *config);
