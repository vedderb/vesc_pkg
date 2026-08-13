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

// ext-esp_led-*: segmented addressable-LED strip engine as a native library.
//
// Lisp sets high-level segment / effect state and a background render thread
// animates, applies brightness / auto-white and pushes pixels.
// The hardware path is the firmware rgbled driver through the C interface,
// addressed by pin: strips are registered with rgbled_init at start and each
// frame's changed groups are pushed with rgbled_update(pin, ...). Behind
// those calls the firmware drives every strip from ONE RMT TX channel,
// re-routed to the target pin through the GPIO matrix per update. Any number
// of pin groups works - the strips latch and hold their last frame - but the
// transmissions serialise on that channel, so a frame's wire time is the sum
// over every group that changed, not the longest one. That is the ceiling a
// high ext-esp_led-fps runs into first on multi-pin setups.
//
// Native-lib constraints shape the implementation: on the RISC-V targets
// the lib executes in place from flash, so there are no writable globals -
// all state lives in one allocated struct reached through ARG - and no
// libm, so the effect math is integer only.
//
// Colors are packed 0xWWRRGGBB ints, like the color-* extensions.

#include "express/vesc_c_if.h"

#include <string.h>

HEADER

#define esp_led_SEG_MAX     8
#define esp_led_OV_MAX      8   // overlay pixels per segment

// Frame pacing. The render loop holds a real cadence - it sleeps the frame
// time minus the work it just did, so that work is absorbed into the frame
// instead of added to it - and advances the effect phase by measured elapsed
// time. Animations therefore keep real-world speed both when the frame rate
// is retuned with ext-esp_led-fps and when the loop falls behind.
#define esp_led_FRAME_MS_DEF   33   // ~30 fps, the default target
#define esp_led_FRAME_MS_MIN   5    // 200 fps ceiling - the lisp VM, wifi and
                                    // bluetooth share this core on the C3/C6
#define esp_led_FRAME_MS_MAX   200  // 5 fps floor

// Phase is counted in units per esp_led_PHASE_REF_MS of real time, so a
// segment's spd keeps the meaning it had when the loop was a fixed 33 ms
// frame: at the default speed an effect looks exactly as it did before the
// frame rate became configurable. Also the reference for the fade rate.
#define esp_led_PHASE_REF_MS   33

// Speed a segment starts at, and the fallback for spd 0 - which reads as
// "unset" rather than "stopped", so a segment that was never given a speed
// still animates.
#define esp_led_SPD_DEF        32

// Brightness easing rate the lib starts at: the fraction of the remaining gap
// closed per esp_led_PHASE_REF_MS, in 32nds. 15/32 is ~47%, i.e. ~0.2 s to
// settle. See ease_u8; 0 would make brightness changes instant.
#define esp_led_FADE_DEF       15

// A late frame advances the phase by the time it actually missed, so
// animations hold real-world time instead of slowing down. Past this the
// jump is capped: a long stall (a blocked transmission, the lisp VM hogging
// the core) should resume the animation, not teleport it.
#define esp_led_CATCHUP_MS_MAX 250

// Milliseconds without changes before a keepalive retransmit: static content
// keeps the data line quiet, but a pixel corrupted by line noise still heals
// shortly. Timed rather than counted in frames so it stays ~2 s at any rate.
#define esp_led_REFRESH_MS 2000

// Effects. Lisp consumers mirror these ids in esp_led_defs.lisp - update that
// file when this enum changes, or the wrong effect is selected silently.
enum {
	FX_OFF = 0,   // all pixels off (ignores the colour) - the zeroed default
	FX_CUSTOM,    // consumer-supplied pixels (ext-esp_led-seg-pixel / -pixels)
	FX_SOLID,     // full strip of the segment colour (or palette if colour = 0)
	FX_BREATHE,
	FX_CHASE,
	FX_RAINBOW,
	FX_SPARKLE,
	FX_COMET,
	FX_GAUGE,     // fill by the fx_val param; battery gradient when color = 0
	FX_STROBE,    // hard on/off flash
	FX_LARSON,    // bouncing eye with tail (knight rider)
	FX_FELONY,    // halves alternate red/blue
	FX_THEATER,   // marquee - every third pixel, marching
	FX_WIPE,      // fill end-to-end, then wipe to black
	FX_WAVES,     // overlapping slow waves (pacifica-like)
	FX_CANDLE,    // warm uneven flicker
	FX_HEARTBEAT, // thump-thump double pulse
	FX_TURN,      // turn signal - the fx_val param selects the mode (see below)
};

// Turn-signal mode, carried in seg.fx_val for the FX_TURN effect. The strip is
// split in half; a mode selects a side (left half / right half / both) and a
// style (solid = steady, blink = flash on/off, sweep = fill centre -> edge).
// Laid out so (mode-1)/3 gives the side and (mode-1)%3 gives the style.
enum {
	TURN_OFF = 0,
	TURN_LEFT_SOLID,   TURN_LEFT_BLINK,   TURN_LEFT_SWEEP,
	TURN_RIGHT_SOLID,  TURN_RIGHT_BLINK,  TURN_RIGHT_SWEEP,
	TURN_HAZARD_SOLID, TURN_HAZARD_BLINK, TURN_HAZARD_SWEEP,
};

// Color byte layouts on the wire
enum {
	TYPE_GRB = 0,
	TYPE_RGB,
	TYPE_GRBW,
	TYPE_RGBW,
	TYPE_WRGB,  // white first (WS2814 and friends)
};

// Wire timing presets. The lib forwards the value to the firmware LED driver;
// it is never switched on here, so this enum is documentation for lisp
// consumers (mirrored into esp_led_defs.lisp by gen_defs.py).
enum {
	TIMING_GENERIC = 0,
	TIMING_WS2812B,
	TIMING_WS2815,
	TIMING_SK6812,
	TIMING_SK6815,
};

// A palette is 4 anchor colors, interpolated across pos 0..255. The
// PAL_<NAME> tag on each row is the canonical id; gen_defs.py mirrors it into
// esp_led_defs.lisp as the row's position + 1, because seg_palette_at()
// reserves 0 for the segment's custom palette (see there). Keep tags unique
// and the rows in id order.
typedef struct { uint32_t c[4]; } palette_t;
static const palette_t palettes[] = {
	{{0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF}}, // PAL_RGBW      rgbw-ish
	{{0xFF0000, 0xFF8000, 0xFFFF00, 0xFF0000}}, // PAL_FIRE      fire
	{{0x0000FF, 0x00FFFF, 0x00FF80, 0x0000FF}}, // PAL_OCEAN     ocean
	{{0xFF00FF, 0x8000FF, 0x0080FF, 0xFF00FF}}, // PAL_NEON      neon
	{{0xFFFFFF, 0xFF4000, 0x400000, 0x000000}}, // PAL_EMBER     ember
	{{0x00FF00, 0xFFFF00, 0xFF0000, 0x00FF00}}, // PAL_TRAFFIC   traffic
	{{0xFFFFFF, 0x000000, 0xFFFFFF, 0x000000}}, // PAL_STROBE    strobe
	{{0x1030FF, 0xFFFFFF, 0x1030FF, 0x001040}}, // PAL_POLICE    police-blue
	{{0x0B1D51, 0xFF6A00, 0xFFD700, 0x2A0E4F}}, // PAL_SUNSET    sunset
	{{0x000000, 0x8B0000, 0xFF4500, 0xFFFFE0}}, // PAL_LAVA      lava
	{{0x01411F, 0x00FFB2, 0x7A00FF, 0x013220}}, // PAL_AURORA    aurora
	{{0x013220, 0x2E8B57, 0x9ACD32, 0x013220}}, // PAL_FOREST    forest
	{{0x8000FF, 0xFF4000, 0xFF00A0, 0x0040FF}}, // PAL_PARTY     party
	{{0x001F5C, 0x00BFFF, 0xFFFFFF, 0x001F5C}}, // PAL_ICE       ice
	{{0xFF6A00, 0x1A001A, 0x8000FF, 0x000000}}, // PAL_HALLOWEEN halloween
	{{0xFF0000, 0x00FF00, 0xFFC000, 0x0000FF}}, // PAL_CHRISTMAS christmas (c9)
	{{0xFFB3BA, 0xBAFFC9, 0xBAE1FF, 0xFFFFBA}}, // PAL_PASTEL    pastel
	{{0xFF2E6A, 0xFFC0CB, 0xFFF0F5, 0xC71585}}, // PAL_SAKURA    sakura
};
#define PALETTE_COUNT ((int)(sizeof(palettes) / sizeof(palettes[0])))

typedef struct {
	bool defined;
	bool on;
	uint8_t pin;
	uint8_t type;      // TYPE_*
	uint8_t timing;    // wire timing preset, 0 = generic
	uint16_t len;      // pixels
	bool reverse;
	bool auto_white;   // Derive the white channel from the common RGB part
	uint8_t fx;
	uint8_t pal;
	uint8_t bri;       // per-segment brightness target 0..255
	uint8_t bri_cur;   // eased current brightness
	uint8_t spd;       // 0..255
	uint8_t size;      // chase head / comet tail length
	// Per-effect parameter: what it means is defined by the effect reading
	// it - the gauge fill 0..255, the turn-signal mode (see the TURN_ enum).
	// Effects that want no parameter simply ignore it.
	uint8_t fx_val;
	uint16_t offset;   // pixel offset within the pin's chain
	uint32_t color;    // packed 0xWWRRGGBB - the target
	// Eased current colour, and the per-segment rate that gets it there. Same
	// units as the brightness fade (32nds of the gap closed per PHASE_REF_MS),
	// and 0 - the default - means colour changes land instantly, so a segment
	// behaves exactly as it did before a consumer opts in. Rendering reads
	// color_cur; everything that sets an appearance writes color.
	uint32_t color_cur;
	uint8_t color_fade;
	uint32_t phase;    // effect position, advanced by elapsed real time
	uint8_t phase_rem; // sub-unit phase carried between frames (render_thd)

	// Overlay pixels: physical LEDs at fixed positions inside the strip
	// (e.g. embedded highbeams) that show ov_color at ov_bri while the
	// effect pixels flow around them. Positions are relative to the
	// segment and extend its footprint to len + ov_count pixels.
	uint8_t ov_count;
	uint8_t ov_idx[esp_led_OV_MAX];
	uint32_t ov_color;
	uint8_t ov_bri;

	// Custom mode: a consumer-supplied pixel buffer (len packed colors) shown
	// by FX_CUSTOM, so consumers can run their own effects while still getting
	// this engine's brightness and channel pooling. NULL until the segment is
	// put in custom mode.
	uint32_t *manual;

	// Custom palette: 4 anchor colours used when pal == 0, so the built-in
	// gradient effects can be recoloured. Set via ext-esp_led-seg-palette.
	uint32_t cpal[4];

	int group;         // pin group index, assigned at init
} seg_t;

// Segments sharing a pin form one chain, rendered into one buffer and
// transmitted once per frame (the segment offsets place them along the
// chain). The firmware LED driver transmits asynchronously from the
// caller's memory and only waits for the previous transmission when the
// next one starts - a long chain can still be shifting out when the next
// frame renders, so each group double buffers: render into one buffer
// while the other may still be on the wire.
typedef struct {
	uint8_t pin;
	uint8_t colors;      // bytes per pixel of the chain
	uint8_t timing;      // wire timing preset of the chain
	uint16_t chain_len;  // pixels
	uint8_t *txbuf[2];   // chain_len * colors bytes each
	uint8_t cur;         // buffer rendered and transmitted this frame
	uint32_t quiet_ms;   // ms since the last transmission
} group_t;

typedef struct {
	lib_thread thread;
	lib_mutex lock;
	volatile bool running;

	seg_t seg[esp_led_SEG_MAX];
	int seg_count;

	group_t group[esp_led_SEG_MAX];
	int group_count;

	uint8_t master_bri;  // target
	uint8_t master_cur;  // eased current
	uint8_t fade;        // gap fraction closed per esp_led_PHASE_REF_MS in
	                     // 32nds, 0 = instant
	uint16_t frame_ms;   // target frame time, set by ext-esp_led-fps

	uint16_t buf_len;    // pixels the work buffer holds
	uint32_t *work;      // packed 0xWWRRGGBB, buf_len entries
} esp_led_t;

static esp_led_t *state(void) {
	return (esp_led_t*)ARG;
}

// ---- Color helpers ------------------------------------------------------

static uint32_t pack(uint32_t r, uint32_t g, uint32_t b, uint32_t w) {
	return (w << 24) | (r << 16) | (g << 8) | b;
}

static uint32_t scale(uint32_t c, uint32_t num) { // num 0..255
	uint32_t w = (((c >> 24) & 0xFF) * num) / 255;
	uint32_t r = (((c >> 16) & 0xFF) * num) / 255;
	uint32_t g = (((c >> 8) & 0xFF) * num) / 255;
	uint32_t b = ((c & 0xFF) * num) / 255;
	return pack(r, g, b, w);
}

// Interpolate a position 0..255 across 4 anchor colours (wrapping).
static uint32_t interp4(const uint32_t *c, uint8_t pos) {
	uint32_t a = c[pos / 64];
	uint32_t b = c[(pos / 64 + 1) % 4];
	uint32_t f = pos % 64; // 0..63 between anchors

	uint32_t r = (((a >> 16) & 0xFF) * (63 - f) + ((b >> 16) & 0xFF) * f) / 63;
	uint32_t g = (((a >> 8) & 0xFF) * (63 - f) + ((b >> 8) & 0xFF) * f) / 63;
	uint32_t bl = ((a & 0xFF) * (63 - f) + (b & 0xFF) * f) / 63;
	return pack(r, g, bl, 0);
}

static uint32_t palette_at(uint8_t pal, uint8_t pos) {
	return interp4(palettes[pal % PALETTE_COUNT].c, pos);
}

// Palette for a segment. pal 0 is the segment's custom palette (cpal); pal
// 1..N map to the built-in palettes (index - 1), so adding custom at 0 did
// not renumber the const table.
static uint32_t seg_palette_at(const seg_t *s, uint8_t pos) {
	if (s->pal == 0) {
		return interp4(s->cpal, pos);
	}
	return palette_at(s->pal - 1, pos);
}

// Triangle wave 0..255..0 over a 512-step period.
static uint32_t triangle(uint32_t x) {
	x &= 511;
	return x < 256 ? x : 511 - x;
}

// ---- Effect renderers ---------------------------------------------------

static void fx_render(const seg_t *s, uint32_t *work) {
	int n = s->len;
	// The phase accumulates spd per frame (see render_thd), so changing
	// the speed only changes the rate from here on - animations speed up
	// or slow down in place instead of jumping to a new position.
	uint32_t ph = s->phase;
	int size = s->size ? s->size : 8;

	// Animation rates. The base is one cycle per ~4 s at the default speed
	// of 32, i.e. 4096 phase units - each effect divides ph so its own
	// period (512 for a triangle, 256 for a uint8_t wrap) lands on that.
	// Switching effects without touching the speed then behaves. Two groups
	// deliberately sit off the base:
	//   - Effects modelling something real keep that thing's rate: the
	//     heartbeat is ~1 s (about 60 bpm), the turn blink ~1.9 Hz (road
	//     signals run 1-2 Hz), strobe and felony stay a hard flash.
	//   - Effects that travel the strip (chase, comet, larson, wipe, turn
	//     sweep) have a period proportional to the LED count, so they hold
	//     pixel velocity rather than crossing time - otherwise a long strip
	//     would run its chase several times faster than a short one.
	//
	// Effects take their color from the color param; a color of 0 means
	// "from the palette" (cycling with the animation phase). Rainbow always
	// renders the palette, solid keeps 0 = black so segments can be
	// blanked, and gauge uses its battery gradient for 0.
	switch (s->fx) {
	case FX_BREATHE: {
		uint32_t b = triangle(ph / 4);
		uint32_t c0 = s->color_cur ? s->color_cur : seg_palette_at(s,(uint8_t)(ph / 128));
		uint32_t c = scale(c0, b);
		for (int i = 0; i < n; i++) work[i] = c;
	} break;

	case FX_CHASE: {
		int head = (int)((ph / 32) % (uint32_t)(n > 0 ? n : 1));
		for (int i = 0; i < n; i++) {
			int d = i - head;
			if (d < 0) d += n;
			uint32_t b = d < size ? 255 - (d * 255) / size : 0;
			uint32_t c = s->color_cur ? s->color_cur
				: seg_palette_at(s,(uint8_t)((i * 255) / (n ? n : 1)));
			work[i] = scale(c, b);
		}
	} break;

	case FX_RAINBOW: {
		for (int i = 0; i < n; i++) {
			uint8_t pos = (uint8_t)((i * 255) / (n ? n : 1) + ph / 16);
			work[i] = seg_palette_at(s,pos);
		}
	} break;

	case FX_SPARKLE: {
		for (int i = 0; i < n; i++) {
			// Deterministic twinkle from phase + index
			uint32_t h = ((uint32_t)i * 2654435761u) ^ ((ph / 128) * 40503u);
			uint32_t c = s->color_cur ? s->color_cur
				: seg_palette_at(s,(uint8_t)(h >> 16));
			work[i] = ((h >> 8) & 0xFF)
				< ((uint32_t)(s->spd ? s->spd : esp_led_SPD_DEF) / 2 + 1) ? c : 0;
		}
	} break;

	case FX_COMET: {
		int head = (int)((ph / 32) % (uint32_t)(n > 0 ? n : 1));
		for (int i = 0; i < n; i++) {
			int d = head - i;
			if (d < 0) d += n;
			uint32_t b = d < size ? 255 - (d * 255) / size : 0;
			uint32_t c = s->color_cur ? s->color_cur : seg_palette_at(s,(uint8_t)(ph / 32));
			work[i] = scale(c, b);
		}
	} break;

	case FX_GAUGE: {
		// Fill the first fx_val/255 of the strip. Fill color: the segment
		// color if set; else the palette as a gradient along the strip,
		// revealed by the fill; else (color 0, palette 0) a battery-style
		// gradient - red when nearly empty, green when full. spd > 0
		// pulses the fill (e.g. while charging).
		int lit = (n * s->fx_val + 254) / 255;
		if (s->fx_val > 0 && lit < 1) lit = 1;
		uint32_t b = s->spd ? 140 + triangle(ph / 8) * 115 / 255
			: 255;
		if (!s->color_cur && s->pal) {
			for (int i = 0; i < n; i++) {
				work[i] = i < lit
					? scale(seg_palette_at(s,(uint8_t)((i * 255) / n)), b)
					: 0;
			}
			break;
		}
		uint32_t c;
		if (s->color_cur) {
			c = s->color_cur;
		} else if (s->fx_val < 51) { // < 20%: red
			c = 0xFF0000;
		} else {
			uint32_t g = ((uint32_t)s->fx_val * 255) / 204; // fx_val/0.8
			if (g > 255) g = 255;
			c = pack(255 - g, g, 0, 0);
		}
		c = scale(c, b);
		for (int i = 0; i < n; i++) work[i] = i < lit ? c : 0;
	} break;

	case FX_STROBE: {
		uint32_t flash = ph / 64;
		uint32_t c = s->color_cur ? s->color_cur
			: seg_palette_at(s,(uint8_t)(flash * 61)); // new hue per flash
		bool lit = flash & 1;
		for (int i = 0; i < n; i++) work[i] = lit ? c : 0;
	} break;

	case FX_LARSON: {
		int span = n > 1 ? n - 1 : 1;
		int pos = (int)((ph / 16) % (uint32_t)(2 * span));
		if (pos > span) pos = 2 * span - pos;
		uint32_t c = s->color_cur ? s->color_cur : seg_palette_at(s,(uint8_t)(ph / 128));
		for (int i = 0; i < n; i++) {
			int d = i > pos ? i - pos : pos - i;
			uint32_t b = d < size ? 255 - (d * 255) / size : 0;
			work[i] = scale(c, b);
		}
	} break;

	case FX_FELONY: {
		bool swap = ((ph / 48) & 1);
		uint32_t c1 = swap ? 0x0000FF : 0xFF0000;
		uint32_t c2 = swap ? 0xFF0000 : 0x0000FF;
		for (int i = 0; i < n; i++) {
			work[i] = i < n / 2 ? c1 : c2;
		}
	} break;

	case FX_THEATER: {
		// Marquee: every third pixel lit, marching along the strip
		int offset = (int)((ph / 64) % 3);
		for (int i = 0; i < n; i++) {
			bool lit = ((i + 3 - offset) % 3) == 0;
			uint32_t c = s->color_cur ? s->color_cur
				: seg_palette_at(s,(uint8_t)((i * 255) / n + ph / 64));
			work[i] = lit ? c : 0;
		}
	} break;

	case FX_WIPE: {
		// Fill end-to-end with color, then wipe to black from the same
		// end. With color 0 each fill cycle takes a new palette color.
		uint32_t period = 2u * (uint32_t)n;
		uint32_t pos = (ph / 32) % period;
		bool filling = pos < (uint32_t)n;
		int edge = (int)(filling ? pos : pos - (uint32_t)n);
		uint32_t c = s->color_cur ? s->color_cur
			: seg_palette_at(s,(uint8_t)(((ph / 32) / period) * 47));
		for (int i = 0; i < n; i++) {
			bool lit = filling ? (i <= edge) : (i > edge);
			work[i] = lit ? c : 0;
		}
	} break;

	case FX_WAVES: {
		// Overlapping slow waves, pacifica-like: one wave picks the
		// palette position, another modulates brightness on top of a
		// floor so the strip shimmers instead of blinking.
		for (int i = 0; i < n; i++) {
			uint32_t p = ((uint32_t)i * 255) / (uint32_t)n;
			uint32_t w1 = triangle(p * 2 + ph / 8);
			uint32_t w2 = triangle(p * 3 + 170 + 1024 - ph / 12);
			uint32_t w3 = triangle(p + 85 + ph / 20);
			uint32_t c0 = s->color_cur ? s->color_cur
				: seg_palette_at(s,(uint8_t)((w1 + w3) / 2));
			work[i] = scale(c0, 64 + (w2 * 191) / 255);
		}
	} break;

	case FX_CANDLE: {
		// Warm uneven flicker: smooth deterministic noise per pixel,
		// interpolated between flicker steps. Color 0 = candle flame
		// (this effect does not cycle the palette).
		uint32_t t = ph / 128;
		uint32_t f = (ph & 127) * 2; // 0..254 between flicker steps
		uint32_t c0 = s->color_cur ? s->color_cur : 0xFF9329;
		for (int i = 0; i < n; i++) {
			uint32_t h1 = ((uint32_t)i * 2654435761u) ^ (t * 40503u);
			uint32_t h2 = ((uint32_t)i * 2654435761u) ^ ((t + 1) * 40503u);
			uint32_t b1 = (h1 >> 8) & 0xFF;
			uint32_t b2 = (h2 >> 8) & 0xFF;
			uint32_t b = (b1 * (255 - f) + b2 * f) / 255;
			work[i] = scale(c0, 100 + (b * 155) / 255);
		}
	} break;

	case FX_HEARTBEAT: {
		// Double pulse: strong thump, short gap, weaker thump, rest
		uint32_t cyc = (ph / 2) & 511;
		uint32_t b = 0;
		if (cyc < 96) {
			b = 255 - (cyc * 255) / 96;
		} else if (cyc >= 160 && cyc < 240) {
			uint32_t d = cyc - 160;
			b = 180 - (d * 180) / 80;
		}
		if (b < 16) b = 16; // faint glow between beats
		uint32_t c = s->color_cur ? s->color_cur : seg_palette_at(s,(uint8_t)(ph / 128));
		c = scale(c, b);
		for (int i = 0; i < n; i++) work[i] = c;
	} break;

	case FX_TURN: {
		// Turn signal. seg.fx_val selects side + style (see the TURN_* enum);
		// the strip is split at the midpoint. Colour is the segment colour, or
		// amber when none is set. Blank whenever off or the mode is invalid.
		for (int i = 0; i < n; i++) work[i] = 0;
		int mode = s->fx_val;
		if (mode < TURN_LEFT_SOLID || mode > TURN_HAZARD_SWEEP) {
			break;
		}
		int m = mode - 1;
		int side = m / 3;    // 0 left, 1 right, 2 both (hazard)
		int style = m % 3;   // 0 solid, 1 blink, 2 sweep
		bool do_left  = (side == 0 || side == 2);
		bool do_right = (side == 1 || side == 2);
		uint32_t c = s->color_cur ? s->color_cur : 0xFF6400; // amber default
		int half = n / 2;

		if (style == 0) {          // solid
			if (do_left)  for (int i = 0; i < half; i++) work[i] = c;
			if (do_right) for (int i = half; i < n; i++) work[i] = c;
		} else if (style == 1) {   // blink
			if ((ph / 256) & 1) {
				if (do_left)  for (int i = 0; i < half; i++) work[i] = c;
				if (do_right) for (int i = half; i < n; i++) work[i] = c;
			}
		} else {                   // sweep, centre -> edge, with a blank gap
			if (do_left && half > 0) {
				int period = half + (half / 2 > 3 ? half / 2 : 3);
				int prog = (int)((ph / 32) % (uint32_t)period);
				int lit = prog < half ? prog + 1 : 0;
				for (int j = 0; j < lit; j++) work[(half - 1) - j] = c; // centre outward
			}
			int hr = n - half;
			if (do_right && hr > 0) {
				int period = hr + (hr / 2 > 3 ? hr / 2 : 3);
				int prog = (int)((ph / 32) % (uint32_t)period);
				int lit = prog < hr ? prog + 1 : 0;
				for (int j = 0; j < lit; j++) work[half + j] = c; // centre outward
			}
		}
	} break;

	case FX_CUSTOM: {
		// Consumer-driven pixels; brightness / overlay still apply
		// downstream in render_seg.
		if (s->manual) {
			for (int i = 0; i < n; i++) work[i] = s->manual[i];
		} else {
			for (int i = 0; i < n; i++) work[i] = 0;
		}
	} break;

	case FX_OFF:
		for (int i = 0; i < n; i++) work[i] = 0;
		break;

	case FX_SOLID:
	default: {
		uint32_t c = s->color_cur ? s->color_cur
			: seg_palette_at(s,(uint8_t)(ph / 128));
		for (int i = 0; i < n; i++) work[i] = c;
	} break;
	}
}

// ---- Render thread ------------------------------------------------------

// Move cur toward target proportionally: close fade/32 of the remaining gap
// per esp_led_PHASE_REF_MS of real time (at least 1 per frame), so large
// changes track quickly while the tail of the fade stays smooth. Scaled by
// the elapsed time like the effect phase, so a fade takes the same wall-clock
// time at any frame rate. 0 = jump immediately.
//
// The 1-step floor is what guarantees progress, and it is per frame: at very
// high frame rates the last few counts of a gap close faster than the rate
// asks. That only ever shortens the tail of a fade, never stalls it.
static uint8_t ease_u8(uint8_t cur, uint8_t target, uint8_t fade,
	uint32_t elapsed) {
	if (fade == 0) {
		return target;
	}
	int d = (int)target - (int)cur;
	if (d == 0) {
		return cur;
	}
	int mag = d > 0 ? d : -d;
	int step = (int)(((uint32_t)mag * fade * elapsed)
		/ (32u * esp_led_PHASE_REF_MS));
	if (step < 1) step = 1;
	if (step > mag) step = mag;
	return d > 0 ? cur + step : cur - step;
}

// Per-channel colour ease, reusing the brightness curve so the two settle at the
// same rate. Colour 0 means "take it from the palette" for every effect, so a
// fade is only meaningful between two real colours: with either end at 0, or with
// no rate set, the target lands immediately. That also avoids fading up from
// black when a segment switches from a palette effect to a solid one.
static uint32_t ease_color(uint32_t cur, uint32_t target, uint8_t fade,
	uint32_t elapsed) {
	if (fade == 0 || cur == 0 || target == 0) {
		return target;
	}
	if (cur == target) {
		return cur;
	}
	uint32_t out = 0;
	for (int sh = 0; sh < 32; sh += 8) {
		uint8_t c = (uint8_t)((cur >> sh) & 0xFF);
		uint8_t t = (uint8_t)((target >> sh) & 0xFF);
		out |= (uint32_t)ease_u8(c, t, fade, elapsed) << sh;
	}
	return out;
}

// Render one segment into its place in the pin group's chain buffer.
// Brightness is sampled once per frame under the ease lock instead of being
// re-read here.
static void render_seg(esp_led_t *st, const seg_t *s, uint8_t master_cur) {
	group_t *grp = &st->group[s->group];
	int n = s->len;
	uint32_t *work = st->work;
	int colors = grp->colors;
	uint8_t *tx = grp->txbuf[grp->cur] + (uint32_t)s->offset * colors;

	fx_render(s, work);

	// Combined per-segment and master brightness
	uint32_t bri = ((uint32_t)s->bri_cur * master_cur) / 255;

	for (int i = 0; i < n; i++) {
		uint32_t c = scale(work[i], bri);

		uint32_t w = (c >> 24) & 0xFF;
		uint32_t r = (c >> 16) & 0xFF;
		uint32_t g = (c >> 8) & 0xFF;
		uint32_t b = c & 0xFF;

		// Derive white from the common RGB part on RGBW strips
		if (s->auto_white && colors == 4 && w == 0) {
			w = r < g ? (r < b ? r : b) : (g < b ? g : b);
			r -= w; g -= w; b -= w;
		}

		work[i] = pack(r, g, b, w);
	}

	// Pack the wire bytes. Overlay pixels take their footprint positions,
	// effect pixels fill the remaining slots in order (reverse applies to
	// the effect pixels only - overlay positions are fixed hardware).
	int total = n + s->ov_count;
	int src = 0;
	for (int i = 0; i < total; i++) {
		bool is_ov = false;
		for (int k = 0; k < s->ov_count; k++) {
			if (s->ov_idx[k] == i) {
				is_ov = true;
				break;
			}
		}

		uint32_t c;
		if (is_ov) {
			c = scale(s->ov_color, s->ov_bri);
		} else if (src < n) {
			c = work[s->reverse ? n - 1 - src : src];
			src++;
		} else {
			c = 0;
		}

		uint32_t w = (c >> 24) & 0xFF;
		uint32_t r = (c >> 16) & 0xFF;
		uint32_t g = (c >> 8) & 0xFF;
		uint32_t b = c & 0xFF;

		uint8_t *px = tx + i * colors;
		switch (s->type) {
		case TYPE_RGB:  px[0] = r; px[1] = g; px[2] = b; break;
		case TYPE_GRBW: px[0] = g; px[1] = r; px[2] = b; px[3] = w; break;
		case TYPE_RGBW: px[0] = r; px[1] = g; px[2] = b; px[3] = w; break;
		case TYPE_WRGB: px[0] = w; px[1] = r; px[2] = g; px[3] = b; break;
		case TYPE_GRB:
		default:        px[0] = g; px[1] = r; px[2] = b; break;
		}
	}
}

static void render_thd(void *arg) {
	esp_led_t *st = (esp_led_t*)arg;
	systime_t prev = VESC_IF->system_time_ticks();

	while (!VESC_IF->should_terminate()) {
		systime_t start = VESC_IF->system_time_ticks();
		uint32_t elapsed = (uint32_t)(start - prev);
		prev = start;
		if (elapsed > esp_led_CATCHUP_MS_MAX) {
			elapsed = esp_led_CATCHUP_MS_MAX;
		}

		// Ease brightness toward the targets, once per frame.
		VESC_IF->mutex_lock(st->lock);
		st->master_cur = ease_u8(st->master_cur, st->master_bri, st->fade,
			elapsed);
		for (int i = 0; i < st->seg_count; i++) {
			seg_t *s = &st->seg[i];
			s->bri_cur = ease_u8(s->bri_cur, s->bri, st->fade, elapsed);
			s->color_cur = ease_color(s->color_cur, s->color,
				s->color_fade, elapsed);
		}
		uint8_t master_cur = st->master_cur;
		VESC_IF->mutex_unlock(st->lock);

		for (int gi = 0; gi < st->group_count; gi++) {
			group_t *g = &st->group[gi];

			// One lock hold per segment instead of one across the whole pass.
			bool any = false;
			for (int i = 0; i < st->seg_count; i++) {
				VESC_IF->mutex_lock(st->lock);
				seg_t *s = &st->seg[i];
				if (s->defined && s->group == gi && s->len > 0
					&& s->len <= st->buf_len) {
					if (s->on) {
						render_seg(st, s, master_cur);
					} else {
						memset(g->txbuf[g->cur] + (uint32_t)s->offset * g->colors,
							0, (uint32_t)(s->len + s->ov_count) * g->colors);
					}
					// Accumulate speed so speed changes take effect in place,
					// without moving the animation position.
					uint32_t spd = s->spd ? s->spd : esp_led_SPD_DEF;
					uint32_t inc = spd * elapsed + s->phase_rem;
					s->phase += inc / esp_led_PHASE_REF_MS;
					s->phase_rem = (uint8_t)(inc % esp_led_PHASE_REF_MS);
					any = true;
				}
				VESC_IF->mutex_unlock(st->lock);
			}
			int pin = g->pin;
			uint8_t *tx = g->txbuf[g->cur];
			int tx_bytes = g->chain_len * g->colors;

			// Only transmit frames that differ from what the strip already
			// shows (the other buffer holds the last transmitted frame),
			// plus a periodic keepalive. The buffer only flips after a real
			// transmission so the comparison stays against the wire state.
			bool send = false;
			if (any) {
				if (g->quiet_ms >= esp_led_REFRESH_MS
					|| memcmp(g->txbuf[0], g->txbuf[1], (size_t)tx_bytes) != 0) {
					send = true;
					g->quiet_ms = 0;
					g->cur ^= 1;
				} else {
					g->quiet_ms += elapsed;
				}
			}

			// Hardware IO outside the lock - the firmware driver can block
			// while a previous transmission finishes. The firmware pools RMT
			// channels per pin, so this just hands off the frame for this
			// group's pin (strips were registered with rgbled_init at start).
			if (send) {
				VESC_IF->rgbled_update(pin, tx, tx_bytes);
			}
		}

		// Sleep until the next frame, but at least 1 ms to avoid a busy loop
		uint32_t frame_ms = st->frame_ms;
		uint32_t work = (uint32_t)(VESC_IF->system_time_ticks() - start);
		VESC_IF->sleep_ms(work < frame_ms ? frame_ms - work : 1);
	}
}

// ---- Extension helpers --------------------------------------------------

static bool check_num_args(lbm_value *args, lbm_uint argn, lbm_uint n) {
	if (argn != n) {
		return false;
	}
	for (lbm_uint i = 0; i < argn; i++) {
		if (!VESC_IF->lbm_is_number(args[i])) {
			return false;
		}
	}
	return true;
}

static seg_t *seg_arg(esp_led_t *st, lbm_value v) {
	int i = VESC_IF->lbm_dec_as_i32(v);
	if (i < 0 || i >= esp_led_SEG_MAX) {
		return NULL;
	}
	return &st->seg[i];
}

// ---- Extensions ---------------------------------------------------------

// (ext-esp_led-seg-def i pin type len [offset] [timing]) - define segment i
// before ext-esp_led-init. type: 0 GRB, 1 RGB, 2 GRBW, 3 RGBW. Segments on
// the same pin form one chain; offset is the segment's pixel position in
// it. timing selects the wire timing preset: 0 generic (default), 1
// WS2812B, 2 WS2815, 3 SK6812, 4 SK6815.
static lbm_value ext_seg_def(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (argn < 4 || argn > 6) return VESC_IF->lbm_enc_sym_terror;
	for (lbm_uint i = 0; i < argn; i++) {
		if (!VESC_IF->lbm_is_number(args[i])) return VESC_IF->lbm_enc_sym_terror;
	}

	seg_t *s = seg_arg(st, args[0]);
	int pin = VESC_IF->lbm_dec_as_i32(args[1]);
	int type = VESC_IF->lbm_dec_as_i32(args[2]);
	int len = VESC_IF->lbm_dec_as_i32(args[3]);
	int offset = argn >= 5 ? VESC_IF->lbm_dec_as_i32(args[4]) : 0;
	int timing = argn >= 6 ? VESC_IF->lbm_dec_as_i32(args[5]) : 0;

	if (!s || pin < 0 || pin > 255 || type < 0 || type > TYPE_WRGB
		|| len < 1 || len > 1024 || offset < 0 || offset > 1024
		|| timing < 0 || timing > 4) {
		return VESC_IF->lbm_enc_sym_terror;
	}

	if (st->running) {
		VESC_IF->lbm_set_error_reason(
			"Stop with ext-esp_led-deinit before redefining segments");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	VESC_IF->mutex_lock(st->lock);
	s->defined = true;
	s->on = true;
	s->pin = (uint8_t)pin;
	s->type = (uint8_t)type;
	s->timing = (uint8_t)timing;
	s->len = (uint16_t)len;
	s->offset = (uint16_t)offset;
	s->reverse = false;
	s->auto_white = false;
	s->fx = FX_SOLID;
	s->pal = 1; // Spectrum (0 is the custom palette, empty by default)
	s->bri = 0;
	s->bri_cur = 0;
	s->spd = esp_led_SPD_DEF;
	s->size = 8;
	s->fx_val = 255;
	s->color = 0;
	s->color_cur = 0;
	s->color_fade = 0;
	s->phase = 0;
	s->phase_rem = 0;
	s->ov_count = 0;
	s->ov_color = 0;
	s->ov_bri = 0;
	s->cpal[0] = 0; s->cpal[1] = 0; s->cpal[2] = 0; s->cpal[3] = 0;
	if (s->manual) { // redefining drops any custom-mode buffer
		VESC_IF->free(s->manual);
		s->manual = NULL;
	}
	VESC_IF->mutex_unlock(st->lock);

	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-seg-overlay-def i idx0 idx1 ...) - define up to 8 overlay
// pixel positions for segment i, before ext-esp_led-init. Positions are
// segment-relative and extend the segment's footprint by one pixel each
// (effect pixels flow around them). No indices clears the overlay.
static lbm_value ext_seg_overlay_def(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (argn < 1 || argn > 1 + esp_led_OV_MAX) return VESC_IF->lbm_enc_sym_terror;
	for (lbm_uint i = 0; i < argn; i++) {
		if (!VESC_IF->lbm_is_number(args[i])) return VESC_IF->lbm_enc_sym_terror;
	}

	seg_t *s = seg_arg(st, args[0]);
	if (!s || !s->defined) return VESC_IF->lbm_enc_sym_terror;

	if (st->running) {
		VESC_IF->lbm_set_error_reason(
			"Stop with ext-esp_led-deinit before redefining segments");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	int count = argn - 1;
	for (int k = 0; k < count; k++) {
		int v = VESC_IF->lbm_dec_as_i32(args[k + 1]);
		if (v < 0 || v >= s->len + count) {
			VESC_IF->lbm_set_error_reason("Overlay index outside the strip");
			return VESC_IF->lbm_enc_sym_terror;
		}
	}

	VESC_IF->mutex_lock(st->lock);
	s->ov_count = (uint8_t)count;
	for (int k = 0; k < count; k++) {
		s->ov_idx[k] = (uint8_t)VESC_IF->lbm_dec_as_i32(args[k + 1]);
	}
	VESC_IF->mutex_unlock(st->lock);

	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-seg-overlay i color bri) - set the overlay color and
// brightness at runtime (bri 0 turns the overlay pixels off).
static lbm_value ext_seg_overlay(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 3)) return VESC_IF->lbm_enc_sym_terror;

	seg_t *s = seg_arg(st, args[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	s->ov_color = VESC_IF->lbm_dec_as_u32(args[1]);
	s->ov_bri = (uint8_t)VESC_IF->lbm_dec_as_i32(args[2]);
	VESC_IF->mutex_unlock(st->lock);

	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-init n) - start rendering the first n segments.
static lbm_value ext_init(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;

	int n = VESC_IF->lbm_dec_as_i32(args[0]);
	if (n < 1 || n > esp_led_SEG_MAX) return VESC_IF->lbm_enc_sym_terror;

	if (st->running) {
		VESC_IF->lbm_set_error_reason("Already running");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	uint16_t max_len = 0;
	for (int i = 0; i < n; i++) {
		if (!st->seg[i].defined) {
			VESC_IF->lbm_set_error_reason("Segment not defined");
			return VESC_IF->lbm_enc_sym_eerror;
		}
		if (st->seg[i].len > max_len) max_len = st->seg[i].len;
	}

	// Build pin groups: segments on the same pin share one chain buffer.
	// All segments of a chain must have the same bytes-per-pixel.
	st->group_count = 0;
	for (int i = 0; i < n; i++) {
		seg_t *s = &st->seg[i];
		int colors = s->type >= TYPE_GRBW ? 4 : 3;
		uint16_t end = s->offset + s->len + s->ov_count;

		s->group = -1;
		for (int gi = 0; gi < st->group_count; gi++) {
			if (st->group[gi].pin == s->pin) {
				s->group = gi;
				break;
			}
		}

		if (s->group < 0) {
			s->group = st->group_count++;
			st->group[s->group].pin = s->pin;
			st->group[s->group].colors = (uint8_t)colors;
			st->group[s->group].timing = s->timing;
			st->group[s->group].chain_len = end;
			st->group[s->group].txbuf[0] = NULL;
			st->group[s->group].txbuf[1] = NULL;
			st->group[s->group].cur = 0;
			// Force the first frame out even if it renders all-black
			// (both buffers start zeroed and would compare equal)
			st->group[s->group].quiet_ms = esp_led_REFRESH_MS;
		} else {
			if (st->group[s->group].colors != colors) {
				VESC_IF->lbm_set_error_reason(
					"Segments on one pin must have the same color depth");
				return VESC_IF->lbm_enc_sym_eerror;
			}
			if (st->group[s->group].timing != s->timing) {
				VESC_IF->lbm_set_error_reason(
					"Segments on one pin must have the same timing preset");
				return VESC_IF->lbm_enc_sym_eerror;
			}
			if (end > st->group[s->group].chain_len) {
				st->group[s->group].chain_len = end;
			}
		}
	}

	// Segments sharing a pin must not overlap on the chain - overlapping
	// footprints would silently overwrite each other every frame.
	for (int i = 0; i < n; i++) {
		for (int j = i + 1; j < n; j++) {
			seg_t *a = &st->seg[i];
			seg_t *b = &st->seg[j];
			if (a->pin != b->pin) {
				continue;
			}
			uint32_t a_end = (uint32_t)a->offset + a->len + a->ov_count;
			uint32_t b_end = (uint32_t)b->offset + b->len + b->ov_count;
			if (a->offset < b_end && b->offset < a_end) {
				VESC_IF->lbm_set_error_reason(
					"Segments on one pin overlap - check the offsets");
				return VESC_IF->lbm_enc_sym_eerror;
			}
		}
	}

	// The firmware drives strips by pin and pools RMT channels behind that,
	// so any number of pin groups works (channels are shared when there are
	// more pins than the chip has). Just require the LED API to be present.
	if (VESC_IF->rgbled_init == NULL || VESC_IF->rgbled_update == NULL
		|| VESC_IF->rgbled_deinit == NULL) {
		VESC_IF->lbm_set_error_reason("This firmware has no LED strip support");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	bool alloc_ok = true;
	st->work = VESC_IF->malloc(max_len * sizeof(uint32_t));
	alloc_ok = st->work != NULL;
	for (int gi = 0; gi < st->group_count && alloc_ok; gi++) {
		group_t *g = &st->group[gi];
		uint32_t bytes = (uint32_t)g->chain_len * g->colors;
		for (int b = 0; b < 2 && alloc_ok; b++) {
			g->txbuf[b] = VESC_IF->malloc(bytes);
			if (g->txbuf[b]) {
				memset(g->txbuf[b], 0, bytes);
			} else {
				alloc_ok = false;
			}
		}
	}

	int registered = 0;
	bool led_ok = true;

	if (alloc_ok) {
		st->buf_len = max_len;
		st->seg_count = n;
		// Register each pin group as a strip so the firmware can bind the LED driver to that pin
		for (int gi = 0; gi < st->group_count; gi++) {
			if (!VESC_IF->rgbled_init(st->group[gi].pin,
					st->group[gi].timing)) {
				VESC_IF->printf("esp_led: strip init failed on pin %d",
					st->group[gi].pin);
				led_ok = false;
				break;
			}
			registered++;
		}
		if (led_ok) {
			st->thread = VESC_IF->spawn(render_thd, 3072, "esp_led_render", st);
			alloc_ok = st->thread != NULL;
		}
	}

	if (!alloc_ok || !led_ok) {
		for (int gi = 0; gi < registered; gi++) {
			VESC_IF->rgbled_deinit(st->group[gi].pin);
		}
		if (st->work) { VESC_IF->free(st->work); st->work = NULL; }
		for (int gi = 0; gi < st->group_count; gi++) {
			for (int b = 0; b < 2; b++) {
				if (st->group[gi].txbuf[b]) {
					VESC_IF->free(st->group[gi].txbuf[b]);
					st->group[gi].txbuf[b] = NULL;
				}
			}
		}
		st->group_count = 0;
		st->seg_count = 0;
		st->buf_len = 0;
		if (!led_ok) {
			VESC_IF->lbm_set_error_reason(
				"Could not start a strip - check the pin numbers");
			return VESC_IF->lbm_enc_sym_eerror;
		}
		return VESC_IF->lbm_enc_sym_merror;
	}

	st->running = true;

	return VESC_IF->lbm_enc_sym_true;
}

static void esp_led_stop(esp_led_t *st) {
	if (!st->running) {
		return;
	}
	VESC_IF->request_terminate(st->thread);
	st->running = false;

	for (int gi = 0; gi < st->group_count; gi++) {
		group_t *g = &st->group[gi];
		uint32_t bytes = (uint32_t)g->chain_len * g->colors;
		if (g->txbuf[g->cur]) {
			memset(g->txbuf[g->cur], 0, bytes);
			VESC_IF->rgbled_update(g->pin, g->txbuf[g->cur], bytes);
		}
	}

	for (int gi = 0; gi < st->group_count; gi++) {
		VESC_IF->rgbled_deinit(st->group[gi].pin);
	}

	VESC_IF->free(st->work); st->work = NULL;
	for (int gi = 0; gi < st->group_count; gi++) {
		for (int b = 0; b < 2; b++) {
			if (st->group[gi].txbuf[b]) {
				VESC_IF->free(st->group[gi].txbuf[b]);
				st->group[gi].txbuf[b] = NULL;
			}
		}
	}
	// Free any manual-mode pixel buffers.
	for (int i = 0; i < esp_led_SEG_MAX; i++) {
		if (st->seg[i].manual) {
			VESC_IF->free(st->seg[i].manual);
			st->seg[i].manual = NULL;
		}
	}
	st->group_count = 0;
	st->buf_len = 0;
	st->seg_count = 0;
}

// (ext-esp_led-deinit)
static lbm_value ext_deinit(lbm_value *args, lbm_uint argn) {
	(void)args; (void)argn;
	esp_led_stop(state());
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-seg-look i fx pal color spd bri) - full appearance in one call.
static lbm_value ext_seg_look(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 6)) return VESC_IF->lbm_enc_sym_terror;

	seg_t *s = seg_arg(st, args[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	uint8_t fx = (uint8_t)VESC_IF->lbm_dec_as_i32(args[1]);
	if (s->fx != fx) {
		s->fx = fx;
		s->phase = 0; // restart only when the effect actually changes,
		s->phase_rem = 0;
		              // so repeated seg-look calls don't stall animations
	}
	s->pal = (uint8_t)VESC_IF->lbm_dec_as_i32(args[2]);
	s->color = VESC_IF->lbm_dec_as_u32(args[3]);
	s->spd = (uint8_t)VESC_IF->lbm_dec_as_i32(args[4]);
	s->bri = (uint8_t)VESC_IF->lbm_dec_as_i32(args[5]);
	VESC_IF->mutex_unlock(st->lock);

	return VESC_IF->lbm_enc_sym_true;
}

// Setters shared by the per-segment and all-segment variants. Field ids
// keep one implementation for all the small setters.
enum { SET_FX = 0, SET_PAL, SET_BRI, SET_SPD, SET_COLOR, SET_ON, SET_REVERSE, SET_SIZE, SET_FX_VAL,
	SET_AUTO_WHITE, SET_COLOR_FADE };

static void seg_set(seg_t *s, int field, uint32_t v) {
	switch (field) {
	case SET_FX:      if (s->fx != (uint8_t)v) { s->fx = (uint8_t)v; s->phase = 0;
	                      s->phase_rem = 0; } break;
	case SET_PAL:     s->pal = (uint8_t)v; break;
	case SET_BRI:     s->bri = (uint8_t)v; break;
	case SET_SPD:     s->spd = (uint8_t)v; break;
	case SET_COLOR:   s->color = v; break;
	case SET_ON:      s->on = v != 0; break;
	case SET_REVERSE: s->reverse = v != 0; break;
	case SET_SIZE:    s->size = (uint8_t)v; break;
	case SET_FX_VAL:  s->fx_val = (uint8_t)v; break;
	case SET_AUTO_WHITE: s->auto_white = v != 0; break;
	case SET_COLOR_FADE: s->color_fade = (uint8_t)(v > 32 ? 32 : v); break;
	}
}

static lbm_value set_one(lbm_value *args, lbm_uint argn, int field) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 2)) return VESC_IF->lbm_enc_sym_terror;

	seg_t *s = seg_arg(st, args[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	seg_set(s, field, VESC_IF->lbm_dec_as_u32(args[1]));
	VESC_IF->mutex_unlock(st->lock);
	return VESC_IF->lbm_enc_sym_true;
}

static lbm_value set_all(lbm_value *args, lbm_uint argn, int field) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	for (int i = 0; i < esp_led_SEG_MAX; i++) {
		seg_set(&st->seg[i], field, VESC_IF->lbm_dec_as_u32(args[0]));
	}
	VESC_IF->mutex_unlock(st->lock);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-seg-fx i fx) / (ext-esp_led-fx fx)
static lbm_value ext_seg_fx(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_FX); }
static lbm_value ext_fx(lbm_value *a, lbm_uint n) { return set_all(a, n, SET_FX); }

// (ext-esp_led-seg-pal i pal) / (ext-esp_led-pal pal)
static lbm_value ext_seg_pal(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_PAL); }
static lbm_value ext_pal(lbm_value *a, lbm_uint n) { return set_all(a, n, SET_PAL); }

// (ext-esp_led-seg-bri i bri)
static lbm_value ext_seg_bri(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_BRI); }

// (ext-esp_led-seg-spd i spd)
static lbm_value ext_seg_spd(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_SPD); }

// (ext-esp_led-seg-size i size) - chase head / comet tail length
static lbm_value ext_seg_size(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_SIZE); }

// (ext-esp_led-seg-fx-val i v) - the selected effect's parameter: the gauge
// fill 0..255, the turn-signal mode. Named for the slot rather than any one
// meaning, because a magnitude and a mode selector share it.
static lbm_value ext_seg_fx_val(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_FX_VAL); }

// (ext-esp_led-seg-col i color) / (ext-esp_led-col color) - packed 0xWWRRGGBB
static lbm_value ext_seg_col(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_COLOR); }
static lbm_value ext_col(lbm_value *a, lbm_uint n) { return set_all(a, n, SET_COLOR); }

// (ext-esp_led-seg-on i on)
static lbm_value ext_seg_on(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_ON); }

// (ext-esp_led-seg-color-fade i rate) - how fast this segment's colour follows
// a change, in 32nds of the remaining gap per 33 ms. 0 (the default) is instant.
// Per segment rather than global because some colours are information, not
// decoration: an alarm that fades in reads as a slow one.
static lbm_value ext_seg_color_fade(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_COLOR_FADE); }

// (ext-esp_led-seg-reverse i rev)
static lbm_value ext_seg_reverse(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_REVERSE); }

// (ext-esp_led-sync) - restart every segment's animation from phase 0, so
// effects set up at different times run in step. Every segment advances its
// phase once per render pass, so segments zeroed together stay locked as long
// as their speeds match; different speeds drift apart again from here.
// Segments are zeroed under one lock hold, i.e. within the same frame.
static lbm_value ext_sync(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 0)) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	for (int i = 0; i < esp_led_SEG_MAX; i++) {
		st->seg[i].phase = 0;
		st->seg[i].phase_rem = 0;
	}
	VESC_IF->mutex_unlock(st->lock);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-seg-sync i) - restart segment i's animation from phase 0,
// leaving the other segments running.
static lbm_value ext_seg_sync(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;

	seg_t *s = seg_arg(st, args[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	s->phase = 0;
	s->phase_rem = 0;
	VESC_IF->mutex_unlock(st->lock);
	return VESC_IF->lbm_enc_sym_true;
}

// Ensure segment s is in custom mode: allocate its pixel buffer (once) and
// switch it to the custom effect. Must be called with the lock held.
static bool seg_custom_ready(seg_t *s) {
	if (!s->manual) {
		s->manual = VESC_IF->malloc((uint32_t)s->len * sizeof(uint32_t));
		if (!s->manual) {
			return false;
		}
		for (int i = 0; i < s->len; i++) {
			s->manual[i] = 0;
		}
	}
	s->fx = FX_CUSTOM;
	return true;
}

// (ext-esp_led-seg-custom i) - put segment i in custom mode (blank buffer).
// Consumers then push pixels with ext-esp_led-seg-pixel / -pixels and run
// their own effect; brightness and channel pooling still apply.
static lbm_value ext_seg_custom(lbm_value *a, lbm_uint n) {
	esp_led_t *st = state();
	if (!check_num_args(a, n, 1)) return VESC_IF->lbm_enc_sym_terror;
	seg_t *s = seg_arg(st, a[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	bool ok = seg_custom_ready(s);
	VESC_IF->mutex_unlock(st->lock);
	return ok ? VESC_IF->lbm_enc_sym_true : VESC_IF->lbm_enc_sym_merror;
}

// (ext-esp_led-seg-pixel i idx color) - set one manual pixel (packed 0xWWRRGGBB).
// Enters manual mode if not already. Out-of-range idx is ignored.
static lbm_value ext_seg_pixel(lbm_value *a, lbm_uint n) {
	esp_led_t *st = state();
	if (!check_num_args(a, n, 3)) return VESC_IF->lbm_enc_sym_terror;
	seg_t *s = seg_arg(st, a[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;
	int idx = VESC_IF->lbm_dec_as_i32(a[1]);
	uint32_t color = VESC_IF->lbm_dec_as_u32(a[2]);

	VESC_IF->mutex_lock(st->lock);
	bool ok = seg_custom_ready(s);
	if (ok && idx >= 0 && idx < s->len) {
		s->manual[idx] = color;
	}
	VESC_IF->mutex_unlock(st->lock);
	return ok ? VESC_IF->lbm_enc_sym_true : VESC_IF->lbm_enc_sym_merror;
}

// (ext-esp_led-seg-pixels i start colors) - set consecutive manual pixels from
// `start`, where colors is a list of packed 0xWWRRGGBB values. Enters manual
// mode if not already; pixels past the end of the segment are ignored.
static lbm_value ext_seg_pixels(lbm_value *a, lbm_uint n) {
	esp_led_t *st = state();
	if (n != 3 || !VESC_IF->lbm_is_number(a[0]) || !VESC_IF->lbm_is_number(a[1])) {
		return VESC_IF->lbm_enc_sym_terror;
	}
	seg_t *s = seg_arg(st, a[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;
	int idx = VESC_IF->lbm_dec_as_i32(a[1]);

	VESC_IF->mutex_lock(st->lock);
	bool ok = seg_custom_ready(s);
	if (ok) {
		lbm_value lst = a[2];
		while (VESC_IF->lbm_is_cons(lst) && idx < s->len) {
			if (idx >= 0) {
				s->manual[idx] = VESC_IF->lbm_dec_as_u32(VESC_IF->lbm_car(lst));
			}
			idx++;
			lst = VESC_IF->lbm_cdr(lst);
		}
	}
	VESC_IF->mutex_unlock(st->lock);
	return ok ? VESC_IF->lbm_enc_sym_true : VESC_IF->lbm_enc_sym_merror;
}

// (ext-esp_led-seg-palette i c0 c1 c2 c3) - set segment i's custom palette
// (4 anchor colours, packed 0xWWRRGGBB) and select it (pal 0), so the built-in
// gradient effects (rainbow, chase, gauge, ...) render in these colours.
static lbm_value ext_seg_palette(lbm_value *a, lbm_uint n) {
	esp_led_t *st = state();
	if (!check_num_args(a, n, 5)) return VESC_IF->lbm_enc_sym_terror;
	seg_t *s = seg_arg(st, a[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	s->cpal[0] = VESC_IF->lbm_dec_as_u32(a[1]);
	s->cpal[1] = VESC_IF->lbm_dec_as_u32(a[2]);
	s->cpal[2] = VESC_IF->lbm_dec_as_u32(a[3]);
	s->cpal[3] = VESC_IF->lbm_dec_as_u32(a[4]);
	s->pal = 0; // select the custom palette
	VESC_IF->mutex_unlock(st->lock);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-col-rgb r g b) / (ext-esp_led-col-rgbw r g b w) - solid color on
static lbm_value ext_col_rgbw(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (argn != 3 && argn != 4) return VESC_IF->lbm_enc_sym_terror;
	for (lbm_uint i = 0; i < argn; i++) {
		if (!VESC_IF->lbm_is_number(args[i])) return VESC_IF->lbm_enc_sym_terror;
	}

	uint32_t r = VESC_IF->lbm_dec_as_u32(args[0]) & 0xFF;
	uint32_t g = VESC_IF->lbm_dec_as_u32(args[1]) & 0xFF;
	uint32_t b = VESC_IF->lbm_dec_as_u32(args[2]) & 0xFF;
	uint32_t w = argn == 4 ? VESC_IF->lbm_dec_as_u32(args[3]) & 0xFF : 0;
	uint32_t c = pack(r, g, b, w);

	VESC_IF->mutex_lock(st->lock);
	for (int i = 0; i < esp_led_SEG_MAX; i++) {
		st->seg[i].color = c;
		st->seg[i].fx = FX_SOLID;
	}
	VESC_IF->mutex_unlock(st->lock);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-bri b) - master brightness 0..255
static lbm_value ext_bri(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;
	st->master_bri = (uint8_t)VESC_IF->lbm_dec_as_i32(args[0]);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-fps n) - target frame rate. The render loop holds this cadence
// by sleeping the frame time minus the work it just did. Animation and fade
// speeds are unaffected: both advance by measured real time, so this trades
// smoothness against CPU without retuning anything. Out-of-range values clamp
// to the frame-time limits, i.e. an effective 5..200 fps.
static lbm_value ext_fps(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;

	int fps = VESC_IF->lbm_dec_as_i32(args[0]);
	if (fps < 1) return VESC_IF->lbm_enc_sym_terror;

	uint32_t ms = 1000u / (uint32_t)fps;
	if (ms < esp_led_FRAME_MS_MIN) ms = esp_led_FRAME_MS_MIN;
	if (ms > esp_led_FRAME_MS_MAX) ms = esp_led_FRAME_MS_MAX;
	st->frame_ms = (uint16_t)ms;

	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-fade rate) - brightness easing: fraction of the remaining gap
// closed per 33 ms of real time, in 32nds (0 = instant, 8 = 25%, 32 = full).
// Applies to master and segment brightness changes.
static lbm_value ext_fade(lbm_value *args, lbm_uint argn) {
	esp_led_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;
	st->fade = (uint8_t)VESC_IF->lbm_dec_as_i32(args[0]);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-esp_led-seg-auto-white i en) - derive W from the common RGB part.
// Per-segment only: it depends on the strip's colour order, so an
// all-segments variant would be meaningless on a mixed set of strips.
static lbm_value ext_seg_auto_white(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_AUTO_WHITE); }

// ---- Lifecycle ----------------------------------------------------------

// The extension list, written once and consumed two different ways.
//
// On the S3 it becomes a table walked at init. That is a code-size
// decision, and a sharp one: the S3 linker script puts .rodata in the data
// region but .literal - where the name and function pointers of each inline
// call land - in the *code* region (c_libs/express/link_esp32s3.ld). As a
// table those 30 pointer pairs move to the data region, which has room to
// spare, leaving just a short loop behind. That is 571 bytes off the code
// region, which is the region this package actually runs out of.
//
// On the RISC-V targets it stays a run of inline calls. They execute in
// place from flash with no relocation pass at load (see the XIP branch of
// ext_load_native_lib in the firmware), so a stored function pointer would
// keep the link-time address it was given and be wrong at runtime - GCC
// puts a table like this in .data.rel.ro precisely because it needs
// relocating. Inline calls materialise each pointer PC-relatively, which is
// position independent, and those targets are not short of code space.
#define esp_led_EXTENSIONS(X) \
	X("ext-esp_led-seg-def", ext_seg_def) \
	X("ext-esp_led-seg-overlay-def", ext_seg_overlay_def) \
	X("ext-esp_led-seg-overlay", ext_seg_overlay) \
	X("ext-esp_led-init", ext_init) \
	X("ext-esp_led-deinit", ext_deinit) \
	X("ext-esp_led-seg-look", ext_seg_look) \
	X("ext-esp_led-seg-fx", ext_seg_fx) \
	X("ext-esp_led-fx", ext_fx) \
	X("ext-esp_led-seg-pal", ext_seg_pal) \
	X("ext-esp_led-pal", ext_pal) \
	X("ext-esp_led-seg-bri", ext_seg_bri) \
	X("ext-esp_led-seg-spd", ext_seg_spd) \
	X("ext-esp_led-seg-size", ext_seg_size) \
	X("ext-esp_led-seg-fx-val", ext_seg_fx_val) \
	X("ext-esp_led-seg-color-fade", ext_seg_color_fade) \
	X("ext-esp_led-seg-col", ext_seg_col) \
	X("ext-esp_led-col", ext_col) \
	X("ext-esp_led-seg-on", ext_seg_on) \
	X("ext-esp_led-seg-reverse", ext_seg_reverse) \
	X("ext-esp_led-sync", ext_sync) \
	X("ext-esp_led-seg-sync", ext_seg_sync) \
	X("ext-esp_led-seg-custom", ext_seg_custom) \
	X("ext-esp_led-seg-pixel", ext_seg_pixel) \
	X("ext-esp_led-seg-pixels", ext_seg_pixels) \
	X("ext-esp_led-seg-palette", ext_seg_palette) \
	X("ext-esp_led-col-rgb", ext_col_rgbw) \
	X("ext-esp_led-col-rgbw", ext_col_rgbw) \
	X("ext-esp_led-bri", ext_bri) \
	X("ext-esp_led-fade", ext_fade) \
	X("ext-esp_led-fps", ext_fps) \
	X("ext-esp_led-seg-auto-white", ext_seg_auto_white)

#ifdef CONFIG_IDF_TARGET_ESP32S3
#define X(name_, fn_) {name_, fn_},
static const struct {
	char *name;
	extension_fptr fn;
} extensions[] = { esp_led_EXTENSIONS(X) };
#undef X
#endif

static void stop(void *arg) {
	esp_led_t *st = (esp_led_t*)arg;

	if (st) {
		esp_led_stop(st);
		VESC_IF->free(st->lock);
		VESC_IF->free(st);
	}

	VESC_IF->printf("esp_led-strip lib stopped");
}

INIT_FUN(lib_info *info) {
	INIT_START

	esp_led_t *st = VESC_IF->malloc(sizeof(esp_led_t));
	if (!st) {
		return false;
	}

	for (unsigned int i = 0; i < sizeof(esp_led_t); i++) {
		((uint8_t*)st)[i] = 0;
	}

	st->master_bri = 255;
	st->master_cur = 255;
	st->fade = esp_led_FADE_DEF;
	st->frame_ms = esp_led_FRAME_MS_DEF;
	st->lock = VESC_IF->mutex_create();
	if (!st->lock) {
		VESC_IF->free(st);
		return false;
	}

	info->arg = st;
	info->stop_fun = stop;

#ifdef CONFIG_IDF_TARGET_ESP32S3
	for (unsigned int i = 0; i < sizeof(extensions) / sizeof(extensions[0]); i++) {
		VESC_IF->lbm_add_extension(extensions[i].name, extensions[i].fn);
	}
#else
#define X(name_, fn_) VESC_IF->lbm_add_extension(name_, fn_);
	esp_led_EXTENSIONS(X)
#undef X
#endif

	VESC_IF->printf("esp_led-strip lib loaded");

	return true;
}
