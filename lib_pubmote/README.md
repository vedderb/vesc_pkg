# Pubmote

ESP-NOW / BLE tilt-remote ([Pubmote](https://github.com/audemuro/pubmote)) link for the VESC Express, as a reusable LispBM library. Handles pairing (ESP-NOW and BLE), telemetry push, control input and WiFi-channel locking; everything package-specific is injected through callbacks, so the library has no opinion about where the configuration lives or what the vehicle is.

## Usage

```clj
(import "pkg@://vesc_packages/lib_pubmote/pubmote.vescpkg" 'pubmote)
(read-eval-program pubmote)

(setup-pubmote
    VEHICLE_TYPE_ONEWHEEL
    (fn (jsy jsx bt-c bt-z is-rev) ...)  ; on-control: remote input arrived
    (fn () (list fault pitch roll ...))  ; get-telemetry: 15-entry list, see below
    (fn (text) ...)                      ; send-msg: user-facing message
    (fn (name) ...)                      ; get-cfg
    (fn (name val) ...)                  ; set-cfg
    (fn () ...)                          ; save-cfg: persist the config
    (fn (state) ...)                     ; on-pairing-state: PAIR_STATE_* changed
)
(spawn pubmote-loop)
```

The host owns the event loop and routes packets in:

```clj
(event-enable 'event-esp-now-rx)
(defun event-handler ()
    (loopwhile t
        (recv
            ((event-esp-now-rx (? src) (? des) (? data) (? rssi))
                (pubmote-rx src des data rssi))
            ((event-data-rx . (? data))
                ; BLE transport arrives as custom app data with a magic byte
                (if (and (> (buflen data) 1) (= (bufget-u8 data 0) PUBMOTE_MAGIC))
                    (pubmote-ble-rx data)))
            (_ nil)
)))
```

## Configuration keys

`get-cfg` / `set-cfg` / `save-cfg` persist these keys, whatever the storage is (custom config, eeprom, ...):

| Key | Meaning |
|---|---|
| `pubmote-enabled` | 1 while the link should run |
| `pubmote-loop-delay` | telemetry rate in Hz |
| `pubmote-secret-code` | pairing secret (set by the pairing flow) |
| `pubmote-remote-mac-a` / `-b` | paired remote MAC, packed; -1 = not paired, 0 in `-a` = BLE-paired |

## API

- `(setup-pubmote vehicle-type on-control get-telemetry send-msg get-cfg set-cfg save-cfg on-pairing-state)` - inject the host callbacks. Vehicle types: `VEHICLE_TYPE_UNSPECIFIED/ONEWHEEL/ESKATE/SCOOTER/EUC`.
- `(pubmote-loop)` - the link loop; spawn it in a thread. Set `pubmote-exit-flag` to make it exit.
- `(pubmote-rx src des data rssi)` - feed ESP-NOW packets in.
- `(pubmote-ble-rx data)` - feed BLE (custom app data) packets in.
- `(pair-pubmote code)` - drive pairing: `code >= 0` starts pairing with that secret, `-1` accepts the bond, `-2` rejects/aborts. `on-pairing-state` reports `PAIR_STATE_IDLE/INITIATED/BONDING`.
- `(pubmote-connected)` - 1 while packets from the paired remote arrived within the last second.
- `pubmote-version` - remote firmware version as `(major minor patch)`, once received.

Telemetry list order (15 entries): fault-code, pitch-angle, roll-angle, state, switch-state, vin, rpm, speed, tot-current, duty-cycle-now, distance-abs, fet-temp-filtered, motor-temp-filtered, odometer, battery-percent-remaining (0.0-1.0).

## Notes

- WiFi channel locking: in station mode with no WiFi connection, the channel is locked while remote traffic (or pairing) is active and released after 10 s of silence, so ESP-NOW and WiFi reconnection don't fight over channel hopping.
- With WiFi disabled the library runs in BLE-only mode.
- Used by the Float Accessories package; see its `ui.qml` pairing flow for a full example.
