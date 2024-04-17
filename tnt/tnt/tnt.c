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
#include "motor_data_tnt.h"
#include "state_tnt.h"
#include "utils_tnt.h"
#include "proportional_gain.h"
#include "kalman.h"
#include "traction.h"
#include "high_current.h"
#include "runtime.h"
#include "ride_time.h"
#include "remote_input.h"

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
	lib_thread main_thread;
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
	float noseangling_step_size;
	float mc_max_temp_fet, mc_max_temp_mot;
	float mc_current_max, mc_current_min;
	bool duty_beeping;

	// Feature: Soft Start
	float softstart_pid_limit, softstart_ramp_step_size;

	// Feature: True Pitch
	ATTITUDE_INFO m_att_ref;

	// Brake Amp Rate Limiting:
	float pid_brake_increment;

	// Runtime values grouped for easy access in ancillary functions
	RuntimeData rt // pitch_angle proportional pid_value setpoint current_time roll_angle  last_accel_z  accel[3]

	// Runtime values read from elsewhere
	float last_pitch_angle, abs_roll_angle;
 	float true_pitch_angle;
	float gyro[3];
	
	float max_duty_with_margin;

	FootpadSensor footpad_sensor;

	// Rumtime state values
	State state;

	float pid_mod;
	float setpoint_target, setpoint_target_interpolated;
	float noseangling_interpolated;
	float disengage_timer, nag_timer;
	float idle_voltage;
	float fault_angle_pitch_timer, fault_angle_roll_timer, fault_switch_timer, fault_switch_half_timer; // Seconds
	float motor_timeout_s;
	float brake_timeout; // Seconds
	float tb_highvoltage_timer;
	float switch_warn_beep_erpm;

	// Odometer
	float odo_timer;
	int odometer_dirty;
	uint64_t odometer;

	//Remote
	RemoteData remote;
	StickyTiltData st_tilt;

	// Feature: Surge
	SurgeData surge;
	SurgeDebug surge_dbg;
	
	//Traction Control
	TractionData traction;
	
	// Drop Detection
	DropData drop;
	
	// Low Pass Filter
	float pitch_smooth; 
	Biquad pitch_biquad;
	
	// Kalman Filter
	KalmanFilter pitch_kalman; 
	float pitch_smooth_kalman;
	float diff_time, last_time;

	// Throttle/Brake Scaling
	float prop_smooth, abs_prop_smooth;
	float roll_pid_mod;
	KpArray accel_kp;
	KpArray brake_kp;
	KpArray roll_accel_kp;
	KpArray roll_brake_kp;

	// Dynamic Stability
	float stabl;
	float stabl_step_size;

	//Haptic Buzz
	float applied_haptic_current, haptic_timer;
	int haptic_counter, haptic_mode;
	HAPTIC_BUZZ_TYPE haptic_type;
	bool haptic_tone_in_progress;

	//Trip Debug
	RideTimeData ridetimer;

	//Debug
	float debug1, debug2;

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

static void configure(data *d) {
	state_init(&d->state, d->tnt_conf.disable_pkg);
	
	// This timer is used to determine how long the board has been disengaged / idle. subtract 1 second to prevent the haptic buzz disengage click on "write config"
	d->disengage_timer = d->rt.current_time - 1;

	// Loop time in microseconds
	d->loop_time_us = 1e6 / d->tnt_conf.hertz;

	// Loop time in seconds times 20 for a nice long grace period
	d->motor_timeout_s = 20.0f / d->tnt_conf.hertz;

	//Setpoint Adjustment
	d->startup_step_size = d->tnt_conf.startup_speed / d->tnt_conf.hertz;
	d->tiltback_duty_step_size = d->tnt_conf.tiltback_duty_speed / d->tnt_conf.hertz;
	d->tiltback_hv_step_size = d->tnt_conf.tiltback_hv_speed / d->tnt_conf.hertz;
	d->tiltback_lv_step_size = d->tnt_conf.tiltback_lv_speed / d->tnt_conf.hertz;
	d->tiltback_return_step_size = d->tnt_conf.tiltback_return_speed / d->tnt_conf.hertz;
	d->tiltback_ht_step_size = d->tnt_conf.tiltback_ht_speed / d->tnt_conf.hertz;

	//Dynamic Stability
	d->stabl_step_size = d->tnt_conf.stabl_ramp/100 / d->tnt_conf.hertz;
	
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

	// Maximum amps change when braking
	d->pid_brake_increment = 100;
	if (d->pid_brake_increment < 0.1) {
		d->pid_brake_increment = 5;
	}

	// Speed above which to warn users about an impending full switch fault
	d->switch_warn_beep_erpm = d->tnt_conf.is_footbeep_enabled ? 2000 : 100000;

	d->beeper_enabled = d->tnt_conf.is_beeper_enabled;

	//Remote
	configure_remote_features(&d->tnt_conf, &d->remote, &d->st_tilt);
	
	//Pitch Biquad Configure
	biquad_configure(&d->pitch_biquad, BQ_LOWPASS, d->tnt_conf.pitch_filter / d->tnt_conf.hertz);

	//Pitch Kalman Configure
	configure_kalman(&d->tnt_conf, &d->pitch_kalman);

	//Motor Data Configure
	motor_data_configure(&d->motor, 3.0 / d->tnt_conf.hertz);
	
	//initialize current and pitch arrays for acceleration
	angle_kp_reset(&d->accel_kp);
	pitch_kp_configure(&d->tnt_conf, &d->accel_kp, 1);
	
	//initialize current and pitch arrays for braking
	if (d->tnt_conf.brake_curve) {
		angle_kp_reset(&d->brake_kp);
		pitch_kp_configure(&d->tnt_conf, &d->brake_kp, 2);
	}
	
	//Check for roll inputs
	roll_kp_configure(&d->tnt_conf, &d->roll_accel_kp, 1);
	roll_kp_configure(&d->tnt_conf, &d->roll_brake_kp, 2);
		
	//Surge Configure
	configure_surge(&d->surge, &d->tnt_conf);

	if (d->state.state == STATE_DISABLED) {
	    beep_alert(d, 3, false);
	} else {
	    beep_alert(d, 1, false);
	}
}

static void reset_vars(data *d) {
	motor_data_reset(&d->motor);
	
	// Set values for startup
	d->rt.setpoint = d->rt.pitch_angle;
	d->setpoint_target_interpolated = d->rt.pitch_angle;
	d->setpoint_target = 0;
	d->brake_timeout = 0;
	d->softstart_pid_limit = 0;
	d->startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance;
	
	//Input tilt/ Sticky tilt
	if (d->st_tilt.inputtilt_interpolated != d->st_tilt.value || VESC_IF->get_ppm_age() > 1) { 	// Persistent sticky tilt value if we are at value with remote connected
		d->st_tilt.inputtilt_interpolated = 0;			// Reset values not at sticky tilt or if remote is off
	}
	
	//Control variables
	d->rt.pid_value = 0;
	d->pid_mod = 0;
	d->roll_pid_mod = 0;
	
	// Feature: click on start
	d->start_counter_clicks = d->start_counter_clicks_max;
	
	// Surge
	reset_surge(&d->surge);
	
	//Low pass pitch filter
	d->prop_smooth = 0;
	d->abs_prop_smooth = 0;
	d->pitch_smooth = d->rt.pitch_angle;
	biquad_reset(&d->pitch_biquad);
	
	//Kalman filter
	reset_kalman(&d->pitch_kalman);
	d->pitch_smooth_kalman = d->rt.pitch_angle;

	//Stability
	d->stabl = 0;

	// Haptic Buzz:
	d->haptic_tone_in_progress = false;
	d->haptic_timer = d->rt.current_time;
	d->applied_haptic_current = 0;

	state_engage(&d->state);
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
				d->odo_timer = d->rt.current_time;
				d->odometer_dirty++;
			}
			else if ((d->rt.current_time - d->odo_timer) > 10) {
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
	case (SAT_PB_DUTY):
		return d->tiltback_duty_step_size;
	case (SAT_PB_HIGH_VOLTAGE):
		return d->tiltback_hv_step_size;
	case (SAT_PB_TEMPERATURE):
		return d->tiltback_ht_step_size;
	case (SAT_PB_LOW_VOLTAGE):
		return d->tiltback_lv_step_size;
	case (SAT_UNSURGE):
		return d->surge.tiltback_step_size;
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
            d->tnt_conf.startup_simplestart_enabled && (d->rt.current_time - d->disengage_timer > 5);

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
            fabsf(d->rt.roll_angle) < 40;

        // Check switch
        // Switch fully open
        if (d->footpad_sensor.state == FS_NONE) {
            if (!disable_switch_faults) {
                if ((1000.0 * (d->rt.current_time - d->fault_switch_timer)) >
                    d->tnt_conf.fault_delay_switch_full) {
                    state_stop(&d->state, STOP_SWITCH_FULL);
                    return true;
                }
                // low speed (below 6 x half-fault threshold speed):
                else if (
                    (d->motor.abs_erpm < d->tnt_conf.fault_adc_half_erpm * 6) &&
                    (1000.0 * (d->rt.current_time - d->fault_switch_timer) >
                     d->tnt_conf.fault_delay_switch_half)) {
                    state_stop(&d->state, STOP_SWITCH_FULL);
                    return true;
                }
            }
    		if ((d->motor.abs_erpm <200) && (fabsf(d->true_pitch_angle) > 14) && 
                (fabsf(d->remote.inputtilt_interpolated) < 30) && 
                (sign(d->true_pitch_angle) ==  d->motor.erpm_sign)) {
    			state_stop(&d->state, STOP_QUICKSTOP);
    			return true;
    		}
        } else {
            d->fault_switch_timer = d->rt.current_time;
        }

        // Switch partially open and stopped
        if (!d->tnt_conf.fault_is_dual_switch) {
            if (!is_engaged(d) && d->motor.abs_erpm < d->tnt_conf.fault_adc_half_erpm) {
                if ((1000.0 * (d->rt.current_time - d->fault_switch_half_timer)) >
                    d->tnt_conf.fault_delay_switch_half) {
                    state_stop(&d->state, STOP_SWITCH_HALF);
                    return true;
                }
            } else {
                d->fault_switch_half_timer = d->rt.current_time;
            }
        }

        // Check roll angle
        if (fabsf(d->rt.roll_angle) > d->tnt_conf.fault_roll) {
            if ((1000.0 * (d->rt.current_time - d->fault_angle_roll_timer)) >
                d->tnt_conf.fault_delay_roll) {
                state_stop(&d->state, STOP_ROLL);
                return true;
            }
        } else {
            d->fault_angle_roll_timer = d->rt.current_time;
        }
        

    // Check pitch angle
    if (fabsf(d->rt.pitch_angle) > d->tnt_conf.fault_pitch && fabsf(d->remote.inputtilt_interpolated) < 30) {
        if ((1000.0 * (d->rt.current_time - d->fault_angle_pitch_timer)) >
            d->tnt_conf.fault_delay_pitch) {
            state_stop(&d->state, STOP_PITCH);
            return true;
        }
    } else {
        d->fault_angle_pitch_timer = d->rt.current_time;
    }

    return false;
}

static void calculate_setpoint_target(data *d) {
	float input_voltage = VESC_IF->mc_get_input_voltage_filtered();
	
	if (input_voltage < d->tnt_conf.tiltback_hv) {
		d->tb_highvoltage_timer = d->rt.current_time;
	}

	if (d->state.wheelslip) {
		d->state.sat = SAT_NONE;
	} else if (d->surge.deactivate) { 
		d->setpoint_target = 0;
		d->state.sat = SAT_UNSURGE;
		if (d->setpoint_target_interpolated < 0.1 && d->setpoint_target_interpolated > -0.1) { // End surge_off once we are back at 0 
			d->surge.deactivate = false;
		}
	} else if (d->surge.active) {
		if (d->rt.proportional*d->motor.erpm_sign < d->tnt_conf.surge_pitchmargin) {
			d->setpoint_target = d->rt.pitch_angle + d->tnt_conf.surge_pitchmargin * d->motor.erpm_sign;
			d->state.sat = SAT_SURGE;
		}
	 } else if (d->motor.duty_cycle > d->tnt_conf.tiltback_duty) {
		if (d->motor.erpm > 0) {
			d->setpoint_target = d->tnt_conf.tiltback_duty_angle;
		} else {
			d->setpoint_target = -d->tnt_conf.tiltback_duty_angle;
		}
		d->state.sat = SAT_PB_DUTY;
	} else if (d->motor.duty_cycle > 0.05 && input_voltage > d->tnt_conf.tiltback_hv) {
		d->beep_reason = BEEP_HV;
		beep_alert(d, 3, false);
		if (((d->rt.current_time - d->tb_highvoltage_timer) > .5) ||
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
				d->setpoint_target = d->tnt_conf.tiltback_ht_angle;
			} else {
				d->setpoint_target = -d->tnt_conf.tiltback_ht_angle;
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
				d->setpoint_target = d->tnt_conf.tiltback_ht_angle;
			} else {
				d->setpoint_target = -d->tnt_conf.tiltback_ht_angle;
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
	} else if (d->state.sat != SAT_CENTERING || d->setpoint_target_interpolated == d->setpoint_target) {
        	// Normal running
         	d->state.sat = SAT_NONE;
	        d->setpoint_target = 0;
	}
	
	//Duty beep
	if (d->setpointAdjustmentType == SAT_PB_DUTY) {
		if (d->tnt_conf.is_dutybeep_enabled || (d->tnt_conf.tiltback_duty_angle == 0)) {
			beep_on(d, true);
			d->beep_reason = BEEP_DUTY;
			d->duty_beeping = true;
		}
	}
	else {
		if (d->duty_beeping) {
			beep_off(d, false);
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

	d->rt.setpoint += d->noseangling_interpolated;
}

static float haptic_buzz(data *d, float note_period) {
	if (d->state.sat == SAT_PB_DUTY) {
		d->haptic_type = d->tnt_conf.haptic_buzz_duty;
	} else if (d->state.sat == SAT_PB_HIGH_VOLTAGE) {
		d->haptic_type = d->tnt_conf.haptic_buzz_hv;
	} else if (d->state.sat == SAT_PB_LOW_VOLTAGE) {
		d->haptic_type = d->tnt_conf.haptic_buzz_lv;
	} else if (d->state.sat == SAT_PB_TEMPERATURE) {
		d->haptic_type = d->tnt_conf.haptic_buzz_temp;
	} else if (d->surge.high_current_buzz) {
		d->haptic_type = d->tnt_conf.haptic_buzz_current;
	} else { d->haptic_type = HAPTIC_BUZZ_NONE;}

	// This kicks it off till at least one ~300ms tone is completed
	if (d->haptic_type != HAPTIC_BUZZ_NONE) {
		d->haptic_tone_in_progress = true;
	}

	if (d->haptic_tone_in_progress) {
		d->haptic_counter += 1;

		float buzz_current = min(20, d->tnt_conf.haptic_buzz_intensity);
		// small periods (1,2) produce audible tone, higher periods produce vibration
		int buzz_period = d->haptic_type;
		if (d->haptic_type == HAPTIC_BUZZ_ALTERNATING) {
			buzz_period = 1;
		}

		// alternate frequencies, depending on "mode"
		buzz_period += d->haptic_mode;
		
		if ((d->motor.abs_erpm < 10000) && (buzz_current > 5)) {
			// scale high currents down to as low as 5A for lower erpms
			buzz_current = max(d->tnt_conf.haptic_buzz_min, d->motor.abs_erpm / 10000 * buzz_current);
		}

		if (d->haptic_counter > buzz_period) {
			d->haptic_counter = 0;
		}

		if (d->haptic_counter == 0) {
			if (d->applied_haptic_current > 0) {
				d->applied_haptic_current = -buzz_current;
			} else { d->applied_haptic_current = buzz_current; }

			if (fabsf(d->haptic_timer - d->rt.current_time) > note_period) {
				d->haptic_tone_in_progress = false;
				if (d->haptic_type == HAPTIC_BUZZ_ALTERNATING) {
					d->haptic_mode = 5 - d->haptic_mode;
				} else { d->haptic_mode = 1 - d->haptic_mode; }
				d->haptic_timer = d->rt.current_time;
			}
		}
	}
	else {
		d->haptic_mode = 0;
		d->haptic_counter = 0;
		d->haptic_timer = d->rt.current_time;
		d->applied_haptic_current = 0;
	}
	return d->applied_haptic_current;
}

static void brake(data *d) {
    // Brake timeout logic
    float brake_timeout_length = 1;  // Brake Timeout hard-coded to 1s
    if (d->motor.abs_erpm > 1 || d->brake_timeout == 0) {
        d->brake_timeout = d->rt.current_time + brake_timeout_length;
    }

    if (d->brake_timeout != 0 && d->rt.current_time > d->brake_timeout) {
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
	VESC_IF->mc_set_current_off_delay(d->motor_timeout_s);
	// Set Duty
	//VESC_IF->mc_set_duty(dutycycle); 
	VESC_IF->mc_set_duty_noramp(dutycycle);
}

static void apply_stability(data *d) {
	float speed_stabl_mod = 0;
	float throttle_stabl_mod = 0;	
	float stabl_mod = 0;
	if (d->tnt_conf.enable_throttle_stability) {
		throttle_stabl_mod = fabsf(d->remote.inputtilt_interpolated) / d->tnt_conf.inputtilt_angle_limit; //using inputtilt_interpolated allows the use of sticky tilt and inputtilt smoothing
	}
	if (d->tnt_conf.enable_speed_stability && d->motor.abs_erpm > d->tnt_conf.stabl_min_erpm) {		
		speed_stabl_mod = min(1 ,	// Do not exceed the max value.				
				lerp(d->tnt_conf.stabl_min_erpm, d->tnt_conf.stabl_max_erpm, 0, 1, d->motor.abs_erpm));
	}
	stabl_mod = max(speed_stabl_mod,throttle_stabl_mod);
	rate_limitf(&d->stabl, stabl_mod, d->stabl_step_size); 
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
		d->rt.current_time = VESC_IF->system_time();
		if (d->last_time == 0) {
			d->last_time = d->rt.current_time;
		}
		d->diff_time = d->rt.current_time - d->last_time;
		d->last_time = d->rt.current_time;
		
		// Get the IMU Values
		d->rt.roll_angle = rad2deg(VESC_IF->imu_get_roll());
		d->abs_roll_angle = fabsf(d->rt.roll_angle);
		d->last_pitch_angle = d->rt.pitch_angle;
		d->true_pitch_angle = rad2deg(VESC_IF->ahrs_get_pitch(&d->m_att_ref)); // True pitch is derived from the secondary IMU filter running with kp=0.2
		d->rt.pitch_angle = rad2deg(VESC_IF->imu_get_pitch());
		VESC_IF->imu_get_gyro(d->gyro);
		d->rt.last_accel_z = d->rt.accel[2];
		VESC_IF->imu_get_accel(d->rt.accel); //Used for drop detection
		
		//Apply low pass and Kalman filters to pitch
		if (d->tnt_conf.pitch_filter > 0) {
			d->pitch_smooth = biquad_process(&d->pitch_biquad, d->rt.pitch_angle);
		} else {d->pitch_smooth = d->rt.pitch_angle;}
		if (d->tnt_conf.kalman_factor1 > 0) {
			 apply_kalman(d->pitch_smooth, d->gyro[1], &d->pitch_smooth_kalman, d->diff_time, &d->pitch_kalman);
		} else {d->pitch_smooth_kalman = d->pitch_smooth;}

		motor_data_update(&d->motor);
		update_remote(&d->tnt_conf, &d->remote);
		
		//Footpad Sensor
	        footpad_sensor_update(&d->footpad_sensor, &d->tnt_conf);
	        if (d->footpad_sensor.state == FS_NONE && d->state.state == STATE_RUNNING &&
	            d->state.mode != MODE_FLYWHEEL && d->motor.abs_erpm > d->switch_warn_beep_erpm) {
	            // If we're at riding speed and the switch is off => ALERT the user
	            // set force=true since this could indicate an imminent shutdown/nosedive
	            beep_on(d, true);
	            d->beep_reason = BEEP_SENSORS;
	        } else {
	            // if the switch comes back on we stop beeping
	            beep_off(d, false);
	        }

		float new_pid_value = 0;		

		// Control Loop State Logic
		switch(d->state.state) {
		case (STATE_STARTUP):
			// Disable output
			brake(d);
			
			//Rest Timer
			rest_timer(&d->ridetimer, &d->rt);
						
			if (VESC_IF->imu_startup_done()) {
				reset_vars(d);
				// set state to READY so we need to meet start conditions to start
				d->state.state = STATE_READY;
	
				// if within 5V of LV tiltback threshold, issue 1 beep for each volt below that
				float bat_volts = VESC_IF->mc_get_input_voltage_filtered();
				float threshold = d->tnt_conf.tiltback_lv + 5;
				if (bat_volts < threshold) {
					int beeps = (int) min(6, threshold - bat_volts);
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
					d->fault_angle_pitch_timer = d->rt.current_time;
				}
				break;
			}
			d->odometer_dirty = 1;
			d->disengage_timer = d->rt.current_time;
			
			//Ride Timer
			ride_timer(&d->ridetimer, &d->rt);
			
			// Calculate setpoint and interpolation
			calculate_setpoint_target(d);
			calculate_setpoint_interpolated(d);
			d->rt.setpoint = d->setpoint_target_interpolated;

			//Apply Remote Tilt
			float input_tiltback_target = d->remote.throttle_val * d->tnt_conf.inputtilt_angle_limit;
			if (d->tnt_conf.is_stickytilt_enabled) { 
				input_tiltback_target = apply_stickytilt(&d->remote, &d->st_tilt, d->motor.current_avg, input_tiltback_target);
			}
			apply_inputtilt(&d->remote, input_tiltback_target); //produces output d->remote.inputtilt_interpolated
			d->rt.setpoint += d->tnt_conf.enable_throttle_stability ? 0 : d->remote.inputtilt_interpolated; //Don't apply if we are using the throttle for stability

			//Adjust Setpoint as required
			apply_noseangling(d);

			//Apply Stability
			if (d->tnt_conf.enable_speed_stability || 
			    d->tnt_conf.enable_throttle_stability) {
				apply_stability(d);
			}
			
			// Do PID maths
			d->rt.proportional = d->rt.setpoint - d->rt.pitch_angle;
			d->prop_smooth = d->rt.setpoint - d->pitch_smooth_kalman;
			d->abs_prop_smooth = fabsf(d->prop_smooth);
			
			//Select and Apply Kp
			d->state.braking_pos = sign(d->rt.proportional) != d->motor.erpm_sign;
			bool brake_curve = d->tnt_conf.brake_curve && d->state.braking_pos;
			float kp_mod;
			kp_mod = angle_kp_select(d->abs_prop_smooth, 
				brake_curve ? &d->brake_kp : &d->accel_kp);
			d->debug1 = brake_curve ? -kp_mod : kp_mod;
			kp_mod *= (1 + d->stabl * d->tnt_conf.stabl_pitch_max_scale / 100); //apply dynamic stability
			new_pid_value = kp_mod * d->rt.proportional;
			
			// Start Rate PID and Booster portion a few cycles later, after the start clicks have been emitted
			// this keeps the start smooth and predictable
			if (d->start_counter_clicks == 0) {
				
                		// Select and Apply Rate P
				float rate_prop = -d->gyro[1];
				float kp_rate = brake_curve ? d->brake_kp.kp_rate : d->accel_kp.kp_rate;		
				float rate_stabl = 1+d->stabl*d->tnt_conf.stabl_rate_max_scale/100; 			
				d->pid_mod = kp_rate * rate_prop * rate_stabl;
				d->debug3 = kp_rate * (rate_stabl - 1);				// Calc the contribution of stability to kp_rate
			
				// Select Roll Boost Kp
				float rollkp = 0;
				float erpmscale = 1;
				bool brake_roll = d->roll_brake_kp.count!=0 && d->state.braking_pos;
				rollkp = angle_kp_select(d->abs_roll_angle, 
					brake_roll ? &d->roll_brake_kp : &d->roll_accel_kp);

				//Apply ERPM Scale
				if (brake_roll && d->motor.abs_erpm < 750) { 				
					// If we want to actually stop at low speed reduce kp to 0
					erpmscale = 0;
				} else if (d->roll_accel_kp.count!=0 && d->motor.abs_erpm < d->tnt_conf.rollkp_higherpm) { 
					erpmscale = 1 + min(1,max(0,1-(d->motor.abs_erpm-d->tnt_conf.rollkp_lowerpm)/
						(d->tnt_conf.rollkp_higherpm-d->tnt_conf.rollkp_lowerpm)))*(d->tnt_conf.rollkp_maxscale/100);
				}
				rollkp *= (d->state.sat == SAT_CENTERING) ? 0 : erpmscale;

				//Apply Roll Boost
				d->roll_pid_mod = .99 * d->roll_pid_mod + .01 * rollkp * fabsf(new_pid_value) * d->motor.erpm_sign; //always act in the direciton of travel
				d->pid_mod += d->roll_pid_mod;
				d->debug2 = brake_roll ? -rollkp : rollkp;	

				//Soft Start
				if (d->softstart_pid_limit < d->mc_current_max) {
					d->pid_mod = fminf(fabsf(d->pid_mod), d->softstart_pid_limit) * sign(d->pid_mod);
					d->softstart_pid_limit += d->softstart_ramp_step_size;
				}
				
				new_pid_value += d->pid_mod; // Apply PID modifiers
			} else { d->pid_mod = 0; }
			
			// Current Limiting!
			float current_limit = d->motor.braking ? d->mc_current_min : d->mc_current_max;
			if (fabsf(new_pid_value) > current_limit) {
				new_pid_value = sign(new_pid_value) * current_limit;
			}
			check_current(&d->moto, &d->surge, &d->state, &d->rt,  &d->tnt_conf); // Check for high current conditions
			
			// Modifiers to PID control
			check_drop(&d->drop, &d->rt);
			check_traction(&d->motor, &d->traction, &d->state, &d->rt, &d->tnt_conf, &d->drop, &d->traction_dbg);
			if (d->tnt_conf.is_surge_enabled){
				check_surge(&d->moto, &d->surge, &d->state, &d->rt,  &d->tnt_conf, &d->surge_dbg);
			}
				
			// PID value application
			// d->rt.pid_value = (d->state.wheelslip && d->tnt_conf.is_traction_enabled) ? 0 : new_pid_value;
			if (d->state.wheelslip && d->tnt_conf.is_traction_enabled) { //Reduce acceleration if we are in traction control and enabled
				d->rt.pid_value = 0;
			} else if (d->motor.erpm_sign * (d->rt.pid_value - new_pid_value) > d->pid_brake_increment) { // Brake Amp Rate Limiting
				if (new_pid_value > d->rt.pid_value) {
					d->rt.pid_value += d->pid_brake_increment;
				}
				else {
					d->rt.pid_value -= d->pid_brake_increment;
				}
			}
			else {
				d->rt.pid_value = new_pid_value;
			}

			// Output to motor
			if (d->start_counter_clicks) {
				// Generate alternate pulses to produce distinct "click"
				d->start_counter_clicks--;
				if ((d->start_counter_clicks & 0x1) == 0)
					set_current(d, d->rt.pid_value - d->tnt_conf.startup_click_current);
				else
					set_current(d, d->rt.pid_value + d->tnt_conf.startup_click_current);
			} else if (d->surge.active) { 	
				set_dutycycle(d, d->surge.new_duty_cycle); 		// Set the duty to surge
			} else {
				// modulate haptic buzz onto pid_value unconditionally to allow
				// checking for haptic conditions, and to finish minimum duration haptic effect
				// even after short pulses of hitting the condition(s)
				d->rt.pid_value += haptic_buzz(d, 0.3);
				set_current(d, d->rt.pid_value); 	// Set current as normal.
			}

			break;

		case (STATE_READY):
			if (d->rt.current_time - d->disengage_timer > 1800) {	// alert user after 30 minutes
				if (d->rt.current_time - d->nag_timer > 60) {		// beep every 60 seconds
					d->nag_timer = d->rt.current_time;
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
				d->nag_timer = d->rt.current_time;
				d->idle_voltage = 0;
			}

			if ((d->rt.current_time - d->fault_angle_pitch_timer) > 1) {
				// 1 second after disengaging - set startup tolerance back to normal (aka tighter)
				d->startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance;
			}

			check_odometer(d);

			//Rest Timer
			rest_timer(&d->ridetimer, &d->rt);
			
			// Check for valid startup position and switch state
			if (fabsf(d->rt.pitch_angle) < d->startup_pitch_tolerance &&
				fabsf(d->rt.roll_angle) < d->tnt_conf.startup_roll_tolerance && 
				is_engaged(d)) {
				reset_vars(d);
				break;
			}
			
			// Push-start aka dirty landing Part II
			if(d->tnt_conf.startup_pushstart_enabled && (d->motor.abs_erpm > 1000) && is_engaged(d)) {
				if ((fabsf(d->rt.pitch_angle) < 45) && (fabsf(d->rt.roll_angle) < 45)) {
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

static void read_cfg_from_eeprom(tnt_config *config) {
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
			confparser_set_defaults_tnt_config(config);
			return;
	        }
	}

	if (read_ok) {
		memcpy(config, buffer, sizeof(tnt_config));
	} else {
		confparser_set_defaults_tnt_config(config);
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
        return d->rt.pid_value;
    case (2):
        return d->rt.proportional;
    case (3):
        return d->rt.proportional;
    case (4):
        return d->rt.proportional;
    case (5):
        return d->rt.setpoint;
    case (6):
        return d->rt.proportional;
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
	static const int bufsize = 103;
	uint8_t buffer[bufsize];
	int32_t ind = 0;
	buffer[ind++] = 111;//Magic Number
	buffer[ind++] = COMMAND_GET_RTDATA;
	float corr_factor;

	// Board State
	buffer[ind++] = d->state.wheelslip ? 4 : d->state.state ; // (d->state.state & 0xF) + (d->state.sat << 4);
	buffer[ind++] = d->state.sat; 
	buffer[ind++] = (d->footpad_sensor.state & 0xF) + (d->beep_reason << 4);
	buffer[ind++] = d->state.stop_condition;
	buffer_append_float32_auto(buffer, d->footpad_sensor.adc1, &ind);
	buffer_append_float32_auto(buffer, d->footpad_sensor.adc2, &ind);
	buffer_append_float32_auto(buffer, VESC_IF->mc_get_input_voltage_filtered(), &ind);
	buffer_append_float32_auto(buffer, d->motor.current_avg, &ind); // current atr_filtered_current
	buffer_append_float32_auto(buffer, d->rt.pitch_angle, &ind);
	buffer_append_float32_auto(buffer, d->rt.roll_angle, &ind);

	//Tune Modifiers
	buffer_append_float32_auto(buffer, d->rt.setpoint, &ind);
	buffer_append_float32_auto(buffer, d->remote.inputtilt_interpolated, &ind);
	buffer_append_float32_auto(buffer, d->remote.throttle_val, &ind);
	buffer_append_float32_auto(buffer, d->rt.current_time - d->traction.timeron , &ind); //Temporary debug. Time since last wheelslip
	buffer_append_float32_auto(buffer, d->rt.current_time - d->surge.timer , &ind); //Temporary debug. Time since last surge

	// Trip
	if (d->ridetimer.ride_time > 0) {
		corr_factor =  d->rt.current_time / d->ridetimer.ride_time;
	} else {corr_factor = 1;}
	buffer_append_float32_auto(buffer, d->ridetimer.ride_time, &ind); //Temporary debug. Ride Time
	buffer_append_float32_auto(buffer, d->ridetimer.rest_time, &ind); //Temporary debug. Rest time
	buffer_append_float32_auto(buffer, VESC_IF->mc_stat_speed_avg() * 3.6 * .621 * corr_factor, &ind); //Temporary debug. speed avg convert m/s to mph
	buffer_append_float32_auto(buffer, VESC_IF->mc_stat_current_avg() * corr_factor, &ind); //Temporary debug. current avg
	buffer_append_float32_auto(buffer, VESC_IF->mc_stat_power_avg() * corr_factor, &ind); //Temporary debug. power avg
	buffer_append_float32_auto(buffer, (VESC_IF->mc_get_watt_hours(false) - VESC_IF->mc_get_watt_hours_charged(false)) / (VESC_IF->mc_get_distance_abs() * 0.000621), &ind); //Temporary debug. efficiency
	
	// DEBUG
	if (d->tnt_conf.is_tcdebug_enabled) {
		buffer[ind++] = 1;
		buffer_append_float32_auto(buffer, d->traction_dbg.debug2, &ind); //Temporary debug. wheelslip erpm factor
		buffer_append_float32_auto(buffer, d->traction_dbg.debug6, &ind); //Temporary debug. accel at wheelslip start
		buffer_append_float32_auto(buffer, d->traction_dbg.debug3, &ind); //Temporary debug. erpm before wheel slip
		buffer_append_float32_auto(buffer, d->traction_dbg.debug9, &ind); //Temporary debug. erpm at wheel slip
		buffer_append_float32_auto(buffer, d->traction_dbg.debug4, &ind); //Temporary debug. Debug condition or last accel
		buffer_append_float32_auto(buffer, d->traction_dbg.debug8, &ind); //Temporary debug. accel at wheelslip end
	} else if (d->tnt_conf.is_surgedebug_enabled) {
		buffer[ind++] = 2;
		buffer_append_float32_auto(buffer, d->surge_dbg.debug1, &ind); //surge start proportional
		buffer_append_float32_auto(buffer, d->surge_dbg.debug5, &ind); //surge added duty cycle
		buffer_append_float32_auto(buffer, d->surge_dbg.debug3, &ind); //surge start current threshold
		buffer_append_float32_auto(buffer, d->surge_dbg.debug6, &ind); //surge end 
		buffer_append_float32_auto(buffer, d->surge_dbg.debug7, &ind); //Duration last surge cycle time
		buffer_append_float32_auto(buffer, d->surge_dbg.debug2, &ind); //start current value
		buffer_append_float32_auto(buffer, d->surge_dbg.debug8, &ind); //ramp rate
	} else if (d->tnt_conf.is_tunedebug_enabled) {
		buffer[ind++] = 3;
		buffer_append_float32_auto(buffer, d->pitch_smooth_kalman, &ind); //smooth pitch	
		buffer_append_float32_auto(buffer, d->debug1, &ind); // scaled angle P
		buffer_append_float32_auto(buffer, d->debug1*d->stabl*d->tnt_conf.stabl_pitch_max_scale/100, &ind); // added stiffnes pitch kp
		buffer_append_float32_auto(buffer, d->debug3, &ind); // added stability rate P
		buffer_append_float32_auto(buffer, d->stabl, &ind);
		buffer_append_float32_auto(buffer, d->debug2, &ind); //rollkp
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

	return VESC_IF->lbm_enc_float(app_get_debug(VESC_IF->lbm_dec_as_i32(args[0])));
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
		confparser_set_defaults_tnt_config(cfg);
	} else {
		cfg = &d->tnt_conf;
	}

	int res = confparser_serialize_tnt_config(buffer, cfg);

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
	
	bool res = confparser_deserialize_tnt_config(buffer, &d->tnt_conf);
	
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
	VESC_IF->printf("Init TNT v%.1fd\n", (double)APPCONF_TNT_VERSION);
	
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
