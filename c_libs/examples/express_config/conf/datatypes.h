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

// The struct the generated confparser serializes. It is written by hand and
// must match conf/settings.xml:
//
//   * the struct name is the <config_name> valString (ExampleConfig)
//   * one member per parameter, named exactly as the XML tag
//   * the members must be in <SerOrder> order
//   * the C type must match the XML <type>, and for ints and doubles the
//     <vTx> as well - that is what sets the width on the wire:
//
//       <type> 5 bool     -> uint8_t
//       <type> 4 enum     -> uint8_t
//       <type> 6 bitfield -> uint8_t   (max 8 flags)
//       <type> 3 string   -> char[maxLen + 1]
//       <type> 2 int      -> vTx 1 uint8_t   2 int8_t
//                            vTx 3 uint16_t  4 int16_t
//                            vTx 5 uint32_t  6 int32_t
//       <type> 1 double   -> float, for all of vTx 7/8/9
//
// Nothing checks this correspondence, and a mismatch corrupts every field
// after it, so packages with more than a handful of parameters generate this
// header and settings.xml together from one table - see
// float_accessories/conf/gen_conf.py.

#ifndef DATATYPES_H_
#define DATATYPES_H_

#include <stdbool.h>
#include <stdint.h>

typedef struct {
	uint8_t demo_bool;
	uint8_t demo_enum;
	uint8_t demo_bitfield;

	uint8_t demo_uint8;
	int8_t demo_int8;
	uint16_t demo_uint16;
	int16_t demo_int16;
	uint32_t demo_uint32;
	int32_t demo_int32;

	float demo_float16;
	float demo_float32;
	float demo_float32_auto;
	float demo_percent;

	char demo_string[32];
} ExampleConfig;

// DATATYPES_H_
#endif
