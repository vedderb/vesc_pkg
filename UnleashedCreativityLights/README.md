# Unleashed Creativity Lights Package

A VESC Express package for ESP32-C3 lighting accessories over CAN bus, integrated with the Refloat package.

## Major Features
- New Refloat RT API integration.
- Lighting control now from Refloat.
- Master-only Refloat discovery and polling, with forwarded state for peers/slaves.
- Two-role node model only: `Master` and `Slave` (default is Slave).
- Master is the sole source of configuration.
- Slave stores pushed configuration with CRC-checked persistence.
- Targeted LED outputs using `SELF (-1)` or peer CAN-ID for daisy-chain layouts.
- Advanced lighting behavior and patterns:
  - Status and startup states
  - Run/reverse white-red behavior
  - Battery meter pattern
  - Cylon pattern
  - Rainbow pattern
  - Brake and highbeam support
- Optimized for minimal CAN traffic during normal operation.

## Acknowledgements
Thanks to the original Float Accessories codebase by Relys:

- https://github.com/Relys/vesc_pkg/tree/float-accessories

## Build
Run:

```bash
make
```

If needed, override `vesc_tool` path:

```bash
make VESC_TOOL=/path/to/vesc_tool
```

The package target is built from:

- `UCLights.lisp`
- `ui.qml`
- `README.md`

Output package:

- `UCLights.vescpkg`
