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
        bool active;				//Drop is occurring
        bool deactivate;			//Return setpoint to normal
        float timeron;				//timer for debug info
        float timeroff;				//timer for debug info
        float count;				//Required code cycles below the limit before drop engages
        float applied_accel_z_reduction;	//Geometry compesation for the angle of the board
        float z_limit;				//Required acceleration to engage drop
        float count_limit;			//Required code cycles to engage drop
        float motor_limit;			//Required motor acceleration to end drop
	float tiltback_step_size;		//Return speed to original setpoint after drop
} DropData;

typedef struct {
	float debug1;
	float debug2;
	float debug3;
	float debug4;
	float debug5;
	float debug6;
} DropDebug;

void check_drop(DropData *drop, MotorData *m, RuntimeData *rt, State *state, DropDebug *drop_dbg);
void drop_deactivate(DropData *drop, DropDebug *drop_dbg);
void reset_drop(DropData *drop);
void configure_drop(DropData *drop, tnt_config *config);
