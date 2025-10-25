/*
    Copyright 2019 - 2022 Mitch Lustig
	Copyright 2022 Benjamin Vedder	benjamin@vedder.se

	This file is part of the VESC firmware.

	The VESC firmware is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    The VESC firmware is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "vesc_c_if.h"

#include "footpad_sensor.h"

#include "conf/datatypes.h"
#include "conf/confparser.h"
#include "conf/confxml.h"
#include "conf/buffer.h"
#include "conf/conf_default.h"
#include "./led.h"

#include "konami.h"

#include <math.h>
#include <string.h>

// Acceleration average
#define ACCEL_ARRAY_SIZE 40

HEADER

// Return the sign of the argument. -1.0 if negative, 1.0 if zero or positive.
#define SIGN(x)				(((x) < 0.0) ? -1.0 : 1.0)

#define DEG2RAD_f(deg)		((deg) * (float)(M_PI / 180.0))
#define RAD2DEG_f(rad) 		((rad) * (float)(180.0 / M_PI))

#define UNUSED(x) (void)(x)

// Data type
typedef enum {
	STARTUP = 0,
	RUNNING = 1,
	RUNNING_TILTBACK = 2,
	RUNNING_WHEELSLIP = 3,
	RUNNING_UPSIDEDOWN = 4,
	RUNNING_FLYWHEEL = 5,   // we remain in "RUNNING" state in flywheel mode,
	                        // but then report "RUNNING_FLYWHEEL" in rt data
	FAULT_ANGLE_PITCH = 6,	// skipped 5 for compatibility
	FAULT_ANGLE_ROLL = 7,
	FAULT_SWITCH_HALF = 8,
	FAULT_SWITCH_FULL = 9,
	FAULT_DUTY = 10, 		// unused but kept for compatibility
	FAULT_STARTUP = 11,
	FAULT_REVERSE = 12,
	FAULT_QUICKSTOP = 13,
	CHARGING = 14,
	DISABLED = 15
} FloatState;

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

typedef enum {
	CENTERING = 0,
	REVERSESTOP,
	TILTBACK_NONE,
	TILTBACK_DUTY,
	TILTBACK_HV,
	TILTBACK_LV,
	TILTBACK_TEMP
} SetpointAdjustmentType;

typedef struct{
	float a0, a1, a2, b1, b2;
	float z1, z2;
} Biquad;

typedef enum {
	BQ_LOWPASS,
	BQ_HIGHPASS
} BiquadType;

typedef enum {
	NO_LIGHTS = 0,
	INTERNAL = 1,
	EXTERNAL_MODULE = 2
} LightingType;

static const FootpadSensorState flywheel_konami_sequence[] = { FS_LEFT, FS_NONE, FS_RIGHT, FS_NONE, FS_LEFT, FS_NONE, FS_RIGHT };
static const FootpadSensorState battery_konami_sequence[] = { FS_LEFT, FS_NONE, FS_LEFT, FS_NONE, FS_LEFT, FS_NONE, FS_LEFT };

#define MAXLCMNAMELENGTH 20
#define MAXLCMPAYLOADLENGTH 64

typedef struct {
    uint8_t data[MAXLCMPAYLOADLENGTH];
    uint8_t size;
} lcmPayload;

// This is all persistent state of the application, which will be allocated in init. It
// is put here because variables can only be read-only when this program is loaded
// in flash without virtual memory in RAM (as all RAM already is dedicated to the
// main firmware and managed from there). This is probably the main limitation of
// loading applications in runtime, but it is not too bad to work around.
typedef struct {
	lib_thread thread; // Balance Thread

	float_config float_conf;

	// Firmware version, passed in from Lisp
	int fw_version_major, fw_version_minor, fw_version_beta;
	uint8_t battery_level;

	// Beeper
	int beep_num_left;
	int beep_duration;
	int beep_countdown;
	int beep_reason;
	bool beeper_enabled;

	// LEDs
	LEDData led_data;

	// External Lights (LCM)
	char lcm_name[MAXLCMNAMELENGTH];
	lcmPayload lcm_payload;

	float charge_voltage, charge_current;
	float charge_timer;
	
	// Config values
	float loop_time_seconds;
	unsigned int start_counter_clicks, start_counter_clicks_max;
	float startup_pitch_trickmargin, startup_pitch_tolerance;
	float startup_step_size;
	float tiltback_duty_step_size, tiltback_hv_step_size, tiltback_lv_step_size, tiltback_return_step_size;
	float torquetilt_on_step_size, torquetilt_off_step_size, turntilt_step_size;
	float tiltback_variable, tiltback_variable_max_erpm, noseangling_step_size, inputtilt_ramped_step_size, inputtilt_step_size;
	float mc_max_temp_fet, mc_max_temp_mot;
	float mc_current_max, mc_current_min, current_max, current_min, max_continuous_current;
	float surge_angle, surge_angle2, surge_angle3, surge_adder;
	float ki; // config ki scaled taking account the loop frequency.
	bool overcurrent;
	bool surge_enable;
	bool current_beeping;
	bool duty_beeping;

	// Feature: True Pitch
	ATTITUDE_INFO m_att_ref;

	// Runtime values read from elsewhere
	float pitch_angle, last_pitch_angle, roll_angle, abs_roll_angle, abs_roll_angle_sin, last_gyro_y;
 	float true_pitch_angle;
	float gyro[3];
	float duty_cycle, abs_duty_cycle, duty_smooth;
	float erpm, abs_erpm, avg_erpm;
	float motor_current;
	float throttle_val;
	float max_duty_with_margin;
	FootpadSensor footpad_sensor;

	// Feature: ATR (Adaptive Torque Response)
	float atr_on_step_size, atr_off_step_size;
	float atr_speed_boost_multiplier;
	float acceleration, last_erpm;
	float accel_gap;
	float accelhist[ACCEL_ARRAY_SIZE];
	float accelavg;
	int accelidx;
	int direction_counter;
	bool braking;

	// Feature: Turntilt
	float last_yaw_angle, yaw_angle, abs_yaw_change, last_yaw_change, yaw_change, yaw_aggregate;
	float turntilt_boost_per_erpm, yaw_aggregate_target;

	// Rumtime state values
	FloatState state;
	float proportional;
	float pid_prop, pid_integral, pid_rate, pid_mod;
	float last_proportional, abs_proportional;
	float pid_value;
	float setpoint, setpoint_target, setpoint_target_interpolated;
	float applied_booster_current;
	float applied_haptic_current, haptic_timer;
	int haptic_counter, haptic_mode;
	HAPTIC_BUZZ_TYPE haptic_type;
	bool haptic_tone_in_progress;
	float noseangling_interpolated, inputtilt_interpolated;
	float filtered_current;
	float torquetilt_target, torquetilt_interpolated;
	float atr_filtered_current, atr_target, atr_interpolated;
	float torqueresponse_interpolated;
	Biquad atr_current_biquad;
	float braketilt_factor, braketilt_target, braketilt_interpolated;
	float turntilt_target, turntilt_interpolated;
	SetpointAdjustmentType setpointAdjustmentType;
	float current_time, last_time, diff_time, loop_overshoot; // Seconds
	float disengage_timer, nag_timer; // Seconds
	float idle_voltage;
	float filtered_loop_overshoot, loop_overshoot_alpha, filtered_diff_time;
	float fault_angle_pitch_timer, fault_angle_roll_timer, fault_switch_timer, fault_switch_half_timer; // Seconds
	float motor_timeout_seconds;
	float brake_timeout; // Seconds
	float wheelslip_timer, wheelslip_end_timer, overcurrent_timer, tb_highvoltage_timer;
	float switch_warn_beep_erpm;
	float quickstop_erpm;
	bool traction_control;

	// PID Brake Scaling
	float kp_brake_scale; // Used for brakes when riding forwards, and accel when riding backwards
	float kp2_brake_scale;
	float kp_accel_scale; // Used for accel when riding forwards, and brakes when riding backwards
	float kp2_accel_scale;

	// Darkride aka upside down mode:
	bool is_upside_down;			// the board is upside down
	bool is_upside_down_started;	// dark ride has been engaged
	bool enable_upside_down;		// dark ride mode is enabled (10 seconds after fault)
	float delay_upside_down_fault;
	float darkride_setpoint_correction;

	// Feature: Flywheel
	bool is_flywheel_mode, flywheel_abort, flywheel_allow_abort;
	float flywheel_pitch_offset, flywheel_roll_offset;

	// Feature: Handtest
	bool do_handtest;

	// Feature: Reverse Stop
	float reverse_stop_step_size, reverse_tolerance, reverse_total_erpm;
	float reverse_timer;

	// Feature: Soft Start
	float softstart_pid_limit, softstart_ramp_step_size;

	// Brake Amp Rate Limiting:
	float pid_brake_increment;

	// Odometer
	float odo_timer;
	int odometer_dirty;
	uint64_t odometer;

	// Feature: RC Move (control via app while idle)
	int rc_steps;
	int rc_counter;
	float rc_current_target;
	float rc_current;

	// Log values
	float float_setpoint, float_atr, float_braketilt, float_torquetilt, float_turntilt, float_inputtilt;
	float float_expected_acc, float_measured_acc, float_acc_diff;

	// Debug values
	int debug_render_1, debug_render_2;
	int debug_sample_field, debug_sample_count, debug_sample_index;
	int debug_experiment_1, debug_experiment_2, debug_experiment_3, debug_experiment_4, debug_experiment_5, debug_experiment_6;

	Konami flywheel_konami;
	Konami battery_konami;
} data;

static void brake(data *d);
static void set_current(data *d, float current);
static void flywheel_stop(data *d);
static void cmd_flywheel_toggle(data *d, unsigned char *cfg, int len);

/**
 * BUZZER / BEEPER on Servo Pin
 */
const VESC_PIN beeper_pin = VESC_PIN_PPM;

#define EXT_BEEPER_ON()  VESC_IF->io_write(beeper_pin, 1)
#define EXT_BEEPER_OFF() VESC_IF->io_write(beeper_pin, 0)

void beeper_init()
{
	VESC_IF->io_set_mode(beeper_pin, VESC_PIN_MODE_OUTPUT);
}

void beeper_update(data *d)
{
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

void beeper_enable(data *d, bool enable)
{
	d->beeper_enabled = enable;
	if (!enable) {
		EXT_BEEPER_OFF();
	}
}

void beep_alert(data *d, int num_beeps, bool longbeep)
{
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

// Utility Functions
static float biquad_process(Biquad *biquad, float in) {
    float out = in * biquad->a0 + biquad->z1;
    biquad->z1 = in * biquad->a1 + biquad->z2 - biquad->b1 * out;
    biquad->z2 = in * biquad->a2 - biquad->b2 * out;
    return out;
}

static void biquad_config(Biquad *biquad, BiquadType type, float Fc) {
	float K = tanf(M_PI * Fc);	// -0.0159;
	float Q = 0.707; // maximum sharpness (0.5 = maximum smoothness)
	float norm = 1 / (1 + K / Q + K * K);
	if (type == BQ_LOWPASS) {
		biquad->a0 = K * K * norm;
		biquad->a1 = 2 * biquad->a0;
		biquad->a2 = biquad->a0;
	}
	else if (type == BQ_HIGHPASS) {
		biquad->a0 = 1 * norm;
		biquad->a1 = -2 * biquad->a0;
		biquad->a2 = biquad->a0;
	}
	biquad->b1 = 2 * (K * K - 1) * norm;
	biquad->b2 = (1 - K / Q + K * K) * norm;
}

static void biquad_reset(Biquad *biquad) {
	biquad->z1 = 0;
	biquad->z2 = 0;
}

// First start only, set initial state
static void app_init(data *d) {
	if (d->state != DISABLED) {
		d->state = STARTUP;
	}
	d->beeper_enabled = true;
	
	// Allow saving of odometer
	d->odometer_dirty = 0;
	d->odometer = VESC_IF->mc_get_odometer();
}

static float normalized_to_iteration_ki(float normalized_ki, int loop_freq_hz) {
	 // Default frequency of Float thread used to be 832 Hz so we retain that scale.
	return normalized_ki * (832.0 / loop_freq_hz);
}

static void configure(data *d) {
	d->debug_render_1 = 2;
	d->debug_render_2 = 4;

	// This timer is used to determine how long the board has been disengaged / idle
	// subtract 1 second to prevent the haptic buzz disengage click on "write config"
	d->disengage_timer = d->current_time - 1;

	// Set calculated values from config
	d->loop_time_seconds = 1.0 / d->float_conf.hertz;

	d->motor_timeout_seconds = d->loop_time_seconds * 20; // Times 20 for a nice long grace period

	d->startup_step_size = d->float_conf.startup_speed / d->float_conf.hertz;
	d->tiltback_duty_step_size = d->float_conf.tiltback_duty_speed / d->float_conf.hertz;
	d->tiltback_hv_step_size = d->float_conf.tiltback_hv_speed / d->float_conf.hertz;
	d->tiltback_lv_step_size = d->float_conf.tiltback_lv_speed / d->float_conf.hertz;
	d->tiltback_return_step_size = d->float_conf.tiltback_return_speed / d->float_conf.hertz;
	d->torquetilt_on_step_size = d->float_conf.torquetilt_on_speed / d->float_conf.hertz;
	d->torquetilt_off_step_size = d->float_conf.torquetilt_off_speed / d->float_conf.hertz;
	d->atr_on_step_size = d->float_conf.atr_on_speed / d->float_conf.hertz;
	d->atr_off_step_size = d->float_conf.atr_off_speed / d->float_conf.hertz;
	d->turntilt_step_size = d->float_conf.turntilt_speed / d->float_conf.hertz;
	d->noseangling_step_size = d->float_conf.noseangling_speed / d->float_conf.hertz;
	d->inputtilt_step_size = d->float_conf.inputtilt_speed / d->float_conf.hertz;
	d->ki = normalized_to_iteration_ki(d->float_conf.ki, d->float_conf.hertz);

	d->surge_angle = d->float_conf.surge_angle;
	d->surge_angle2 = d->float_conf.surge_angle * 2;
	d->surge_angle3 = d->float_conf.surge_angle * 3;
	d->surge_enable = d->surge_angle > 0;

	// Feature: Stealthy start vs normal start (noticeable click when engaging) - 0-20A
	d->start_counter_clicks_max = 3;
	// Feature: Soft Start
	d->softstart_ramp_step_size = (float)100 / d->float_conf.hertz;
	// Feature: Dirty Landings
	d->startup_pitch_trickmargin = d->float_conf.startup_dirtylandings_enabled ? 10 : 0;

	// Overwrite App CFG Mahony KP to Float CFG Value
	if (VESC_IF->get_cfg_float(CFG_PARAM_IMU_mahony_kp) != d->float_conf.mahony_kp) {
		VESC_IF->set_cfg_float(CFG_PARAM_IMU_mahony_kp, d->float_conf.mahony_kp);
	}

	d->mc_max_temp_fet = VESC_IF->get_cfg_float(CFG_PARAM_l_temp_fet_start) - 3;
	d->mc_max_temp_mot = VESC_IF->get_cfg_float(CFG_PARAM_l_temp_motor_start) - 3;

	// Current limiting
	d->mc_current_max = VESC_IF->get_cfg_float(CFG_PARAM_l_current_max);
	d->current_max = fminf(d->mc_current_max, d->float_conf.limit_current_accel);
	d->mc_current_min = fabsf(VESC_IF->get_cfg_float(CFG_PARAM_l_current_min));
	d->current_min = fminf(d->mc_current_min, fabsf(d->float_conf.limit_current_brake));
	d->max_continuous_current = d->float_conf.limit_current_cont;

	// Maximum amps change when braking
	d->pid_brake_increment = 5;
	if (d->pid_brake_increment < 0.1) {
		d->pid_brake_increment = 5;
	}

	d->max_duty_with_margin = VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty) - 0.1;

	/* WIP /////////////////////////////

	// INSERT ASYMMETRICAL BOOSTER INIT's

	///////////////////////////// WIP */
	
	// Feature: Reverse Stop
	d->reverse_tolerance = 50000;
	d->reverse_stop_step_size = 100.0 / d->float_conf.hertz;

	// Init Filters
	float loop_time_filter = 3.0; // Originally Parameter, now hard-coded to 3Hz
	d->loop_overshoot_alpha = 2.0 * M_PI * ((float)1.0 / (float)d->float_conf.hertz) *
				loop_time_filter / (2.0 * M_PI * (1.0 / (float)d->float_conf.hertz) *
						loop_time_filter + 1.0);

	if (d->float_conf.atr_filter > 0) { // ATR Current Biquad
		float Fc = d->float_conf.atr_filter / d->float_conf.hertz;
		biquad_config(&d->atr_current_biquad, BQ_LOWPASS, Fc);
	}

	// Feature: ATR:
	d->float_acc_diff = 0;
	d->atr_speed_boost_multiplier = 1.0 / 3000.0;  // used to be hard coded to 3000, still is for speed_boost <= 40%
	if (fabsf(d->float_conf.atr_speed_boost) > 0.4) {
		// above 0.4 we add 500erpm for each extra 10% of speed boost, so at most +6000 for 100% speed boost
		// we're producing a multiplier here to avoid unnecessary floating point division in the main loop
		d->atr_speed_boost_multiplier = 1 / ((fabsf(d->float_conf.atr_speed_boost) - 0.4) * 5000 + 3000);
	}

	/* INSERT OG TT LOGIC? */

	// Feature: Braketilt
	if (d->float_conf.braketilt_strength == 0) {
		d->braketilt_factor = 0;
	} else {
		// incorporate negative sign into braketilt factor instead of adding it each balance loop
		d->braketilt_factor = -(0.5 + (20 - d->float_conf.braketilt_strength)/ 5.0);
	}

	// Feature: Turntilt
	d->yaw_aggregate_target = fmaxf(50, d->float_conf.turntilt_yaw_aggregate);
	d->turntilt_boost_per_erpm = (float)d->float_conf.turntilt_erpm_boost / 100.0 / (float)d->float_conf.turntilt_erpm_boost_end;

	// Feature: Darkride
	d->enable_upside_down = false;
	d->is_upside_down = false;
	d->darkride_setpoint_correction = d->float_conf.dark_pitch_offset;

	// Feature: Flywheel
	d->is_flywheel_mode = false;
	d->flywheel_abort = false;
	d->flywheel_allow_abort = false;

	// Allows smoothing of Remote Tilt
	d->inputtilt_ramped_step_size = 0;

	// Speed above which to warn users about an impending full switch fault
	d->switch_warn_beep_erpm = d->float_conf.is_footbeep_enabled ? 2000 : 100000;

	// Speed below which we check for quickstop conditions
	d->quickstop_erpm = 200;

	// Variable nose angle adjustment / tiltback (setting is per 1000erpm, convert to per erpm)
	d->tiltback_variable = d->float_conf.tiltback_variable / 1000;
	if ((d->float_conf.tiltback_variable < 0) || (d->float_conf.tiltback_variable_max < 0)) {
		// we now allow negative rate or negative max (or both), it all is treated as negative tilt
		// runtime logic expects positive rate but negative max for negative tilt:
		if (d->tiltback_variable < 0)
			d->tiltback_variable *= -1;
		if (d->float_conf.tiltback_variable_max > 0)
			d->float_conf.tiltback_variable_max *= -1;
	}
	if (d->tiltback_variable == 0) {
		d->tiltback_variable_max_erpm = 100000;
	} else {
		d->tiltback_variable_max_erpm = fabsf(d->float_conf.tiltback_variable_max / d->tiltback_variable);
	}

	// Reset loop time variables
	d->last_time = 0.0;
	d->filtered_loop_overshoot = 0.0;

	d->beeper_enabled = d->float_conf.is_beeper_enabled;
	if (d->float_conf.float_disable) {
		d->state = DISABLED;
		beep_alert(d, 3, false);
	}
	else {
		d->state = STARTUP;
		beep_alert(d, 1, false);
	}

	d->do_handtest = false;

	konami_init(&d->flywheel_konami, flywheel_konami_sequence, sizeof(flywheel_konami_sequence));
	konami_init(&d->battery_konami, battery_konami_sequence, sizeof(battery_konami_sequence));

	// External light module support
	d->lcm_name[0] = '\0';
	d->lcm_payload.size = 0;
}

static void reset_vars(data *d) {
	// Clear accumulated values.
	d->last_proportional = 0;
	// Set values for startup
	d->setpoint = d->pitch_angle;
	d->setpoint_target_interpolated = d->pitch_angle;
	d->setpoint_target = 0;
	d->applied_booster_current = 0;
	d->noseangling_interpolated = 0;
	d->inputtilt_interpolated = 0;
	d->torquetilt_target = 0;
	d->torquetilt_interpolated = 0;
	d->atr_target = 0;
	d->atr_interpolated = 0;
	d->atr_filtered_current = 0;
	biquad_reset(&d->atr_current_biquad);
	d->braketilt_target = 0;
	d->braketilt_interpolated = 0;
	d->torqueresponse_interpolated = 0;
	d->turntilt_target = 0;
	d->turntilt_interpolated = 0;
	d->setpointAdjustmentType = CENTERING;
	d->state = RUNNING;
	d->current_time = 0;
	d->last_time = 0;
	d->diff_time = 0;
	d->brake_timeout = 0;
	d->traction_control = false;
	d->pid_value = 0;
	d->pid_mod = 0;
	d->pid_prop = 0;
	d->pid_integral = 0;
	d->softstart_pid_limit = 0;
	d->startup_pitch_tolerance = d->float_conf.startup_pitch_tolerance;
	d->surge_adder = 0;
	d->overcurrent = false;

	// PID Brake Scaling
	d->kp_brake_scale = 1.0;
	d->kp2_brake_scale = 1.0;
	d->kp_accel_scale = 1.0;
	d->kp2_accel_scale = 1.0;

	// ATR:
	d->accel_gap = 0;
	d->direction_counter = 0;

	for (int i = 0; i < 40; i++)
		d->accelhist[i] = 0;
	d->accelidx = 0;
	d->accelavg = 0;

	// Turntilt:
	d->last_yaw_angle = 0;
	d->yaw_aggregate = 0;

	// Feature: click on start
	d->start_counter_clicks = d->start_counter_clicks_max;

	// RC Move:
	d->rc_steps = 0;
	d->rc_current = 0;

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

/**
 *  do_rc_move: perform motor movement while board is idle
 */
static void do_rc_move(data *d)
{
	if (d->rc_steps > 0) {
		d->rc_current = d->rc_current * 0.95 + d->rc_current_target * 0.05;
		if (d->abs_erpm > 800)
			d->rc_current = 0;
		set_current(d, d->rc_current);
		d->rc_steps--;
		d->rc_counter++;
		if ((d->rc_counter == 500) && (d->rc_current_target > 2)) {
			d->rc_current_target /= 2;
		}
	}
	else {
		d->rc_counter = 0;
		
		if ((d->float_conf.remote_throttle_current_max > 0) && (d->current_time - d->disengage_timer > d->float_conf.remote_throttle_grace_period) && (fabsf(d->throttle_val) > 0.02)) { // Throttle must be greater than 2% (Help mitigate lingering throttle)
			float servo_val = d->throttle_val;
			servo_val *= (d->float_conf.inputtilt_invert_throttle ? -1.0 : 1.0);
			d->rc_current = d->rc_current * 0.95 + (d->float_conf.remote_throttle_current_max * servo_val) * 0.05;
			set_current(d, d->rc_current);
		}
		else {
			d->rc_current = 0;
			// Disable output
			brake(d);
		}
	}
}

static float get_setpoint_adjustment_step_size(data *d) {
	switch(d->setpointAdjustmentType){
		case (CENTERING):
			return d->startup_step_size;
		case (TILTBACK_DUTY):
			return d->tiltback_duty_step_size;
		case (TILTBACK_HV):
		case (TILTBACK_TEMP):
			return d->tiltback_hv_step_size;
		case (TILTBACK_LV):
			return d->tiltback_lv_step_size;
		case (TILTBACK_NONE):
			return d->tiltback_return_step_size;
		case (REVERSESTOP):
			return d->reverse_stop_step_size;
		default:
			;
	}
	return 0;
}

bool is_engaged(const data *d) {
	if (d->footpad_sensor.state == FS_BOTH) {
		return true;
	}

	if (d->footpad_sensor.state == FS_LEFT || d->footpad_sensor.state == FS_RIGHT) {
		// 5 seconds after stopping we allow starting with a single sensor (e.g. for jump starts)
		bool is_simple_start = d->float_conf.startup_simplestart_enabled &&
			(d->current_time - d->disengage_timer > 5);

		if (d->float_conf.fault_is_dual_switch || is_simple_start) {
			return true;
		}
	}

	// Keep the board engaged in flywheel mode
	if (d->is_flywheel_mode) {
		return true;
	}

	return false;
}

// Fault checking order does not really matter. From a UX perspective, switch should be before angle.
static bool check_faults(data *d){
	// Aggressive reverse stop in case the board runs off when upside down
	if (d->is_upside_down) {
		if (d->erpm > 1000) {
			// erpms are also reversed when upside down!
			if (((d->current_time - d->fault_switch_timer) * 1000 > 100) ||
				(d->erpm > 2000) ||
				((d->state == RUNNING_WHEELSLIP) && (d->current_time - d->delay_upside_down_fault > 1) &&
				 ((d->current_time - d->fault_switch_timer) * 1000 > 30)) ) {
				
				// Trigger FAULT_REVERSE when board is going reverse AND
				// going > 2mph for more than 100ms
				// going > 4mph
				// detecting wheelslip (aka excorcist wiggle) after the first second
				d->state = FAULT_REVERSE;
				return true;
			}
		}
		else {
			d->fault_switch_timer = d->current_time;
			if (d->erpm > 300) {
				// erpms are also reversed when upside down!
				if ((d->current_time - d->fault_angle_roll_timer) * 1000 > 500){
					d->state = FAULT_REVERSE;
					return true;
				}
			}
			else {
				d->fault_angle_roll_timer = d->current_time;
			}
		}
		if (is_engaged(d)) {
			// allow turning it off by engaging foot sensors
			d->state = FAULT_SWITCH_HALF;
			return true;
		}
	}
	else {
		bool disable_switch_faults = d->float_conf.fault_moving_fault_disabled &&
									 d->erpm > (d->float_conf.fault_adc_half_erpm * 2) && // Rolling forward (not backwards!)
									 fabsf(d->roll_angle) < 40; // Not tipped over

		// Check switch
		// Switch fully open
		if (d->footpad_sensor.state == FS_NONE && !d->is_flywheel_mode) {
			if (!disable_switch_faults) {
				if((1000.0 * (d->current_time - d->fault_switch_timer)) > d->float_conf.fault_delay_switch_full){
					d->state = FAULT_SWITCH_FULL;
					return true;
				}
				// low speed (below 6 x half-fault threshold speed):
				else if ((d->abs_erpm < d->float_conf.fault_adc_half_erpm * 6)
					&& (1000.0 * (d->current_time - d->fault_switch_timer) > d->float_conf.fault_delay_switch_half)){
					d->state = FAULT_SWITCH_FULL;
					return true;
				}
			}
			
			if ((d->abs_erpm < d->quickstop_erpm) && (fabsf(d->true_pitch_angle) > 14) && (fabsf(d->inputtilt_interpolated) < 30) && (SIGN(d->true_pitch_angle) == SIGN(d->erpm))) {
				// QUICK STOP
				d->state = FAULT_QUICKSTOP;
				return true;
			}
		} else {
			d->fault_switch_timer = d->current_time;
		}

		// Feature: Reverse-Stop
		if(d->setpointAdjustmentType == REVERSESTOP){
			//  Taking your foot off entirely while reversing? Ignore delays
			if (d->footpad_sensor.state == FS_NONE) {
				d->state = FAULT_SWITCH_FULL;
				return true;
			}
			if (fabsf(d->true_pitch_angle) > 15) {
				d->state = FAULT_REVERSE;
				return true;
			}
			// Above 10 degrees for a half a second? Switch it off
			if ((fabsf(d->true_pitch_angle) > 10) && (d->current_time - d->reverse_timer > .5)) {
				d->state = FAULT_REVERSE;
				return true;
			}
			// Above 5 degrees for a full second? Switch it off
			if ((fabsf(d->true_pitch_angle) > 5) && (d->current_time - d->reverse_timer > 1)) {
				d->state = FAULT_REVERSE;
				return true;
			}
			if (d->reverse_total_erpm > d->reverse_tolerance * 3) {
				d->state = FAULT_REVERSE;
				return true;
			}
			if (fabsf(d->true_pitch_angle) < 5) {
				d->reverse_timer = d->current_time;
			}
		}

		// Switch partially open and stopped
		if(!d->float_conf.fault_is_dual_switch) {
			if(!is_engaged(d) && d->abs_erpm < d->float_conf.fault_adc_half_erpm){
				if ((1000.0 * (d->current_time - d->fault_switch_half_timer)) > d->float_conf.fault_delay_switch_half){
					d->state = FAULT_SWITCH_HALF;
					return true;
				}
			} else {
				d->fault_switch_half_timer = d->current_time;
			}
		}

		// Check roll angle
		if (fabsf(d->roll_angle) > d->float_conf.fault_roll) {
			if ((1000.0 * (d->current_time - d->fault_angle_roll_timer)) > d->float_conf.fault_delay_roll) {
				d->state = FAULT_ANGLE_ROLL;
				return true;
			}
		} else {
			d->fault_angle_roll_timer = d->current_time;

			if (d->float_conf.fault_darkride_enabled) {
				if((fabsf(d->roll_angle) > 100) && (fabsf(d->roll_angle) < 135)) {
					d->state = FAULT_ANGLE_ROLL;
					return true;
				}
			}
		}

		if (d->is_flywheel_mode && d->flywheel_allow_abort) {
			FootpadSensorState state = footpad_sensor_state_evaluate(&d->footpad_sensor, &d->float_conf, true);
			if (state == FS_BOTH) {
				d->state = FAULT_SWITCH_HALF;
				d->flywheel_abort = true;
				return true;
			}
		}
	}

	// Check pitch angle
	if ((fabsf(d->true_pitch_angle) > d->float_conf.fault_pitch) && (fabsf(d->inputtilt_interpolated) < 30)) {
		if ((1000.0 * (d->current_time - d->fault_angle_pitch_timer)) > d->float_conf.fault_delay_pitch) {
			d->state = FAULT_ANGLE_PITCH;
			return true;
		}
	} else {
		d->fault_angle_pitch_timer = d->current_time;
	}

	// *Removed Duty Cycle Fault*

	return false;
}

static void calculate_setpoint_target(data *d) {
	float input_voltage = VESC_IF->mc_get_input_voltage_filtered();

	if (input_voltage < d->float_conf.tiltback_hv) {
		d->tb_highvoltage_timer = d->current_time;
	}

	if (d->setpointAdjustmentType == CENTERING && d->setpoint_target_interpolated != d->setpoint_target) {
		// Ignore tiltback during centering sequence
		d->state = RUNNING;
	} else if (d->setpointAdjustmentType == REVERSESTOP) {
		// accumalete erpms:
		d->reverse_total_erpm += d->erpm;
		if (fabsf(d->reverse_total_erpm) > d->reverse_tolerance) {
			// tilt down by 10 degrees after 50k aggregate erpm
			d->setpoint_target = 10 * (fabsf(d->reverse_total_erpm) - d->reverse_tolerance) / 50000;
		}
		else {
			if (fabsf(d->reverse_total_erpm) <= d->reverse_tolerance / 2) {
				if (d->erpm >= 0){
					d->setpointAdjustmentType = TILTBACK_NONE;
					d->reverse_total_erpm = 0;
					d->setpoint_target = 0;
					d->pid_integral = 0;
				}
			}
		}
	} else if ((fabsf(d->acceleration) > 15) &&					// this isn't normal, either wheelslip or wheel getting stuck
			  (SIGN(d->acceleration) == SIGN(d->erpm)) &&		// we only act on wheelslip, not when the wheel gets stuck
			  (d->abs_duty_cycle > 0.3) &&
			  (d->abs_erpm > 2000))								// acceleration can jump a lot at very low speeds
	{
		d->state = RUNNING_WHEELSLIP;
		d->setpointAdjustmentType = TILTBACK_NONE;
		d->wheelslip_timer = d->current_time;
		if (d->is_upside_down) {
			d->traction_control = true;
		}
	} else if (d->state == RUNNING_WHEELSLIP) {
		if (fabsf(d->acceleration) < 10) {
			// acceleration is slowing down, traction control seems to have worked
			d->traction_control = false;
		}
		// Remain in wheelslip state for at least 500ms to avoid any overreactions
		if (d->abs_duty_cycle > d->max_duty_with_margin) {
			d->wheelslip_timer = d->current_time;
		}
		else if (d->current_time - d->wheelslip_timer > 0.2) {
			if (d->abs_duty_cycle < 0.7) {
				// Leave wheelslip state only if duty < 70%
				d->traction_control = false;
				d->state = RUNNING;
			}
		}
		if (d->float_conf.fault_reversestop_enabled && (d->erpm < 0)) {
			// the 500ms wheelslip time can cause us to blow past the reverse stop condition!
			d->setpointAdjustmentType = REVERSESTOP;
			d->reverse_timer = d->current_time;
			d->reverse_total_erpm = 0;
		}
	} else if (d->abs_duty_cycle > d->float_conf.tiltback_duty) {
		if (d->erpm > 0) {
			d->setpoint_target = d->float_conf.tiltback_duty_angle;
		} else {
			d->setpoint_target = -d->float_conf.tiltback_duty_angle;
		}
		d->setpointAdjustmentType = TILTBACK_DUTY;
		d->state = RUNNING_TILTBACK;
	} else if (d->abs_duty_cycle > 0.05 && input_voltage > d->float_conf.tiltback_hv) {
		d->beep_reason = BEEP_HV;
		beep_alert(d, 3, false);	// Triple-beep
		if (((d->current_time - d->tb_highvoltage_timer) > .5) ||
		   (input_voltage > d->float_conf.tiltback_hv + 1)) {
			// 500ms have passed or voltage is another volt higher, time for some tiltback
			if (d->erpm > 0){
				d->setpoint_target = d->float_conf.tiltback_hv_angle;
			} else {
				d->setpoint_target = -d->float_conf.tiltback_hv_angle;
			}

			d->setpointAdjustmentType = TILTBACK_HV;
			d->state = RUNNING_TILTBACK;
		}
		else {
			// The rider has 500ms to react to the triple-beep, or maybe it was just a short spike
			d->setpointAdjustmentType = TILTBACK_NONE;
			d->state = RUNNING;
		}
	} else if(VESC_IF->mc_temp_fet_filtered() > d->mc_max_temp_fet){
		// Use the angle from Low-Voltage tiltback, but slower speed from High-Voltage tiltback
		beep_alert(d, 3, true);	// Triple-beep (long beeps)
		d->beep_reason = BEEP_TEMPFET;
		if(VESC_IF->mc_temp_fet_filtered() > (d->mc_max_temp_fet + 1)) {
			if(d->erpm > 0){
				d->setpoint_target = d->float_conf.tiltback_lv_angle;
			} else {
				d->setpoint_target = -d->float_conf.tiltback_lv_angle;
			}
			d->setpointAdjustmentType = TILTBACK_TEMP;
			d->state = RUNNING_TILTBACK;
		}
		else {
			// The rider has 1 degree Celsius left before we start tilting back
			d->setpointAdjustmentType = TILTBACK_NONE;
			d->state = RUNNING;
		}
	} else if(VESC_IF->mc_temp_motor_filtered() > d->mc_max_temp_mot){
		// Use the angle from Low-Voltage tiltback, but slower speed from High-Voltage tiltback
		beep_alert(d, 3, true);	// Triple-beep (long beeps)
		d->beep_reason = BEEP_TEMPMOT;
		if(VESC_IF->mc_temp_motor_filtered() > (d->mc_max_temp_mot + 1)) {
			if(d->erpm > 0){
				d->setpoint_target = d->float_conf.tiltback_lv_angle;
			} else {
				d->setpoint_target = -d->float_conf.tiltback_lv_angle;
			}
			d->setpointAdjustmentType = TILTBACK_TEMP;
			d->state = RUNNING_TILTBACK;
		}
		else {
			// The rider has 1 degree Celsius left before we start tilting back
			d->setpointAdjustmentType = TILTBACK_NONE;
			d->state = RUNNING;
		}
	} else if (d->abs_duty_cycle > 0.05 && input_voltage < d->float_conf.tiltback_lv) {
		beep_alert(d, 3, false);	// Triple-beep
		d->beep_reason = BEEP_LV;
		float abs_motor_current = fabsf(d->motor_current);
		float vdelta = d->float_conf.tiltback_lv - input_voltage;
		float ratio = vdelta * 20 / abs_motor_current;
		// When to do LV tiltback:
		// a) we're 2V below lv threshold
		// b) motor current is small (we cannot assume vsag)
		// c) we have more than 20A per Volt of difference (we tolerate some amount of vsag)
		if ((vdelta > 2) || (abs_motor_current < 5) || (ratio > 1)) {
			if (d->erpm > 0) {
				d->setpoint_target = d->float_conf.tiltback_lv_angle;
			} else {
				d->setpoint_target = -d->float_conf.tiltback_lv_angle;
			}

			d->setpointAdjustmentType = TILTBACK_LV;
			d->state = RUNNING_TILTBACK;
		}
		else {
			d->setpointAdjustmentType = TILTBACK_NONE;
			d->setpoint_target = 0;
			d->state = RUNNING;
		}
	} else {
		// Normal running
		if (d->float_conf.fault_reversestop_enabled && (d->erpm < -200) && !d->is_upside_down) {
			d->setpointAdjustmentType = REVERSESTOP;
			d->reverse_timer = d->current_time;
			d->reverse_total_erpm = 0;
		}
		else {
			d->setpointAdjustmentType = TILTBACK_NONE;
		}
		d->setpoint_target = 0;
		d->state = RUNNING;
	}

	if ((d->state == RUNNING_WHEELSLIP) && (d->abs_duty_cycle > d->max_duty_with_margin)) {
		d->setpoint_target = 0;
	}
	if (d->is_upside_down && (d->state == RUNNING)) {
		d->state = RUNNING_UPSIDEDOWN;
		if (!d->is_upside_down_started) {
			// right after flipping when first engaging dark ride we add a 1 second grace period
			// before aggressively checking for board wiggle (based on acceleration)
			d->is_upside_down_started = true;
			d->delay_upside_down_fault = d->current_time;
		}
	}

	if (d->is_flywheel_mode == false) {
		if (d->setpointAdjustmentType == TILTBACK_DUTY) {
			if (d->float_conf.is_dutybeep_enabled || (d->float_conf.tiltback_duty_angle == 0)) {
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
}

static void calculate_setpoint_interpolated(data *d) {
	if (d->setpoint_target_interpolated != d->setpoint_target) {
		// If we are less than one step size away, go all the way
		if (fabsf(d->setpoint_target - d->setpoint_target_interpolated) < get_setpoint_adjustment_step_size(d)) {
			d->setpoint_target_interpolated = d->setpoint_target;
		} else if (d->setpoint_target - d->setpoint_target_interpolated > 0) {
			d->setpoint_target_interpolated += get_setpoint_adjustment_step_size(d);
		} else {
			d->setpoint_target_interpolated -= get_setpoint_adjustment_step_size(d);
		}
	}
}

static void add_surge(data *d) {
	if (d->surge_enable) {
		float abs_duty_smooth = fabsf(d->duty_smooth);
		float surge_now = 0;

		if (abs_duty_smooth > d->float_conf.surge_duty_start + 0.04) {
			surge_now = d->surge_angle3;
			beep_alert(d, 3, 1);
		}
		else if (abs_duty_smooth > d->float_conf.surge_duty_start + 0.02) {
			surge_now = d->surge_angle2;
			beep_alert(d, 2, 1);
		}
		else if (abs_duty_smooth > d->float_conf.surge_duty_start) {
			surge_now = d->surge_angle;
			beep_alert(d, 1, 1);
		}
		if (surge_now >= d->surge_adder) {
			// kick in instantly
			d->surge_adder = surge_now;
		}
		else {
			// release less harshly
			d->surge_adder = d->surge_adder * 0.98 + surge_now * 0.02;
		}

		// Add surge angle to setpoint
		if (d->erpm > 0) {
			d->setpoint += d->surge_adder;
		}
		else {
			d->setpoint -= d->surge_adder;
		}
	}
}

static void calculate_torqueresponse_interpolated(data *d) {
	float atr_brake_interpolated = d->atr_interpolated + d->braketilt_interpolated;

	// TOTAL: Torque Response Interpolated
	// If signs match between TorqueTilt and ATR+BrakeTilt, the more significant tilt angle between the two is taken
	// If signs do not match, they are simply added together
	if (SIGN(atr_brake_interpolated) == SIGN(d->torquetilt_interpolated)) {
		d->torqueresponse_interpolated = SIGN(atr_brake_interpolated) * fmaxf(fabsf(atr_brake_interpolated), fabsf(d->torquetilt_interpolated));
	} else {
		d->torqueresponse_interpolated = atr_brake_interpolated + d->torquetilt_interpolated;
	}
}

static void apply_noseangling(data *d){
	if (d->state != RUNNING_WHEELSLIP) {
		// Nose angle adjustment, add variable then constant tiltback
		float noseangling_target = 0;

		float variable_erpm = fmaxf(0, fabsf(d->erpm) - d->float_conf.tiltback_variable_erpm); // Variable Tiltback looks at ERPM from the reference point of the set minimum ERPM
		if (variable_erpm > d->tiltback_variable_max_erpm) {
			noseangling_target = d->float_conf.tiltback_variable_max * SIGN(d->erpm);
		} else {
			noseangling_target = d->tiltback_variable * variable_erpm * SIGN(d->erpm) * SIGN(d->float_conf.tiltback_variable_max);
		}

		if (fabsf(d->erpm) > d->float_conf.tiltback_constant_erpm) {
			noseangling_target += d->float_conf.tiltback_constant * SIGN(d->erpm);
		}

		if (fabsf(noseangling_target - d->noseangling_interpolated) < d->noseangling_step_size) {
			d->noseangling_interpolated = noseangling_target;
		} else if (noseangling_target - d->noseangling_interpolated > 0) {
			d->noseangling_interpolated += d->noseangling_step_size;
		} else {
			d->noseangling_interpolated -= d->noseangling_step_size;
		}
	}

	d->setpoint += d->noseangling_interpolated;
}

static void apply_inputtilt(data *d){ // Input Tiltback
	float input_tiltback_target;
	 
	// Scale by Max Angle
	input_tiltback_target = d->throttle_val * d->float_conf.inputtilt_angle_limit;

	// Invert for Darkride
	input_tiltback_target *= (d->is_upside_down ? -1.0 : 1.0);

	// // Default Behavior: Nose Tilt at any speed, does not invert for reverse (Safer for slow climbs/descents & jumps)
	// // Alternate Behavior (Negative Tilt Speed): Nose Tilt only while moving, invert to match direction of travel
	// if (balance_conf.roll_steer_erpm_kp < 0) {
	// 	if (state == RUNNING_WHEELSLIP) {     // During wheelslip, setpoint drifts back to level for ERPM-based Input Tilt
	// 		inputtilt_interpolated *= 0.995;  // to prevent chain reaction between setpoint and motor direction
	// 	} else if (erpm <= -200){
	// 		input_tiltback_target *= -1; // Invert angles for reverse
	// 	} else if (erpm < 200){
	// 		input_tiltback_target = 0; // Disable Input Tiltback at standstill to mitigate oscillations
	// 	}
	// }

	// if (d->float_conf.roll_steer_erpm_kp >= 0 || d->state != RUNNING_WHEELSLIP) { // Pause and gradually decrease ERPM-based Input Tilt during wheelslip
	// 	if (fabsf(input_tiltback_target - d->inputtilt_interpolated) < d->inputtilt_step_size){
	// 		d->inputtilt_interpolated = input_tiltback_target;
	// 	} else if (input_tiltback_target - d->inputtilt_interpolated > 0){
	// 		d->inputtilt_interpolated += d->inputtilt_step_size;
	// 	} else {
	// 		d->inputtilt_interpolated -= d->inputtilt_step_size;
	// 	}
	// }

	float input_tiltback_target_diff = input_tiltback_target - d->inputtilt_interpolated;

	if (d->float_conf.inputtilt_smoothing_factor > 0) { // Smoothen changes in tilt angle by ramping the step size
		float smoothing_factor = 0.02;
		for (int i = 1; i < d->float_conf.inputtilt_smoothing_factor; i++) {
			smoothing_factor /= 2;
		}

		float smooth_center_window = 1.5 + (0.5 * d->float_conf.inputtilt_smoothing_factor); // Sets the angle away from Target that step size begins ramping down
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

	d->setpoint += d->inputtilt_interpolated;
}

static void apply_torquetilt(data *d) {
	float tt_step_size = 0;
	float atr_step_size = 0;
	float braketilt_step_size = 0;
	int torque_sign;
	float abs_torque;
	float atr_threshold;
	float torque_offset;
	float accel_factor;
	float accel_factor2;
	float expected_acc;

	// Filter current (Biquad)
	if (d->float_conf.atr_filter > 0) {
		d->atr_filtered_current = biquad_process(&d->atr_current_biquad, d->motor_current);
	} else {
		d->atr_filtered_current = d->motor_current;
	}

	torque_sign = SIGN(d->atr_filtered_current);

	if ((d->abs_erpm > 250) && (torque_sign != SIGN(d->erpm))) {
		// current is negative, so we are braking or going downhill
		// high currents downhill are less likely
		d->braking = true;
	}
	else {
		d->braking = false;
	}

	// Are we dealing with a free-spinning wheel?
	// If yes, don't change the torquetilt till we got traction again
	// instead slightly decrease it each cycle
	if (d->state == RUNNING_WHEELSLIP) {
		d->torquetilt_interpolated *= 0.995;
		d->torquetilt_target *= 0.99;
		d->atr_interpolated *= 0.995;
		d->atr_target *= 0.99;
		d->braketilt_interpolated *= 0.995;
		d->braketilt_target *= 0.99;
		calculate_torqueresponse_interpolated(d);
		d->setpoint += d->torqueresponse_interpolated;
		d->wheelslip_end_timer = d->current_time;
		return;
	}
	else {
		/*
		if ((d->current_time - d->wheelslip_end_timer) * 1000 < 100) {
			// for 100ms after wheelslip we still don't do ATR to allow the wheel to decelerate
			d->torquetilt_interpolated *= 0.998;
			d->torquetilt_target *= 0.999;
			d->atr_interpolated *= 0.998;
			d->atr_target *= 0.999;
			d->braketilt_interpolated *= 0.998;
			d->braketilt_target *= 0.999;
			calculate_torqueresponse_interpolated(d);
			d->setpoint += d->torqueresponse_interpolated;
			return;
		}
		else if ((fabsf(d->acceleration) > 10) && (d->abs_erpm > 1000)) {
			d->torquetilt_interpolated *= 0.998;
			d->torquetilt_target *= 0.999;
			d->atr_interpolated *= 0.998;
			d->atr_target *= 0.999;
			d->braketilt_interpolated *= 0.998;
			d->braketilt_target *= 0.999;
			calculate_torqueresponse_interpolated(d);
			d->setpoint += d->torqueresponse_interpolated;
			return;
			}*/
	}

	// CLASSIC TORQUE TILT /////////////////////////////////

	float tt_strength = d->braking ? d->float_conf.torquetilt_strength_regen : d->float_conf.torquetilt_strength;

	// Do stock FW torque tilt: (comment from Mitch Lustig)
	// Take abs motor current, subtract start offset, and take the max of that with 0 to get the current above our start threshold (absolute).
	// Then multiply it by "power" to get our desired angle, and min with the limit to respect boundaries.
	// Finally multiply it by sign motor current to get directionality back
	float abs_net_torque = fmaxf(0, (fabsf(d->atr_filtered_current) - d->float_conf.torquetilt_start_current));
	d->torquetilt_target = fminf(abs_net_torque * tt_strength, d->float_conf.torquetilt_angle_limit) * SIGN(d->atr_filtered_current);

	if ((d->torquetilt_interpolated - d->torquetilt_target > 0 && d->torquetilt_target > 0) ||
			(d->torquetilt_interpolated - d->torquetilt_target < 0 && d->torquetilt_target < 0)) {
		tt_step_size = d->torquetilt_off_step_size;
	} else {
		tt_step_size = d->torquetilt_on_step_size;
	}

	
	// ADAPTIVE TORQUE RESPONSE ////////////////////////////

	abs_torque = fabsf(d->atr_filtered_current);
	torque_offset = 8;// hard-code to 8A for now (shouldn't really be changed much anyways)
	atr_threshold = d->braking ? d->float_conf.atr_threshold_down : d->float_conf.atr_threshold_up;
	accel_factor = d->braking ? d->float_conf.atr_amps_decel_ratio : d->float_conf.atr_amps_accel_ratio;
	accel_factor2 = accel_factor * 1.3;

	// compare measured acceleration to expected acceleration
	float measured_acc = fmaxf(d->acceleration, -5);
	measured_acc = fminf(measured_acc, 5);

	// expected acceleration is proportional to current (minus an offset, required to balance/maintain speed)
	//XXXXXfloat expected_acc;
	if (abs_torque < 25) {
		expected_acc = (d->atr_filtered_current - SIGN(d->erpm) * torque_offset) / accel_factor;
	}
	else {
		// primitive linear approximation of non-linear torque-accel relationship
		expected_acc = (torque_sign * 25 - SIGN(d->erpm) * torque_offset) / accel_factor;
		expected_acc += torque_sign * (abs_torque - 25) / accel_factor2;
	}

	bool forward = (d->erpm > 0);
	if ((d->abs_erpm < 250) && (abs_torque > 30)) {
		forward = (expected_acc > 0);
	}

	float acc_diff = expected_acc - measured_acc;
	d->float_expected_acc = expected_acc;
	d->float_measured_acc = measured_acc;
	d->float_acc_diff = acc_diff;

	if (d->abs_erpm > 2000)
		d->accel_gap = 0.9 * d->accel_gap + 0.1 * acc_diff;
	else if (d->abs_erpm > 1000)
		d->accel_gap = 0.95 * d->accel_gap + 0.05 * acc_diff;
	else if (d->abs_erpm > 250)
		d->accel_gap = 0.98 * d->accel_gap + 0.02 * acc_diff;
	else {
		d->accel_gap = 0;
	}

	// d->accel_gap | > 0  | <= 0
	// -------------+------+-------
	//      forward | up   | down
	//     !forward | down | up
	float atr_strength = forward == (d->accel_gap > 0) ? d->float_conf.atr_strength_up : d->float_conf.atr_strength_down;

	// from 3000 to 6000..9000 erpm gradually crank up the torque response
	if ((d->abs_erpm > 3000) && (!d->braking)) {
		float speedboost = (d->abs_erpm - 3000) * d->atr_speed_boost_multiplier;
		// configured speedboost can now also be negative (-1...1)!
		// -1 brings it to 0 (if erpm exceeds 9000)
		// +1 doubles it     (if erpm exceeds 9000)
		speedboost = fminf(1, speedboost) * d->float_conf.atr_speed_boost;
		atr_strength += atr_strength * speedboost;
	}

	// now ATR target is purely based on gap between expected and actual acceleration
	float new_atr_target = atr_strength * d->accel_gap;
	if (fabsf(new_atr_target) < atr_threshold) {
		new_atr_target = 0;
	}
	else {
		new_atr_target -= SIGN(new_atr_target) * atr_threshold;
	}

	d->atr_target = d->atr_target * 0.95 + 0.05 * new_atr_target;
	d->atr_target = fminf(d->atr_target, d->float_conf.atr_angle_limit);
	d->atr_target = fmaxf(d->atr_target, -d->float_conf.atr_angle_limit);

	float response_boost = 1;
	if (d->abs_erpm > 2500) {
		response_boost = d->float_conf.atr_response_boost;
	}
	if (d->abs_erpm > 6000) {
		response_boost *= d->float_conf.atr_response_boost;
	}

	// Key to keeping the board level and consistent is to determine the appropriate step size!
	// We want to react quickly to changes, but we don't want to overreact to glitches in acceleration data
	// or trigger oscillations...
	const float TT_BOOST_MARGIN = 2;
	if (forward) {
		if (d->atr_interpolated < 0) {
			// downhill
			if (d->atr_interpolated < d->atr_target) {
				// to avoid oscillations we go down slower than we go up
				atr_step_size = d->atr_off_step_size;
				if ((d->atr_target > 0)
					&& ((d->atr_target - d->atr_interpolated) > TT_BOOST_MARGIN)
					&& (d->abs_erpm > 2000))
				{
					// boost the speed if tilt target has reversed (and if there's a significant margin)
					atr_step_size = d->atr_off_step_size * d->float_conf.atr_transition_boost;
				}
			}
			else {
				// ATR is increasing
				atr_step_size = d->atr_on_step_size * response_boost;
			}
		}
		else {
			// uphill or other heavy resistance (grass, mud, etc)
			if ((d->atr_target > -3) && (d->atr_interpolated > d->atr_target)) {
				// ATR winding down (current ATR is bigger than the target)
				// normal wind down case: to avoid oscillations we go down slower than we go up
				atr_step_size = d->atr_off_step_size;
			}else{
				// standard case of increasing ATR
				atr_step_size = d->atr_on_step_size * response_boost;
			}
		}
	}
	else {
		if (d->atr_interpolated > 0) {
			// downhill
			if (d->atr_interpolated > d->atr_target) {
				// to avoid oscillations we go down slower than we go up
				atr_step_size = d->atr_off_step_size;
				if ((d->atr_target < 0)
					&& ((d->atr_interpolated - d->atr_target) > TT_BOOST_MARGIN)
					&& (d->abs_erpm > 2000)) {
					// boost the speed if tilt target has reversed (and if there's a significant margin)
					atr_step_size = d->atr_off_step_size * d->float_conf.atr_transition_boost;
				}
			}
			else {
				// ATR is increasing
				atr_step_size = d->atr_on_step_size * response_boost;
			}
		}
		else {
			// uphill or other heavy resistance (grass, mud, etc)
			if ((d->atr_target < 3) && (d->atr_interpolated < d->atr_target)) {
				// normal wind down case: to avoid oscillations we go down slower than we go up
				atr_step_size = d->atr_off_step_size;
			}else{
				// standard case of increasing torquetilt
				atr_step_size = d->atr_on_step_size * response_boost;
			}
		}
	}

	// Feature: Brake Tiltback

	// braking also should cause setpoint change lift, causing a delayed lingering nose lift
	if ((d->braketilt_factor < 0) && d->braking && (d->abs_erpm > 2000)) {
		// negative currents alone don't necessarily consitute active braking, look at proportional:
		if (SIGN(d->proportional) != SIGN(d->erpm)) {
			float downhill_damper = 1;
			// if we're braking on a downhill we don't want braking to lift the setpoint quite as much
			if (((d->erpm > 1000) && (d->accel_gap < -1)) ||
				((d->erpm < -1000) && (d->accel_gap > 1))) {
				downhill_damper += fabsf(d->accel_gap) / 2;
			}
			d->braketilt_target = d->proportional / d->braketilt_factor / downhill_damper;
			if (downhill_damper > 2) {
				// steep downhills, we don't enable this feature at all!
				d->braketilt_target = 0;
			}
		}
	}
	else {
		d->braketilt_target = 0;
	}

	braketilt_step_size = d->atr_off_step_size / d->float_conf.braketilt_lingering;
	if(fabsf(d->braketilt_target) > fabsf(d->braketilt_interpolated)) {
		braketilt_step_size = d->atr_on_step_size * 1.5;
	}
	else if (d->abs_erpm < 800) {
		braketilt_step_size = d->atr_on_step_size;
	}

	// when slow then erpm data is especially choppy, causing fake spikes in acceleration
	// mellow down the reaction to reduce noticeable oscillations
	if (d->abs_erpm < 500) {
		tt_step_size /= 2;
		atr_step_size /= 2;
		braketilt_step_size /= 2;
	}

	// Torque Tilt Interpolated
	if (fabsf(d->torquetilt_target - d->torquetilt_interpolated) < tt_step_size) {
		d->torquetilt_interpolated = d->torquetilt_target;
	} else if (d->torquetilt_target - d->torquetilt_interpolated > 0) {
		d->torquetilt_interpolated += tt_step_size;
	} else {
		d->torquetilt_interpolated -= tt_step_size;
	}

	// ATR Interpolated
	if (fabsf(d->atr_target - d->atr_interpolated) < atr_step_size) {
		d->atr_interpolated = d->atr_target;
	} else if (d->atr_target - d->atr_interpolated > 0) {
		d->atr_interpolated += atr_step_size;
	} else {
		d->atr_interpolated -= atr_step_size;
	}

	// Brake Tilt Interpolated
	if(fabsf(d->braketilt_target - d->braketilt_interpolated) < braketilt_step_size){
		d->braketilt_interpolated = d->braketilt_target;
	}else if (d->braketilt_target - d->braketilt_interpolated > 0){
		d->braketilt_interpolated += braketilt_step_size;
	}else{
		d->braketilt_interpolated -= braketilt_step_size;
	}

	calculate_torqueresponse_interpolated(d);
	d->setpoint += d->torqueresponse_interpolated;
}

static void apply_turntilt(data *d) {
	if (d->float_conf.turntilt_strength == 0) {
		return;
	}

	float abs_yaw_aggregate = fabsf(d->yaw_aggregate);
	
	// incremental turn increment since the last iteration
	float turn_increment = d->abs_yaw_change;

	// Minimum threshold based on
	// a) minimum degrees per second (yaw/turn increment)
	// b) minimum yaw aggregate (to filter out wiggling on uneven road)
	if ((abs_yaw_aggregate < d->float_conf.turntilt_start_angle) ||
		(turn_increment < 0.04) ||
		(d->state != RUNNING)) {
		d->turntilt_target = 0;
	}
	else {
		// Calculate desired angle
		float turn_change = d->abs_yaw_change;
		d->turntilt_target = turn_change * d->float_conf.turntilt_strength;

		// Apply speed scaling
		float boost;
		if (d->abs_erpm < d->float_conf.turntilt_erpm_boost_end) {
			boost = 1.0 + d->abs_erpm * d->turntilt_boost_per_erpm;
		} else {
			boost = 1.0 + (float)d->float_conf.turntilt_erpm_boost / 100.0;
		}
		d->turntilt_target *= boost;

		// Increase turntilt based on aggregate yaw change (at most: double it)
		float aggregate_damper = 1.0;
		if (d->abs_erpm < 2000) {
			aggregate_damper = 0.5;
		}
		boost = 1 + aggregate_damper * abs_yaw_aggregate / d->yaw_aggregate_target;
		boost = fminf(boost, 2);
		d->turntilt_target *= boost;

		// Limit angle to max angle
		if (d->turntilt_target > 0) {
			d->turntilt_target = fminf(d->turntilt_target, d->float_conf.turntilt_angle_limit);
		} else {
			d->turntilt_target = fmaxf(d->turntilt_target, -d->float_conf.turntilt_angle_limit);
		}

		// Disable below erpm threshold otherwise add directionality
		if (d->abs_erpm < d->float_conf.turntilt_start_erpm) {
			d->turntilt_target = 0;
		} else {
			d->turntilt_target *= SIGN(d->erpm);
		}

		// ATR interference: Reduce turntilt_target during moments of high torque response
		float atr_min = 2;
		float atr_max = 5;
		if (SIGN(d->atr_target) != SIGN(d->turntilt_target)) {
			// further reduced turntilt during moderate to steep downhills
			atr_min = 1;
			atr_max = 4;
		}
		if (fabsf(d->atr_target) > atr_min) {
			// Start scaling turntilt when ATR>2, down to 0 turntilt for ATR > 5 degrees
			float atr_scaling = (atr_max - fabsf(d->atr_target)) / (atr_max-atr_min);
			if (atr_scaling < 0) {
				atr_scaling = 0;
				// during heavy torque response clear the yaw aggregate too
				d->yaw_aggregate = 0;
			}
			d->turntilt_target *= atr_scaling;
		}
		if (fabsf(d->pitch_angle - d->noseangling_interpolated) > 4) {
			// no setpoint changes during heavy acceleration or braking
			d->turntilt_target = 0;
			d->yaw_aggregate = 0;
		}
	}

	// Move towards target limited by max speed
	if (fabsf(d->turntilt_target - d->turntilt_interpolated) < d->turntilt_step_size) {
		d->turntilt_interpolated = d->turntilt_target;
	} else if (d->turntilt_target - d->turntilt_interpolated > 0) {
		d->turntilt_interpolated += d->turntilt_step_size;
	} else {
		d->turntilt_interpolated -= d->turntilt_step_size;
	}

	d->setpoint += d->turntilt_interpolated;
}

static float haptic_buzz(data *d, float note_period, bool brake) {
	if (d->is_flywheel_mode) {
		return 0;
	}
	if (((d->setpointAdjustmentType > TILTBACK_NONE) && (d->state <= RUNNING_TILTBACK))
	    || d->overcurrent) {

		if (d->setpointAdjustmentType == TILTBACK_DUTY)
			d->haptic_type = d->float_conf.haptic_buzz_duty;
		else if (d->setpointAdjustmentType == TILTBACK_HV)
			d->haptic_type = d->float_conf.haptic_buzz_hv;
		else if (d->setpointAdjustmentType == TILTBACK_LV)
			d->haptic_type = d->float_conf.haptic_buzz_lv;
		else if (d->setpointAdjustmentType == TILTBACK_TEMP)
			d->haptic_type = d->float_conf.haptic_buzz_temp;
		else if (d->overcurrent)
			d->haptic_type = d->float_conf.haptic_buzz_current;
		else
			d->haptic_type = HAPTIC_BUZZ_NONE;

		// This kicks it off till at least one ~300ms tone is completed
		if (d->haptic_type != HAPTIC_BUZZ_NONE)
			d->haptic_tone_in_progress = true;
	}

	if (d->haptic_tone_in_progress || brake) {
		d->haptic_counter += 1;

		float buzz_current = fminf(20, d->float_conf.haptic_buzz_intensity);
		// small periods (1,2) produce audible tone, higher periods produce vibration
		int buzz_period = d->haptic_type;
		if (d->haptic_type == HAPTIC_BUZZ_ALTERNATING)
			buzz_period = 1;

		// alternate frequencies, depending on "mode"
		buzz_period += d->haptic_mode;

		if (brake) {
			// This is to emulate the equivalent of "stop click"
			buzz_current = fmaxf(3, d->float_conf.startup_click_current * 0.8);
			buzz_current = fminf(10, buzz_current);
			buzz_period = 0;
		}
		else if ((d->abs_erpm < 10000) && (buzz_current > 5)) {
			// scale high currents down to as low as 5A for lower erpms
			buzz_current = fmaxf(d->float_conf.haptic_buzz_min, d->abs_erpm / 10000 * buzz_current);
		}

		if (d->haptic_counter > buzz_period) {
			d->haptic_counter = 0;
		}

		if (d->haptic_counter == 0) {
			if (d->applied_haptic_current > 0) {
				d->applied_haptic_current = -buzz_current;
			}
			else {
				d->applied_haptic_current = buzz_current;
			}

			if (fabsf(d->haptic_timer - d->current_time) > note_period) {
				d->haptic_tone_in_progress = false;
				if (brake)
					d->haptic_mode += 1;
				else {
					if (d->haptic_type == HAPTIC_BUZZ_ALTERNATING)
						d->haptic_mode = 5 - d->haptic_mode;
					else
						d->haptic_mode = 1 - d->haptic_mode;
				}

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
	float brake_timeout_length = 1; // Brake Timeout hard-coded to 1s
	if ((d->abs_erpm > 1 || d->brake_timeout == 0)) {
		d->brake_timeout = d->current_time + brake_timeout_length;
	}

	if (d->brake_timeout != 0 && d->current_time > d->brake_timeout) {
		return;
	}

	// Reset the timeout
	VESC_IF->timeout_reset();

	// Set current
	VESC_IF->mc_set_brake_current(d->float_conf.brake_current);
}

static void set_current(data *d, float current){
	// Limit current output to configured max output (as configured in motor cfg)
	if (current > d->mc_current_max) {
		current = d->mc_current_max;
		d->overcurrent = true;
	} else if(current < -d->mc_current_min) {
		current = -d->mc_current_min;
	}

	// Reset the timeout
	VESC_IF->timeout_reset();
	// Set the current delay
	VESC_IF->mc_set_current_off_delay(d->motor_timeout_seconds);
	// Set Current
	VESC_IF->mc_set_current(current);
}

static void imu_ref_callback(float *acc, float *gyro, float *mag, float dt) {
	UNUSED(mag);
	data *d = (data*)ARG;
	VESC_IF->ahrs_update_mahony_imu(gyro, acc, dt, &d->m_att_ref);
}

static void float_thd(void *arg) {
	data *d = (data*)arg;

	app_init(d);
	led_init(&d->led_data, &d->float_conf);

	while (!VESC_IF->should_terminate()) {
		beeper_update(d);

		// Update times
		d->current_time = VESC_IF->system_time();
		if (d->last_time == 0) {
			d->last_time = d->current_time;
		}

		d->diff_time = d->current_time - d->last_time;
		d->filtered_diff_time = 0.03 * d->diff_time + 0.97 * d->filtered_diff_time; // Purely a metric
		d->last_time = d->current_time;

		// Loop Time Filter (Hard Coded to 3Hz)
		d->loop_overshoot = d->diff_time - (d->loop_time_seconds - roundf(d->filtered_loop_overshoot));
		d->filtered_loop_overshoot = d->loop_overshoot_alpha * d->loop_overshoot + (1.0 - d->loop_overshoot_alpha) * d->filtered_loop_overshoot;

		// Read values for GUI
		d->motor_current = VESC_IF->mc_get_tot_current_directional_filtered();

		// Get the IMU Values
		d->roll_angle = RAD2DEG_f(VESC_IF->ahrs_get_roll(&d->m_att_ref));
		d->abs_roll_angle = fabsf(d->roll_angle);
		d->abs_roll_angle_sin = sinf(DEG2RAD_f(d->abs_roll_angle));

		// Darkride:
		if (d->float_conf.fault_darkride_enabled) {
			if (d->is_upside_down) {
				if (d->abs_roll_angle < 120) {
					d->is_upside_down = false;
				}
			} else if (d->enable_upside_down) {
				if (d->abs_roll_angle > 150) {
					d->is_upside_down = true;
					d->is_upside_down_started = false;
					d->pitch_angle = -d->pitch_angle;
				}
			}
		}

		d->last_pitch_angle = d->pitch_angle;

		// True pitch is derived from the secondary IMU filter running with kp=0.2
		d->true_pitch_angle = RAD2DEG_f(VESC_IF->ahrs_get_pitch(&d->m_att_ref));
		d->pitch_angle = RAD2DEG_f(VESC_IF->imu_get_pitch());
		if (d->is_flywheel_mode) {
			// flip sign and use offsets
			d->true_pitch_angle = d->flywheel_pitch_offset - d->true_pitch_angle;
			d->pitch_angle = d->true_pitch_angle;
			d->roll_angle -= d->flywheel_roll_offset;
			if (d->roll_angle < -200) {
				d->roll_angle += 360;
			}
			else if (d->roll_angle > 200) {
				d->roll_angle -= 360;
			}
		}
		else if (d->is_upside_down) {
			d->pitch_angle = -d->pitch_angle - d->darkride_setpoint_correction;;
			d->true_pitch_angle = -d->true_pitch_angle - d->darkride_setpoint_correction;
		}

		d->last_gyro_y = d->gyro[1];
		VESC_IF->imu_get_gyro(d->gyro);

		// Get the motor values we want
		d->duty_cycle = VESC_IF->mc_get_duty_cycle_now();
		d->abs_duty_cycle = fabsf(d->duty_cycle);
		d->erpm = VESC_IF->mc_get_rpm();
		d->abs_erpm = fabsf(d->erpm);
		d->duty_smooth = d->duty_smooth * 0.9 + d->duty_cycle * 0.1;

		// UART/PPM Remote Throttle ///////////////////////
		bool remote_connected = false;
		float servo_val = 0;

		switch (d->float_conf.inputtilt_remote_type) {
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
			float deadband = d->float_conf.inputtilt_deadband;
			if (fabsf(servo_val) < deadband) {
				servo_val = 0.0;
			} else {
				servo_val = SIGN(servo_val) * (fabsf(servo_val) - deadband) / (1 - deadband);
			}

			// Invert Throttle
			servo_val *= (d->float_conf.inputtilt_invert_throttle ? -1.0 : 1.0);
		}

		d->throttle_val = servo_val;
		///////////////////////////////////////////////////


		// Torque Tilt:

		/* FW SUPPORT NEEDED FOR SMOOTH ERPM //////////////////////////
		float smooth_erpm = erpm_sign * mcpwm_foc_get_smooth_erpm();
		float acceleration_raw = smooth_erpm - last_erpm;
		d->last_erpm = smooth_erpm;
		////////////////////////// FW SUPPORT NEEDED FOR SMOOTH ERPM */

		float acceleration_raw = d->erpm - d->last_erpm;
		d->last_erpm = d->erpm;

		d->accelavg += (acceleration_raw - d->accelhist[d->accelidx]) / ACCEL_ARRAY_SIZE;
		d->accelhist[d->accelidx] = acceleration_raw;
		d->accelidx++;
		if (d->accelidx == ACCEL_ARRAY_SIZE)
			d->accelidx = 0;

		d->acceleration = d->accelavg;
		
		// Turn Tilt:
		d->yaw_angle = VESC_IF->ahrs_get_yaw(&d->m_att_ref) * 180.0f / M_PI;
		float new_change = d->yaw_angle - d->last_yaw_angle;
		bool unchanged = false;
		if ((new_change == 0) // Exact 0's only happen when the IMU is not updating between loops
			|| (fabsf(new_change) > 100)) // yaw flips signs at 180, ignore those changes
		{
			new_change = d->last_yaw_change;
			unchanged = true;
		}
		d->last_yaw_change = new_change;
		d->last_yaw_angle = d->yaw_angle;

		// To avoid overreactions at low speed, limit change here:
		new_change = fminf(new_change, 0.10);
		new_change = fmaxf(new_change, -0.10);
		d->yaw_change = d->yaw_change * 0.8 + 0.2 * (new_change);
		// Clear the aggregate yaw whenever we change direction
		if (SIGN(d->yaw_change) != SIGN(d->yaw_aggregate))
			d->yaw_aggregate = 0;
		d->abs_yaw_change = fabsf(d->yaw_change);
		if ((d->abs_yaw_change > 0.04) && !unchanged)	// don't count tiny yaw changes towards aggregate
			d->yaw_aggregate += d->yaw_change;

		footpad_sensor_update(&d->footpad_sensor, &d->float_conf);

		int float_state = (d->is_flywheel_mode && (d->state <= RUNNING_TILTBACK)) ? RUNNING_FLYWHEEL : d->state;
		int switch_state = footpad_sensor_state_to_switch_compat(d->footpad_sensor.state);
		led_update(&d->led_data, &d->float_conf, d->current_time, d->erpm, d->abs_duty_cycle, switch_state, float_state);

		if (d->footpad_sensor.state == FS_NONE && float_state <= RUNNING_TILTBACK && d->abs_erpm > d->switch_warn_beep_erpm) {
			// If we're at riding speed and the switch is off => ALERT the user
			// set force=true since this could indicate an imminent shutdown/nosedive
			beep_on(d, true);
			d->beep_reason = BEEP_SENSORS;
		} else {
			// if the switch comes back on we stop beeping
			beep_off(d, false);
		}

		// Log Values
		d->float_setpoint = d->setpoint;
		d->float_atr = d->atr_interpolated;
		d->float_braketilt = d->braketilt_interpolated;
		d->float_torquetilt = d->torquetilt_interpolated;
		d->float_turntilt = d->turntilt_interpolated;
		d->float_inputtilt = d->inputtilt_interpolated;

		float new_pid_value = 0;

		// Control Loop State Logic
		switch(d->state) {
		case (STARTUP):
				// Disable output
				brake(d);
				if (VESC_IF->imu_startup_done()) {
					reset_vars(d);
					d->state = FAULT_STARTUP; // Trigger a fault so we need to meet start conditions to start

					// Are we within 5V of the LV tiltback threshold? Issue 1 beep for each volt below that
					float bat_volts = VESC_IF->mc_get_input_voltage_filtered();
					float threshold = d->float_conf.tiltback_lv + 5;
					if (bat_volts < threshold) {
						int beeps = (int)fminf(6, threshold - bat_volts);
						beep_alert(d, beeps + 1, true);
						d->beep_reason = BEEP_LOWBATT;
					}
					else {
						// // Let the rider know that the board is ready (one long beep)
						beep_alert(d, 1, true);
					}
				}
				break;

		case (RUNNING):
		case (RUNNING_TILTBACK):
		case (RUNNING_WHEELSLIP):
		case (RUNNING_UPSIDEDOWN):
		case (RUNNING_FLYWHEEL):
			// Check for faults
			if (check_faults(d)) {
				if ((d->state == FAULT_SWITCH_FULL) && !d->is_upside_down) {
					// dirty landings: add extra margin when rightside up
					d->startup_pitch_tolerance = d->float_conf.startup_pitch_tolerance + d->startup_pitch_trickmargin;
					d->fault_angle_pitch_timer = d->current_time;
				}
				break;
			}
			d->odometer_dirty = 1;
			
			d->enable_upside_down = true;
			d->disengage_timer = d->current_time;

			// Calculate setpoint and interpolation
			calculate_setpoint_target(d);
			calculate_setpoint_interpolated(d);
			d->setpoint = d->setpoint_target_interpolated;
			add_surge(d);
			apply_inputtilt(d); // Allow Input Tilt for Darkride
			if (!d->is_upside_down) {
				apply_noseangling(d);
				apply_torquetilt(d);
				apply_turntilt(d);
			}

			// Prepare Brake Scaling (ramp scale values as needed for smooth transitions)
			if (fabsf(d->erpm) < 500) { // Nearly standstill
				d->kp_brake_scale = 0.01 + 0.99 * d->kp_brake_scale; // All scaling should roll back to 1.0x when near a stop for a smooth stand-still and back-forth transition
				d->kp2_brake_scale = 0.01 + 0.99 * d->kp2_brake_scale;
				d->kp_accel_scale = 0.01 + 0.99 * d->kp_accel_scale;
				d->kp2_accel_scale = 0.01 + 0.99 * d->kp2_accel_scale;

			} else if (d->erpm > 0){ // Moving forwards
				d->kp_brake_scale = 0.01 * d->float_conf.kp_brake + 0.99 * d->kp_brake_scale; // Once rolling forward, brakes should transition to scaled values
				d->kp2_brake_scale = 0.01 * d->float_conf.kp2_brake + 0.99 * d->kp2_brake_scale;
				d->kp_accel_scale = 0.01 + 0.99 * d->kp_accel_scale;
				d->kp2_accel_scale = 0.01 + 0.99 * d->kp2_accel_scale;

			} else { // Moving backwards
				d->kp_brake_scale = 0.01 + 0.99 * d->kp_brake_scale; // Once rolling backward, the NEW brakes (we will use kp_accel) should transition to scaled values
				d->kp2_brake_scale = 0.01 + 0.99 * d->kp2_brake_scale;
				d->kp_accel_scale = 0.01 * d->float_conf.kp_brake + 0.99 * d->kp_accel_scale;
				d->kp2_accel_scale = 0.01 * d->float_conf.kp2_brake + 0.99 * d->kp2_accel_scale;
			}

			// Do PID maths
			d->proportional = d->setpoint - d->pitch_angle;
			bool tail_down = SIGN(d->proportional) != SIGN(d->erpm);

			// Resume real PID maths
			d->pid_integral = d->pid_integral + d->proportional * d->ki;

			// Apply I term Filter
			if (d->float_conf.ki_limit > 0 && fabsf(d->pid_integral) > d->float_conf.ki_limit) {
				d->pid_integral = d->float_conf.ki_limit * SIGN(d->pid_integral);
			}
			// Quickly ramp down integral component during reverse stop
			if (d->setpointAdjustmentType == REVERSESTOP) {
				d->pid_integral = d->pid_integral * 0.9;
			}

			// Apply P Brake Scaling
			float scaled_kp;
			if (d->proportional < 0) { // Choose appropriate scale based on board angle (yes, this accomodates backwards riding)
				scaled_kp = d->float_conf.kp * d->kp_brake_scale;
			} else {
				scaled_kp = d->float_conf.kp * d->kp_accel_scale;
			}

			d->pid_prop = scaled_kp * d->proportional;
			new_pid_value = d->pid_prop + d->pid_integral;

			d->last_proportional = d->proportional;

			// Start Rate PID and Booster portion a few cycles later, after the start clicks have been emitted
			// this keeps the start smooth and predictable
			if (d->start_counter_clicks == 0) {

				// Rate P (Angle + Rate, rather than Angle-Rate Cascading)
				float rate_prop = -d->gyro[1];

				float scaled_kp2;
				if (rate_prop < 0) { // Choose appropriate scale based on board angle (yes, this accomodates backwards riding)
					scaled_kp2 = d->float_conf.kp2 * d->kp2_brake_scale;
				} else {
					scaled_kp2 = d->float_conf.kp2 * d->kp2_accel_scale;
				}

				d->pid_mod = (scaled_kp2 * rate_prop);


				// Apply Booster (Now based on True Pitch)
				float true_proportional = (d->setpoint - d->braketilt_interpolated) - d->true_pitch_angle; // Braketilt excluded to allow for soft brakes that strengthen when near tail-drag
				d->abs_proportional = fabsf(true_proportional);

				float booster_current, booster_angle, booster_ramp;
				if (tail_down) {
					booster_current = d->float_conf.brkbooster_current;
					booster_angle = d->float_conf.brkbooster_angle;
					booster_ramp = d->float_conf.brkbooster_ramp;
				}
				else {
					booster_current = d->float_conf.booster_current;
					booster_angle = d->float_conf.booster_angle;
					booster_ramp = d->float_conf.booster_ramp;
				}

				// Make booster a bit stronger at higher speed (up to 2x stronger when braking)
				const int boost_min_erpm = 3000;
				if (d->abs_erpm > boost_min_erpm) {
					float speedstiffness = fminf(1, (d->abs_erpm - boost_min_erpm) / 10000);
					if (tail_down) {
						// use higher current at speed when braking
						booster_current += booster_current * speedstiffness;
					}
					else {
						// when accelerating, we reduce the booster start angle as we get faster
						// strength remains unchanged
						float angledivider = 1 + speedstiffness;
						booster_angle /= angledivider;
					}
				}

				if (d->abs_proportional > booster_angle) {
					if (d->abs_proportional - booster_angle < booster_ramp) {
						booster_current *= SIGN(true_proportional) *
								((d->abs_proportional - booster_angle) / booster_ramp);
					} else {
						booster_current *= SIGN(true_proportional);
					}
				}
				else {
					booster_current = 0;
				}

				// No harsh changes in booster current (effective delay <= 100ms)
				d->applied_booster_current = 0.01 * booster_current + 0.99 * d->applied_booster_current;
				d->pid_mod += d->applied_booster_current;

				if (d->softstart_pid_limit < d->mc_current_max) {
					d->pid_mod = fminf(fabs(d->pid_mod), d->softstart_pid_limit) * SIGN(d->pid_mod);
					d->softstart_pid_limit += d->softstart_ramp_step_size;
				}

				new_pid_value += d->pid_mod;
			}
			else {
				d->pid_mod = 0;
			}

			// Current Limiting!
			float current_limit;
			if (d->braking) {
				current_limit = d->current_min * (1 + 0.6 * fabsf(d->torqueresponse_interpolated / 10));
			}
			else {
				current_limit = d->current_max * (1 + 0.6 * fabsf(d->torqueresponse_interpolated / 10));
			}
			if (fabsf(new_pid_value) > current_limit) {
				new_pid_value = SIGN(new_pid_value) * current_limit;
			}

			d->overcurrent = false;

			// Over continuous current for more than 3 seconds? Just beep, don't actually limit currents
			if (fabsf(d->atr_filtered_current) < d->max_continuous_current) {
				d->overcurrent_timer = d->current_time;
				if (d->current_beeping) {
					d->current_beeping = false;
					beep_off(d, false);
				}
			} else {
				if (d->current_time - d->overcurrent_timer > 3) {
					beep_on(d, true);
					d->current_beeping = true;
					d->overcurrent = true;
				}
			}

			if (d->traction_control) {
				// freewheel while traction loss is detected
				d->pid_value = 0;
			}
			else {
				// Brake Amp Rate Limiting
				if (d->braking && (fabsf(d->pid_value - new_pid_value) > d->pid_brake_increment)) {
					if (new_pid_value > d->pid_value) {
						d->pid_value += d->pid_brake_increment;
					}
					else {
						d->pid_value -= d->pid_brake_increment;
					}
				}
				else {
					d->pid_value = d->pid_value * 0.8 + new_pid_value * 0.2;
				}
			}

			// Output to motor
			if (d->start_counter_clicks) {
				// Generate alternate pulses to produce distinct "click"
				d->start_counter_clicks--;
				if ((d->start_counter_clicks & 0x1) == 0)
					set_current(d, d->pid_value - d->float_conf.startup_click_current);
				else
					set_current(d, d->pid_value + d->float_conf.startup_click_current);
			}
			else {
				// modulate haptic buzz onto pid_value unconditionally to allow
				// checking for haptic conditions, and to finish minimum duration haptic effect
				// even after short pulses of hitting the condition(s)
				d->pid_value += haptic_buzz(d, 0.3, false);
				set_current(d, d->pid_value);
			}

			break;

		case (FAULT_ANGLE_PITCH):
		case (FAULT_ANGLE_ROLL):
		case (FAULT_REVERSE):
		case (FAULT_QUICKSTOP):
		case (FAULT_SWITCH_HALF):
		case (FAULT_SWITCH_FULL):
		case (FAULT_STARTUP):
			if (d->is_flywheel_mode) {
				if ((d->flywheel_abort) ||	// single-pad pressed while balancing upright
					(d->flywheel_allow_abort && d->footpad_sensor.adc1 > 1 && d->footpad_sensor.adc2 > 1)) {
					flywheel_stop(d);
					break;
				}
			}

			if (!d->is_flywheel_mode && d->true_pitch_angle > 75 && d->true_pitch_angle < 105) {
				if (konami_check(&d->flywheel_konami, &d->footpad_sensor, &d->float_conf, d->current_time)) {
					unsigned char enabled[6] = {0x82, 0, 0, 0, 0, 1};
					cmd_flywheel_toggle(d, enabled, 6);
				}
			}

			if (konami_check(&d->battery_konami, &d->footpad_sensor, &d->float_conf, d->current_time)) {
				if (d->battery_level > 94)
					// 1 long beep indicates full charge (95% or more)
					beep_alert(d, 1, 1);
				else
					// N short beeps where N is batterylevel/10 (e.g. 5 beeps for 50%)
					beep_alert(d, d->battery_level / 10, 0);
			}

			if (d->current_time - d->disengage_timer > 10) {
				// 10 seconds of grace period between flipping the board over and allowing darkride mode...
				if (d->is_upside_down) {
					beep_alert(d, 1, true);
				}
				d->enable_upside_down = false;
				d->is_upside_down = false;
			}	
			if (d->current_time - d->disengage_timer > 1800) {	// alert user after 30 minutes
				if (d->current_time - d->nag_timer > 60) {		// beep every 60 seconds
					d->nag_timer = d->current_time;
					float input_voltage = VESC_IF->mc_get_input_voltage_filtered();
					if (input_voltage > d->idle_voltage) {
						// don't beep if the voltage keeps increasing (board is charging)
						d->idle_voltage = input_voltage;
					}
					else {
						d->beep_reason = BEEP_IDLE;
						beep_alert(d, 2, 1);						// 2 long beeps
					}
				}
			}
			else {
				d->nag_timer = d->current_time;
				d->idle_voltage = 0;
			}

			if ((d->current_time - d->fault_angle_pitch_timer) > 1) {
				// 1 second after disengaging - set startup tolerance back to normal (aka tighter)
				d->startup_pitch_tolerance = d->float_conf.startup_pitch_tolerance;
			}

			check_odometer(d);

			// Check for valid startup position and switch state
			if (fabsf(d->pitch_angle) < d->startup_pitch_tolerance &&
				fabsf(d->roll_angle) < d->float_conf.startup_roll_tolerance && 
				is_engaged(d)) {
				reset_vars(d);
				break;
			}
			// Ignore roll for the first second while it's upside down
			if(d->is_upside_down && (fabsf(d->pitch_angle) < d->startup_pitch_tolerance)) {
				if ((d->current_time - d->disengage_timer) > 1) {
					// after 1 second:
					if (fabsf(fabsf(d->roll_angle) - 180) < d->float_conf.startup_roll_tolerance) {
						reset_vars(d);
						break;
					}
				}
				else {
					// 1 second or less, ignore roll-faults to allow for kick flips etc.
					if (d->state != FAULT_REVERSE) {
						// don't instantly re-engage after a reverse fault!
						reset_vars(d);
						break;
					}
				}
			}
			// Push-start aka dirty landing Part II
			if(d->float_conf.startup_pushstart_enabled && (d->abs_erpm > 1000) && is_engaged(d)) {
				if ((fabsf(d->pitch_angle) < 45) && (fabsf(d->roll_angle) < 45)) {
					// 45 to prevent board engaging when upright or laying sideways
					// 45 degree tolerance is more than plenty for tricks / extreme mounts
					reset_vars(d);
					break;
				}
			}

			if ((d->current_time - d->disengage_timer) < 0.008) {
				// 20ms brake buzz, single tone
				if (d->float_conf.startup_click_current > 0) {
					set_current(d, haptic_buzz(d, 0.008, true));
				}
			}
			else {
				// Set RC current or maintain brake current (and keep WDT happy!)
				do_rc_move(d);
			}
			break;
		case (CHARGING):
			if ((d->current_time - d->charge_timer) > 10) {
				// 10 seconds of no chargestate calls? Revert back to normal
				if (d->float_conf.float_disable) {
					d->state = DISABLED;
				}
				else {
					d->state = STARTUP;
				}
			}
			break;
		case (DISABLED):;
			// no set_current, no brake_current
		default:;
		}

		// Debug outputs
//		app_balance_sample_debug();
//		app_balance_experiment();

		// Delay between loops
		VESC_IF->sleep_us((uint32_t)((d->loop_time_seconds - roundf(d->filtered_loop_overshoot)) * 1000000.0));
	}
}

static void write_cfg_to_eeprom(data *d) {
	uint32_t ints = sizeof(float_config) / 4 + 1;
	uint32_t *buffer = VESC_IF->malloc(ints * sizeof(uint32_t));
	bool write_ok = true;
	memcpy(buffer, &(d->float_conf), sizeof(float_config));
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
		v.as_u32 = FLOAT_CONFIG_SIGNATURE;
		VESC_IF->store_eeprom_var(&v, 0);
	}

	// Emit 1 short beep to confirm writing all settings to eeprom
	beep_alert(d, 1, 0);
}

static void read_cfg_from_eeprom(data *d) {
	// Read config from EEPROM if signature is correct
	eeprom_var v;
	uint32_t ints = sizeof(float_config) / 4 + 1;
	uint32_t *buffer = VESC_IF->malloc(ints * sizeof(uint32_t));
	bool read_ok = VESC_IF->read_eeprom_var(&v, 0);
	if (read_ok && v.as_u32 == FLOAT_CONFIG_SIGNATURE) {
		for (uint32_t i = 0;i < ints;i++) {
			if (!VESC_IF->read_eeprom_var(&v, i + 1)) {
				read_ok = false;
				break;
			}
			buffer[i] = v.as_u32;
		}
	} else {
		read_ok = false;
	}

	if (read_ok) {
		memcpy(&(d->float_conf), buffer, sizeof(float_config));

		if (d->float_conf.float_version != APPCONF_FLOAT_VERSION) {
			if (!VESC_IF->app_is_output_disabled()) {
				VESC_IF->printf("Version change since last config write (%.1f vs %.1f) !",
								(double)d->float_conf.float_version,
								(double)APPCONF_FLOAT_VERSION);
			}
			d->float_conf.float_version = APPCONF_FLOAT_VERSION;
		}
	} else {
		confparser_set_defaults_float_config(&(d->float_conf));
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("Float Package Error: Reverting to default config!\n");
		}
	}

	VESC_IF->free(buffer);
}

static float app_float_get_debug(int index) {
	data *d = (data*)ARG;

	switch(index){
		case(1):
			return d->setpoint;
		case(2):
			return d->float_setpoint;
		case(3):
			return d->atr_filtered_current;
		case(4):
			return d->float_atr;
		case(5):
			return d->last_pitch_angle - d->pitch_angle;
		case(6):
			return d->motor_current;
		case(7):
			return d->erpm;
		case(8):
			return d->abs_erpm;
		case(9):
			return d->loop_time_seconds;
		case(10):
			return d->diff_time;
		case(11):
			return d->loop_overshoot;
		case(12):
			return d->filtered_loop_overshoot;
		case(13):
			return d->filtered_diff_time;
		case(14):
			return d->pid_integral / d->float_conf.ki;
		case(15):
			return d->pid_integral;
		case(16):
			return 0;
		case(17):
			return 0;
		default:
			return 0;
	}
}

enum {
	FLOAT_COMMAND_GET_INFO = 0,		// get version / package info
	FLOAT_COMMAND_GET_RTDATA = 1,	// get rt data
	FLOAT_COMMAND_RT_TUNE = 2,		// runtime tuning (don't write to eeprom)
	FLOAT_COMMAND_TUNE_DEFAULTS = 3,// set tune to defaults (no eeprom)
	FLOAT_COMMAND_CFG_SAVE = 4,		// save config to eeprom
	FLOAT_COMMAND_CFG_RESTORE = 5,	// restore config from eeprom
	FLOAT_COMMAND_TUNE_OTHER = 6,	// make runtime changes to startup/etc
	FLOAT_COMMAND_RC_MOVE = 7,		// move motor while board is idle
	FLOAT_COMMAND_BOOSTER = 8,		// change booster settings
	FLOAT_COMMAND_PRINT_INFO = 9,	// print verbose info
	FLOAT_COMMAND_GET_ALLDATA = 10,	// send all data, compact
	FLOAT_COMMAND_EXPERIMENT = 11,  // generic cmd for sending data, used for testing/tuning new features
	FLOAT_COMMAND_LOCK = 12,
	FLOAT_COMMAND_HANDTEST = 13,
	FLOAT_COMMAND_TUNE_TILT = 14,
	FLOAT_COMMAND_FLYWHEEL = 22,
	FLOAT_COMMAND_HAPTIC = 23,
	FLOAT_COMMAND_LCM_POLL = 24,   // this should only be called by external light modules
	FLOAT_COMMAND_LIGHT_INFO = 25, // to be called by apps to check if a lighting module is present / get info
	FLOAT_COMMAND_LIGHT_CTRL = 26, // to be called by apps to change light settings
	FLOAT_COMMAND_LCM_INFO = 27,   // to be called by apps to check lighting controller firmware
	FLOAT_COMMAND_CHARGESTATE = 28,// to be called by ADV LCM while charging
	FLOAT_COMMAND_GET_BATTERY = 29, 
	FLOAT_COMMAND_LCM_DEBUG = 99,  // reserved for external debug purposes
} float_commands;

static void send_realtime_data(data *d){
	#define BUFSIZE 72
	uint8_t send_buffer[BUFSIZE];
	int32_t ind = 0;
	send_buffer[ind++] = 101;//Magic Number
	send_buffer[ind++] = FLOAT_COMMAND_GET_RTDATA;

	// RT Data
	buffer_append_float32_auto(send_buffer, d->pid_value, &ind);
	buffer_append_float32_auto(send_buffer, d->pitch_angle, &ind);
	buffer_append_float32_auto(send_buffer, d->roll_angle, &ind);

	uint8_t state = (d->state & 0xF);
	if ((d->is_flywheel_mode) && (d->state > 0) && (d->state < 6)) {
		state = RUNNING_FLYWHEEL;
	}
	send_buffer[ind++] = (state & 0xF) + (d->setpointAdjustmentType << 4);
	state = footpad_sensor_state_to_switch_compat(d->footpad_sensor.state);
	if (d->do_handtest) {
		state |= 0x8;
	}
	send_buffer[ind++] = (state & 0xF) + (d->beep_reason << 4);
	buffer_append_float32_auto(send_buffer, d->footpad_sensor.adc1, &ind);
	buffer_append_float32_auto(send_buffer, d->footpad_sensor.adc2, &ind);

	// Setpoints
	buffer_append_float32_auto(send_buffer, d->float_setpoint, &ind);
	buffer_append_float32_auto(send_buffer, d->float_atr, &ind);
	buffer_append_float32_auto(send_buffer, d->float_braketilt, &ind);
	buffer_append_float32_auto(send_buffer, d->float_torquetilt, &ind);
	buffer_append_float32_auto(send_buffer, d->float_turntilt, &ind);
	buffer_append_float32_auto(send_buffer, d->float_inputtilt, &ind);

	// DEBUG
	buffer_append_float32_auto(send_buffer, d->true_pitch_angle, &ind);
	buffer_append_float32_auto(send_buffer, d->atr_filtered_current, &ind);
	buffer_append_float32_auto(send_buffer, d->float_acc_diff, &ind);
	if (d->state == CHARGING) {
		buffer_append_float32_auto(send_buffer, d->charge_current, &ind);
		buffer_append_float32_auto(send_buffer, d->charge_voltage, &ind);
	}
	else {
		buffer_append_float32_auto(send_buffer, d->applied_booster_current, &ind);
		buffer_append_float32_auto(send_buffer, d->motor_current, &ind);
	}
	buffer_append_float32_auto(send_buffer, d->throttle_val, &ind);

	if (ind > BUFSIZE) {
		VESC_IF->printf("BUFSIZE too small...\n");
	}
	VESC_IF->send_app_data(send_buffer, ind);
}

static void cmd_send_all_data(data *d, unsigned char mode){
	#define SNDBUFSIZE 60
	uint8_t send_buffer[SNDBUFSIZE];
	int32_t ind = 0;
	mc_fault_code fault = VESC_IF->mc_get_fault();

	send_buffer[ind++] = 101;//Magic Number
	send_buffer[ind++] = FLOAT_COMMAND_GET_ALLDATA;

	if (fault != FAULT_CODE_NONE) {
		send_buffer[ind++] = 69;
		send_buffer[ind++] = fault;
	}
	else {
		send_buffer[ind++] = mode;

		// RT Data
		buffer_append_float16(send_buffer, d->pid_value, 10, &ind);
		buffer_append_float16(send_buffer, d->pitch_angle, 10, &ind);
		buffer_append_float16(send_buffer, d->roll_angle, 10, &ind);

		uint8_t state = (d->state & 0xF) + (d->setpointAdjustmentType << 4);
		if ((d->is_flywheel_mode) && (d->state > 0) && (d->state < 6)) {
			state = RUNNING_FLYWHEEL;
		}
		send_buffer[ind++] = state;

		// passed switch-state includes bit3 for handtest, and bits4..7 for beep reason
		state = footpad_sensor_state_to_switch_compat(d->footpad_sensor.state);
		if (d->do_handtest) {
			state |= 0x8;
		}
		send_buffer[ind++] = (state & 0xF) + (d->beep_reason << 4);
		d->beep_reason = BEEP_NONE;

		send_buffer[ind++] = d->footpad_sensor.adc1 * 50;
		send_buffer[ind++] = d->footpad_sensor.adc2 * 50;

		// Setpoints (can be positive or negative)
		send_buffer[ind++] = d->float_setpoint * 5 + 128;
		send_buffer[ind++] = d->float_atr * 5 + 128;
		send_buffer[ind++] = d->float_braketilt * 5 + 128;
		send_buffer[ind++] = d->float_torquetilt * 5 + 128;
		send_buffer[ind++] = d->float_turntilt * 5 + 128;
		send_buffer[ind++] = d->float_inputtilt * 5 + 128;
	
		buffer_append_float16(send_buffer, d->true_pitch_angle, 10, &ind);
		send_buffer[ind++] = d->applied_booster_current + 128;

		// Now send motor stuff:
		buffer_append_float16(send_buffer, VESC_IF->mc_get_input_voltage_filtered(), 10, &ind);
		buffer_append_int16(send_buffer, VESC_IF->mc_get_rpm(), &ind);
		buffer_append_float16(send_buffer, VESC_IF->mc_get_speed(), 10, &ind);
		buffer_append_float16(send_buffer, VESC_IF->mc_get_tot_current(), 10, &ind);
		buffer_append_float16(send_buffer, VESC_IF->mc_get_tot_current_in(), 10, &ind);
		send_buffer[ind++] = VESC_IF->mc_get_duty_cycle_now() * 100 + 128;
		if (VESC_IF->foc_get_id != NULL)
			send_buffer[ind++] = fabsf(VESC_IF->foc_get_id()) * 3;
		else
			send_buffer[ind++] = 222;	// using 222 as magic number to avoid false positives with 255
		// ind = 35!

		if (mode >= 2) {
			// data not required as fast as possible
			buffer_append_float32_auto(send_buffer, VESC_IF->mc_get_distance_abs(), &ind);
			send_buffer[ind++] = fmaxf(0, VESC_IF->mc_temp_fet_filtered() * 2);
			send_buffer[ind++] = fmaxf(0, VESC_IF->mc_temp_motor_filtered() * 2);
			send_buffer[ind++] = 0;//fmaxf(VESC_IF->mc_batt_temp() * 2);
			// ind = 42
		}
		if (mode >= 3) {
			// data required even less frequently
			buffer_append_uint32(send_buffer, VESC_IF->mc_get_odometer(), &ind);
			buffer_append_float16(send_buffer, VESC_IF->mc_get_amp_hours(false), 10, &ind);
			buffer_append_float16(send_buffer, VESC_IF->mc_get_amp_hours_charged(false), 10, &ind);
			buffer_append_float16(send_buffer, VESC_IF->mc_get_watt_hours(false), 1, &ind);
			buffer_append_float16(send_buffer, VESC_IF->mc_get_watt_hours_charged(false), 1, &ind);
			send_buffer[ind++] = fmaxf(0, fminf(110, d->battery_level)) * 2;
			// ind = 55
		}
		if (mode >= 4) {
			// make charge current and voltage available in mode 4
			buffer_append_float16(send_buffer, d->charge_current, 10, &ind);
			buffer_append_float16(send_buffer, d->charge_voltage, 10, &ind);
			// ind = 59
		}
	}

	if (ind > SNDBUFSIZE) {
		VESC_IF->printf("BUFSIZE too small...\n");
	}
	VESC_IF->send_app_data(send_buffer, ind);
}

static void cmd_send_battery(){
	uint8_t send_buffer[10];
	int32_t ind = 0;
	send_buffer[ind++] = 101;//Magic Number
	send_buffer[ind++] = FLOAT_COMMAND_GET_BATTERY;
	buffer_append_float32_auto(send_buffer, VESC_IF->mc_get_battery_level(NULL), &ind);

	if (ind > 10) {
		VESC_IF->printf("BUFSIZE too small...\n");
	}
	VESC_IF->send_app_data(send_buffer, ind);
}

static void split(unsigned char byte, int* h1, int* h2)
{
	*h1 = byte & 0xF;
	*h2 = byte >> 4;
}

static void cmd_print_info(data *d)
{
	//VESC_IF->printf("A:%.1f, D:%.2f\n", d->surge_angle, d->float_conf.surge_duty_start);
}

static void cmd_lock(data *d, unsigned char *cfg)
{
	if (d->state >= FAULT_ANGLE_PITCH) {
		d->float_conf.float_disable = cfg[0] ? true : false;
		if (d->state != CHARGING) {
			d->state = cfg[0] ? DISABLED : STARTUP;
		}
		write_cfg_to_eeprom(d);
	}
}

static void cmd_handtest(data *d, unsigned char *cfg)
{
	if (d->state >= FAULT_ANGLE_PITCH) {
		d->do_handtest = cfg[0] ? true : false;
		if (d->do_handtest) {
			// temporarily reduce max currents to make hand test safer / gentler
			d->current_max = 7;
			d->current_min = -7;
			// Disable I-term and all tune modifiers and tilts
			d->float_conf.ki = 0;
			d->float_conf.kp_brake = 1;
			d->float_conf.kp2_brake = 1;
			d->float_conf.brkbooster_angle = 100;
			d->float_conf.booster_angle = 100;
			d->float_conf.torquetilt_strength = 0;
			d->float_conf.torquetilt_strength_regen = 0;
			d->float_conf.atr_strength_up = 0;
			d->float_conf.atr_strength_down = 0;
			d->float_conf.turntilt_strength = 0;
			d->float_conf.tiltback_constant = 0;
			d->float_conf.tiltback_variable = 0;
			d->float_conf.fault_delay_pitch = 50;
			d->float_conf.fault_delay_roll = 50;
			d->float_conf.startup_pitch_tolerance = 1;
			d->float_conf.startup_speed = 10;
		}
		else {
			read_cfg_from_eeprom(d);
			configure(d);
		}
	}
}

static void cmd_experiment(data *d, unsigned char *cfg)
{
	d->surge_angle = cfg[0];
	d->surge_angle /= 10;
	d->float_conf.surge_duty_start = cfg[1];
	d->float_conf.surge_duty_start /= 100;
	if ((d->surge_angle > 1) || (d->float_conf.surge_duty_start < 0.85)) {
		d->float_conf.surge_duty_start = 0.85;
		d->surge_angle = 0.6;
	}
	else {
		d->surge_enable = true;
		beep_alert(d, 2, 0);
	}
	d->surge_angle2 = d->surge_angle * 2;
	d->surge_angle3 = d->surge_angle * 3;

	if (d->surge_angle == 0) {
		d->surge_enable = false;
	}
}

static void cmd_booster(data *d, unsigned char *cfg)
{
	int h1, h2;
	split(cfg[0], &h1, &h2);
	d->float_conf.booster_angle = h1 + 5;
	d->float_conf.booster_ramp = h2 + 2;

	split(cfg[1], &h1, &h2);
	if (h1 == 0)
		d->float_conf.booster_current = 0;
	else
		d->float_conf.booster_current = 8 + h1 * 2;

	split(cfg[2], &h1, &h2);
	d->float_conf.brkbooster_angle = h1 + 5;
	d->float_conf.brkbooster_ramp = h2 + 2;

	split(cfg[3], &h1, &h2);
	if (h1 == 0)
		d->float_conf.brkbooster_current = 0;
	else
		d->float_conf.brkbooster_current = 8 + h1 * 2;

	beep_alert(d, 1, false);
}

/**
 * cmd_runtime_tune		Extract tune info from 20byte message but don't write to EEPROM!
 */
static void cmd_runtime_tune(data *d, unsigned char *cfg, int len)
{
	int h1, h2;
	if (len >= 12) {
		split(cfg[0], &h1, &h2);
		d->float_conf.kp = h1 + 15;
		d->float_conf.kp2 = ((float)h2) / 10;

		split(cfg[1], &h1, &h2);
		d->float_conf.ki = h1;
		if (h1 == 1)
			d->float_conf.ki = 0.005;
		else if (h1 > 1)
			d->float_conf.ki = ((float)(h1 - 1)) / 100;
		d->ki = normalized_to_iteration_ki(d->float_conf.ki, d->float_conf.hertz);
		d->float_conf.ki_limit = h2 + 19;
		if (h2 == 0)
			d->float_conf.ki_limit = 0;

		split(cfg[2], &h1, &h2);
		d->float_conf.booster_angle = h1 + 5;
		d->float_conf.booster_ramp = h2 + 2;

		split(cfg[3], &h1, &h2);
		if (h1 == 0)
			d->float_conf.booster_current = 0;
		else
			d->float_conf.booster_current = 8 + h1 * 2;
		d->float_conf.turntilt_strength = h2;

		split(cfg[4], &h1, &h2);
		d->float_conf.turntilt_angle_limit = (h1 & 0x3) + 2;
		d->float_conf.turntilt_start_erpm = (float)(h1 >> 2) * 500 + 1000;
		d->float_conf.mahony_kp = ((float)h2) / 10 + 1.5;
		VESC_IF->set_cfg_float(CFG_PARAM_IMU_mahony_kp + 100, d->float_conf.mahony_kp);

		split(cfg[5], &h1, &h2);
		if (h1 == 0)
			d->float_conf.atr_strength_up = 0;
		else
			d->float_conf.atr_strength_up = ((float)h1) / 10.0 + 0.5;
		if (h2 == 0)
			d->float_conf.atr_strength_down = 0;
		else
			d->float_conf.atr_strength_down = ((float)h2) / 10.0 + 0.5;

		split(cfg[6], &h1, &h2);
		int isnegative = h1;
		d->float_conf.atr_speed_boost = ((float)(h2 * 5)) / 100;
		if (isnegative) {
			d->float_conf.atr_speed_boost *= -1;
		}

		split(cfg[7], &h1, &h2);
		d->float_conf.atr_angle_limit = h1 + 5;
		d->float_conf.atr_on_speed = (h2 & 0x3) + 3;
		d->float_conf.atr_off_speed = (h2 >> 2) + 2;

		split(cfg[8], &h1, &h2);
		d->float_conf.atr_response_boost = ((float)h1) / 10 + 1;
		d->float_conf.atr_transition_boost = ((float)h2) / 5 + 1;

		split(cfg[9], &h1, &h2);
		d->float_conf.atr_amps_accel_ratio = h1 + 5;
		d->float_conf.atr_amps_decel_ratio = h2 + 5;

		split(cfg[10], &h1, &h2);
		d->float_conf.braketilt_strength = h1;
		d->float_conf.braketilt_lingering = h2;

		split(cfg[11], &h1, &h2);
		d->current_max = h1 * 5 + 55;
		d->current_min = h2 * 5 + 55;
		if (h1 == 0) d->current_max = fminf(d->mc_current_max, d->float_conf.limit_current_accel);
		if (h2 == 0) d->current_min = fminf(d->mc_current_min, fabsf(d->float_conf.limit_current_brake));

		// Update values normally done in configure()
		d->atr_on_step_size = d->float_conf.atr_on_speed / d->float_conf.hertz;
		d->atr_off_step_size = d->float_conf.atr_off_speed / d->float_conf.hertz;
		d->turntilt_step_size = d->float_conf.turntilt_speed / d->float_conf.hertz;

		// Feature: Braketilt
		d->braketilt_factor = d->float_conf.braketilt_strength;
		d->braketilt_factor = 20 - d->braketilt_factor;
		// incorporate negative sign into braketilt factor instead of adding it each balance loop
		d->braketilt_factor = -(0.5 + d->braketilt_factor / 5.0);
	}
	if (len >= 16) {
		split(cfg[12], &h1, &h2);
		float thup = h1;
		float thdown = h2;
		d->float_conf.atr_threshold_up = thup / 2;
		d->float_conf.atr_threshold_down = thdown / 2;

		split(cfg[13], &h1, &h2);
		float ttup = h1;
		float ttdn = h2;
		d->float_conf.torquetilt_strength = ttup / 10 * 0.3;
		d->float_conf.torquetilt_strength_regen = ttdn / 10 * 0.3;

		split(cfg[14], &h1, &h2);
		float maxangle = h1;
		d->float_conf.torquetilt_start_current = h2 + 15;
		d->float_conf.torquetilt_angle_limit = maxangle / 2;

		split(cfg[15], &h1, &h2);
		float onspd = h1;
		float offspd = h2;
		d->float_conf.torquetilt_on_speed = onspd / 2;
		d->float_conf.torquetilt_off_speed = offspd + 3;
		d->torquetilt_on_step_size = d->float_conf.torquetilt_on_speed / d->float_conf.hertz;
		d->torquetilt_off_step_size = d->float_conf.torquetilt_off_speed / d->float_conf.hertz;
	}
	if (len >= 17) {
		split(cfg[16], &h1, &h2);
		d->float_conf.kp_brake = ((float)h1 + 1) / 10;
		d->float_conf.kp2_brake = ((float)h2) / 10;
		beep_alert(d, 1, 1);
	}
}

static void cmd_tune_defaults(data *d){
	d->float_conf.kp = APPCONF_FLOAT_KP;
	d->float_conf.kp2 = APPCONF_FLOAT_KP2;
	d->float_conf.ki = APPCONF_FLOAT_KI;
	d->float_conf.mahony_kp = APPCONF_FLOAT_MAHONY_KP;
	d->float_conf.kp_brake = APPCONF_FLOAT_KP_BRAKE;
	d->float_conf.kp2_brake = APPCONF_FLOAT_KP2_BRAKE;
	d->float_conf.ki_limit = APPCONF_FLOAT_KI_LIMIT;
	d->float_conf.booster_angle = APPCONF_FLOAT_BOOSTER_ANGLE;
	d->float_conf.booster_ramp = APPCONF_FLOAT_BOOSTER_RAMP;
	d->float_conf.booster_current = APPCONF_FLOAT_BOOSTER_CURRENT;
	d->float_conf.brkbooster_angle = APPCONF_FLOAT_BRKBOOSTER_ANGLE;
	d->float_conf.brkbooster_ramp = APPCONF_FLOAT_BRKBOOSTER_RAMP;
	d->float_conf.brkbooster_current = APPCONF_FLOAT_BRKBOOSTER_CURRENT;
	d->float_conf.turntilt_strength = APPCONF_FLOAT_TURNTILT_STRENGTH;
	d->float_conf.turntilt_angle_limit = APPCONF_FLOAT_TURNTILT_ANGLE_LIMIT;
	d->float_conf.turntilt_start_angle = APPCONF_FLOAT_TURNTILT_START_ANGLE;
	d->float_conf.turntilt_start_erpm = APPCONF_FLOAT_TURNTILT_START_ERPM;
	d->float_conf.turntilt_speed = APPCONF_FLOAT_TURNTILT_SPEED;
	d->float_conf.turntilt_erpm_boost = APPCONF_FLOAT_TURNTILT_ERPM_BOOST;
	d->float_conf.turntilt_erpm_boost_end = APPCONF_FLOAT_TURNTILT_ERPM_BOOST_END;
	d->float_conf.turntilt_yaw_aggregate = APPCONF_FLOAT_TURNTILT_YAW_AGGREGATE;
	d->float_conf.atr_strength_up = APPCONF_FLOAT_ATR_UPHILL_STRENGTH;
	d->float_conf.atr_strength_down = APPCONF_FLOAT_ATR_DOWNHILL_STRENGTH;
	d->float_conf.atr_threshold_up = APPCONF_FLOAT_ATR_THRESHOLD_UP;
	d->float_conf.atr_threshold_down = APPCONF_FLOAT_ATR_THRESHOLD_DOWN;
	d->float_conf.atr_speed_boost = APPCONF_FLOAT_ATR_SPEED_BOOST;
	d->float_conf.atr_angle_limit = APPCONF_FLOAT_ATR_ANGLE_LIMIT;
	d->float_conf.atr_on_speed = APPCONF_FLOAT_ATR_ON_SPEED;
	d->float_conf.atr_off_speed = APPCONF_FLOAT_ATR_OFF_SPEED;
	d->float_conf.atr_response_boost = APPCONF_FLOAT_ATR_RESPONSE_BOOST;
	d->float_conf.atr_transition_boost = APPCONF_FLOAT_ATR_TRANSITION_BOOST;
	d->float_conf.atr_filter = APPCONF_FLOAT_ATR_FILTER;
	d->float_conf.atr_amps_accel_ratio = APPCONF_FLOAT_ATR_AMPS_ACCEL_RATIO;
	d->float_conf.atr_amps_decel_ratio = APPCONF_FLOAT_ATR_AMPS_DECEL_RATIO;
	d->float_conf.braketilt_strength = APPCONF_FLOAT_BRAKETILT_STRENGTH;
	d->float_conf.braketilt_lingering = APPCONF_FLOAT_BRAKETILT_LINGERING;

	d->float_conf.startup_pitch_tolerance = APPCONF_FLOAT_STARTUP_PITCH_TOLERANCE;
	d->float_conf.startup_roll_tolerance = APPCONF_FLOAT_STARTUP_ROLL_TOLERANCE;
	d->float_conf.startup_speed = APPCONF_FLOAT_STARTUP_SPEED;
	d->float_conf.startup_click_current = APPCONF_FLOAT_STARTUP_CLICK_CURRENT;
	d->float_conf.brake_current = APPCONF_FLOAT_BRAKE_CURRENT;
	d->float_conf.is_beeper_enabled = APPCONF_FLOAT_IS_BEEPER_ENABLED;
	d->float_conf.tiltback_constant = APPCONF_FLOAT_TILTBACK_CONSTANT;
	d->float_conf.tiltback_constant_erpm = APPCONF_FLOAT_TILTBACK_CONSTANT_ERPM;
	d->float_conf.tiltback_variable = APPCONF_FLOAT_TILTBACK_VARIABLE;
	d->float_conf.tiltback_variable_max = APPCONF_FLOAT_TILTBACK_VARIABLE_MAX;
	d->float_conf.noseangling_speed = APPCONF_FLOAT_NOSEANGLING_SPEED;
	d->float_conf.startup_pushstart_enabled = APPCONF_PUSHSTART_ENABLED;
	d->float_conf.startup_simplestart_enabled = APPCONF_SIMPLESTART_ENABLED;
	d->float_conf.startup_dirtylandings_enabled = APPCONF_DIRTYLANDINGS_ENABLED;

	// Update values normally done in configure()
	d->atr_on_step_size = d->float_conf.atr_on_speed / d->float_conf.hertz;
	d->atr_off_step_size = d->float_conf.atr_off_speed / d->float_conf.hertz;
	d->turntilt_step_size = d->float_conf.turntilt_speed / d->float_conf.hertz;

	d->startup_step_size = d->float_conf.startup_speed / d->float_conf.hertz;
	d->noseangling_step_size = d->float_conf.noseangling_speed / d->float_conf.hertz;
	d->startup_pitch_trickmargin = d->float_conf.startup_dirtylandings_enabled ? 10 : 0;
	d->tiltback_variable = d->float_conf.tiltback_variable / 1000;
	if (d->tiltback_variable > 0) {
		d->tiltback_variable_max_erpm = fabsf(d->float_conf.tiltback_variable_max / d->tiltback_variable);
	} else {
		d->tiltback_variable_max_erpm = 100000;
	}
}

/**
 * cmd_runtime_tune_tilt		Extract settings from 20byte message but don't write to EEPROM!
 */
static void cmd_runtime_tune_tilt(data *d, unsigned char *cfg, int len)
{
	unsigned int flags = cfg[0];
	bool duty_beep = flags & 0x1;
	d->float_conf.is_dutybeep_enabled = duty_beep;
	float retspeed = cfg[1];
	if (retspeed > 0) {
		d->float_conf.tiltback_return_speed = retspeed / 10;
		d->tiltback_return_step_size = d->float_conf.tiltback_return_speed / d->float_conf.hertz;
	}
	d->float_conf.tiltback_duty = (float)cfg[2] / 100.0;
	d->float_conf.tiltback_duty_angle = (float)cfg[3] / 10.0;
	d->float_conf.tiltback_duty_speed = (float)cfg[4] / 10.0;

	if (len >= 6) {
		float surge_duty_start = cfg[5];
		if (surge_duty_start > 0) {
			d->float_conf.surge_duty_start = surge_duty_start / 100.0;
			d->float_conf.surge_angle  = (float)cfg[6] / 20.0;
			d->surge_angle = d->float_conf.surge_angle;
			d->surge_angle2 = d->float_conf.surge_angle * 2;
			d->surge_angle3 = d->float_conf.surge_angle * 3;
			d->surge_enable = d->surge_angle > 0;
		}
		beep_alert(d, 1, 1);
	}
	else {
		beep_alert(d, 3, 0);
	}
}

/**
 * cmd_runtime_tune_other		Extract settings from 20byte message but don't write to EEPROM!
 */
static void cmd_runtime_tune_other(data *d, unsigned char *cfg, int len)
{
	unsigned int flags = cfg[0];
	d->beeper_enabled = ((flags & 0x2) == 2);
	d->float_conf.fault_reversestop_enabled = ((flags & 0x4) == 4);
	d->float_conf.fault_is_dual_switch = ((flags & 0x8) == 8);
	d->float_conf.fault_darkride_enabled = ((flags & 0x10) == 0x10);
	bool dirty_landings = ((flags & 0x20) == 0x20);
	d->float_conf.startup_simplestart_enabled = ((flags & 0x40) == 0x40);
	d->float_conf.startup_pushstart_enabled = ((flags & 0x80) == 0x80);

	d->float_conf.is_beeper_enabled = d->beeper_enabled;
	d->startup_pitch_trickmargin = dirty_landings ? 10 : 0;
	d->float_conf.startup_dirtylandings_enabled = dirty_landings;

	// startup
	float ctrspeed = cfg[1];
	float pitchtolerance = cfg[2];
	float rolltolerance = cfg[3];
	float brakecurrent = cfg[4];
	float clickcurrent = cfg[5];

	d->startup_step_size = ctrspeed / d->float_conf.hertz;
	d->float_conf.startup_speed = ctrspeed;
	d->float_conf.startup_pitch_tolerance = pitchtolerance / 10;
	d->float_conf.startup_roll_tolerance = rolltolerance;
	d->float_conf.brake_current = brakecurrent / 2;
	d->float_conf.startup_click_current = clickcurrent;

	// nose angling
	float tiltconst = cfg[6] - 100;
	float tiltspeed = cfg[7];
	int tilterpm = cfg[8] * 100;
	float tiltvarrate = cfg[9];
	float tiltvarmax = cfg[10];

	if (fabsf(tiltconst <= 20)) {
		d->float_conf.tiltback_constant = tiltconst / 2;
		d->float_conf.tiltback_constant_erpm = tilterpm;
		if (tiltspeed > 0) {
			d->noseangling_step_size = tiltspeed / 10 / d->float_conf.hertz;
			d->float_conf.noseangling_speed = tiltspeed / 10;
		}
		d->float_conf.tiltback_variable = tiltvarrate / 100;
		d->float_conf.tiltback_variable_max = tiltvarmax / 10;

		d->startup_step_size = d->float_conf.startup_speed / d->float_conf.hertz;
		d->noseangling_step_size = d->float_conf.noseangling_speed / d->float_conf.hertz;
		d->tiltback_variable = d->float_conf.tiltback_variable / 1000;
		if (d->tiltback_variable > 0) {
			d->tiltback_variable_max_erpm = fabsf(d->float_conf.tiltback_variable_max / d->tiltback_variable);
		} else {
			d->tiltback_variable_max_erpm = 100000;
		}
		d->float_conf.tiltback_variable_erpm = cfg[11] * 100;
	}

	if (len >= 14) {
		int inputtilt = cfg[12] & 0x3;
		if (inputtilt <= INPUTTILT_PPM) {
			d->float_conf.inputtilt_remote_type = inputtilt;
			if (inputtilt > 0) {
				d->float_conf.inputtilt_angle_limit = cfg[12] >> 2;
				d->float_conf.inputtilt_speed = cfg[13];
				d->inputtilt_step_size = d->float_conf.inputtilt_speed / d->float_conf.hertz;
			}
		}
	}
}

void cmd_rc_move(data *d, unsigned char *cfg)//int amps, int time)
{
	int ind = 0;
	int direction = cfg[ind++];
	int current = cfg[ind++];
	int time = cfg[ind++];
	int sum = cfg[ind++];
	if (sum != time+current) {
		current = 0;
	}
	else if (direction == 0) {
		current = -current;
	}

	if (d->state >= FAULT_ANGLE_PITCH) {
		d->rc_counter = 0;
		if (current == 0) {
			d->rc_steps = 1;
			d->rc_current_target = 0;
			d->rc_current = 0;
		}
		else {
			d->rc_steps = time * 100;
			d->rc_current_target = current / 10.0;
			if (d->rc_current_target > 8) {
				d->rc_current_target = 2;
			}
		}
	}
}

static void cmd_haptic_config(data *d, unsigned char *cfg, int len)
{
	if (len > 6) {
		d->float_conf.haptic_buzz_intensity = cfg[0];
		d->float_conf.haptic_buzz_min = cfg[1];
	        d->float_conf.haptic_buzz_duty = cfg[2];
		d->float_conf.haptic_buzz_hv = cfg[3];
		d->float_conf.haptic_buzz_lv = cfg[4];
		d->float_conf.haptic_buzz_temp = cfg[5];
		d->float_conf.haptic_buzz_current = cfg[6];
		beep_alert(d, 1, 1);
	}
	else {
		d->float_conf.haptic_buzz_intensity = cfg[0];
		d->float_conf.haptic_buzz_min = 4;
	        d->float_conf.haptic_buzz_duty = cfg[1];
		d->float_conf.haptic_buzz_hv = cfg[1];
		d->float_conf.haptic_buzz_lv = cfg[1];
		d->float_conf.haptic_buzz_temp = cfg[1];
		d->float_conf.haptic_buzz_current = cfg[1];
	}
	beep_alert(d, 1, 1);
}

/**
 * Command for the LCM to poll data from the float package
 * Also used to pass LCM name/version info (usually on 1st call)
 */
static void cmd_lcm_poll(data *d, unsigned char *cfg, int len)
{
	// Optional: pass in name and version in a single string
	if (len > 0) {
 		// Read name from LCM
		for (int i = 0; i < MAXLCMNAMELENGTH; i++) {
			if (i > len || i > MAXLCMNAMELENGTH - 1 || cfg[i] == '\0') {
				d->lcm_name[i] = '\0';
				break;
			}
			d->lcm_name[i] = (char)cfg[i];
		}
	}

	#define POLLBUFSIZE 20 + MAXLCMPAYLOADLENGTH
	uint8_t send_buffer[POLLBUFSIZE];
	int32_t ind = 0;
	mc_fault_code fault = VESC_IF->mc_get_fault();

	// 11 bytes for base info
	send_buffer[ind++] = 101;//Magic Number
	send_buffer[ind++] = FLOAT_COMMAND_LCM_POLL;

	uint8_t state = (d->state & 0xF);
	if ((d->is_flywheel_mode) && (d->state > 0) && (d->state < 6)) {
		state = RUNNING_FLYWHEEL;
	}
	state += d->footpad_sensor.state << 4;
	if (d->do_handtest) {
		state |= 0x80;
	}
		
	send_buffer[ind++] = state;
	send_buffer[ind++] = fault;

	// LCM only needs Duty Cycle, ERPM, and Input Current
	send_buffer[ind++] = fminf(100, fabsf(d->abs_duty_cycle * 100));
	buffer_append_float16(send_buffer, d->erpm, 1e0, &ind);
	buffer_append_float16(send_buffer, VESC_IF->mc_get_tot_current_in(), 1e0, &ind);
	buffer_append_float16(send_buffer, VESC_IF->mc_get_input_voltage_filtered(), 1e1, &ind);

	// LCM control info
	send_buffer[ind++] = d->float_conf.led_brightness;
	send_buffer[ind++] = d->float_conf.led_brightness_idle;
	send_buffer[ind++] = d->float_conf.led_status_brightness;

	// Relay any generic byte pairs set by cmd_light_ctrl
	for (int i = 0; i < d->lcm_payload.size; i++) {
		send_buffer[ind++] = d->lcm_payload.data[i];
	}
	d->lcm_payload.size = 0; // Message has been processed, clear it

	if (ind > POLLBUFSIZE) {
		VESC_IF->printf("BUFSIZE too small [%d vs %d]...\n", ind, POLLBUFSIZE);
	}
	VESC_IF->send_app_data(send_buffer, ind);
}

/**
 * Command for apps to call to get info about lighting
 */
static void cmd_light_info(data *d)
{
	uint8_t send_buffer[15];
	int32_t ind = 0;
	send_buffer[ind++] = 101;//Magic Number
	send_buffer[ind++] = FLOAT_COMMAND_LIGHT_INFO;
	send_buffer[ind++] = d->float_conf.led_type;
	send_buffer[ind++] = d->float_conf.led_brightness;
	send_buffer[ind++] = d->float_conf.led_brightness_idle;
	send_buffer[ind++] = d->float_conf.led_status_brightness;
	send_buffer[ind++] = d->float_conf.led_mode;
	send_buffer[ind++] = d->float_conf.led_mode_idle;
	send_buffer[ind++] = d->float_conf.led_status_mode;
	send_buffer[ind++] = d->float_conf.led_status_count;
	send_buffer[ind++] = d->float_conf.led_forward_count;
	send_buffer[ind++] = d->float_conf.led_rear_count;

	VESC_IF->send_app_data(send_buffer, ind);
}

/**
 * Command for apps to call to LCM hardware info (if any)
 */
static void cmd_lcm_info(data *d)
{
	uint8_t send_buffer[18];
	int32_t ind = 0;
	send_buffer[ind++] = 101;//Magic Number
	send_buffer[ind++] = FLOAT_COMMAND_LCM_INFO;
	// Write light module firmware name into buffer
	for (int i = 0; i < MAXLCMNAMELENGTH; i++) {
		send_buffer[ind++] = d->lcm_name[i];
		if (d->lcm_name[i] == '\0') {
			break;
		}
	}

	VESC_IF->send_app_data(send_buffer, ind);
}

/**
 * Command to be called by ADV/LCM to announce that the board is charging
 */
static void cmd_chargestate(data *d, unsigned char *cfg, int len)
{
	// ignore this while riding!
	if ((d->state >= RUNNING) && (d->state <= RUNNING_FLYWHEEL))
		return;

	// Expecting 6 bytes:
	// -magic nr: must be 151
	// -charging: 1/0 aka true/false
	// -voltage: 16bit float divided by 10
	// -current: 16bit float divided by 10
	if (len < 6)
		return;

        uint8_t magicnr = cfg[0];
	if (magicnr != 151)
		return;

	bool charging = (cfg[1] > 0);
	d->charge_timer = d->current_time;

	if (charging) {
	        int32_t idx = 2;
		d->charge_voltage = buffer_get_float16(cfg, 10, &idx);
		d->charge_current = buffer_get_float16(cfg, 10, &idx);
		d->state = CHARGING;
	}
	else if (d->state == CHARGING) {
		// Once charging is done, go back to normal
		if (d->float_conf.float_disable) {
			d->state = DISABLED;
		}
		else {
			d->state = STARTUP;
		}
		d->charge_voltage = 0;
		d->charge_current = 0;
	}
}

/**
 * Command for apps to call to control LCM details (lights, behavior, etc)
 */
static void cmd_light_ctrl(data *d, unsigned char *cfg, int len)
{
	if (len < 3)
		return;

	d->float_conf.led_brightness = cfg[0];
	d->float_conf.led_brightness_idle = cfg[1];
	d->float_conf.led_status_brightness = cfg[2];

	if (len > 3) {
		if (d->float_conf.led_type == LED_Type_External_Module) {
			// Copy rest of payload into data for LCM to pull
			d->lcm_payload.size = len - 3;
			for (int i = 0; i < d->lcm_payload.size; i++) {
				d->lcm_payload.data[i] = cfg[i + 3];
			}
		} else {
			if (len > 5) {
				d->float_conf.led_mode = cfg[3];
				d->float_conf.led_mode_idle = cfg[4];
				d->float_conf.led_status_mode = cfg[5];
			}
		}
	}
}

static void cmd_flywheel_toggle(data *d, unsigned char *cfg, int len)
{
	if ((cfg[0] & 0x80) == 0)
		return;

	if ((d->state >= RUNNING) && (d->state <= RUNNING_FLYWHEEL))
		return;

	// cfg[0]: Command (0 = stop, 1 = start)
	// All of the below are mandatory, but can be 0 to just use defaults
	// cfg[1]: AngleP: kp*10 (e.g. 90: P=9.0)
	// cfg[2]: RateP:  kp2*100 (e.g. 50: RateP=0.5)
	// cfg[3]: Duty TB Angle * 10
	// cfg[4]: Duty TB Duty %
	// cfg[5]: Allow Abort via footpad (1 = do allow, 0 = don't allow)
	// Optional:
	// cfg[6]: Duty TB Speed in deg/sec
	int command = cfg[0] & 0x7F;
	d->is_flywheel_mode = (command == 0) ? false : true;

	if (d->is_flywheel_mode) {
		if ((d->flywheel_pitch_offset == 0) || (command == 2)) {
			// accidental button press?? board isn't evn close to being upright
			if (fabsf(d->true_pitch_angle) < 70) {
				// don't forget to set flywheel mode back to false!
				d->is_flywheel_mode = false;
				return;
			}

			d->flywheel_pitch_offset = d->true_pitch_angle;
			d->flywheel_roll_offset = d->roll_angle;
			beep_alert(d, 1, 1);
		}
		else {
			beep_alert(d, 3, 0);
		}
		d->flywheel_abort = false;

		// Tighter startup/fault tolerances
		d->startup_pitch_tolerance = 0.2;
		d->float_conf.startup_pitch_tolerance = 0.2;
		d->float_conf.startup_roll_tolerance = 25;
		d->float_conf.fault_pitch = 6;
		d->float_conf.fault_roll = 60;	// roll can fluctuate significantly in the upright position
		if (command & 0x4) {
			d->float_conf.fault_roll = 90;
		}
		d->float_conf.fault_delay_pitch = 50; // 50ms delay should help filter out IMU noise
		d->float_conf.fault_delay_roll = 50;  // 50ms delay should help filter out IMU noise
		d->surge_enable = false;

		// Aggressive P with some D (aka Rate-P) for Mahony kp=0.3
		d->float_conf.kp = 8.0;
		d->float_conf.kp2 = 0.3;

		if (cfg[1] > 0) {
			d->float_conf.kp = cfg[1];
			d->float_conf.kp /= 10;
		}
		if (cfg[2] > 0) {
			d->float_conf.kp2 = cfg[2];
			d->float_conf.kp2 /= 100;
		}

		d->float_conf.tiltback_duty_angle = 2;
		d->float_conf.tiltback_duty = 0.1;
		d->float_conf.tiltback_duty_speed = 5;
		d->float_conf.tiltback_return_speed = 5;

		if (cfg[3] > 0) {
			d->float_conf.tiltback_duty_angle = cfg[3];
			d->float_conf.tiltback_duty_angle /= 10;
		}
		if (cfg[4] > 0) {
			d->float_conf.tiltback_duty = cfg[4];
			d->float_conf.tiltback_duty /= 100;
		}
		if ((len > 6) && (cfg[6] > 1) && (cfg[6] < 100)) {
			d->float_conf.tiltback_duty_speed = cfg[6] / 2;
			d->float_conf.tiltback_return_speed = cfg[6] / 2;
		}
		d->tiltback_duty_step_size = d->float_conf.tiltback_duty_speed / d->float_conf.hertz;
		d->tiltback_return_step_size = d->float_conf.tiltback_return_speed / d->float_conf.hertz;

		// Limit speed of wheel and limit amps
		//backup_erpm = mc_interface_get_configuration()->l_max_erpm;
		VESC_IF->set_cfg_float(CFG_PARAM_l_min_erpm + 100, -6000);
		VESC_IF->set_cfg_float(CFG_PARAM_l_max_erpm + 100, 6000);
		d->current_max = d->current_min = 50;

		d->flywheel_allow_abort = cfg[5];

		// Disable I-term and all tune modifiers and tilts
		d->float_conf.ki = 0;
		d->float_conf.kp_brake = 1;
		d->float_conf.kp2_brake = 1;
		d->float_conf.brkbooster_angle = 100;
		d->float_conf.booster_angle = 100;
		d->float_conf.torquetilt_strength = 0;
		d->float_conf.torquetilt_strength_regen = 0;
		d->float_conf.atr_strength_up = 0;
		d->float_conf.atr_strength_down = 0;
		d->float_conf.turntilt_strength = 0;
		d->float_conf.tiltback_constant = 0;
		d->float_conf.tiltback_variable = 0;
		d->float_conf.brake_current = 0;
		d->float_conf.fault_darkride_enabled = false;
		d->float_conf.fault_reversestop_enabled = false;
		d->float_conf.tiltback_constant = 0;
		d->tiltback_variable_max_erpm = 0;
		d->tiltback_variable = 0;
	} else {
		flywheel_stop(d);
	}
}

void flywheel_stop(data *d)
{
	// Just entirely restore the app settings
	beep_on(d, 1);
	d->is_flywheel_mode = false;
	VESC_IF->set_cfg_float(CFG_PARAM_l_min_erpm + 100, -30000);
	VESC_IF->set_cfg_float(CFG_PARAM_l_max_erpm + 100, 30000);
	read_cfg_from_eeprom(d);
	configure(d);
}

// Handler for incoming app commands
static void on_command_received(unsigned char *buffer, unsigned int len) {
	data *d = (data*)ARG;
	uint8_t magicnr = buffer[0];
	uint8_t command = buffer[1];

	if(len < 2){
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("Float App: Missing Args\n");
		}
		return;
	}
	if (magicnr != 101) {
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("Float App: Wrong magic number %d\n", magicnr);
		}
		return;
	}

	switch(command) {
		case FLOAT_COMMAND_GET_INFO: {
			int32_t ind = 0;
			uint8_t send_buffer[10];
			send_buffer[ind++] = 101;	// magic nr.
			send_buffer[ind++] = 0x0;	// command ID
			send_buffer[ind++] = (uint8_t) (10 * APPCONF_FLOAT_VERSION);
			send_buffer[ind++] = 1;     // build number
			send_buffer[ind++] = d->float_conf.led_type;
			VESC_IF->send_app_data(send_buffer, ind);
			return;
		}
		case FLOAT_COMMAND_GET_RTDATA: {
			send_realtime_data(d);
			return;
		}
		case FLOAT_COMMAND_RT_TUNE: {
			cmd_runtime_tune(d, &buffer[2], len - 2);
			return;
		}
		case FLOAT_COMMAND_TUNE_OTHER: {
			if (len >= 14) {
				cmd_runtime_tune_other(d, &buffer[2], len - 2);
			}
			else {
				if (!VESC_IF->app_is_output_disabled()) {
					VESC_IF->printf("Float App: Command length incorrect (%d)\n", len);
				}
			}
			return;
		}
		case FLOAT_COMMAND_TUNE_TILT: {
			if (len >= 10) {
				cmd_runtime_tune_tilt(d, &buffer[2], len - 2);
			}
			else {
				if (!VESC_IF->app_is_output_disabled()) {
					VESC_IF->printf("Float App: Command length incorrect (%d)\n", len);
				}
			}
			return;
		}
		case FLOAT_COMMAND_RC_MOVE: {
			if (len == 6) {
				cmd_rc_move(d, &buffer[2]);
			}
			else {
				if (!VESC_IF->app_is_output_disabled()) {
					VESC_IF->printf("Float App: Command length incorrect (%d)\n", len);
				}
			}
			return;
		}
		case FLOAT_COMMAND_CFG_RESTORE: {
			read_cfg_from_eeprom(d);
			VESC_IF->set_cfg_float(CFG_PARAM_IMU_mahony_kp + 100, d->float_conf.mahony_kp);
			return;
		}
		case FLOAT_COMMAND_TUNE_DEFAULTS: {
			cmd_tune_defaults(d);
			VESC_IF->set_cfg_float(CFG_PARAM_IMU_mahony_kp + 100, d->float_conf.mahony_kp);
			return;
		}
		case FLOAT_COMMAND_CFG_SAVE: {
			write_cfg_to_eeprom(d);
			return;
		}
		case FLOAT_COMMAND_PRINT_INFO: {
			cmd_print_info(d);
			return;
		}
		case FLOAT_COMMAND_GET_ALLDATA: {
			if (len == 3) {
				cmd_send_all_data(d, buffer[2]);
			}
                        else {
                                if (!VESC_IF->app_is_output_disabled()) {
                                        VESC_IF->printf("Float App: Command length incorrect (%d)\n", len);
                                }
                        }
			return;
		}
		case FLOAT_COMMAND_EXPERIMENT: {
			cmd_experiment(d, &buffer[2]);
			return;
		}
		case FLOAT_COMMAND_LOCK: {
			cmd_lock(d, &buffer[2]);
			return;
		}
		case FLOAT_COMMAND_HANDTEST: {
			cmd_handtest(d, &buffer[2]);
			return;
		}
		case FLOAT_COMMAND_BOOSTER: {
			if (len == 6) {
				cmd_booster(d, &buffer[2]);
			}
			else {
				if (!VESC_IF->app_is_output_disabled()) {
					VESC_IF->printf("Float App: Command length incorrect (%d)\n", len);
				}
			}
			return;
		}
		case FLOAT_COMMAND_FLYWHEEL: {
			if (len >= 8) {
				cmd_flywheel_toggle(d, &buffer[2], len-2);
			}
			else {
				if (!VESC_IF->app_is_output_disabled()) {
					VESC_IF->printf("Float App: Command length incorrect (%d)\n", len);
				}
			}
			return;
		}
		case FLOAT_COMMAND_HAPTIC: {
			if (len >= 6) {
				cmd_haptic_config(d, &buffer[2], len-2);
			}
			else {
				if (!VESC_IF->app_is_output_disabled()) {
					VESC_IF->printf("Float App: Command length incorrect (%d)\n", len);
				}
			}
			return;
		}
		case FLOAT_COMMAND_LCM_POLL: {
			cmd_lcm_poll(d, &buffer[2], len-2);
			return;
		}
		case FLOAT_COMMAND_LIGHT_INFO: {
			cmd_light_info(d);
			return;
		}
		case FLOAT_COMMAND_LIGHT_CTRL: {
			cmd_light_ctrl(d, &buffer[2], len-2);
			return;
		}
		case FLOAT_COMMAND_LCM_INFO: {
			cmd_lcm_info(d);
			return;
		}
		case FLOAT_COMMAND_CHARGESTATE: {
			cmd_chargestate(d, &buffer[2], len-2);
			return;
		}
		case FLOAT_COMMAND_GET_BATTERY: {
			cmd_send_battery();
			return;
		}
		default: {
			if (!VESC_IF->app_is_output_disabled()) {
				VESC_IF->printf("Float App: Unknown command received %d vs %d\n", command, FLOAT_COMMAND_PRINT_INFO);
			}
		}
	}
}

// Register get_debug as a lisp extension
static lbm_value ext_bal_dbg(lbm_value *args, lbm_uint argn) {
	if (argn != 1 || !VESC_IF->lbm_is_number(args[0])) {
		return VESC_IF->lbm_enc_sym_eerror;
	}

	return VESC_IF->lbm_enc_float(app_float_get_debug(VESC_IF->lbm_dec_as_i32(args[0])));
}

// Called from Lisp on init to pass in the version info of the firmware
static lbm_value ext_set_fw_version(lbm_value *args, lbm_uint argn) {
	data *d = (data*)ARG;
	if (argn > 2) {
		d->fw_version_major = VESC_IF->lbm_dec_as_i32(args[0]);
		d->fw_version_minor = VESC_IF->lbm_dec_as_i32(args[1]);
		d->fw_version_beta = VESC_IF->lbm_dec_as_i32(args[2]);
	}
	//VESC_IF->printf("Version is set: %d.%d [%d]\n", d->fw_version_major, d->fw_version_minor, d->fw_version_beta);
	return VESC_IF->lbm_enc_sym_true;
}

// Called from Lisp periodically to pass in the battery level
static lbm_value ext_set_batt_level(lbm_value *args, lbm_uint argn) {
	data *d = (data*)ARG;
	if (argn > 0) {
		// store battery level as 0..100 8-bit integer
		d->battery_level = VESC_IF->lbm_dec_as_float(args[0]) * 100;
	}
	return VESC_IF->lbm_enc_sym_true;
}

// These functions are used to send the config page to VESC Tool
// and to make persistent read and write work
static int get_cfg(uint8_t *buffer, bool is_default) {
	data *d = (data*)ARG;
	float_config *cfg = VESC_IF->malloc(sizeof(float_config));

	*cfg = d->float_conf;

	if (is_default) {
		confparser_set_defaults_float_config(cfg);
	}

	int res = confparser_serialize_float_config(buffer, cfg);
	VESC_IF->free(cfg);

	return res;
}

static bool set_cfg(uint8_t *buffer) {
	data *d = (data*)ARG;

	// don't let users use the Float Cfg "write" button in flywheel mode
	if (d->is_flywheel_mode || d->do_handtest)
		return false;

	bool res = confparser_deserialize_float_config(buffer, &(d->float_conf));

	// Store to EEPROM
	if (res) {
		write_cfg_to_eeprom(d);
		configure(d);
	}

	return res;
}

static int get_cfg_xml(uint8_t **buffer) {
	// Note: As the address of data_float_config_ is not known
	// at compile time it will be relative to where it is in the
	// linked binary. Therefore we add PROG_ADDR to it so that it
	// points to where it ends up on the STM32.
	*buffer = data_float_config_ + PROG_ADDR;
	return DATA_FLOAT_CONFIG__SIZE;
}

// Called when code is stopped
static void stop(void *arg) {
	data *d = (data*)arg;
	VESC_IF->imu_set_read_callback(NULL);
	VESC_IF->set_app_data_handler(NULL);
	VESC_IF->conf_custom_clear_configs();
	VESC_IF->request_terminate(d->thread);
	if (!VESC_IF->app_is_output_disabled()) {
		VESC_IF->printf("Float App Terminated");
	}	
	
	led_stop(&d->led_data);

	VESC_IF->free(d);
}

INIT_FUN(lib_info *info) {
	INIT_START
	if (!VESC_IF->app_is_output_disabled()) {
		VESC_IF->printf("Init Float v%.1fd\n", (double)APPCONF_FLOAT_VERSION);
	}

	data *d = VESC_IF->malloc(sizeof(data));
	memset(d, 0, sizeof(data));
	if (!d) {
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("Float App: Out of memory, startup failed!");
		}
		return false;
	}

	read_cfg_from_eeprom(d);

	info->stop_fun = stop;	
	info->arg = d;
	
	VESC_IF->conf_custom_add_config(get_cfg, set_cfg, get_cfg_xml);

	configure(d);

	if ((d->float_conf.is_beeper_enabled) || (d->float_conf.inputtilt_remote_type != INPUTTILT_PPM)) {
		beeper_init();
	}

	VESC_IF->ahrs_init_attitude_info(&d->m_att_ref);
	d->m_att_ref.acc_confidence_decay = 0.1;
	d->m_att_ref.kp = 0.2;

	VESC_IF->imu_set_read_callback(imu_ref_callback);

	d->thread = VESC_IF->spawn(float_thd, 2048, "Float Main", d);

	VESC_IF->set_app_data_handler(on_command_received);
	VESC_IF->lbm_add_extension("ext-float-dbg", ext_bal_dbg);
	VESC_IF->lbm_add_extension("ext-set-fw-version", ext_set_fw_version);
	VESC_IF->lbm_add_extension("ext-set-batt-level", ext_set_batt_level);

	return true;
}
