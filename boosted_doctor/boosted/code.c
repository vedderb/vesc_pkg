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
// The whole CAN side of the protocol lives here: the keep-alive ping that
// stops the pack shutting down after ten minutes, the cell-report request,
// the RLOD (PFAILRESET) recovery command, decoding of the periodic 0x334xx
// broadcasts, and reassembly of the AFE's ASCII cell report - which arrives
// as a byte stream chopped across CAN frames, not as fixed-layout data. That
// text reassembly is why this is C: it is a line buffer and a digit loop
// here, where in lisp it was several hundred lines of buffer arithmetic.
//
// The ui.qml side is served from here too, over custom app data, in exactly
// the "data:status ..." / "data:cells ..." format the QML already parses.
//
// What stays in lisp: set-bms-val has no C-interface equivalent, so code.lbm
// polls ext-boosted-bms and republishes the values as VESC BMS state. That
// is the only reason there is any lisp left.
//
// Native-lib constraints shape two things. On the RISC-V Express targets the
// lib executes in place from flash, so there are no writable globals - all
// state lives in one allocated struct reached through ARG, including from
// the CAN rx callback, which gets no user pointer of its own. And there is
// no snprintf worth linking into a blob this size, so the status strings are
// formatted by hand; every value is a whole number of mV or mA anyway, so
// the decimal point is placed with integer division.
//
// Concurrency: the CAN rx callback is the only writer of decoded state, and
// every field it writes is a naturally aligned word or halfword. Readers
// (the tx thread, the app-data handler, the lisp extension) can therefore
// never observe a torn value, and no lock is taken on a path that may run in
// interrupt context.

#ifdef ESP_PLATFORM
#include "express/vesc_c_if.h"
#else
#include "vesc_c_if.h"
#endif

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
#define BD_HDR_COUNTER			0x33448
#define BD_HDR_SOC				0x33449
#define BD_HDR_STATE			0x3344A
#define BD_HDR_BUTTON_SRB		0x3344C
#define BD_HDR_TIMESTAMP		0x3344E
#define BD_HDR_COUNTER_B		0x1B418
#define BD_HDR_COUNTER_C		0x2B418
#define BD_HDR_BUTTON_XRB		0x3B41A

// Battery type, mirrored in ui.qml.
#define BD_BAT_UNKNOWN			0
#define BD_BAT_SRB				1
#define BD_BAT_XRB				2
#define BD_BAT_REV				3

// Commands from ui.qml, first byte of a custom-app-data packet.
#define BD_COMM_GET_STATUS		1
#define BD_COMM_GET_CELLS		2
#define BD_COMM_PFAIL_RESET		3

// ---- Tuning -------------------------------------------------------------

#define BD_CELL_MAX				15
#define BD_CELL_COUNT_DEF		12	// until the AFE report says otherwise
#define BD_LINE_MAX				64	// longest AFE report line kept

#define BD_TICK_MS				100
#define BD_PING_INTERVAL		0.1f
#define BD_CELL_REQ_INTERVAL	0.5f
#define BD_LINK_TIMEOUT			1.0f	// pack considered gone, stop talking
#define BD_STATUS_TIMEOUT		2.0f	// what ui.qml is told
#define BD_BTN_TIMEOUT			1.0f	// latched button state expires

// A cell reading more than this fraction away from the previous one for the
// same cell is a mis-framed line rather than a real jump, and is dropped.
#define BD_OUTLIER_DIV			10

// Shortest plausible integer part of an AFE cell voltage. The AFE reports
// millivolts, so a good reading always has at least four digits; a shorter
// one means the line was truncated.
#define BD_CELL_MIN_DIGITS		4

// Size of the blob ext-boosted-bms hands to lisp. Layout is documented at
// the extension itself and mirrored in code.lbm.
#define BD_BMS_LEN				50

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
	volatile int32_t ver_major;
	volatile int32_t ver_minor;
	volatile int32_t ver_patch;
	volatile int32_t cell_count;
	volatile uint16_t cell_mv[BD_CELL_MAX];

	// AFE line assembly. Touched only by the rx callback.
	char line[BD_LINE_MAX];
	int line_len;

	// Touched only by the tx thread.
	uint32_t ping_counter;

	volatile bool debug;
} bd_state;

static bd_state *state(void) {
	return (bd_state*)ARG;
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
// Hand-rolled because linking a float-capable snprintf would dwarf the rest
// of the library. Every quantity is already an integer count of mV or mA, so
// put_milli just places the point.

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

// Parse one reassembled report line, e.g. "Cell 3: 4123.45", and fold the
// reading into the cell table. Returns true when a value was accepted.
static bool parse_cell_line(bd_state *st, const char *line, int len) {
	if (len <= 5 || line[0] != 'C' || line[1] != 'e' ||
			line[2] != 'l' || line[3] != 'l') {
		return false;
	}

	int i = 4;
	while (i < len && line[i] == ' ') {
		i++;
	}

	int cell = 0;
	int digits = 0;
	while (i < len && line[i] >= '0' && line[i] <= '9') {
		cell = cell * 10 + (line[i] - '0');
		i++;
		digits++;
	}
	if (digits == 0) {
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

	int32_t mv = 0;
	digits = 0;
	while (i < len && line[i] >= '0' && line[i] <= '9') {
		mv = mv * 10 + (line[i] - '0');
		i++;
		digits++;
	}

	// The fractional part is read past but not used: the table holds whole
	// millivolts, which is the resolution the rest of the package works in.
	if (digits < BD_CELL_MIN_DIGITS || mv <= 0 ||
			cell < 1 || cell > BD_CELL_MAX) {
		return false;
	}

	int idx = cell - 1;
	int32_t old_mv = st->cell_mv[idx];

	if (old_mv > 0) {
		int32_t diff = mv - old_mv;
		if (diff < 0) {
			diff = -diff;
		}
		if (diff > old_mv / BD_OUTLIER_DIV) {
			VESC_IF->printf("Ignored outlier cell %d: %d (prev: %d)",
					cell, (int)mv, (int)old_mv);
			return false;
		}
	}

	st->cell_mv[idx] = (uint16_t)mv;

	if (cell > st->cell_count) {
		st->cell_count = cell;
	}

	return true;
}

// Feed AFE stream bytes through the line buffer. CR is dropped, LF ends a
// line, and an over-long line is truncated rather than allowed to run on.
static void afe_feed(bd_state *st, const uint8_t *data, int len) {
	for (int i = 0; i < len; i++) {
		char c = (char)data[i];

		if (c == '\n') {
			if (st->line_len > 0 &&
					parse_cell_line(st, st->line, st->line_len) && st->debug) {
				VESC_IF->printf("RX: Parsed cell line");
			}
			st->line_len = 0;
		} else if (c != '\r' && st->line_len < BD_LINE_MAX) {
			st->line[st->line_len++] = c;
		}
	}
}

// ---- CAN receive --------------------------------------------------------

static const char *btn_state_str(int32_t s) {
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
			st->last_btn_time = now;

			const char *s = btn_state_str(data[0]);
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
			st->last_btn_time = now;
			VESC_IF->printf("  -> [XRB BUTTON] State: 0x%02X", (int)data[1]);
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

	case BD_HDR_COUNTER:
	case BD_HDR_COUNTER_B:
	case BD_HDR_COUNTER_C:
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
		buf[n++] = ' ';
		n += put_uint(buf + n, st->cell_mv[i]);
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

		// A press is latched so the UI can show it; "pressed now" (0x06) is
		// a level rather than an event and clears itself.
		int32_t btn = st->btn_state;
		if (btn > 0 && btn != 0x06 &&
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
//  20  u16  cell voltages, mV, BD_CELL_MAX entries
//
// code.lbm unpacks this and republishes it through set-bms-val, which has no
// C-interface equivalent.
static lbm_value ext_bms(lbm_value *args, lbm_uint argn) {
	(void)args;
	(void)argn;

	bd_state *st = state();
	if (st == 0) {
		return VESC_IF->lbm_enc_sym_eerror;
	}

	lbm_value res;
	if (!VESC_IF->lbm_create_byte_array(&res, BD_BMS_LEN)) {
		return VESC_IF->lbm_enc_sym_merror;
	}

	uint8_t *b = (uint8_t*)VESC_IF->lbm_dec_str(res);
	if (b == 0) {
		return VESC_IF->lbm_enc_sym_eerror;
	}

	int count = st->cell_count;
	if (count > BD_CELL_MAX) {
		count = BD_CELL_MAX;
	}

	float age = VESC_IF->system_time() - st->last_rx_time;

	b[0] = age < BD_STATUS_TIMEOUT ? 1 : 0;
	b[1] = (uint8_t)count;
	b[2] = (uint8_t)st->bat_type;
	b[3] = (uint8_t)st->btn_state;

	uint32_t pack = (uint32_t)st->pack_mv;
	b[4] = (uint8_t)pack;
	b[5] = (uint8_t)(pack >> 8);
	b[6] = (uint8_t)(pack >> 16);
	b[7] = (uint8_t)(pack >> 24);

	uint32_t cur = (uint32_t)st->current_ma;
	b[8] = (uint8_t)cur;
	b[9] = (uint8_t)(cur >> 8);
	b[10] = (uint8_t)(cur >> 16);
	b[11] = (uint8_t)(cur >> 24);

	b[12] = (uint8_t)st->cell_min_mv;
	b[13] = (uint8_t)(st->cell_min_mv >> 8);
	b[14] = (uint8_t)st->cell_max_mv;
	b[15] = (uint8_t)(st->cell_max_mv >> 8);

	b[16] = (uint8_t)st->soc_pct;
	b[17] = (uint8_t)st->ver_major;
	b[18] = (uint8_t)st->ver_minor;
	b[19] = (uint8_t)st->ver_patch;

	for (int i = 0; i < BD_CELL_MAX; i++) {
		uint16_t mv = st->cell_mv[i];
		b[20 + i * 2] = (uint8_t)mv;
		b[21 + i * 2] = (uint8_t)(mv >> 8);
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

	// Published before anything that can call state(): the CAN callback has
	// no user pointer and reaches the state through ARG.
	info->arg = st;
	info->stop_fun = stop;

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
