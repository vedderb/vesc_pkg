// Copyright 2019 - 2022 Mitch Lustig
// Copyright 2022 Benjamin Vedder <benjamin@vedder.se>
// Copyright 2023 Michael Silberstein
// Copyright 2024 Lukas Hrazky
//
// This file is part of the Trick and Trail VESC package.
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

#include "vesc_c_if.h"

#include "runtime.h"
#include "footpad_sensor.h"
#include "motor_data_tnt.h"
#include "state_tnt.h"
#include "pid.h"
#include "setpoint.h"
#include "kalman.h"
#include "traction.h"
#include "surge.h"
#include "utils_tnt.h"
#include "remote_input.h"
#include "foc_tone.h"
#include "ridetrack.h"
#include "drop.h"

#include "conf/datatypes.h"
#include "conf/confparser.h"
#include "conf/confxml.h"
#include "conf/buffer.h"
#include "conf/conf_general.h"

#include <math.h>
#include <string.h>

HEADER

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

	//Essentials for an operating board with Trick and Trail control algorithm
  	MotorData motor;			//Motor data
	State state;				//Runtime state values
	PidData pid;				//control variables
	PidDebug pid_dbg;			//additional control variable information
	SetpointData spd;			//Board angle changes
	RuntimeData rt; 			//runtime data (IMU, times, etc)
	FootpadSensor footpad_sensor;		//Footpad states and detection
	YawData yaw;				//Yaw change data
	YawDebugData yaw_dbg;			//Yaw debug

	// Throttle/Brake Curves for Pitch Roll and Yaw
	KpArray accel_kp;
	KpArray brake_kp;
	KpArray roll_accel_kp;
	KpArray roll_brake_kp;
	KpArray yaw_accel_kp;
	KpArray yaw_brake_kp;

	//Non-essential Features
	ToneData tone;				//FOC play tones feature
	ToneConfigs tone_config;		//Configurations for different beep profiles
	RemoteData remote;			//Read and apply input remote
	StickyTiltData st_tilt;			//Use input remote to lock in board angle
	SurgeData surge;			//Temporary duty control mode
	SurgeDebug surge_dbg;			//Surge debug info
	TractionData traction;			//Traction control for accelerating
	TractionDebug traction_dbg;		//traction control debug info
	BrakingData braking;			//Traction control for braking
	BrakingDebug braking_dbg;		//Braking debug info
	RideTrackData ridetrack;		//Trip tracking data
	DropData drop; 				//Drop tracking
	DropDebug drop_dbg; 			//Drop debug 
} data;

static void configure(data *d) {
	state_init(&d->state, d->tnt_conf.disable_pkg);				//Initialize
	configure_runtime(&d->rt, &d->tnt_conf);				//runtime data (IMU, times, etc)
	configure_pid(&d->pid, &d->tnt_conf);					//control variables 
	setpoint_configure(&d->spd, &d->tnt_conf);				//setpoint adjustment
	configure_remote_features(&d->tnt_conf, &d->remote, &d->st_tilt);	//remote input
	motor_data_configure(&d->motor, &d->tnt_conf);				//motor data
	configure_surge(&d->surge, &d->tnt_conf);				//surge feature
	configure_traction(&d->traction, &d->braking, &d->tnt_conf, 
		&d->traction_dbg, &d->braking_dbg); 				//traction control and traction braking
	tone_configure_all(&d->tone_config, &d->tnt_conf, &d->tone);		//FOC play tones
	configure_ride_tracking(&d->ridetrack, &d->tnt_conf);			//Ride tracking
	reset_ride_tracking_on_configure(&d->ridetrack, &d->tnt_conf, &d->traction_dbg, &d->drop_dbg);	//Reset current trip information
	configure_ride_tracking(&d->ridetrack, &d->tnt_conf);			//Ride tracking
	configure_drop(&d->drop,&d->tnt_conf);					//Drop detection
	
	//initialize pitch arrays for acceleration
	angle_kp_reset(&d->accel_kp);
	pitch_kp_configure(&d->tnt_conf, &d->accel_kp, 1);
	
	//initialize pitch arrays for braking
	if (d->tnt_conf.brake_curve) {
		angle_kp_reset(&d->brake_kp);
		pitch_kp_configure(&d->tnt_conf, &d->brake_kp, 2);
	}
	
	//Check for roll inputs
	roll_kp_configure(&d->tnt_conf, &d->roll_accel_kp, 1);
	roll_kp_configure(&d->tnt_conf, &d->roll_brake_kp, 2);

	//Check for yaw inputs
	yaw_kp_configure(&d->tnt_conf, &d->yaw_accel_kp, 1);
	yaw_kp_configure(&d->tnt_conf, &d->yaw_brake_kp, 2);

	// Overwrite App CFG Mahony KP to Float CFG Value
	if (VESC_IF->get_cfg_float(CFG_PARAM_IMU_mahony_kp) != d->tnt_conf.mahony_kp) {
		VESC_IF->set_cfg_float(CFG_PARAM_IMU_mahony_kp, d->tnt_conf.mahony_kp);
	}
}

static void reset_vars(data *d) {
	if (d->rt.current_time - d->rt.disengage_timer > 1) {//Delay reset in case there is a minor disengagement
		motor_data_reset(&d->motor);				//Motor
		setpoint_reset(&d->spd, &d->tnt_conf, &d->rt);		//Setpoint
		reset_runtime(&d->rt, &d->yaw, &d->yaw_dbg);		//Runtime 
		reset_pid(&d->pid);					//Control variables
		reset_remote(&d->remote, &d->st_tilt);			//Remote
		reset_surge(&d->surge);					//Surge
		reset_traction(&d->traction, &d->state, &d->braking);	//Traction Control
		tone_reset(&d->tone);					//FOC tones
		reset_ride_tracking(&d->ridetrack);	//Ride tracking
		reset_drop(&d->drop);
	}
	state_engage(&d->state);
}

void apply_kp_modifiers(data *d) {
	//Select and Apply Pitch kp rate			
	d->pid.pid_mod = apply_kp_rate(&d->accel_kp, &d->brake_kp, &d->pid, &d->pid_dbg) * -d->rt.gyro_y;
	d->pid_dbg.debug4 = d->rt.gyro_y;
	
	//Select and apply roll kp
	d->pid.pid_mod += apply_roll_kp(&d->roll_accel_kp, &d->roll_brake_kp, &d->pid, d->motor.erpm_sign, d->rt.abs_roll_angle, 
	    roll_erpm_scale(&d->pid,  &d->state, d->motor.abs_erpm, &d->roll_accel_kp, &d->tnt_conf), 
	    &d->pid_dbg);

	// Calculate yaw change
	calc_yaw_change(&d->yaw, &d->rt, &d->yaw_dbg, d->tnt_conf.hertz);
		
	//Select and apply yaw kp
	d->pid.pid_mod += apply_yaw_kp(&d->yaw_accel_kp, &d->yaw_brake_kp, &d->pid, d->motor.erpm_sign, d->yaw.abs_change, 
	    yaw_erpm_scale(&d->pid,  &d->state, d->motor.abs_erpm, &d->tnt_conf), 
	    &d->yaw_dbg);
}

static void imu_ref_callback(float *acc, float *gyro, float *mag, float dt) {
	UNUSED(mag);
	data *d = (data*)ARG;
	VESC_IF->ahrs_update_mahony_imu(gyro, acc, dt, &d->rt.m_att_ref);
}

static void tnt_thd(void *arg) {
	data *d = (data*)arg;

	configure(d);

	while (!VESC_IF->should_terminate()) {
		runtime_data_update(&d->rt);
		apply_pitch_filters(&d->rt, &d->tnt_conf);
		motor_data_update(&d->motor, &d->tnt_conf);
		update_remote(&d->tnt_conf, &d->remote);
		temp_recovery_tone(&d->tone, &d->tone_config.fasttripleup, &d->motor);
		tone_update(&d->tone, &d->rt, &d->state);
	        footpad_sensor_update(&d->footpad_sensor, &d->tnt_conf);
		ride_tracking_update(&d->ridetrack, &d->rt, &d->yaw, &d->tnt_conf);
		check_drop(&d->drop, &d->motor, &d->rt, &d->state, &d->drop_dbg);
	      	d->pid.new_pid_value = 0;		

		// Control Loop State Logic
		switch(d->state.state) {
		case (STATE_STARTUP):
			if (VESC_IF->imu_startup_done()) {
				reset_vars(d);
				d->state.state = STATE_READY;
            		}
           		break;
		case (STATE_RUNNING):	
			// Check for faults
			if (check_faults(&d->motor, &d->footpad_sensor, &d->rt, &d->state, 
			    d->remote.setpoint, &d->tnt_conf)) {
				if (d->state.stop_condition == STOP_SWITCH_FULL) {
					// dirty landings: add extra margin when rightside up
					d->spd.startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance + d->spd.startup_pitch_trickmargin;
					d->rt.fault_angle_pitch_timer = d->rt.current_time;
				}
				break;
			}

			play_footpad_beep(&d->tone, &d->motor, &d->footpad_sensor, &d->tone_config.continuousfootpad);

			//Ride Timer
			ride_timer(&d->ridetrack, &d->rt);
			d->rt.disengage_timer = d->rt.current_time;
			d->rt.odometer_dirty = 1;
			
			// Calculate setpoint and interpolation
			calculate_setpoint_target(&d->spd, &d->state, &d->motor, &d->rt, &d->tnt_conf, d->pid.proportional);
			calculate_setpoint_interpolated(&d->spd, &d->state);
			d->spd.setpoint = d->spd.setpoint_target_interpolated;

			//Apply Remote Tilt and Sticky Tilt
			float input_tiltback_target = d->remote.throttle_val * d->tnt_conf.inputtilt_angle_limit;
			if (d->tnt_conf.is_stickytilt_enabled)
				apply_stickytilt(&d->remote, &d->st_tilt, d->motor.current_filtered, &input_tiltback_target);
			apply_inputtilt(&d->remote, input_tiltback_target); 	//produces output d->remote.setpoint
			d->spd.setpoint += d->tnt_conf.enable_throttle_stability ? 0 : d->remote.setpoint; //Don't apply if we are using the throttle for stability

			//Adjust Setpoint as required
			apply_noseangling(&d->spd, &d->motor, &d->tnt_conf);

			//Apply Stability
			if (d->tnt_conf.enable_speed_stability || 
			    d->tnt_conf.enable_throttle_stability) 
				apply_stability(&d->pid, d->motor.abs_erpm, d->remote.setpoint, &d->tnt_conf);
			
			// Calculate proportional difference for raw and filtered pitch
			calculate_proportional(&d->rt, &d->pid, d->spd.setpoint);

			//Check for braking conditions and braking curves, and kp values for pitch roll and yaw
			d->state.braking_pos = sign(d->pid.proportional) != d->motor.erpm_sign;
			d->state.braking_pos_smooth = sign(d->pid.prop_smooth) != d->motor.erpm_sign;
			check_brake_kp(&d->pid,  &d->state,  &d->tnt_conf,  &d->roll_brake_kp,  &d->yaw_brake_kp);

			//Apply Pitch, Roll, Yaw Kp, and Soft Start
			d->pid.new_pid_value = apply_pitch_kp(&d->accel_kp, &d->brake_kp, &d->pid, &d->pid_dbg);
			apply_kp_modifiers(d);			//Roll Yaw
			apply_soft_start(&d->pid, d->motor.mc_current_max);	//Soft start
			d->pid.new_pid_value += d->pid.pid_mod; 
			
			// Current Limiting
			float current_limit = d->motor.braking ? d->motor.mc_current_min : d->motor.mc_current_max;
			if (fabsf(d->pid.new_pid_value) > current_limit) {
				d->pid.new_pid_value = sign(d->pid.new_pid_value) * current_limit;
			}
			check_current(&d->motor, &d->surge, &d->state,  &d->tnt_conf, 
			    &d->tone, &d->tone_config.currenttone); // Check for high current conditions
			
			// Modifiers to PID control
			if (d->tnt_conf.is_surge_enabled)
				check_surge(&d->motor, &d->surge, &d->state, &d->rt, &d->pid, 
				    d->spd.setpoint, &d->surge_dbg);
			if (d->tnt_conf.is_tc_braking_enabled)
				check_traction_braking(&d->braking, &d->motor, &d->state, &d->tnt_conf, 
				    d->remote.setpoint, &d->pid, &d->braking_dbg);
			check_traction(&d->motor, &d->traction, &d->state, &d->tnt_conf,
			    &d->pid, &d->traction_dbg);
			check_tone(&d->tone, &d->tone_config, &d->motor);
			
			// PID value application
			d->pid.pid_value = (d->state.wheelslip && d->tnt_conf.is_traction_enabled) ? 0 : d->pid.new_pid_value;

			// Output to motor
			if (d->state.surge_active)
				set_dutycycle(d->surge.new_duty_cycle, &d->rt); 	// Set the duty to surge
			else if (d->state.braking_active) 
				set_brake(d->pid.pid_value, &d->rt);			// Use braking function for traction control
			else
				set_current(d->pid.pid_value, &d->rt); 			// Set current as normal.

			break;

		case (STATE_READY):
			idle_tone(&d->tone, &d->tone_config.slowdouble2, &d->rt, &d->motor);
			check_odometer(&d->rt);
			rest_timer(&d->ridetrack, &d->rt);
			
			if ((d->rt.current_time - d->rt.fault_angle_pitch_timer) > 1) {
				// 1 second after disengaging - set startup tolerance back to normal (aka tighter)
				d->spd.startup_pitch_tolerance = d->tnt_conf.startup_pitch_tolerance;
			}
			
			// Check for valid startup position and switch state
			if (fabsf(d->rt.pitch_angle) < d->spd.startup_pitch_tolerance &&
				fabsf(d->rt.roll_angle) < 45 && 	//d->tnt_conf.startup_roll_tolerance && 
				is_engaged(&d->footpad_sensor, &d->rt, &d->tnt_conf)) {
				reset_vars(d);
				break;
			}
			
			// Push-start aka dirty landing Part II
			if(d->tnt_conf.startup_pushstart_enabled && (d->motor.abs_erpm > 1000) && 
			    is_engaged(&d->footpad_sensor, &d->rt, &d->tnt_conf)) {
				if ((fabsf(d->rt.pitch_angle) < 45) && (fabsf(d->rt.roll_angle) < 45)) {
					// 45 to prevent board engaging when upright or laying sideways
					// 45 degree tolerance is more than plenty for tricks / extreme mounts
					reset_vars(d);
					break;
				}
			}

			brake(d->tnt_conf.brake_current, &d->rt, &d->motor);
			break;
		case (STATE_DISABLED):;
			// no set_current, no brake_current
		default:;
		}

		// Delay between loops
		VESC_IF->sleep_us(d->rt.loop_time_us);
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

	// Emit 3 short beeps to confirm writing all settings to eeprom
	if (d->state.state != STATE_RUNNING)
		play_tone(&d->tone, &d->tone_config.fasttriple1, BEEP_NONE);
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
    d->rt.odometer = VESC_IF->mc_get_odometer();
}

static float app_get_debug(int index) {
    data *d = (data *) ARG;

    switch (index) {
    case (1):
        return d->pid.pid_value;
    case (2):
        return d->pid.proportional;
    case (3):
        return d->pid.proportional;
    case (4):
        return d->pid.proportional;
    case (5):
        return d->spd.setpoint;
    case (6):
        return d->pid.proportional;
    case (7):
        return d->motor.erpm;
    case (8):
        return d->motor.current;
    case (9):
        return d->motor.current;
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
	static const int bufsize = 144;
	uint8_t buffer[bufsize];
	int32_t ind = 0;
	buffer[ind++] = 111;//Magic Number
	buffer[ind++] = COMMAND_GET_RTDATA;

	// Board State
	buffer[ind++] = d->state.wheelslip ? 4 : d->state.state; 
	buffer[ind++] = d->state.sat; 
	buffer[ind++] = d->footpad_sensor.state;
	buffer[ind++] =	d->tone.beep_reason;
	buffer[ind++] = d->state.stop_condition;
	buffer_append_float32_auto(buffer, d->footpad_sensor.adc1, &ind);
	buffer_append_float32_auto(buffer, d->footpad_sensor.adc2, &ind);
	buffer_append_float32_auto(buffer, d->motor.voltage_filtered, &ind);
	buffer_append_float32_auto(buffer, d->motor.current_filtered, &ind); // current atr_filtered_current 
	buffer_append_float32_auto(buffer, d->rt.pitch_angle, &ind); 
	buffer_append_float32_auto(buffer, d->rt.roll_angle, &ind); 

	//Tune Modifiers
	buffer_append_float32_auto(buffer, d->spd.setpoint, &ind);
	buffer_append_float32_auto(buffer, d->remote.setpoint, &ind);
	buffer_append_float32_auto(buffer, d->remote.throttle_val, &ind);
	buffer_append_float32_auto(buffer, d->rt.current_time - d->traction.timeron , &ind); //Time since last wheelslip
	buffer_append_float32_auto(buffer, d->rt.current_time - d->surge.timer , &ind); //Time since last surge
	buffer_append_float32_auto(buffer, d->rt.current_time - d->braking.timeroff , &ind); //Time since last traction braking
	buffer_append_float32_auto(buffer, d->rt.current_time - d->drop.timeroff , &ind); //Time since last drop
	
	// Trip
	buffer_append_float32_auto(buffer, d->ridetrack.ride_time, &ind); //Ride Time
	buffer_append_float32_auto(buffer, d->ridetrack.rest_time, &ind); //Rest time
	buffer_append_float32_auto(buffer, d->ridetrack.distance, &ind); //distance
	buffer_append_float32_auto(buffer, d->ridetrack.efficiency, &ind); //efficiency
	buffer_append_float32_auto(buffer, d->ridetrack.current_avg, &ind); //current avg
	buffer_append_float32_auto(buffer, d->ridetrack.speed_avg, &ind); //speed avg mph
	buffer_append_float32_auto(buffer, d->ridetrack.max_carve_chain, &ind); 
	buffer_append_float32_auto(buffer, d->ridetrack.carves_mile, &ind);
	buffer_append_float32_auto(buffer, d->ridetrack.max_roll_avg, &ind); 
	buffer_append_float32_auto(buffer, d->ridetrack.max_yaw_avg * d->tnt_conf.hertz, &ind); 
	buffer_append_float32_auto(buffer, d->traction_dbg.max_time, &ind); 
	buffer_append_float32_auto(buffer, d->traction_dbg.bonks_total, &ind); 
	buffer_append_float32_auto(buffer, d->drop_dbg.max_time, &ind); 
	buffer_append_float32_auto(buffer, d->drop_dbg.debug7, &ind); 

	// DEBUG
	if (d->tnt_conf.is_tcdebug_enabled) {
		buffer[ind++] = 1;
		buffer_append_float32_auto(buffer, d->traction_dbg.debug2, &ind); //ERPM Limited
		buffer_append_float32_auto(buffer, d->traction_dbg.debug6, &ind); //ERPM Limited at traction control start
		buffer_append_float32_auto(buffer, d->traction_dbg.debug3, &ind); //actual erpm before wheel slip 
		buffer_append_float32_auto(buffer, d->traction_dbg.debug9, &ind); //actual erpm at wheel slip
		buffer_append_float32_auto(buffer, d->traction_dbg.debug4, &ind); //Debug condition 
		buffer_append_float32_auto(buffer, d->traction_dbg.debug8, &ind); //duration
		buffer_append_float32_auto(buffer, d->traction_dbg.debug5, &ind); //count 
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
		buffer_append_float32_auto(buffer, d->rt.pitch_smooth_kalman, &ind); //smooth pitch	
		buffer_append_float32_auto(buffer, d->pid_dbg.debug1, &ind); // scaled angle P
		buffer_append_float32_auto(buffer, cosf(deg2rad(d->rt.roll_angle)) * cosf(deg2rad(d->rt.roll_angle)) * d->rt.gyro[1], &ind); // added stiffnes pitch kp 	d->pid_dbg.debug1*d->pid.stabl*d->tnt_conf.stabl_pitch_max_scale/100.0
		buffer_append_float32_auto(buffer, cosf(deg2rad(d->rt.roll_angle)) * sinf(deg2rad(d->rt.roll_angle)) * d->rt.gyro[2], &ind); // added stability rate P 		d->pid_dbg.debug3
		buffer_append_float32_auto(buffer, d->rt.roll_angle, &ind); //													d->pid.stabl
		buffer_append_float32_auto(buffer, d->pid_dbg.debug2, &ind); //rollkp 
		buffer_append_float32_auto(buffer, d->pid_dbg.debug4, &ind); //pitch rate 
	} else if (d->tnt_conf.is_yawdebug_enabled) {
		buffer[ind++] = 4;
		buffer_append_float32_auto(buffer, d->rt.yaw_angle, &ind); //yaw angle
		buffer_append_float32_auto(buffer, d->yaw_dbg.debug5, &ind); //erpm scaler
		buffer_append_float32_auto(buffer, d->yaw_dbg.debug1 * d->tnt_conf.hertz, &ind); //yaw change
		buffer_append_float32_auto(buffer, d->yaw_dbg.debug3 * d->tnt_conf.hertz, &ind); //max yaw change
		buffer_append_float32_auto(buffer, d->yaw_dbg.debug4, &ind); //yaw kp 	
		buffer_append_float32_auto(buffer, d->yaw_dbg.debug2, &ind); //max kp change
	} else if (d->tnt_conf.is_brakingdebug_enabled) {
		buffer[ind++] = 5;
		buffer_append_float32_auto(buffer, d->braking_dbg.debug2, &ind); //current duty
		buffer_append_float32_auto(buffer, d->braking_dbg.debug6, &ind); //max accel
		buffer_append_float32_auto(buffer, d->braking_dbg.debug3, &ind); //Min ERPM
		buffer_append_float32_auto(buffer, d->braking_dbg.debug9, &ind); //Max ERPM
		buffer_append_float32_auto(buffer, d->braking_dbg.debug4, &ind); //Debug condition 
		buffer_append_float32_auto(buffer, d->braking_dbg.debug8, &ind); //duration
		buffer_append_float32_auto(buffer, d->braking_dbg.debug5, &ind); //count 
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

	VESC_IF->ahrs_init_attitude_info(&d->rt.m_att_ref);
	d->rt.m_att_ref.acc_confidence_decay = 0.1;
	d->rt.m_att_ref.kp = 0.2;

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
