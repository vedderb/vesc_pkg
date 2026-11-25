// Copyright 2024 Lukas Hrazky
// Copyright 2026 Henrik Buestad
//
// This file is part of the Wheel-E VESC package which is a fork of the Refloat VESC package.
//
// Wheel-E VESC package is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// Wheel-E VESC package is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.

#include "footpad_sensor.h"

#include "vesc_c_if.h"

#include <math.h>

void footpad_sensor_init(FootpadSensor *fs) {
    fs->adc_left = 0.0f;
    fs->adc_right = 0.0f;
    fs->state = FS_NONE;

    fs->adc1_filtered = 0.0f;
    fs->adc2_filtered = 0.0f;
    fs->adc1_mapped = 0.0f;
    fs->adc2_mapped = 0.0f;
}

void footpad_sensor_update(FootpadSensor *fs, const RefloatConfig *config) {
    // io_read_analog() returns -1.0 if the pin is missing on the hardware
    float adc1 = VESC_IF->io_read_analog(VESC_PIN_ADC1);
    float adc2 = VESC_IF->io_read_analog(VESC_PIN_ADC2);

    bool adc1_on = config->fault_adc1 == 0.0f || adc1 > config->fault_adc1;
    bool adc2_on = config->fault_adc2 == 0.0f || adc2 > config->fault_adc2;

    if (config->hardware.swap_footpad_adcs) {
        fs->adc_left = adc2;
        fs->adc_right = adc1;
    } else {
        fs->adc_left = adc1;
        fs->adc_right = adc2;
    }

    if (config->fault_adc1 == 0.0f || config->fault_adc2 == 0.0f) {
        // No or single sensor: report FS_BOTH when the (single) sensor is on, FS_NONE otherwise
        fs->state = (adc1_on && adc2_on) ? FS_BOTH : FS_NONE;
    } else if (config->hardware.swap_footpad_adcs) {
        fs->state = adc1_on ? FS_RIGHT : FS_NONE;
        fs->state |= adc2_on ? FS_LEFT : FS_NONE;
    } else {
        fs->state = adc1_on ? FS_LEFT : FS_NONE;
        fs->state |= adc2_on ? FS_RIGHT : FS_NONE;
    }
}

void footpad_sensor_filter_and_map(FootpadSensor *fs, const RefloatConfig *config, float dt) {
    float filter = config->throttle_adc_filter;
    float adc1 = fs->adc_left;
    float adc2 = fs->adc_right;
    if (config->hardware.swap_footpad_adcs) {
        adc1 = fs->adc_right;
        adc2 = fs->adc_left;
    }
    fs->adc1_filtered = fs->adc1_filtered * filter + adc1 * (1.0f - filter);
    fs->adc2_filtered = fs->adc2_filtered * filter + adc2 * (1.0f - filter);

    // ADC1: piecewise min/center/max mapping to 0.0–1.0
    float _adc1_mapped;
    {
        float v = fs->adc1_filtered;
        float vmin = config->throttle_adc1_voltage_min;
        float vctr = config->throttle_adc1_voltage_center;
        float vmax = config->throttle_adc1_voltage_max;
        if (v <= vmin) {
            _adc1_mapped = 0.0f;
        } else if (v <= vctr) {
            _adc1_mapped = 0.5f * (v - vmin) / fmaxf(vctr - vmin, 0.001f);
        } else if (v <= vmax) {
            _adc1_mapped = 0.5f + 0.5f * (v - vctr) / fmaxf(vmax - vctr, 0.001f);
        } else {
            _adc1_mapped = 1.0f;
        }
        if (config->throttle_adc1_invert) {
            _adc1_mapped = 1.0f - _adc1_mapped;
        }
    }

    // Throttle ramp: ramp adc1_mapped up over throttle_ramp_time, instant release.
    // A ramp_time of 0 means instant apply (no ramp).
    if (_adc1_mapped > fs->adc1_mapped && config->throttle_ramp_time > 0.0f) {
        float ramp_step = dt / config->throttle_ramp_time;
        fs->adc1_mapped = fminf(fs->adc1_mapped + ramp_step, _adc1_mapped);
    } else {
        fs->adc1_mapped = _adc1_mapped;
    }

    // ADC2: linear min/max mapping to 0.0–1.0
    float _adc2_mapped;
    {
        float v = fs->adc2_filtered;
        float vmin = config->throttle_adc2_voltage_min;
        float vmax = config->throttle_adc2_voltage_max;
        if (v <= vmin) {
            _adc2_mapped = 0.0f;
        } else if (v >= vmax) {
            _adc2_mapped = 1.0f;
        } else {
            _adc2_mapped = (v - vmin) / fmaxf(vmax - vmin, 0.001f);
        }
        if (config->throttle_adc2_invert) {
            _adc2_mapped = 1.0f - _adc2_mapped;
        }
    }

    // Brake ramp: ramp adc2_mapped up over throttle_brake_ramp_time, instant release.
    // A ramp_time of 0 means instant apply (no ramp).
    float brake_target = _adc2_mapped;
    if (brake_target > fs->adc2_mapped && config->throttle_brake_ramp_time > 0.0f) {
        float ramp_step = dt / config->throttle_brake_ramp_time;
        fs->adc2_mapped = fminf(fs->adc2_mapped + ramp_step, brake_target);
    } else {
        fs->adc2_mapped = brake_target;
    }
}

int footpad_sensor_state_to_switch_compat(FootpadSensorState v) {
    switch (v) {
    case FS_BOTH:
        return 2;
    case FS_LEFT:
    case FS_RIGHT:
        return 1;
    case FS_NONE:
    default:
        return 0;
    }
}
