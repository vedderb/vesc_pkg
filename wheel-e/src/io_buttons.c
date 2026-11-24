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

#include "io_buttons.h"

#include "vesc_c_if.h"

static void button_update(IoButton *btn, bool raw) {
    btn->prev = btn->pressed;
    if (raw == btn->pressed) {
        btn->count = 0;
    } else if (++btn->count >= BTN_DEBOUNCE_THRESHOLD) {
        btn->count = 0;
        btn->pressed = raw;
    }
}

void io_buttons_init(const RefloatConfig *config) {
    // Configure TX pin as digital input with pull-up for wheelie button
    if (config->wheelie_button_mode != WHEELIE_BTN_NONE) {
        VESC_IF->io_set_mode(VESC_PIN_COMM_TX, VESC_PIN_MODE_INPUT_PULL_UP);
    }

    // Configure RX pin as digital input with pull-up for cruise control button
    if (config->cruise_enabled) {
        VESC_IF->io_set_mode(VESC_PIN_COMM_RX, VESC_PIN_MODE_INPUT_PULL_UP);
    }
}

void io_buttons_update(IoButton *wheelie_btn, IoButton *cruise_btn, const RefloatConfig *config) {
    // TX pin: active low (pulled high, button pulls to GND)
    if (config->wheelie_button_mode != WHEELIE_BTN_NONE) {
        button_update(wheelie_btn, !VESC_IF->io_read(VESC_PIN_COMM_TX));
    }

    // RX pin: active low (pulled high, button pulls to GND)
    if (config->cruise_enabled) {
        button_update(cruise_btn, !VESC_IF->io_read(VESC_PIN_COMM_RX));
    }
}
