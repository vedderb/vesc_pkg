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

// Custom config example for a VESC Express native library.
//
// The config in conf/settings.xml is a catalogue rather than a real device
// configuration: one parameter of every type VESC Tool can render, named
// after the type it demonstrates.
//
// A custom config lets a package describe its settings in an XML file
// (conf/settings.xml) and have VESC Tool render the standard parameter UI
// for them - no QML needed. The lib registers three callbacks with
// conf_custom_add_config() and the firmware answers the COMM_*_CUSTOM_CONFIG
// packets from them:
//
//   get_cfg      - serialize the current (or default) config for VESC Tool
//   set_cfg      - deserialize a config VESC Tool wrote, and persist it
//   get_cfg_xml  - hand out the compiled settings.xml so VESC Tool knows
//                  what the parameters are
//
// The lib also exposes the config to LispBM through ext-cfg-* extensions, so
// the package's lisp code reads the same values the user edits in VESC Tool.
//
// See express_config.lisp for the lisp side and README.md for the build.

#include "express/vesc_c_if.h"

#include "conf_general.h"
#include "confparser.h"
#include "confxml.h"
#include "datatypes.h"

#include <stddef.h>
#include <string.h>

HEADER

// The serialized config is stored in the firmware's eeprom vars, which are
// 32-bit slots backed by NVS. EEPROM_BASE_IDX + CONFIG_WORDS must stay within
// the firmware's EEPROM_VARS count, and packages that use eeprom vars for
// other things too should leave the low indices free (float_accessories
// starts at 128, for instance).
#define EEPROM_BASE_IDX 0
#define CONFIG_WORDS ((SERIALIZED_CONFIG_LENGTH - 1) / 4 + 1)

typedef struct {
	ExampleConfig cfg;
	volatile bool changed; // set when VESC Tool writes the config
} example_data;

// ---- Persistence ----------------------------------------------------------

static bool write_cfg_to_eeprom(example_data *d) {
	uint32_t buffer[CONFIG_WORDS];
	memset(buffer, 0, sizeof(buffer));

	int32_t written =
		confparser_serialize_exampleconfig((uint8_t *)buffer, &d->cfg);
	if (written > (int32_t)sizeof(buffer)) {
		VESC_IF->printf("cfg: serialized config too big");
		return false;
	}

	// The whole config goes down in one NVS transaction. Storing it a word at
	// a time (count 1) would work, but a config is one atomic thing - a
	// partial write is a corrupt config.
	if (!VESC_IF->store_eeprom_var(
			(eeprom_var *)buffer, EEPROM_BASE_IDX, CONFIG_WORDS)) {
		VESC_IF->printf("cfg: eeprom write failed");
		return false;
	}

	return true;
}

static void read_cfg_from_eeprom(example_data *d) {
	uint32_t buffer[CONFIG_WORDS];

	bool read_ok = VESC_IF->read_eeprom_var(
		(eeprom_var *)buffer, EEPROM_BASE_IDX, CONFIG_WORDS);

	// The deserializer checks the signature that VESC Tool derived from
	// settings.xml, so data written by an older parameter layout is rejected
	// and the defaults are used instead. No magic number or CRC of your own
	// is needed.
	if (!read_ok
		|| !confparser_deserialize_exampleconfig((uint8_t *)buffer, &d->cfg)) {
		VESC_IF->printf("cfg: no stored config, using defaults");
		confparser_set_defaults_exampleconfig(&d->cfg);
	}
}

// ---- Custom config interface (VESC Tool) ----------------------------------

// Called for COMM_GET_CUSTOM_CONFIG and COMM_GET_CUSTOM_CONFIG_DEFAULT.
// Returns the number of bytes written into buffer.
static int get_cfg(uint8_t *buffer, bool is_default) {
	example_data *d = (example_data *)ARG;

	if (is_default) {
		// The defaults are built into a heap copy so the live config is not
		// disturbed by VESC Tool asking what the defaults are.
		ExampleConfig *cfg = VESC_IF->malloc(sizeof(ExampleConfig));
		if (!cfg) {
			return 0;
		}
		confparser_set_defaults_exampleconfig(cfg);
		int res = confparser_serialize_exampleconfig(buffer, cfg);
		VESC_IF->free(cfg);
		return res;
	}

	return confparser_serialize_exampleconfig(buffer, &d->cfg);
}

// Called for COMM_SET_CUSTOM_CONFIG, i.e. when the user hits write in VESC
// Tool. Persisting here is what makes the setting survive a reboot.
static bool set_cfg(uint8_t *buffer) {
	example_data *d = (example_data *)ARG;

	bool res = confparser_deserialize_exampleconfig(buffer, &d->cfg);
	if (res) {
		write_cfg_to_eeprom(d);
		d->changed = true;
	}

	return res;
}

// Called for COMM_GET_CUSTOM_CONFIG_XML. data_exampleconfig_ is the compiled
// settings.xml emitted into confxml.c.
//
// Note: unlike the STM32 example (c_libs/examples/config), no PROG_ADDR is
// added here. On the Express the lib is either executed in place with
// PC-relative addressing (RISC-V) or relocated at load time (esp32s3), so the
// address of the array is already correct at runtime.
static int get_cfg_xml(uint8_t **buffer) {
	*buffer = data_exampleconfig_;
	return DATA_EXAMPLECONFIG__SIZE;
}

// ---- LispBM access --------------------------------------------------------

// Name -> field lookup for the generic get/set extensions.
//
// Value-only tables: on the RISC-V targets a native lib executes in place
// from flash without load-time relocation, so a statically initialized array
// of POINTERS (const char *names[] = {"a", ...}) would hold meaningless
// link-time addresses. Names are stored as fixed-size char arrays instead -
// their addresses are computed at runtime, which is position-independent.

// One entry per C storage type in ExampleConfig. Bool, enum and bitfield all
// land on CFG_U8 - they differ in how VESC Tool edits them, not in how they
// are stored.
typedef enum {
	CFG_U8 = 0,
	CFG_I8,
	CFG_U16,
	CFG_I16,
	CFG_U32,
	CFG_I32,
	CFG_F32,
	CFG_STR,
} cfg_field_type;

#define CFG_FIELD_COUNT 14
#define CFG_NAME_LEN 18

static const char cfg_names[CFG_FIELD_COUNT][CFG_NAME_LEN] = {
	"demo_bool", "demo_enum", "demo_bitfield",
	"demo_uint8", "demo_int8", "demo_uint16", "demo_int16",
	"demo_uint32", "demo_int32",
	"demo_float16", "demo_float32", "demo_float32_auto", "demo_percent",
	"demo_string",
};

static const uint16_t cfg_offsets[CFG_FIELD_COUNT] = {
	offsetof(ExampleConfig, demo_bool),
	offsetof(ExampleConfig, demo_enum),
	offsetof(ExampleConfig, demo_bitfield),
	offsetof(ExampleConfig, demo_uint8),
	offsetof(ExampleConfig, demo_int8),
	offsetof(ExampleConfig, demo_uint16),
	offsetof(ExampleConfig, demo_int16),
	offsetof(ExampleConfig, demo_uint32),
	offsetof(ExampleConfig, demo_int32),
	offsetof(ExampleConfig, demo_float16),
	offsetof(ExampleConfig, demo_float32),
	offsetof(ExampleConfig, demo_float32_auto),
	offsetof(ExampleConfig, demo_percent),
	offsetof(ExampleConfig, demo_string),
};

static const uint8_t cfg_types[CFG_FIELD_COUNT] = {
	CFG_U8, CFG_U8, CFG_U8,
	CFG_U8, CFG_I8, CFG_U16, CFG_I16, CFG_U32, CFG_I32,
	CFG_F32, CFG_F32, CFG_F32, CFG_F32,
	CFG_STR,
};

// Buffer size in bytes for CFG_STR fields, 0 otherwise.
static const uint16_t cfg_lengths[CFG_FIELD_COUNT] = {
	0, 0, 0,
	0, 0, 0, 0, 0, 0,
	0, 0, 0, 0,
	sizeof(((ExampleConfig *)0)->demo_string),
};

// '-' and '_' compare equal, so lisp can pass its usual dashed symbol names
// ('demo-float16) for the underscored XML names (demo_float16).
static bool name_eq(const char *a, const char *b) {
	while (*a && *b) {
		char ca = *a == '-' ? '_' : *a;
		char cb = *b == '-' ? '_' : *b;
		if (ca != cb) {
			return false;
		}
		a++;
		b++;
	}
	return *a == *b;
}

static int find_field(lbm_value name_arg) {
	char *name = VESC_IF->lbm_dec_str(name_arg);
	if (!name) {
		return -1;
	}

	for (int i = 0; i < CFG_FIELD_COUNT; i++) {
		if (name_eq(name, cfg_names[i])) {
			return i;
		}
	}

	return -1;
}

// (ext-cfg-get name-str) -> value
static lbm_value ext_cfg_get(lbm_value *args, lbm_uint argn) {
	example_data *d = (example_data *)ARG;

	if (argn != 1) {
		return VESC_IF->lbm_enc_sym_terror;
	}

	int f = find_field(args[0]);
	if (f < 0) {
		VESC_IF->lbm_set_error_reason("Unknown config parameter");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	// memcpy rather than a cast through a typed pointer: the fields are packed
	// at their natural offsets in the struct, but nothing guarantees the
	// alignment a dereference would need.
	const uint8_t *p = (const uint8_t *)&d->cfg + cfg_offsets[f];
	switch (cfg_types[f]) {
	case CFG_F32: {
		float v;
		memcpy(&v, p, sizeof(v));
		return VESC_IF->lbm_enc_float(v);
	}
	case CFG_I8:
		return VESC_IF->lbm_enc_i((int8_t)*p);
	case CFG_U16: {
		uint16_t v;
		memcpy(&v, p, sizeof(v));
		return VESC_IF->lbm_enc_i(v);
	}
	case CFG_I16: {
		int16_t v;
		memcpy(&v, p, sizeof(v));
		return VESC_IF->lbm_enc_i(v);
	}
	case CFG_U32: {
		uint32_t v;
		memcpy(&v, p, sizeof(v));
		return VESC_IF->lbm_enc_u32(v);
	}
	case CFG_I32: {
		int32_t v;
		memcpy(&v, p, sizeof(v));
		return VESC_IF->lbm_enc_i32(v);
	}
	case CFG_STR: {
		const char *s = (const char *)p;
		uint16_t n = 0;
		while (n < cfg_lengths[f] && s[n]) {
			n++;
		}
		lbm_value v;
		if (!VESC_IF->lbm_create_byte_array(&v, (lbm_uint)n + 1)) {
			return VESC_IF->lbm_enc_sym_merror;
		}
		char *dst = VESC_IF->lbm_dec_str(v);
		if (!dst) {
			return VESC_IF->lbm_enc_sym_merror;
		}
		memcpy(dst, s, n);
		dst[n] = '\0';
		return v;
	}
	case CFG_U8:
	default:
		return VESC_IF->lbm_enc_i(*p);
	}
}

// (ext-cfg-set name-str value) -> t. Updates RAM only; persist with
// (ext-cfg-store).
static lbm_value ext_cfg_set(lbm_value *args, lbm_uint argn) {
	example_data *d = (example_data *)ARG;

	if (argn != 2) {
		return VESC_IF->lbm_enc_sym_terror;
	}

	int f = find_field(args[0]);
	if (f < 0) {
		VESC_IF->lbm_set_error_reason("Unknown config parameter");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	uint8_t *p = (uint8_t *)&d->cfg + cfg_offsets[f];

	// String fields take a byte array, numeric fields take a number, so the
	// type check is per field type rather than a blanket is-number gate.
	if (cfg_types[f] == CFG_STR) {
		if (!VESC_IF->lbm_is_byte_array(args[1])) {
			return VESC_IF->lbm_enc_sym_terror;
		}
		const char *src = VESC_IF->lbm_dec_str(args[1]);
		uint16_t cap = cfg_lengths[f];
		if (src && cap > 0) {
			uint16_t i = 0;
			for (; src[i] && i < (uint16_t)(cap - 1); i++) {
				p[i] = (uint8_t)src[i];
			}
			p[i] = '\0';
		}
		return VESC_IF->lbm_enc_sym_true;
	}

	if (!VESC_IF->lbm_is_number(args[1])) {
		return VESC_IF->lbm_enc_sym_terror;
	}

	switch (cfg_types[f]) {
	case CFG_F32: {
		float v = VESC_IF->lbm_dec_as_float(args[1]);
		memcpy(p, &v, sizeof(v));
	} break;
	case CFG_I8:
		*p = (uint8_t)(int8_t)VESC_IF->lbm_dec_as_i32(args[1]);
		break;
	case CFG_U16: {
		uint16_t v = (uint16_t)VESC_IF->lbm_dec_as_u32(args[1]);
		memcpy(p, &v, sizeof(v));
	} break;
	case CFG_I16: {
		int16_t v = (int16_t)VESC_IF->lbm_dec_as_i32(args[1]);
		memcpy(p, &v, sizeof(v));
	} break;
	case CFG_U32: {
		uint32_t v = VESC_IF->lbm_dec_as_u32(args[1]);
		memcpy(p, &v, sizeof(v));
	} break;
	case CFG_I32: {
		int32_t v = VESC_IF->lbm_dec_as_i32(args[1]);
		memcpy(p, &v, sizeof(v));
	} break;
	case CFG_U8:
	default:
		*p = (uint8_t)VESC_IF->lbm_dec_as_u32(args[1]);
		break;
	}

	// Values are stored as given - the XML min/max only bound VESC Tool's
	// editor, so a lisp caller can write outside that range.
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-cfg-store) -> t/nil. Persist the current config.
static lbm_value ext_cfg_store(lbm_value *args, lbm_uint argn) {
	(void)args;
	(void)argn;
	example_data *d = (example_data *)ARG;
	return write_cfg_to_eeprom(d) ? VESC_IF->lbm_enc_sym_true
								  : VESC_IF->lbm_enc_sym_nil;
}

// (ext-cfg-restore) -> t. Reset to the XML defaults and persist.
static lbm_value ext_cfg_restore(lbm_value *args, lbm_uint argn) {
	(void)args;
	(void)argn;
	example_data *d = (example_data *)ARG;
	confparser_set_defaults_exampleconfig(&d->cfg);
	write_cfg_to_eeprom(d);
	d->changed = true;
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-cfg-changed) -> t once after VESC Tool wrote the config, then nil.
// Poll this from lisp to apply settings without needing a reboot.
static lbm_value ext_cfg_changed(lbm_value *args, lbm_uint argn) {
	(void)args;
	(void)argn;
	example_data *d = (example_data *)ARG;

	if (d->changed) {
		d->changed = false;
		return VESC_IF->lbm_enc_sym_true;
	}
	return VESC_IF->lbm_enc_sym_nil;
}

// ---- Lifecycle ------------------------------------------------------------

static void stop(void *arg) {
	example_data *d = (example_data *)arg;

	// Unregister before the lib is unloaded, otherwise the firmware keeps
	// calling into freed code.
	VESC_IF->conf_custom_clear_configs();

	if (d) {
		VESC_IF->free(d);
	}

	VESC_IF->printf("Config example stopped");
}

INIT_FUN(lib_info *info) {
	INIT_START

	example_data *d = VESC_IF->malloc(sizeof(example_data));
	if (!d) {
		return false;
	}
	memset(d, 0, sizeof(example_data));

	info->arg = d;
	info->stop_fun = stop;

	read_cfg_from_eeprom(d);

	VESC_IF->conf_custom_add_config(get_cfg, set_cfg, get_cfg_xml);

	VESC_IF->lbm_add_extension("ext-cfg-get", ext_cfg_get);
	VESC_IF->lbm_add_extension("ext-cfg-set", ext_cfg_set);
	VESC_IF->lbm_add_extension("ext-cfg-store", ext_cfg_store);
	VESC_IF->lbm_add_extension("ext-cfg-restore", ext_cfg_restore);
	VESC_IF->lbm_add_extension("ext-cfg-changed", ext_cfg_changed);

	VESC_IF->printf("Config example loaded");

	return true;
}
