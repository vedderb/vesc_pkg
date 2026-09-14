/*
	Copyright 2026 Benjamin Vedder	benjamin@vedder.se

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

HEADER

#define IS_CONS(x)			VESC_IF->lbm_is_cons(x)
#define IS_NUMBER(x)		VESC_IF->lbm_is_number(x)
#define CAR(x)				VESC_IF->lbm_car(x)
#define CDR(x)				VESC_IF->lbm_cdr(x)
#define FIRST(x)			CAR(x)
#define SECOND(x)			CAR(CDR(x))
#define DEC_F(x)			VESC_IF->lbm_dec_as_float(x)
#define DEC_I(x)			VESC_IF->lbm_dec_as_i32(x)
#define ENC_F(x)			VESC_IF->lbm_enc_float(x)
#define SYM_TRUE			VESC_IF->lbm_enc_sym_true
#define SYM_TERROR			VESC_IF->lbm_enc_sym_terror
#define SYM_EERROR			VESC_IF->lbm_enc_sym_eerror
#define SYM_MERROR			VESC_IF->lbm_enc_sym_merror

static lbm_value ext_cmd_proc(lbm_value *args, lbm_uint argn) {
	if (argn != 1 || !VESC_IF->lbm_is_byte_array(args[0])) {
		return SYM_TERROR;
	}
	
	lbm_array_header_t *arr = (lbm_array_header_t *)VESC_IF->lbm_car(args[0]);
	
	VESC_IF->commands_process_packet((uint8_t*)arr->data, arr->size, 0);

	return SYM_TRUE;
}

INIT_FUN(lib_info *info) {
	INIT_START
	(void)info;
	VESC_IF->lbm_add_extension("ext-cmd-proc", ext_cmd_proc);
	return true;
}
