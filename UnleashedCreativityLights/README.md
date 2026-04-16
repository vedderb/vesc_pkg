<p align="left">
  <a href="https://unleashedcreativity.com.au/index.php/product/led-vescexpress/">
    <img src="https://i0.wp.com/unleashedcreativity.com.au/wp-content/uploads/2024/06/cropped-UC-Logo-no-background.png" width="50" alt="Unleashed Creativity">
  </a>
</p>

# Unleashed Creativity Lights Package

A package for ESP32-C3 lighting hardware running VESC(R) software over CAN bus, integrated with the Refloat package.

Looking for Unleashed Creativity hardware for use with VESC(R) software:
[Unleashed Creativity hardware range](https://unleashedcreativity.com.au/index.php/product-category/vesc/)

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

## What's Changed Since 2026.041
- Release `V2026.042`.
- Retains the target CAN-ID selector stability fix while edits are pending `Save Config`.
- Retains the diagnostics status line that makes unsaved target CAN-ID edits obvious to the user.

## Acknowledgements
Thanks to the original Float Accessories codebase by Relys:

- https://github.com/Relys/vesc_pkg/tree/float-accessories

## Trademark Notice
VESC is a registered trademark of Benjamin Vedder.
Unleashed Creativity hardware is sold for use with VESC(R) software and VESC Tool. No affiliation with or endorsement by Benjamin Vedder or the VESC Project is claimed.

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
