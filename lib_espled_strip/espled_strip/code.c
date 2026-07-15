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

// ext-espled-*: segmented addressable-LED strip engine as a native library.
//
// Lisp sets high-level segment /
// effect state and a background render thread animates, applies
// brightness / auto-white / an adaptive current limit and pushes pixels.
// The hardware path is the firmware rgbled driver through the C interface,
// addressed by pin: strips are registered with rgbled_init at start and each
// frame's changed groups are pushed with rgbled_update(pin, ...). The
// firmware pools the chip's RMT TX channels behind those calls (2 on the
// ESP32-C3/C6, 4 on the S3), so any number of pin groups works - strips that
// fit the pool stay lit continuously, and beyond that they share channels
// and are refreshed in turn.
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

#define ESPLED_SEG_MAX     8
#define ESPLED_OV_MAX      8   // overlay pixels per segment
#define ESPLED_RENDER_MS   33  // ~30 fps

// Frames without changes before a keepalive retransmit (~2 s): static
// content keeps the data line quiet, but a pixel corrupted by line noise
// still heals shortly.
#define ESPLED_REFRESH_FRAMES 60

// Effects
enum {
	FX_SOLID = 0,
	FX_BREATHE,
	FX_CHASE,
	FX_RAINBOW,
	FX_SPARKLE,
	FX_COMET,
	FX_GAUGE,     // fill by the level param; battery gradient when color = 0
	FX_STROBE,    // hard on/off flash
	FX_LARSON,    // bouncing eye with tail (knight rider)
	FX_FELONY,    // halves alternate red/blue
	FX_THEATER,   // marquee - every third pixel, marching
	FX_WIPE,      // fill end-to-end, then wipe to black
	FX_WAVES,     // overlapping slow waves (pacifica-like)
	FX_CANDLE,    // warm uneven flicker
	FX_HEARTBEAT, // thump-thump double pulse
};

// Color byte layouts on the wire
enum {
	TYPE_GRB = 0,
	TYPE_RGB,
	TYPE_GRBW,
	TYPE_RGBW,
};

// A palette is 4 anchor colors, interpolated across pos 0..255.
typedef struct { uint32_t c[4]; } palette_t;
static const palette_t palettes[] = {
	{{0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF}}, // 0 rgbw-ish
	{{0xFF0000, 0xFF8000, 0xFFFF00, 0xFF0000}}, // 1 fire
	{{0x0000FF, 0x00FFFF, 0x00FF80, 0x0000FF}}, // 2 ocean
	{{0xFF00FF, 0x8000FF, 0x0080FF, 0xFF00FF}}, // 3 neon
	{{0xFFFFFF, 0xFF4000, 0x400000, 0x000000}}, // 4 ember
	{{0x00FF00, 0xFFFF00, 0xFF0000, 0x00FF00}}, // 5 traffic
	{{0xFFFFFF, 0x000000, 0xFFFFFF, 0x000000}}, // 6 strobe
	{{0x1030FF, 0xFFFFFF, 0x1030FF, 0x001040}}, // 7 police-blue
	{{0x0B1D51, 0xFF6A00, 0xFFD700, 0x2A0E4F}}, // 8 sunset
	{{0x000000, 0x8B0000, 0xFF4500, 0xFFFFE0}}, // 9 lava
	{{0x01411F, 0x00FFB2, 0x7A00FF, 0x013220}}, // 10 aurora
	{{0x013220, 0x2E8B57, 0x9ACD32, 0x013220}}, // 11 forest
	{{0x8000FF, 0xFF4000, 0xFF00A0, 0x0040FF}}, // 12 party
	{{0x001F5C, 0x00BFFF, 0xFFFFFF, 0x001F5C}}, // 13 ice
	{{0xFF6A00, 0x1A001A, 0x8000FF, 0x000000}}, // 14 halloween
	{{0xFF0000, 0x00FF00, 0xFFC000, 0x0000FF}}, // 15 christmas (c9)
	{{0xFFB3BA, 0xBAFFC9, 0xBAE1FF, 0xFFFFBA}}, // 16 pastel
	{{0xFF2E6A, 0xFFC0CB, 0xFFF0F5, 0xC71585}}, // 17 sakura
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
	uint8_t fx;
	uint8_t pal;
	uint8_t bri;       // per-segment brightness target 0..255
	uint8_t bri_cur;   // eased current brightness
	uint8_t spd;       // 0..255
	uint8_t size;      // chase head / comet tail length
	uint8_t level;     // gauge fill 0..255
	uint16_t offset;   // pixel offset within the pin's chain
	uint32_t color;    // packed 0xWWRRGGBB
	uint32_t phase;    // frames since effect start

	// Overlay pixels: physical LEDs at fixed positions inside the strip
	// (e.g. embedded highbeams) that show ov_color at ov_bri while the
	// effect pixels flow around them. Positions are relative to the
	// segment and extend its footprint to len + ov_count pixels.
	uint8_t ov_count;
	uint8_t ov_idx[ESPLED_OV_MAX];
	uint32_t ov_color;
	uint8_t ov_bri;

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
	uint16_t quiet;      // frames since the last transmission
} group_t;

typedef struct {
	lib_thread thread;
	lib_mutex lock;
	volatile bool running;

	seg_t seg[ESPLED_SEG_MAX];
	int seg_count;

	group_t group[ESPLED_SEG_MAX];
	int group_count;

	uint8_t master_bri;  // target
	uint8_t master_cur;  // eased current
	uint8_t fade;        // gap fraction closed per frame in 32nds, 0 = instant
	bool auto_white;
	uint32_t ablimit_ma; // 0 = off

	// Current limiting is global: each frame sums the unscaled demand of
	// all segments and the scale derived from it is applied on the next
	// frame (one frame of lag instead of a second render pass).
	uint32_t ma_frame;   // demand accumulated this frame
	uint8_t ma_scale;    // 0..255 output scale, 255 = no limiting

	uint16_t buf_len;    // pixels the work buffer holds
	uint32_t *work;      // packed 0xWWRRGGBB, buf_len entries
} espled_t;

static espled_t *state(void) {
	return (espled_t*)ARG;
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

static uint32_t palette_at(uint8_t pal, uint8_t pos) {
	const palette_t *p = &palettes[pal % PALETTE_COUNT];
	uint32_t a = p->c[pos / 64];
	uint32_t b = p->c[(pos / 64 + 1) % 4];
	uint32_t f = pos % 64; // 0..63 between anchors

	uint32_t r = (((a >> 16) & 0xFF) * (63 - f) + ((b >> 16) & 0xFF) * f) / 63;
	uint32_t g = (((a >> 8) & 0xFF) * (63 - f) + ((b >> 8) & 0xFF) * f) / 63;
	uint32_t bl = ((a & 0xFF) * (63 - f) + (b & 0xFF) * f) / 63;
	return pack(r, g, bl, 0);
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

	// Effects take their color from the color param; a color of 0 means
	// "from the palette" (cycling with the animation phase). Rainbow always
	// renders the palette, solid keeps 0 = black so segments can be
	// blanked, and gauge uses its battery gradient for 0.
	switch (s->fx) {
	case FX_BREATHE: {
		uint32_t b = triangle(ph / 32);
		uint32_t c0 = s->color ? s->color : palette_at(s->pal, (uint8_t)(ph / 128));
		uint32_t c = scale(c0, b);
		for (int i = 0; i < n; i++) work[i] = c;
	} break;

	case FX_CHASE: {
		int head = (int)((ph / 32) % (uint32_t)(n > 0 ? n : 1));
		for (int i = 0; i < n; i++) {
			int d = i - head;
			if (d < 0) d += n;
			uint32_t b = d < size ? 255 - (d * 255) / size : 0;
			uint32_t c = s->color ? s->color
				: palette_at(s->pal, (uint8_t)((i * 255) / (n ? n : 1)));
			work[i] = scale(c, b);
		}
	} break;

	case FX_RAINBOW: {
		for (int i = 0; i < n; i++) {
			uint8_t pos = (uint8_t)((i * 255) / (n ? n : 1) + ph / 32);
			work[i] = palette_at(s->pal, pos);
		}
	} break;

	case FX_SPARKLE: {
		for (int i = 0; i < n; i++) {
			// Deterministic twinkle from phase + index
			uint32_t h = ((uint32_t)i * 2654435761u) ^ ((ph / 32) * 40503u);
			uint32_t c = s->color ? s->color
				: palette_at(s->pal, (uint8_t)(h >> 16));
			work[i] = ((h >> 8) & 0xFF) < ((uint32_t)(s->spd ? s->spd : 32) / 2 + 1) ? c : 0;
		}
	} break;

	case FX_COMET: {
		int head = (int)((ph / 32) % (uint32_t)(n > 0 ? n : 1));
		for (int i = 0; i < n; i++) {
			int d = head - i;
			if (d < 0) d += n;
			uint32_t b = d < size ? 255 - (d * 255) / size : 0;
			uint32_t c = s->color ? s->color : palette_at(s->pal, (uint8_t)(ph / 32));
			work[i] = scale(c, b);
		}
	} break;

	case FX_GAUGE: {
		// Fill the first level/255 of the strip. Fill color: the segment
		// color if set; else the palette as a gradient along the strip,
		// revealed by the fill; else (color 0, palette 0) a battery-style
		// gradient - red when nearly empty, green when full. spd > 0
		// pulses the fill (e.g. while charging).
		int lit = (n * s->level + 254) / 255;
		if (s->level > 0 && lit < 1) lit = 1;
		uint32_t b = s->spd ? 140 + triangle(ph / 32) * 115 / 255
			: 255;
		if (!s->color && s->pal) {
			for (int i = 0; i < n; i++) {
				work[i] = i < lit
					? scale(palette_at(s->pal, (uint8_t)((i * 255) / n)), b)
					: 0;
			}
			break;
		}
		uint32_t c;
		if (s->color) {
			c = s->color;
		} else if (s->level < 51) { // < 20%: red
			c = 0xFF0000;
		} else {
			uint32_t g = ((uint32_t)s->level * 255) / 204; // level/0.8
			if (g > 255) g = 255;
			c = pack(255 - g, g, 0, 0);
		}
		c = scale(c, b);
		for (int i = 0; i < n; i++) work[i] = i < lit ? c : 0;
	} break;

	case FX_STROBE: {
		uint32_t flash = ph / 64;
		uint32_t c = s->color ? s->color
			: palette_at(s->pal, (uint8_t)(flash * 61)); // new hue per flash
		bool lit = flash & 1;
		for (int i = 0; i < n; i++) work[i] = lit ? c : 0;
	} break;

	case FX_LARSON: {
		int span = n > 1 ? n - 1 : 1;
		int pos = (int)((ph / 16) % (uint32_t)(2 * span));
		if (pos > span) pos = 2 * span - pos;
		uint32_t c = s->color ? s->color : palette_at(s->pal, (uint8_t)(ph / 128));
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
			uint32_t c = s->color ? s->color
				: palette_at(s->pal, (uint8_t)((i * 255) / n + ph / 64));
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
		uint32_t c = s->color ? s->color
			: palette_at(s->pal, (uint8_t)(((ph / 32) / period) * 47));
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
			uint32_t w1 = triangle(p * 2 + ph / 32);
			uint32_t w2 = triangle(p * 3 + 170 + 1024 - ph / 48);
			uint32_t w3 = triangle(p + 85 + ph / 80);
			uint32_t c0 = s->color ? s->color
				: palette_at(s->pal, (uint8_t)((w1 + w3) / 2));
			work[i] = scale(c0, 64 + (w2 * 191) / 255);
		}
	} break;

	case FX_CANDLE: {
		// Warm uneven flicker: smooth deterministic noise per pixel,
		// interpolated between flicker steps. Color 0 = candle flame
		// (this effect does not cycle the palette).
		uint32_t t = ph / 128;
		uint32_t f = (ph & 127) * 2; // 0..254 between flicker steps
		uint32_t c0 = s->color ? s->color : 0xFF9329;
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
		uint32_t cyc = (ph / 16) & 511;
		uint32_t b = 0;
		if (cyc < 96) {
			b = 255 - (cyc * 255) / 96;
		} else if (cyc >= 160 && cyc < 240) {
			uint32_t d = cyc - 160;
			b = 180 - (d * 180) / 80;
		}
		if (b < 16) b = 16; // faint glow between beats
		uint32_t c = s->color ? s->color : palette_at(s->pal, (uint8_t)(ph / 128));
		c = scale(c, b);
		for (int i = 0; i < n; i++) work[i] = c;
	} break;

	case FX_SOLID:
	default:
		for (int i = 0; i < n; i++) work[i] = s->color;
		break;
	}
}

// ---- Render thread ------------------------------------------------------

// Move cur toward target proportionally: close fade/32 of the remaining
// gap per frame (at least 1), so large changes track quickly while the
// tail of the fade stays smooth. 0 = jump immediately.
static uint8_t ease_u8(uint8_t cur, uint8_t target, uint8_t fade) {
	if (fade == 0) {
		return target;
	}
	int d = (int)target - (int)cur;
	if (d == 0) {
		return cur;
	}
	int mag = d > 0 ? d : -d;
	int step = (mag * fade) / 32;
	if (step < 1) step = 1;
	if (step > mag) step = mag;
	return d > 0 ? cur + step : cur - step;
}

// Render one segment into its place in the pin group's chain buffer.
static void render_seg(espled_t *st, seg_t *s) {
	group_t *grp = &st->group[s->group];
	int n = s->len;
	uint32_t *work = st->work;
	int colors = grp->colors;
	uint8_t *tx = grp->txbuf[grp->cur] + (uint32_t)s->offset * colors;

	fx_render(s, work);

	// Combined per-segment and master brightness
	uint32_t bri = ((uint32_t)s->bri_cur * st->master_cur) / 255;

	uint32_t sum = 0; // channel sum for the current estimate
	for (int i = 0; i < n; i++) {
		uint32_t c = scale(work[i], bri);

		uint32_t w = (c >> 24) & 0xFF;
		uint32_t r = (c >> 16) & 0xFF;
		uint32_t g = (c >> 8) & 0xFF;
		uint32_t b = c & 0xFF;

		// Derive white from the common RGB part on RGBW strips
		if (st->auto_white && colors == 4 && w == 0) {
			w = r < g ? (r < b ? r : b) : (g < b ? g : b);
			r -= w; g -= w; b -= w;
		}

		work[i] = pack(r, g, b, w);
		sum += r + g + b + w;
	}

	// Adaptive current limit: ~20 mA per full channel + 1 mA idle per LED.
	// The demand goes into the frame total and last frame's scale is
	// applied, so the cap holds across all segments together.
	if (st->ablimit_ma) {
		st->ma_frame += (sum * 20) / 255 + n;
		if (st->ma_scale < 255) {
			for (int i = 0; i < n; i++) {
				work[i] = scale(work[i], st->ma_scale);
			}
		}
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
		case TYPE_GRB:
		default:        px[0] = g; px[1] = r; px[2] = b; break;
		}
	}
}

static void render_thd(void *arg) {
	espled_t *st = (espled_t*)arg;

	while (!VESC_IF->should_terminate()) {
		// Ease brightness toward the targets and derive the current-limit
		// scale from last frame's total demand, once per frame.
		VESC_IF->mutex_lock(st->lock);
		st->master_cur = ease_u8(st->master_cur, st->master_bri, st->fade);
		for (int i = 0; i < st->seg_count; i++) {
			seg_t *s = &st->seg[i];
			s->bri_cur = ease_u8(s->bri_cur, s->bri, st->fade);
		}
		if (st->ablimit_ma && st->ma_frame > st->ablimit_ma) {
			st->ma_scale = (uint8_t)((st->ablimit_ma * 255) / st->ma_frame);
		} else {
			st->ma_scale = 255;
		}
		st->ma_frame = 0;
		VESC_IF->mutex_unlock(st->lock);

		for (int gi = 0; gi < st->group_count; gi++) {
			group_t *g = &st->group[gi];

			VESC_IF->mutex_lock(st->lock);
			bool any = false;
			for (int i = 0; i < st->seg_count; i++) {
				seg_t *s = &st->seg[i];
				if (s->defined && s->group == gi && s->len > 0
					&& s->len <= st->buf_len) {
					if (s->on) {
						render_seg(st, s);
					} else {
						memset(g->txbuf[g->cur] + (uint32_t)s->offset * g->colors,
							0, (uint32_t)(s->len + s->ov_count) * g->colors);
					}
					// Accumulate speed so speed changes take effect
					// in place, without moving the animation position.
					s->phase += s->spd ? s->spd : 32;
					any = true;
				}
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
				if (g->quiet >= ESPLED_REFRESH_FRAMES
					|| memcmp(g->txbuf[0], g->txbuf[1], (size_t)tx_bytes) != 0) {
					send = true;
					g->quiet = 0;
					g->cur ^= 1;
				} else if (g->quiet < 0xFFFF) {
					g->quiet++;
				}
			}
			VESC_IF->mutex_unlock(st->lock);

			// Hardware IO outside the lock - the firmware driver can block
			// while a previous transmission finishes. The firmware pools RMT
			// channels per pin, so this just hands off the frame for this
			// group's pin (strips were registered with rgbled_init at start).
			if (send) {
				VESC_IF->rgbled_update(pin, tx, tx_bytes);
			}
		}

		VESC_IF->sleep_ms(ESPLED_RENDER_MS);
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

static seg_t *seg_arg(espled_t *st, lbm_value v) {
	int i = VESC_IF->lbm_dec_as_i32(v);
	if (i < 0 || i >= ESPLED_SEG_MAX) {
		return NULL;
	}
	return &st->seg[i];
}

// ---- Extensions ---------------------------------------------------------

// (ext-espled-seg-def i pin type len [offset] [timing]) - define segment i
// before ext-espled-init. type: 0 GRB, 1 RGB, 2 GRBW, 3 RGBW. Segments on
// the same pin form one chain; offset is the segment's pixel position in
// it. timing selects the wire timing preset: 0 generic (default), 1
// WS2812B, 2 WS2815, 3 SK6812, 4 SK6815.
static lbm_value ext_seg_def(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
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

	if (!s || pin < 0 || pin > 255 || type < 0 || type > TYPE_RGBW
		|| len < 1 || len > 1024 || offset < 0 || offset > 1024
		|| timing < 0 || timing > 4) {
		return VESC_IF->lbm_enc_sym_terror;
	}

	if (st->running) {
		VESC_IF->lbm_set_error_reason(
			"Stop with ext-espled-deinit before redefining segments");
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
	s->fx = FX_SOLID;
	s->pal = 0;
	s->bri = 255;
	s->bri_cur = 255;
	s->spd = 32;
	s->size = 8;
	s->level = 255;
	s->color = 0;
	s->phase = 0;
	s->ov_count = 0;
	s->ov_color = 0;
	s->ov_bri = 0;
	VESC_IF->mutex_unlock(st->lock);

	return VESC_IF->lbm_enc_sym_true;
}

// (ext-espled-seg-overlay-def i idx0 idx1 ...) - define up to 8 overlay
// pixel positions for segment i, before ext-espled-init. Positions are
// segment-relative and extend the segment's footprint by one pixel each
// (effect pixels flow around them). No indices clears the overlay.
static lbm_value ext_seg_overlay_def(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
	if (argn < 1 || argn > 1 + ESPLED_OV_MAX) return VESC_IF->lbm_enc_sym_terror;
	for (lbm_uint i = 0; i < argn; i++) {
		if (!VESC_IF->lbm_is_number(args[i])) return VESC_IF->lbm_enc_sym_terror;
	}

	seg_t *s = seg_arg(st, args[0]);
	if (!s || !s->defined) return VESC_IF->lbm_enc_sym_terror;

	if (st->running) {
		VESC_IF->lbm_set_error_reason(
			"Stop with ext-espled-deinit before redefining segments");
		return VESC_IF->lbm_enc_sym_eerror;
	}

	int count = argn - 1;
	uint8_t idx[ESPLED_OV_MAX];
	for (int k = 0; k < count; k++) {
		int v = VESC_IF->lbm_dec_as_i32(args[k + 1]);
		if (v < 0 || v >= s->len + count) {
			VESC_IF->lbm_set_error_reason("Overlay index outside the strip");
			return VESC_IF->lbm_enc_sym_terror;
		}
		idx[k] = (uint8_t)v;
	}

	VESC_IF->mutex_lock(st->lock);
	s->ov_count = (uint8_t)count;
	for (int k = 0; k < count; k++) {
		s->ov_idx[k] = idx[k];
	}
	VESC_IF->mutex_unlock(st->lock);

	return VESC_IF->lbm_enc_sym_true;
}

// (ext-espled-seg-overlay i color bri) - set the overlay color and
// brightness at runtime (bri 0 turns the overlay pixels off).
static lbm_value ext_seg_overlay(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
	if (!check_num_args(args, argn, 3)) return VESC_IF->lbm_enc_sym_terror;

	seg_t *s = seg_arg(st, args[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	s->ov_color = VESC_IF->lbm_dec_as_u32(args[1]);
	s->ov_bri = (uint8_t)VESC_IF->lbm_dec_as_i32(args[2]);
	VESC_IF->mutex_unlock(st->lock);

	return VESC_IF->lbm_enc_sym_true;
}

// (ext-espled-init n) - start rendering the first n segments.
static lbm_value ext_init(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;

	int n = VESC_IF->lbm_dec_as_i32(args[0]);
	if (n < 1 || n > ESPLED_SEG_MAX) return VESC_IF->lbm_enc_sym_terror;

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
			st->group[s->group].quiet = 0xFFFF;
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

	if (alloc_ok) {
		st->buf_len = max_len;
		st->seg_count = n;
		// Register each pin group as a strip so the firmware can bind RMT
		// channels (dedicated while they fit, shared beyond that).
		for (int gi = 0; gi < st->group_count; gi++) {
			VESC_IF->rgbled_init(st->group[gi].pin, st->group[gi].timing);
		}
		st->thread = VESC_IF->spawn(render_thd, 3072, "espled_render", st);
		alloc_ok = st->thread != NULL;
	}

	if (!alloc_ok) {
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
		return VESC_IF->lbm_enc_sym_merror;
	}

	st->ma_frame = 0;
	st->ma_scale = 255;
	st->running = true;

	return VESC_IF->lbm_enc_sym_true;
}

static void espled_stop(espled_t *st) {
	if (!st->running) {
		return;
	}
	VESC_IF->request_terminate(st->thread);
	st->running = false;

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
	st->group_count = 0;
	st->buf_len = 0;
	st->seg_count = 0;
}

// (ext-espled-deinit)
static lbm_value ext_deinit(lbm_value *args, lbm_uint argn) {
	(void)args; (void)argn;
	espled_stop(state());
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-espled-seg-look i fx pal color spd bri) - full appearance in one call.
static lbm_value ext_seg_look(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
	if (!check_num_args(args, argn, 6)) return VESC_IF->lbm_enc_sym_terror;

	seg_t *s = seg_arg(st, args[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	uint8_t fx = (uint8_t)VESC_IF->lbm_dec_as_i32(args[1]);
	if (s->fx != fx) {
		s->fx = fx;
		s->phase = 0; // restart only when the effect actually changes,
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
enum { SET_FX = 0, SET_PAL, SET_BRI, SET_SPD, SET_COLOR, SET_ON, SET_REVERSE, SET_SIZE, SET_LEVEL };

static void seg_set(seg_t *s, int field, uint32_t v) {
	switch (field) {
	case SET_FX:      if (s->fx != (uint8_t)v) { s->fx = (uint8_t)v; s->phase = 0; } break;
	case SET_PAL:     s->pal = (uint8_t)v; break;
	case SET_BRI:     s->bri = (uint8_t)v; break;
	case SET_SPD:     s->spd = (uint8_t)v; break;
	case SET_COLOR:   s->color = v; break;
	case SET_ON:      s->on = v != 0; break;
	case SET_REVERSE: s->reverse = v != 0; break;
	case SET_SIZE:    s->size = (uint8_t)v; break;
	case SET_LEVEL:   s->level = (uint8_t)v; break;
	}
}

static lbm_value set_one(lbm_value *args, lbm_uint argn, int field) {
	espled_t *st = state();
	if (!check_num_args(args, argn, 2)) return VESC_IF->lbm_enc_sym_terror;

	seg_t *s = seg_arg(st, args[0]);
	if (!s) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	seg_set(s, field, VESC_IF->lbm_dec_as_u32(args[1]));
	VESC_IF->mutex_unlock(st->lock);
	return VESC_IF->lbm_enc_sym_true;
}

static lbm_value set_all(lbm_value *args, lbm_uint argn, int field) {
	espled_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;

	VESC_IF->mutex_lock(st->lock);
	for (int i = 0; i < ESPLED_SEG_MAX; i++) {
		seg_set(&st->seg[i], field, VESC_IF->lbm_dec_as_u32(args[0]));
	}
	VESC_IF->mutex_unlock(st->lock);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-espled-seg-fx i fx) / (ext-espled-fx fx)
static lbm_value ext_seg_fx(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_FX); }
static lbm_value ext_fx(lbm_value *a, lbm_uint n) { return set_all(a, n, SET_FX); }

// (ext-espled-seg-pal i pal) / (ext-espled-pal pal)
static lbm_value ext_seg_pal(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_PAL); }
static lbm_value ext_pal(lbm_value *a, lbm_uint n) { return set_all(a, n, SET_PAL); }

// (ext-espled-seg-bri i bri)
static lbm_value ext_seg_bri(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_BRI); }

// (ext-espled-seg-spd i spd)
static lbm_value ext_seg_spd(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_SPD); }

// (ext-espled-seg-size i size) - chase head / comet tail length
static lbm_value ext_seg_size(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_SIZE); }

// (ext-espled-seg-level i level) - gauge fill 0..255
static lbm_value ext_seg_level(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_LEVEL); }

// (ext-espled-seg-col i color) / (ext-espled-col color) - packed 0xWWRRGGBB
static lbm_value ext_seg_col(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_COLOR); }
static lbm_value ext_col(lbm_value *a, lbm_uint n) { return set_all(a, n, SET_COLOR); }

// (ext-espled-seg-on i on)
static lbm_value ext_seg_on(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_ON); }

// (ext-espled-seg-reverse i rev)
static lbm_value ext_seg_reverse(lbm_value *a, lbm_uint n) { return set_one(a, n, SET_REVERSE); }

// (ext-espled-col-rgb r g b) / (ext-espled-col-rgbw r g b w) - solid color on
// all segments, like fled-col-rgb.
static lbm_value ext_col_rgbw(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
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
	for (int i = 0; i < ESPLED_SEG_MAX; i++) {
		st->seg[i].color = c;
		st->seg[i].fx = FX_SOLID;
	}
	VESC_IF->mutex_unlock(st->lock);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-espled-bri b) - master brightness 0..255
static lbm_value ext_bri(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;
	st->master_bri = (uint8_t)VESC_IF->lbm_dec_as_i32(args[0]);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-espled-fade rate) - brightness easing: fraction of the remaining
// gap closed per frame, in 32nds (0 = instant, 8 = 25%/frame, 32 = full).
// Applies to master and segment brightness changes.
static lbm_value ext_fade(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;
	st->fade = (uint8_t)VESC_IF->lbm_dec_as_i32(args[0]);
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-espled-auto-white en) - derive W from RGB on RGBW strips
static lbm_value ext_auto_white(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;
	st->auto_white = VESC_IF->lbm_dec_as_i32(args[0]) != 0;
	return VESC_IF->lbm_enc_sym_true;
}

// (ext-espled-ablimit ma) - adaptive current cap in mA, 0 = off
static lbm_value ext_ablimit(lbm_value *args, lbm_uint argn) {
	espled_t *st = state();
	if (!check_num_args(args, argn, 1)) return VESC_IF->lbm_enc_sym_terror;
	int ma = VESC_IF->lbm_dec_as_i32(args[0]);
	st->ablimit_ma = ma < 0 ? 0 : (uint32_t)ma;
	return VESC_IF->lbm_enc_sym_true;
}

// ---- Lifecycle ----------------------------------------------------------

static void stop(void *arg) {
	espled_t *st = (espled_t*)arg;

	if (st) {
		espled_stop(st);
		VESC_IF->free(st->lock);
		VESC_IF->free(st);
	}

	VESC_IF->printf("espled-strip lib stopped");
}

INIT_FUN(lib_info *info) {
	INIT_START

	espled_t *st = VESC_IF->malloc(sizeof(espled_t));
	if (!st) {
		return false;
	}

	for (unsigned int i = 0; i < sizeof(espled_t); i++) {
		((uint8_t*)st)[i] = 0;
	}

	st->master_bri = 255;
	st->master_cur = 255;
	st->fade = 15; // close ~half the gap per frame (~0.2 s to settle)
	st->lock = VESC_IF->mutex_create();
	if (!st->lock) {
		VESC_IF->free(st);
		return false;
	}

	info->arg = st;
	info->stop_fun = stop;

	VESC_IF->lbm_add_extension("ext-espled-seg-def", ext_seg_def);
	VESC_IF->lbm_add_extension("ext-espled-seg-overlay-def", ext_seg_overlay_def);
	VESC_IF->lbm_add_extension("ext-espled-seg-overlay", ext_seg_overlay);
	VESC_IF->lbm_add_extension("ext-espled-init", ext_init);
	VESC_IF->lbm_add_extension("ext-espled-deinit", ext_deinit);
	VESC_IF->lbm_add_extension("ext-espled-seg-look", ext_seg_look);
	VESC_IF->lbm_add_extension("ext-espled-seg-fx", ext_seg_fx);
	VESC_IF->lbm_add_extension("ext-espled-fx", ext_fx);
	VESC_IF->lbm_add_extension("ext-espled-seg-pal", ext_seg_pal);
	VESC_IF->lbm_add_extension("ext-espled-pal", ext_pal);
	VESC_IF->lbm_add_extension("ext-espled-seg-bri", ext_seg_bri);
	VESC_IF->lbm_add_extension("ext-espled-seg-spd", ext_seg_spd);
	VESC_IF->lbm_add_extension("ext-espled-seg-size", ext_seg_size);
	VESC_IF->lbm_add_extension("ext-espled-seg-level", ext_seg_level);
	VESC_IF->lbm_add_extension("ext-espled-seg-col", ext_seg_col);
	VESC_IF->lbm_add_extension("ext-espled-col", ext_col);
	VESC_IF->lbm_add_extension("ext-espled-seg-on", ext_seg_on);
	VESC_IF->lbm_add_extension("ext-espled-seg-reverse", ext_seg_reverse);
	VESC_IF->lbm_add_extension("ext-espled-col-rgb", ext_col_rgbw);
	VESC_IF->lbm_add_extension("ext-espled-col-rgbw", ext_col_rgbw);
	VESC_IF->lbm_add_extension("ext-espled-bri", ext_bri);
	VESC_IF->lbm_add_extension("ext-espled-fade", ext_fade);
	VESC_IF->lbm_add_extension("ext-espled-auto-white", ext_auto_white);
	VESC_IF->lbm_add_extension("ext-espled-ablimit", ext_ablimit);

	VESC_IF->printf("espled-strip lib loaded");

	return true;
}
