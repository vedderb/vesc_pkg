# Technical notes

Design/protocol details behind `main.lisp`, kept out of the code comments
to keep the script itself readable. Mirrors the file's own section order.

## Architecture

Single shared event dispatcher (`event-loop`): only one process may block
on `can-recv-sid`/`recv-data` at a time in this firmware, so every CAN/
custom-app-data consumer runs through this one loop rather than spawning
a second receiver. The `canmsg-recv` listeners (`vesc-info-listener`,
`vesc-register-listener`) are exempt -- they have their own separate
per-slot blocking mechanism.

Inter-device messaging (Express <-> VESC(s)) uses `canmsg-send`/
`canmsg-recv` (controller-ID addressed), not raw CAN frames. It's
point-to-point, not a bus broadcast, so Express has to track every
registered VESC's controller-id itself (`relay-targets`, grown via
`handle-vesc-info`/`handle-vesc-register`).

## Pins

Pin 7 ("Multipin") is confirmed from the reference hardware's production
GPIO map to be a horn/underglow output, not a button input (an earlier,
incorrect assumption in this project's history). Only underglow is
driven here; horn isn't implemented.

## Vehicle constants and VESC registration

`vesc-can-id`/`motor-poles`/`wheel-diam-mm`/`battery-pct`/`voltage-v`/
`motor-temp-c` are learned from `vesc-side-master.lisp`'s registration
message over `canmsg-recv` (slot `slot-vesc-info`), not configured here.

Registration payload layout (8 bytes): byte 0 CAN id, byte 1 motor poles,
bytes 2-3 wheel diameter in mm (little-endian u16), byte 4 battery %,
bytes 5-6 voltage x10 (little-endian u16), byte 7 motor temperature.
Voltage/motor-temp are only present in newer payloads -- `handle-vesc-info`
checks `buflen` before reading bytes 5-7 since reading past a real
buffer's end is a hard `eval_error` that kills the whole script, not a
safe out-of-range read.

The slave registration (`slot-vesc-register`) is just byte 0 (CAN id) --
Express doesn't track a slave's motor config or battery, it just adds it
as a speed-relay target.

## EEPROM settings

`ee-settings-sentinel` must be bumped whenever a new settings field is
added. `init-settings` only re-seeds defaults when the stored sentinel
doesn't match, so a board with an old sentinel would otherwise leave new
fields at their never-written eeprom value (`nil`, not `0` -- which is
why reads use `not-eq`, not `!=`; the latter is numeric-only and
type-errors on `nil`).

## Dashboard boot detection (0x100)

0x100 is the dashboard's own heartbeat (~20ms while it's on). A gap in it
longer than `dashboard-boot-gap-ms` (2000ms, matching the reference
firmware's own confirmed heartbeat timeout) means the dashboard was off,
or Express itself just booted. When 0x100 resumes after that gap, the
current speed-limit profile is re-applied to every registered VESC
immediately, rather than waiting for the next actual 0x20C change --
which might not arrive for a long time if the dashboard powers back on
into the same profile it was already in.

## Profile-switch speed relay

Express decodes the drive-mode byte from 0x20C and relays the resulting
speed to every registered VESC, gated by the `disable-prof-sw` setting --
this is the only mechanism giving that toggle somewhere to take effect,
since the VESC-side scripts don't read 0x20C directly. Each VESC still
computes its own target ERPM locally via `conf-get`. When
`disable-prof-sw` is set, Express simply stops sending updates; it
doesn't force a specific speed.

`send-current-speed-to` exists because a VESC that registers *after*
Express has already set `last-drive-mode-byte` (reboots mid-ride, or
just registers a beat after Express's own boot) would otherwise never
get anything until the rider actually switches profile -- `handle-drive-mode`
only relays on change.

## MCU/BMS status frame emulation

Byte templates for the periodic dashboard-facing frames are copied
verbatim from the reference firmware's own scheduled-message table; only
specific bytes get patched live (see `patch-telemetry`/`patch-battery`).

The BMS frame family (0x310/0x311/0x420-0x425/0x500-0x502) is suppressed
as one unit when `bms-mode` is 1 (a real BMS owns the bus then) --
confirmed from the reference firmware's own skip logic, which treats
this whole group as one all-or-nothing unit, not per-frame.

0x420's voltage/current fields are x100 real value (not x10 -- the
reference firmware double-scales: VESC's own STATUS_4/5 already report
x10 in VESC's native convention, then the reference multiplies by
another x10 before the wire write). SoC is x10 (`reported-battery-pct() *
10`).

`patch-telemetry`'s speed field is rounded to the nearest whole km/h
(round-half-up: `+0.5` before truncating) rather than kept at 0.1 km/h
precision -- the physical dashboard floors rather than rounds when
rendering a sub-integer value, so keeping fractional precision on the
wire gets silently displayed wrong on the dashboard's own side anyway.

## "Bypass Speed limit warning"

Ported from the reference firmware's `nativeSpeedDisplayEnabled` flag
(`can_helper.cpp`'s `display_update_task`), but tracking the actual
active profile's limit (`last-drive-mode-byte`, from 0x20C) instead of
the reference's fixed 22 km/h constant.

When the toggle is on and real speed exceeds the current profile's
limit, the displayed speed on 0x211 is forced to a fake 1.0 km/h for the
last `speed-warn-flash-ms` (100ms) of every `speed-warn-trigger-ms` +
`speed-warn-flash-ms` (1100ms) window -- roughly 90% real speed, 10%
flash. The dashboard's own firmware watches its displayed speed for
sustained overspeed and raises its own native warning/lockout when it
sees one; periodically resetting what it sees down to 1 km/h prevents
that native warning from ever triggering, even though the rider is
actually over the limit. Toggle off (the default) means the real speed
always shows, so the dashboard's native warning behaves as it normally
would.

Two details that look like bugs but aren't:

- **Polarity is intentionally inverted** from the reference's own flag --
  there, *disabling* native speed display turns the flash on; here,
  *enabling* `bypass-speed-limit-warning` turns the flash on, by explicit
  request. Don't "fix" this to match the reference's polarity.
- **Deliberately stateless** -- the flash phase is derived fresh every
  call from `(mod (systime) period)`, not tracked across calls via
  separate "when did this start" timestamps. An earlier version tracked
  it statefully, looked correct on paper, but got stuck flashing
  permanently on real hardware (root cause never confirmed). The
  stateless version can't get stuck the same way since every call
  recomputes the answer from scratch.

Only 0x211's speed field gets this treatment -- 0x212's speed field is
left on the real value, matching the reference's own scope.

## QML settings channel

`send-data`/`event-data-rx` on the script side, `sendCustomAppData`/
`onCustomAppDataReceived` on the `main-settings.qml` side -- not VESC
Tool's native custom-config system (`VescIf.customConfig()`), which only
exists for compiled C packages, not pure LispBM ones.

Byte protocol:

| Byte | Meaning |
|---|---|
| 0 | command: `0x01` = get, `0x02` = set |
| 1 | `disable-prof-sw` (0/1) |
| 2 | `freeze-batt-below-11` (0/1) |
| 3 | `bms-mode` (0 = Use VESC BMS, 1 = Use Ninebot BMS/JBD2X3Bridge) |
| 4 | `bypass-speed-limit-warning` (0/1) |
| 5 | `underglow-on-park` (0/1) |
| 6 | `enable-charge-light` (0/1) |

A "set" reply echoes the same layout (byte 0 = `0x01`) to confirm the
write. `apply-settings-from-qml` checks `buflen` before reading bytes
4-6, guarding against a stale/shorter payload from an older
`main-settings.qml`.

Live telemetry (speed, motor temp, voltage, current, light state, active
drive-mode byte) is pushed to the QML side periodically over the same
channel, tagged with byte 0 = `0x03` to distinguish it from the settings
get/set replies above.

## main-settings.qml notes

`profileSpeedLimitKmh`: there's no fixed Eco/Drive/Sport byte enum --
each profile's cap is user-configurable in the companion app, and the
dashboard just sends whatever km/h value is currently active (confirmed
live on real G3 hardware: `0x22` -> 17 km/h, `0x2a` -> 21 km/h, both fit
`byte / 2`). Same formula `main.lisp`'s `handle-drive-mode` uses.

`sendCustomAppData`/`onCustomAppDataReceived` need an `ArrayBuffer` built
via `DataView`, not a plain JS array -- confirmed from VESC Tool's own
official examples (`res/qml/Examples/BalanceUi.qml`, `Mp3Stream.qml`), not
guessed. An earlier version of this file sent a plain array literal
(`[cmd, ...]`), which silently did nothing on real hardware (stuck on
"Loading...", nothing ever saved) -- QML's JS array doesn't implicitly
marshal to the `QByteArray` the C++ side expects, and even the *reply*
comes back as an `ArrayBuffer`, not something bracket-indexable directly.

Per-setting notes not already covered by the byte protocol table above:

- **Freeze Battery Percentage under 11%** -- lets the rider bypass
  whatever the dashboard itself does at low battery (e.g. a walk-mode
  lockout) without touching the real battery reading anywhere else.
  Requires the master VESC's registration message to actually be running
  to have real data to floor in the first place.
- **Underglow on park** -- ported from the reference firmware's
  `underglowOnPark`, simplified to the plain on/off case (the reference
  also weaves this into indicator blink states via a physical
  quick-action button this project doesn't wire up).
- **Enable charge light** -- on by default, matching this project's
  original always-on behavior before the toggle existed.
- `vesc-can-id`/`motor-poles`/`wheel-diam-mm` are intentionally NOT
  settings on this page -- `main.lisp` learns them live from the master
  VESC's registration message, since that VESC already has the real
  values locally.
- LED strip (WLED/WS2812) support from the reference firmware is NOT
  included -- stock VESC Express's LispBM has no extension for driving
  addressable LEDs (needs a hardware RMT peripheral, only exposed via a
  custom C extension, out of scope for a pure-LispBM package).
