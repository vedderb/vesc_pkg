# VL Link Status

Bring-up and status package for the **VL Link** board (ESP32-C3 + SIMCom SIM7070G).

## What it does

- **Enables the CAN transceiver.** `hw_init()` for this board is empty, so GPIO 6
  is left in standby at boot. Without a package driving it low, a CAN scan finds
  only the local device and reports no bus errors to explain why. This package
  drives it low on every start.
- **Shows link state on the two onboard LEDs.** One LED per subsystem:

  | LED | Colour | Meaning |
  |---|---|---|
  | 1 (CAN) | rainbow chase | no node on the bus |
  | 1 (CAN) | solid green | node found |
  | 2 (LTE) | blue breathe | modem booting or not responding |
  | 2 (LTE) | solid red | modem up, no SIM |
  | 2 (LTE) | amber breathe | SIM ok, searching for network |
  | 2 (LTE) | **flashing green** | registered on the network |

  Registered flashes rather than sitting solid, so **solid green + flashing
  green** reads at a glance as "both links up". Two solid greens would not.
- **Reports LTE state** — carrier name, modem power, SIM, network attach and a
  5-bar signal meter — in the VESC Tool panel.

  Verified against live hardware on T-Mobile: LTE Cat-M1, band 12, `+CSQ: 31`
  (-51 dBm), network-provided APN `mobilenet`. The SIM7070G is Cat-M1 / NB-IoT
  / GSM only — it has no plain LTE — so a SIM whose carrier has not provisioned
  Cat-M will sit unattached indefinitely with no other symptom.
- **Publishes telemetry to an MQTT broker** over the LTE data connection,
  when enabled. See below.
- **Reports pack voltage** of the first live CAN node. Shown only when a fresh
  status frame 5 has arrived, so a node found by ping alone reads blank rather
  than a misleading 0.0 V.

- **Logs to the SD card** using the firmware's own log subsystem
  (`log-config-field` / `log-start` / `log-send-f32`), so the output is VESC's
  native format in `/sdcard/log_can/` and opens directly in VESC Tool's log
  analysis page. 10 Hz, matching the stock vesc_pkg logger.
- **Exports on mobile.** The Logs tab lists what is on the card, pulls a file
  over the link, and hands it to the log analysis view. Mobile VESC Tool has no
  file browser, so without this there is no way off the device.

## Logging notes

The `can_id` argument to `log-start` decides where log packets go
(`log_comm.c:91`): `0`-`254` sends over CAN to that device, `-1` sends to the
connected VESC Tool, and anything else is processed locally. This package uses
`-2` so the Link writes to its own card.

Fields are built per CAN node from `can-fields`, plus two LTE columns. Only
single-argument `canget-*` getters are used — note there is no `canget-ah` or
`canget-wh`, so amp/watt hours cannot be logged from a remote node.

Logging needs nodes that broadcast status frames. Without them the field list
comes back empty and the getters would only ever return stale zeros, so
`log-begin` refuses to start rather than recording a file full of nothing.

There is no shutdown hook: Express has no `event-shutdown` (it is ESC-only, and
`event-enable` rejects it). Stop logging from the UI before cutting power, or
the tail of the file may be lost.

## Cloud telemetry (MQTT)

Optional, off by default. Brings up a packet data context, connects to a
broker and publishes a JSON object on an interval. Configured in Settings;
persists in EEPROM.

Defaults target ThingsBoard (`mqtt.thingsboard.cloud:1883`, topic
`v1/devices/me/telemetry`, access token in the username field, password
blank), but host, port, credentials, client id and topic are all fields, so
Mosquitto or a Home Assistant broker work the same way.

```json
{"can":1,"rssi":-51,"voltage":84.23,"battery":87,"rpm":-3421,
 "speed_kmh":27.4,"current_in":-12.3,"temp_fet":41.2,"temp_motor":33.8,
 "trip_km":12.346,"trip_wh":456.8,"trip_ah":12.35,
 "moving":1,"guard":1,"lock":-1,"logging":0}
```

Around 220 bytes. Keys are omitted rather than zeroed when the value is not
known -- the motor block disappears with no live CAN node, `voltage` until
a status frame 5 arrives, `battery` unless the controller reported it.
`battery` is the controller's own figure and is not inferred from pack
voltage here, because a voltage curve without a chemistry is worse than no
number.

`AT+SMCONN` is a TCP handshake plus a CONNECT round trip and regularly
takes over ten seconds on Cat-M1, so the session is opened once and held
rather than reopened per sample, and reconnected only when `AT+SMSTATE?`
says it is gone. Publishing is QoS 1. Failed connects back off 5 s -> 300 s
for the same reason `can-scan` does: a wrong token never becomes right.
Expect 15-20 s of "Connecting" after a boot while the modem attaches.

`AT+CNACT` alone will not do -- the context profile has to be configured
first with `AT+CNCFG`, and on a SIM whose carrier does not push an APN that
is the difference between a modem that attaches and one that also passes
traffic. Leave the APN blank to request the network's own.

Plain TCP: the SIM7070G's TLS stack is not reachable through the `SM*`
command set, so use a token scoped to this device alone.

### When it will not connect

The Cloud row separates the failures that look identical from outside --
no data context is an APN or plan problem, a refusal is credentials or the
wrong host. For anything past that, `(def mqtt-log true)` prints every
connect, refusal and inbound UI form with the raw AT reply attached.

One error is worth knowing in advance: a CONNECT the **broker rejected**
comes back as `+CME ERROR: operation not allowed`, which reads like a
session conflict and is usually a bad or revoked token.

```clj
(list mqtt-on modem-rdy net-att mqtt-state mqtt-last (str-len mqtt-user))
```

`mqtt-state` 0 down, 1 context up, 2 connected. `mqtt-last` 0 idle,
1 published, 2 publish failed, 3 refused, 4 no data context.

## SMS control

Optional. When enabled and a number is set, the modem's mailbox is checked
every 30 s and one message handled per pass.

| Command | Reply |
|---|---|
| `STATUS` | pack voltage, CAN state, signal, logging state |
| `LOG ON` | starts logging |
| `LOG OFF` | stops logging |
| `TRIP` | distance, Wh, Ah, max speed |
| `GUARD ON` / `GUARD OFF` | arm or disarm the movement alert |
| `LOCK` / `UNLOCK` | request the ESC lock package; confirmed by ack |
| `CLOUD ON` / `CLOUD OFF` | enable or disable MQTT publishing |
| `PING` | liveness check |

Only approved numbers are obeyed, matched on the last 10 digits so formatting
differences do not matter. Messages are deleted after handling so the mailbox
cannot fill and stall reception.

### Access roster

An unknown number that texts the Link is not silently dropped. It appears in
the **Access** tab as a pending request, and gets one reply telling it the
owner has been notified. You allow or deny from VESC Tool; approved members can
be switched on and off individually without deleting them, which is what makes
lending the vehicle practical.

Five slots. Member 0 is the owner, set in Settings. Pending requests live in
RAM only, so an unapproved number cannot fill EEPROM and does not survive a
restart.

Approving happens over BLE or USB, which means physical proximity and your own
device -- a far better channel to authorise on than an incoming text. Note it
does **not** make SMS trustworthy: an approved member is still identified only
by caller ID, which is forgeable.

**Nothing here can move the vehicle.** Sender numbers are trivially
spoofable and SMS is an unauthenticated public bearer, so the command set
is limited to reporting plus `LOCK`, `GUARD` and `LOG`. Those do change
vehicle state, and `LOCK` in particular is a real actuation -- but they can
only ever remove capability, never grant it. There is no command that
applies throttle, releases a brake or raises a limit.

Requires SMS to be provisioned on the line. A data-only Cat-M plan will
register, attach and pass IP traffic while having no SMS bearer at all --
check `AT+CSCA?` returns a service centre address.

## Trip metering

Distance, watt hours, amp hours and max speed since the vehicle last started
moving, plus Wh/km. Reset from the Status tab or query by SMS with `TRIP`.

Amp and watt hours are **not** available through `canget-*`. They arrive in CAN
status frames 2 and 3, which the firmware decodes internally but never exposes
to lisp, so the package decodes them from the raw frame via `event-can-eid`
(int32 / 1e4, big-endian; extended id is `node_id | packet_type << 8`).

## Movement guard

When armed, the first movement sends one SMS to the owner. It reports, it does
not intervene -- knowing the vehicle is moving is most of the value and none of
the risk.

## Remote lock

`LOCK` / `UNLOCK` by SMS, or from the Status tab. Persists across reboots.

Actuation is a **latch held on the ESC**, not a continuous assertion from
here. The Link sends `(lock)` or `(unlock)` over `can-cmd` and the ESC
package holds `app-disable-output -1`, so the request only has to arrive
once and the Link can then go quiet.

The cost of a latch is that nothing reveals a lost command -- there is no
heartbeat whose absence would show up. So every request is confirmed: the
Link asks, the ESC package calls `(lock-ack 0|1)` back over CAN, and
nothing here reports success until that arrives. Requests are resent until
confirmed, and an ack older than 15 s is treated as unknown rather than
assuming the last state still holds.

It removes drive rather than braking, so it is equivalent to letting off
the throttle.

**This needs a package on the ESC**, providing:

| Call | Does |
|---|---|
| `(lock)` | latch output disabled, persist across reboot |
| `(unlock)` | release, persist |
| `(lock-report id)` | `can-cmd` `"(lock-ack <0|1>)"` back to CAN node `id` |

The same channel carries `(batt-report id)` -> `(batt-ack <0.0-1.0>)`,
which is where the `battery` figure in the telemetry comes from.

## Settings

Stored on the device in EEPROM and reloaded at boot.

| Setting | Default | Notes |
|---|---|---|
| Log rate | 10 Hz | Matches the stock vesc_pkg logger |
| Log LTE columns | on | Adds `lte_rssi` and `lte_att` |
| Start logging automatically | off | Waits up to 60 s for a CAN node first |
| SMS control | off | Needs an owner number set |
| Owner number | unset | Member 0; numbers stored as three 5-digit EEPROM chunks |
| Cloud telemetry | off | MQTT publishing |
| Broker / port | thingsboard / 1883 | Plain TCP |
| Username / password | unset | ThingsBoard: access token in username, password blank |
| Client id / topic | `vl-link` / `v1/devices/me/telemetry` | |
| APN | unset | Blank asks the network for one |
| Publish interval | 60 s | Floor of 15 s; the modem cycle is 3 s plus command time |

Strings pack three characters per EEPROM slot -- a fourth byte would
overflow LBM's 28-bit integer before reaching `eeprom-store-i`. Uses 127 of
the 512 slots.

All threads run on a 200 word stack. The JSON builder appends one field at
a time rather than nesting `str-merge`, which would otherwise hold every
intermediate result live at once.

## Requirements

- VESC Express firmware with `HW_NAME "VL Link"`
- For a node to appear on the bus, the remote controller needs
  **App Settings → General → CAN Status Message Mode** enabled. A controller
  straight out of the box does not have this on, and every value will read as a
  stale zero without it.
- A SIM is only needed for the LTE row. Everything else works without one.

## Notes

- The LEDs need both the power rail (GPIO 7) and data (GPIO 8). Powering the rail
  alone leaves them dark, which looks like a hardware fault.
- The modem PWRKEY is a **toggle**, not an on switch. The package reads the status
  pin before pulsing so it never turns a running modem off.
- A fresh SIM7070G reports `+IPR: 0` (autobaud) and only locks a rate once it sees
  valid `AT` traffic. The package sends `AT` repeatedly before deciding the modem
  is absent, then pins the rate with `AT+IPR`.
- `can-scan` pings all 254 ids and can take ~2.5 s on an empty bus, so it runs in
  its own thread and is backed off. The LED animation is never blocked by it.

## License

GPLv3. See LICENSE.
