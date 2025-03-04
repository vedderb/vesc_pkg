// Copyright 2024 Lukas Hrazky
//
// This file is part of the Refloat VESC package.
//
// Refloat VESC package is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// Refloat VESC package is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.

#pragma once
#include "conf/datatypes.h"
#include "biquad.h"
#include <stdbool.h>
#include <stdint.h>

#define ACCEL_ARRAY_SIZE 5 // For traction control erpm tracking
#define ERPM_ARRAY_SIZE 5 // For traction control erpm tracking

typedef struct {
    float erpm;
    float abs_erpm;
    int8_t erpm_sign;

    float erpm_sign_factor;
    float erpm_sign_soft;
    bool erpm_sign_check;

    Biquad erpm_biquad;
    float erpm_filtered;
    float last_erpm_filtered;

    float current;
    bool braking;
    Biquad current_biquad;
    float current_filtered;

    float accel_avg;
    float accel_history[ACCEL_ARRAY_SIZE];
    uint8_t accel_idx;
    uint8_t last_accel_idx;
    float accel_filtered;
    float last_accel_filtered;

    float erpm_history[ERPM_ARRAY_SIZE];
    int erpm_idx;
    int last_erpm_idx;

    float mc_max_temp_fet;
    float mc_max_temp_mot;
    float mc_current_max;
    float mc_current_min;

    float duty_cycle;
    float duty_cycle_filtered;
    float duty_filter_factor;

    float voltage_filtered;
    float voltage_filter_factor;
    float vq, iq, i_batt;
} MotorData;

void motor_data_reset(MotorData *m);
void motor_data_configure(MotorData *m, tnt_config *config);
void update_erpm_sign(MotorData *m);
void motor_data_update(MotorData *m, tnt_config *config);
