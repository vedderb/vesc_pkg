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
#include "state_tnt.h"
#include "motor_data_tnt.h"
#include "runtime.h"
#include "foc_tone.h"

typedef struct {
        float setpoint;
	float startup_pitch_trickmargin, startup_pitch_tolerance;
	float startup_step_size;
	float tiltback_duty_step_size, tiltback_hv_step_size, tiltback_lv_step_size, tiltback_return_step_size, tiltback_ht_step_size;
        float surge_tiltback_step_size;
	float noseangling_step_size;
	float tiltback_duty;
	float setpoint_target, setpoint_target_interpolated;
	float noseangling_interpolated;
	float tb_highvoltage_timer;
} SetpointData;

void setpoint_configure(SetpointData *s, tnt_config *config);
void setpoint_reset(SetpointData *s, tnt_config *config, RuntimeData *rt);
float get_setpoint_adjustment_step_size(SetpointData *s, State *state);
void calculate_setpoint_interpolated(SetpointData *s, State *state);
void apply_noseangling(SetpointData *s, MotorData *motor, tnt_config *config);
void calculate_setpoint_target(SetpointData *spd, State *state, MotorData *motor, RuntimeData *rt, 
    tnt_config *config, float proportional);
