# Boosted Doctor (Boosted VESC Bridge)

A VESC package for using Boosted Board (and Rev Scooter) batteries with VESC controllers or VESC Express modules.

## Overview

Boosted Doctor implements the CAN commands and response parsing for Boosted's proprietary battery protocol, including the periodic battery ping required to keep the battery powered on beyond 10 minutes.

## Features

- Compatible with Boosted XR and Rev Scooter battery packs
- Implements Boosted CAN communication protocol (commands + parsing)
- Sends periodic battery ping to prevent auto-shutdown
- View individual cell voltages in VESC Tool
- Clear Red Light of Death (RLOD) directly from VESC Tool

## Settings

The package registers a custom config, so its settings appear in VESC Tool
under the usual parameter editor rather than in the package UI.

| Setting | Default | Effect |
| --- | --- | --- |
| Publish as VESC BMS | **off** | Report the pack as a VESC BMS — pack voltage, current, state of charge and cell voltages — published locally and broadcast on CAN so a separate motor controller can see them. |

It is off by default because enabling it puts BMS frames on the CAN bus,
which should not fight an existing BMS. **Turn it on if you want the pack to
appear as the VESC's battery** — that is the usual setup where a VESC Express
bridges a Boosted pack to a motor controller.

Leaving it off changes nothing else: the keep-alive ping, the cell report,
RLOD recovery and the Boosted Doctor page all keep working. The setting is
read on every publish cycle, so it takes effect within 200 ms of writing it —
no reboot. Values already sent to the VESC are left alone and age out on
their own.

Settings are stored in the firmware's eeprom vars from index 0 and survive a
reboot. The generated deserializer checks a signature derived from
`conf/settings.xml`, so a stored config from an older parameter layout is
rejected and the defaults are used instead.

## Implementation

The protocol runs as a native C library (`boosted/code.c`): CAN transmit and
receive, the keep-alive ping, reassembly and parsing of the AFE's ASCII cell
report, and the custom-app-data replies the UI reads. `code.lbm` is a thin
shim that loads the library and republishes its decoded values through
`set-bms-val`, which has no C-interface equivalent.

A native library only runs on the chip it was built for, so the package ships
one binary per target and picks between them at load time. VESC Express
selection uses `(sysinfo 'hw-target)` and needs firmware new enough to report
it; on older firmware the package prints a message and does nothing.

| Target | Binary |
| --- | --- |
| VESC Express (ESP32-C3) | `boosted/boosted_esp32c3.bin` |
| VESC Express (ESP32-C6) | `boosted/boosted_esp32c6.bin` |
| VESC Express (ESP32-S3) | `boosted/boosted_esp32s3.bin` |
| VESC Express (ESP32-P4) | `boosted/boosted_esp32p4.bin` |
| VESC motor controller (STM32F4) | `boosted/boosted_stm32.bin` |

## Building

`make` generates the config sources, builds every binary and then the
package, so it needs `vesc_tool` plus the ESP32 RISC-V, ESP32-S3 Xtensa and
`arm-none-eabi` toolchains on `PATH`. The RISC-V targets also need RVfplib
checked out under `c_libs/express/RVfplib`:

```
git submodule update --init c_libs/express/RVfplib
```

`boosted/conf/confparser.*`, `confxml.*` and `conf_default.h` are generated
from `boosted/conf/settings.xml` by `vesc_tool --xmlConfToCode` and are not in
git. `make conf` regenerates them on their own. When adding a parameter, edit
`settings.xml` and `boosted/conf/datatypes.h` together — nothing checks that
they agree, and a mismatch silently corrupts every field after it.

To work on a single target while developing:

```
make conf
make -C boosted ARCH=esp32 ESP_TARGET=esp32c3
make -C boosted ARCH=stm32
```

Objects are not target-suffixed, so run `make -C boosted ... clean` when
switching targets.

## Credits & Acknowledgements

**Robert Scullin** - Boosted CANBUS Research
[beambreak.org](https://beambreak.org) - [GitHub](https://github.com/rscullin/beambreak)

**Alex Krysl** - Boosted CANBUS Research
[GitHub](https://github.com/axkrysl47/BoostedBreak)

**Simon Wilson** - VESC Express Implementation
[GitHub](https://github.com/techfoundrynz)

**David Wang** - Boosted CANBUS Research
[XR General Hospital](https://www.xrgeneralhospital.com/)