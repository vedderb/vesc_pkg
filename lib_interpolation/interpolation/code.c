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
#define SYM_EERROR			VESC_IF->lbm_enc_sym_eerror
#define SYM_MERROR			VESC_IF->lbm_enc_sym_merror

// See http://paulbourke.net/miscellaneous/interpolation/

static float fun_linear(float y0,float y1, float y2,float y3, float mu) {
	(void)y0; (void)y3;
	return (y1*(1-mu) + y2*mu);
}

static float fun_cosine(float y0,float y1, float y2,float y3, float mu) {
	(void)y0; (void)y3;
	float mu2 = (1.0 - cosf(mu * M_PI)) / 2.0;
	return (y1*(1-mu2) + y2*mu2);
}

static float fun_cubic(float y0,float y1, float y2,float y3, float mu) {
	float mu2 = mu*mu;
	float a0 = y3 - y2 - y0 + y1;
	float a1 = y0 - y1 - a0;
	float a2 = y2 - y0;
	float a3 = y1;
	return (a0*mu*mu2 + a1*mu2+a2*mu + a3);
}

static float fun_hermite(float y0,float y1, float y2,float y3, float mu) {
	float mu2 = mu*mu;
	float a0 = -0.5*y0 + 1.5*y1 - 1.5*y2 + 0.5*y3;
	float a1 = y0 - 2.5*y1 + 2*y2 - 0.5*y3;
	float a2 = -0.5*y0 + 0.5*y2;
	float a3 = y1;
	return (a0*mu*mu2 + a1*mu2+a2*mu + a3);
}

static lbm_value ext_interpolate(lbm_value *args, lbm_uint argn) {
	if ((argn != 2 && argn != 3) || !IS_NUMBER(args[0]) || !IS_CONS(args[1])) {
		VESC_IF->lbm_set_error_reason("Format: (ext-interpolate value table optMethod)");
		return SYM_EERROR;
	}

	float val = DEC_F(args[0]);

	int method = 3;
	if (argn == 3 && IS_NUMBER(args[2])) {
		method = DEC_I(args[2]);
	}

	float x1 = 0.0;
	float x2 = 0.0;
	float y0 = 0.0;
	float y1 = 0.0;
	float y2 = 0.0;
	float y3 = 0.0;

	lbm_value curr = args[1];
	int cnt = 0;
	while (IS_CONS(curr)) {
		lbm_value  arg = CAR(curr);
		curr = CDR(curr);
		float x = DEC_F(FIRST(arg));
		float y = DEC_F(SECOND(arg));

		if (cnt == 0) {
			x1 = x;
			x2 = x;
			y0 = y;
			y1 = y;
			y2 = y;
			y3 = y;
		} else if (cnt == 1) {
			x1 = x;
			x2 = x;
			y1 = y;
			y2 = y;
			y3 = y;
		} else if (cnt == 2) {
			x2 = x;
			y2 = y;
			y3 = y;
		} else if (cnt == 3) {
			y3 = y;
		} else {
			break;
		}

		cnt++;
	}

	float res = 0.0;

	curr = args[1];
	bool passed = false;
	while (IS_CONS(curr)) {
		lbm_value  arg = CAR(curr);
		curr = CDR(curr);
		float x = DEC_F(FIRST(arg));
		float y = DEC_F(SECOND(arg));

		y0 = y1;
		y1 = y2;
		y2 = y3;
		y3 = y;

		if (!IS_CONS(curr)) {
			if (!passed) {
				passed = true;

				x1 = x2;
				x2 = x;

				y0 = y1;
				y1 = y2;
				y2 = y3;
				y3 = y;
			}

			x = val + 1;
		}

		if (x > val) {
			if (passed) {
				float mu = 0.0;
				if (x2 != x1) {
					mu = (val - x1) / (x2 - x1);
					if (mu > 1.0) {
						mu = 1.0;
					} else if (mu < 0.0) {
						mu = 0.0;
					}
				}

				if (method == 0) {
					res = fun_linear(y0, y1, y2, y3, mu);
				} else if (method == 1) {
					res = fun_cosine(y0, y1, y2, y3, mu);
				} else if (method == 2) {
					res = fun_cubic(y0, y1, y2, y3, mu);
				} else {
					res = fun_hermite(y0, y1, y2, y3, mu);
				}
				break;
			} else {
				passed = true;
			}
		}

		x1 = x2;
		x2 = x;
	}

	return ENC_F(res);
}

INIT_FUN(lib_info *info) {
	INIT_START
	(void)info;
	VESC_IF->lbm_add_extension("ext-interpolate", ext_interpolate);
	return true;
}
