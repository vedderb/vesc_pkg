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

// Boosted Board / Rev Scooter battery bridge, as a native library.
//
// The whole CAN side lives here: the keep-alive ping that stops the pack
// shutting down after ten minutes, the cell-report request, RLOD
// (PFAILRESET) recovery, the periodic 0x334xx broadcasts, and reassembly of
// the AFE's ASCII cell report - a byte stream chopped across CAN frames
// rather than fixed-layout data. ui.qml is served from here too, over custom
// app data.
//
// code.lbm only republishes the result through set-bms-val, which has no
// C-interface equivalent. That is the only reason there is any lisp left.
//
// Two constraints shape the code. On the RISC-V Express targets the lib runs
// in place from flash, so there are no writable globals - all state lives in
// one allocated struct reached through ARG, including from the CAN rx
// callback, which gets no user pointer of its own. And there is no snprintf
// worth linking into a blob this size, so status strings are formatted by
// hand from integer mV and mA.
//
// Concurrency: the CAN rx callback is the only writer of decoded state, and
// every field it writes is a naturally aligned word or halfword, so readers
// cannot see a torn value and nothing locks on a path that may run in
// interrupt context.

#ifdef ESP_PLATFORM
#include "express/vesc_c_if.h"
#else
#include "vesc_c_if.h"
#endif

#include "conf/conf_general.h"
#include "conf/confparser.h"
#include "conf/confxml.h"
#include "conf/datatypes.h"

#include <string.h>

HEADER

// ---- Protocol -----------------------------------------------------------

// Transmit IDs (extended). The AFE command IDs carry an 8-byte first frame
// and the remainder in a second frame on the low ID.
#define BD_EID_ROUTING			0x10346090u
#define BD_EID_AFE_CMD_HI		0x10246110u
#define BD_EID_AFE_CMD_LO		0x10146111u
#define BD_EID_REBOOT			0x10346110u
#define BD_EID_PING_BASE		0x103434B0u	// low nibble is a rolling counter

// Receive headers, i.e. (id >> 4) & 0xFFFFF.
#define BD_HDR_AFE_A			0x02411
#define BD_HDR_AFE_B			0x12411
#define BD_HDR_AFE_C			0x22411
#define BD_HDR_VERSION			0x33440
#define BD_HDR_SERIAL			0x33441
#define BD_HDR_IDENTIFIER		0x33443
#define BD_HDR_VOLTAGE			0x33445
#define BD_HDR_AMPERAGE			0x33447
#define BD_HDR_UNKNOWN_CTR		0x33448
#define BD_HDR_SOC				0x33449
#define BD_HDR_STATE			0x3344A
#define BD_HDR_BUTTON_SRB		0x3344C
#define BD_HDR_TIMESTAMP		0x3344E
#define BD_HDR_UNKNOWN_A		0x1B418
#define BD_HDR_UNKNOWN_B		0x2B418
#define BD_HDR_BUTTON_XRB		0x3B41A

// Battery type, mirrored in ui.qml.
#define BD_BAT_UNKNOWN			0
#define BD_BAT_SRB				1
#define BD_BAT_XRB				2
#define BD_BAT_REV				3

#define BD_BTN_SRC_SRB			0
#define BD_BTN_SRC_XRB			1

#define BD_BTN_HELD_SRB			0x06
#define BD_BTN_HELD_XRB			0x07

// Commands from ui.qml, first byte of a custom-app-data packet.
#define BD_COMM_GET_STATUS		1
#define BD_COMM_GET_CELLS		2
#define BD_COMM_PFAIL_RESET		3

// ---- Tuning -------------------------------------------------------------

#define BD_CELL_MAX				15
#define BD_CELL_COUNT_DEF		12
#define BD_LINE_MAX				64	// longest AFE report line kept

// "No reading yet" marker for the cell table.
#define BD_CELL_MV_NONE			0xFFFF

#define BD_TICK_MS				100
#define BD_PING_INTERVAL		0.1f
#define BD_CELL_REQ_INTERVAL	0.5f
#define BD_LINK_TIMEOUT			1.0f	// pack considered gone, stop talking
#define BD_STATUS_TIMEOUT		2.0f	// what ui.qml is told
#define BD_BTN_TIMEOUT			1.0f	// latched button state expires
#define BD_BMS_TIMEOUT			5.0f

// Integer digits an AFE cell voltage must have, exactly. Readings are
// millivolts at a fixed four-digit width, zero padded: fewer digits means the
// line was truncated, more means a line boundary was lost and two readings
// ran together. The fixed width is also why a collapsed cell still reads
// correctly - 412 mV arrives as "0412", not as something indistinguishable
// from "4123" minus its last byte.
#define BD_CELL_DIGITS			4

// Never accumulate more than this many digits, so a corrupted line cannot
// overflow the accumulator before the digit count rejects it.
#define BD_DIGITS_MAX			9

// The blob ext-boosted-bms hands to lisp: fixed header, then one u16 per
// cell. Layout is at the extension; offsets are mirrored in code.lbm. Derived
// from BD_CELL_MAX so raising the ceiling cannot leave the buffer behind.
#define BD_BMS_CELLS_OFF		20
#define BD_BMS_LEN				(BD_BMS_CELLS_OFF + BD_CELL_MAX * 2)

// Where the serialized config lives in the firmware's eeprom vars, which are
// 32-bit NVS-backed slots. This package uses no others, so it starts at 0.
#define BD_EEPROM_BASE			0
#define BD_CONFIG_WORDS			((SERIALIZED_CONFIG_LENGTH - 1) / 4 + 1)

// ---- State --------------------------------------------------------------

typedef struct {
	lib_thread thd;

	// Written only by the CAN rx callback (see the concurrency note above).
	volatile float last_rx_time;
	volatile float last_btn_time;
	volatile int32_t pack_mv;
	volatile int32_t current_ma;	// pack average, sign as the pack reports it
	volatile int32_t cell_min_mv;
	volatile int32_t cell_max_mv;
	volatile int32_t soc_pct;
	volatile int32_t bat_type;
	volatile int32_t btn_state;
	volatile int32_t btn_src;	// BD_BTN_SRC_*, which table btn_state uses
	volatile int32_t ver_major;
	volatile int32_t ver_minor;
	volatile int32_t ver_patch;
	volatile int32_t cell_count;
	volatile uint16_t cell_mv[BD_CELL_MAX];

	// AFE line assembly and report sequencing. Touched only by the rx
	// callback. expect_cell is the cell number the current report should
	// carry next, or 0 while waiting for a report to start.
	char line[BD_LINE_MAX];
	int line_len;
	bool line_ovf;
	int expect_cell;
	int last_report_n;	// cells in the previous clean report, for shrinking

	// Touched only by the tx thread.
	uint32_t ping_counter;

	// Written by set_cfg on the comms thread, read by the lisp extension.
	// One byte, so a reader cannot catch it half updated.
	BoostedConfig cfg;

	volatile bool debug;
} bd_state;

static bd_state *state(void) {
	return (bd_state*)ARG;
}

// ---- Config persistence -------------------------------------------------
//
// Express takes a base index and a count and does the whole config in one NVS
// transaction; bldc stores one 32-bit slot per call.

static bool cfg_write(bd_state *st) {
	uint32_t buf[BD_CONFIG_WORDS];
	memset(buf, 0, sizeof(buf));

	int32_t len = confparser_serialize_boostedconfig((uint8_t*)buf, &st->cfg);
	if (len > (int32_t)sizeof(buf)) {
		VESC_IF->printf("boosted: serialized config too big");
		return false;
	}

#ifdef ESP_PLATFORM
	if (!VESC_IF->store_eeprom_var(
			(eeprom_var*)buf, BD_EEPROM_BASE, BD_CONFIG_WORDS)) {
		VESC_IF->printf("boosted: eeprom write failed");
		return false;
	}
#else
	for (uint32_t i = 0; i < BD_CONFIG_WORDS; i++) {
		eeprom_var v;
		v.as_u32 = buf[i];
		if (!VESC_IF->store_eeprom_var(&v, BD_EEPROM_BASE + (int)i)) {
			VESC_IF->printf("boosted: eeprom write failed");
			return false;
		}
	}
#endif

	return true;
}

static void cfg_read(bd_state *st) {
	uint32_t buf[BD_CONFIG_WORDS];
	bool read_ok = true;

#ifdef ESP_PLATFORM
	read_ok = VESC_IF->read_eeprom_var(
			(eeprom_var*)buf, BD_EEPROM_BASE, BD_CONFIG_WORDS);
#else
	for (uint32_t i = 0; i < BD_CONFIG_WORDS; i++) {
		eeprom_var v;
		if (!VESC_IF->read_eeprom_var(&v, BD_EEPROM_BASE + (int)i)) {
			read_ok = false;
			break;
		}
		buf[i] = v.as_u32;
	}
#endif

	// The deserializer checks the signature VESC Tool derived from
	// settings.xml, so anything written by an older parameter layout is
	// rejected and the defaults are used. No magic number of our own needed.
	if (!read_ok ||
			!confparser_deserialize_boostedconfig((uint8_t*)buf, &st->cfg)) {
		VESC_IF->printf("boosted: no stored config, using defaults");
		confparser_set_defaults_boostedconfig(&st->cfg);
	}
}

// ---- Custom config interface (VESC Tool) --------------------------------

// COMM_GET_CUSTOM_CONFIG / COMM_GET_CUSTOM_CONFIG_DEFAULT.
static int get_cfg(uint8_t *buffer, bool is_default) {
	bd_state *st = state();
	if (st == 0) {
		return 0;
	}

	if (is_default) {
		// Built into a heap copy so asking for the defaults does not disturb
		// the live config.
		BoostedConfig *cfg = VESC_IF->malloc(sizeof(BoostedConfig));
		if (cfg == 0) {
			return 0;
		}
		confparser_set_defaults_boostedconfig(cfg);
		int res = confparser_serialize_boostedconfig(buffer, cfg);
		VESC_IF->free(cfg);
		return res;
	}

	return confparser_serialize_boostedconfig(buffer, &st->cfg);
}

// COMM_SET_CUSTOM_CONFIG, i.e. the user pressed write in VESC Tool.
// Persisting here is what makes the setting survive a reboot.
static bool set_cfg(uint8_t *buffer) {
	bd_state *st = state();
	if (st == 0) {
		return false;
	}

	bool res = confparser_deserialize_boostedconfig(buffer, &st->cfg);
	if (res) {
		cfg_write(st);
		VESC_IF->printf("boosted: BMS publishing %s",
				st->cfg.bms_enabled ? "enabled" : "disabled");
	}

	return res;
}

// COMM_GET_CUSTOM_CONFIG_XML. data_boostedconfig_ is the compiled
// settings.xml emitted into confxml.c, so it needs the target's own way of
// resolving a symbol defined in another translation unit.
static int get_cfg_xml(uint8_t **buffer) {
#ifdef ESP_PLATFORM
	*buffer = VESC_LIB_SYM_ADDR(data_boostedconfig_);
#else
	// The address is relative to where the symbol sits in the linked binary,
	// so PROG_ADDR turns it into where it ended up on the STM32.
	*buffer = data_boostedconfig_ + PROG_ADDR;
#endif
	return DATA_BOOSTEDCONFIG__SIZE;
}

// ---- Little-endian readers ---------------------------------------------

static uint16_t rd_u16(const uint8_t *d, int i) {
	return (uint16_t)((uint32_t)d[i] | ((uint32_t)d[i + 1] << 8));
}

static uint32_t rd_u32(const uint8_t *d, int i) {
	return (uint32_t)d[i] | ((uint32_t)d[i + 1] << 8) |
			((uint32_t)d[i + 2] << 16) | ((uint32_t)d[i + 3] << 24);
}

static int32_t rd_i32(const uint8_t *d, int i) {
	return (int32_t)rd_u32(d, i);
}

// ---- Number formatting --------------------------------------------------
//
// Hand-rolled because a float-capable snprintf would dwarf the rest of the
// library. Every quantity is already integer mV or mA, so put_milli just
// places the point.

static int put_uint(char *p, uint32_t v) {
	char tmp[12];
	int n = 0;

	if (v == 0) {
		p[0] = '0';
		return 1;
	}

	while (v > 0) {
		tmp[n++] = (char)('0' + (v % 10));
		v /= 10;
	}

	for (int i = 0; i < n; i++) {
		p[i] = tmp[n - 1 - i];
	}

	return n;
}

static int put_int(char *p, int32_t v) {
	int n = 0;

	if (v < 0) {
		p[n++] = '-';
		v = -v;
	}

	return n + put_uint(p + n, (uint32_t)v);
}

// Print a value given in thousandths with `dec` (0..3) decimals, rounded.
static int put_milli(char *p, int32_t milli, int dec) {
	int n = 0;

	if (milli < 0) {
		p[n++] = '-';
		milli = -milli;
	}

	int32_t scale = 1;			// 10^(3 - dec), what we round away
	for (int i = dec; i < 3; i++) {
		scale *= 10;
	}

	int32_t pow10 = 1;			// 10^dec
	for (int i = 0; i < dec; i++) {
		pow10 *= 10;
	}

	int32_t v = (milli + scale / 2) / scale;
	n += put_uint(p + n, (uint32_t)(v / pow10));

	if (dec > 0) {
		p[n++] = '.';
		int32_t frac = v % pow10;
		for (int32_t d = pow10 / 10; d > 0; d /= 10) {
			p[n++] = (char)('0' + ((frac / d) % 10));
		}
	}

	return n;
}

// ---- Transmit -----------------------------------------------------------

static void send_routing_cmd(bd_state *st) {
	uint8_t d = 0x01;
	VESC_IF->can_transmit_eid(BD_EID_ROUTING, &d, 1);

	if (st->debug) {
		VESC_IF->printf("TX: Routing Cmd");
	}
}

// AFE commands go out as one 8-byte frame on the high ID plus the tail on
// the low ID. Copied onto the stack rather than transmitted straight out of
// .rodata, so the payload path is identical on every target.
static void send_afe_cmd(const char *cmd, int len) {
	uint8_t buf[8];
	int head = len < 8 ? len : 8;

	for (int i = 0; i < head; i++) {
		buf[i] = (uint8_t)cmd[i];
	}
	VESC_IF->can_transmit_eid(BD_EID_AFE_CMD_HI, buf, (uint8_t)head);

	if (len > 8) {
		int tail = len - 8;
		for (int i = 0; i < tail; i++) {
			buf[i] = (uint8_t)cmd[8 + i];
		}
		VESC_IF->can_transmit_eid(BD_EID_AFE_CMD_LO, buf, (uint8_t)tail);
	}
}

static void send_get_afe_cells(bd_state *st) {
	send_afe_cmd("GETAFECELLS\r\n", 13);

	if (st->debug) {
		VESC_IF->printf("TX: GETAFECELLS");
	}
}

static void send_pfail_reset(void) {
	send_afe_cmd("PFAILRESET\r\n", 12);
	VESC_IF->printf("TX: PFAILRESET");
}

static void send_reboot(void) {
	uint8_t buf[8];
	const char *cmd = "REBOOT\r\n";

	for (int i = 0; i < 8; i++) {
		buf[i] = (uint8_t)cmd[i];
	}
	VESC_IF->can_transmit_eid(BD_EID_REBOOT, buf, 8);

	VESC_IF->printf("TX: REBOOT");
}

static void send_ping(bd_state *st) {
	uint8_t buf[8];

	for (int i = 0; i < 8; i++) {
		buf[i] = 0;
	}

	uint32_t id = BD_EID_PING_BASE + (st->ping_counter & 0xF);
	VESC_IF->can_transmit_eid(id, buf, 8);
	st->ping_counter++;

	if (st->debug) {
		VESC_IF->printf("TX Ping ID: 0x%X", (unsigned int)id);
	}
}

// ---- AFE cell report ----------------------------------------------------

// Read a run of decimal digits starting at *i. Stops accumulating past
// BD_DIGITS_MAX so a corrupted line cannot overflow the accumulator, but
// keeps counting, so the caller still sees how long the run really was.
static int32_t read_digits(const char *line, int len, int *i, int *digits) {
	int32_t v = 0;
	int n = 0;

	while (*i < len && line[*i] >= '0' && line[*i] <= '9') {
		if (n < BD_DIGITS_MAX) {
			v = v * 10 + (line[*i] - '0');
		}
		(*i)++;
		n++;
	}

	*digits = n;

	return v;
}

// Parse one reassembled report line, e.g. "Cell 3: 4123.45", and fold the
// reading into the cell table. Returns true when a value was accepted.
//
// A frame lost on the bus splices the byte stream rather than announcing
// itself, so a reading is trusted only if it has exactly four integer digits
// - catching both "Cell 3: 41" and "Cell 3: 41234130" - and is the line the
// report should carry next. The AFE answers GETAFECELLS with one line per
// cell ascending, so a gap discards the rest of that report until the next
// one starts at cell 1.
static bool parse_cell_line(bd_state *st, const char *line, int len) {
	if (len <= 5 || line[0] != 'C' || line[1] != 'e' ||
			line[2] != 'l' || line[3] != 'l') {
		return false;
	}

	int i = 4;
	while (i < len && line[i] == ' ') {
		i++;
	}

	int digits = 0;
	int cell = (int)read_digits(line, len, &i, &digits);
	if (digits == 0 || cell < 1 || cell > BD_CELL_MAX) {
		return false;
	}

	while (i < len && line[i] == ' ') {
		i++;
	}
	if (i < len && line[i] == ':') {
		i++;
	}
	while (i < len && line[i] == ' ') {
		i++;
	}

	// The fractional part is read past but not used: the table holds whole
	// millivolts, which is the resolution the rest of the package works in.
	int32_t mv = read_digits(line, len, &i, &digits);

	// No digits at all is some other line that happens to begin with "Cell",
	// not a damaged reading, so it leaves the report sequence alone.
	if (digits == 0) {
		return false;
	}

	// mv of 0 is accepted: see BD_CELL_MV_NONE. digits == BD_CELL_DIGITS
	// already bounds it to 0..9999.
	if (digits != BD_CELL_DIGITS) {
		// Only the first failure in a report is reported; expect_cell is
		// already 0 for the rest of it.
		if (st->expect_cell != 0) {
			VESC_IF->printf("Dropped malformed cell %d: %d digits (%d)",
					cell, digits, (int)mv);
		}
		st->expect_cell = 0;
		return false;
	}

	if (cell == 1) {
		// Start of a fresh report, and the point at which the previous one
		// can be sized: a report that ran cleanly from cell 1 to N says the
		// pack has N cells. Nothing else does, and packs differ (SR 12S,
		// XR 13S) and can be swapped without a reboot.
		if (st->expect_cell > 1) {
			int n = st->expect_cell - 1;

			if (n > st->cell_count) {
				st->cell_count = n;
			} else if (n < st->cell_count && n == st->last_report_n) {
				// Shrink only once two reports agree, so a report that lost
				// its tail cannot drop a live cell. Clear above the new count
				// so stale readings cannot reappear on a larger pack.
				st->cell_count = n;
				for (int i = n; i < BD_CELL_MAX; i++) {
					st->cell_mv[i] = BD_CELL_MV_NONE;
				}
			}

			st->last_report_n = n;
		}

		st->expect_cell = 1;
	} else if (st->expect_cell == 0 || cell != st->expect_cell) {
		if (st->expect_cell != 0) {
			VESC_IF->printf("Dropped out-of-sequence cell %d (expected %d)",
					cell, st->expect_cell);
		}
		st->expect_cell = 0;
		return false;
	}

	st->cell_mv[cell - 1] = (uint16_t)mv;
	st->expect_cell = cell + 1;

	if (cell > st->cell_count) {
		st->cell_count = cell;
	}

	return true;
}

// Feed AFE stream bytes through the line buffer. CR is dropped and LF ends a
// line. A line longer than the buffer is discarded whole rather than parsed
// as its own truncated prefix.
static void afe_feed(bd_state *st, const uint8_t *data, int len) {
	for (int i = 0; i < len; i++) {
		char c = (char)data[i];

		if (c == '\n') {
			if (st->line_ovf) {
				st->expect_cell = 0;
			} else if (st->line_len > 0 &&
					parse_cell_line(st, st->line, st->line_len) && st->debug) {
				VESC_IF->printf("RX: Parsed cell line");
			}
			st->line_len = 0;
			st->line_ovf = false;
		} else if (c != '\r') {
			if (st->line_len < BD_LINE_MAX) {
				st->line[st->line_len++] = c;
			} else {
				st->line_ovf = true;
			}
		}
	}
}

// ---- CAN receive --------------------------------------------------------

static const char *btn_state_str_srb(int32_t s) {
	switch (s) {
	case 0x01: return "Pressed 1x";
	case 0x02: return "Pressed 2x";
	case 0x03: return "Pressed 3x";
	case 0x04: return "Pressed 4x";
	case 0x05: return "Pressed 5x";
	case 0x06: return "Pressed Now";
	case 0x07: return "Held <1s";
	case 0x08: return "Held <2s";
	case 0x09: return "Held >2s";
	case 0x0A: return "Was Held <1.5s";
	case 0x0B: return "Was Held <2s";
	case 0x0C: return "Was Held >2s";
	default: return 0;
	}
}

static const char *btn_state_str_xrb(int32_t s) {
	switch (s) {
	case 0x05: return "Charging";
	case 0x06: return "Shutting Down";
	case 0x07: return "Pressed Now";
	case 0x08: return "Finalizing";
	case 0x09: return "Pressed 1x";
	case 0x0A: return "Pressed 2x";
	case 0x0B: return "Pressed 3x";
	case 0x0C: return "Pressed 4x";
	case 0x0D: return "Pressed 5x";
	case 0x0E: return "Held <1s";
	case 0x0F: return "Held <1.5s";
	case 0x10: return "Held <2s";
	case 0x11: return "Held <2.5s";
	case 0x12: return "Was Held <1.5s";
	case 0x13: return "Was Held <2s";
	case 0x14: return "Was Held >2.5s";
	default: return 0;
	}
}

static bool can_rx(uint32_t id, uint8_t *data, uint8_t len) {
	bd_state *st = state();
	if (st == 0) {
		return false;
	}

	uint32_t header = (id >> 4) & 0xFFFFF;
	float now = VESC_IF->system_time();

	switch (header) {
	case BD_HDR_AFE_A:
	case BD_HDR_AFE_B:
	case BD_HDR_AFE_C:
		afe_feed(st, data, len);
		break;

	case BD_HDR_VOLTAGE:
		if (len >= 8) {
			st->last_rx_time = now;
			st->cell_min_mv = rd_u16(data, 0);
			st->cell_max_mv = rd_u16(data, 2);
			st->pack_mv = (int32_t)rd_u32(data, 4);

			if (st->debug) {
				VESC_IF->printf("  -> [VOLTAGE] Pack: %d mV | Cells: %d - %d mV",
						(int)st->pack_mv, (int)st->cell_min_mv, (int)st->cell_max_mv);
			}
		}
		break;

	case BD_HDR_SOC:
		// Deliberately does not refresh last_rx_time: the pack keeps
		// broadcasting SOC in states where the link is otherwise dead.
		if (len >= 5) {
			st->soc_pct = data[4];

			if (st->debug) {
				int charge_status = len > 6 ? data[6] : 0;
				VESC_IF->printf("  -> [SOC] %d%% (Status: %d)",
						(int)st->soc_pct, charge_status);
			}
		}
		break;

	case BD_HDR_AMPERAGE:
		if (len >= 8) {
			st->last_rx_time = now;
			st->current_ma = rd_i32(data, 0);

			if (st->debug) {
				VESC_IF->printf("  -> [AMPS] Avg: %d mA | Inst: %d mA",
						(int)st->current_ma, (int)rd_i32(data, 4));
			}
		}
		break;

	case BD_HDR_VERSION:
		if (len >= 3) {
			st->last_rx_time = now;
			st->ver_major = data[0];
			st->ver_minor = data[1];
			st->ver_patch = data[2];

			if (st->debug) {
				VESC_IF->printf("  -> [VERSION] v%d.%d.%d",
						(int)data[0], (int)data[1], (int)data[2]);
			}
		}
		break;

	case BD_HDR_IDENTIFIER:
		if (len >= 8) {
			st->last_rx_time = now;

			int32_t type = BD_BAT_UNKNOWN;
			if (data[0] == 0xD2) {
				type = BD_BAT_SRB;
			} else if (data[0] == 0x81) {
				if (data[4] == 0x0C) {
					type = BD_BAT_REV;
				} else if (data[4] == 0x0D) {
					type = BD_BAT_XRB;
				}
			}
			st->bat_type = type;

			if (st->debug) {
				VESC_IF->printf("  -> [ID] Enum: %d", (int)type);
			}
		}
		break;

	case BD_HDR_TIMESTAMP:
		if (len >= 7) {
			st->last_rx_time = now;

			if (st->debug) {
				VESC_IF->printf("  -> [TIME] 20%02d-%02d-%02d %02d:%02d:%02d",
						(int)data[6], (int)data[5], (int)data[4],
						(int)data[2], (int)data[1], (int)data[0]);
			}
		}
		break;

	case BD_HDR_BUTTON_SRB:
		if (len >= 2) {
			st->btn_state = data[0];
			st->btn_src = BD_BTN_SRC_SRB;
			st->last_btn_time = now;

			const char *s = btn_state_str_srb(data[0]);
			if (s != 0) {
				VESC_IF->printf("  -> [BUTTON] %s (Pairing: %d)", s, (int)data[1]);
			} else {
				VESC_IF->printf("  -> [BUTTON] 0x%02X (Pairing: %d)",
						(int)data[0], (int)data[1]);
			}
		}
		break;

	case BD_HDR_BUTTON_XRB:
		if (len >= 2) {
			st->btn_state = data[1];
			st->btn_src = BD_BTN_SRC_XRB;
			st->last_btn_time = now;

			const char *s = btn_state_str_xrb(data[1]);
			if (s != 0) {
				VESC_IF->printf("  -> [XRB BUTTON] %s", s);
			} else {
				VESC_IF->printf("  -> [XRB BUTTON] 0x%02X", (int)data[1]);
			}
		}
		break;

	case BD_HDR_STATE:
		if (len >= 7 && st->debug) {
			int timer = data[1] | (data[2] << 8);
			VESC_IF->printf("  -> [STATE] Pwr: 0x%02X | Tmr: %d ms | TS: %d ms | Chg: %d",
					(int)data[3], timer, (int)data[6], (int)data[0]);
		}
		break;

	case BD_HDR_SERIAL:
		if (st->debug) {
			VESC_IF->printf("  -> [SERIAL]");
		}
		break;

	case BD_HDR_UNKNOWN_CTR:
	case BD_HDR_UNKNOWN_A:
	case BD_HDR_UNKNOWN_B:
	default:
		break;
	}

	// Never consume the frame. The lisp implementation this replaces used
	// event-can-eid, which cannot consume either, so the rest of the CAN
	// stack keeps seeing exactly what it saw before.
	return false;
}

// ---- Custom app data (ui.qml) -------------------------------------------

static void send_status(bd_state *st) {
	char buf[128];
	int n = 0;
	const char *tag = "data:status ";

	for (int i = 0; tag[i] != '\0'; i++) {
		buf[n++] = tag[i];
	}

	float age = VESC_IF->system_time() - st->last_rx_time;
	int connected = age < BD_STATUS_TIMEOUT ? 1 : 0;

	n += put_int(buf + n, connected);
	buf[n++] = ' ';
	n += put_int(buf + n, st->bat_type);
	buf[n++] = ' ';
	n += put_int(buf + n, st->ver_major);
	buf[n++] = ' ';
	n += put_int(buf + n, st->ver_minor);
	buf[n++] = ' ';
	n += put_int(buf + n, st->ver_patch);
	buf[n++] = ' ';
	n += put_milli(buf + n, st->pack_mv, 2);
	buf[n++] = ' ';
	n += put_int(buf + n, st->soc_pct);
	buf[n++] = ' ';
	n += put_milli(buf + n, st->cell_min_mv, 3);
	buf[n++] = ' ';
	n += put_milli(buf + n, st->cell_max_mv, 3);
	buf[n++] = ' ';
	n += put_milli(buf + n, st->current_ma, 2);
	buf[n++] = ' ';
	n += put_int(buf + n, st->btn_state);
	buf[n++] = ' ';
	n += put_int(buf + n, st->btn_src);

	VESC_IF->send_app_data((unsigned char*)buf, (unsigned int)n);
}

static void send_cells(bd_state *st) {
	// "data:cells" plus BD_CELL_MAX readings of at most six characters each.
	char buf[128];
	int n = 0;
	const char *tag = "data:cells";

	for (int i = 0; tag[i] != '\0'; i++) {
		buf[n++] = tag[i];
	}

	int count = st->cell_count;
	if (count > BD_CELL_MAX) {
		count = BD_CELL_MAX;
	}

	for (int i = 0; i < count; i++) {
		uint16_t mv = st->cell_mv[i];
		buf[n++] = ' ';
		// ui.qml divides by 1000 unconditionally, so an unread cell goes out
		// as 0 and renders 0.000 V - as does a real 0000 mV reading.
		n += put_uint(buf + n, mv == BD_CELL_MV_NONE ? 0 : mv);
	}

	VESC_IF->send_app_data((unsigned char*)buf, (unsigned int)n);
}

static void app_data_rx(unsigned char *data, unsigned int len) {
	bd_state *st = state();
	if (st == 0 || len < 1) {
		return;
	}

	switch (data[0]) {
	case BD_COMM_GET_STATUS:
		send_status(st);
		break;

	case BD_COMM_GET_CELLS:
		send_cells(st);
		break;

	case BD_COMM_PFAIL_RESET:
		send_pfail_reset();
		send_reboot();
		break;

	default:
		break;
	}
}

// ---- Keep-alive thread --------------------------------------------------

static void tx_thd(void *arg) {
	bd_state *st = (bd_state*)arg;
	float last_ping = 0.0f;
	float last_cell_req = 0.0f;

	while (!VESC_IF->should_terminate()) {
		VESC_IF->sleep_ms(BD_TICK_MS);

		float now = VESC_IF->system_time();
		bool connected = (now - st->last_rx_time) < BD_LINK_TIMEOUT;

		if (connected) {
			// The pack powers itself down about ten minutes after it stops
			// hearing this.
			if ((now - last_ping) > BD_PING_INTERVAL) {
				send_ping(st);
				last_ping = now;
			}

			if ((now - last_cell_req) > BD_CELL_REQ_INTERVAL) {
				send_routing_cmd(st);
				send_get_afe_cells(st);
				last_cell_req = now;
			}
		}

		// A press is latched so the UI can show it. "Pressed now" is a level
		// the pack re-sends, not an event, so it is the one state left alone.
		int32_t btn = st->btn_state;
		int32_t held = st->btn_src == BD_BTN_SRC_XRB
				? BD_BTN_HELD_XRB : BD_BTN_HELD_SRB;
		if (btn > 0 && btn != held &&
				(now - st->last_btn_time) > BD_BTN_TIMEOUT) {
			st->btn_state = 0;
		}
	}
}

// ---- Lisp extensions ----------------------------------------------------

// (ext-boosted-bms) -> byte array, laid out little-endian as
//
//   0  u8   link up (last pack frame newer than BD_STATUS_TIMEOUT)
//   1  u8   cell count
//   2  u8   battery type
//   3  u8   button state
//   4  i32  pack voltage, mV
//   8  i32  pack current, mA (average, sign as the pack reports it)
//  12  u16  lowest cell, mV
//  14  u16  highest cell, mV
//  16  u8   state of charge, percent
//  17  u8   firmware major
//  18  u8   firmware minor
//  19  u8   firmware patch
//  20  u16  cell voltages, mV, BD_CELL_MAX entries, 0xFFFF where no reading
//           has arrived yet. 0 is a real value, not a placeholder.
//
// Returns nil when nothing should be published - the "Publish as VESC BMS"
// setting is off, or the pack has been quiet longer than BD_BMS_TIMEOUT - so
// code.lbm skips set-bms-val and send-bms-can. Both are re-checked every
// poll, so enabling the setting or reconnecting takes effect on the next one.
static lbm_value ext_bms(lbm_value *args, lbm_uint argn) {
	(void)args;
	(void)argn;

	bd_state *st = state();
	if (st == 0) {
		return VESC_IF->lbm_enc_sym_eerror;
	}

	if (!st->cfg.bms_enabled) {
		return VESC_IF->lbm_enc_sym_nil;
	}

	if ((VESC_IF->system_time() - st->last_rx_time) > BD_BMS_TIMEOUT) {
		return VESC_IF->lbm_enc_sym_nil;
	}

	lbm_value res;
	if (!VESC_IF->lbm_create_byte_array(&res, BD_BMS_LEN)) {
		return VESC_IF->lbm_enc_sym_merror;
	}

	uint8_t *out = (uint8_t*)VESC_IF->lbm_dec_str(res);
	if (out == 0) {
		return VESC_IF->lbm_enc_sym_eerror;
	}

	int count = st->cell_count;
	if (count > BD_CELL_MAX) {
		count = BD_CELL_MAX;
	}

	float age = VESC_IF->system_time() - st->last_rx_time;

	out[0] = age < BD_STATUS_TIMEOUT ? 1 : 0;
	out[1] = (uint8_t)count;
	out[2] = (uint8_t)st->bat_type;
	out[3] = (uint8_t)st->btn_state;

	uint32_t pack = (uint32_t)st->pack_mv;
	out[4] = (uint8_t)pack;
	out[5] = (uint8_t)(pack >> 8);
	out[6] = (uint8_t)(pack >> 16);
	out[7] = (uint8_t)(pack >> 24);

	uint32_t cur = (uint32_t)st->current_ma;
	out[8] = (uint8_t)cur;
	out[9] = (uint8_t)(cur >> 8);
	out[10] = (uint8_t)(cur >> 16);
	out[11] = (uint8_t)(cur >> 24);

	out[12] = (uint8_t)st->cell_min_mv;
	out[13] = (uint8_t)(st->cell_min_mv >> 8);
	out[14] = (uint8_t)st->cell_max_mv;
	out[15] = (uint8_t)(st->cell_max_mv >> 8);

	out[16] = (uint8_t)st->soc_pct;
	out[17] = (uint8_t)st->ver_major;
	out[18] = (uint8_t)st->ver_minor;
	out[19] = (uint8_t)st->ver_patch;

	for (int i = 0; i < BD_CELL_MAX; i++) {
		uint16_t mv = st->cell_mv[i];
		out[BD_BMS_CELLS_OFF + i * 2] = (uint8_t)mv;
		out[BD_BMS_CELLS_OFF + i * 2 + 1] = (uint8_t)(mv >> 8);
	}

	return res;
}

// (ext-boosted-debug on) -> t. Turns the per-frame decode trace on or off.
static lbm_value ext_debug(lbm_value *args, lbm_uint argn) {
	bd_state *st = state();
	if (st == 0 || argn != 1 || !VESC_IF->lbm_is_number(args[0])) {
		return VESC_IF->lbm_enc_sym_eerror;
	}

	st->debug = VESC_IF->lbm_dec_as_i32(args[0]) != 0;

	return VESC_IF->lbm_enc_sym_true;
}

// ---- Lifecycle ----------------------------------------------------------

static void stop(void *arg) {
	bd_state *st = (bd_state*)arg;

	// Drop the callbacks before the state they read goes away.
#ifdef ESP_PLATFORM
	VESC_IF->can_set_eid_rx_callback(0);
#else
	VESC_IF->can_set_eid_cb(0);
#endif
	VESC_IF->set_app_data_handler(0);
	VESC_IF->conf_custom_clear_configs();

	if (st != 0) {
		if (st->thd != 0) {
			VESC_IF->request_terminate(st->thd);
		}
		VESC_IF->free(st);
	}

	VESC_IF->printf("boosted lib stopped");
}

INIT_FUN(lib_info *info) {
	INIT_START

	bd_state *st = VESC_IF->malloc(sizeof(bd_state));
	if (st == 0) {
		return false;
	}

	for (unsigned int i = 0; i < sizeof(bd_state); i++) {
		((uint8_t*)st)[i] = 0;
	}

	st->cell_count = BD_CELL_COUNT_DEF;

	for (int i = 0; i < BD_CELL_MAX; i++) {
		st->cell_mv[i] = BD_CELL_MV_NONE;
	}

	// Published before anything that can call state(): the CAN callback and
	// the config callbacks have no user pointer and reach the state through
	// ARG.
	info->arg = st;
	info->stop_fun = stop;

	cfg_read(st);
	VESC_IF->conf_custom_add_config(get_cfg, set_cfg, get_cfg_xml);

	VESC_IF->lbm_add_extension("ext-boosted-bms", ext_bms);
	VESC_IF->lbm_add_extension("ext-boosted-debug", ext_debug);

#ifdef ESP_PLATFORM
	VESC_IF->can_set_eid_rx_callback(can_rx);
#else
	VESC_IF->can_set_eid_cb(can_rx);
#endif
	// Something else already owning the custom-app-data hook would leave the
	// UI with no data at all, so say so rather than fail silently.
	if (!VESC_IF->set_app_data_handler(app_data_rx)) {
		VESC_IF->printf("boosted: custom app data handler unavailable, UI will not update");
	}

	st->thd = VESC_IF->spawn(tx_thd, 2048, "boosted_tx", st);
	if (st->thd == 0) {
		stop(st);
		// Cleared so a loader that runs stop_fun on a failed init cannot
		// free the state a second time.
		info->arg = 0;
		info->stop_fun = 0;
		return false;
	}

	VESC_IF->printf("boosted lib loaded");

	return true;
}
