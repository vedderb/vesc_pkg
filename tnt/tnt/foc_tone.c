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

#include "foc_tone.h"
#include "utils_tnt.h"
#include <math.h>

void tone_update(ToneData *tone, RuntimeData *rt, State *state) {
	//This function is updated every code cycle to execute initiated tones
	int index;
	
	if (tone->duration > 30 &&		//Don't allow continuous tones outiside run state
	    state->state != STATE_RUNNING) {	
		end_tone(tone);
	}
	
	if (!tone->pause) { 					//only play or stop tones outside of pause period
		tone->pause_timer = rt->current_time; 		// keep updated until we are in pause state
		if (!tone->tone_in_progress && tone->times != 0) { //play if times>0 and we are ready for the next tone
			index = min(2, tone->times - 1);	//Use index/times to play frequencies in reverser order: 3 2 1
			if (state->state == STATE_RUNNING) { 	//Choose function based on state
				tone->tone_in_progress = VESC_IF->foc_play_tone(0,  tone->freq[index], tone->voltage);
			} else { tone->tone_in_progress = VESC_IF->foc_beep(tone->freq[index], tone->duration, tone->voltage); }
			tone->timer = rt->current_time;		//Used to track tone duration
			tone->times--; 				//Decrement the times property until 0
		} else if (rt->current_time - tone->timer > tone->duration && tone->tone_in_progress) {
			VESC_IF->foc_stop_audio(true);	//stop foc play tone after duration
			if (tone->times > 0) 		
				tone->pause = true; 		//put in pause if there is another play to do
			tone->tone_in_progress = false; 
		}
	} else if (rt->current_time - tone->pause_timer > 0.1) { //Hard coded pause of 100 ms
		tone->pause = false;
	}
}

void play_tone(ToneData *tone, ToneConfig *toneconfig, int beep_reason) {
	//This function is used to initiate tones, and only called in specific instances
	float current_time = VESC_IF->system_time();
	if (current_time - tone->timer < toneconfig->delay && 	//This section applies delay to prevent constant repetition
	    tone->priority == toneconfig->priority)  				//if the beep reason remains the same.
		return;			
	
	if (tone->priority < toneconfig->priority) { //Allow for immediate override of higher priority
		tone->tone_in_progress = false;
		VESC_IF->foc_stop_audio(true);
	}
	
	if (!tone->tone_in_progress) {		//Applies tone properties and initiates tone with tone->times > 0
		tone->freq[0] = toneconfig->freq[0];
		tone->freq[1] = toneconfig->freq[1];
		tone->freq[2] = toneconfig->freq[2];
		tone->voltage = toneconfig->voltage;
		tone->duration = toneconfig->duration;
		tone->priority = toneconfig->priority;
		tone->times = toneconfig->times;
		tone->pause = false;
		tone->beep_reason = beep_reason;
	}
}

void end_tone(ToneData *tone) {
	//Used to end continuous tones
	tone->freq[0] = 0;
	tone->freq[1] = 0;
	tone->freq[2] = 0;
	tone->voltage = 0;
	tone->duration = 0;
	tone->times = 0;
}

void tone_reset_on_configure(ToneData *tone) {
	//low voltage warnings reset on board start up
	tone->midrange_activated = false;
	tone->lowrange_activated = false;
}

void tone_reset(ToneData *tone) {
	tone->duty_tone_count = 0;
	tone->duty_beep_count = 0; 
	tone->midrange_count = 0;
	tone->lowrange_count = 0;
	tone->highvolt_count = 0;
	tone->lowvolt_count = 0;
	tone->voltage_diff = 0;
	tone->last_voltage = VESC_IF->mc_get_input_voltage_filtered();
}

void tone_configure(ToneConfig *toneconfig, float freq1, float freq2, float freq3, float voltage, float duration, int times, float delay, int priority) {
	toneconfig->freq[0] = freq1;
	toneconfig->freq[1] = freq2;
	toneconfig->freq[2] = freq3;
	toneconfig->voltage = voltage;
	toneconfig->duration = duration;
	toneconfig->times = times;
	toneconfig->delay = delay;
	toneconfig->priority = priority;
}

void tone_configure_all(ToneConfigs *toneconfig, tnt_config *config, ToneData *tone) {
	float beep_voltage = config->is_beeper_enabled ? config->beep_voltage : 0;
	tone_configure(&toneconfig->continuous1, 659.3, 0, 0, beep_voltage, 601, 1, 0, 1);
	tone_configure(&toneconfig->fastdouble1, 659.3, 659.3, 0, beep_voltage, .1, 2, 10, 1);
	tone_configure(&toneconfig->fastdouble2, 784, 784, 0, beep_voltage, .1, 2, 0, 1);
	tone_configure(&toneconfig->slowdouble1, 659.3, 659.3, 0, beep_voltage, .3, 2, 30, 1);
	tone_configure(&toneconfig->slowdouble2, 784, 784, 0, beep_voltage, .3, 2, 300, 3);		//Charged or idle
	tone_configure(&toneconfig->fasttriple1, 659.3, 659.3, 659.3, beep_voltage, .1, 3, 0, 1);	//On write
	tone_configure(&toneconfig->slowtriple1, 659.3, 659.3, 659.3, beep_voltage, .3, 3, 10, 5); 	//Temp motor
	tone_configure(&toneconfig->slowtriple2, 784, 784, 784, beep_voltage, .3, 3, 10, 5);		//Temp fets
	tone_configure(&toneconfig->fasttripleup, 784, 698.5, 659.3, beep_voltage, .1, 3, 10, 5);	//temp recovery
	tone_configure(&toneconfig->fasttripledown, 659.3, 698.5, 784, beep_voltage, .1, 3, 30, 1);
	tone_configure(&toneconfig->slowtripleup, 784, 698.5, 659.3, beep_voltage, .3, 3, 5, 7);	//high voltage
	tone_configure(&toneconfig->slowtripledown, 659.3, 698.5, 784, beep_voltage, .3, 3, 30, 8);	//low voltage
	tone_configure(&toneconfig->midvoltwarning, 659.3, 784, 784, beep_voltage, .3, 3, 0, 7);	//mid range
	tone_configure(&toneconfig->lowvoltwarning, 659.3, 659.3, 784, beep_voltage, .3, 3, 0, 7); 	//low range
	
	beep_voltage = config->is_dutybeep_enabled ? config->beep_voltage : 0;
	tone_configure(&toneconfig->fasttripleupduty, 784, 698.5, 659.3, beep_voltage, .1, 3, 10, 15);	//duty beep
	
	beep_voltage = config->is_footbeep_enabled ? config->beep_voltage : 0;
	tone_configure(&toneconfig->continuousfootpad, 659.3, 0, 0, beep_voltage, 601, 1, -1, 4);	//footpad beep

	beep_voltage = config->haptic_buzz_duty ? config->tone_volt_high_duty : 0;			//High Duty Tone
	tone_configure(&toneconfig->dutytone, config->tone_freq_high_duty, 0, 0, beep_voltage, 600, 1, -1, 15);

	beep_voltage = config->haptic_buzz_current ? config->tone_volt_high_current : 0; 		//High Current Tone
	tone_configure(&toneconfig->currenttone, config->tone_freq_high_current, 0, 0, beep_voltage, config->overcurrent_period, 1, 0, 12);

	tone->tone_duty = 1.0 * config->tiltback_duty / 100.0; 
	tone->delay_100ms = config->hertz / 10;
	tone->delay_250ms = config->hertz / 4;
	tone->delay_500ms = config->hertz / 2;
	tone->lowrange_warning = config->lowvolt_warning;
	tone->midrange_warning = config->midvolt_warning;
	tone->lowvolt_warning = config->tiltback_lv;
	tone->highvolt_warning = config->tiltback_hv;
	tone->shutdown_mode = VESC_IF->get_cfg_int(CFG_PARAM_app_shutdown_mode);
	tone_reset_on_configure(tone);
}

void idle_tone(ToneData *tone, ToneConfig *toneconfig, RuntimeData *rt, MotorData *m) {
	//Conditions to play a charged or idle tone
	if (tone->voltage_diff >= 0.1) {						// Allow a possible charged beep if increasing voltage differential. Don't idle beep.
		if (m->voltage_filtered - tone->charged_voltage > 0.01) {		//Once the voltage stops climbing this will no longer be true
			tone->charged_timer = rt->current_time;				//and this timer will record how long the voltage has stopped climbing for
			tone->charged_voltage = m->voltage_filtered;
		}
		if (rt->current_time - tone->charged_timer > 600) {		 	// voltage has stopped climbing for 10 minutes
			play_tone(tone, toneconfig, BEEP_CHARGED);
			tone->voltage_diff = 0.1;					//reset voltage diff to 0.1. Allows continued charge beeps but if voltage drops idle beep can engage
		}
	} else if (tone->shutdown_mode > 2) {						//Autoshutdown is activated in the app settings
		if (tone->voltage_diff < -1 && tone->voltage_diff > -2)			//If we are dropping voltage too fast something is wrong, so attract attention
			play_tone(tone, toneconfig, BEEP_IDLE);	
	} else if (rt->current_time - rt->disengage_timer > 1800 &&			// alert user after 30 minutes
	    tone->voltage_diff > -1) {							// give up after dropping 1 volts.
		play_tone(tone, toneconfig, BEEP_IDLE);	
	}
	
	//These variables aggregate voltage change to determine we have been charging. This is necessary to prevent small dips and recoveries that look like charging.
	if (rt->current_time - rt->disengage_timer < 5)
		tone->voltage_diff = 0;					// reset the voltage differential if we just disengaged
	else if (rt->current_time - rt->disengage_timer > 480)		// wait 8 minutes to discern normal battery recovery from charging
		tone->voltage_diff += m->voltage_filtered - tone->last_voltage;	//aggregate the voltage change
	tone->last_voltage = m->voltage_filtered;			// keep updated, doesn't require conditional
}

void temp_recovery_tone(ToneData *tone, ToneConfig *toneconfig, MotorData *motor) {
	//This function alerts the user once the motor or fets have cooled 10 degrees below the tiltback limit
	if (VESC_IF->mc_temp_motor_filtered() < motor->mc_max_temp_mot - 7 &&
	    tone->motortemp_activated) {
		play_tone(tone, toneconfig, BEEP_MOTREC);
		tone->motortemp_activated = false;
	} else if (VESC_IF->mc_temp_fet_filtered() < motor->mc_max_temp_fet - 7 &&
	    tone->fettemp_activated) {
		play_tone(tone, toneconfig, BEEP_FETREC);
		tone->fettemp_activated = false;
	}
}


void check_tone(ToneData *tone, ToneConfigs *toneconfig, MotorData *motor) {
	//This function provides a delay before the activation of certain tones
	float input_voltage = VESC_IF->mc_get_input_voltage_filtered();
	
	//Duty FOC Tone and Beep
	if (motor->duty_cycle_filtered > tone->tone_duty - .1) { //10% below titltback duty for beep
		if (motor->duty_cycle_filtered > tone->tone_duty) { 
			tone->duty_tone_count++; 	//A counter is used to track duty cycle to prevent nuisance trips
			tone->duty_beep_count = 0;
		} else {
			tone->duty_tone_count = 0;	
			tone->duty_beep_count++; 	//A counter is used to track duty cycle to prevent nuisance trips
		}
	} else { 
		tone->duty_tone_count = 0;
		tone->duty_beep_count = 0; 
	}
	
	if (tone->duty_tone_count > tone->delay_100ms) // After we are above duty for 500ms then play tone
		play_tone(tone, &toneconfig->dutytone, TONE_DUTY);
	else if (tone->tone_in_progress && tone->duration == 600) 
		end_tone(tone);	
	else if (tone->duty_beep_count > tone->delay_100ms) // After we are above duty for 500ms then play beep
		play_tone(tone, &toneconfig->fasttripleupduty, BEEP_DUTY);

	//Mid Range Warning
	float abs_motor_current = fabsf(motor->current_filtered);
	float vdelta = tone->midrange_warning - input_voltage;
	float ratio = vdelta * 20 / abs_motor_current;

	if ((vdelta > 2) || (abs_motor_current < 5 && input_voltage < tone->midrange_warning) || (ratio > 1)) 
		tone->midrange_count++; 	//A counter is used to track duty cycle to prevent nuisance trips
	else tone->midrange_count = 0;

	if (!tone->midrange_activated && 
	    tone->midrange_count > tone->delay_500ms) {
		play_tone(tone, &toneconfig->midvoltwarning, BEEP_MW);
		tone->midrange_activated = true;
	}
	
	//Low Range Warning
	vdelta = tone->lowrange_warning - input_voltage;
	ratio = vdelta * 20 / abs_motor_current;
	
	if ((vdelta > 2) || (abs_motor_current < 5 && input_voltage < tone->lowrange_warning) || (ratio > 1)) 
		tone->lowrange_count++; 	//A counter is used to track duty cycle to prevent nuisance trips
	else tone->lowrange_count = 0;

	if (!tone->lowrange_activated && 
	    tone->lowrange_count > tone->delay_500ms) {
		play_tone(tone, &toneconfig->lowvoltwarning, BEEP_LW);
		tone->lowrange_activated = true;
	}

	//High motor and fet temperatures
	if (VESC_IF->mc_temp_fet_filtered() > motor->mc_max_temp_fet) {
		play_tone(tone, &toneconfig->slowtriple2, BEEP_TEMPFET);
		tone->fettemp_activated = true;
	} else if (VESC_IF->mc_temp_motor_filtered() > motor->mc_max_temp_mot) {
		play_tone(tone, &toneconfig->slowtriple1, BEEP_TEMPMOT);
		tone->motortemp_activated = true;
	}

	//Low and high voltages	
	if (input_voltage > tone->highvolt_warning) 
		tone->highvolt_count++; 
	else tone->highvolt_count = 0;
	
	if (input_voltage < tone->lowvolt_warning) 
		tone->lowvolt_count++;
	else tone->lowvolt_count = 0;

	if (tone->highvolt_count > tone->delay_500ms) 
		play_tone(tone, &toneconfig->slowtripleup, BEEP_HV);
	else if (tone->lowvolt_count > tone->delay_500ms) 
		play_tone(tone, &toneconfig->slowtripledown, BEEP_LV);
}

void play_footpad_beep(ToneData *tone, MotorData *motor, FootpadSensor *fs, ToneConfig *toneconfig) {
	//Check footpad beep
	if (fs->state == FS_NONE &&
	  motor->abs_erpm > 2000) {
	    play_tone(tone, toneconfig, BEEP_SENSORS);
	} else if (tone->tone_in_progress && tone->beep_reason == BEEP_SENSORS) { 
	    end_tone(tone);
	}
}
