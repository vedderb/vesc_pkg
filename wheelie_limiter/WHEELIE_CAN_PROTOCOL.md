# 3ShulMotors Wheelie Assist — CAN Protocol v1

This document is the complete spec for talking to the **Wheelie Assist** controller
(a LispBM script running on a 3ShulMotors / VESC-based motor controller) from a display.
Hand this whole file to the display firmware developer; nothing else is needed.

---

## 1. Transport

| Property        | Value |
|-----------------|-------|
| Bus             | CAN 2.0A, **standard 11-bit identifiers** |
| Bitrate         | Match the controller's CAN bus — **500 kbit/s** by default |
| Frame length    | Always **8 data bytes** (DLC = 8) for every frame, both directions |
| Byte order      | **Big-endian** for all multi-byte fields (MSB first) |
| Frame marker    | **Byte 0 of every frame is `0x57`** ('W'). Ignore frames whose byte 0 ≠ 0x57 |

> The controller's own VESC protocol uses **extended (29-bit)** IDs, so these
> standard 11-bit IDs never collide with it.

---

## 2. Addressing

Each frame ID embeds the controller's VESC CAN ID (`canid`, 0–63, default **0**):

| Direction               | CAN ID            | Default (canid 0) |
|-------------------------|-------------------|-------------------|
| Display → Controller    | `0x500 + canid`   | **0x500**         |
| Controller → Display    | `0x540 + canid`   | **0x540**         |

If you only have one controller, use **0x500** (send) and **0x540** (receive).
For a non-default controller ID, add it to the base.

---

## 3. Register map

All tunable parameters are addressed by a register index `0..5`. Every register
is an **f32**:

| Reg | Name          | Type | Unit   | Typical range | Notes |
|-----|---------------|------|--------|---------------|-------|
| 0   | start         | f32  | deg    | 0 … 60        | Throttle fade begins at this pitch |
| 1   | end           | f32  | deg    | 10 … 75       | Balance ceiling / hard cap |
| 2   | damp          | f32  | —      | 0 … 0.1       | Pitch-rate damping |
| 3   | pull_max      | f32  | 0…1    | 0 … 1.0       | Max reverse (pull-down) current |
| 4   | rate_lpf      | f32  | 0…1    | 0.02 … 1.0    | Gyro low-pass alpha |
| 5   | pitch_sign    | f32  | ±1     | -1.0 / +1.0   | Flip if IMU mounted reversed |

Arm / disarm is **not** a register — use the ARM command (0x05).

---

## 4. Display → Controller (commands)

Sent to ID `0x500 + canid`. Byte 0 = `0x57`, byte 1 = command. Unused bytes = 0.

### 0x01 — READ_ALL
| Byte | 0    | 1    | 2–7 |
|------|------|------|-----|
| Val  | 0x57 | 0x01 | 0   |

Controller replies with **6 CONFIG frames** (one per register, reg 0→5).

### 0x02 — READ_REG
| Byte | 0    | 1    | 2   | 3–7 |
|------|------|------|-----|-----|
| Val  | 0x57 | 0x02 | reg | 0   |

Controller replies with **one CONFIG frame** for `reg`.

### 0x03 — WRITE_REG
| Byte | 0    | 1    | 2   | 3    | 4–7         |
|------|------|------|-----|------|-------------|
| Val  | 0x57 | 0x03 | reg | type | value (BE)  |

- `type`: always 0 (all registers are f32); sent for forward-compatibility.
- `value`: 4-byte big-endian f32.
- Applies **immediately** to the running controller (live), but is **not persisted**
  until a SAVE. Controller echoes back a **CONFIG frame** for that reg as confirmation.

### 0x04 — SAVE
| Byte | 0    | 1    | 2–7 |
|------|------|------|-----|
| Val  | 0x57 | 0x04 | 0   |

Persists the current values to EEPROM (survives reboot). Controller replies with an **ACK frame**.

### 0x05 — ARM
| Byte | 0    | 1    | 2    | 3–7 |
|------|------|------|------|-----|
| Val  | 0x57 | 0x05 | mode | 0   |

`mode`: 0 = disarm, 1 = arm, 2 = toggle. New state appears in the next TELEMETRY frame.

### 0x06 — SUB (telemetry rate)
| Byte | 0    | 1    | 2    | 3–7 |
|------|------|------|------|-----|
| Val  | 0x57 | 0x06 | rate | 0   |

`rate`: telemetry period in units of 100 ms. `0` = off, `1` = 10 Hz (default),
`5` = 2 Hz, etc. (Telemetry is **on at 10 Hz by default** — you do not have to send this.)

---

## 5. Controller → Display (responses)

Sent to ID `0x540 + canid`. Byte 0 = `0x57`, byte 1 = response type.

### 0x81 — TELEMETRY  (broadcast, default 10 Hz)
| Byte | 0    | 1    | 2–3        | 4–5        | 6     | 7        |
|------|------|------|------------|------------|-------|----------|
| Val  | 0x57 | 0x81 | pitch i16  | rate i16   | flags | out i8   |

- `pitch` = signed i16, **degrees × 10** → `pitch_deg = raw / 10.0`
- `rate`  = signed i16, **deg/s × 10** → `rate_dps  = raw / 10.0`
- `flags` = bitfield: **bit0 = armed**, **bit2 = engaged** (assist is actively
  driving the motor right now). bit1 is reserved (0).
- `out`   = signed i8, **current-rel × 100** → `out = raw / 100.0` (range −1.0 … +1.0;
  negative = pulling the front down, positive = driving)

### 0x82 — CONFIG  (reply to READ_ALL / READ_REG / WRITE_REG)
| Byte | 0    | 1    | 2   | 3    | 4–7        |
|------|------|------|-----|------|------------|
| Val  | 0x57 | 0x82 | reg | type | value (BE) |

- `type`: always 0 (f32)
- `value`: 4-byte big-endian f32.

### 0x83 — ACK  (reply to SAVE)
| Byte | 0    | 1    | 2       | 3      | 4–7 |
|------|------|------|---------|--------|-----|
| Val  | 0x57 | 0x83 | ref_cmd | status | 0   |

- `ref_cmd`: the command being acknowledged (e.g. 0x04 for SAVE)
- `status`: 1 = ok, 0 = fail

---

## 6. Worked examples (canid = 0)

**Read all settings on screen open**
```
TX  0x500 : 57 01 00 00 00 00 00 00          ; READ_ALL
RX  0x540 : 57 82 00 00 42 0C 00 00          ; reg0 start = f32 35.0
RX  0x540 : 57 82 01 00 42 34 00 00          ; reg1 end   = f32 45.0
... (regs 2..5) ...
```

**Set the balance ceiling (reg 1) to 50.0°**
```
TX  0x500 : 57 03 01 00 42 48 00 00          ; WRITE_REG reg1 type=f32 value=50.0
RX  0x540 : 57 82 01 00 42 48 00 00          ; CONFIG echo confirms 50.0
```
*(42 48 00 00 = IEEE-754 big-endian for 50.0)*

**Make changes permanent**
```
TX  0x500 : 57 04 00 00 00 00 00 00          ; SAVE
RX  0x540 : 57 83 04 01 00 00 00 00          ; ACK save ok
```

**Live wheelie angle (arrives automatically at 10 Hz)**
```
RX  0x540 : 57 81 01 5E 00 96 01 2D          ; pitch=35.0°, rate=15.0°/s, armed+? , out=0.45
            pitch  = 0x015E = 350  -> 35.0
            rate   = 0x0096 = 150  -> 15.0
            flags  = 0x01          -> armed=1, engaged=0 (bit1 reserved)
            out    = 0x2D  = 45    -> 0.45
```

---

## 7. Implementation notes

- **Always send/expect DLC = 8.** Pad unused bytes with 0.
- **WRITE is live, SAVE persists.** For a "set and keep" UX: send WRITE_REG, then SAVE.
- The CONFIG echo after a WRITE is your write-confirm; if you don't get it within
  ~200 ms, retransmit.
- Reading is idempotent — poll READ_ALL on screen entry; rely on TELEMETRY thereafter.
- If both a display and VESC Tool are connected, the display's writes take effect
  immediately on the controller, but VESC Tool's on-screen values won't refresh until
  its "Read" button is pressed (the controller doesn't push config to VESC Tool unsolicited).
- Multiple controllers: address each by `0x500 + canid` / `0x540 + canid`.
- To move the protocol off 0x500/0x540 (bus conflict), change `whl-sid-cmd` /
  `whl-sid-rsp` in `wheelie_limiter.lisp` and this document together.

---
*3ShulMotors Wheelie Assist — CAN protocol v1*
