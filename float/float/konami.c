#include "konami.h"

void konami_init(Konami *konami, const FootpadSensorState *sequence, uint8_t sequence_size) {
	konami->time = 0;
	konami->state = 0;
	konami->sequence = sequence;
	konami->sequence_size = sequence_size;
}

static void konami_reset(Konami *konami) {
	konami->time = 0;
	konami->state = 0;
}

bool konami_check(Konami *konami, const FootpadSensor *fs, const float_config *config, float current_time) {
	if (konami->time > 0 && current_time - konami->time > 0.5) {
		konami_reset(konami);
		return false;
	}

	FootpadSensorState fs_state = footpad_sensor_state_evaluate(fs, config, true);
	if (fs_state == konami->sequence[konami->state]) {
		++konami->state;
		if (konami->state == konami->sequence_size) {
			konami_reset(konami);
			return true;
		}

		konami->time = current_time;
	} else if (konami->state > 0 && fs_state != konami->sequence[konami->state - 1]) {
		konami_reset(konami);
	}

	return false;
}
