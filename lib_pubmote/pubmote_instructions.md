# Pubmote Library Usage Instructions

The Pubmote receiver library is designed to be imported and used as a standalone library by other VESC Lisp packages. It supports remotes connected over ESP-NOW or BLE.

For a complete real-world integration, see the `float_accessories` VESC package (`float_accessories.lisp`, `lib/utils.lisp` event handler, `lib/commands.lisp` data-rx dispatch, and `ui.qml` pairing UI).

The library is split across four files, which must be loaded in this order (later files depend on definitions from earlier ones):

| File | Contents |
|------|----------|
| `pubmote-consts.lisp` | Protocol command IDs, pairing states, vehicle types, `PUBMOTE_MAGIC` |
| `pubmote-vars.lisp` | Runtime state variables and callback slots |
| `pubmote-utils.lisp` | Helpers: config access, telemetry serialization, wifi channel locking, packet send |
| `pubmote.lisp` | Public API: `setup-pubmote`, `pubmote-loop`, `pair-pubmote`, RX handlers |

## Integration Steps

1. **Import and load all four library files** in your host script, in order:
   ```lisp
   (import "lib/pubmote-consts.lisp" 'pubmote-consts)
   (import "lib/pubmote-vars.lisp" 'pubmote-vars)
   (import "lib/pubmote-utils.lisp" 'pubmote-utils)
   (import "lib/pubmote.lisp" 'pubmote)

   (read-eval-program pubmote-consts)
   (read-eval-program pubmote-vars)
   (read-eval-program pubmote-utils)
   (read-eval-program pubmote)
   ```

2. **Initialize callbacks and vehicle mode** using `setup-pubmote`:
   ```lisp
   (setup-pubmote
       vehicle-type     ; Vehicle type constant (e.g., VEHICLE_TYPE_ONEWHEEL)
       on-control-cb    ; Callback: (fn (jsy jsx bt-c bt-z is-rev) { ... })
       get-telemetry-cb ; Callback returning the telemetry list (see format below)
       send-msg-cb      ; Callback for logging: (fn (text) { ... })
       get-config-cb    ; Callback to get config value: (fn (name) { ... })
       set-config-cb    ; Callback to set config value: (fn (name val) { ... })
       save-config-cb   ; Callback to persist config to eeprom: (fn () { ... })
   )
   ```

3. **Register the receive handlers.** The library defines `pubmote-rx` (ESP-NOW) and `pubmote-ble-rx` (BLE / custom app data), but the host script owns event registration:
   ```lisp
   (defun event-handler ()
       (loopwhile t
           (recv
               ((event-esp-now-rx (? src) (? des) (? data) (? rssi)) (pubmote-rx src des data rssi))
               ((event-data-rx . (? data)) (pubmote-ble-rx data))
               (_ nil)
   )))

   (event-register-handler (spawn event-handler))
   (event-enable 'event-esp-now-rx)
   (event-enable 'event-data-rx)
   ```
   Notes:
   - If your package also receives its own QML/app commands over `event-data-rx`, dispatch on the first byte: Pubmote packets always start with `PUBMOTE_MAGIC` (169). See `command-rx` in float_accessories' `lib/commands.lisp`.
   - Consider wrapping each handler call in `trap` and monitoring the event thread for restarts, so a malformed packet can never kill event handling (see `dispatch-trapped` / `spawn-event-handler-with-restart` in float_accessories).

4. **Spawn the background loop** thread:
   ```lisp
   (setq pubmote-context-id (spawn pubmote-loop))
   ```

## Required Config Keys

The `get-config-cb` / `set-config-cb` / `save-config-cb` callbacks must back the following keys (persisted by the host package, e.g. in eeprom):

- `pubmote-enabled` — master enable; when false the loop idles and RX packets are ignored (default 0)
- `pubmote-remote-mac-a` — first 4 bytes of the paired remote's MAC, packed as i32 (default `-1` = unpaired, `0` = BLE-paired placeholder)
- `pubmote-remote-mac-b` — last 2 bytes of the paired MAC, packed as i32 (default `-1`)
- `pubmote-secret-code` — i32 shared secret established during pairing; validated on every packet (default `-1`)
- `pubmote-loop-delay` — loop rate in Hz (default 20; values below 1 fall back to 20)

`save-config-cb` only needs to persist the pairing-related keys (`pubmote-remote-mac-a`, `pubmote-remote-mac-b`, `pubmote-secret-code`) — those are the only values the library changes.

## Pairing

Drive pairing from your app/QML layer via `pair-pubmote` (e.g. float_accessories' `ui.qml` sends `(pair-pubmote N)` as eval'd code):

- `(pair-pubmote code)` with `code >= 0` — start pairing, using `code` as the new secret code. The library broadcasts pairing packets over ESP-NOW and responds to BLE pairing requests.
- `(pair-pubmote -1)` — accept: persists the remote's MAC and secret code, then re-initializes.
- `(pair-pubmote -2)` — reject/cancel: clears the stored MAC.

Pairing times out automatically after 60 seconds. State changes are reported to the connected app via `send-data` as `"pairing-status N"` (`0` idle, `1` initiated, `2` bonding).

A remote paired over BLE is stored with the all-zeros placeholder MAC (`pubmote-remote-mac-a` = 0); telemetry is then pushed over the BLE connection instead of ESP-NOW. If WiFi is disabled on the Express (`wifi-mode` 0), the library runs in BLE-only mode and skips all ESP-NOW setup.

## Telemetry Format

`get-telemetry-cb` must return a 15-element list, in order:

```
fault-code, pitch-angle, roll-angle, state, switch-state, input-voltage,
rpm, speed, total-current, duty-cycle, distance-abs, fet-temp, motor-temp,
odometer, battery-percent (0.0 - 1.0)
```

## Supported Vehicle Types

Vehicle types are defined as constants in `pubmote-consts.lisp`; pass one directly to `setup-pubmote`:
- `VEHICLE_TYPE_UNSPECIFIED` (0)
- `VEHICLE_TYPE_ONEWHEEL` (1)
- `VEHICLE_TYPE_ESKATE` (2)
- `VEHICLE_TYPE_SCOOTER` (3)
- `VEHICLE_TYPE_EUC` (4)

## WiFi Channel Locking

When the Express is in station mode but not connected to WiFi, incoming remote traffic locks the current WiFi channel (disables auto-reconnect) so ESP-NOW stays on a stable channel. The lock is released automatically after 10 seconds of remote inactivity, allowing normal WiFi reconnection to resume. No host integration is required, but be aware WiFi reconnection is deferred while a remote is active.
