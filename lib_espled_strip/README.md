# ESPLED Strip

Segmented addressable-LED strip engine for the VESC Express as a native library, with a QML test page. LispBM sets high-level segment / effect state, and a background render thread animates, applies brightness, RGBW auto-white and an adaptive current limit, and pushes pixels through the firmware rgbled driver.

Works on all Express targets (ESP32-C3, C6, S3, P4) - the package contains one binary per chip and picks the right one at runtime with `(sysinfo 'hw-target)`.

## Test UI

The package includes a VESC Tool page for testing. Each LED strip is a tab: use **+ Add** to add a strip, set its pin / LED count / type / timing, then play with effects, palettes, colour and per-strip level. Several strips on different pins run at once (the firmware pools the chip's RMT channels behind the pins). A **Global** tab holds master brightness, fade, RGBW auto-white and the current limit, plus **Stop all**. The controls send LispBM expressions to the device as custom app data, which `espled_strip.lisp` evaluates. One strip is added automatically when the page opens.

## Extensions

| Extension | Args | Notes |
|---|---|---|
| `ext-espled-seg-def` | `(i pin type len [offset] [timing])` | define segment `i` (type: 0 GRB, 1 RGB, 2 GRBW, 3 RGBW). Segments on the same pin form one chained strip; `offset` is the segment's pixel position in the chain. `timing` selects the wire timing: 0 generic (default), 1 WS2812B, 2 WS2815, 3 SK6812, 4 SK6815 |
| `ext-espled-init` | `(n)` | start rendering the first `n` segments |
| `ext-espled-deinit` | `()` | stop rendering and release the LED driver |
| `ext-espled-seg-look` | `(i fx pal color spd bri)` | full appearance in one call |
| `ext-espled-seg-fx` / `ext-espled-fx` | `(i fx)` / `(fx)` | effect per segment / all segments |
| `ext-espled-seg-pal` / `ext-espled-pal` | `(i pal)` / `(pal)` | palette: 0 = custom (set with `ext-espled-seg-palette`), 1..18 = built-in |
| `ext-espled-seg-col` / `ext-espled-col` | `(i color)` / `(color)` | packed `0xWWRRGGBB` |
| `ext-espled-col-rgb` / `ext-espled-col-rgbw` | `(r g b [w])` | solid color on all segments |
| `ext-espled-seg-bri` | `(i bri)` | per-segment brightness 0..255 |
| `ext-espled-seg-spd` | `(i spd)` | animation speed 0..255 |
| `ext-espled-seg-size` | `(i size)` | chase head / comet tail length |
| `ext-espled-seg-level` | `(i level)` | gauge fill level 0..255 |
| `ext-espled-seg-overlay-def` | `(i idx...)` | define up to 8 fixed overlay pixel positions (e.g. embedded highbeam LEDs) before init; effect pixels flow around them. No indices clears the overlay |
| `ext-espled-seg-overlay` | `(i color bri)` | overlay color and brightness at runtime (bri 0 = off) |
| `ext-espled-seg-on` | `(i on)` | enable/disable a segment |
| `ext-espled-seg-reverse` | `(i rev)` | reverse pixel order |
| `ext-espled-seg-custom` | `(i)` | put segment `i` in custom mode (effect 1): a blank consumer-driven pixel buffer, so you can run your own effect while still getting brightness / current limit / channel pooling |
| `ext-espled-seg-pixel` | `(i idx color)` | set one custom pixel (packed `0xWWRRGGBB`); enters custom mode automatically |
| `ext-espled-seg-pixels` | `(i start colors)` | set consecutive custom pixels from `start`, `colors` a list of packed values; enters custom mode automatically |
| `ext-espled-seg-palette` | `(i c0 c1 c2 c3)` | set segment `i`'s custom palette (4 anchor colours) and select it (palette 0), to recolour the gradient effects |
| `ext-espled-bri` | `(b)` | master brightness 0..255 |
| `ext-espled-fade` | `(rate)` | brightness easing: fraction of the remaining gap closed per frame in 32nds (0 = instant, default 15 = ~47%/frame) |
| `ext-espled-auto-white` | `(en)` | derive W from RGB on RGBW strips |
| `ext-espled-ablimit` | `(ma)` | adaptive current cap in mA (0 = off) |

Effects: 0 off (all pixels dark, whatever the colour), 1 custom (consumer-supplied pixels via `ext-espled-seg-pixel` / `-pixels`), 2 solid, 3 breathe, 4 chase, 5 rainbow, 6 sparkle, 7 comet, 8 gauge (fill by `level`, pulses when `spd` > 0), 9 strobe, 10 larson/knight-rider, 11 felony (halves alternate red/blue), 12 theater (marching marquee), 13 wipe (fill then wipe to black), 14 waves (overlapping slow waves), 15 candle (warm flicker), 16 heartbeat (double pulse), 17 turn signal (splits the strip in half; `level` selects the mode - 0 off, then left/right/hazard x solid/blink/sweep as `1 + side*3 + style`; defaults to amber when no colour is set).

Color semantics: a segment color of 0 means "take color from the palette" - breathe, chase, sparkle, comet, strobe, larson, theater, wipe, waves and heartbeat then cycle their color through the palette, and rainbow always draws the palette. Exceptions: solid with color 0 is black (so segments can be blanked - or use effect 0, off), gauge draws the palette as a gradient along the fill for palettes 1+ (and a battery-style red-to-green gradient for palette 0), felony has fixed red/blue, and candle with color 0 uses a fixed warm flame color.
Palettes: 0 custom (4 anchor colours set with `ext-espled-seg-palette`; recolours the gradient effects - gauge excepted, which reads palette 0 as its battery gradient), 1 spectrum, 2 fire, 3 ocean, 4 neon, 5 ember, 6 traffic, 7 b&w flash, 8 police-blue, 9 sunset, 10 lava, 11 aurora, 12 forest, 13 party, 14 ice, 15 halloween, 16 christmas, 17 pastel, 18 sakura.

## Example

```clj
(import "pkg::espled@://vesc_packages/lib_espled_strip/espled_strip.vescpkg" 'espled)
(load-native-lib espled)

(ext-espled-seg-def 0 20 0 30) ; seg 0: pin 20, GRB, 30 px
(ext-espled-init 1)
(ext-espled-bri 128)
(ext-espled-seg-fx 0 3)        ; rainbow
```

Segments can sit on different pins. The firmware pools the chip's RMT TX channels (2 on the ESP32-C3/C6, 4 on the S3) behind the LED driver, so any number of pins works: strips that fit the pool are driven continuously, and beyond that pins share a channel and are refreshed in turn (each strip holds its last frame between refreshes). The default timing is the firmware's universal preset, which covers WS2812B / WS2815 / SK6812 / SK6815; a strip-specific preset can be picked per pin with the `timing` argument of `ext-espled-seg-def`.

Frames are only transmitted when they differ from what the strip already shows (WLED-style dirty tracking), so static content keeps the data line quiet - useful on setups prone to EMF pickup. A keepalive retransmit every ~2 s heals pixels corrupted by line noise.

## Quirks and limitations

- The current limit (`ext-espled-ablimit`) is an estimate (~20 mA per full channel + 1 mA idle per LED at 5 V), summed across all segments. The scale it produces is computed from the previous frame's demand, so a sudden jump can exceed the cap for one frame (~33 ms) before settling.
- Overlay pixels deliberately bypass master brightness, fading and the current limiter - they are meant for headlights that must not dim with the effects. Turning a segment off (`ext-espled-seg-on i 0`) blanks its overlay pixels too.
- The effect phase is a 32-bit frame accumulator; at maximum speed it wraps about once a week, causing a single one-frame jump in the animation.
- The C interface has no way to destroy a mutex, so each load/unload cycle of the lib leaks one FreeRTOS mutex (~80 bytes of kernel heap). This only matters if LispBM is restarted very many times without a reboot.
- Segments on one pin must not overlap on the chain (validated at `ext-espled-init`), and must share the same color depth (3 vs 4 bytes per pixel) and timing preset.

## Building

```sh
make
```

Needs the `riscv32-esp-elf` and `xtensa-esp32s3-elf` toolchains, the `c_libs/RVfplib` submodule and `vesc_tool`.

## Requirements

Firmware with native lib support including `(sysinfo 'hw-target)` and the `rgbled_*` C interface. On the ESP32-S3 the firmware must be built with `CONFIG_ESP_SYSTEM_MEMPROT_FEATURE=n`.
