# MQTTCAN4VESC

Turns a **VESC Express** into a CAN → MQTT telemetry bridge, configurable from
this panel — no Lisp scripting needed.

The Express listens to the motor controller's CAN status messages (statuses
1–6), decodes them into engineering units, and publishes them over WiFi to an
MQTT broker, either as one JSON document or as one topic per signal. It is
read-only with respect to the vehicle: it never commands the controller.

Published every interval, whatever the controller has enabled (undecoded fields
carry `0`): `erpm`, `current_motor`, `motor_speed`, `motor_torque`, `duty`,
`amp_hours`, `amp_hours_charged`, `watt_hours`, `watt_hours_charged`,
`temp_fet`, `temp_motor`, `current_in`, `pid_pos`, `tachometer`, `v_in`,
`adc1`, `adc2`, `adc3`, `ppm`. Both the raw signals (`erpm`, `current_motor`)
and the values derived from them are sent, so a wrong pole-pair or torque
constant can be corrected downstream instead of re-flashing.

## Before you start: WiFi

WiFi is **not** configured from this panel. Set it once on the device itself:
VESC Tool → **VESC Express** → **WiFi** tab → WiFi Mode = `Station`, then fill
in **Station Mode SSID** and **Station Mode Key**, write the config and reboot.
The firmware connects and reconnects on its own; this package just uses the
link. (The ESP32-C3 is 2.4 GHz only — a 5 GHz network will never connect.)

## Using the panel

Open this package's panel in VESC Tool (connected to the Express over BLE or
USB) and set:

- **MQTT Broker** — host, port, and optional username/password.
- **Publishing** — topic prefix, mode (json / topics / both), publish interval, and MQTT keepalive.
- **Motor** — the controller's VESC ID, the speed divisor (pole pairs) and the torque constant used to convert raw CAN values.

Press **Save & Apply** to store the settings on the device and reconnect (no
reboot needed). **Test Connection** shows the current WiFi/MQTT state,
**Restore Defaults** resets everything, and **Reboot** restarts the device.

The **Status** box updates about once a second: WiFi/MQTT state, live speed,
torque, voltage, temperatures, and a CAN-frame counter so you can tell at a
glance whether CAN data is arriving.

## CAN mode

- **vesc** (default) — decodes status 1–6 and leaves the VESC protocol enabled, so VESC Tool can still reach the controller over CAN. Falls back to `canget-*` polling if no status frames arrive.
- **raw** — same decode, but disables the VESC protocol on CAN.
- **sim** — publishes simulated telemetry with no controller attached, for bench-testing the MQTT chain. Never ship a vehicle in this mode.

## Notes

- Requires VESC Express firmware 6.05+.
- Uses plain (non-TLS) MQTT. Prefer a private broker with a username and password; the credentials and the telemetry both cross the network in the clear.
- Settings are stored in the device's EEPROM and survive reboots and package updates.
