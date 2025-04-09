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

#include "motor_data_tnt.h"

#include "utils_tnt.h"

#include "vesc_c_if.h"

#include <math.h>

void motor_data_reset(MotorData *m) {
    m->erpm_sign_soft = 0;
    m->accel_filtered = 0;
    m->last_accel_filtered = 0;
    m->erpm_filtered = 0;
    m->last_erpm_filtered = 0;
    m->accel_avg = 0;
    m->current_filtered = 0;	
    m->erpm_avg = 0;

    m->erpm_idx = 0;
    for (int i = 0; i < m->erpm_array_size; i++) {
        m->erpm_history[i] = 0;
    }
    m->accel_idx = 0;
    for (int i = 0; i < ACCEL_ARRAY_SIZE; i++) {
        m->accel_history[i] = 0;
    }
    biquad_reset(&m->current_biquad);
    biquad_reset(&m->erpm_biquad);

    m->voltage_filtered = VESC_IF->mc_get_input_voltage_filtered();
}

void motor_data_configure(MotorData *m, tnt_config *config) {
    biquad_configure(&m->current_biquad, BQ_LOWPASS, 1.0 * config->current_filter / config->hertz);
    biquad_configure(&m->erpm_biquad, BQ_LOWPASS, 1.0 * config->wheelslip_filter_freq / config->hertz);
   
    m->erpm_sign_factor = 0.9984 / config->hertz; //originally configured for 832 hz to delay an erpm sign change for 1 second (0.0012 factor)
    m->erpm_array_size = min(500, max(5, config->wheelslip_filter_period * config->hertz /1000)); //convert from time period in ms to number of code cycles

    m->mc_max_temp_fet = VESC_IF->get_cfg_float(CFG_PARAM_l_temp_fet_start) - 3;
    m->mc_max_temp_mot = VESC_IF->get_cfg_float(CFG_PARAM_l_temp_motor_start) - 3;
    m->mc_current_max = VESC_IF->get_cfg_float(CFG_PARAM_l_current_max); 
    m->mc_current_min = fabsf(VESC_IF->get_cfg_float(CFG_PARAM_l_current_min));    // min current is a positive value here!
    m->voltage_filter_factor = 0.001 * 832 / config->hertz;
    m->duty_filter_factor = 0.01 * 832 / config->hertz;
}

void update_erpm_sign(MotorData *m) {
	// Monitors erpm direction with a delay to prevent nuisance trips to surge and traction control
	m->erpm_sign_soft = max(-1, min( 1, m->erpm_sign_soft + m->erpm_sign_factor * m->erpm_sign));
	m->erpm_sign_check = m->erpm_sign == sign(m->erpm_sign_soft);
}

void motor_data_update(MotorData *m, tnt_config *config) {
    m->erpm = VESC_IF->mc_get_rpm();
    m->abs_erpm = fabsf(m->erpm);
    m->erpm_sign = sign(m->erpm);
    update_erpm_sign(m);

    //ERPM Moving Average
    m->erpm_avg += (m->erpm - m->erpm_history[m->erpm_idx]) / m->erpm_array_size;
    m->erpm_history[m->erpm_idx] = m->erpm;
    m->erpm_idx = (m->erpm_idx + 1) % m->erpm_array_size; 

    //ERPM at the start of the acceleration array
    m->start_accel_idx = m->erpm_idx - ACCEL_ARRAY_SIZE; 
    if (m->start_accel_idx < 0) 
       m->start_accel_idx += m->erpm_array_size;
    m->erpm_at_accel_start =  m->erpm_history[m->start_accel_idx];

    //Use low pass filtered erpm for accleration calculation
    m->erpm_filtered = config->wheelslip_filter_freq > 0 ? biquad_process(&m->erpm_biquad, m->erpm) : m->erpm;	
    m->last_accel_filtered = m->accel_filtered;
    m->accel_filtered =  m->erpm_filtered - m->last_erpm_filtered;
    m->last_erpm_filtered = m->erpm_filtered;

    //Use averaging for acceleration across a few cycles, 5-10
    m->accel_avg += (m->accel_filtered - m->accel_history[m->accel_idx]) / ACCEL_ARRAY_SIZE;
    m->accel_history[m->accel_idx] = m->accel_filtered;
    m->accel_idx = (m->accel_idx + 1) % ACCEL_ARRAY_SIZE;

    m->current = VESC_IF->mc_get_tot_current_directional_filtered();
    m->current_filtered = biquad_process(&m->current_biquad, m->current);
    m->braking = m->abs_erpm > 250 && sign(m->current) != m->erpm_sign;

    m->duty_cycle = fabsf(VESC_IF->mc_get_duty_cycle_now());
    m->duty_cycle_filtered = m->duty_cycle * m->duty_filter_factor + m->duty_cycle_filtered * (1 - m->duty_filter_factor);

    m->voltage_filtered = VESC_IF->mc_get_input_voltage_filtered() * m->voltage_filter_factor + m->voltage_filtered * (1 - m->voltage_filter_factor);
    m->vq = VESC_IF->foc_get_vq();
    m->iq = VESC_IF->foc_get_iq();
    m->i_batt = VESC_IF->mc_get_tot_current_in();
}
