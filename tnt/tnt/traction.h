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
#include "state.h"
#include "runtime.h"

typedef struct {
	float timeron;       	 	//Timer from the start of wheelslip
	float timeroff;      		//Timer from the end of high motor acceleration
	float accelstartval;		//Starting value to engage wheelslip
	bool highaccelon1;		//Flag that indicates acceleration magnitude has reduced
	bool highaccelon2;		//Flag that indicates acceleration direction has changed
	float lasterpm;			//ERPM before wheelslip
	float erpm;			//ERPM once wheelslip engaged
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
} TractionDebug

typedef struct {
        bool state;				//Drop is occurring
        float timeron;				//timer for debug info
        float timeroff;				//timer for debug info
        float count;				//Required code cycles below the limit before drop engages
        float applied_accel_z_reduction;	//Geometry compesation for the angle of the board
        float limit;				//Required acceleration to engage drop
} DropData;

void check_traction(MotorData *m, TractionData *traction, StateData *state, RuntimeData *rt, tnt_config *config, TractionDebug *traction_dbg);
void check_drop(DropData *drop, RuntimeData *rt);
