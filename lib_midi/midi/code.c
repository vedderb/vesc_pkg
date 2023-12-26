/*
	Copyright 2023 Benjamin Vedder	benjamin@vedder.se

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
 
#include "vesc_c_if.h"

// See https://github.com/abique/midi-parser
#include "midi-parser.h"

HEADER

#define IS_CONS(x)			VESC_IF->lbm_is_cons(x)
#define IS_NUMBER(x)		VESC_IF->lbm_is_number(x)
#define CAR(x)				VESC_IF->lbm_car(x)
#define CDR(x)				VESC_IF->lbm_cdr(x)
#define CONS(car, cdr)		VESC_IF->lbm_cons(car, cdr)
#define FIRST(x)			CAR(x)
#define SECOND(x)			CAR(CDR(x))
#define DEC_F(x)			VESC_IF->lbm_dec_as_float(x)
#define DEC_I(x)			VESC_IF->lbm_dec_as_i32(x)
#define ENC_F(x)			VESC_IF->lbm_enc_float(x)
#define ENC_I(x)			VESC_IF->lbm_enc_i(x)
#define ENC_SYM(x)			VESC_IF->lbm_enc_sym(x)
#define SYM_TRUE			VESC_IF->lbm_enc_sym_true
#define SYM_NIL				VESC_IF->lbm_enc_sym_nil
#define SYM_EERROR			VESC_IF->lbm_enc_sym_eerror
#define SYM_MERROR			VESC_IF->lbm_enc_sym_merror
#define SYM_TERROR			VESC_IF->lbm_enc_sym_terror

static bool get_add_symbol(char *name, lbm_uint* id) {
	if (!VESC_IF->lbm_get_symbol_by_name(name, id)) {
		if (!VESC_IF->lbm_add_symbol_const(name, id)) {
			return false;
		}
	}

	return true;
}

typedef struct {
	int parsers;
	struct midi_parser *parser;
	lbm_uint sym_midi_eob;
	lbm_uint sym_midi_error;
	lbm_uint sym_midi_init;
	lbm_uint sym_midi_header;
	lbm_uint sym_midi_track;
	lbm_uint sym_midi_track_midi;
	lbm_uint sym_midi_track_meta;
	lbm_uint sym_midi_track_sysex;
} midi_state;

static lbm_value ext_midi_init(lbm_value *args, lbm_uint argn) {
	if (argn != 1 || !IS_NUMBER(args[0])) {
		VESC_IF->lbm_set_error_reason("Invalid argument");
		return SYM_TERROR;
	}

	int parser_num = DEC_I(args[0]);
	if (parser_num < 0 || parser_num > 10) {
		VESC_IF->lbm_set_error_reason("Invalid parser amount");
		return SYM_TERROR;
	}

	midi_state *state = VESC_IF->malloc(sizeof(midi_state));

	if (!state) {
		return SYM_MERROR;
	}

	memset(state, 0, sizeof(midi_state));
	state->parsers = parser_num;

	state->parser = VESC_IF->malloc(sizeof(struct midi_parser) * parser_num);

	if (!state->parser) {
		VESC_IF->free(state);
		return SYM_MERROR;
	}

	for (int i = 0;i < parser_num;i++) {
		memset(&state->parser[i], 0, sizeof(struct midi_parser));
	}

	ARG = state;

	return SYM_TRUE;
}

static lbm_value ext_midi_open(lbm_value *args, lbm_uint argn) {
	if (argn != 2 || !IS_NUMBER(args[0]) || !VESC_IF->lbm_is_byte_array(args[1])) {
		VESC_IF->lbm_set_error_reason("Format: (ext-midi-open parser midi-file)");
		return SYM_TERROR;
	}

	if (!ARG) {
		VESC_IF->lbm_set_error_reason("Not initialized");
		return SYM_EERROR;
	}

	midi_state *state = (midi_state*)ARG;

	int parser_num = DEC_I(args[0]);
	if (parser_num < 0 || parser_num >= state->parsers) {
		VESC_IF->lbm_set_error_reason("Invalid parser");
		return SYM_TERROR;
	}

	get_add_symbol("midi-eob", &state->sym_midi_eob);
	get_add_symbol("midi-error", &state->sym_midi_error);
	get_add_symbol("midi-init", &state->sym_midi_init);
	get_add_symbol("midi-header", &state->sym_midi_header);
	get_add_symbol("midi-track", &state->sym_midi_track);
	get_add_symbol("midi-track-midi", &state->sym_midi_track_midi);
	get_add_symbol("midi-track-meta", &state->sym_midi_track_meta);
	get_add_symbol("midi-sysex", &state->sym_midi_track_sysex);

	lbm_array_header_t *arr = (lbm_array_header_t *)VESC_IF->lbm_car(args[1]);

	state->parser[parser_num].state = MIDI_PARSER_INIT;
	state->parser[parser_num].size = arr->size;
	state->parser[parser_num].in = (uint8_t*)arr->data;

	ARG = state;

	return SYM_TRUE;
}

static lbm_value ext_midi_parse(lbm_value *args, lbm_uint argn) {
	if (argn != 1 || !IS_NUMBER(args[0])) {
		VESC_IF->lbm_set_error_reason("Invalid argument");
		return SYM_TERROR;
	}

	if (!ARG) {
		VESC_IF->lbm_set_error_reason("Not initialized");
		return SYM_EERROR;
	}

	midi_state *state = (midi_state*)ARG;

	int parser_num = DEC_I(args[0]);
	if (parser_num < 0 || parser_num >= state->parsers) {
		VESC_IF->lbm_set_error_reason("Invalid parser");
		return SYM_TERROR;
	}

	struct midi_parser *parser = &state->parser[parser_num];

	enum midi_parser_status status = midi_parse(parser);

	lbm_value res = SYM_NIL;

	switch (status) {
	case MIDI_PARSER_EOB:
		res = ENC_SYM(state->sym_midi_eob);
		break;

	case MIDI_PARSER_ERROR:
		res = ENC_SYM(state->sym_midi_error);
		break;

	case MIDI_PARSER_INIT:
		res = ENC_SYM(state->sym_midi_init);
		break;

	case MIDI_PARSER_HEADER:
		res = CONS(ENC_I(parser->header.time_division), res);
		res = CONS(ENC_I(parser->header.tracks_count), res);
		res = CONS(ENC_I(parser->header.format), res);
		res = CONS(ENC_I(parser->header.size), res);
		res = CONS(ENC_SYM(state->sym_midi_header), res);

//		VESC_IF->printf("header\n");
//		VESC_IF->printf("  size: %d\n", parser->header.size);
//		VESC_IF->printf("  format: %d [%s]\n", parser->header.format, midi_file_format_name(parser->header.format));
//		VESC_IF->printf("  tracks count: %d\n", parser->header.tracks_count);
//		VESC_IF->printf("  time division: %d\n", parser->header.time_division);
		break;

	case MIDI_PARSER_TRACK:
		res = CONS(ENC_I(parser->track.size), res);
		res = CONS(ENC_SYM(state->sym_midi_track), res);

//		VESC_IF->printf("track\n");
//		VESC_IF->printf("  length: %d\n", parser->track.size);
		break;

	case MIDI_PARSER_TRACK_MIDI:
		res = CONS(ENC_I(parser->midi.param2), res);
		res = CONS(ENC_I(parser->midi.param1), res);
		res = CONS(ENC_I(parser->midi.channel), res);
		res = CONS(ENC_I(parser->midi.status), res);
		res = CONS(ENC_I(parser->vtime), res);
		res = CONS(ENC_SYM(state->sym_midi_track_midi), res);

//		VESC_IF->printf("track-midi\n");
//		VESC_IF->printf("  time: %lld\n", parser->vtime);
//		VESC_IF->printf("  status: %d [%s]\n", parser->midi.status, midi_status_name(parser->midi.status));
//		VESC_IF->printf("  channel: %d\n", parser->midi.channel);
//		VESC_IF->printf("  param1: %d\n", parser->midi.param1);
//		VESC_IF->printf("  param2: %d\n", parser->midi.param2);
		break;

	case MIDI_PARSER_TRACK_META: {
		uint32_t data = 0;
		int len = parser->meta.length;
		if (len > 4) {
			len = 4;
		}

		for (int i = 0;i < len;i++) {
			data |= ((uint32_t)parser->meta.bytes[i]) << ((len - i - 1) * 8);
		}

		res = CONS(ENC_I(data), res);
		res = CONS(ENC_I(parser->meta.length), res);
		res = CONS(ENC_I(parser->meta.type), res);
		res = CONS(ENC_I(parser->vtime), res);
		res = CONS(ENC_SYM(state->sym_midi_track_meta), res);

//		VESC_IF->printf("track-meta\n");
//		VESC_IF->printf("  time: %lld\n", parser->vtime);
//		VESC_IF->printf("  type: %d [%s]\n", parser->meta.type, midi_meta_name(parser->meta.type));
//		VESC_IF->printf("  length: %d\n", parser->meta.length);
//		VESC_IF->printf("  data: %d (%02x %02x %02x)\n", data, parser->meta.bytes[0], parser->meta.bytes[1], parser->meta.bytes[2]);
	} break;

	case MIDI_PARSER_TRACK_SYSEX:
		res = CONS(ENC_I(parser->vtime), res);
		res = CONS(ENC_SYM(state->sym_midi_track_sysex), res);
		break;

	default:
		break;
	}

	return res;
}

INIT_FUN(lib_info *info) {
	INIT_START
	info->arg = 0;

	VESC_IF->lbm_add_extension("ext-midi-init", ext_midi_init);
	VESC_IF->lbm_add_extension("ext-midi-open", ext_midi_open);
	VESC_IF->lbm_add_extension("ext-midi-parse", ext_midi_parse);
	return true;
}
