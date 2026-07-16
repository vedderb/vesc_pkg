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

// Float Accessories package configuration as a VESC custom config.
//
// The config is described by conf/settings.xml, edited in VESC Tool's
// standard parameter UI (Float Accessories Cfg), serialized by the
// generated confparser and persisted in the firmware's eeprom-var storage.
// LispBM reads and writes the same config through the ext-facfg-*
// extensions; parameter names use the XML names, with '-' and '_' treated
// as equal so lisp code can pass its usual dashed symbols.

#include "express/vesc_c_if.h"

#include "conf_general.h"
#include "confparser.h"
#include "confxml.h"
#include "conf_lookup.h"

#include <string.h>

HEADER

// Serialized config is chunked into eeprom vars starting at this index,
// leaving the low indices free for other uses of the eeprom space. The
// firmware backs these with NVS slots (EEPROM_VARS in flash_helper.c), so
// EEPROM_BASE_IDX + CONFIG_WORDS must stay <= EEPROM_VARS. With the MQTT
// string fields the config needs ~151 words; the firmware eeprom-var space
// was raised to 512 so this still fits from base 128 with v0..v127 free.
#define EEPROM_BASE_IDX 128
#define CONFIG_WORDS ((SERIALIZED_CONFIG_LENGTH - 1) / 4 + 1)

typedef struct {
	FaConfig cfg;
	volatile bool changed; // set when VESC Tool writes the config
} fa_data;

static bool write_cfg_to_eeprom(fa_data *d) {
	uint32_t buffer[CONFIG_WORDS];
	memset(buffer, 0, sizeof(buffer));

	int32_t written = confparser_serialize_faconfig((uint8_t *)buffer, &d->cfg);
	if (written > (int32_t)sizeof(buffer)) {
		VESC_IF->printf("facfg: serialized config too big");
		return false;
	}

	for (uint32_t i = 0; i < CONFIG_WORDS; i++) {
		eeprom_var v;
		v.as_u32 = buffer[i];
		if (!VESC_IF->store_eeprom_var(&v, EEPROM_BASE_IDX + i)) {
			VESC_IF->printf("facfg: eeprom write failed");
			return false;
		}
	}

	return true;
}

static void read_cfg_from_eeprom(fa_data *d) {
	uint32_t buffer[CONFIG_WORDS];

	bool read_ok = true;
	for (uint32_t i = 0; i < CONFIG_WORDS; i++) {
		eeprom_var v;
		if (!VESC_IF->read_eeprom_var(&v, EEPROM_BASE_IDX + i)) {
			read_ok = false;
			break;
		}
		buffer[i] = v.as_u32;
	}

	// The signature check rejects stale data from older layouts, which
	// replaces the magic/crc scheme the package used to implement itself.
	if (!read_ok || !confparser_deserialize_faconfig((uint8_t *)buffer, &d->cfg)) {
		VESC_IF->printf("facfg: no stored config, using defaults");
		confparser_set_defaults_faconfig(&d->cfg);
	}
}

// ---- Custom config interface (VESC Tool) --------------------------------

static int get_cfg(uint8_t *buffer, bool is_default) {
	fa_data *d = (fa_data *)ARG;

	if (is_default) {
		FaConfig *cfg = VESC_IF->malloc(sizeof(FaConfig));
		if (!cfg) {
			return 0;
		}
		confparser_set_defaults_faconfig(cfg);
		int res = confparser_serialize_faconfig(buffer, cfg);
		VESC_IF->free(cfg);
		return res;
	}

	return confparser_serialize_faconfig(buffer, &d->cfg);
}

static bool set_cfg(uint8_t *buffer) {
	fa_data *d = (fa_data *)ARG;

	bool res = confparser_deserialize_faconfig(buffer, &d->cfg);
	if (res) {
		write_cfg_to_eeprom(d);
		d->changed = true;
	}

	return res;
}

static int get_cfg_xml(uint8_t **buffer) {
	*buffer = data_faconfig_;
	return DATA_FACONFIG__SIZE;
}

// ---- LispBM access -------------------------------------------------------

// '-' and '_' compare equal so lisp symbol names map onto XML names.
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

	for (int i = 0; i < (int)CFG_FIELD_COUNT; i++) {
		if (name_eq(name, cfg_names[i])) {
			return i;
		}
	}

	return -1;
}

// (ext-facfg-get name-str) -> value
static lbm_value ext_facfg_get(lbm_value *args, lbm_uint argn) {
	fa_data *d = (fa_data *)ARG;

	if (argn != 1) {
		return VESC_IF->lbm_enc_sym_terror;
	}

	int f = find_field(args[0]);
	if (f < 0) {
		VESC_IF->lbm_set_error_reason("Unknown config parameter");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	const uint8_t *p = (const uint8_t *)&d->cfg + cfg_offsets[f];
	switch (cfg_types[f]) {
	case CFG_F32: {
		float v;
		memcpy(&v, p, sizeof(v));
		return VESC_IF->lbm_enc_float(v);
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

// (ext-facfg-set name-str value) -> t. RAM only; persist with
// (ext-facfg-store).
static lbm_value ext_facfg_set(lbm_value *args, lbm_uint argn) {
	fa_data *d = (fa_data *)ARG;

	// String fields take a byte array; numeric fields take a number. The
	// per-type check below enforces it, so no blanket is-number gate here.
	if (argn != 2) {
		return VESC_IF->lbm_enc_sym_terror;
	}

	int f = find_field(args[0]);
	if (f < 0) {
		VESC_IF->lbm_set_error_reason("Unknown config parameter");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	uint8_t *p = (uint8_t *)&d->cfg + cfg_offsets[f];
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
	case CFG_I32: {
		int32_t v = VESC_IF->lbm_dec_as_i32(args[1]);
		memcpy(p, &v, sizeof(v));
	} break;
	case CFG_U8:
	default:
		*p = (uint8_t)VESC_IF->lbm_dec_as_i32(args[1]);
		break;
	}

	return VESC_IF->lbm_enc_sym_true;
}

// (ext-facfg-store) -> t/nil. Persist the current config.
static lbm_value ext_facfg_store(lbm_value *args, lbm_uint argn) {
	(void)args; (void)argn;
	fa_data *d = (fa_data *)ARG;
	return write_cfg_to_eeprom(d) ? VESC_IF->lbm_enc_sym_true
		: VESC_IF->lbm_enc_sym_nil;
}

// (ext-facfg-restore) -> t. Reset to defaults and persist.
static lbm_value ext_facfg_restore(lbm_value *args, lbm_uint argn) {
	(void)args; (void)argn;
	fa_data *d = (fa_data *)ARG;
	confparser_set_defaults_faconfig(&d->cfg);
	write_cfg_to_eeprom(d);
	d->changed = true;
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-facfg-changed) -> t once after VESC Tool wrote the config, then nil.
static lbm_value ext_facfg_changed(lbm_value *args, lbm_uint argn) {
	(void)args; (void)argn;
	fa_data *d = (fa_data *)ARG;

	if (d->changed) {
		d->changed = false;
		return VESC_IF->lbm_enc_sym_true;
	}
	return VESC_IF->lbm_enc_sym_nil;
}

// ---- Lifecycle ------------------------------------------------------------

static void stop(void *arg) {
	fa_data *d = (fa_data *)arg;

	VESC_IF->conf_custom_clear_configs();
	if (d) {
		VESC_IF->free(d);
	}

	VESC_IF->printf("facfg stopped");
}

INIT_FUN(lib_info *info) {
	INIT_START

	fa_data *d = VESC_IF->malloc(sizeof(fa_data));
	if (!d) {
		return false;
	}
	memset(d, 0, sizeof(fa_data));

	info->arg = d;
	info->stop_fun = stop;

	read_cfg_from_eeprom(d);

	VESC_IF->conf_custom_add_config(get_cfg, set_cfg, get_cfg_xml);

	VESC_IF->lbm_add_extension("ext-facfg-get", ext_facfg_get);
	VESC_IF->lbm_add_extension("ext-facfg-set", ext_facfg_set);
	VESC_IF->lbm_add_extension("ext-facfg-store", ext_facfg_store);
	VESC_IF->lbm_add_extension("ext-facfg-restore", ext_facfg_restore);
	VESC_IF->lbm_add_extension("ext-facfg-changed", ext_facfg_changed);

	return true;
}
