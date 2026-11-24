// Copyright 2026 Henrik Buestad
//
// This file is part of the Wheel-E VESC package.
//
// Wheel-E VESC package is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// Wheel-E VESC package is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.

#pragma once

#include "conf/datatypes.h"

#include <stdbool.h>
#include <stdint.h>

// Number of consecutive stable reads required before a button state change is accepted
#define BTN_DEBOUNCE_THRESHOLD 10

typedef struct {
    bool pressed;
    bool prev;
    uint8_t count;
} IoButton;

void io_buttons_init(const RefloatConfig *config);

void io_buttons_update(IoButton *wheelie_btn, IoButton *cruise_btn, const RefloatConfig *config);
