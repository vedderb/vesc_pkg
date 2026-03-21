<p align="left">
  <a href="https://unleashedcreativity.com.au/index.php/product/led-vescexpress/">
    <img src="https://i0.wp.com/unleashedcreativity.com.au/wp-content/uploads/2024/06/cropped-UC-Logo-no-background.png" width="50" alt="Unleashed Creativity">
  </a>
</p>

# Unleashed Creativity Lights Package

A VESC Express package for ESP32-C3 lighting accessories over CAN bus, integrated with the Refloat package.

Looking for VESC Express controllers and accessories:
[Unleashed Creativity VESC Controller Range](https://unleashedcreativity.com.au/index.php/product-category/vesc/)

## Major Features
- New Refloat RT API integration.
- Lighting control now from Refloat.
- Master-only Refloat discovery and polling, with forwarded state for peers/slaves.
- Two-role node model only: `Master` and `Slave` (default is Slave).
- Master is the sole source of configuration.
- Slave stores pushed configuration with CRC-checked persistence.
- Targeted LED outputs using `SELF (-1)` or peer CAN-ID for daisy-chain layouts.
- Slave diagnostics tab with per-output details for node-targeted channels.
- Runtime config refresh improvements for UI (`Read Config` and status-driven target updates).
- Reduced CAN chatter defaults for better app link stability.
- Advanced lighting behavior and patterns:
  - Status states
  - Run/reverse white-red behavior
  - Battery meter pattern
  - Cylon pattern
  - Rainbow pattern
  - Brake and highbeam support
- Optimized for minimal CAN traffic during normal operation.

## What's Changed Since 2026.03
- Removed Terms of Service flow and related protocol hooks.
- Removed startup mode and startup timeout controls; non-running behavior now defaults to idle mode.
- Compressed UI settings payload to used parameters only.
- Updated CAN timing defaults:
  - `refloat-poll-interval` -> `0.75`
  - `ucl-peer-poke-interval` -> `2.0`
  - `ucl-announce-interval` -> `3.0`
  - `refloat-quiet-grace` -> `15.0`
  - `ucl-fwd-source-freshness` -> `2.0`
- Forwarded lights replay tied to CAN loop frequency.
- Improved LED loop restart handling on `Save Config` to prevent duplicate loop overlays.

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
