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

## Credits & Acknowledgements

**Robert Scullin** - Boosted CANBUS Research
[beambreak.org](https://beambreak.org) - [GitHub](https://github.com/rscullin/beambreak)

**Alex Krysl** - Boosted CANBUS Research
[GitHub](https://github.com/axkrysl47/BoostedBreak)

**Simon Wilson** - VESC Express Implementation
[GitHub](https://github.com/techfoundrynz)

**David Wang** - Boosted CANBUS Research
[XR General Hospital](https://www.xrgeneralhospital.com/)