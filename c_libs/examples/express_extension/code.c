/*
	Copyright 2026 VESC project

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

// Minimal test library for native lib loading on the VESC Express. It
// exercises the parts of the C interface that differ between targets:
// printf and string handling (data addressing), float math (soft float on
// C3/C6, FPU on S3/P4), malloc + the ARG mechanism (base address
// bookkeeping) and thread spawn/terminate.

#include "express/vesc_c_if.h"

HEADER

typedef struct {
	lib_thread thread;
	int counter;
} test_state;

static void test_thd(void *arg) {
	test_state *state = (test_state*)arg;

	while (!VESC_IF->should_terminate()) {
		state->counter++;
		VESC_IF->sleep_ms(100);
	}
}

// (ext-test-hello) -> t. Prints a string, exercising rodata addressing.
static lbm_value ext_test_hello(lbm_value *args, lbm_uint argn) {
	(void)args; (void)argn;
	VESC_IF->printf("Hello from the native test lib!");
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-test-mul a b) -> a * b as float. Exercises the float ABI, which
// must match the firmware (soft float on C3/C6, hard float on S3/P4).
static lbm_value ext_test_mul(lbm_value *args, lbm_uint argn) {
	if (argn != 2 || !VESC_IF->lbm_is_number(args[0])
		|| !VESC_IF->lbm_is_number(args[1])) {
		return VESC_IF->lbm_enc_sym_terror;
	}

	float a = VESC_IF->lbm_dec_as_float(args[0]);
	float b = VESC_IF->lbm_dec_as_float(args[1]);

	return VESC_IF->lbm_enc_float(a * b);
}

// (ext-test-counter) -> i. Value of the counter the lib thread increments
// every 100 ms. Exercises spawn, thread-local terminate state and the
// ARG/get_arg base address bookkeeping.
static lbm_value ext_test_counter(lbm_value *args, lbm_uint argn) {
	(void)args; (void)argn;

	test_state *state = (test_state*)ARG;
	if (!state) {
		VESC_IF->lbm_set_error_reason("Not initialized");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	return VESC_IF->lbm_enc_i(state->counter);
}

static void stop(void *arg) {
	test_state *state = (test_state*)arg;

	if (state) {
		VESC_IF->request_terminate(state->thread);
		VESC_IF->printf("Test lib stopped, counter was %d", state->counter);
		VESC_IF->free(state);
	}
}

INIT_FUN(lib_info *info) {
	INIT_START

	test_state *state = VESC_IF->malloc(sizeof(test_state));
	if (!state) {
		return false;
	}

	state->counter = 0;
	state->thread = VESC_IF->spawn(test_thd, 2048, "lib_test", state);
	if (!state->thread) {
		VESC_IF->free(state);
		return false;
	}

	VESC_IF->lbm_add_extension("ext-test-hello", ext_test_hello);
	VESC_IF->lbm_add_extension("ext-test-mul", ext_test_mul);
	VESC_IF->lbm_add_extension("ext-test-counter", ext_test_counter);

	info->arg = state;
	info->stop_fun = stop;

	VESC_IF->printf("Native test lib loaded");

	return true;
}
