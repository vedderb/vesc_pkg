#pragma once

#include "conf/datatypes.h"

typedef enum {
	FS_NONE = 0,
	FS_LEFT = 1,
	FS_RIGHT = 2,
	FS_BOTH = 3
} FootpadSensorState;

typedef struct {
	float adc1, adc2;
	FootpadSensorState state;
} FootpadSensor;

FootpadSensorState footpad_sensor_state_evaluate(const FootpadSensor *fs, const float_config *config, bool handpress);

void footpad_sensor_update(FootpadSensor *fs, const float_config *config);

int footpad_sensor_state_to_switch_compat(FootpadSensorState v);
