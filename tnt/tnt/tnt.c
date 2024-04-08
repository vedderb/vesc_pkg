// Copyright 2019 - 2022 Mitch Lustig
// Copyright 2022 Benjamin Vedder <benjamin@vedder.se>
// Copyright 2023 Michael Silberstein
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

#include "vesc_c_if.h"

#include "footpad_sensor.h"
#include "motor_data.h"
#include "state.h"
#include "utils.h"

#include "conf/datatypes.h"
#include "conf/confparser.h"
#include "conf/confxml.h"
#include "conf/buffer.h"
#include "conf/conf_default.h"

#include <math.h>
#include <string.h>

HEADER

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
	BEEP_ERROR = 10
} BeepReason;

// This is all persistent state of the application, which will be allocated in init. It
// is put here because variables can only be read-only when this program is loaded
// in flash without virtual memory in RAM (as all RAM already is dedicated to the
// main firmware and managed from there). This is probably the main limitation of
// loading applications in runtime, but it is not too bad to work around.
typedef struct {
	lib_thread thread; // Balance Thread

	tnt_config tnt_conf;

	// Firmware version, passed in from Lisp
	int fw_version_major, fw_version_minor, fw_version_beta;

  	MotorData motor;
	
	// Beeper
	int beep_num_left;
	int beep_duration;
	int beep_countdown;
	int beep_reason;
	bool beeper_enabled;

	// Config values
	uint32_t loop_time_us;
	unsigned int start_counter_clicks, start_counter_clicks_max;
	float startup_pitch_trickmargin, startup_pitch_tolerance;
	float startup_step_size;
	float tiltback_duty_step_size, tiltback_hv_step_size, tiltback_lv_step_size, tiltback_return_step_size, tiltback_ht_step_size;
	float inputtilt_ramped_step_size, inputtilt_step_size, noseangling_step_size;
	float mc_max_temp_fet, mc_max_temp_mot;
	float mc_current_max, mc_current_min;
	bool current_beeping;
	bool duty_beeping;
	bool overcurrent;

	// Feature: True Pitch
	ATTITUDE_INFO m_att_ref;

	// Runtime values read from elsewhere
	float pitch_angle, last_pitch_angle, roll_angle, abs_roll_angle, last_gyro_y;
 	float true_pitch_angle;
	float gyro[3];
	
	float throttle_val;
	float max_duty_with_margin;

	FootpadSensor footpad_sensor;

	// Rumtime state values
	State state;

	float proportional;
	float pid_mod;
	float last_proportional, abs_proportional;
	float pid_value;
	float setpoint, setpoint_target, setpoint_target_interpolated;
	float inputtilt_interpolated, noseangling_interpolated;
	float current_time;
	float disengage_timer, nag_timer;
	float idle_voltage;
	float fault_angle_pitch_timer, fault_angle_roll_timer, fault_switch_timer, fault_switch_half_timer; // Seconds
	float motor_timeout_s;
	float brake_timeout; // Seconds
	float overcurrent_timer, tb_highvoltage_timer;
	float switch_warn_beep_erpm;
	bool traction_control;

	// Odometer
	float odo_timer;
	int odometer_dirty;
	uint64_t odometer;

	//Sitcky Tilt
	float stickytilt_val; 
	bool stickytilton; 
	float stickytilt_maxval; 
	float last_throttle_val;
	bool stickytiltoff;  
	
	// Feature: Surge
	float surge_timer;			//Timer to monitor surge cycle and period
	bool surge;				//Identifies surge state which drives duty to max
	float differential;			//Pitch differential
	float new_duty_cycle;
	bool surge_off;
	float tiltback_surge_step_size;
	float surge_setpoint;
	float surge_start_current;
	float surge_ramp_rate;
	
	//Traction Control
	float wheelslip_timeron;
	float wheelslip_timeroff;
	float wheelslip_accelstartval;
	bool wheelslip_highaccelon1;
	bool wheelslip_highaccelon2;
	float wheelslip_lasterpm;
	float wheelslip_erpm;
	float direction;
	
	// Drop Detection
	bool wheelslip_drop;
	float wheelslip_droptimeron;
	float wheelslip_droptimeroff;
	float last_accel_z;
	float accel_z;
	float accel[3];
	float wheelslip_dropcount;
	float applied_accel_z_reduction;
	float wheelslip_droplimit;
	
	// Low Pass Filter
	float prop_smooth, abs_prop_smooth, pitch_smooth; 
	Biquad pitch_biquad;
	
	// Kalman Filter
	float P00, P01, P10, P11, bias, pitch_smooth_kalman;

	// Throttle/Brake Scaling
	float roll_pid_mod;
	int roll_count;
	int brkroll_count;
	int current_count;
	float pitch[7];
	float kp[7];
	float current[7];
	int brake_current_count;
	float brakepitch[7];
	float brakekp[7];
	float brakecurrent[7];

	// Dynamic Stability
	float stabl;
	float stabl_step_size;

	//Haptic Buzz
	float applied_haptic_current, haptic_timer;
	int haptic_counter, haptic_mode;
	HAPTIC_BUZZ_TYPE haptic_type;
	bool haptic_tone_in_progress;

	//Trip Debug
	float rest_time, last_rest_time, ride_time, last_ride_time;
	bool run_flag;

	//Debug
	float debug1, debug2, debug3, debug4, debug5, debug6, debug7, debug8, debug9, debug10, debug11, debug12, debug13, debug14, debug15, debug16, debug17, debug18, debug19;

	// Log values
	float float_setpoint, float_inputtilt;

} data;

static void brake(data *d);
static void set_current(data *d, float current);

const VESC_PIN beeper_pin = VESC_PIN_PPM; //BUZZER / BEEPER on Servo Pin

#define EXT_BEEPER_ON()  VESC_IF->io_write(beeper_pin, 1)
#define EXT_BEEPER_OFF() VESC_IF->io_write(beeper_pin, 0)

void beeper_init() {
	VESC_IF->io_set_mode(beeper_pin, VESC_PIN_MODE_OUTPUT);
}

void beeper_update(data *d) {
	if (d->beeper_enabled && (d->beep_num_left > 0)) {
		d->beep_countdown--;
		if (d->beep_countdown <= 0) {
			d->beep_countdown = d->beep_duration;
			d->beep_num_left--;	
			if (d->beep_num_left & 0x1)
				EXT_BEEPER_ON();
			else
				EXT_BEEPER_OFF();
		}
	}
}

void beeper_enable(data *d, bool enable) {
	d->beeper_enabled = enable;
	if (!enable) {
		EXT_BEEPER_OFF();
	}
}

void beep_alert(data *d, int num_beeps, bool longbeep) {
	if (!d->beeper_enabled)
		return;
	if (d->beep_num_left == 0) {
		d->beep_num_left = num_beeps * 2 + 1;
		d->beep_duration = longbeep ? 300 : 80;
		d->beep_countdown = d->beep_duration;
	}
}

void beep_off(data *d, bool force)
{
	// don't mess with the beeper if we're in the process of doing a multi-beep
	if (force || (d->beep_num_left == 0))
		EXT_BEEPER_OFF();
}

void beep_on(data *d, bool force)
{
	if (!d->beeper_enabled)
		return;
	// don't mess with the beeper if we're in the process of doing a multi-beep
	if (force || (d->beep_num_left == 0))
		EXT_BEEPER_ON();
}


static void reconfigure(data *d) {
    balance_filter_configure(&d->balance_filter, &d->tnt_conf);
}

static void configure(data *d) {
	state_init(&d->state, d->tnt_conf.disabled);
	
	// This timer is used to determine how long the board has been disengaged / idle. subtract 1 second to prevent the haptic buzz disengage click on "write config"
	d->disengage_timer = d->current_time - 1;

	// Loop time in microseconds
	d->loop_time_us = 1e6 / d->tnt_conf.hertz;

	// Loop time in seconds times 20 for a nice long grace period
	d->motor_timeout_s = 20.0f / d->tnt_conf.hertz;
	
	d->startup_step_size = d->tnt_conf.startup_speed / d->tnt_conf.hertz;
	d->tiltback_duty_step_size = d->tnt_conf.tiltback_duty_speed / d->tnt_conf.hertz;
	d->tiltback_hv_step_size = d->tnt_conf.tiltback_hv_speed / d->tnt_conf.hertz;
	d->tiltback_lv_step_size = d->tnt_conf.tiltback_lv_speed / d->tnt_conf.hertz;
	d->tiltback_return_step_size = d->tnt_conf.tiltback_return_speed / d->tnt_conf.hertz;
	d->inputtilt_step_size = d->tnt_conf.inputtilt_speed / d->tnt_conf.hertz;
	d->tiltback_ht_step_size = d->tnt_conf.tiltback_ht_speed / d->tnt_conf.hertz;
	d->stabl_step_size = d->tnt_conf.stabl_ramp/100 / d->tnt_conf.hertz;
	d->tiltback_surge_step_size = d->tnt_conf.tiltback_surge_speed / d->tnt_conf.hertz;
	
	// Feature: Stealthy start vs normal start (noticeable click when engaging) - 0-20A
	d->start_counter_clicks_max = 3;
	// Feature: Soft Start
	d->softstart_ramp_step_size = (float)100 / d->tnt_conf.hertz;
	// Feature: Dirty Landings
	d->startup_pitch_trickmargin = d->tnt_conf.startup_dirtylandings_enabled ? 10 : 0;

	// Overwrite App CFG Mahony KP to Float CFG Value
	if (VESC_IF->get_cfg_float(CFG_PARAM_IMU_mahony_kp) != d->tnt_conf.mahony_kp) {
		VESC_IF->set_cfg_float(CFG_PARAM_IMU_mahony_kp, d->tnt_conf.mahony_kp);
	}

	d->mc_max_temp_fet = VESC_IF->get_cfg_float(CFG_PARAM_l_temp_fet_start) - 3;
	d->mc_max_temp_mot = VESC_IF->get_cfg_float(CFG_PARAM_l_temp_motor_start) - 3;

	d->mc_current_max = VESC_IF->get_cfg_float(CFG_PARAM_l_current_max);
	// min current is a positive value here!
	d->mc_current_min = fabsf(VESC_IF->get_cfg_float(CFG_PARAM_l_current_min));


	d->max_duty_with_margin = VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty) - 0.1;

	// Allows smoothing of Remote Tilt
	d->inputtilt_ramped_step_size = 0;

	// Speed above which to warn users about an impending full switch fault
	d->switch_warn_beep_erpm = d->tnt_conf.is_footbeep_enabled ? 2000 : 100000;

	d->beeper_enabled = d->tnt_conf.is_beeper_enabled;

	reconfigure(d);
	
	if (d->state.state == STATE_DISABLED) {
	    beep_alert(d, 3, false);
	} else {
	    beep_alert(d, 1, false);
	}

	//initialize current and pitch arrays for acceleration
	d->pitch[0] = 0;
	d->pitch[1] = d->tnt_conf.pitch1;
	d->pitch[2] = d->tnt_conf.pitch2;
	d->pitch[3] = d->tnt_conf.pitch3;
	d->pitch[4] = d->tnt_conf.pitch4;
	d->pitch[5] = d->tnt_conf.pitch5;
	d->pitch[6] = d->tnt_conf.pitch6;
	d->current[0] = 0;
	d->current[1] = d->tnt_conf.current1;
	d->current[2] = d->tnt_conf.current2;
	d->current[3] = d->tnt_conf.current3;
	d->current[4] = d->tnt_conf.current4;
	d->current[5] = d->tnt_conf.current5;
	d->current[6] = d->tnt_conf.current6;
	//Check for current inputs
	d->current_count=0;
	int i = 1;
	while (i <= 6){
		if (d->current[i]!=0 && d->pitch[i]>d->pitch[i-1]) {
			d->current_count = i;
			if (d->tnt_conf.pitch_kp_input) {
				d->kp[i]=d->current[i];
			} else {d->kp[i]=d->current[i]/d->pitch[i];}
		} else { i=7; }
		i++;
	}
	//Check kp0 for an appropriate value, prioritizing kp1
	if (d->current_count > 0) {
		if (d->kp[1]<d->tnt_conf.kp0) {
			d->kp[0]= d->kp[1];
		} else { d->kp[0] = d->tnt_conf.kp0; }
	} else { d->kp[0] = d->tnt_conf.kp0; }

	//initialize current and pitch arrays for braking
	if (d->tnt_conf.brake_curve) {
		d->brakepitch[0] = 0;
		d->brakepitch[1] = d->tnt_conf.brakepitch1;
		d->brakepitch[2] = d->tnt_conf.brakepitch2;
		d->brakepitch[3] = d->tnt_conf.brakepitch3;
		d->brakepitch[4] = d->tnt_conf.brakepitch4;
		d->brakepitch[5] = d->tnt_conf.brakepitch5;
		d->brakepitch[6] = d->tnt_conf.brakepitch6;
		d->brakecurrent[0] = 0;
		d->brakecurrent[1] = d->tnt_conf.brakecurrent1;
		d->brakecurrent[2] = d->tnt_conf.brakecurrent2;
		d->brakecurrent[3] = d->tnt_conf.brakecurrent3;
		d->brakecurrent[4] = d->tnt_conf.brakecurrent4;
		d->brakecurrent[5] = d->tnt_conf.brakecurrent5;
		d->brakecurrent[6] = d->tnt_conf.brakecurrent6;
		//Check for current inputs
		d->brake_current_count=0;
		int i = 1;
		while (i <= 6){
			if (d->brakecurrent[i]!=0 && d->brakepitch[i]>d->brakepitch[i-1]) {
				d->brake_current_count = i;
				if (d->tnt_conf.pitch_kp_input_brake) {
					d->brakekp[i]=d->brakecurrent[i];
				} else {d->brakekp[i]=d->brakecurrent[i]/d->brakepitch[i];}
			} else { i=7; }
			i++;
		}
		//Check kp0 for an appropriate value, prioritizing kp1
		if (d->brake_current_count > 0) {
			if (d->brakekp[1]<d->tnt_conf.brake_kp0) {
				d->brakekp[0]= d->brakekp[1];
			} else { d->brakekp[0] = d->tnt_conf.brake_kp0; }
		} else { d->brakekp[0] = d->tnt_conf.brake_kp0; }
	}
	
	//Check for roll inputs
	if (d->tnt_conf.roll_kp1<d->tnt_conf.roll_kp2 && d->tnt_conf.roll1<d->tnt_conf.roll2) {
		if (d->tnt_conf.roll_kp2<d->tnt_conf.roll_kp3 && d->tnt_conf.roll2<d->tnt_conf.roll3) {
			d->roll_count = 3;
		} else {d->roll_count = 2;}
	} else if (d->tnt_conf.roll_kp1 >0 && d->tnt_conf.roll1>0) {
		d->roll_count = 1;
	} else {d->roll_count = 0;}
	if (d->tnt_conf.brkroll_kp1<d->tnt_conf.brkroll_kp2 && d->tnt_conf.brkroll1<d->tnt_conf.brkroll2) {
		if (d->tnt_conf.brkroll_kp2<d->tnt_conf.brkroll_kp3 && d->tnt_conf.brkroll2<d->tnt_conf.brkroll3) {
			d->brkroll_count = 3;
		} else {d->brkroll_count = 2;}
	} else if (d->tnt_conf.brkroll_kp1 >0 && d->tnt_conf.brkroll1>0) {
		d->brkroll_count = 1;
	} else {d->brkroll_count = 0;}

	//Surge
	d->surge_ramp_rate =  d->tnt_conf.surge_duty / 100 / (float)d->tnt_conf.hertz;
}

static void reset_vars(data *d) {
	motor_data_reset(&d->motor);
	
	// Set values for startup
	d->setpoint = d->pitch_angle;
	d->setpoint_target_interpolated = d->pitch_angle;
	d->setpoint_target = 0;
	d->brake_timeout = 0;
	d->softstart_pid_limit = 0;
	d->startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance;
	d->overcurrent = false;
	d->overcurrent_timer = 0;
	
	//Input tilt/ Sticky tilt
	if (d->inputtilt_interpolated != d->stickytilt_val || !(VESC_IF->get_ppm_age() < 1)) { 	// Persistent sticky tilt value if we are at value with remote connected
		d->inputtilt_interpolated = 0;			// Reset other values
	}
	
	//Control variables
	d->pid_value = 0;
	d->pid_mod = 0;
	d->roll_pid_mod = 0;
	
	// Feature: click on start
	d->start_counter_clicks = d->start_counter_clicks_max;
	
	// Traction Control
	d->traction_control = false;
	d->direction = 0;
	
	// Surge
	d->last_proportional = 0;
	d->surge = false;
	d->surge_off = false;
	
	//Low pass pitch filter
	d->prop_smooth = 0;
	d->abs_prop_smooth = 0;
	
	//Kalman filter
	d->P00 = 0;
	d->P01 = 0;
	d->P10 = 0;
	d->P11 = 0;
	d->bias = 0;
	d->pitch_smooth = d->pitch_angle;
	d->pitch_smooth_kalman = d->pitch_angle;

	//Stability
	d->stabl = 0;

	// Haptic Buzz:
	d->haptic_tone_in_progress = false;
	d->haptic_timer = d->current_time;
	d->applied_haptic_current = 0;
}


/**
 *	check_odometer: see if we need to write back the odometer during fault state
 */
static void check_odometer(data *d)
{
	// Make odometer persistent if we've gone 200m or more
	if (d->odometer_dirty > 0) {
		float stored_odo = VESC_IF->mc_get_odometer();
		if ((stored_odo > d->odometer + 200) || (stored_odo < d->odometer - 10000)) {
			if (d->odometer_dirty == 1) {
				// Wait 10 seconds before writing to avoid writing if immediately continuing to ride
				d->odo_timer = d->current_time;
				d->odometer_dirty++;
			}
			else if ((d->current_time - d->odo_timer) > 10) {
				VESC_IF->store_backup_data();
				d->odometer = VESC_IF->mc_get_odometer();
				d->odometer_dirty = 0;
			}
		}
	}
}

static float get_setpoint_adjustment_step_size(data *d) {
	switch (d->state.sat) {
	case (SAT_NONE):
		return d->tiltback_return_step_size;
	case (SAT_CENTERING):
		return d->startup_step_size;
	case (SAT_REVERSESTOP):
		return d->reverse_stop_step_size;
	case (SAT_PB_DUTY):
		return d->tiltback_duty_step_size;
	case (SAT_PB_HIGH_VOLTAGE):
	case (SAT_PB_TEMPERATURE):
		return d->tiltback_hv_step_size;
	case (SAT_PB_LOW_VOLTAGE):
		return d->tiltback_lv_step_size;
	case (SAT_UNSURGE):
		return d->tiltback_surge_step_size;
	case (SAT_SURGE):
		return 25;
	default:
		return 0;
	}
}

bool is_engaged(const data *d) {
    if (d->footpad_sensor.state == FS_BOTH) {
        return true;
    }

    if (d->footpad_sensor.state == FS_LEFT || d->footpad_sensor.state == FS_RIGHT) {
        // 5 seconds after stopping we allow starting with a single sensor (e.g. for jump starts)
        bool is_simple_start =
            d->tnt_conf.startup_simplestart_enabled && (d->current_time - d->disengage_timer > 5);

        if (d->tnt_conf.fault_is_dual_switch || is_simple_start) {
            return true;
        }
    }
    return false;
}


// Fault checking order does not really matter. From a UX perspective, switch should be before angle.
static bool check_faults(data *d) {
        bool disable_switch_faults = d->tnt_conf.fault_moving_fault_disabled &&
            // Rolling forward (not backwards!)
            d->motor.erpm > (d->tnt_conf.fault_adc_half_erpm * 2) &&
            // Not tipped over
            fabsf(d->roll) < 40;

        // Check switch
        // Switch fully open
        if (d->footpad_sensor.state == FS_NONE) {
            if (!disable_switch_faults) {
                if ((1000.0 * (d->current_time - d->fault_switch_timer)) >
                    d->tnt_conf.fault_delay_switch_full) {
                    state_stop(&d->state, STOP_SWITCH_FULL);
                    return true;
                }
                // low speed (below 6 x half-fault threshold speed):
                else if (
                    (d->motor.abs_erpm < d->tnt_conf.fault_adc_half_erpm * 6) &&
                    (1000.0 * (d->current_time - d->fault_switch_timer) >
                     d->tnt_conf.fault_delay_switch_half)) {
                    state_stop(&d->state, STOP_SWITCH_FULL);
                    return true;
                }
            }

            if (d->motor.abs_erpm < 200 && fabsf(d->pitch) > 14 &&
                fabsf(d->inputtilt_interpolated) < 30 && sign(d->pitch) == d->motor.erpm_sign) {
                state_stop(&d->state, STOP_QUICKSTOP);
                return true;
            }
        } else {
            d->fault_switch_timer = d->current_time;
        }

        // Switch partially open and stopped
        if (!d->tnt_conf.fault_is_dual_switch) {
            if (!is_engaged(d) && d->motor.abs_erpm < d->tnt_conf.fault_adc_half_erpm) {
                if ((1000.0 * (d->current_time - d->fault_switch_half_timer)) >
                    d->tnt_conf.fault_delay_switch_half) {
                    state_stop(&d->state, STOP_SWITCH_HALF);
                    return true;
                }
            } else {
                d->fault_switch_half_timer = d->current_time;
            }
        }

        // Check roll angle
        if (fabsf(d->roll) > d->tnt_conf.fault_roll) {
            if ((1000.0 * (d->current_time - d->fault_angle_roll_timer)) >
                d->tnt_conf.fault_delay_roll) {
                state_stop(&d->state, STOP_ROLL);
                return true;
            }
        } else {
            d->fault_angle_roll_timer = d->current_time;

            if (d->tnt_conf.fault_darkride_enabled) {
                if (fabsf(d->roll) > 100 && fabsf(d->roll) < 135) {
                    state_stop(&d->state, STOP_ROLL);
                    return true;
                }
            }
        }

    // Check pitch angle
    if (fabsf(d->pitch) > d->tnt_conf.fault_pitch && fabsf(d->inputtilt_interpolated) < 30) {
        if ((1000.0 * (d->current_time - d->fault_angle_pitch_timer)) >
            d->tnt_conf.fault_delay_pitch) {
            state_stop(&d->state, STOP_PITCH);
            return true;
        }
    } else {
        d->fault_angle_pitch_timer = d->current_time;
    }

    return false;
}

static void calculate_setpoint_target(data *d) {
	float input_voltage = VESC_IF->mc_get_input_voltage_filtered();
	
	if (input_voltage < d->tnt_conf.tiltback_hv) {
		d->tb_highvoltage_timer = d->current_time;
	}

	if (d->state.sat != SAT_CENTERING && d->setpoint_target_interpolated != d->setpoint_target) {
		// Ignore tiltback during centering sequence
		d->state.sat = SAT_NONE;
	} else if (d->state.wheelslip) {
		d->state.sat = SAT_NONE;
	} else if (d->surge_off) { 
		d->setpoint_target = 0;
		d->state.sat = SAT_UNSURGE;
		if (d->setpoint_target_interpolated < 0.1 && d->setpoint_target_interpolated > -0.1) { // End surge_off once we are back at 0 
			d->surge_off = false;
		}
	} else if (d->surge) {
		if (d->proportional*SIGN(d->erpm) < d->tnt_conf.surge_pitchmargin) {
			d->setpoint_target = d->pitch_angle + d->tnt_conf.surge_pitchmargin * SIGN(d->erpm);
			d->state.sat = SAT_SURGE;
		}
	 } else if (d->motor.duty_cycle > d->tnt_conf.tiltback_duty) {
		if (d->motor.erpm > 0) {
			d->setpoint_target = d->tnt_conf.tiltback_duty_angle;
		} else {
			d->setpoint_target = -d->tnt_conf.tiltback_duty_angle;
		}
	} else if (d->motor.duty_cycle > 0.05 && input_voltage > d->tnt_conf.tiltback_hv) {
		d->beep_reason = BEEP_HV;
		beep_alert(d, 3, false);
		if (((d->current_time - d->tb_highvoltage_timer) > .5) ||
		   (input_voltage > d->tnt_conf.tiltback_hv + 1)) {
		// 500ms have passed or voltage is another volt higher, time for some tiltback
			if (d->motor.erpm > 0) {
		d->setpoint_target = d->tnt_conf.tiltback_hv_angle;
			} else {
				d->setpoint_target = -d->tnt_conf.tiltback_hv_angle;
			}
	
			d->state.sat = SAT_PB_HIGH_VOLTAGE;
		} else {
		// The rider has 500ms to react to the triple-beep, or maybe it was just a short spike
		d->state.sat = SAT_NONE;
		}
	} else if (VESC_IF->mc_temp_fet_filtered() > d->mc_max_temp_fet) {
		// Use the angle from Low-Voltage tiltback, but slower speed from High-Voltage tiltback
		beep_alert(d, 3, true);
		d->beep_reason = BEEP_TEMPFET;
		if (VESC_IF->mc_temp_fet_filtered() > (d->mc_max_temp_fet + 1)) {
			if (d->motor.erpm > 0) {
				d->setpoint_target = d->tnt_conf.tiltback_lv_angle;
			} else {
			d->setpoint_target = -d->tnt_conf.tiltback_lv_angle;
			}
		d->state.sat = SAT_PB_TEMPERATURE;
		} else {
		// The rider has 1 degree Celsius left before we start tilting back
		d->state.sat = SAT_NONE;
		}
	} else if (VESC_IF->mc_temp_motor_filtered() > d->mc_max_temp_mot) {
		// Use the angle from Low-Voltage tiltback, but slower speed from High-Voltage tiltback
		beep_alert(d, 3, true);
		d->beep_reason = BEEP_TEMPMOT;
		if (VESC_IF->mc_temp_motor_filtered() > (d->mc_max_temp_mot + 1)) {
			if (d->motor.erpm > 0) {
				d->setpoint_target = d->tnt_conf.tiltback_lv_angle;
			} else {
				d->setpoint_target = -d->tnt_conf.tiltback_lv_angle;
			}
		d->state.sat = SAT_PB_TEMPERATURE;
		} else {
		// The rider has 1 degree Celsius left before we start tilting back
		d->state.sat = SAT_NONE;
		}
	} else if (d->motor.duty_cycle > 0.05 && input_voltage < d->tnt_conf.tiltback_lv) {
		beep_alert(d, 3, false);
		d->beep_reason = BEEP_LV;
		float abs_motor_current = fabsf(d->motor.current);
		float vdelta = d->tnt_conf.tiltback_lv - input_voltage;
		float ratio = vdelta * 20 / abs_motor_current;
		// When to do LV tiltback:
		// a) we're 2V below lv threshold
		// b) motor current is small (we cannot assume vsag)
		// c) we have more than 20A per Volt of difference (we tolerate some amount of vsag)
		if ((vdelta > 2) || (abs_motor_current < 5) || (ratio > 1)) {
			if (d->motor.erpm > 0) {
				d->setpoint_target = d->tnt_conf.tiltback_lv_angle;
			} else {
				d->setpoint_target = -d->tnt_conf.tiltback_lv_angle;
			}
	
			d->state.sat = SAT_PB_LOW_VOLTAGE;
		} else {
		d->state.sat = SAT_NONE;
		d->setpoint_target = 0;
		}
	}
}

static void calculate_setpoint_interpolated(data *d) {
    if (d->setpoint_target_interpolated != d->setpoint_target) {
        rate_limitf(
            &d->setpoint_target_interpolated,
            d->setpoint_target,
            get_setpoint_adjustment_step_size(d)
        );
    }
}

static void apply_noseangling(data *d){
	float noseangling_target = 0;
	if (d->motor.abs_erpm > d->tnt_conf.tiltback_constant_erpm) {
		noseangling_target += d->tnt_conf.tiltback_constant * d->motor.erpm_sign;
	}
	
	rate_limitf(&d->noseangling_interpolated, noseangling_target, d->noseangling_step_size);

	d->setpoint += d->noseangling_interpolated;
}

static void apply_inputtilt(data *d){ // Input Tiltback
	float input_tiltback_target;
	 
	// Scale by Max Angle
	input_tiltback_target = d->throttle_val * d->tnt_conf.inputtilt_angle_limit;
	
	//Sticky Tilt Input Start	
	if (d->tnt_conf.is_stickytilt_enabled) { 
		float stickytilt_val1 = d->tnt_conf.stickytiltval1; // Value that defines where tilt will stick for both nose up and down. Can be made UI input later.
		float stickytilt_val2 = d->tnt_conf.stickytiltval2; // Value of 0 or above max disables. Max value <=  d->tnt_conf.inputtilt_angle_limit. 
		//Val1 is the default value and value 2 is the step up value that engages when you flick the throttle toward sitcky tilt direction while engaged at val1 (but not to max)
		
		// Monitor the throttle to start sticky tilt
		if ((fabsf(d->throttle_val) - fabsf(d->last_throttle_val) > .001) || // If the throttle is travelling away from center
		   (fabsf(d->throttle_val) > 0.95)) {					// Or close to max
			d->stickytilt_maxval = SIGN(d->throttle_val) * fmaxf(fabsf(d->throttle_val), fabsf(d->stickytilt_maxval)); // Monitor the maximum throttle value
		}
		// Check for conditions to start stop and swap sticky tilt
		if ((d->throttle_val == 0) && // The throttle is at the center
		   (fabsf(d->stickytilt_maxval) > 0.01)) { // And a throttle action just happened
			if ((!d->stickytiltoff) && // Don't apply sticky tilt if we just left sticky tilt
			   (fabsf(d->stickytilt_maxval) < .95)) { //Check that we have not pushed beyond this limit
				if (d->stickytilton) {//if sticky tilt is activated, switch values
					if (((fabsf(d->atr_filtered_current) < d->tnt_conf.stickytilt_holdcurrent) &&
					   (fabsf(d->stickytilt_val) == stickytilt_val2)) ||				//If we are val2 we must be below max current to change
					   (fabsf(d->stickytilt_val) == stickytilt_val1)) {				//If we are at val1 the current restriction is not required
						d->stickytilt_val = SIGN(d->stickytilt_maxval) * ((fabsf(d->stickytilt_val) == stickytilt_val1) ? stickytilt_val2 : stickytilt_val1); //switch sticky tilt values from 1 to 2
					}
				} else { //else apply sticky tilt value 1
					d->stickytilton = true;
					d->stickytilt_val = SIGN(d->stickytilt_maxval) * stickytilt_val1; // Apply val 1 for initial sticky tilt application							
				} 
			}
			d->stickytiltoff = false; // We can turn off this flag after 1 cycle of throttle ==0. Avoids getting stuck on sticky tilt when turning sticky tilt off
			d->stickytilt_maxval = 0; // Reset
		}
		
		if (d->stickytilton) { 	//Apply sticky tilt. Check for exit condition
			//Apply sticky tilt value or throttle values higher than sticky tilt value
			if ((SIGN(d->inputtilt_interpolated) == SIGN(input_tiltback_target)) || (d->throttle_val == 0)) { // If the throttle is at zero or pushed to the direction of the sticky tilt value. 
				if (fabsf(d->stickytilt_val) >= fabsf(input_tiltback_target)) { // If sticky tilt value greater than throttle value keep at sticky value
					input_tiltback_target = d->stickytilt_val; // apply our sticky tilt value
				} //else we will apply the normal throttle value calculated at the beginning of apply_inputtilt() in the direction of sticky tilt
			} else {  //else we will apply the normal throttle value calculated at the beginning of apply_inputtilt() in the opposite direction of sticky tilt and exit sticky tilt
				d->stickytiltoff = true;
				d->stickytilton = false;
			}
		}
		d->last_throttle_val = d->throttle_val;
	}
	//Sticky Tilt Input End
	
	float input_tiltback_target_diff = input_tiltback_target - d->inputtilt_interpolated;

	if (d->tnt_conf.inputtilt_smoothing_factor > 0) { // Smoothen changes in tilt angle by ramping the step size
		float smoothing_factor = 0.02;
		for (int i = 1; i < d->tnt_conf.inputtilt_smoothing_factor; i++) {
			smoothing_factor /= 2;
		}

		float smooth_center_window = 1.5 + (0.5 * d->tnt_conf.inputtilt_smoothing_factor); // Sets the angle away from Target that step size begins ramping down
		if (fabsf(input_tiltback_target_diff) < smooth_center_window) { // Within X degrees of Target Angle, start ramping down step size
			d->inputtilt_ramped_step_size = (smoothing_factor * d->inputtilt_step_size * (input_tiltback_target_diff / 2)) + ((1 - smoothing_factor) * d->inputtilt_ramped_step_size); // Target step size is reduced the closer to center you are (needed for smoothly transitioning away from center)
			float centering_step_size = fminf(fabsf(d->inputtilt_ramped_step_size), fabsf(input_tiltback_target_diff / 2) * d->inputtilt_step_size) * SIGN(input_tiltback_target_diff); // Linearly ramped down step size is provided as minimum to prevent overshoot
			if (fabsf(input_tiltback_target_diff) < fabsf(centering_step_size)) {
				d->inputtilt_interpolated = input_tiltback_target;
			} else {
				d->inputtilt_interpolated += centering_step_size;
			}
		} else { // Ramp up step size until the configured tilt speed is reached
			d->inputtilt_ramped_step_size = (smoothing_factor * d->inputtilt_step_size * SIGN(input_tiltback_target_diff)) + ((1 - smoothing_factor) * d->inputtilt_ramped_step_size);
			d->inputtilt_interpolated += d->inputtilt_ramped_step_size;
		}
	} else { // Constant step size; no smoothing
		if (fabsf(input_tiltback_target_diff) < d->inputtilt_step_size){
		d->inputtilt_interpolated = input_tiltback_target;
	} else {
		d->inputtilt_interpolated += d->inputtilt_step_size * SIGN(input_tiltback_target_diff);
	}
	}
	if (!d->tnt_conf.enable_throttle_stability) {
		d->setpoint += d->inputtilt_interpolated;
	}
}

static float haptic_buzz(data *d, float note_period) {
	if (d->setpointAdjustmentType == TILTBACK_DUTY) {
		d->haptic_type = d->tnt_conf.haptic_buzz_duty;
	} else if (d->setpointAdjustmentType == TILTBACK_HV) {
		d->haptic_type = d->tnt_conf.haptic_buzz_hv;
	} else if (d->setpointAdjustmentType == TILTBACK_LV) {
		d->haptic_type = d->tnt_conf.haptic_buzz_lv;
	} else if (d->setpointAdjustmentType == TILTBACK_TEMP) {
		d->haptic_type = d->tnt_conf.haptic_buzz_temp;
	} else if (d->overcurrent) {
		d->haptic_type = d->tnt_conf.haptic_buzz_current;
	} else { d->haptic_type = HAPTIC_BUZZ_NONE;}

	// This kicks it off till at least one ~300ms tone is completed
	if (d->haptic_type != HAPTIC_BUZZ_NONE) {
		d->haptic_tone_in_progress = true;
	}

	if (d->haptic_tone_in_progress) {
		d->haptic_counter += 1;

		float buzz_current = fminf(20, d->tnt_conf.haptic_buzz_intensity);
		// small periods (1,2) produce audible tone, higher periods produce vibration
		int buzz_period = d->haptic_type;
		if (d->haptic_type == HAPTIC_BUZZ_ALTERNATING) {
			buzz_period = 1;
		}

		// alternate frequencies, depending on "mode"
		buzz_period += d->haptic_mode;
		
		if ((d->abs_erpm < 10000) && (buzz_current > 5)) {
			// scale high currents down to as low as 5A for lower erpms
			buzz_current = fmaxf(d->tnt_conf.haptic_buzz_min, d->abs_erpm / 10000 * buzz_current);
		}

		if (d->haptic_counter > buzz_period) {
			d->haptic_counter = 0;
		}

		if (d->haptic_counter == 0) {
			if (d->applied_haptic_current > 0) {
				d->applied_haptic_current = -buzz_current;
			} else { d->applied_haptic_current = buzz_current; }

			if (fabsf(d->haptic_timer - d->current_time) > note_period) {
				d->haptic_tone_in_progress = false;
				if (d->haptic_type == HAPTIC_BUZZ_ALTERNATING) {
					d->haptic_mode = 5 - d->haptic_mode;
				} else { d->haptic_mode = 1 - d->haptic_mode; }
				d->haptic_timer = d->current_time;
			}
		}
	}
	else {
		d->haptic_mode = 0;
		d->haptic_counter = 0;
		d->haptic_timer = d->current_time;
		d->applied_haptic_current = 0;
	}
	return d->applied_haptic_current;
}

static void brake(data *d) {
    // Brake timeout logic
    float brake_timeout_length = 1;  // Brake Timeout hard-coded to 1s
    if (d->motor.abs_erpm > 1 || d->brake_timeout == 0) {
        d->brake_timeout = d->current_time + brake_timeout_length;
    }

    if (d->brake_timeout != 0 && d->current_time > d->brake_timeout) {
        return;
    }

    VESC_IF->timeout_reset();
    VESC_IF->mc_set_brake_current(d->tnt_conf.brake_current);
}

static void set_current(data *d, float current) {
    VESC_IF->timeout_reset();
    VESC_IF->mc_set_current_off_delay(d->motor_timeout_s);
    VESC_IF->mc_set_current(current);
}

static void set_dutycycle(data *d, float dutycycle){
	// Limit duty output to configured max output
	if (dutycycle >  VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty)) {
		dutycycle = VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty);
	} else if(dutycycle < 0 && dutycycle < (-1) * VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty)) {
		dutycycle = (-1) *  VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty);
	}
	
	// Reset the timeout
	VESC_IF->timeout_reset();
	// Set the current delay
	VESC_IF->mc_set_current_off_delay(d->motor_timeout_seconds);
	// Set Duty
	//VESC_IF->mc_set_duty(dutycycle); 
	VESC_IF->mc_set_duty_noramp(dutycycle);
}

static void check_surge(data *d){
	//Start Surge Code
	//Initialize Surge Cycle
	if ((d->currentavg1 * SIGN(d->erpm) > d->surge_start_current) && 	//High current condition 
	     (d->overcurrent) && 						//If overcurrent is triggered this satifies traction control, min erpm, braking, centering and direction
	     (d->abs_duty_cycle < 0.8) &&					//Prevent surge when pushing top speed
	     (d->current_time - d->surge_timer > 0.7)) {	//Not during an active surge period			
		d->surge_timer = d->current_time; 			//Reset surge timer
		d->surge = true; 					//Indicates we are in the surge cycle of the surge period
		d->surge_setpoint = d->setpoint;			//Records setpoint at the start of surge because surge changes the setpoint
		d->new_duty_cycle = SIGN(d->erpm) * d->abs_duty_cycle;
		d->debug13 = d->proportional;				
		d->debug5 = 0;
		d->debug16 = 0;
		d->debug18 = 0;
		d->debug17 = d->currentavg1;
		d->debug14 = 0;
		d->debug15 = d->surge_start_current;
		d->debug19 = d->duty_cycle;
	}
	
	//Conditions to stop surge and increment the duty cycle
	if (d->surge){	
		d->new_duty_cycle += SIGN(d->erpm) * d->surge_ramp_rate; 	
		if((d->current_time - d->surge_timer > 0.5) ||			//Outside the surge cycle portion of the surge period
		 (-1 * (d->surge_setpoint - d->pitch_angle) * SIGN(d->erpm) > d->tnt_conf.surge_maxangle) ||	//Limit nose up angle based on the setpoint at start of surge because surge changes the setpoint
		 (d->state == RUNNING_WHEELSLIP)) {						//In traction control		
			d->surge = false;
			d->surge_off = true;							//Identifies the end of surge to change the setpoint back to before surge 
			d->pid_value = VESC_IF->mc_get_tot_current_directional_filtered();	//This allows a smooth transition to PID current control
			d->debug5 = d->current_time - d->surge_timer;				//Register how long the surge cycle lasted
			d->debug18 = d->duty_cycle - d->debug19;
			d->debug14 = d->debug18 / (d->current_time - d->surge_timer) * 100;
			if (d->current_time - d->surge_timer >= 0.5) {
				d->debug16 = 111;
			} else if (-1 * (d->surge_setpoint - d->pitch_angle) * SIGN(d->erpm) > d->tnt_conf.surge_maxangle){
				d->debug16 = d->pitch_angle;
			} else if (d->state == RUNNING_WHEELSLIP){
				d->debug16 = 222;
			}
		}
	}
}

static void check_current(data *d){
	d->overcurrent = false;
	float scale_start_current;
	scale_start_current = ((d->tnt_conf.surge_start_hd_current - d->tnt_conf.surge_startcurrent) / (.95 - d->tnt_conf.surge_scaleduty/100)) * d->abs_duty_cycle			//linear scaling mx
		+ (d->tnt_conf.surge_start_hd_current - ((d->tnt_conf.surge_start_hd_current - d->tnt_conf.surge_startcurrent) / (.95 - d->tnt_conf.surge_scaleduty/100)) * .95); 	//+b
	d->surge_start_current = fminf(d->tnt_conf.surge_startcurrent, scale_start_current); 
	if ((d->currentavg1 * SIGN(d->erpm) > d->surge_start_current - d->tnt_conf.overcurrent_margin) && 	//High current condition 
	     (SIGN(d->proportional) == SIGN(d->erpm)) && 				//Not braking
	     (d->state != RUNNING_WHEELSLIP) &&						//Not during traction control
	     (fabsf(d->erpm) > d->tnt_conf.surge_minerpm) &&				//Above the min erpm threshold
	     (SIGN(d->direction) == SIGN(d->erpm)) &&					//Prevents surge if direction has changed rapidly, like a situation with hard brake and wheelslip
	     (d->setpointAdjustmentType != CENTERING)) { 				//Not during startup
		// High current, just haptic buzz don't actually limit currents
		if (d->current_time - d->overcurrent_timer < d->tnt_conf.overcurrent_period) {	//Not during an active overcurrent period
			d->overcurrent = true;
		}
	} else { d->overcurrent_timer = d->current_time; } //reset timer to restrict haptic buzz period once it renters overcurrent
}

static void check_traction(data *d){
	float wheelslip_erpmfactor = d->tnt_conf.wheelslip_scaleaccel - fminf(d->tnt_conf.wheelslip_scaleaccel - 1, (d->tnt_conf.wheelslip_scaleaccel -1) * ( d->abs_erpm / d->tnt_conf.wheelslip_scaleerpm));
	bool erpm_check;
	
	int last_accelidx1 = d->accelidx1 - 1; // Identify the last cycles accel
	if (d->accelidx1 == 0) {
		last_accelidx1 = ACCEL_ARRAY_SIZE1 - 1;
	}
	
	int last_erpmidx = d->erpmidx1 -10; // Identify ERPM at the start of the acceleration array
	if (last_erpmidx < 0) {
		last_erpmidx += ERPM_ARRAY_SIZE1;
	}
	int current_erpmidx = d->erpmidx1 -1;
	if (current_erpmidx < 0) {
		current_erpmidx += ERPM_ARRAY_SIZE1;
	}
	
	// Conditons to end traction control
	if (d->state == RUNNING_WHEELSLIP) {
		if (d->current_time - d->wheelslip_droptimeroff < 0.5) {		// Drop has ended recently
			d->state = RUNNING;
			d->wheelslip_timeroff = d->current_time;
			d->debug4 = 6666;
			d->debug8 = d->accelavg1;
		} else	if (d->current_time - d->wheelslip_timeron > .5) {		// Time out at 500ms
			d->state = RUNNING;
			d->wheelslip_timeroff = d->current_time;
			d->debug4 = 5000;
			d->debug8 = d->accelavg1;
		} else {
			//This section determines if the wheel is acted on by outside forces by detecting acceleration direction change
			if (d->wheelslip_highaccelon2) { 
				if (SIGN(d->wheelslip_accelstartval) != SIGN(d->accelhist1[d->accelidx1])) { 
				// First we identify that the wheel has deccelerated due to traciton control, switching the sign
					d->wheelslip_highaccelon2 = false;				
					d->debug1 = d->current_time - d->wheelslip_timeron;
				} else if (d->current_time - d->wheelslip_timeron > .18) {	// Time out at 150ms if wheel does not deccelerate
					d->state = RUNNING;
					d->wheelslip_timeroff = d->current_time;
					d->debug4 = 1800;
					d->debug8 = d->accelavg1;
				}
			} else if (SIGN(d->accelhist1[d->accelidx1])!= SIGN(d->accelhist1[last_accelidx1])) { 
			// Next we check to see if accel direction changes again from outside forces 
				d->state = RUNNING;
				d->wheelslip_timeroff = d->current_time;
				d->debug4 = d->accelhist1[last_accelidx1];
				d->debug8 = d->accelhist1[d->accelidx1];	
			}
			//This section determines if the wheel is acted on by outside forces by detecting acceleration magnitude
			if (d->state == RUNNING_WHEELSLIP) { // skip this if we are already out of wheelslip to preserve debug values
				if (d->wheelslip_highaccelon1) {		
					if (SIGN(d->wheelslip_accelstartval) * d->accelavg1 < d->tnt_conf.wheelslip_accelend) {	
					// First we identify that the wheel has deccelerated due to traciton control
						d->wheelslip_highaccelon1 = false;
						d->debug7 = d->current_time - d->wheelslip_timeron;
					} else if (d->current_time - d->wheelslip_timeron > .2) {	// Time out at 200ms if wheel does not deccelerate
						d->state = RUNNING;
						d->wheelslip_timeroff = d->current_time;
						d->debug4 = 2000;
						d->debug8 = d->accelavg1;
					}
				} else if (fabsf(d->accelavg1) > d->tnt_conf.wheelslip_margin) { 
				// If accel increases by a value higher than margin, the wheel is acted on by outside forces so we presumably have traction again
					d->state = RUNNING;
					d->wheelslip_timeroff = d->current_time;
					d->debug4 = 2222;
					d->debug8 = d->accelavg1;		
				}
			}
		}
	}	
	if (SIGN(d->erpmhist1[current_erpmidx]) == SIGN(d->erpmhist1[last_erpmidx])) { // We check sign to make sure erpm is increasing or has changed direction. 
		if (fabsf(d->erpmhist1[current_erpmidx]) > fabsf(d-> erpmhist1[last_erpmidx])) {
			erpm_check = true;
		} else {erpm_check = false;} //If the erpm suddenly decreased without changing sign that is a false positive. Do not enter traction control.
	} else if (SIGN(d->direction) != SIGN(d->accelavg1)) { // The wheel has changed direction and if these are the same sign we do not want traciton conrol because we likely just landed with high wheel spin
		erpm_check = true;
	} else {erpm_check = false;}
		
		
	// Initiate traction control
	if ((SIGN(d->motor_current) * d->accelavg1 > d->tnt_conf.wheelslip_accelstart * wheelslip_erpmfactor) && 	// The wheel has broken free indicated by abnormally high acceleration in the direction of motor current
	   (d->state != RUNNING_WHEELSLIP) &&									// Not in traction control
	   (SIGN(d->motor_current) == SIGN(d->accelhist1[d->accelidx1])) &&				// a more precise condition than the first for current dirrention and erpm - last erpm
	   (SIGN(d->proportional) == SIGN(d->erpmhist1[current_erpmidx])) &&							// Do not apply for braking because once we lose traction braking the erpm will change direction and the board will consider it acceleration anyway
	   (d->current_time - d->wheelslip_timeroff > .2) && 						// Did not recently wheel slip.
	   (erpm_check)) {
		d->state = RUNNING_WHEELSLIP;
		d->wheelslip_accelstartval = d->accelavg1;
		d->wheelslip_highaccelon1 = true; 	
		d->wheelslip_highaccelon2 = true; 	
		d->wheelslip_timeron = d->current_time;
		d->wheelslip_erpm = d->erpmhist1[current_erpmidx];
		d->wheelslip_lasterpm = d->erpmhist1[last_erpmidx];
		d->debug6 = d->accelavg1;
		d->debug3 = d->erpmhist1[last_erpmidx];
		d->debug1 = 0;
		d->debug2 = wheelslip_erpmfactor;
		d->debug4 = 0;
		d->debug8 = 0;
		d->debug9 = d->erpmhist1[current_erpmidx];
	}
}

static void check_drop(data *d){
	d->last_accel_z = d->accel[2];
	VESC_IF->imu_get_accel(d->accel);
	float accel_z_reduction = cosf(DEG2RAD_f(d->roll_angle)) * cosf(DEG2RAD_f(d->pitch_angle));		// Accel z is naturally reduced by the pitch and roll angles, so use geometry to compensate
	if (d->applied_accel_z_reduction > accel_z_reduction) {							// Accel z acts slower than pitch and roll so we need to delay accel z reduction as necessary
		d->applied_accel_z_reduction = accel_z_reduction ;						// Roll or pitch are increasing. Do not delay
	} else {
		d->applied_accel_z_reduction = d->applied_accel_z_reduction * .999 + accel_z_reduction * .001;	// Roll or pitch decreasing. Delay to allow accel z to keep pace	
	}
	d->wheelslip_droplimit = 0.92;	// Value of accel z to initiate drop. A drop of about 6" / .1s produces about 0.9 accel y (normally 1)
	if ((d->accel[2] < d->wheelslip_droplimit * d->applied_accel_z_reduction) && 	// Compare accel z to drop limit with reduction for pitch and roll.
	    (d->last_accel_z >= d->accel[2]) &&  			// for fastest landing reaction check that we are still dropping
	    (d->current_time - d->wheelslip_droptimeroff > 0.5)) {	// Don't re-enter drop state for duration 	
		d->wheelslip_dropcount += 1;
		if (d->wheelslip_dropcount > 5) {			// Counter used to reduce nuisance trips
			d->wheelslip_drop = true;
			if (d->current_time - d->wheelslip_droptimeron > 3) { // Set the on timer only if it is well past what is normal so it only sets once
				d->wheelslip_droptimeron = d->current_time;
			}
		}
	} else if (d->wheelslip_drop == true) {		// If any conditions are not met while in drop state, exit drop state
		d->wheelslip_drop = false;
		d->wheelslip_droptimeroff = d->current_time;
		d->wheelslip_dropcount = 0;		// reset
	} else {
		d->wheelslip_drop = false;		// Out of drop state by default
		d->wheelslip_dropcount = 0;		// reset
	}
}

static void apply_rollkp(data *d, float new_pid_value){
	float m = 0;
	float b = 0;
	float rollkp = 0;
	float kp_min = 0;
	float scale_angle_min = 0;
	float scale_angle_max = 1;
	float kp_max = 0;
	float erpmscale = 1;

	//Determine the correct kp to use based on abs_roll_angle
	if (SIGN(d->proportional) != SIGN(d->erpm)) { //Braking
		if (d->abs_roll_angle > d->tnt_conf.brkroll3 && d->brkroll_count==3) {
			kp_min = d->tnt_conf.brkroll_kp3;
			kp_max = d->tnt_conf.brkroll_kp3;
			scale_angle_min = d->tnt_conf.brkroll3;
			scale_angle_max = 90;
		} else if (d->abs_roll_angle > d->tnt_conf.brkroll2 && d->brkroll_count>=2) {
			kp_min = d->tnt_conf.brkroll_kp2;
			scale_angle_min = d->tnt_conf.brkroll2;
			if (d->brkroll_count==3) {
				kp_max = d->tnt_conf.brkroll_kp3;
				scale_angle_max = d->tnt_conf.brkroll3;
			} else {
				kp_max = d->tnt_conf.brkroll_kp2;
				scale_angle_max = 90;
			}
		} else if (d->abs_roll_angle > d->tnt_conf.brkroll1 && d->brkroll_count>=1) {
			kp_min = d->tnt_conf.brkroll_kp1;
			scale_angle_min = d->tnt_conf.brkroll1;
			if (d->brkroll_count>=2) {
				kp_max = d->tnt_conf.brkroll_kp2;
				scale_angle_max = d->tnt_conf.brkroll2;
			} else {
				kp_max = d->tnt_conf.brkroll_kp1;
				scale_angle_max = 90;
			}
		} 
		if (fabsf(d->erpm) < 750) { // If we want to actually stop at low speed reduce kp to 0
			erpmscale = 0;
		}
	} else { //Accelerating
		if (d->abs_roll_angle > d->tnt_conf.roll3 && d->roll_count == 3) {
			kp_min = d->tnt_conf.roll_kp3;
			kp_max = d->tnt_conf.roll_kp3;
			scale_angle_min = d->tnt_conf.roll3;
			scale_angle_max = 90;
		} else if (d->abs_roll_angle > d->tnt_conf.roll2 && d->roll_count>=2) {
			kp_min = d->tnt_conf.roll_kp2;
			scale_angle_min = d->tnt_conf.roll2;
			if (d->roll_count==3) {
				kp_max = d->tnt_conf.roll_kp3;
				scale_angle_max = d->tnt_conf.roll3;
			} else {
				kp_max = d->tnt_conf.roll_kp2;
				scale_angle_max = 90;
			}
		} else if (d->abs_roll_angle > d->tnt_conf.roll1 && d->roll_count>=1) {
			kp_min = d->tnt_conf.roll_kp1;
			scale_angle_min = d->tnt_conf.roll1;
			if (d->roll_count>=2) {
				kp_max = d->tnt_conf.roll_kp2;
				scale_angle_max = d->tnt_conf.roll2;
			} else {
				kp_max = d->tnt_conf.roll_kp1;
				scale_angle_max = 90;
			}
		}
		if (fabsf(d->erpm) < d->tnt_conf.rollkp_higherpm) { 
			erpmscale = 1 + fminf(1,fmaxf(0,1-(d->abs_erpm-d->tnt_conf.rollkp_lowerpm)/(d->tnt_conf.rollkp_higherpm-d->tnt_conf.rollkp_lowerpm)))*(d->tnt_conf.rollkp_maxscale/100);
		}
	}
	m = (kp_max - kp_min) / (scale_angle_max - scale_angle_min); 	//calcs slope between points (scale angle min, min kp) and (scale angle max, max kp)
	b = kp_max - m * scale_angle_max;				//calcs y-int between points (scale angle min, min kp) and (scale angle max, max kp)
	rollkp = fmaxf(kp_min, fminf(kp_max, m * fabsf(d->abs_roll_angle) + b)); // scale kp between min and max with the calculated equation
	rollkp *= erpmscale;
	if (d->setpointAdjustmentType == CENTERING) {
		rollkp=0; 
	}
	d->roll_pid_mod = .99 * d->roll_pid_mod + .01 * rollkp * fabsf(new_pid_value) * SIGN(d->erpm); //always act in the direciton of travel
	d->debug11 = rollkp;
}

static void apply_kalman(data *d){
    // KasBot V2  -  Kalman filter module - http://www.x-firm.com/?page_id=145
    // Modified by Kristian Lauszus
    // See my blog post for more information: http://blog.tkjelectronics.dk/2012/09/a-practical-approach-to-kalman-filter-and-how-to-implement-it
    // Discrete Kalman filter time update equations - Time Update ("Predict")
    // Update xhat - Project the state ahead
	float Q_angle = d->tnt_conf.kalman_factor1/10000;
	float Q_bias = d->tnt_conf.kalman_factor2/10000;
	float R_measure = d->tnt_conf.kalman_factor3/100000;
	// Step 1
	float rate = d->gyro[1] / 131 - d->bias; 
	d->pitch_smooth_kalman += d->diff_time * rate;
	// Update estimation error covariance - Project the error covariance ahead
	// Step 2 
	d->P00 += d->diff_time * (d->diff_time * d->P11 - d->P01 - d->P10 + Q_angle);
	d->P01 -= d->diff_time * d->P11;
	d->P10 -= d->diff_time * d->P11;
	d->P11 += Q_bias * d->diff_time;
	// Discrete Kalman filter measurement update equations - Measurement Update ("Correct")
	// Step 4
	float S = d->P00 + R_measure; // Estimate error
	// Calculate Kalman gain
	// Step 5
	float K0 = d->P00 / S; // Kalman gain - This is a 2x1 vector
	float K1 = d->P10 / S;
	// Calculate angle and bias - Update estimate with measurement zk (newAngle)
	// Step 3
	float y = d->pitch_smooth - d->pitch_smooth_kalman; // Angle difference
	// Step 6
	d->pitch_smooth_kalman += K0 * y;
	d->bias += K1 * y;
	// Calculate estimation error covariance - Update the error covariance
	// Step 7
	float P00_temp = d->P00;
	float P01_temp = d->P01;
	d->P00 -= K0 * P00_temp;
	d->P01 -= K0 * P01_temp;
	d->P10 -= K1 * P00_temp;
	d->P11 -= K1 * P01_temp;
}

static float select_kp(data *d) {
	float kp_mod = 0;
	float kp_min = 0;
	float scale_angle_min = 0;
	float scale_angle_max = 1;
	float kp_max = 0;
	int i = d->current_count;
	//Determine the correct current to use based on d->prop_smooth
	while (i >= 0) {
		if (d->abs_prop_smooth>= d->pitch[i]) {
			kp_min = d->kp[i];
			scale_angle_min = d->pitch[i];
			if (i == d->current_count) { //if we are at the highest current only use highest kp
				kp_max = d->kp[i];
				scale_angle_max = 90;
			} else {
				kp_max = d->kp[i+1];
				scale_angle_max = d->pitch[i+1];
			}
			i=-1;
		}
		i--;
	}
	
	if (d->current_count == 0) { //If no currents 
		if (d->kp[0]==0) {
			kp_mod = 5; //If no kp use 5
		} else { kp_mod = d->kp[0]; }
	} else { //Scale the kp values according to d->prop_smooth
		kp_mod = ((kp_max - kp_min) / (scale_angle_max - scale_angle_min)) * d->abs_prop_smooth			//linear scaling mx
				+ (kp_max - ((kp_max - kp_min) / (scale_angle_max - scale_angle_min)) * scale_angle_max); 	//+b
	}
	d->debug10 = kp_mod;
	return kp_mod;
}

static float select_kp_brake(data *d) {
	float kp_mod = 0;
	float kp_min = 0;
	float scale_angle_min = 0;
	float scale_angle_max = 1;
	float kp_max = 0;
	int i = d->brake_current_count;
	//Determine the correct current to use based on d->prop_smooth
	while (i >= 0) {
		if (d->abs_prop_smooth>= d->brakepitch[i]) {
			kp_min = d->brakekp[i];
			scale_angle_min = d->brakepitch[i];
			if (i == d->brake_current_count) { //if we are at the highest current only use highest kp
				kp_max = d->brakekp[i];
				scale_angle_max = 90;
			} else {
				kp_max = d->brakekp[i+1];
				scale_angle_max = d->brakepitch[i+1];
			}
			i=-1;
		}
		i--;
	}
	
	if (d->brake_current_count == 0) { //If no currents 
		if (d->brakekp[0]==0) {
			kp_mod = 5; //If no kp use 5
		} else { kp_mod = d->brakekp[0]; }
	} else { //Scale the kp values according to d->prop_smooth
		kp_mod = ((kp_max - kp_min) / (scale_angle_max - scale_angle_min)) * d->abs_prop_smooth			//linear scaling mx
				+ (kp_max - ((kp_max - kp_min) / (scale_angle_max - scale_angle_min)) * scale_angle_max); 	//+b
	}
	d->debug10 = -kp_mod; //negative to indicate braking on AppUI
	return kp_mod;
}

static void apply_stability(data *d) {
	float speed_stabl_mod = 0;
	float throttle_stabl_mod = 0;	
	float stabl_mod = 0;
	if (d->tnt_conf.enable_throttle_stability) {
		throttle_stabl_mod = fabsf(d->inputtilt_interpolated) / d->tnt_conf.inputtilt_angle_limit; //using inputtilt_interpolated allows the use of sticky tilt and inputtilt smoothing
	}
	if (d->tnt_conf.enable_speed_stability && fabsf(d->erpm) > d->tnt_conf.stabl_min_erpm) {		
		speed_stabl_mod = fminf(1 ,	// Do not exceed the max value. Divided by 100 for percentage.					
				((1 - 0) / (d->tnt_conf.stabl_max_erpm - d->tnt_conf.stabl_min_erpm)) * fabsf(d->erpm)				//linear scaling mx
				+ (1 - ((1 - 0) / (d->tnt_conf.stabl_max_erpm - d->tnt_conf.stabl_min_erpm)) * d->tnt_conf.stabl_max_erpm) 	//+b
				);
	}
	stabl_mod = fmaxf(speed_stabl_mod,throttle_stabl_mod);
	if (d->stabl > stabl_mod) {
		d->stabl = fmaxf(d->stabl - d->stabl_step_size, 0); //ramp stifness down but not below zero. Ramp is a percentage of max scale
	} else if (d->stabl < stabl_mod) {
		d->stabl = fminf(d->stabl + d->stabl_step_size, stabl_mod); //ramp stability up but do not exceed stabl_mod
	}
}

static void imu_ref_callback(float *acc, float *gyro, float *mag, float dt) {
	UNUSED(mag);
	data *d = (data*)ARG;
	VESC_IF->ahrs_update_mahony_imu(gyro, acc, dt, &d->m_att_ref);
}

static void tnt_thd(void *arg) {
	data *d = (data*)arg;

	configure(d);

	while (!VESC_IF->should_terminate()) {
		beeper_update(d);

		// Update times
		d->current_time = VESC_IF->system_time();

		// Get the IMU Values
		d->roll_angle = RAD2DEG_f(VESC_IF->imu_get_roll());
		d->abs_roll_angle = fabsf(d->roll_angle);
		d->last_pitch_angle = d->pitch_angle;
		d->true_pitch_angle = RAD2DEG_f(VESC_IF->ahrs_get_pitch(&d->m_att_ref)); // True pitch is derived from the secondary IMU filter running with kp=0.2
		d->pitch_angle = RAD2DEG_f(VESC_IF->imu_get_pitch());
		d->last_gyro_y = d->gyro[1];
		VESC_IF->imu_get_gyro(d->gyro);

		//Apply low pass and Kalman filters to pitch
		if (d->tnt_conf.pitch_filter > 0) {
			d->pitch_smooth = biquad_process2(&d->pitch_biquad, d->pitch_angle);
		} else {d->pitch_smooth = d->pitch_angle;}
		if (d->tnt_conf.kalman_factor1 > 0) {
			apply_kalman(d);
		} else {d->pitch_smooth_kalman = d->pitch_smooth;}

		motor_data_update(&d->motor);
		
		// UART/PPM Remote Throttle ///////////////////////
		bool remote_connected = false;
		float servo_val = 0;

		switch (d->tnt_conf.inputtilt_remote_type) {
		case (INPUTTILT_PPM):
			servo_val = VESC_IF->get_ppm();
			remote_connected = VESC_IF->get_ppm_age() < 1;
			break;
		case (INPUTTILT_UART): ; // Don't delete ";", required to avoid compiler error with first line variable init
			remote_state remote = VESC_IF->get_remote_state();
			servo_val = remote.js_y;
			remote_connected = remote.age_s < 1;
			break;
		case (INPUTTILT_NONE):
			break;
		}
		
		if (!remote_connected) {
			servo_val = 0;
		} else {
			// Apply Deadband
			float deadband = d->tnt_conf.inputtilt_deadband;
			if (fabsf(servo_val) < deadband) {
				servo_val = 0.0;
			} else {
				servo_val = SIGN(servo_val) * (fabsf(servo_val) - deadband) / (1 - deadband);
			}

			// Invert Throttle
			servo_val *= (d->tnt_conf.inputtilt_invert_throttle ? -1.0 : 1.0);
		}

		d->throttle_val = servo_val;
		///////////////////////////////////////////////////
		
		d->switch_state = check_adcs(d);

		// Log Values
		d->float_setpoint = d->setpoint;
		d->float_inputtilt = d->inputtilt_interpolated;

		float new_pid_value = 0;		

		// Control Loop State Logic
		switch(d->state.state) {
		case (STATE_STARTUP):
			// Disable output
			brake(d);
			
			//Rest Timer
			if(!d->run_flag) { //First trigger run flag and reset last rest time
				d->rest_time += d->current_time - d->last_rest_time;
			}
			d->run_flag = false;
			d->last_rest_time = d->current_time;
						
			if (VESC_IF->imu_startup_done()) {
				reset_vars(d);
				// set state to READY so we need to meet start conditions to start
				d->state.state = STATE_READY;
	
				// if within 5V of LV tiltback threshold, issue 1 beep for each volt below that
				float bat_volts = VESC_IF->mc_get_input_voltage_filtered();
				float threshold = d->tnt_conf.tiltback_lv + 5;
				if (bat_volts < threshold) {
					int beeps = (int) fminf(6, threshold - bat_volts);
					beep_alert(d, beeps + 1, true);
					d->beep_reason = BEEP_LOWBATT;
				} else {
					// Let the rider know that the board is ready (one long beep)
					beep_alert(d, 1, true);
				}
            		}
           		break;
		case (STATE_RUNNING):
			// Check for faults
			if (check_faults(d)) {
				if (d->state.stop_condition == STOP_SWITCH_FULL) {
					// dirty landings: add extra margin when rightside up
					d->startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance + d->startup_pitch_trickmargin;
					d->fault_angle_pitch_timer = d->current_time;
				}
				break;
			}
			d->odometer_dirty = 1;
			d->disengage_timer = d->current_time;
			
			//Ride Timer
			if(d->run_flag) { //First trigger run flag and reset last ride time
				d->ride_time += d->current_time - d->last_ride_time;
			}
			d->run_flag = true;
			d->last_ride_time = d->current_time;
			
			// Calculate setpoint and interpolation
			calculate_setpoint_target(d);
			calculate_setpoint_interpolated(d);
			d->setpoint = d->setpoint_target_interpolated;
			apply_inputtilt(d); 
			apply_noseangling(d);
			if (d->tnt_conf.enable_speed_stability || d->tnt_conf.enable_throttle_stability) {
				apply_stability(d);
			}
			// Do PID maths
			d->proportional = d->setpoint - d->pitch_angle;
			d->prop_smooth = d->setpoint - d->pitch_smooth_kalman;
			d->abs_prop_smooth = fabsf(d->prop_smooth);
			d->differential = d->proportional - d->last_proportional;
			if (d->tnt_conf.brake_curve && SIGN(d->proportional) != SIGN(d->erpm)) { 	//If braking and user allows braking curve
				new_pid_value = select_kp_brake(d)*d->proportional*(1+d->stabl*d->tnt_conf.stabl_pitch_max_scale/100);			// Use separate braking function
			} else {new_pid_value = select_kp(d)*d->proportional*(1+d->stabl*d->tnt_conf.stabl_pitch_max_scale/100); }				// Else use normal function
			d->last_proportional = d->proportional; 
			d->direction = 0.999 * d->direction + (1-0.999) * SIGN(d->erpm);  // Monitors erpm direction with a delay to prevent nuisance trips to surge and traction control
			
			// Start Rate PID and Booster portion a few cycles later, after the start clicks have been emitted
			// this keeps the start smooth and predictable
			if (d->start_counter_clicks == 0) {
				// Rate P
				float rate_prop = -d->gyro[1];
				if (d->tnt_conf.brake_curve && SIGN(d->proportional) != SIGN(d->erpm)) { 	//If braking and user allows braking curve
					d->pid_mod = d->tnt_conf.brakekp_rate * rate_prop*(1+d->stabl*d->tnt_conf.stabl_rate_max_scale/100);			// Use separate braking function
					d->debug12 = -d->tnt_conf.brakekp_rate * d->stabl*d->tnt_conf.stabl_rate_max_scale/100;					// negative for braking
				} else {
					d->pid_mod = d->tnt_conf.kp_rate * rate_prop*(1+d->stabl*d->tnt_conf.stabl_rate_max_scale/100); 			// Else use normal function
					d->debug12 = d->tnt_conf.kp_rate * d->stabl*d->tnt_conf.stabl_rate_max_scale/100;
				}				
				
				// Apply Turn Boost
				if (d->roll_count > 0 || d->brkroll_count > 0) {
					apply_rollkp(d, new_pid_value);
					d->pid_mod += d->roll_pid_mod;
				}

				if (d->softstart_pid_limit < d->mc_current_max) {
					d->pid_mod = fminf(fabs(d->pid_mod), d->softstart_pid_limit) * SIGN(d->pid_mod);
					d->softstart_pid_limit += d->softstart_ramp_step_size;
				}

				new_pid_value += d->pid_mod;
			} else {
				d->pid_mod = 0;
			}
			
			// Current Limiting!
			float current_limit = d->motor.braking ? d->mc_current_min : d->mc_current_max;
			if (fabsf(new_pid_value) > current_limit) {
				new_pid_value = sign(new_pid_value) * current_limit;
			}
			
			check_current(d);
			
			// Modifiers to PID control
			if (d->tnt_conf.is_traction_enabled) {
				check_drop(d);
				check_traction(d);
			}
			if (d->tnt_conf.is_surge_enabled){
			check_surge(d);
			}
						
			d->last_erpm = d->erpm; //moved here so last erpm can be used in traction control
				
			// PID value application
			if (d->state.wheelslip) { //Reduce acceleration if we are in traction control
				d->pid_value = 0;
			} else if (SIGN(d->erpm) * (d->pid_value - new_pid_value) > d->pid_brake_increment) { // Brake Amp Rate Limiting
				if (new_pid_value > d->pid_value) {
					d->pid_value += d->pid_brake_increment;
				}
				else {
					d->pid_value -= d->pid_brake_increment;
				}
			}
			else {
				d->pid_value = new_pid_value;
			}

			// Output to motor
			if (d->start_counter_clicks) {
				// Generate alternate pulses to produce distinct "click"
				d->start_counter_clicks--;
				if ((d->start_counter_clicks & 0x1) == 0)
					set_current(d, d->pid_value - d->tnt_conf.startup_click_current);
				else
					set_current(d, d->pid_value + d->tnt_conf.startup_click_current);
			} else if (d->surge) { 	
				set_dutycycle(d, d->new_duty_cycle); 		// Set the duty to surge
			} else {
				// modulate haptic buzz onto pid_value unconditionally to allow
				// checking for haptic conditions, and to finish minimum duration haptic effect
				// even after short pulses of hitting the condition(s)
				d->pid_value += haptic_buzz(d, 0.3);
				set_current(d, d->pid_value); 	// Set current as normal.
				d->surge = false;		// Don't re-engage surge if we have left surge cycle until new surge period
			}

			break;

		case (STATE_READY):
			if (d->current_time - d->disengage_timer > 1800) {	// alert user after 30 minutes
				if (d->current_time - d->nag_timer > 60) {		// beep every 60 seconds
					d->nag_timer = d->current_time;
					float input_voltage = VESC_IF->mc_get_input_voltage_filtered();
					if (input_voltage > d->idle_voltage) {
						// don't beep if the voltage keeps increasing (board is charging)
						d->idle_voltage = input_voltage;
					}
					else {
						beep_alert(d, 2, 1);					// 2 long beeps
						d->beep_reason = BEEP_IDLE;
					}
				}
			} else {
				d->nag_timer = d->current_time;
				d->idle_voltage = 0;
			}

			if ((d->current_time - d->fault_angle_pitch_timer) > 1) {
				// 1 second after disengaging - set startup tolerance back to normal (aka tighter)
				d->startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance;
			}

			check_odometer(d);

			//Rest Timer
			if(!d->run_flag) { //First trigger run flag and reset last rest time
				d->rest_time += d->current_time - d->last_rest_time;
			}
			d->run_flag = false;
			d->last_rest_time = d->current_time;
			
			// Check for valid startup position and switch state
			if (fabsf(d->pitch_angle) < d->startup_pitch_tolerance &&
				fabsf(d->roll_angle) < d->tnt_conf.startup_roll_tolerance && 
				d->switch_state == ON) {
				reset_vars(d);
				break;
			}
			
			// Push-start aka dirty landing Part II
			if(d->tnt_conf.startup_pushstart_enabled && (d->abs_erpm > 1000) && (d->switch_state == ON)) {
				if ((fabsf(d->pitch_angle) < 45) && (fabsf(d->roll_angle) < 45)) {
					// 45 to prevent board engaging when upright or laying sideways
					// 45 degree tolerance is more than plenty for tricks / extreme mounts
					reset_vars(d);
					break;
				}
			}
			brake(d);
			break;
		case (STATE_DISABLED):;
			// no set_current, no brake_current
		default:;
		}

		// Delay between loops
		VESC_IF->sleep_us(d->loop_time_us);
	}
}

static void write_cfg_to_eeprom(data *d) {
	uint32_t ints = sizeof(tnt_config) / 4 + 1;
	uint32_t *buffer = VESC_IF->malloc(ints * sizeof(uint32_t));
	if (!buffer) {
		log_error("Failed to write config to EEPROM: Out of memory.");
		return;
	}
	
	bool write_ok = true;
	memcpy(buffer, &(d->tnt_conf), sizeof(tnt_config));
	for (uint32_t i = 0;i < ints;i++) {
		eeprom_var v;
		v.as_u32 = buffer[i];
		if (!VESC_IF->store_eeprom_var(&v, i + 1)) {
			write_ok = false;
			break;
		}
	}

	VESC_IF->free(buffer);

	if (write_ok) {
		eeprom_var v;
		v.as_u32 = TNT_CONFIG_SIGNATURE;
		VESC_IF->store_eeprom_var(&v, 0);
	} else {
        	log_error("Failed to write config to EEPROM.");
   	}

	// Emit 1 short beep to confirm writing all settings to eeprom
	beep_alert(d, 1, 0);
}

static void read_cfg_from_eeprom(data *d) {
	// Read config from EEPROM if signature is correct
	uint32_t ints = sizeof(tnt_config) / 4 + 1;
	uint32_t *buffer = VESC_IF->malloc(ints * sizeof(uint32_t));
	if (!buffer) {
        	log_error("Failed to read config from EEPROM: Out of memory.");
        	return;
    	}
	
	eeprom_var v;	
	bool read_ok = VESC_IF->read_eeprom_var(&v, 0);
	if (read_ok) {
		if (v.as_u32 == TNT_CONFIG_SIGNATURE) {
			for (uint32_t i = 0;i < ints;i++) {
				if (!VESC_IF->read_eeprom_var(&v, i + 1)) {
					read_ok = false;
					break;
				}
				buffer[i] = v.as_u32;
			}
		} else {
			log_error("Failed signature check while reading config from EEPROM, using defaults.");
			confparser_set_defaults_refloatconfig(config);
			return;
	        }
	}

	if (read_ok) {
		memcpy(&(d->tnt_conf), buffer, sizeof(tnt_config));
	} else {
		confparser_set_defaults_tnt_config(&(d->tnt_conf));
		log_error("Failed to read config from EEPROM, using defaults.");
	}

	VESC_IF->free(buffer);
}


static void data_init(data *d) {
    memset(d, 0, sizeof(data));
    read_cfg_from_eeprom(&d->tnt_conf);
    d->odometer = VESC_IF->mc_get_odometer();
}

static float app_get_debug(int index) {
    data *d = (data *) ARG;

    switch (index) {
    case (1):
        return d->pid_value;
    case (2):
        return d->proportional;
    case (3):
        return d->integral;
    case (4):
        return d->rate_p;
    case (5):
        return d->setpoint;
    case (6):
        return d->atr.offset;
    case (7):
        return d->motor.erpm;
    case (8):
        return d->motor.current;
    case (9):
        return d->motor.atr_filtered_current;
    default:
        return 0;
    }
}

enum {
    COMMAND_GET_INFO = 0,  // get version / package info
    COMMAND_GET_RTDATA = 1,  // get rt data
    COMMAND_CFG_SAVE = 2,  // save config to eeprom
    COMMAND_CFG_RESTORE = 3,  // restore config from eeprom
} Commands;

static void send_realtime_data(data *d){
	static const int bufsize = 101;
	uint8_t buffer[bufsize];
	int32_t ind = 0;
	buffer[ind++] = 111;//Magic Number
	buffer[ind++] = COMMAND_GET_RTDATA;
	float corr_factor;

	// Board State
	buffer[ind++] = (d->state & 0xF) + (d->setpointAdjustmentType << 4);
	buffer[ind++] = (d->switch_state & 0xF) + (d->beep_reason << 4);
	buffer_append_float32_auto(buffer, d->adc1, &ind);
	buffer_append_float32_auto(buffer, d->adc2, &ind);
	buffer_append_float32_auto(buffer, VESC_IF->mc_get_input_voltage_filtered(), &ind);
	buffer_append_float32_auto(buffer, d->currentavg1, &ind); // current atr_filtered_current
	buffer_append_float32_auto(buffer, d->pitch_angle, &ind);
	buffer_append_float32_auto(buffer, d->roll_angle, &ind);

	//Tune Modifiers
	buffer_append_float32_auto(buffer, d->float_setpoint, &ind);
	buffer_append_float32_auto(buffer, d->float_inputtilt, &ind);
	buffer_append_float32_auto(buffer, d->throttle_val, &ind);
	buffer_append_float32_auto(buffer, d->current_time - d->wheelslip_timeron , &ind); //Temporary debug. Time since last wheelslip
	buffer_append_float32_auto(buffer, d->current_time - d->surge_timer , &ind); //Temporary debug. Time since last surge

	// Trip
	if (d->ride_time > 0) {
		corr_factor =  d->current_time / d->ride_time;
	} else {corr_factor = 1;}
	buffer_append_float32_auto(buffer, d->ride_time, &ind); //Temporary debug. Ride Time
	buffer_append_float32_auto(buffer, d->rest_time, &ind); //Temporary debug. Rest time
	buffer_append_float32_auto(buffer, VESC_IF->mc_stat_speed_avg() * 3.6 * .621 * corr_factor, &ind); //Temporary debug. speed avg convert m/s to mph
	buffer_append_float32_auto(buffer, VESC_IF->mc_stat_current_avg() * corr_factor, &ind); //Temporary debug. current avg
	buffer_append_float32_auto(buffer, VESC_IF->mc_stat_power_avg() * corr_factor, &ind); //Temporary debug. power avg
	buffer_append_float32_auto(buffer, (VESC_IF->mc_get_watt_hours(false) - VESC_IF->mc_get_watt_hours_charged(false)) / (VESC_IF->mc_get_distance_abs() * 0.000621), &ind); //Temporary debug. efficiency
	
	// DEBUG
	if (d->tnt_conf.is_tcdebug_enabled) {
		buffer[ind++] = 1;
		buffer_append_float32_auto(buffer, d->debug2, &ind); //Temporary debug. wheelslip erpm factor
		buffer_append_float32_auto(buffer, d->debug6, &ind); //Temporary debug. accel at wheelslip start
		buffer_append_float32_auto(buffer, d->debug3, &ind); //Temporary debug. erpm before wheel slip
		buffer_append_float32_auto(buffer, d->debug9, &ind); //Temporary debug. erpm at wheel slip
		buffer_append_float32_auto(buffer, d->debug4, &ind); //Temporary debug. Debug condition or last accel
		buffer_append_float32_auto(buffer, d->debug8, &ind); //Temporary debug. accel at wheelslip end
	} else if (d->tnt_conf.is_surgedebug_enabled) {
		buffer[ind++] = 2;
		buffer_append_float32_auto(buffer, d->debug13, &ind); //Temporary debug. surge start proportional
		buffer_append_float32_auto(buffer, d->debug18, &ind); //Temporary debug. surge added duty cycle
		buffer_append_float32_auto(buffer, d->debug15, &ind); //Temporary debug. surge start current threshold
		buffer_append_float32_auto(buffer, d->debug16, &ind); //Temporary debug. surge end early from proportional
		buffer_append_float32_auto(buffer, d->debug5, &ind); //Temporary debug. Duration last surge cycle time
		buffer_append_float32_auto(buffer, d->debug17, &ind); //Temporary debug. start current value
		buffer_append_float32_auto(buffer, d->debug14, &ind); //Temporary debug. ramp rate
	} else if (d->tnt_conf.is_tunedebug_enabled) {
		buffer[ind++] = 3;
		buffer_append_float32_auto(buffer, d->pitch_smooth_kalman, &ind); //smooth pitch	
		buffer_append_float32_auto(buffer, d->debug10, &ind); // scaled angle P
		buffer_append_float32_auto(buffer, d->debug10*d->stabl*d->tnt_conf.stabl_pitch_max_scale/100, &ind); // added stiffnes pitch kp
		buffer_append_float32_auto(buffer, d->debug12, &ind); // added stability rate P
		buffer_append_float32_auto(buffer, d->stabl, &ind);
		buffer_append_float32_auto(buffer, d->debug11, &ind); //rollkp
	} else { 
		buffer[ind++] = 0; 
	}

	SEND_APP_DATA(buffer, bufsize, ind);
}

// Handler for incoming app commands
static void on_command_received(unsigned char *buffer, unsigned int len) {
	data *d = (data*)ARG;
	uint8_t magicnr = buffer[0];
	uint8_t command = buffer[1];

	if(len < 2){
		log_error("Received command data too short.");
		return;
	}
	if (magicnr != 111) {
		log_error("Invalid Package ID: %u", magicnr);
		return;
	}

	switch(command) {
		case COMMAND_GET_INFO: {
			int32_t ind = 0;
			uint8_t buffer[10];
			buffer[ind++] = 111;	// magic nr.
			buffer[ind++] = 0x0;	// command ID
			buffer[ind++] = (uint8_t) (10 * APPCONF_TNT_VERSION);
			buffer[ind++] = 1;
			VESC_IF->send_app_data(buffer, ind);
			return;
		}
		case COMMAND_GET_RTDATA: {
			send_realtime_data(d);
			return;
		}
		case COMMAND_CFG_RESTORE: {
			read_cfg_from_eeprom(&d->tnt_conf);
			return;
		}
		case COMMAND_CFG_SAVE: {
			write_cfg_to_eeprom(d);
			return;
		}
		default: {
			if (!VESC_IF->app_is_output_disabled()) {
				log_error("Unknown command received: %u", command);
			}
		}
	}
}

// Register get_debug as a lisp extension
static lbm_value ext_bal_dbg(lbm_value *args, lbm_uint argn) {
	if (argn != 1 || !VESC_IF->lbm_is_number(args[0])) {
		return VESC_IF->lbm_enc_sym_eerror;
	}

	return VESC_IF->lbm_enc_float(app_tnt_get_debug(VESC_IF->lbm_dec_as_i32(args[0])));
}

// Called from Lisp on init to pass in the version info of the firmware
static lbm_value ext_set_fw_version(lbm_value *args, lbm_uint argn) {
	data *d = (data*)ARG;
	if (argn > 2) {
		d->fw_version_major = VESC_IF->lbm_dec_as_i32(args[0]);
		d->fw_version_minor = VESC_IF->lbm_dec_as_i32(args[1]);
		d->fw_version_beta = VESC_IF->lbm_dec_as_i32(args[2]);
	}
	return VESC_IF->lbm_enc_sym_true;
}

// These functions are used to send the config page to VESC Tool
// and to make persistent read and write work
static int get_cfg(uint8_t *buffer, bool is_default) {
	data *d = (data *) ARG;

	tnt_config *cfg;
	if (is_default) {
		cfg = VESC_IF->malloc(sizeof(tnt_config));
		if (!cfg) {
			log_error("Failed to send default config to VESC tool: Out of memory.");
			return 0;
		}
		confparser_set_defaults_refloatconfig(cfg);
	} else {
		cfg = &d->tnt_conf;
	}

	int res = confparser_serialize_refloatconfig(buffer, cfg);

	if (is_default) {
		VESC_IF->free(cfg);
	}

	return res;
}

static bool set_cfg(uint8_t *buffer) {
	data *d = (data *) ARG;

	// don't let users use the TNT Cfg "write" button in special modes
	if (d->state.mode != MODE_NORMAL) {
		return false;
	}
	
	bool res = confparser_deserialize_refloatconfig(buffer, &d->tnt_conf);
	
	// Store to EEPROM
	if (res) {
		write_cfg_to_eeprom(d);
		configure(d);
	}
	
	return res;
}

static int get_cfg_xml(uint8_t **buffer) {
	// Note: As the address of data_tnt_config_ is not known
	// at compile time it will be relative to where it is in the
	// linked binary. Therefore we add PROG_ADDR to it so that it
	// points to where it ends up on the STM32.
	*buffer = data_tnt_config_ + PROG_ADDR;
	return DATA_TNT_CONFIG__SIZE;
}

// Called when code is stopped
static void stop(void *arg) {
	data *d = (data *) arg;
	VESC_IF->imu_set_read_callback(NULL);
	VESC_IF->set_app_data_handler(NULL);
	VESC_IF->conf_custom_clear_configs();
	VESC_IF->request_terminate(d->main_thread);
	log_msg("Terminating.");
	VESC_IF->free(d);
}

INIT_FUN(lib_info *info) {
	INIT_START
	log_msg("Initializing TNT v" PACKAGE_VERSION);

	data *d = VESC_IF->malloc(sizeof(data));
	if (!d) {
		log_error("Out of memory, startup failed.");
		return false;
	}
	data_init(d);

	info->stop_fun = stop;	
	info->arg = d;
	
	VESC_IF->conf_custom_add_config(get_cfg, set_cfg, get_cfg_xml);

	if ((d->tnt_conf.is_beeper_enabled) || (d->tnt_conf.inputtilt_remote_type != INPUTTILT_PPM)) {
		beeper_init();
	}

	VESC_IF->ahrs_init_attitude_info(&d->m_att_ref);
	d->m_att_ref.acc_confidence_decay = 0.1;
	d->m_att_ref.kp = 0.2;

	VESC_IF->imu_set_read_callback(imu_ref_callback);
	
	footpad_sensor_update(&d->footpad_sensor, &d->tnt_conf);
	

	d->main_thread = VESC_IF->spawn(tnt_thd, 1024, "TNT Main", d);
	if (!d->main_thread) {
		log_error("Failed to spawn TNT Main thread.");
		return false;
	}

	VESC_IF->set_app_data_handler(on_command_received);
	VESC_IF->lbm_add_extension("ext-tnt-dbg", ext_bal_dbg);
	VESC_IF->lbm_add_extension("ext-set-fw-version", ext_set_fw_version);

	return true;
}

void send_app_data_overflow_terminate() {
    VESC_IF->request_terminate(((data *) ARG)->main_thread);
}