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

#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    STATE_DISABLED = 0,
    STATE_STARTUP = 1,
    STATE_READY = 2,
    STATE_RUNNING = 3
} RunState;

typedef enum {
    MODE_NORMAL = 0,
    MODE_HANDTEST = 1,
    MODE_FLYWHEEL = 2
} Mode;

typedef enum {
    STOP_NONE = 0,
    STOP_PITCH = 1,
    STOP_ROLL = 2,
    STOP_SWITCH_HALF = 3,
    STOP_SWITCH_FULL = 4,
    STOP_REVERSE_STOP = 5,
    STOP_QUICKSTOP = 6,
    STOP_TRACTN_CTRL = 7
} StopCondition;

// leaving gaps for more states inbetween the different "classes" of the types
// (normal / warning / error)
typedef enum {
    SAT_NONE = 0,
    SAT_CENTERING = 1,
    SAT_REVERSESTOP = 2,
    SAT_PB_DUTY = 6,
    SAT_PB_HIGH_VOLTAGE = 10,
    SAT_PB_LOW_VOLTAGE = 11,
    SAT_PB_TEMPERATURE = 12,
    SAT_UNSURGE = 13,
    SAT_SURGE = 14,
    SAT_UNDROP = 15,
    SAT_DROP = 16
} SetpointAdjustmentType;

typedef struct {
    RunState state;
    Mode mode;
    SetpointAdjustmentType sat;
    StopCondition stop_condition;
    bool charging;
    bool wheelslip;
    bool darkride;
    bool braking_pos;
    bool braking_pos_smooth;
    bool surge_active;
    bool surge_deactivate;
    bool braking_active;
} State;

void state_init(State *state, bool disable);

void state_stop(State *state, StopCondition stop_condition);

void state_engage(State *state);
