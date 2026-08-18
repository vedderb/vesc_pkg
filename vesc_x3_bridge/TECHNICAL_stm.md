# Technical notes

## If you changed VESC Express's controller id

The script assumes VESC Express is reachable at controller id **2**
(`vesc_express`'s own default). If you changed it in VESC Tool, edit
`express-can-id` at the top of `code_stm.lisp` to match.

## Wire protocol

This VESC registers with Express roughly once a second over
`canmsg-send`, an 8-byte payload: byte 0 own CAN id, byte 1 motor poles,
bytes 2-3 wheel diameter in mm (little-endian u16), byte 4 battery %,
bytes 5-6 voltage x10 (little-endian u16), byte 7 motor temperature.

Express relays the active speed-limit profile back the same way, as a
2-byte little-endian speed x10 km/h value.

## Slave variant (code_stm_slave.lisp)

Registers with a 1-byte payload (own CAN id only) instead of the 8-byte
telemetry frame above -- Express doesn't track a slave's motor config or
battery, it just adds the id to `relay-targets` so it receives the same
speed-limit relay the master does. Throttle/brake/cruise current reaches
the slave through VESC's own Multi ESC over CAN feature (enabled on the
master in VESC Tool, not scripted), which forwards to any VESC it's
recently seen a CAN status message from -- not through anything this
package sends.
