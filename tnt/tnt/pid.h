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
#include "remote_input.h"
#include "runtime.h"
#include "motor_data_tnt.h"
#include "state_tnt.h"
#include "vesc_c_if.h"
#include "footpad_sensor.h"
#include <stdbool.h>
#include <stdint.h>

typedef struct {
	float angle_kp[7][2];
	int count;
	float kp_rate;
} KpArray;

typedef struct {
	float proportional;
	float pid_value;
	float prop_smooth;
	float abs_prop_smooth;
	float pid_mod;
	float stabl;
	float stability_kp;
	float stability_kprate;
	float stabl_step_size_up, stabl_step_size_down;
	float roll_pid_mod;
	float yaw_pid_mod;
	float softstart_pid_limit;
	float softstart_step_size;
	bool brake_pitch, brake_roll, brake_yaw;
	float new_pid_value;
} PidData;

typedef struct {
	float debug1;	//pitch kp
	float debug2;	// roll kp
	float debug3;	// temp stability rate kp 
	float debug4;	// pitch rate
	float debug5;	// yaw rate
	float debug6;	// stability pitch rate kp 
	float debug7;	// stability yaw rate kp 
	float debug8;	// stability pitch angle kp
	float debug9;	// pitch rate kp
	float debug10; 	// temp pitch/yaw rate kp
	float debug11; 	// yaw rate kp
	float debug12; 	// pitch angle demand
	float debug13; 	// stability angle demand
	float debug14;	// stability rate demand
	float debug15; 	// yaw angle current demand
	float debug16; 	// max roll angle
	float debug17; // roll erpm scale
	float debug18; // roll anngle demand
} PidDebug;

void pitch_kp_configure(const tnt_config *config, KpArray *k, int mode);
void roll_kp_configure(const tnt_config *config, KpArray *k, int mode);
void yaw_kp_configure(const tnt_config *config, KpArray *k, int mode);
float angle_kp_select(float angle, const KpArray *k);
void angle_kp_reset(KpArray *k);
float erpm_scale(float lowvalue, float highvalue, float lowscale, float highscale, float abs_erpm); 
void apply_stability(PidData *p, float abs_erpm, float inputtilt_interpolated, tnt_config *config);
void check_brake_kp(PidData *p, State *state, tnt_config *config, KpArray *roll_brake_kp, KpArray *yaw_brake_kp);
float roll_erpm_scale(PidData *p, State *state, float abs_erpm, KpArray *roll_accel_kp, tnt_config *config);
void reset_pid(PidData *p, PidDebug *pid_dbg);
void apply_soft_start(PidData *p, float mc_current_max);
void configure_pid(PidData *p, tnt_config *config);
float apply_pitch_kp(KpArray *accel_kp, KpArray *brake_kp, PidData *p, PidDebug *pid_dbg);
float apply_kp_rate(KpArray *accel_kp, KpArray *brake_kp, bool braking, PidDebug *pid_dbg);
float apply_roll_kp(KpArray *roll_accel_kp, KpArray *roll_brake_kp, PidData *p, int erpm_sign, float abs_roll_angle, float roll_erpm_scale, PidDebug *pid_dbg);
float yaw_erpm_scale(PidData *p, State *state, float abs_erpm, tnt_config *config);
float apply_yaw_kp(KpArray *yaw_accel_kp, KpArray *yaw_brake_kp, PidData *p, float erpm_sign, float abs_change, float yaw_erpm_scale, YawDebugData *yaw_dbg);
void brake(float current, RuntimeData *rt, MotorData *motor);
void set_current(float current, RuntimeData *rt );
void set_dutycycle(float dutycycle, RuntimeData *rt);
void set_brake(float current,  RuntimeData *rt);
bool check_faults(MotorData *motor, FootpadSensor *fs, RuntimeData *rt, State *state, float inputtilt_interpolated, tnt_config *config);
void calculate_proportional(RuntimeData *rt, PidData *pid, float setpoint);
