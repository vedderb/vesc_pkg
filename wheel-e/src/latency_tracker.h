// Copyright 2026 Lukas Hrazky
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

/**
 * Tracks the delivery latency of IMU samples. The dt provided by the firmware
 * is the spacing of pre-read timestamps, a clean sample interval free of
 * delivery delays (read stretching, scheduling). The interval between
 * consecutive callback timestamps contains those delays. Both are measured on
 * TIM5, so accumulating (interval - dt) telescopes to the delivery latency of
 * the current sample, offset by an unknown startup constant. Subtracting the
 * running minimum (the best-case delivery path) isolates the excess delay.
 *
 * Dropped samples don't affect the metric: dt spans the gap the same as the
 * callback interval does, so the accumulator is unaffected.
 *
 * On older firmware versions, which measure dt in the callback,
 * (interval - dt) is ~zero and the latency is flat.
 */
typedef struct {
    float latency;  // accumulated delivery latency [s], arbitrary offset
    float latency_min;
    float excess;  // latency - latency_min [ms]
    uint32_t last_stamp;
    bool first;
} LatencyTracker;

void latency_tracker_init(LatencyTracker *lt);

/**
 * Accumulates the latency from dt and the interval between successive calls.
 */
void latency_tracker_update(LatencyTracker *lt, float dt);
