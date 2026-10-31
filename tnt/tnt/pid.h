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
	float roll_kp_mod;
	float yaw_kp_mod;
	float softstart_pid_limit;
	float softstart_step_size;
	bool brake_pitch, brake_roll, brake_yaw, brake_gyro;
	float new_pid_value;
	float pitch_kp;
	float roll_erpm_scaler;
	float yaw_erpm_scaler;
	float rollkp;
	float yawkp;
	float kp_rate;
	float selected_stability_kprate;
	float pitch_rate_current;
	float yaw_kp_rate;
	float yaw_kp_rate_current;
	float kp_rate_current;
	float pitch_current;
} PidData;

typedef struct {
	float debug1;	//pitch kp
	float debug2;	//pitch kp rate
	float debug3;	//roll kp
	float debug4;	//yaw kp
	float debug5;	// yaw angle current
	float debug6;	// stability pitch rate kp 
	float debug7;	// stability rate demand
	float debug8;	// stability pitch angle kp
	float debug9;	// stability angle demand
	float debug10; 	// roll angle demand
	float debug11; 	// max roll
	bool pitch;	//enable pitch debug
	bool stability;	//enable stability debug
	bool yaw;	//enable yaw debug
	bool roll;	//enable roll debug
	bool current; // enable currents debug
} PidDebug;

void pitch_kp_configure(const tnt_config *config, KpArray *k, int mode);
void roll_kp_configure(const tnt_config *config, KpArray *k, int mode);
void yaw_kp_configure(const tnt_config *config, KpArray *k, int mode, bool brake_curve);
float angle_kp_select(float angle, const KpArray *k);
void angle_kp_reset(KpArray *k);
float erpm_scale(float lowvalue, float highvalue, float lowscale, float highscale, float abs_erpm); 
void apply_stability(PidData *p, float abs_erpm, float inputtilt_interpolated, tnt_config *config);
float roll_erpm_scale(State *state, float abs_erpm, tnt_config *config);
void reset_pid(PidData *p, PidDebug *pid_dbg);
void apply_soft_start(PidData *p, float mc_current_max);
void configure_pid(PidData *p, tnt_config *config, PidDebug *pid_dbg);
float yaw_erpm_scale(State *state, float abs_erpm, tnt_config *config);
void brake(float current, RuntimeData *rt, MotorData *motor);
void set_current(float current, RuntimeData *rt );
void set_dutycycle(float dutycycle, RuntimeData *rt);
void set_brake(float current,  RuntimeData *rt);
bool check_faults(MotorData *motor, FootpadSensor *fs, RuntimeData *rt, State *state, float inputtilt_interpolated, tnt_config *config);
void calculate_proportional(RuntimeData *rt, PidData *pid, float setpoint);
