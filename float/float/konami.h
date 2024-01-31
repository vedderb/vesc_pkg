#pragma once

#include "footpad_sensor.h"

typedef struct {
	float time;
	uint8_t state;
	const FootpadSensorState *sequence;
	uint8_t sequence_size;
} Konami;

void konami_init(Konami *konami, const FootpadSensorState *sequence, uint8_t sequence_size);

bool konami_check(Konami *konami, const FootpadSensor *fs, const float_config *config, float current_time);
