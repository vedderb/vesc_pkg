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

// The struct the generated confparser serializes. Written by hand, and it has
// to match conf/settings.xml: struct name is the <config_name> valString, one
// member per parameter named exactly as the XML tag, in <SerOrder> order, and
// the C type has to match the XML <type>. Nothing checks the correspondence
// and a mismatch silently corrupts every field after it. See
// c_libs/examples/express_config/conf/datatypes.h for the full type table.

#ifndef DATATYPES_H_
#define DATATYPES_H_

#include <stdbool.h>
#include <stdint.h>

typedef struct {
	uint8_t bms_enabled;	// <type> 5, bool
} BoostedConfig;

// DATATYPES_H_
#endif
