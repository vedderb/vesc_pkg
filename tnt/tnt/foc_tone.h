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
#include "runtime.h"
#include "state_tnt.h"
#include "vesc_c_if.h"
#include "motor_data_tnt.h"
#include "footpad_sensor.h"

typedef enum {
	BEEP_NONE = 0,
	BEEP_LV = 1,
	BEEP_HV = 2,
	BEEP_TEMPFET = 3,
	BEEP_TEMPMOT = 4,
	BEEP_CURRENT = 5,
	BEEP_DUTY = 6,
	BEEP_SENSORS = 7,
	BEEP_LOWBATT = 8,
	BEEP_IDLE = 9,
	BEEP_ERROR = 10,
	TONE_CURRENT = 11,
	TONE_DUTY = 12,
	BEEP_MW = 13,
	BEEP_LW = 14,
	BEEP_FETREC = 15,
	BEEP_MOTREC = 16,
	BEEP_CHARGED = 17
} BeepReason;

typedef struct {
	float freq[3];
	float voltage;
	float duration;
	int priority;
	int times;
	bool tone_in_progress;
	float timer;
	bool pause;
	float pause_timer;
	int beep_reason;
	bool midrange_activated;
	bool lowrange_activated;
	bool motortemp_activated;
	bool fettemp_activated;
	float tone_duty;
	int delay_100ms;
	int delay_250ms;
	int delay_500ms;
	int duty_tone_count;
	int duty_beep_count;
	int midrange_count;
	int lowrange_count;
	float midrange_warning;
	float lowrange_warning;
	float highvolt_warning;
	float lowvolt_warning;
	int highvolt_count;
	int lowvolt_count;
	float voltage_diff;
	float last_voltage;
	int shutdown_mode;
	float charged_voltage;
	float charged_timer;
} ToneData;

typedef struct {
	float freq[3];
	float voltage;
	float duration;
	int priority;
	int times;
	float delay;
} ToneConfig;

typedef struct {
	ToneConfig continuous1;
	ToneConfig continuousfootpad;
	ToneConfig fastdouble1;
	ToneConfig fastdouble2;
	ToneConfig slowdouble1;
	ToneConfig slowdouble2;
	ToneConfig fasttriple1;
	ToneConfig fasttriple2;
	ToneConfig slowtriple1;
	ToneConfig slowtriple2;
	ToneConfig fasttripleup;
	ToneConfig fasttripleupduty;
	ToneConfig fasttripledown;
	ToneConfig slowtripleup;
	ToneConfig slowtripledown;
	ToneConfig midvoltwarning;
	ToneConfig lowvoltwarning;
	ToneConfig dutytone;
	ToneConfig currenttone;
} ToneConfigs;

void tone_update(ToneData *tone, RuntimeData *rt, State *state);
void play_tone(ToneData *tone, ToneConfig *toneconfig, int beep_reason);
void end_tone(ToneData *tone);
void tone_reset_on_configure(ToneData *tone);
void tone_reset(ToneData *tone);
void tone_configure(ToneConfig *toneconfig, float freq1, float freq2, float freq3, float voltage, float duration, int times, float delay, int priority);
void tone_configure_all(ToneConfigs *toneconfig, tnt_config *config, ToneData *tone);
void idle_tone(ToneData *tone, ToneConfig *toneconfig, RuntimeData *rt, MotorData *m);
void temp_recovery_tone(ToneData *tone, ToneConfig *toneconfig, MotorData *motor);
void check_tone(ToneData *tone, ToneConfigs *toneconfig, MotorData *motor);
void play_footpad_beep(ToneData *tone, MotorData *motor, FootpadSensor *fs, ToneConfig *toneconfig);
