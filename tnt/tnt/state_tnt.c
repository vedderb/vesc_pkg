// Copyright 2024 Lukas Hrazky
//
// This file is part of the Refloat VESC package.
//
// Refloat VESC package is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// Refloat VESC package is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.

#include "state_tnt.h"

void state_init(State *state, bool disable) {
    state->state = disable ? STATE_DISABLED : STATE_STARTUP;
    state->mode = MODE_NORMAL;
    state->sat = SAT_NONE;
    state->stop_condition = STOP_NONE;
    state->charging = false;
    state->darkride = false;
}

void state_stop(State *state, StopCondition stop_condition) {
    state->state = STATE_READY;
    state->stop_condition = stop_condition;
    state->wheelslip = false;
}

void state_engage(State *state) {
    if (!state->charging) {
        state->state = STATE_RUNNING;
        state->sat = SAT_CENTERING;
        state->stop_condition = STOP_NONE;
        state->wheelslip = false;
    }
}
