/*
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

#include <math.h>
#include <string.h>

HEADER

#define UNUSED(x) (void)(x)

// This is all persistent state of the application, which will be allocated in init. It
// is put here because variables can only be read-only when this program is loaded
// in flash without virtual memory in RAM (as all RAM already is dedicated to the
// main firmware and managed from there). This is probably the main limitation of
// loading applications in runtime, but it is not too bad to work around.
typedef struct {
	lib_thread thread; // NVM test Thread

	int top_address;
} data;


// Utility Functions

static void gscan(const char* str, uint8_t* vin) {
	uint8_t v = 0;
	while (*str != '\0') {
		v = v*10 + (*str++ - '0');
	}
	*vin = v;
	return;
}


static void terminal_wipe_nvm(int argc, const char **argv) {
	(void) argc;
	(void) argv;

	int res = VESC_IF->wipe_nvm();
	VESC_IF->printf("%d", res);
}

static void terminal_write_nvm(int argc, const char **argv) {
	if (argc >= 2) {
		int argo = 1;
		int offset = 0;
		if (argc > 4 && argv[1][0] == '-' && argv[1][1] == 'i') {
			gscan(argv[2], &offset);
			argo = 3;
		}
			
		VESC_IF->printf("Reading %d arguments. Starting processing...\n", argc);
		uint8_t w = 0;
		for (int i = 0; i < argc-argo; i++) {
			gscan(argv[i+argo], &w);
			VESC_IF->printf("\tTRYING TO WRITE AT %x (from data structure %x)\n", offset, d);
			if (VESC_IF->write_nvm(&w, 1, offset++)) {
				VESC_IF->printf("\tentry %d: %x", i, w);
				continue;
			}
			return;
		}
	} else {
		VESC_IF->printf("Usage: %s [integer]\n", argv[0]);
	}
}

static void terminal_read_nvm(int argc, const char **argv) {
	if (argc == 2) {
		uint8_t d = 0;
		gscan(argv[1], &d);
		if (d == 0) {
			return;
		}

		uint8_t *v = (uint8_t*)VESC_IF->malloc(d);
		if (VESC_IF->read_nvm(v, d, 0)) {
			for (int i = 0; i < d; i++) VESC_IF->printf("entry %d of %d = %d\n", i, d, v[i]);
		}
		return;
	} else {
		VESC_IF->printf("Usage: %s [integer]\n", argv[0]);
	}
}

// First start only, set initial state
static void app_init(data *d) {
	
	if (VESC_IF->write_nvm == NULL || VESC_IF->read_nvm == NULL || VESC_IF->wipe_nvm == NULL) {
		VESC_IF->lbm_set_error_reason("Firmware doesn't support NVM manipulation operations.");
		VESC_IF->printf("!! This version of the VESC firmware does not provide NVM manipulation operations! !!\n
				Try flashing a more recent version on your board."); 
		return;
	}

	VESC_IF->terminal_register_command_callback(
			"wipe_nvm",
			"Erases content of sector 8 of NVM.",
			"",
			terminal_wipe_nvm);

	VESC_IF->terminal_register_command_callback( "write_nvm",
			"Appends a list of bytes to NVM.",
			"[-i start index] ... bytes ..",
			terminal_write_nvm);

	VESC_IF->terminal_register_command_callback(
			"read_nvm",
			"Reads out d entries from the end of the NVM region.",
			"[d]",
			terminal_read_nvm);

	d->top_address = 0;
	VESC_IF->printf("Start address: %d\n", d->top_address);
	terminal_write_nvm(0, NULL, d);
	terminal_wipe_nvm(0, NULL, d);
}

static void nvm_test_thd(void *arg) {
	data *d = (data*)arg;

	app_init(d);

	while (!VESC_IF->should_terminate()) {
		VESC_IF->sleep_us(1000.0);
	}
}

// Called when code is stopped
static void stop(void *arg) {
	VESC_IF->terminal_unregister_callback( terminal_wipe_nvm);

	VESC_IF->terminal_unregister_callback( terminal_write_nvm);

	VESC_IF->terminal_unregister_callback( terminal_read_nvm);

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
		VESC_IF->printf("Init nvmtest\n");
	}

	data *d = VESC_IF->malloc(sizeof(data));
	memset(d, 0, sizeof(data));
	if (!d) {
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("nvmtest App: Out of memory, startup failed!");
		}
		return false;
	}

	info->stop_fun = stop;	
	info->arg = d;
	
	d->thread = VESC_IF->spawn(nvm_test_thd, 2048, "nvmtest Main", d);

	return true;
}
