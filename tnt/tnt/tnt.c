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

#include "conf/datatypes.h"
#include "conf/confparser.h"
#include "conf/confxml.h"
#include "conf/buffer.h"
#include "conf/conf_default.h"

#include <math.h>
#include <string.h>

#define ACCEL_ARRAY_SIZE1 10 // For Tration Control acceleration average
#define ERPM_ARRAY_SIZE1 250 // For traction control erpm tracking


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
	FAULT_ANGLE_PITCH = 6,	// skipped 5 for compatibility
	FAULT_ANGLE_ROLL = 7,
	FAULT_SWITCH_HALF = 8,
	FAULT_SWITCH_FULL = 9,
	FAULT_DUTY = 10, 		// unused but kept for compatibility
	FAULT_STARTUP = 11,
	FAULT_REVERSE = 12,
	FAULT_QUICKSTOP = 13,
	DISABLED = 15
} FloatState;

typedef enum {
	CENTERING = 0,
	REVERSESTOP,
    	TILTBACK_NONE,
	TILTBACK_DUTY,
	TILTBACK_HV,
	TILTBACK_LV,
	TILTBACK_TEMP
} SetpointAdjustmentType;

typedef enum {
	OFF = 0,
	HALF,
	ON
} SwitchState;

typedef struct{
	float a0, a1, a2, b1, b2;
	float c1, c2;
	float x0, x1, x2, y1, y2;
	float z1, z2;
} Biquad;

typedef enum {
	BQ_LOWPASS,
	BQ_HIGHPASS
} BiquadType;

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

	// Buzzer
	int beep_num_left;
	int beep_duration;
	int beep_countdown;
	bool buzzer_enabled;

	// Config values
	float loop_time_seconds;
	unsigned int start_counter_clicks, start_counter_clicks_max;
	float startup_pitch_trickmargin, startup_pitch_tolerance;
	float startup_step_size;
	float tiltback_duty_step_size, tiltback_hv_step_size, tiltback_lv_step_size, tiltback_return_step_size, tiltback_ht_step_size;
	float inputtilt_ramped_step_size, inputtilt_step_size, noseangling_step_size;
	float mc_max_temp_fet, mc_max_temp_mot;
	float mc_current_max, mc_current_min, max_continuous_current;
	bool current_beeping;
	bool duty_beeping;

	// Feature: True Pitch
	ATTITUDE_INFO m_att_ref;

	// Runtime values read from elsewhere
	float pitch_angle, last_pitch_angle, roll_angle, abs_roll_angle, last_gyro_y;
 	float true_pitch_angle;
	float gyro[3];
	float duty_cycle, abs_duty_cycle;
	float erpm, abs_erpm, avg_erpm, last_erpm;
	float motor_current;
	float adc1, adc2;
	float throttle_val;
	float max_duty_with_margin;
	SwitchState switch_state;

	// Rumtime state values
	FloatState state;
	float proportional;
	float pid_prop, pid_rate, pid_mod;
	float last_proportional, abs_proportional;
	float pid_value;
	float setpoint, setpoint_target, setpoint_target_interpolated;
	float inputtilt_interpolated, noseangling_interpolated;
	float filtered_current;
	SetpointAdjustmentType setpointAdjustmentType;
	float current_time, last_time, diff_time, loop_overshoot; // Seconds
	float disengage_timer, nag_timer; // Seconds
	float idle_voltage;
	float filtered_loop_overshoot, loop_overshoot_alpha, filtered_diff_time;
	float fault_angle_pitch_timer, fault_angle_roll_timer, fault_switch_timer, fault_switch_half_timer; // Seconds
	float motor_timeout_seconds;
	float brake_timeout; // Seconds
	float overcurrent_timer, tb_highvoltage_timer;
	float switch_warn_buzz_erpm;
	float quickstop_erpm;
	bool traction_control;

	// Feature: Simple start
	bool enable_simple_start;

	// Feature: Soft Start
	float softstart_pid_limit, softstart_ramp_step_size;

	// Brake Amp Rate Limiting:
	float pid_brake_increment;

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
	float atr_filtered_current;
	Biquad atr_current_biquad;
	
	// Feature: Surge
	float surge_timer;			//Timer to monitor surge cycle and period
	bool surge;				//Identifies surge state which drives duty to max
	float differential;			//Pitch differential
	float surge_diffcount;			//Counter to watch for continuous start angle speed or else reset to zero
	
	//Traction Control
	float wheelslip_timeron;
	float wheelslip_timeroff;
	float wheelslip_accelstartval;
	bool wheelslip_highaccelon1;
	bool wheelslip_highaccelon2;
	float wheelslip_lasterpm;
	float wheelslip_erpm;
	float accelhist1[ACCEL_ARRAY_SIZE1];
	float accelavg1;
	int accelidx1;
	float erpmhist1[ERPM_ARRAY_SIZE1];
	float erpmavg1;
	int erpmidx1;
	
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
	
	//Debug
	float debug1, debug2, debug3, debug4, debug5, debug6, debug7, debug8, debug9, debug10, debug11;

	// Log values
	float float_setpoint, float_inputtilt;

} data;

static void brake(data *d);
static void set_current(data *d, float current);

/**
 * BUZZER / BEEPER on Servo Pin
 */
const VESC_PIN buzzer_pin = VESC_PIN_PPM;

#define EXT_BUZZER_ON()  VESC_IF->io_write(buzzer_pin, 1)
#define EXT_BUZZER_OFF() VESC_IF->io_write(buzzer_pin, 0)

void buzzer_init()
{
	VESC_IF->io_set_mode(buzzer_pin, VESC_PIN_MODE_OUTPUT);
}

void buzzer_update(data *d)
{
	if (d->buzzer_enabled && (d->beep_num_left > 0)) {
		d->beep_countdown--;
		if (d->beep_countdown <= 0) {
			d->beep_countdown = d->beep_duration;
			d->beep_num_left--;	
			if (d->beep_num_left & 0x1)
				EXT_BUZZER_ON();
			else
				EXT_BUZZER_OFF();
		}
	}
}

void buzzer_enable(data *d, bool enable)
{
	d->buzzer_enabled = enable;
	if (!enable) {
		EXT_BUZZER_OFF();
	}
}

void beep_alert(data *d, int num_beeps, bool longbeep)
{
	if (!d->buzzer_enabled)
		return;
	if (d->beep_num_left == 0) {
		d->beep_num_left = num_beeps * 2 + 1;
		d->beep_duration = longbeep ? 300 : 80;
		d->beep_countdown = d->beep_duration;
	}
}

void beep_off(data *d, bool force)
{
	// don't mess with the buzzer if we're in the process of doing a multi-beep
	if (force || (d->beep_num_left == 0))
		EXT_BUZZER_OFF();
}

void beep_on(data *d, bool force)
{
	if (!d->buzzer_enabled)
		return;
	// don't mess with the buzzer if we're in the process of doing a multi-beep
	if (force || (d->beep_num_left == 0))
		EXT_BUZZER_ON();
}

// Utility Functions
// Biquad 1 is for current Biquad 2 is for pitch
static float biquad_process1(Biquad *biquad, float in) {
    float out = in * biquad->a0 + biquad->c1;
    biquad->c1 = in * biquad->a1 + biquad->c2 - biquad->b1 * out;
    biquad->c2 = in * biquad->a2 - biquad->b2 * out;
    return out;
}

static void biquad_config1(Biquad *biquad, BiquadType type, float Fc) {
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

static void biquad_reset1(Biquad *biquad) {
	biquad->c1 = 0;
	biquad->c2 = 0;
}

static float biquad_process2(Biquad *biquad, float in) {
    float out = in * biquad->x0 + biquad->z1;
    biquad->z1 = in * biquad->x1 + biquad->z2 - biquad->y1 * out;
    biquad->z2 = in * biquad->x2 - biquad->y2 * out;
    return out;
}

static void biquad_config2(Biquad *biquad, BiquadType type, float Fc) {
	float K = tanf(M_PI * Fc);	// -0.0159;
	float Q = 0.5; // maximum sharpness (0.5 = maximum smoothness)
	float norm = 1 / (1 + K / Q + K * K);
	if (type == BQ_LOWPASS) {
		biquad->x0 = K * K * norm;
		biquad->x1 = 2 * biquad->x0;
		biquad->x2 = biquad->x0;
	}
	else if (type == BQ_HIGHPASS) {
		biquad->x0 = 1 * norm;
		biquad->x1 = -2 * biquad->x0;
		biquad->x2 = biquad->x0;
	}
	biquad->y1 = 2 * (K * K - 1) * norm;
	biquad->y2 = (1 - K / Q + K * K) * norm;
}

static void biquad_reset2(Biquad *biquad) {
	biquad->z1 = 0;
	biquad->z2 = 0;
}

// First start only, set initial state
static void app_init(data *d) {
	if (d->state != DISABLED) {
		d->state = STARTUP;
	}
	d->buzzer_enabled = true;
	
	// Allow saving of odometer
	d->odometer_dirty = 0;
	d->odometer = VESC_IF->mc_get_odometer();
}

static void configure(data *d) {

	// This timer is used to determine how long the board has been disengaged / idle
	d->disengage_timer = d->current_time;

	// Set calculated values from config
	d->loop_time_seconds = 1.0 / d->tnt_conf.hertz;

	d->motor_timeout_seconds = d->loop_time_seconds * 20; // Times 20 for a nice long grace period

	d->startup_step_size = d->tnt_conf.startup_speed / d->tnt_conf.hertz;
	d->tiltback_duty_step_size = d->tnt_conf.tiltback_duty_speed / d->tnt_conf.hertz;
	d->tiltback_hv_step_size = d->tnt_conf.tiltback_hv_speed / d->tnt_conf.hertz;
	d->tiltback_lv_step_size = d->tnt_conf.tiltback_lv_speed / d->tnt_conf.hertz;
	d->tiltback_return_step_size = d->tnt_conf.tiltback_return_speed / d->tnt_conf.hertz;
	d->inputtilt_step_size = d->tnt_conf.inputtilt_speed / d->tnt_conf.hertz;
	d->tiltback_ht_step_size = d->tnt_conf.tiltback_ht_speed / d->tnt_conf.hertz;

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
	int mcm = d->mc_current_max;
	float mc_max_reduce = d->mc_current_max - mcm;
	if (mc_max_reduce >= 0.5) {
		// reduce the max current by X% to save that for torque tilt situations
		// less than 60 peak amps makes no sense though so I'm not allowing it
		d->mc_current_max = fmaxf(mc_max_reduce * d->mc_current_max, 60);
	}

	// min current is a positive value here!
	d->mc_current_min = fabsf(VESC_IF->get_cfg_float(CFG_PARAM_l_current_min));
	mcm = d->mc_current_min;
	float mc_min_reduce = fabsf(d->mc_current_min - mcm);
	if (mc_min_reduce >= 0.5) {
		// reduce the max current by X% to save that for torque tilt situations
		// less than 50 peak breaking amps makes no sense though so I'm not allowing it
		d->mc_current_min = fmaxf(mc_min_reduce * d->mc_current_min, 50);
	}

	// Decimals of abs-max specify max continuous current
	float max_abs = VESC_IF->get_cfg_float(CFG_PARAM_l_abs_current_max);
	int mabs = max_abs;
	d->max_continuous_current = (max_abs - mabs) * 100;
	if (d->max_continuous_current < 25) {
		// anything below 25A is suspicious and will be ignored!
		d->max_continuous_current = d->mc_current_max;
	}

	// Maximum amps change when braking
	d->pid_brake_increment = 5;
	if (d->pid_brake_increment < 0.1) {
		d->pid_brake_increment = 5;
	}

	d->max_duty_with_margin = VESC_IF->get_cfg_float(CFG_PARAM_l_max_duty) - 0.1;

	// Init Filters
	float loop_time_filter = 3.0; // Originally Parameter, now hard-coded to 3Hz
	d->loop_overshoot_alpha = 2.0 * M_PI * ((float)1.0 / (float)d->tnt_conf.hertz) *
				loop_time_filter / (2.0 * M_PI * (1.0 / (float)d->tnt_conf.hertz) *
						loop_time_filter + 1.0);
		
	float Fc1, Fc2; 
	Fc1 = 5.0 / (float)d->tnt_conf.hertz; 
	Fc2 = d->tnt_conf.pitch_filter / (float)d->tnt_conf.hertz; 
	biquad_config1(&d->atr_current_biquad, BQ_LOWPASS, Fc1);
	biquad_config2(&d->pitch_biquad, BQ_LOWPASS, Fc2);
	
	// Allows smoothing of Remote Tilt
	d->inputtilt_ramped_step_size = 0;

	// Speed above which to warn users about an impending full switch fault
	d->switch_warn_buzz_erpm = d->tnt_conf.is_footbuzz_enabled ? 2000 : 100000;

	// Speed below which we check for quickstop conditions
	d->quickstop_erpm = 200;

	// Reset loop time variables
	d->last_time = 0.0;
	d->filtered_loop_overshoot = 0.0;

	d->buzzer_enabled = d->tnt_conf.is_buzzer_enabled;
	if (d->tnt_conf.disable_pkg) {
		d->state = DISABLED;
		beep_alert(d, 3, false);
	}
	else {
		d->state = STARTUP;
		beep_alert(d, 1, false);
	}

	//initialize current and pitch arrays
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
		if (d->current[i]>d->current[i-1] && d->pitch[i]>d->pitch[i-1]) {
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
}

static void reset_vars(data *d) {
	// Clear accumulated values.
	d->last_proportional = 0;
	d->prop_smooth = 0;
	d->abs_prop_smooth = 0;
	// Set values for startup
	d->setpoint = d->pitch_angle;
	d->setpoint_target_interpolated = d->pitch_angle;
	d->setpoint_target = 0;
	if (d->inputtilt_interpolated != d->stickytilt_val || !(VESC_IF->get_ppm_age() < 1)) { 	// Persistent sticky tilt value if we are at value with remote connected
		d->inputtilt_interpolated = 0;			// Reset other values
	}
	d->setpointAdjustmentType = CENTERING;
	d->state = RUNNING;
	d->current_time = 0;
	d->last_time = 0;
	d->diff_time = 0;
	d->brake_timeout = 0;
	d->traction_control = false;
	d->pid_value = 0;
	d->pid_mod = 0;
	d->roll_pid_mod = 0;
	d->softstart_pid_limit = 0;
	d->startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance;
	d->atr_filtered_current = 0;
	biquad_reset1(&d->atr_current_biquad);
	biquad_reset2(&d->pitch_biquad);
	
	for (int i = 0; i < ACCEL_ARRAY_SIZE1; i++)
		d->accelhist1[i] = 0;
	d->accelidx1 = 0;
	d->accelavg1 = 0;
	
	for (int i = 0; i < ERPM_ARRAY_SIZE1; i++)
		d->erpmhist1[i] = 0;
	d->erpmidx1 = 0;
	d->erpmavg1 = 0;

	// Feature: click on start
	d->start_counter_clicks = d->start_counter_clicks_max;
	
	//Kalman
	d->P00 = 0;
	d->P01 = 0;
	d->P10 = 0;
	d->P11 = 0;
	d->bias = 0;
	d->pitch_smooth = d->pitch_angle;
	d->pitch_smooth_kalman = d->pitch_angle;
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
	switch(d->setpointAdjustmentType){
		case (CENTERING):
			return d->startup_step_size;
		case (TILTBACK_DUTY):
			return d->tiltback_duty_step_size;
		case (TILTBACK_HV):
			return d->tiltback_hv_step_size;
		case (TILTBACK_TEMP):
			return d->tiltback_ht_step_size;
		case (TILTBACK_LV):
			return d->tiltback_lv_step_size;
		case (TILTBACK_NONE):
			return d->tiltback_return_step_size;
		default:
			;
	}
	return 0;
}

// Read ADCs and determine switch state
static SwitchState check_adcs(data *d) {
	SwitchState sw_state;

	// Calculate switch state from ADC values
	if(d->tnt_conf.fault_adc1 == 0 && d->tnt_conf.fault_adc2 == 0){ // No Switch
		sw_state = ON;
	}else if(d->tnt_conf.fault_adc2 == 0){ // Single switch on ADC1
		if(d->adc1 > d->tnt_conf.fault_adc1){
			sw_state = ON;
		} else {
			sw_state = OFF;
		}
	}else if(d->tnt_conf.fault_adc1 == 0){ // Single switch on ADC2
		if(d->adc2 > d->tnt_conf.fault_adc2){
			sw_state = ON;
		} else {
			sw_state = OFF;
		}
	}else{ // Double switch
		if(d->adc1 > d->tnt_conf.fault_adc1 && d->adc2 > d->tnt_conf.fault_adc2){
			sw_state = ON;
		}else if(d->adc1 > d->tnt_conf.fault_adc1 || d->adc2 > d->tnt_conf.fault_adc2){
			// 5 seconds after stopping we allow starting with a single sensor (e.g. for jump starts)
			bool is_simple_start = d->tnt_conf.startup_simplestart_enabled &&
				(d->current_time - d->disengage_timer > 5);

			if (d->tnt_conf.fault_is_dual_switch || is_simple_start)
				sw_state = ON;
			else
				sw_state = HALF;
		}else{
			sw_state = OFF;
		}
	}

	if ((sw_state == OFF) && (d->state <= RUNNING_TILTBACK)) {
		if (d->abs_erpm > d->switch_warn_buzz_erpm) {
			// If we're at riding speed and the switch is off => ALERT the user
			// set force=true since this could indicate an imminent shutdown/nosedive
			beep_on(d, true);
		}
		else {
			// if we drop below riding speed stop buzzing
			beep_off(d, false);
		}
	}
	else {
		// if the switch comes back on we stop buzzing
		beep_off(d, false);
	}

	return sw_state;
}

// Fault checking order does not really matter. From a UX perspective, switch should be before angle.
static bool check_faults(data *d){
	bool disable_switch_faults = d->tnt_conf.fault_moving_fault_disabled &&
								 d->erpm > (d->tnt_conf.fault_adc_half_erpm * 2) && // Rolling forward (not backwards!)
								 fabsf(d->roll_angle) < 40; // Not tipped over

	// Check switch
	// Switch fully open
	if (d->switch_state == OFF) {
		if (!disable_switch_faults) {
			if((1000.0 * (d->current_time - d->fault_switch_timer)) > d->tnt_conf.fault_delay_switch_full){
				d->state = FAULT_SWITCH_FULL;
				return true;
			}
			// low speed (below 6 x half-fault threshold speed):
			else if ((d->abs_erpm < d->tnt_conf.fault_adc_half_erpm * 6)
				&& (1000.0 * (d->current_time - d->fault_switch_timer) > d->tnt_conf.fault_delay_switch_half)){
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

	// Switch partially open and stopped
	if(!d->tnt_conf.fault_is_dual_switch) {
		if((d->switch_state == HALF || d->switch_state == OFF) && fabsf(d->erpm) < d->tnt_conf.fault_adc_half_erpm){
			if ((1000.0 * (d->current_time - d->fault_switch_half_timer)) > d->tnt_conf.fault_delay_switch_half){
				d->state = FAULT_SWITCH_HALF;
				return true;
			}
		} else {
			d->fault_switch_half_timer = d->current_time;
		}
	}

	// Check roll angle
	if (fabsf(d->roll_angle) > d->tnt_conf.fault_roll) {
		if ((1000.0 * (d->current_time - d->fault_angle_roll_timer)) > d->tnt_conf.fault_delay_roll) {
			d->state = FAULT_ANGLE_ROLL;
			return true;
		}
	} else {
		d->fault_angle_roll_timer = d->current_time;
	}
	
	// Check pitch angle
	if ((fabsf(d->true_pitch_angle) > d->tnt_conf.fault_pitch) && (fabsf(d->inputtilt_interpolated) < 30)) {
		if ((1000.0 * (d->current_time - d->fault_angle_pitch_timer)) > d->tnt_conf.fault_delay_pitch) {
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
	
	if (input_voltage < d->tnt_conf.tiltback_hv) {
		d->tb_highvoltage_timer = d->current_time;
	}

	if (d->setpointAdjustmentType == CENTERING && d->setpoint_target_interpolated != d->setpoint_target) {
		// Ignore tiltback during centering sequence
		d->state = RUNNING;
	} else if (d->state == RUNNING_WHEELSLIP) {
		d->setpointAdjustmentType = TILTBACK_NONE;
	} else if (d->abs_duty_cycle > d->tnt_conf.tiltback_duty) {
		if (d->erpm > 0) {
			d->setpoint_target = d->tnt_conf.tiltback_duty_angle;
		} else {
			d->setpoint_target = -d->tnt_conf.tiltback_duty_angle;
		}
		d->setpointAdjustmentType = TILTBACK_DUTY;
		d->state = RUNNING_TILTBACK;
	} else if (d->abs_duty_cycle > 0.05 && input_voltage > d->tnt_conf.tiltback_hv) {
		beep_alert(d, 3, false);	// Triple-beep
		if (((d->current_time - d->tb_highvoltage_timer) > .5) ||
		   (input_voltage > d->tnt_conf.tiltback_hv + 1)) {
			// 500ms have passed or voltage is another volt higher, time for some tiltback
			if (d->erpm > 0){
				d->setpoint_target = d->tnt_conf.tiltback_hv_angle;
			} else {
				d->setpoint_target = -d->tnt_conf.tiltback_hv_angle;
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
		if(VESC_IF->mc_temp_fet_filtered() > (d->mc_max_temp_fet + 1)) {
			if(d->erpm > 0){
				d->setpoint_target = d->tnt_conf.tiltback_ht_angle;
			} else {
				d->setpoint_target = -d->tnt_conf.tiltback_ht_angle;
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
		if(VESC_IF->mc_temp_motor_filtered() > (d->mc_max_temp_mot + 1)) {
			if(d->erpm > 0){
				d->setpoint_target = d->tnt_conf.tiltback_ht_angle;
			} else {
				d->setpoint_target = -d->tnt_conf.tiltback_ht_angle;
			}
			d->setpointAdjustmentType = TILTBACK_TEMP;
			d->state = RUNNING_TILTBACK;
		}
		else {
			// The rider has 1 degree Celsius left before we start tilting back
			d->setpointAdjustmentType = TILTBACK_NONE;
			d->state = RUNNING;
		}
	} else if (d->abs_duty_cycle > 0.05 && input_voltage < d->tnt_conf.tiltback_lv) {
		beep_alert(d, 3, false);	// Triple-beep
		float abs_motor_current = fabsf(d->motor_current);
		float vdelta = d->tnt_conf.tiltback_lv - input_voltage;
		float ratio = vdelta * 20 / abs_motor_current;
		// When to do LV tiltback:
		// a) we're 2V below lv threshold
		// b) motor current is small (we cannot assume vsag)
		// c) we have more than 20A per Volt of difference (we tolerate some amount of vsag)
		if ((vdelta > 2) || (abs_motor_current < 5) || (ratio > 1)) {
			if (d->erpm > 0) {
				d->setpoint_target = d->tnt_conf.tiltback_lv_angle;
			} else {
				d->setpoint_target = -d->tnt_conf.tiltback_lv_angle;
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
		d->setpointAdjustmentType = TILTBACK_NONE;
		d->setpoint_target = 0;
		d->state = RUNNING;
	}
	if ((d->state == RUNNING_WHEELSLIP) && (d->abs_duty_cycle > d->max_duty_with_margin)) {
		d->setpoint_target = 0;
	}
	
	if (d->setpointAdjustmentType == TILTBACK_DUTY) {
		if (d->tnt_conf.is_dutybuzz_enabled || (d->tnt_conf.tiltback_duty_angle == 0)) {
			beep_on(d, true);
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

static void apply_noseangling(data *d){
	if (d->state != RUNNING_WHEELSLIP) {
		// Nose angle adjustment, add variable then constant tiltback
		float noseangling_target = 0;

		if (fabsf(d->erpm) > d->tnt_conf.tiltback_constant_erpm) {
			noseangling_target += d->tnt_conf.tiltback_constant * SIGN(d->erpm);
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
	d->setpoint += d->inputtilt_interpolated;
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
	VESC_IF->mc_set_brake_current(d->tnt_conf.brake_current);
}

static void set_current(data *d, float current){
	// Limit current output to configured max output
	if (current > 0 && current > VESC_IF->get_cfg_float(CFG_PARAM_l_current_max)) {
		current = VESC_IF->get_cfg_float(CFG_PARAM_l_current_max);
	} else if(current < 0 && current < VESC_IF->get_cfg_float(CFG_PARAM_l_current_min)) {
		current = VESC_IF->get_cfg_float(CFG_PARAM_l_current_min);
	}

	// Reset the timeout
	VESC_IF->timeout_reset();
	// Set the current delay
	VESC_IF->mc_set_current_off_delay(d->motor_timeout_seconds);
	// Set Current
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

static void check_surge(data *d, float new_pid_value){
	//Start Surge Code
	//Counter for high nose angle speed
	if (d->differential * SIGN(d->erpm) > d->tnt_conf.surge_startanglespeed / d->tnt_conf.hertz) {
		d->surge_diffcount += d->differential * SIGN(d->erpm);	// Add until diff limit. 
	} else if (d->differential * SIGN(d->erpm) < 0) { 	//Pitch is travelling back to center
		d->surge_diffcount = 0;				// reset
	}

	//Initialize Surge Cycle
	if ((d->surge_diffcount >= d->tnt_conf.surge_difflimit) && 		//Nose dip condition 
	     (SIGN(d->erpm) * d->proportional - d->tnt_conf.surge_difflimit > 0) &&	//Minimum angle for acceleration
	     (SIGN(d->proportional) == SIGN(d->erpm)) && 				//Not braking
	     (d->current_time - d->surge_timer > d->tnt_conf.surge_period) &&	//Not during an active surge period
	     (d->state != RUNNING_WHEELSLIP) &&				//Not during traction control
	     (d->setpointAdjustmentType != CENTERING)) { 		//Not during startup
		d->surge_timer = d->current_time; 			//Reset surge timer
		d->surge = true; 					//Indicates we are in the surge cycle of the surge period
		d->debug5 = 0;
	}

	//Conditions to stop surge and increment the duty cycle
	if (d->surge){	
		d->duty_cycle = SIGN(d->erpm); 					// Max duty during surge cycle	
		d->surge_diffcount = 0;						// Reset surge initialization counter
		//Conditions that will cause surge cycle to end
		if ((d->current_time - d->surge_timer > d->tnt_conf.surge_cycle) ||		//Outside the surge cycle portion of the surge period
		 (d->state == RUNNING_WHEELSLIP) ||						//In traction control
		 ((SIGN(d->erpm) * d->proportional - 0.05) < 0) ||			//The pitch is less than our minimum angle
		 (new_pid_value <= d->motor_current / d->tnt_conf.surge_currentmargin && SIGN(d->erpm) * d->differential < 0)) {
		 //PID current demand has lowered below our surge current / margin and the nose is lifting (to prevent nuisance trips)
			d->surge = false;
			d->pid_value = d->motor_current;	//This allows a smooth transition to PID current control
			if (d->current_time - d->surge_timer < d->tnt_conf.surge_cycle) { 	//If we are still in the surge cycle
				d->debug5 = d->current_time - d->surge_timer;	//Register how long the surge cycle lasted
			}
		}
	}
}

static void check_traction(data *d){
	float wheelslip_erpmfactor = d->tnt_conf.wheelslip_scaleaccel - fminf(d->tnt_conf.wheelslip_scaleaccel - 1, (d->tnt_conf.wheelslip_scaleaccel -1) * ( d->abs_erpm / d->tnt_conf.wheelslip_scaleerpm));
	
	int last_accelidx1 = d->accelidx1 - 1; // Identify the last cycles accel
	if (d->accelidx1 == 0) {
		last_accelidx1 = ACCEL_ARRAY_SIZE1 - 1;
	}
	
	int last_erpmidx = d->erpmidx1 + 2; // Identify ERPM from array size cycles ago, +1 in case we nned the extra cycle
	if (d->erpmidx1 > ERPM_ARRAY_SIZE1 - 1) {
		last_erpmidx = 0;
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
			//This section determines if the wheel has changed directions
			if (d->state == RUNNING_WHEELSLIP) { // skip this if we are already out of wheelslip to preserve debug values
				if (SIGN(d->wheelslip_lasterpm)!=SIGN(d->wheelslip_erpm) && SIGN(d->erpm)==SIGN(d->wheelslip_lasterpm)) {		
					//If the wheel slipped into reverse while braking, end wheelslip once the wheel is spinning in the right direction again
					d->state = RUNNING;
					d->wheelslip_timeroff = d->current_time;
					d->debug4 = 3333;
					d->debug8 = d->erpm;		
				}
			}
		}
	}	
	
	// Initiate traction control
	if ((SIGN(d->motor_current) * d->accelavg1 > d->tnt_conf.wheelslip_accelstart * wheelslip_erpmfactor) && 	// The wheel has broken free indicated by abnormally high acceleration in the direction of motor current
	   (d->state != RUNNING_WHEELSLIP) &&									// Not in traction control
	   (SIGN(d->motor_current) == SIGN(d->accelhist1[d->accelidx1])) &&				// a more precise condition than the first for current dirrention and erpm - last erpm
	   (SIGN(d->proportional) == SIGN(d->erpm)) &&							// Do not apply for braking because once we lose traction braking the erpm will change direction and the board will consider it acceleration anyway
	   (d->current_time - d->wheelslip_timeroff > .2)) {						// Did not recently wheel slip.
		d->state = RUNNING_WHEELSLIP;
		d->wheelslip_accelstartval = d->accelavg1;
		d->wheelslip_highaccelon1 = true; 	
		d->wheelslip_highaccelon2 = true; 	
		d->wheelslip_timeron = d->current_time;
		d->wheelslip_erpm = d->erpm;
		d->wheelslip_lasterpm = d->erpmhist1[last_erpmidx];
		d->debug6 = d->accelavg1;
		d->debug3 = d->erpmhist1[last_erpmidx];
		d->debug1 = 0;
		d->debug2 = wheelslip_erpmfactor;
		d->debug4 = 0;
		d->debug8 = 0;
		d->debug9 = d->erpm;
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
		if (d->abs_roll_angle > d->tnt_conf.brkroll3  && d->brkroll_count==3) {
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
		if (d->abs_roll_angle > d->tnt_conf.roll3  && d->roll_count == 3) {
			kp_min = d->tnt_conf.roll_kp3;
			kp_max = d->tnt_conf.roll_kp3;
			scale_angle_min = d->tnt_conf.roll3;
			scale_angle_max = 90;
		} else if (d->abs_roll_angle > d->tnt_conf.roll2  && d->roll_count>=2) {
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

static void imu_ref_callback(float *acc, float *gyro, float *mag, float dt) {
	UNUSED(mag);
	data *d = (data*)ARG;
	VESC_IF->ahrs_update_mahony_imu(gyro, acc, dt, &d->m_att_ref);
}

static void tnt_thd(void *arg) {
	data *d = (data*)arg;

	app_init(d);

	while (!VESC_IF->should_terminate()) {
		buzzer_update(d);

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
		// Filter current (Biquad)
		d->atr_filtered_current = biquad_process1(&d->atr_current_biquad, d->motor_current);
		
		// Get the IMU Values
		d->roll_angle = RAD2DEG_f(VESC_IF->ahrs_get_roll(&d->m_att_ref));
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
		
		// Get the motor values we want
		d->duty_cycle = VESC_IF->mc_get_duty_cycle_now();
		d->abs_duty_cycle = fabsf(d->duty_cycle);
		d->erpm = VESC_IF->mc_get_rpm();
		d->abs_erpm = fabsf(d->erpm);
		d->adc1 = VESC_IF->io_read_analog(VESC_PIN_ADC1);
		d->adc2 = VESC_IF->io_read_analog(VESC_PIN_ADC2); // Returns -1.0 if the pin is missing on the hardware
		if (d->adc2 < 0.0) {
			d->adc2 = 0.0;
		}

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

		//d->erpmavg1 += (d->erpm - d->erpmhist1[d->erpmidx1]) / ERPM_ARRAY_SIZE1;
		d->erpmhist1[d->erpmidx1] = d->erpm;
		d->erpmidx1++;
 		if (d->erpmidx1 == ERPM_ARRAY_SIZE1) {
			d->erpmidx1 = 0;
		}	
		
		float acceleration_raw = d->erpm - d->last_erpm;
		d->accelavg1 += (acceleration_raw - d->accelhist1[d->accelidx1]) / ACCEL_ARRAY_SIZE1;
		d->accelhist1[d->accelidx1] = acceleration_raw;
		d->accelidx1++;
 		if (d->accelidx1 == ACCEL_ARRAY_SIZE1) {
			d->accelidx1 = 0;
		}

		d->switch_state = check_adcs(d);

		// Log Values
		d->float_setpoint = d->setpoint;
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
					float threshold = d->tnt_conf.tiltback_lv + 5;
					if (bat_volts < threshold) {
						int beeps = (int)fminf(6, threshold - bat_volts);
						beep_alert(d, beeps + 1, true);
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
			// Check for faults
			if (check_faults(d)) {
				if (d->state == FAULT_SWITCH_FULL) {
					// dirty landings: add extra margin when rightside up
					d->startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance + d->startup_pitch_trickmargin;
					d->fault_angle_pitch_timer = d->current_time;
				}
				break;
			}
			d->odometer_dirty = 1;
			d->disengage_timer = d->current_time;

			// Calculate setpoint and interpolation
			calculate_setpoint_target(d);
			calculate_setpoint_interpolated(d);
			d->setpoint = d->setpoint_target_interpolated;
			apply_inputtilt(d); 
			apply_noseangling(d);

			// Do PID maths
			d->proportional = d->setpoint - d->pitch_angle;
			d->prop_smooth = d->setpoint - d->pitch_smooth_kalman;
			d->abs_prop_smooth = fabsf(d->prop_smooth);
			d->differential = d->proportional - d->last_proportional;
			new_pid_value = select_kp(d)*d->proportional;
			
			// Start Rate PID and Booster portion a few cycles later, after the start clicks have been emitted
			// this keeps the start smooth and predictable
			if (d->start_counter_clicks == 0) {
				// Rate P
				float rate_prop = -d->gyro[1];
				d->pid_mod = d->tnt_conf.kp_rate * rate_prop;
				
				// Apply Turn Boost
				if (d->roll_count > 0) {
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
			float current_limit;
			if (SIGN(d->proportional) != SIGN(d->erpm)) {
				current_limit = d->mc_current_min;
			}
			else {
				current_limit = d->mc_current_max; 
			}
			if (fabsf(new_pid_value) > current_limit) {
				new_pid_value = SIGN(new_pid_value) * current_limit;
			}
			else {
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
					}
				}
			}
			
			// Modifiers to PID control
			if (d->tnt_conf.is_traction_enabled) {
				check_drop(d);
				check_traction(d);
			}
			if (d->tnt_conf.is_surge_enabled){
			check_surge(d, new_pid_value);
			}
						
			d->last_proportional = d->proportional; // Moved here so turn boost can use last prop
			d->last_erpm = d->erpm; //moved here so last erpm can be used in traction control
				
			// PID value application
			if (d->state == RUNNING_WHEELSLIP) { //Reduce acceleration if we are in traction control
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
				d->pid_value = d->pid_value * 0.8 + new_pid_value * 0.2; // Normal application of PID current control
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
				set_dutycycle(d, d->duty_cycle); 		// Set the duty to surge
			} else {
				set_current(d, d->pid_value); 	// Set current as normal.
				d->surge = false;		// Don't re-engage surge if we have left surge cycle until new surge period
			}

			break;

		case (FAULT_ANGLE_PITCH):
		case (FAULT_ANGLE_ROLL):
		case (FAULT_REVERSE):
		case (FAULT_QUICKSTOP):
		case (FAULT_SWITCH_HALF):
		case (FAULT_SWITCH_FULL):
		case (FAULT_STARTUP):
			if (d->current_time - d->disengage_timer > 1800) {	// alert user after 30 minutes
				if (d->current_time - d->nag_timer > 60) {		// beep every 60 seconds
					d->nag_timer = d->current_time;
					float input_voltage = VESC_IF->mc_get_input_voltage_filtered();
					if (input_voltage > d->idle_voltage) {
						// don't beep if the voltage keeps increasing (board is charging)
						d->idle_voltage = input_voltage;
					}
					else {
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
				d->startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance;
			}

			check_odometer(d);

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
		case (DISABLED):;
			// no set_current, no brake_current
		default:;
		}

		// Delay between loops
		VESC_IF->sleep_us((uint32_t)((d->loop_time_seconds - roundf(d->filtered_loop_overshoot)) * 1000000.0));
	}
}

static void write_cfg_to_eeprom(data *d) {
	uint32_t ints = sizeof(tnt_config) / 4 + 1;
	uint32_t *buffer = VESC_IF->malloc(ints * sizeof(uint32_t));
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
	}

	// Emit 1 short beep to confirm writing all settings to eeprom
	beep_alert(d, 1, 0);
}

static void read_cfg_from_eeprom(data *d) {
	// Read config from EEPROM if signature is correct
	eeprom_var v;
	uint32_t ints = sizeof(tnt_config) / 4 + 1;
	uint32_t *buffer = VESC_IF->malloc(ints * sizeof(uint32_t));
	bool read_ok = VESC_IF->read_eeprom_var(&v, 0);
	if (read_ok && v.as_u32 == TNT_CONFIG_SIGNATURE) {
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
		memcpy(&(d->tnt_conf), buffer, sizeof(tnt_config));

		if (d->tnt_conf.version != APPCONF_TNT_VERSION) {
			if (!VESC_IF->app_is_output_disabled()) {
				VESC_IF->printf("Version change since last config write (%.1f vs %.1f) !",
								(double)d->tnt_conf.version,
								(double)APPCONF_TNT_VERSION);
			}
			d->tnt_conf.version = APPCONF_TNT_VERSION;
		}
	} else {
		confparser_set_defaults_tnt_config(&(d->tnt_conf));
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("Package Error: Reverting to default config!\n");
		}
	}

	VESC_IF->free(buffer);
}

static float app_tnt_get_debug(int index) {
	data *d = (data*)ARG;

	switch(index){
		case(1):
			return d->setpoint;
		case(2):
			return d->float_setpoint;
		case(3):
			return d->filtered_current;
		case(4):
			return d->pid_mod;
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
			return 0;
		case(15):
			return 0;
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
	FLOAT_COMMAND_TUNE_DEFAULTS = 3,// set tune to defaults (no eeprom)
	FLOAT_COMMAND_CFG_SAVE = 4,		// save config to eeprom
	FLOAT_COMMAND_CFG_RESTORE = 5,	// restore config from eeprom
	FLOAT_COMMAND_PRINT_INFO = 9,	// print verbose info
	FLOAT_COMMAND_GET_ALLDATA = 10,	// send all data, compact
	FLOAT_COMMAND_EXPERIMENT = 11,  // generic cmd for sending data, used for testing/tuning new features
} float_commands;

static void send_realtime_data(data *d){
	#define BUFSIZE 100
	uint8_t send_buffer[BUFSIZE];
	int32_t ind = 0;
	send_buffer[ind++] = 111;//Magic Number
	send_buffer[ind++] = FLOAT_COMMAND_GET_RTDATA;

	// RT Data
	buffer_append_float32_auto(send_buffer, VESC_IF->mc_get_input_voltage_filtered(), &ind);
	buffer_append_float32_auto(send_buffer, d->debug11, &ind); //rollkp
	buffer_append_float32_auto(send_buffer, d->pitch_smooth_kalman, &ind); //smooth pitch	
	buffer_append_float32_auto(send_buffer, d->pitch_angle, &ind);
	buffer_append_float32_auto(send_buffer, d->roll_angle, &ind);
	buffer_append_float32_auto(send_buffer, d->debug10, &ind); // scaled angle P
	buffer_append_float32_auto(send_buffer, d->atr_filtered_current, &ind); // current
	
	send_buffer[ind++] = (d->state & 0xF) + (d->setpointAdjustmentType << 4);
	send_buffer[ind++] = d->switch_state;
	buffer_append_float32_auto(send_buffer, d->adc1, &ind);
	buffer_append_float32_auto(send_buffer, d->adc2, &ind);

	buffer_append_float32_auto(send_buffer, d->float_setpoint, &ind);
	buffer_append_float32_auto(send_buffer, d->float_inputtilt, &ind);
	buffer_append_float32_auto(send_buffer, d->throttle_val, &ind);
	
	// DEBUG
	buffer_append_float32_auto(send_buffer, d->current_time - d->surge_timer , &ind); //Temporary debug. Time since last surge
	buffer_append_float32_auto(send_buffer, d->debug5, &ind); //Temporary debug. Duration last surge cycle time
	
	buffer_append_float32_auto(send_buffer, d->current_time - d->wheelslip_timeron , &ind); //Temporary debug. Time since last wheelslip
	buffer_append_float32_auto(send_buffer, d->wheelslip_timeroff - d->wheelslip_timeron , &ind); //Temporary debug. Duration last wheelslip
	buffer_append_float32_auto(send_buffer, d->debug1, &ind); //Temporary debug. Time until start accel reversed
	buffer_append_float32_auto(send_buffer, d->debug7, &ind); //Temporary debug. Time until start accel reduced	
	buffer_append_float32_auto(send_buffer, d->debug2, &ind); //Temporary debug. wheelslip erpm factor
	buffer_append_float32_auto(send_buffer, d->debug6, &ind); //Temporary debug. accel at wheelslip start
	buffer_append_float32_auto(send_buffer, d->debug3, &ind); //Temporary debug. erpm before wheel slip
	buffer_append_float32_auto(send_buffer, d->debug9, &ind); //Temporary debug. erpm at wheel slip
	buffer_append_float32_auto(send_buffer, d->debug4, &ind); //Temporary debug. Debug condition or last accel
	buffer_append_float32_auto(send_buffer, d->debug8, &ind); //Temporary debug. accel at wheelslip end

	if (ind > BUFSIZE) {
		VESC_IF->printf("BUFSIZE too small...\n");
	}
	VESC_IF->send_app_data(send_buffer, ind);
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
	if (magicnr != 111) {
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("Float App: Wrong magic number %d\n", magicnr);
		}
		return;
	}

	switch(command) {
		case FLOAT_COMMAND_GET_INFO: {
			int32_t ind = 0;
			uint8_t send_buffer[10];
			send_buffer[ind++] = 111;	// magic nr.
			send_buffer[ind++] = 0x0;	// command ID
			send_buffer[ind++] = (uint8_t) (10 * APPCONF_TNT_VERSION);
			send_buffer[ind++] = 1;
			VESC_IF->send_app_data(send_buffer, ind);
			return;
		}
		case FLOAT_COMMAND_GET_RTDATA: {
			send_realtime_data(d);
			return;
		}
		case FLOAT_COMMAND_CFG_RESTORE: {
			read_cfg_from_eeprom(d);
			VESC_IF->set_cfg_float(CFG_PARAM_IMU_mahony_kp + 100, d->tnt_conf.mahony_kp);
			return;
		}
		case FLOAT_COMMAND_TUNE_DEFAULTS: {
			//cmd_tune_defaults(d);
			VESC_IF->set_cfg_float(CFG_PARAM_IMU_mahony_kp + 100, d->tnt_conf.mahony_kp);
			return;
		}
		case FLOAT_COMMAND_CFG_SAVE: {
			write_cfg_to_eeprom(d);
			return;
		}
		case FLOAT_COMMAND_PRINT_INFO: {
			//cmd_print_info(d);
			return;
		}
		case FLOAT_COMMAND_GET_ALLDATA: {
			if (len == 3) {
				//cmd_send_all_data(d, buffer[2]);
			}
                        else {
                                if (!VESC_IF->app_is_output_disabled()) {
                                        VESC_IF->printf("Float App: Command length incorrect (%d)\n", len);
                                }
                        }
			return;
		}
		case FLOAT_COMMAND_EXPERIMENT: {
			//cmd_experiment(d, &buffer[2]);
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
	//VESC_IF->printf("Version is set: %d.%d [%d]\n", d->fw_version_major, d->fw_version_minor, d->fw_version_beta);
	return VESC_IF->lbm_enc_sym_true;
}

// These functions are used to send the config page to VESC Tool
// and to make persistent read and write work
static int get_cfg(uint8_t *buffer, bool is_default) {
	data *d = (data*)ARG;
	tnt_config *cfg = VESC_IF->malloc(sizeof(tnt_config));

	*cfg = d->tnt_conf;

	if (is_default) {
		confparser_set_defaults_tnt_config(cfg);
	}

	int res = confparser_serialize_tnt_config(buffer, cfg);
	VESC_IF->free(cfg);

	return res;
}

static bool set_cfg(uint8_t *buffer) {
	data *d = (data*)ARG;
	bool res = confparser_deserialize_tnt_config(buffer, &(d->tnt_conf));

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
	data *d = (data*)arg;
	VESC_IF->imu_set_read_callback(NULL);
	VESC_IF->set_app_data_handler(NULL);
	VESC_IF->conf_custom_clear_configs();
	VESC_IF->request_terminate(d->thread);
	if (!VESC_IF->app_is_output_disabled()) {
		VESC_IF->printf("Float App Terminated");
	}
	VESC_IF->free(d);
}

INIT_FUN(lib_info *info) {
	INIT_START
	if (!VESC_IF->app_is_output_disabled()) {
		VESC_IF->printf("Init Float v%.1f - Surge3\n", (double)APPCONF_TNT_VERSION);
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

	if ((d->tnt_conf.is_buzzer_enabled) || (d->tnt_conf.inputtilt_remote_type != INPUTTILT_PPM)) {
		buzzer_init();
	}

	VESC_IF->ahrs_init_attitude_info(&d->m_att_ref);
	d->m_att_ref.acc_confidence_decay = 0.1;
	d->m_att_ref.kp = 0.2;

	VESC_IF->imu_set_read_callback(imu_ref_callback);

	d->thread = VESC_IF->spawn(tnt_thd, 2048, "Float Main", d);

	VESC_IF->set_app_data_handler(on_command_received);
	VESC_IF->lbm_add_extension("ext-tnt-dbg", ext_bal_dbg);
	VESC_IF->lbm_add_extension("ext-set-fw-version", ext_set_fw_version);

	return true;
}
