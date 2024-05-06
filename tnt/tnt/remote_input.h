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
#include "vesc_c_if.h"
#include "conf/datatypes.h"

typedef struct {
	float ramped_step_size;
	float step_size;
	float throttle_val;
	float inputtilt_interpolated;
	float smoothing_factor;
} RemoteData;

typedef struct {
	float value; 
	bool active; 
	float max_value; 
	float last_throttle_val;
	bool deactivate; 
	float hold_current;
	float low_value;
	float high_value;
} StickyTiltData;

void update_remote(tnt_config *config, RemoteData *r);
void apply_inputtilt(RemoteData *r, float input_tiltback_target);
void apply_stickytilt(RemoteData *r, StickyTiltData *s, float current_avg, float *input_tiltback_target);
void configure_remote_features(tnt_config *config, RemoteData *r, StickyTiltData *s);
void reset_remote(RemoteData *r, StickyTiltData *s);

