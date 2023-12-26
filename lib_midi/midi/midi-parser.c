#include <math.h>

#include "midi-parser.h"

const char* midi_file_format_name(int fmt) {
	switch (fmt) {
	case MIDI_FILE_FORMAT_SINGLE_TRACK:
		return "single track";
	case MIDI_FILE_FORMAT_MULTIPLE_TRACKS:
		return "multiple tracks";
	case MIDI_FILE_FORMAT_MULTIPLE_SONGS:
		return "multiple songs";

	default:
		return "(unknown)";
	}
}

int midi_event_datalen(int status) {
	switch (status) {
	case MIDI_STATUS_PGM_CHANGE:
		return 1;
	case MIDI_STATUS_CHANNEL_AT:
		return 1;
	default:
		return 2;
	}
}

const char* midi_status_name(int status) {
	switch (status) {
	case MIDI_STATUS_NOTE_OFF:
		return "Note Off";
	case MIDI_STATUS_NOTE_ON:
		return "Note On";
	case MIDI_STATUS_NOTE_AT:
		return "Note Aftertouch";
	case MIDI_STATUS_CC:
		return "CC";
	case MIDI_STATUS_PGM_CHANGE:
		return "Program Change";
	case MIDI_STATUS_CHANNEL_AT:
		return "Channel Aftertouch";
	case MIDI_STATUS_PITCH_BEND:
		return "Pitch Bend";

	default:
		return "(unknown)";
	}
}

const char* midi_meta_name(int type) {
	switch (type) {
	case MIDI_META_SEQ_NUM:
		return "Sequence Number";
	case MIDI_META_TEXT:
		return "Text";
	case MIDI_META_COPYRIGHT:
		return "Copyright";
	case MIDI_META_TRACK_NAME:
		return "Track Name";
	case MIDI_META_INSTRUMENT_NAME:
		return "Instrument Name";
	case MIDI_META_LYRICS:
		return "Lyrics";
	case MIDI_META_MAKER:
		return "Maker";
	case MIDI_META_CUE_POINT:
		return "Cue Point";
	case MIDI_META_CHANNEL_PREFIX:
		return "Channel Prefix";
	case MIDI_META_END_OF_TRACK:
		return "End of Track";
	case MIDI_META_SET_TEMPO:
		return "Set Tempo";
	case MIDI_META_SMPTE_OFFSET:
		return "SMPTE Offset";
	case MIDI_META_TIME_SIGNATURE:
		return "Time Signature";
	case MIDI_META_KEY_SIGNATURE:
		return "Key Signature";
	case MIDI_META_SEQ_SPECIFIC:
		return "Sequencer Specific";

	default:
		return "(unknown)";
	}
}

static inline uint16_t midi_parse_be16(const uint8_t *in) {
	return (in[0] << 8) | in[1];
}

static inline uint32_t midi_parse_be32(const uint8_t *in) {
	return (in[0] << 24) | (in[1] << 16) | (in[2] << 8) | in[3];
}

static inline uint64_t midi_parse_variable_length(struct midi_parser *parser, int32_t *offset) {
	uint64_t value = 0;
	int32_t i = *offset;

	for (; i < parser->size; ++i) {
		value = (value << 7) | (parser->in[i] & 0x7f);
		if (!(parser->in[i] & 0x80))
			break;
	}
	*offset = i + 1;
	return value;
}

static inline enum midi_parser_status midi_parse_header(struct midi_parser *parser) {
	if (parser->size < 14)
		return MIDI_PARSER_EOB;

	if (memcmp(parser->in, "MThd", 4))
		return MIDI_PARSER_ERROR;

	parser->header.size = midi_parse_be32(parser->in + 4);
	parser->header.format = midi_parse_be16(parser->in + 8);
	parser->header.tracks_count = midi_parse_be16(parser->in + 10);
	parser->header.time_division = midi_parse_be16(parser->in + 12);

	parser->in += 14;
	parser->size -= 14;
	parser->state = MIDI_PARSER_HEADER;
	return MIDI_PARSER_HEADER;
}

static inline enum midi_parser_status midi_parse_track( struct midi_parser *parser) {
	if (parser->size < 8)
		return MIDI_PARSER_EOB;

	parser->track.size = midi_parse_be32(parser->in + 4);
	parser->state = MIDI_PARSER_TRACK;
	parser->in += 8;
	parser->size -= 8;
	parser->buffered_status = 0;
	return MIDI_PARSER_TRACK;
}

static inline bool midi_parse_vtime(struct midi_parser *parser) {
	uint8_t nbytes = 0;
	uint8_t cont = 1; // continue flag

	parser->vtime = 0;
	while (cont) {
		++nbytes;

		if (parser->size < nbytes || parser->track.size < nbytes)
			return false;

		uint8_t b = parser->in[nbytes - 1];
		parser->vtime = (parser->vtime << 7) | (b & 0x7f);

		// The largest value allowed within a MIDI file is 0x0FFFFFFF. A lot of
		// leading bytes with the highest bit set might overflow the nbytes counter
		// and create an endless loop.
		// If one would use 0x80 bytes for padding the check on parser->vtime would
		// not terminate the endless loop. Since the maximum value can be encoded
		// in 5 bytes or less, we can assume bad input if more bytes were used.
		if (parser->vtime > 0x0fffffff || nbytes > 5)
			return false;

		cont = b & 0x80;
	}

	parser->in += nbytes;
	parser->size -= nbytes;
	parser->track.size -= nbytes;

	return true;
}

static inline enum midi_parser_status midi_parse_channel_event(
		struct midi_parser *parser) {
	if (parser->size < 2)
		return MIDI_PARSER_EOB;

	if ((parser->in[0] & 0x80) == 0) {
		// Shortened event with running status.
		if (parser->buffered_status == 0)
			return MIDI_PARSER_EOB;
		parser->midi.status = parser->buffered_status;
		int datalen = midi_event_datalen(parser->midi.status);
		if (parser->size < datalen)
			return MIDI_PARSER_EOB;
		parser->midi.channel = parser->buffered_channel;
		parser->midi.param1 = (datalen > 0 ? parser->in[0] : 0);
		parser->midi.param2 = (datalen > 1 ? parser->in[1] : 0);

		parser->in += datalen;
		parser->size -= datalen;
		parser->track.size -= datalen;
	} else {
		// Full event with its own status.
		if (parser->size < 3)
			return MIDI_PARSER_EOB;
		parser->midi.status = (parser->in[0] >> 4) & 0xf;
		int datalen = midi_event_datalen(parser->midi.status);
		if (parser->size < 1 + datalen)
			return MIDI_PARSER_EOB;
		parser->midi.channel = parser->in[0] & 0xf;
		parser->midi.param1 = (datalen > 0 ? parser->in[1] : 0);
		parser->midi.param2 = (datalen > 1 ? parser->in[2] : 0);
		parser->buffered_status = parser->midi.status;
		parser->buffered_channel = parser->midi.channel;

		parser->in += 1 + datalen;
		parser->size -= 1 + datalen;
		parser->track.size -= 1 + datalen;
	}

	return MIDI_PARSER_TRACK_MIDI;
}

static int midi_parse_sysex_event(struct midi_parser *parser) {
	if (parser->size < 2)
		return MIDI_PARSER_ERROR;

	int32_t offset = 1;
	parser->sysex.length = midi_parse_variable_length(parser, &offset);
	if (offset < 1 || offset > parser->size)
		return MIDI_PARSER_ERROR;
	parser->in += offset;
	parser->size -= offset;
	parser->track.size -= offset;

	// Length should be positive and not more than the remaining size
	if (parser->sysex.length <= 0 || parser->sysex.length > parser->size)
		return MIDI_PARSER_ERROR;

	parser->sysex.bytes = parser->in;
	parser->in += parser->sysex.length;
	parser->size -= parser->sysex.length;
	parser->track.size -= parser->sysex.length;
	// Don't count the 0xF7 ending byte as data, if given:
	if (parser->sysex.bytes[parser->sysex.length - 1] == 0xF7)
		parser->sysex.length--;

	return MIDI_PARSER_TRACK_SYSEX;
}

static inline enum midi_parser_status midi_parse_meta_event( struct midi_parser *parser) {
	if (parser->size < 2)
		return MIDI_PARSER_ERROR;

	parser->meta.type = parser->in[1];
	int32_t offset = 2;
	parser->meta.length = midi_parse_variable_length(parser, &offset);

	// Length should never be negative or more than the remaining size
	if (parser->meta.length < 0 || parser->meta.length > parser->size)
		return MIDI_PARSER_ERROR;

	// Check buffer size
	if (parser->size < offset || parser->size - offset < parser->meta.length)
		return MIDI_PARSER_ERROR;

	parser->meta.bytes = parser->in + offset;
	offset += parser->meta.length;
	parser->in += offset;
	parser->size -= offset;
	parser->track.size -= offset;
	return MIDI_PARSER_TRACK_META;
}

static inline enum midi_parser_status midi_parse_event(struct midi_parser *parser) {
	parser->meta.bytes = NULL;
	if (!midi_parse_vtime(parser))
		return MIDI_PARSER_EOB;

	// Make sure the parser has not consumed the entire file or track, else
	// `parser-in[0]` might access heap-memory after the allocated buffer.
	if (parser->size <= 0 || parser->track.size <= 0)
		return MIDI_PARSER_ERROR;

	if (parser->in[0] < 0xf0) {  // Regular channel events:
		return midi_parse_channel_event(parser);
	} else {  // Special event types:
		parser->buffered_status = 0;  // (cancels running status)

		if (parser->in[0] == 0xf0)
			return midi_parse_sysex_event(parser);

		if (parser->in[0] == 0xff)
			return midi_parse_meta_event(parser);
	}
	return MIDI_PARSER_ERROR;
}

enum midi_parser_status midi_parse(struct midi_parser *parser) {
	if (!parser->in || parser->size < 1)
		return MIDI_PARSER_EOB;

	switch (parser->state) {
	case MIDI_PARSER_INIT:
		return midi_parse_header(parser);

	case MIDI_PARSER_HEADER:
		return midi_parse_track(parser);

	case MIDI_PARSER_TRACK:
		if (parser->track.size == 0) {
			// we reached the end of the track
			parser->state = MIDI_PARSER_HEADER;
			return midi_parse(parser);
		}
		return midi_parse_event(parser);

	default:
		return MIDI_PARSER_ERROR;
	}
}
