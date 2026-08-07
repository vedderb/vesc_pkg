# ESP LED Strip

Segmented addressable-LED strip engine for the VESC Express as a native library, with a QML test page. LispBM sets high-level segment / effect state, and a background render thread animates, applies brightness and RGBW auto-white, and pushes pixels through the firmware rgbled driver.

Works on all Express targets (ESP32-C3, C6, S3, P4) - the package contains one binary per chip and picks the right one at runtime with `(sysinfo 'hw-target)`.

## Test UI

The package includes a VESC Tool page for testing. Each LED strip is a tab: use **+ Add** to add a strip, set its pin / LED count / type / timing, then play with effects, palettes, colour, per-strip level and RGBW auto-white (enabled only on strips with a white channel). Several strips on different pins run at once (the firmware pools the chip's RMT channels behind the pins). A **Global** tab holds master brightness and fade, plus **Sync animations** (lines up the effects on every strip, which otherwise start whenever they were set) and **Stop all**. The controls send LispBM expressions to the device as custom app data, which `esp_led_strip.lisp` evaluates. The page opens with no strips, leaving the device running whatever it already had until a strip is added.

## Extensions

| Extension | Args | Notes |
|---|---|---|
| `ext-esp_led-seg-def` | `(i pin type len [offset] [timing])` | define segment `i` (type: 0 GRB, 1 RGB, 2 GRBW, 3 RGBW, 4 WRGB - white first, e.g. WS2814. Types 2+ are 4 bytes per pixel). Segments on the same pin form one chained strip; `offset` is the segment's pixel position in the chain. `timing` selects the wire timing: 0 generic (default), 1 WS2812B, 2 WS2815, 3 SK6812, 4 SK6815 |
| `ext-esp_led-init` | `(n)` | start rendering the first `n` segments |
| `ext-esp_led-deinit` | `()` | stop rendering and release the LED driver |
| `ext-esp_led-seg-look` | `(i fx pal color spd bri)` | full appearance in one call |
| `ext-esp_led-seg-fx` / `ext-esp_led-fx` | `(i fx)` / `(fx)` | effect per segment / all segments |
| `ext-esp_led-seg-pal` / `ext-esp_led-pal` | `(i pal)` / `(pal)` | palette: 0 = custom (set with `ext-esp_led-seg-palette`), 1..18 = built-in |
| `ext-esp_led-seg-col` / `ext-esp_led-col` | `(i color)` / `(color)` | packed `0xWWRRGGBB` |
| `ext-esp_led-col-rgb` / `ext-esp_led-col-rgbw` | `(r g b [w])` | solid color on all segments |
| `ext-esp_led-seg-bri` | `(i bri)` | per-segment brightness 0..255 |
| `ext-esp_led-seg-spd` | `(i spd)` | animation speed 0..255 |
| `ext-esp_led-seg-size` | `(i size)` | chase head / comet tail length |
| `ext-esp_led-seg-level` | `(i level)` | gauge fill level 0..255 |
| `ext-esp_led-seg-overlay-def` | `(i idx...)` | define up to 8 fixed overlay pixel positions (e.g. embedded highbeam LEDs) before init; effect pixels flow around them. No indices clears the overlay |
| `ext-esp_led-seg-overlay` | `(i color bri)` | overlay color and brightness at runtime (bri 0 = off) |
| `ext-esp_led-seg-on` | `(i on)` | enable/disable a segment |
| `ext-esp_led-seg-reverse` | `(i rev)` | reverse pixel order |
| `ext-esp_led-sync` / `ext-esp_led-seg-sync` | `()` / `(i)` | restart animations from phase 0: every segment (all in the same frame, so segments running the same speed line up) or one segment. Changes nothing else about the segments |
| `ext-esp_led-seg-auto-white` | `(i en)` | derive W from the common RGB part on segment `i`. Only affects 4-colour strips, and only pixels whose white byte is 0, so an explicitly set W always wins. Off by default, and reset by `ext-esp_led-seg-def` |
| `ext-esp_led-seg-custom` | `(i)` | put segment `i` in custom mode (effect 1): a blank consumer-driven pixel buffer, so you can run your own effect while still getting brightness / channel pooling |
| `ext-esp_led-seg-pixel` | `(i idx color)` | set one custom pixel (packed `0xWWRRGGBB`); enters custom mode automatically |
| `ext-esp_led-seg-pixels` | `(i start colors)` | set consecutive custom pixels from `start`, `colors` a list of packed values; enters custom mode automatically |
| `ext-esp_led-seg-palette` | `(i c0 c1 c2 c3)` | set segment `i`'s custom palette (4 anchor colours) and select it (palette 0), to recolour the gradient effects |
| `ext-esp_led-bri` | `(b)` | master brightness 0..255 |
| `ext-esp_led-fade` | `(rate)` | brightness easing: fraction of the remaining gap closed per frame in 32nds (0 = instant, default 15 = ~47%/frame) |

Effects: 0 off (all pixels dark, whatever the colour), 1 custom (consumer-supplied pixels via `ext-esp_led-seg-pixel` / `-pixels`), 2 solid, 3 breathe, 4 chase, 5 rainbow, 6 sparkle, 7 comet, 8 gauge (fill by `level`, pulses when `spd` > 0), 9 strobe, 10 larson/knight-rider, 11 felony (halves alternate red/blue), 12 theater (marching marquee), 13 wipe (fill then wipe to black), 14 waves (overlapping slow waves), 15 candle (warm flicker), 16 heartbeat (double pulse), 17 turn signal (splits the strip in half; `level` selects the mode - 0 off, then left/right/hazard x solid/blink/sweep as `1 + side*3 + style`; defaults to amber when no colour is set).

Color semantics: a segment color of 0 means "take color from the palette" - breathe, chase, sparkle, comet, strobe, larson, theater, wipe, waves and heartbeat then cycle their color through the palette, and rainbow always draws the palette. Exceptions: solid with color 0 is black (so segments can be blanked - or use effect 0, off), gauge draws the palette as a gradient along the fill for palettes 1+ (and a battery-style red-to-green gradient for palette 0), felony has fixed red/blue, and candle with color 0 uses a fixed warm flame color.
Palettes: 0 custom (4 anchor colours set with `ext-esp_led-seg-palette`; recolours the gradient effects - gauge excepted, which reads palette 0 as its battery gradient), 1 spectrum, 2 fire, 3 ocean, 4 neon, 5 ember, 6 traffic, 7 b&w flash, 8 police-blue, 9 sunset, 10 lava, 11 aurora, 12 forest, 13 party, 14 ice, 15 halloween, 16 christmas, 17 pastel, 18 sakura.

## Using the library

A native lib only runs on the chip it was built for, so there is one binary per
chip and the consumer picks the right one at runtime. Whichever way you get at
the binaries, the selection and the calls are the same - only the four `import`
lines differ. Pick the style that matches where your code lives:

| Your code is | Use |
| --- | --- |
| A package in the released archive | `pkg::` with `://vesc_packages/…` |
| A package built locally against a checkout | `pkg::` with a relative `.vescpkg` path |
| A sibling package in this repo | relative paths straight to the files |
| An ad-hoc script in the lisp editor | `pkg::` with `://vesc_packages/…`, or absolute paths |

### Loading the binary

```clj
; --- from the package archive (released) --------------------------------
(import "pkg::lib-esp32c3@://vesc_packages/lib_esp_led_strip/esp_led_strip.vescpkg" 'led-c3)
(import "pkg::lib-esp32c6@://vesc_packages/lib_esp_led_strip/esp_led_strip.vescpkg" 'led-c6)
(import "pkg::lib-esp32s3@://vesc_packages/lib_esp_led_strip/esp_led_strip.vescpkg" 'led-s3)
(import "pkg::lib-esp32p4@://vesc_packages/lib_esp_led_strip/esp_led_strip.vescpkg" 'led-p4)

; --- from a locally built .vescpkg --------------------------------------
; Same labels, but the @ points at the package on disk. Build it first with
; `make -C ../lib_esp_led_strip`.
;
; (import "pkg::lib-esp32c3@../lib_esp_led_strip/esp_led_strip.vescpkg" 'led-c3)
; (import "pkg::lib-esp32c6@../lib_esp_led_strip/esp_led_strip.vescpkg" 'led-c6)
; (import "pkg::lib-esp32s3@../lib_esp_led_strip/esp_led_strip.vescpkg" 'led-s3)
; (import "pkg::lib-esp32p4@../lib_esp_led_strip/esp_led_strip.vescpkg" 'led-p4)

; --- straight from the built files (sibling package in this repo) -------
; No packaging step and no labels - just the .bin files themselves. Build
; them first with `make -C ../lib_esp_led_strip libs`. This is what
; float_accessories does.
;
; (import "../lib_esp_led_strip/esp_led_strip/esp_led_strip_esp32c3.bin" 'led-c3)
; (import "../lib_esp_led_strip/esp_led_strip/esp_led_strip_esp32c6.bin" 'led-c6)
; (import "../lib_esp_led_strip/esp_led_strip/esp_led_strip_esp32s3.bin" 'led-s3)
; (import "../lib_esp_led_strip/esp_led_strip/esp_led_strip_esp32p4.bin" 'led-p4)

(def target (sysinfo 'hw-target))

(def lib (cond
    ((= (str-cmp target "esp32c3") 0) led-c3)
    ((= (str-cmp target "esp32c6") 0) led-c6)
    ((= (str-cmp target "esp32s3") 0) led-s3)
    ((= (str-cmp target "esp32p4") 0) led-p4)
    (t nil)
))

(if (eq lib nil)
    (print (str-merge "esp_led: no native lib for target " target))
    (load-native-lib lib)
)
```

All three forms are resolved by VESC Tool when the consumer package is built,
and the imported data is copied into it - so the finished `.vescpkg` is
self-contained either way. The difference is only what has to exist at build
time: the archive, a built `.vescpkg`, or the raw `.bin` files.

Relative paths resolve against the directory of the lisp file being packaged.
For an ad-hoc script that has never been saved there is no such directory, so
use the `://vesc_packages/` form or absolute paths.

### The effect and palette constants

`esp_led_defs.lisp` gives the ids readable names (`FX-RAINBOW`, `PAL-NEON`, …)
and is generated from `code.c`, so it cannot drift from the firmware. It is a
plain lisp file, imported and evaluated rather than loaded as a lib:

```clj
(import "../lib_esp_led_strip/esp_led_defs.lisp" 'esp-led-defs)
(read-eval-program esp-led-defs)

(ext-esp_led-seg-fx 0 FX-RAINBOW)
```

Generate it with `make -C ../lib_esp_led_strip defs` (the `libs` target does it
too). It is not in git, and it is **not reachable through `pkg::`** - the
library's own lisp imports only the four binaries, so there is no label for the
defs. Consumers outside this repo have to use the numeric ids from the tables
above, or copy the file.

### What does not come across

Only the files you import cross over. The library's own `esp_led_strip.lisp`
does not run in a consumer package, so its `esp_led-setup` helper and its
`event-data-rx` handler are not available - a package driving this lib from a
QML page has to provide its own command handling.

### Example

```clj
(ext-esp_led-seg-def 0 20 0 30) ; seg 0: pin 20, GRB, 30 px
(ext-esp_led-init 1)
(ext-esp_led-bri 128)
(ext-esp_led-seg-fx 0 5)        ; rainbow - see the effect ids above
```

Segments can sit on different pins. The firmware pools the chip's RMT TX channels (2 on the ESP32-C3/C6, 4 on the S3) behind the LED driver, so any number of pins works: strips that fit the pool are driven continuously, and beyond that pins share a channel and are refreshed in turn (each strip holds its last frame between refreshes). The default timing is the firmware's universal preset, which covers WS2812B / WS2815 / SK6812 / SK6815; a strip-specific preset can be picked per pin with the `timing` argument of `ext-esp_led-seg-def`.

Frames are only transmitted when they differ from what the strip already shows (WLED-style dirty tracking), so static content keeps the data line quiet - useful on setups prone to EMF pickup. A keepalive retransmit every ~2 s heals pixels corrupted by line noise.

## Quirks and limitations

- The library draws whatever the strips ask for: there is no current limiting, so sizing the supply (and capping brightness where it matters) is the consumer's job.
- Overlay pixels deliberately bypass master brightness and fading - they are meant for headlights that must not dim with the effects. Turning a segment off (`ext-esp_led-seg-on i 0`) blanks its overlay pixels too.
- The effect phase is a 32-bit frame accumulator; at maximum speed it wraps about once a week, causing a single one-frame jump in the animation.
- `ext-esp_led-sync` lines animations up only at the moment it is called. Segments then keep their own phase, so any difference in speed makes them drift apart again, and the position-based effects (chase, comet, larson, wipe, theater, turn sweep) still look different on strips of different lengths because their period follows the LED count.
- The C interface has no way to destroy a mutex, so each load/unload cycle of the lib leaks one FreeRTOS mutex (~80 bytes of kernel heap). This only matters if LispBM is restarted very many times without a reboot.
- Segments on one pin must not overlap on the chain (validated at `ext-esp_led-init`), and must share the same color depth (3 vs 4 bytes per pixel) and timing preset.

## Building

```sh
make
```

Needs the `riscv32-esp-elf` and `xtensa-esp32s3-elf` toolchains, the `c_libs/RVfplib` submodule and `vesc_tool`.

## Requirements

Firmware with native lib support including `(sysinfo 'hw-target)` and the `rgbled_*` C interface. On the ESP32-S3 the firmware must be built with `CONFIG_ESP_SYSTEM_MEMPROT_FEATURE=n`.
