# slcan Adapter

Turns a VESC Express based device, for example the **Nanolog**, into a
serial-line CAN adapter. The device speaks the Lawicel / slcan ASCII
protocol on a UART, so with a USB-serial adapter it shows up on Linux as
an ordinary SocketCAN interface (`can0`) usable with, for example `candump` and
`cansend`

## Wiring

| Device pin | USB-serial adapter |
|---|---|
| GPIO 21 (TX) | RX |
| GPIO 20 (RX) | TX |
| GND | GND |

The UART runs at **921600 baud**, 8N1. Pins, UART number and baudrate
can be changed at the top of `slcan.lisp`. At the top of slcan.lisp you can
also change the `use-vesc-decoder` to nil if you do not want the
VESC device used as a slcan-adapter to also be reachable as a normal
VESC via CAN.

## Linux setup

Connect the USB-serial adapter to a USB port and check with DMESG how it
the adapter gets added to the /dev tree, for example as ttyUSB0.

```
sudo slcand -o -c -s6 -S 921600 /dev/ttyUSB0 can0
sudo ip link set up can0
```

`-s` selects the CAN bitrate of the VESC device:

| -s | Bitrate    |
|--- |---         |
| 0  | 10 kbit/s  |
| 1  | 20 kbit/s  |
| 2  | 50 kbit/s  |
| 3  | 100 kbit/s |
| 4  | 125 kbit/s |
| 5  | 250 kbit/s |
| 6  | 500 kbit/s |
| 8  | 1 Mbit/s   |

800 kbit/s (`-s7`) is not supported by the device. Selecting a bitrate
changes the running CAN configuration of the device, it is not stored.

## Example

To set up this example you need two vesc devices, for example Nanologs,
and a linux pc. One of the Nanolog boards will be used as a slcan-adapter
and the other Nanolog will connect to the slcan-adapter over CAN.

```
   ________             ________              ________             _______
  | Nanolog|           | Nanolog|            |   USB  |           |       |
  |        | --- CAN---| slcan  | --- UART---|  serial| --- USB---|  PC   |
  |        |           | adapter|            | adapter|           |       |
  |--------|           |--------|            |--------|           |-------|
      A                     B          
```

Start candump on the linux machine connected to the USB-serial adapter:

```
candump can0
```

Nanolog B should run the slcan-adapter package.

Then on Nanolog A you can run for example this program:

```
(defun counter-loop (n)
    (progn
        (can-send-sid 0x100 (list (bitwise-and (shr n 8) 0xFF) (bitwise-and n 0xFF)))
        (sleep 0.1)
        (counter-loop (+ n 1))
        )
)

(spawn counter-loop 0)
```

If you run this program the linux pc running `candump` should show a sequence
of CAN messages counting upwards.

```
  can0       100   [2]  25 3C
  can0       100   [2]  25 3D
  can0       100   [2]  25 3E
  can0       100   [2]  25 3F
  can0       100   [2]  25 40
  can0       100   [2]  25 41
  can0       100   [2]  25 42
  can0       100   [2]  25 43
  can0       100   [2]  25 44
  can0       100   [2]  25 45
  can0       100   [2]  25 46
  can0       100   [2]  25 47
  can0       100   [2]  25 48
  can0       100   [2]  25 49
  can0       100   [2]  25 4A
  can0       100   [2]  25 4B
  can0       100   [2]  25 4C
```