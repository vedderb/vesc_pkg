# Technical notes

## If you changed VESC Express's controller id

The script assumes VESC Express is reachable at controller id **2**
(`vesc_express`'s own default). If you changed it in VESC Tool, edit
`express-can-id` at the top of `vesc-side-master.lisp` to match.

## Wire protocol

This VESC registers with Express roughly once a second over
`canmsg-send`, an 8-byte payload: byte 0 own CAN id, byte 1 motor poles,
bytes 2-3 wheel diameter in mm (little-endian u16), byte 4 battery %,
bytes 5-6 voltage x10 (little-endian u16), byte 7 motor temperature.

Express relays the active speed-limit profile back the same way, as a
2-byte little-endian speed x10 km/h value.
