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

`make` builds every binary and then the package, so it needs the ESP32
RISC-V, ESP32-S3 Xtensa and `arm-none-eabi` toolchains on `PATH`. The
RISC-V targets also need RVfplib checked out under `c_libs/express/RVfplib`.
To work on a single target while developing:

```
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