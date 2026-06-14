# BlackTip DPV Development Documentation

## lispBM Runtime Architecture Overview

The BlackTip DPV lispBM runtime is organized as a set of cooperative threads and event-driven state machines, designed for reliability and clarity on resource-constrained VESC hardware. Key architectural components:

* **State Machine:**
  * Manages button presses, clicks, long holds, and transitions between operational states (off, running, Smart Cruise, etc.).
  * Implements logic for Smart Cruise activation, speed changes, and safety features.
* **Display Update Loop:**
  * Periodically updates the OLED display with speed, battery, Smart Cruise status, error codes, and timer bar.
  * Uses a lookup table for LED timer bar mapping (left-to-right countdown).
    * Loads display frames from a binary file generated from a CSV asset.
* **Smart Cruise Logic:**
  * Allows hands-free operation with configurable timeout and auto-engage.
  * Visual feedback via display and 8-LED timer bar; warning mode triggers slowdown and beep.
  * Speed changes require a long hold before tap, preventing accidental adjustments.
* **Peripheral Loops:**
  * Separate threads for motor control, trigger/button polling, battery monitoring, and Smart Cruise background checks.
  * Each loop uses minimal stack and sleep intervals to conserve memory and CPU.
* **Logging and Debugging:**
  * Conditional debug logging via `debug_log` and `when-debug` macros to minimize memory usage.
    * Debug output can be enabled for troubleshooting in VESC Tool.
* **Configuration and EEPROM:**
  * Settings are stored in EEPROM and loaded at startup; configuration is managed via QML UI in VESC Tool.
  * Battery calculation supports voltage-based or ampere-hour-based methods.

For more details, see the sections below and refer to `blacktip_dpv.lisp` for implementation specifics.

This document contains information for developers working on the BlackTip DPV VESC package.

## VESC 7.00 Compatibility

### Flash / Heap Layout Strategy

VESC firmware 7.00 introduced a persistent flash heap using `@const-start` / `@const-end` blocks that replaces the older `move-to-flash` pattern. The runtime is structured as two const blocks with mutable state defined between them:

```lisp
@const-start       ; Block 1: constants and the debug-logging macro (flashed, immutable)
  (define SLEEP_STATE_MACHINE …)
  …
  (define debug_log_format …)
@const-end

; MUTABLE GLOBAL STATE — heap-resident (NOT flashed), so setvar/set works at runtime.
(define sw_state 0)
…

(import "generated/display_lut.bin" 'display_lut_bin)

@const-start       ; Block 2: all functions (flashed, immutable)
  (defun eeprom_store_i_if_changed …)
  …
@const-end

; Boot sequence: init, then (progn (image-save) (main)) as a single top-level form.
(init)
(progn
    (image-save)
    (main))
```

**Rules that govern this layout:**

**(a) Mutable globals must live outside the const blocks.**
Flashed bindings are immutable. Every variable written at runtime via `setvar` or `set` must be defined on the working heap, between the two const blocks. These heap globals are pre-defined at the top level so their initialisers can reference already-flashed constants.

**(b) Const-block initialisers are evaluated in source order.**
A constant that references an earlier constant (e.g. `SOFT_START_DURATION` referencing `SAFE_START_TIMEOUT`) must come after it in the file. Function bodies have no such ordering constraint; LispBM resolves symbols at call time, not at definition time.

**(c) Hardware init runs on every boot.**
`image-save` does not restore external hardware state. All hardware initialisation (`i2c-start`, `gpio-configure`, oscillator setup) must live in the `init` / `main` call path so it re-executes on each cold boot.

**(d) `import` must be a top-level form, not inside a flashed function.**
When an `import` lives inside a flashed const-block function, the binding action is lost on subsequent boots; the imported symbol resolves to `nil`, causing `bufget-u32` type errors at runtime. The `import` for `display_lut.bin` is therefore placed as a top-level form between the two const blocks, where it runs once each time the package source is evaluated.

**(e) `image-save` and `main` must be wrapped in a single `(progn …)` form.**
`image-save` relocates the heap and serialises the environment, which invalidates the reader's source channel. If `image-save` and `main` are separate top-level forms, the reader tries to read `main` from the channel after `image-save` has run and fails with `read_error / ~CHANNEL~`. Wrapping both in one `(progn …)` means the entire form is parsed first, then `image-save` and `main` execute back-to-back with no intervening read.

**(f) On subsequent boots the saved image is loaded and `main` is auto-invoked.**
Only `init` runs from source on the very first boot after a fresh package upload. From the second boot onwards, the saved image is restored and `main` is invoked directly, bypassing the reader entirely.

### VESC 7.00 Known Bugs and Workarounds

#### I2C First-Message Bug

On VESC firmware 7.00, the first `i2c-tx-rx` call issued after `i2c-start` — i.e. the first transaction on a freshly muxed bus, which happens on every cold boot — is silently swallowed and never reaches the I2C device.

**Effect on cold boot:** The HT16K33 display controller's oscillator-enable command (`0x21`) was dropped on every cold boot. The oscillator never started, so the display chip stayed dormant and the screen remained dark. On firmware 6.06 the same single `0x21` was delivered correctly and the panel lit up.

**Workaround:** Send the oscillator-enable command twice. The first write is sacrificial (absorbed by the firmware bug); the second is delivered to the controller.

```lisp
(i2c-tx-rx 0x70 (list 0x21)) ; sacrificial — absorbs the dropped first transaction
(i2c-tx-rx 0x70 (list 0x21)) ; real oscillator-enable, reaches the HT16K33
(i2c-tx-rx 0x70 (list 0x81)) ; display ON, blink off
```

This bug only affects the first transaction on a freshly muxed bus. Subsequent commands on the same bus configuration are delivered normally. The second display controller (`0x71` on CudaX) does not need the doubled command because by the time it is initialised the bus is already exercised by the `0x70` sequence.

## Build System

The project uses GNU Make for building the VESC package:

```text
make              # Build blacktip_dpv.vescpkg
make clean        # Remove generated files
make test         # Run code quality checks and smoke tests
make smoke-tests  # Run unit-style smoke tests only
make binary       # Generate binary LUT files only
```

### Version Management

The build system automatically generates version information for the package:

* **Version source**: Base version (e.g., `1.0.0`) is stored in `README.md` in the line `**Version:** 1.0.0`
* **Version format:**
  * On `main` branch: `<version>-<yyyymmdd>-<git-hash>` (e.g., `1.0.0-20251013-120605-2eacfa2`)
  * On other branches: `<version>-<branch-name>-<git-hash>` (e.g., `1.0.0-feature-xyz-2eacfa2`)
* **Distribution**: During build, `tools/update_version.sh` creates `README.dist.md` with the full version and build timestamp
* **Distribution**: During build, `tools/update_version.sh` creates `ui.dist.qml` with the full version and build timestamp
* **Package**: The `.vescpkg` includes `README.dist.md` and `ui.dist.qml` (referenced in `pkgdesc.qml`) so users see the detailed version info
* **Repository**: The `README.md` in the repository shows only the base version for simplicity
* **Rebuild behavior**: The package is only rebuilt when source files change (`blacktip_dpv.lisp`, `ui.qml`, `pkgdesc.qml`, `README.md`)

To update the version:

1. Edit the version line in `README.md`: `**Version:** 1.1.0`
1. Run `make` - the distribution file will be generated automatically with a new timestamp

**Note**: `README.dist.md` and `ui.dist.qml` are generated during build and should not be committed to git.

### Test Suite

The project includes smoke tests for pure functions to catch regressions before flashing hardware:

```text
make smoke-tests  # Run 30+ unit tests for pure functions
```

**Tested functions:**

* `clamp` - Value clamping (7 tests)
* `validate_boolean` - Boolean validation (5 tests)
* `state_name_for` - State name mapping (6 tests)
* `speed_percentage_at` - Speed percentage lookup (5 tests)
* `calculate_rpm` - RPM calculation (7 tests)

Tests are implemented in Python (`tests/run_tests.py`) to mirror the LispBM implementations and verify correctness without needing hardware.

## Project Structure

    blacktip_dpv/
    ├── assets/                          // Source data files
    │   └── display_lut.csv             // Display frames (124 frames × 4 rotations)
    ├── tools/                           // Build and development tools
    │   ├── generate_lut_binary.py      // Generates binary files from CSV
    │   └── preview_display.py          // ASCII/PGM visualization tool
    ├── generated/                       // Auto-generated files (not in git)
    │   └── display_lut.bin             // Binary display data (1992 bytes)
    ├── blacktip_dpv.lisp               // Main lispBM runtime source
    ├── ui.qml                           // User interface
    ├── pkgdesc.qml                     // Package descriptor
    └── README.md                        // User-facing documentation

## Display Assets and Tooling

### Asset Files

The OLED screen artwork lives in `assets/display_lut.csv` as a CSV file:

* **`display_lut.csv`** — All display frames (124 rows, one per screen/rotation)

This CSV file is the source of truth. The build system automatically generates the binary display LUT from it.

### Preview Tool

Visualize and verify display artwork before building:

```text
// List all available screens
python tools/preview_display.py --list
// Preview a specific frame by index
python tools/preview_display.py --index 0
// Preview by name and rotation
python tools/preview_display.py --name "Display Battery 4 Bars" --rotation 0
// Show all screens for a given rotation
python tools/preview_display.py --show-all-rotation 0
// Export as PGM image
python tools/preview_display.py --index 0 --output preview.pgm
```

The preview tool applies the correct 90° clockwise rotation and vertical flip to match the physical hardware orientation.

### Binary File Format

The lispBM runtime loads display data from a binary file at runtime using LispBM's `import` statement. This file is automatically generated from the CSV asset during the build process.

**Display LUT** (`generated/display_lut.bin`):

* Header (8 bytes):
  * Magic number: 0x4C555444 ("LUTD" in ASCII)
  * Version: u16 (currently 1)
  * Frame count: u16 (currently 124)
* Frame data: 124 frames × 4 rotations × 16 bytes per frame = 1984 bytes
* Total size: 1992 bytes

## Development Workflow

### Editing Display Artwork

1. Edit `assets/display_lut.csv` (modify existing frames or add new ones)
1. Preview your changes: `python tools/preview_display.py --index N`
1. Build package: `make`

The binary files will be automatically regenerated from the CSV.

### Adding New Displays

1. Add four rows to `display_lut.csv` (one per rotation 0-3). The `index` field must be sequential and unique. Each row has 16 byte fields (`b0` through `b15`) representing the 8×8 pixel matrix as interleaved low/high column bytes.

## Display Orientation

The display hardware is rotated 90° clockwise relative to the natural orientation. The preview tool and lispBM runtime both handle this transformation automatically.

Each display frame consists of:

* 8 columns × 8 rows = 64 pixels
* Stored as 16 bytes (8 column pairs, each pair = low byte + high byte)
* Bit 7 (MSB) = top pixel, Bit 0 (LSB) = bottom pixel in each column

## Code Quality

### Testing

```text
make test  # Runs whitespace checks
```

### Code Style

* Use snake\_case for LispBM variable and function names
* Use 4 spaces for indentation (not tabs)
* No trailing whitespace
* Brace style: 1TBS (One True Brace Style)
* See `.github/instructions/copilot-instructions.md` for full style guide

## Logging Hygiene

The lispBM runtime uses conditional debug logging to minimize memory pressure on the resource-constrained VESC hardware.

### Debug Logging Functions

Two mechanisms are available for debug logging:

**`debug_log` function** - For static strings:

```lisp
(debug_log "Motor: Stopping motor")
```

**`debug_log_format` macro** - For dynamic strings with expensive operations:

```lisp
(debug_log_format (str-merge "Speed: Set to " (to-str clamped_speed)))
```

### When to Use `debug_log_format`

Use the `debug_log_format` macro when logging requires:

* String concatenation (`str-merge`)
* Number-to-string conversion (`to-str`)
* Any other expensive operations

The macro only evaluates these expressions when `debug_enabled` is 1, preventing unnecessary memory allocation and CPU cycles in hot paths.

### Hot Paths Requiring `debug_log_format`

* `set_speed_safe` - Called every speed change (multiple times per second)
* Motor control loop - Runs continuously
* State machine handlers - Active during user interactions
* Click action handlers - Called on every button press

### Example

**Bad** (evaluates `str-merge` even when debug is off):

```lisp
(debug_log (str-merge "Speed: Set to " (to-str speed)))
```

**Good** (only evaluates when debug is enabled):

```lisp
(debug_log_format (str-merge "Speed: Set to " (to-str speed)))
```

## Testing Best Practices

### Adding Tests for Pure Functions

When adding new pure functions (functions without side effects), add corresponding tests to `tests/run_tests.py`:

1. **Identify pure functions** - Functions that always return the same output for the same input, with no side effects (no I/O, no state modification)
2. **Implement Python equivalent** - Create a Python version that mirrors the LispBM logic exactly
3. **Write test cases** - Cover:

* Normal/expected inputs
* Boundary conditions (min, max, zero)
* Edge cases (negative, overflow, empty)
* Error conditions

4. **Run tests before committing**:

```text
make test
```

### What to Test

✅ **Pure functions** - Calculations, validation, state mappings
✅ **Boundary conditions** - Min/max values, thresholds
✅ **Edge cases** - Empty lists, negative values, overflow
❌ **Hardware I/O** - Not feasible without full simulation
❌ **State machines** - Complex runtime behavior, test manually

### Test Structure

Each test function should:

* Have a descriptive name (`test_function_name`)
* Print a section header
* Use `assert_eq` or `assert_near` for validation
* Include descriptive test names explaining what's being tested

Example:

```text
def test_new_function():
    print("\n=== Testing new_function ===")
    assert_eq(new_function(5), 10, "new_function: basic case")
    assert_eq(new_function(0), 0, "new_function: zero input")
    assert_eq(new_function(-1), 0, "new_function: negative clamped")
```

## Binary Loading Implementation

The runtime uses LispBM's `import` statement to load binary data at runtime:

```lisp
; Import binary file as a top-level form (NOT inside a flashed function — see VESC 7.00 notes)
(import "generated/display_lut.bin" 'display_lut_bin)
; Validate headers
(defun validate_lut_header (data magic expected_version) { … })
; Access display data (offset by 8-byte header)
(bufcpy pixbuf 0 display_lut_bin (+ 8 start_pos) 16)
```

### Why `pixbuf` is Required

The `pixbuf` variable is a 16-byte working buffer that is essential to the display system and **cannot be removed**:

```lisp
(let ((start_pos 0)
         (pixbuf (array-create 16))) {  // Temporary 16-byte buffer
      …
      // Copy 16 bytes from binary file to pixbuf
      (bufcpy pixbuf 0 display_lut_bin (+ 8 start_pos) 16)

      // Send pixbuf to display via I2C
      (i2c-tx-rx mpu-addr pixbuf)
})
```

**Why it's needed:**

1. The `i2c-tx-rx` function requires a buffer to send data
2. We cannot send data directly from the binary file to I2C
3. The buffer extracts the specific 16-byte frame we need from the larger binary file
4. It's a small (16 bytes) stack-allocated array with negligible overhead

## Build Dependencies

* Python 3.x (for build tools)
* VESC Tool (for building .vescpkg files)
* Standard Unix tools (make, grep, etc.)

## Repository

<https://github.com/vedderb/vesc_pkg>
