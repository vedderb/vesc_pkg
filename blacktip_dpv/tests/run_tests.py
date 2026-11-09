#!/usr/bin/env python3
"""
BlackTip DPV Smoke Tests
Tests pure functions to catch regressions before flashing hardware
"""

import contextlib
import csv
import importlib.util
import io
import os
import random
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

# Test counters
test_passes = 0
test_failures = 0

def assert_eq(actual, expected, test_name):
    """Assert that actual equals expected"""
    global test_passes, test_failures
    if actual == expected:
        test_passes += 1
        print(f"✓ {test_name}")
    else:
        test_failures += 1
        print(f"✗ {test_name}")
        print(f"  Expected: {expected}")
        print(f"  Actual:   {actual}")

def assert_near(actual, expected, tolerance, test_name):
    """Assert that actual is within tolerance of expected"""
    global test_passes, test_failures
    if abs(actual - expected) <= tolerance:
        test_passes += 1
        print(f"✓ {test_name}")
    else:
        test_failures += 1
        print(f"✗ {test_name}")
        print(f"  Expected: {expected} ± {tolerance}")
        print(f"  Actual:   {actual}")

# =============================================================================
# Pure Function Implementations (mirroring blacktip_dpv.lisp)
# =============================================================================

SPEED_REVERSE_THRESHOLD = 5
DISPLAY_LUT_PATH = Path(__file__).resolve().parents[1] / 'assets' / 'display_lut.csv'
DISPLAY_LUT_HEADERS = ['index', 'name'] + [f'b{i}' for i in range(16)]
DISPLAY_LUT_GENERATOR = Path(__file__).resolve().parents[1] / 'tools' / 'generate_lut_binary.py'
DISPLAY_ROTATION_MODULE = Path(__file__).resolve().parents[1] / 'tools' / 'display_rotation.py'
DISPLAY_LUT_BIN_PATH = Path(__file__).resolve().parents[1] / 'generated' / 'display_lut.bin'
DISPLAY_LUT_FRAMES = 33
DISPLAY_LUT_VERSION = 2
TIMER_BAR_MASKS = [0x00, 0x40, 0x60, 0x70, 0x78, 0x7C, 0x7E, 0x7F, 0xFF]
# Bit of a row byte that drives physical column 0..7 (DISPLAY_COLUMN_BITS in the Lisp).
DISPLAY_COLUMN_BITS = [0x80, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]
# Legacy constants of the timer bar that was drawn on the pre-rotated frames
# (firmware 1.6.1 and 1.6.2 before the table stored one orientation). They are
# an independent, hand-written oracle for where the timer bar lands at each
# rotation, not code under test.
LEGACY_TIMER_BAR_SOURCE_BITS = DISPLAY_COLUMN_BITS
LEGACY_TIMER_BAR_ROTATION_2_BITS = [0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01, 0x80]

def _load_display_rotation():
    """Import the shared reference rotation (also used by tools/preview_display.py)."""
    spec = importlib.util.spec_from_file_location('display_rotation', DISPLAY_ROTATION_MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# The reference rotation: defined from the geometry (a quarter turn moves
# pixel (row a, column b) to (row b, column 7 - a)), not copied from the Lisp.
# test_display_rotation_reference anchors it to hand-typed bytes.
DISPLAY_ROTATION = _load_display_rotation()
rotate_frame = DISPLAY_ROTATION.rotate_frame


def clamp(value, min_val, max_val):
    """Clamp value between min and max"""
    if value < min_val:
        return min_val
    elif value > max_val:
        return max_val
    else:
        return value

def validate_boolean(value):
    """Convert to boolean (0 or 1)"""
    # In LispBM, (> value 0) returns true for positive numbers
    # -1 is NOT > 0, so it returns 0
    return 1 if value > 0 else 0

def state_name_for(state):
    """Map state number to name"""
    STATE_OFF = 0
    STATE_COUNTING_CLICKS = 1
    STATE_PRESSED = 2
    STATE_GOING_OFF = 3
    STATE_UNINITIALIZED = 4

    mapping = {
        STATE_OFF: "Off",
        STATE_COUNTING_CLICKS: "CountingClicks",
        STATE_PRESSED: "Pressed",
        STATE_GOING_OFF: "GoingOff",
        STATE_UNINITIALIZED: "Init"
    }
    return mapping.get(state, "Unknown")

def speed_percentage_at(speed_index):
    """Get speed percentage for given index"""
    speed_set = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    max_index = len(speed_set) - 1
    clamped = clamp(speed_index, 0, max_index)
    return speed_set[clamped]

def calculate_rpm(speed_index, divisor, max_erpm=50000):
    """Calculate RPM for given speed index"""
    speed_percent = speed_percentage_at(speed_index)
    # Formula: (* (/ max_erpm divisor) speed_percent)
    # speed_percent is 0-100, not 0-1
    base_rpm = (max_erpm / divisor) * (speed_percent / 100.0)

    if speed_index < SPEED_REVERSE_THRESHOLD:
        return -base_rpm
    else:
        return base_rpm


def apply_timer_bar_overlay(frame_bytes, leds_lit):
    """Mirror apply_smart_cruise_timer_bar: one set of bits, rotation 0 frame."""
    frame = list(frame_bytes)
    if leds_lit != -1:
        frame[15] |= TIMER_BAR_MASKS[max(0, min(8, leds_lit))]
    return frame


def legacy_timer_bar_overlay(frame_bytes, leds_lit, rotation):
    """The overlay that was applied to an already rotated frame (oracle only)."""
    frame = list(frame_bytes)
    if leds_lit == -1:
        return frame
    mask = TIMER_BAR_MASKS[max(0, min(8, leds_lit))]

    if rotation == 0:
        frame[15] |= mask
    elif rotation == 1:
        for column, source_bit in enumerate(LEGACY_TIMER_BAR_SOURCE_BITS):
            if mask & source_bit:
                frame[column * 2 + 1] |= 0x80
    elif rotation == 2:
        for column, source_bit in enumerate(LEGACY_TIMER_BAR_SOURCE_BITS):
            if mask & source_bit:
                frame[1] |= LEGACY_TIMER_BAR_ROTATION_2_BITS[column]
    elif rotation == 3:
        for column, source_bit in enumerate(LEGACY_TIMER_BAR_SOURCE_BITS):
            if mask & source_bit:
                frame[(7 - column) * 2 + 1] |= 0x40
    return frame


def frame_to_send(rotation0_frame, leds_lit, rotation):
    """What the display path sends: overlay at rotation 0, then rotate (reference rotation)."""
    return rotate_frame(apply_timer_bar_overlay(rotation0_frame, leds_lit), rotation)


# Five-click shutdown mirrors. The third fw-ver value is the beta/test build;
# zero denotes a stable release.
SPEED_OFF = 99
def firmware_supports_shutdown(fw_ver):
    if fw_ver is None or len(fw_ver) < 3:
        return False
    major, minor, patch = fw_ver[:3]
    return major > 7 or (major == 7 and
                         (minor > 0 or (minor == 0 and (patch == 0 or patch >= 2))))


def five_click_shutdown_rejection_reason(state):
    if state['enable_five_click_shutdown'] != 1:
        return 'feature disabled'
    if state['hw_name'] != '60_MK5':
        return 'hardware is not 60_MK5'
    if not firmware_supports_shutdown(state['fw_ver']):
        return 'unsupported pre-release firmware build'
    if state['speed'] != SPEED_OFF:
        return 'commanded speed is not off'
    return None


def request_five_click_shutdown_simulate(state):
    """Return shutdown call count for the immediate stopped-state decision."""
    return 0 if five_click_shutdown_rejection_reason(state) is not None else 1


def trigger_click_accepted(trigger_input_ready, trigger_armed, sw_pressed):
    """Mirror the stopped-state guard before beginning a click sequence."""
    return trigger_input_ready == 1 and trigger_armed == 1 and sw_pressed == 1


def trigger_arm_after_release(trigger_input_ready, sw_pressed, trigger_armed=0):
    """Mirror the trigger loop's release-to-arm behaviour."""
    if trigger_input_ready == 1 and sw_pressed == 0:
        return 1
    return trigger_armed


def trigger_arm_after_ready_sample(trigger_input_ready, sw_pressed):
    """Mirror the synchronous sample that follows readiness publication."""
    return 1 if trigger_input_ready == 1 and sw_pressed == 0 else 0


def migrate_eeprom_v3(eeprom, stored_version):
    """Mirror only the layered v3 migration relevant to an existing schema."""
    result = dict(eeprom)
    if stored_version < 3:
        result[32] = 0
        result[127] = 3
    return result


def receive_settings_simulate(eeprom, payload):
    if len(payload) < 33:
        return False, dict(eeprom)
    result = dict(eeprom)
    for index, value in enumerate(payload[:33]):
        result[index] = value
    return True, result

# =============================================================================
# Test Suites
# =============================================================================

def test_clamp():
    """Test clamp function"""
    print("\n=== Testing clamp ===")

    # Within range
    assert_eq(clamp(5, 0, 10), 5, "clamp: value within range")

    # Below minimum
    assert_eq(clamp(-5, 0, 10), 0, "clamp: value below min")

    # Above maximum
    assert_eq(clamp(15, 0, 10), 10, "clamp: value above max")

    # At boundaries
    assert_eq(clamp(0, 0, 10), 0, "clamp: value at min boundary")
    assert_eq(clamp(10, 0, 10), 10, "clamp: value at max boundary")

    # Negative range
    assert_eq(clamp(-5, -10, -1), -5, "clamp: value in negative range")
    assert_eq(clamp(-15, -10, -1), -10, "clamp: value below negative min")

def test_validate_boolean():
    """Test validate_boolean function"""
    print("\n=== Testing validate_boolean ===")

    # Valid boolean values
    assert_eq(validate_boolean(0), 0, "validate_boolean: 0 -> 0")
    assert_eq(validate_boolean(1), 1, "validate_boolean: 1 -> 1")

    # Non-standard truthy values
    assert_eq(validate_boolean(5), 1, "validate_boolean: 5 -> 1")
    assert_eq(validate_boolean(100), 1, "validate_boolean: 100 -> 1")

    # Negative values (> operator: -1 is NOT > 0, so returns 0)
    assert_eq(validate_boolean(-1), 0, "validate_boolean: -1 -> 0")

def test_state_name_for():
    """Test state_name_for function"""
    print("\n=== Testing state_name_for ===")

    # Valid states
    assert_eq(state_name_for(0), "Off", "state_name_for: STATE_OFF")
    assert_eq(state_name_for(1), "CountingClicks", "state_name_for: STATE_COUNTING_CLICKS")
    assert_eq(state_name_for(2), "Pressed", "state_name_for: STATE_PRESSED")
    assert_eq(state_name_for(3), "GoingOff", "state_name_for: STATE_GOING_OFF")
    assert_eq(state_name_for(4), "Init", "state_name_for: STATE_UNINITIALIZED")

    # Invalid state
    assert_eq(state_name_for(99), "Unknown", "state_name_for: invalid state")

def test_speed_percentage_at():
    """Test speed_percentage_at function"""
    print("\n=== Testing speed_percentage_at ===")

    # Valid indices
    assert_eq(speed_percentage_at(0), 0, "speed_percentage_at: index 0")
    assert_eq(speed_percentage_at(5), 50, "speed_percentage_at: index 5")
    assert_eq(speed_percentage_at(10), 100, "speed_percentage_at: index 10")

    # Out of bounds (should clamp)
    assert_eq(speed_percentage_at(-1), 0, "speed_percentage_at: negative index clamped to 0")
    assert_eq(speed_percentage_at(99), 100, "speed_percentage_at: large index clamped to max")

def test_calculate_rpm():
    """Test calculate_rpm function"""
    print("\n=== Testing calculate_rpm ===")

    # Forward speeds (above SPEED_REVERSE_THRESHOLD)
    assert_near(calculate_rpm(5, 1), 25000, 0.1, "calculate_rpm: speed 5, divisor 1")
    assert_near(calculate_rpm(10, 1), 50000, 0.1, "calculate_rpm: speed 10 (max), divisor 1")
    assert_near(calculate_rpm(5, 2), 12500, 0.1, "calculate_rpm: speed 5, divisor 2")

    # Reverse speeds (below SPEED_REVERSE_THRESHOLD)
    assert_near(calculate_rpm(0, 1), 0, 0.1, "calculate_rpm: speed 0 (reverse range, 0 RPM)")
    assert_near(calculate_rpm(2, 1), -10000, 0.1, "calculate_rpm: speed 2 (reverse)")

    # Edge case at threshold
    assert_near(calculate_rpm(4, 1), -20000, 0.1, "calculate_rpm: speed 4 (just below threshold)")
    assert_near(calculate_rpm(5, 1), 25000, 0.1, "calculate_rpm: speed 5 (at threshold, forward)")


def test_motor_speed_command_centralisation():
    """Normal selector commands must retain one RPM-controlled path."""
    print("\n=== Testing motor speed command centralisation ===")
    source = (Path(__file__).resolve().parents[1] / 'blacktip_dpv.lisp').read_text()

    assert_eq('(defun set_motor_speed (speed_index divisor)' in source, True,
              "motor speed: common command helper exists")
    assert_eq('(set-rpm (calculate_rpm speed_index divisor))' in source, True,
              "motor speed: helper preserves RPM calculation")
    assert_eq(source.count('(set_motor_speed speed ') == 7, True,
              "motor speed: every normal speed command uses the helper")
    assert_eq('(set-rpm (calculate_rpm speed RPM_PERCENT_DENOMINATOR))' in source,
              False, "motor speed: full-speed commands do not bypass the helper")
    assert_eq('(set-rpm (calculate_rpm speed SMART_CRUISE_SLOWDOWN_DIVISOR))' in source,
              False, "motor speed: Smart Cruise slowdown does not bypass the helper")
    assert_eq('(set-duty SAFE_START_DUTY)' in source, True,
              "motor speed: safe-start duty command remains separate")


def test_startup_tune_cancellation_for_motor_start():
    """A motor start must prevent background startup audio reclaiming FOC."""
    print("\n=== Testing startup tune cancellation ===")
    source = (Path(__file__).resolve().parents[1] / 'blacktip_dpv.lisp').read_text()

    assert_eq("(setvar 'startup_tune_cancelled 1)" in source, True,
              "startup audio: motor start cancels the conflicting startup tune")
    assert_eq("(setvar 'batt_beeps_pending 0)" in source, True,
              "startup audio: motor start cancels deferred battery beeps")
    assert_eq("(setvar 'startup_tune_active 1)" in source, True,
              "startup audio: startup marks the tune active")
    assert_eq("(setvar 'startup_tune_active 0)" in source, True,
              "startup audio: tune completion releases FOC ownership")
    assert_eq('(defun startup_tune_note (tone time delay)' in source, True,
              "startup audio: tune notes check for motor-start cancellation")
    assert_eq('(foc-beep tone time beeps_vol)' in source, True,
              "startup audio: tune retains its existing note generator")
    assert_eq('(foc-play-tone 1 3000 beeps_vol)' in source, True,
              "startup audio: normal double-click confirmation tone is retained")


def _load_lut_generator():
    """Import the very module the Makefile runs, not a copy of its logic."""
    spec = importlib.util.spec_from_file_location('generate_lut_binary', DISPLAY_LUT_GENERATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _read_display_csv_frames():
    """Return (rows, frames): the CSV rows and the 16 bytes of each of the 33 displays."""
    with DISPLAY_LUT_PATH.open(newline='') as asset:
        rows = list(csv.DictReader(asset))
    return rows, [[int(row[f'b{i}']) for i in range(16)] for row in rows]


def test_display_lut_structure():
    """Keep the CSV layout stable: one rotation 0 row for each of the 33 displays."""
    print("\n=== Testing display LUT structure ===")

    with DISPLAY_LUT_PATH.open(newline='') as asset:
        reader = csv.DictReader(asset)
        rows = list(reader)

    assert_eq(reader.fieldnames, DISPLAY_LUT_HEADERS,
              "display LUT: CSV columns are index, name and b0..b15 (no rotation column)")
    assert_eq(len(rows), DISPLAY_LUT_FRAMES, "display LUT: 33 displays, one row each")
    assert_eq([int(row['index']) for row in rows], list(range(DISPLAY_LUT_FRAMES)),
              "display LUT: indices are sequential, so row n is display n")
    assert_eq(all(set(row) == set(DISPLAY_LUT_HEADERS) for row in rows), True,
              "display LUT: each row has exactly the required fields")
    names = [row['name'] for row in rows]
    assert_eq(all(names) and len(set(names)) == len(names), True,
              "display LUT: every display has a unique name")

    frame_bytes = [[int(row[f'b{i}']) for i in range(16)] for row in rows]
    assert_eq(all(0 <= value <= 255 for frame in frame_bytes for value in frame), True,
              "display LUT: byte values are unsigned octets")
    assert_eq(all(frame[0::2] == [0] * 8 for frame in frame_bytes), True,
              "display LUT: low/high interleaved layout is preserved (even bytes are 0)")


def test_display_lut_binary_single_orientation():
    """The binary stores rotation 0 of each frame once; the firmware rotates it."""
    print("\n=== Testing display LUT binary (one orientation per frame) ===")
    generator = _load_lut_generator()
    rows, frames = _read_display_csv_frames()

    # Expected table, built here from the CSV without the generator's code.
    expected = struct.pack('<IHH', DISPLAY_LUT_MAGIC, DISPLAY_LUT_VERSION, DISPLAY_LUT_FRAMES)
    expected += b''.join(bytes(frame) for frame in frames)

    with tempfile.TemporaryDirectory() as work:
        out_dir = Path(work) / 'generated'
        saved = (generator.GENERATED_DIR, generator.DISPLAY_BIN)
        generator.GENERATED_DIR, generator.DISPLAY_BIN = out_dir, out_dir / 'display_lut.bin'
        try:
            generator.generate_display_binary()
            data = generator.DISPLAY_BIN.read_bytes()
        finally:
            generator.GENERATED_DIR, generator.DISPLAY_BIN = saved

    assert_eq(data[:4], b'DTUL', "display binary: magic bytes spell LUTD little-endian")
    assert_eq(struct.unpack_from('<IHH', data, 0),
              (DISPLAY_LUT_MAGIC, DISPLAY_LUT_VERSION, DISPLAY_LUT_FRAMES),
              "display binary: header is magic, version 2, 33 frames")
    assert_eq(validate_lut_header(data, DISPLAY_LUT_MAGIC, DISPLAY_LUT_VERSION), DISPLAY_LUT_FRAMES,
              "display binary: version 2 passes the firmware header check")
    assert_eq(validate_lut_header(data, DISPLAY_LUT_MAGIC, 1), None,
              "display binary: the firmware's old version 1 check rejects it")
    assert_eq(len(data), 536,
              "display binary: 8 byte header plus 16 bytes for each of the 33 frames is 536 bytes")
    assert_eq(data, expected, "display binary: the 33 CSV rows converted straight to the table")
    assert_eq([list(data[8 + 16 * n:24 + 16 * n]) for n in range(DISPLAY_LUT_FRAMES)], frames,
              "display binary: entry n is the CSV row of display n")

    # The Lisp source must check for the version this generator writes.
    source = LISP_SOURCE.read_text()
    assert_eq('(validate_lut_header display_lut_bin 0x4C555444u32 %d)' % generator.VERSION in source, True,
              "display binary: the firmware checks for the generator's version")
    assert_eq(generator.VERSION, DISPLAY_LUT_VERSION, "display binary: generator writes version 2")

    # Optional: a table left over from an earlier build of another format.
    if DISPLAY_LUT_BIN_PATH.exists():
        assert_eq(DISPLAY_LUT_BIN_PATH.read_bytes() == data, True,
                  "display binary: generated/display_lut.bin is current (run 'make binary' if not)")
    else:
        print("SKIPPED: generated/display_lut.bin not built; run 'make binary' to check it too")


def _run_generator_on(generator, csv_text):
    """Run the generator's entry point on csv_text.

    A stale table is put in place first. Returns (exit status, stderr text,
    table bytes or None if no table exists afterwards).
    """
    with tempfile.TemporaryDirectory() as work:
        csv_path = Path(work) / 'input.csv'
        csv_path.write_text(csv_text)
        out_dir = Path(work) / 'generated'
        out_dir.mkdir()
        (out_dir / 'display_lut.bin').write_bytes(b'stale')
        saved = (generator.DISPLAY_CSV, generator.GENERATED_DIR, generator.DISPLAY_BIN)
        generator.DISPLAY_CSV = csv_path
        generator.GENERATED_DIR, generator.DISPLAY_BIN = out_dir, out_dir / 'display_lut.bin'
        errors = io.StringIO()
        try:
            with contextlib.redirect_stderr(errors), contextlib.redirect_stdout(io.StringIO()):
                status = generator.main()
        finally:
            generator.DISPLAY_CSV, generator.GENERATED_DIR, generator.DISPLAY_BIN = saved
        table = (out_dir / 'display_lut.bin')
        return status, errors.getvalue(), table.read_bytes() if table.exists() else None


def test_display_lut_generator_validation():
    """The generator converts a clean CSV and fails loudly, with the line, on a malformed one."""
    print("\n=== Testing display LUT generator validation ===")
    generator = _load_lut_generator()
    lines = DISPLAY_LUT_PATH.read_text().splitlines()
    assert_eq(len(lines), 1 + DISPLAY_LUT_FRAMES, "generator validation: the CSV under test has 33 rows")
    frames = generator.read_frames(DISPLAY_LUT_PATH)
    assert_eq((len(frames), frames == _read_display_csv_frames()[1]), (DISPLAY_LUT_FRAMES, True),
              "generator validation: the real CSV is read as its 33 rows")

    def csv_of(rows):
        return '\n'.join(rows) + '\n'

    def with_line(number, text):
        copy = list(lines)
        copy[number - 1] = text
        return csv_of(copy)

    def fields(number):
        return lines[number - 1].split(',')

    def with_fields(number, change):
        parts = fields(number)
        change(parts)
        return with_line(number, ','.join(parts))

    # The clean CSV goes through the same entry point, so the failures below
    # are not an artefact of the helper.
    status, message, table = _run_generator_on(generator, csv_of(lines))
    assert_eq((status, message, table is not None and len(table)), (0, '', 536),
              "generator validation: the clean CSV converts and leaves a 536 byte table")
    # A display can be added without changing the generator (the tests pin 33).
    status, _, table = _run_generator_on(generator, csv_of(lines[:-1]))
    assert_eq((status, table is not None and len(table)), (0, 8 + 16 * 32),
              "generator validation: the table size follows the number of rows")

    def odd_names(parts):
        parts[1] = fields(3)[1]

    # (what is wrong, the CSV text, expected line in the message or None, expected snippet)
    cases = [
        ("a CSV with no rows", csv_of(lines[:1]), None, 'no display rows'),
        ("an empty file", '', 1, 'expected the columns'),
        ("the old rotation column", csv_of(
            [lines[0].replace('name,', 'name,rotation,')] + lines[1:]), 1, 'expected the columns'),
        ("a missing row in the middle", csv_of(lines[:6] + lines[7:]), 7, 'index 6, expected 5'),
        ("a row with the wrong index", with_fields(5, lambda p: p.__setitem__(0, '9')), 5, 'index 9'),
        ("too few byte fields", with_fields(5, lambda p: p.pop()), 5, 'got 17'),
        ("too many byte fields", with_fields(5, lambda p: p.append('0')), 5, 'got 19'),
        ("an empty byte field", with_fields(5, lambda p: p.__setitem__(6, '')), 5, 'invalid literal'),
        ("a byte above 255", with_fields(5, lambda p: p.__setitem__(7, '256')), 5, '0..255'),
        ("a negative byte", with_fields(5, lambda p: p.__setitem__(7, '-1')), 5, '0..255'),
        ("a byte that is not a number", with_fields(5, lambda p: p.__setitem__(7, 'x')), 5, 'invalid literal'),
        ("a non-zero even byte", with_fields(6, lambda p: p.__setitem__(2, '1')), 6, 'even bytes'),
        ("a non-zero last even byte", with_fields(6, lambda p: p.__setitem__(16, '4')), 6, 'even bytes'),
        ("a duplicate name", with_fields(9, odd_names), 9, 'already used'),
        ("an empty name", with_fields(9, lambda p: p.__setitem__(1, ' ')), 9, 'no name'),
    ]
    for label, text, line, snippet in cases:
        status, message, table = _run_generator_on(generator, text)
        expected_message = snippet in message and (line is None or f'line {line}:' in message)
        assert_eq((status, expected_message, table), (1, True, None),
                  f"generator validation: {label} makes the generator exit 1 with "
                  f"'{snippet}'{'' if line is None else f' at line {line}'} and removes the stale table")


def _typed_asymmetric_frames():
    """An asymmetric bitmap and its clockwise turns, typed by hand.

    Pixels of the bitmap (row a from the top, column b from the left):
        row 0: # # # . . . . .
        row 1: # . . . . . . .
        row 2: # # . . . . . .
        row 3: # . . . . . . .
        rows 4 to 6 empty
        row 7: . . . . . . . #
    The bits of a row byte, for columns 0 to 7, are 0x80, 0x01, 0x02, 0x04,
    0x08, 0x10, 0x20, 0x40. A quarter turn moves pixel (a, b) to (b, 7 - a).
    """
    turns = [
        # as drawn: row 0 = columns 0, 1, 2 = 0x83; row 7 = column 7 = 0x40
        [0, 0x83, 0, 0x80, 0, 0x81, 0, 0x80, 0, 0, 0, 0, 0, 0, 0, 0x40],
        # one turn: the rows become columns 7, 6, 5, 4 of the first rows
        [0, 0x78, 0, 0x50, 0, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x80],
        # two turns: the bitmap upside down and mirrored left to right
        [0, 0x80, 0, 0, 0, 0, 0, 0, 0, 0x40, 0, 0x60, 0, 0x40, 0, 0x70],
        # three turns: one counter-clockwise turn
        [0, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x80, 0, 0x82, 0, 0x87],
    ]
    return turns


def _flip_both_axes(frame):
    """Rows bottom to top and columns right to left, written with the bit masks."""
    flipped = [0] * 16
    for a in range(8):
        for b in range(8):
            if frame[2 * a + 1] & DISPLAY_COLUMN_BITS[b]:
                flipped[2 * (7 - a) + 1] |= DISPLAY_COLUMN_BITS[7 - b]
    return flipped


def test_display_rotation_reference():
    """Anchor the shared Python reference rotation to the geometry and to hand-typed bytes."""
    print("\n=== Testing the reference display rotation ===")
    rows, display_frames = _read_display_csv_frames()

    # The physical column to bit map, from a hand-written example.
    assert_eq(DISPLAY_ROTATION.COLUMN_BITS, [7, 0, 1, 2, 3, 4, 5, 6],
              "reference rotation: physical column to bit map is 7, 0, 1, 2, 3, 4, 5, 6")
    for row, column, byte_index, mask in ((0, 0, 1, 0x80), (0, 1, 1, 0x01), (0, 7, 1, 0x40),
                                          (3, 5, 7, 0x10), (7, 0, 15, 0x80), (7, 7, 15, 0x40)):
        single = [0] * 16
        single[byte_index] = mask
        grid = DISPLAY_ROTATION.frame_to_grid(single)
        assert_eq(sum(map(sum, grid)) == 1 and grid[row][column] == 1, True,
                  f"reference rotation: byte {byte_index} mask 0x{mask:02X} is row {row}, column {column}")
        assert_eq(DISPLAY_ROTATION.grid_to_frame(grid), single,
                  f"reference rotation: row {row}, column {column} converts back to byte {byte_index}")

    # An asymmetric bitmap against bytes typed from the geometric rule.
    typed = _typed_asymmetric_frames()
    for turns in range(4):
        assert_eq(rotate_frame(typed[0], turns), typed[turns],
                  f"reference rotation: the asymmetric bitmap turned {turns} x 90 degrees "
                  "equals the hand-typed bytes")
    assert_eq(rotate_frame(typed[0], 1) != typed[3], True,
              "reference rotation: a clockwise turn is not a counter-clockwise turn")
    top_left = [0, 0x80] + [0] * 14
    assert_eq(rotate_frame(top_left, 1), [0, 0x40] + [0] * 14,
              "reference rotation: the top-left pixel goes to the top-right corner")
    assert_eq(rotate_frame(top_left, 3), [0] * 14 + [0, 0x80],
              "reference rotation: the top-left pixel goes to the bottom-left corner")

    # Properties on the 33 displays, every single pixel and pseudo-random bitmaps.
    singles = []
    for a in range(8):
        for b in range(8):
            single = [0] * 16
            single[2 * a + 1] = DISPLAY_COLUMN_BITS[b]
            singles.append(single)
    generator = random.Random(2026)
    randoms = [[0 if i % 2 == 0 else generator.randrange(256) for i in range(16)] for _ in range(200)]
    corpus = display_frames + singles + randoms + [[0] * 16, [0, 255] * 8]
    four_turns = sum(1 for f in corpus if rotate_frame(rotate_frame(rotate_frame(rotate_frame(f, 1), 1), 1), 1) != f)
    assert_eq((len(corpus), four_turns), (len(corpus), 0),
              "reference rotation: four quarter turns are the identity "
              f"({len(corpus)} bitmaps)")
    half_turns = sum(1 for f in corpus if rotate_frame(f, 2) != _flip_both_axes(f))
    assert_eq(half_turns, 0, "reference rotation: two quarter turns equal flipping both axes")
    composed = sum(1 for f in corpus for m in range(4) for n in range(4)
                   if rotate_frame(rotate_frame(f, m), n) != rotate_frame(f, m + n))
    assert_eq(composed, 0, "reference rotation: turns add up (every pair of turn counts)")
    pixels = sum(1 for f in corpus for t in range(4)
                 if sum(map(sum, DISPLAY_ROTATION.frame_to_grid(rotate_frame(f, t))))
                 != sum(map(sum, DISPLAY_ROTATION.frame_to_grid(f))))
    assert_eq(pixels, 0, "reference rotation: the number of lit pixels never changes")
    assert_eq(sum(1 for f in singles if rotate_frame(f, 1) == f), 0,
              "reference rotation: no single pixel stays put under a quarter turn")
    assert_eq(all(rotate_frame(f, t)[0::2] == [0] * 8 for f in corpus for t in range(1, 4)), True,
              "reference rotation: the even bytes of a rotated frame are 0")

    # Turn counts are taken modulo 4, negative ones included.
    sample = display_frames[11]
    for turns, equivalent in ((4, 0), (5, 1), (6, 2), (7, 3), (-1, 3), (-2, 2), (-3, 1), (-4, 0), (8, 0)):
        assert_eq(rotate_frame(sample, turns), rotate_frame(sample, equivalent),
                  f"reference rotation: out-of-range turn count {turns} behaves as {equivalent}")

    # The preview tool uses this very module, not a copy of the rule.
    preview = (Path(__file__).resolve().parents[1] / 'tools' / 'preview_display.py').read_text()
    assert_eq('from display_rotation import rotate_frame' in preview, True,
              "reference rotation: preview_display.py imports the shared rotation")


def test_smart_cruise_timer_bar_rotation():
    """The timer overlay is applied to the stored frame, then both rotate together."""
    print("\n=== Testing Smart Cruise timer bar rotation ===")

    base_frame = [0] * 16
    for leds_lit in range(9):
        expected = DISPLAY_ROTATION.frame_to_grid(apply_timer_bar_overlay(base_frame, leds_lit))
        for rotation in range(4):
            if rotation > 0:
                expected = DISPLAY_ROTATION.rotate_grid_clockwise(expected)
            actual = DISPLAY_ROTATION.frame_to_grid(frame_to_send(base_frame, leds_lit, rotation))
            assert_eq(actual, expected,
                      f"timer bar: {leds_lit} LEDs rotates clockwise at rotation {rotation}")
            assert_eq(frame_to_send(base_frame, leds_lit, rotation),
                      legacy_timer_bar_overlay(rotate_frame(base_frame, rotation), leds_lit, rotation),
                      f"timer bar: {leds_lit} LEDs at rotation {rotation} matches the earlier "
                      "per-rotation overlay on an empty frame")

    # Overlay then rotate equals the hand-written per-rotation overlay on the
    # rotated frame, for every frame, rotation and LED count. The frames are
    # the 33 rotation 0 rows turned by the reference rotation.
    rows, frames = _read_display_csv_frames()
    differences = 0
    checked = 0
    for frame in frames:
        for rotation in range(4):
            for leds_lit in range(-1, 9):
                checked += 1
                old = legacy_timer_bar_overlay(rotate_frame(frame, rotation), leds_lit, rotation)
                if frame_to_send(frame, leds_lit, rotation) != old:
                    differences += 1
    assert_eq((checked, differences), (33 * 4 * 10, 0),
              "timer bar: overlay then rotate equals the per-rotation overlay on the rotated frame "
              "(33 frames x 4 rotations x LED counts -1..8)")
    # Non-vacuous: the wrong rotation does change the bytes.
    wrong = sum(1 for frame in frames for leds_lit in range(1, 9)
                if rotate_frame(apply_timer_bar_overlay(frame, leds_lit), 1)
                != legacy_timer_bar_overlay(rotate_frame(frame, 2), leds_lit, 2))
    assert_eq(wrong > 0, True, "timer bar: comparing against the wrong rotation is detected")


# =============================================================================
# New functions added in PR (VESC 7.00 compatibility)
# =============================================================================

# BRIGHTNESS_LUT: six discrete brightness levels sent to the HT16K33 via I2C.
# Indices 0..5 map to hardware register values.
BRIGHTNESS_LUT = [224, 227, 230, 233, 236, 239]

# LUT binary magic for the display lookup table ('LUTD' as a little-endian u32)
DISPLAY_LUT_MAGIC = 0x4C555444


def validate_lut_header(data, magic, expected_version):
    """
    Mirror of validate_lut_header from blacktip_dpv.lisp.

    Binary layout (little-endian):
      offset 0 : u32  magic
      offset 4 : u16  version
      offset 6 : u16  num_items

    Returns num_items on success, None on any mismatch (mirrors LispBM nil).
    Raises struct.error if data is too short.
    """
    file_magic = struct.unpack_from('<I', data, 0)[0]
    file_version = struct.unpack_from('<H', data, 4)[0]
    num_items = struct.unpack_from('<H', data, 6)[0]
    if file_magic != magic:
        return None
    if file_version != expected_version:
        return None
    return num_items


def _make_lut_header(magic, version, num_items):
    """Build an 8-byte LUT header for use in tests."""
    return struct.pack('<IHH', magic, version, num_items)


def debug_log(debug_enabled, msg, log_target):
    """
    Mirror of debug_log from blacktip_dpv.lisp (const block 2).

    Only appends msg to log_target when debug_enabled is exactly 1 and not None.
    """
    if debug_enabled is not None and debug_enabled == 1:
        log_target.append(msg)


def debug_log_format(debug_enabled, expr_fn, log_target):
    """
    Mirror of the debug_log_format macro from blacktip_dpv.lisp (const block 1).

    expr_fn is a callable that produces the string to log; it is only called
    (lazy evaluation) when debug_enabled is 1. This models the macro behaviour
    that prevents expensive str-merge / to-str calls in hot paths when debug is off.
    """
    if debug_enabled is not None and debug_enabled == 1:
        log_target.append(expr_fn())


def brightness_index_for(disp_brightness):
    """
    Mirror of the brightness clamp used in peripherals_setup.

    Returns the index into BRIGHTNESS_LUT after clamping disp_brightness to
    the valid range [0, len(BRIGHTNESS_LUT) - 1].
    """
    return clamp(disp_brightness, 0, len(BRIGHTNESS_LUT) - 1)


def brightness_value_for(disp_brightness):
    """Return the HT16K33 register value for the given brightness setting."""
    return BRIGHTNESS_LUT[brightness_index_for(disp_brightness)]


def simulate_i2c_init_sequence(disp_brightness, scooter_type):
    """
    Simulate the I2C command sequence emitted by peripherals_setup.

    Returns the ordered list of (addr, data) tuples that would be sent via
    i2c-tx-rx, modelling the VESC 7.00 double-write workaround for address 0x70.
    scooter_type: 0 = Blacktip, 1 = CudaX.
    """
    commands = []
    # VESC 7.00 workaround: two oscillator-enable writes to 0x70.
    # First is sacrificial (absorbed by firmware bug); second reaches HT16K33.
    commands.append((0x70, [0x21]))  # sacrificial
    commands.append((0x70, [0x21]))  # real oscillator-enable
    brightness_val = brightness_value_for(disp_brightness)
    commands.append((0x70, [brightness_val]))
    if scooter_type == 1:
        # Second controller: bus already exercised, single write is enough.
        commands.append((0x71, [0x21]))
        commands.append((0x71, [brightness_val]))
    return commands


def simulate_blacktip_display_timeout_sequence():
    """Mirror the defensive Blacktip display-timeout I2C sequence."""
    blank_framebuffer = [0] * 16
    return [
        (0x70, blank_framebuffer),
        (0x70, [0x80]),
        (0x70, [0x80]),
    ]


def state_metrics_reset_simulate(state_store):
    """
    Mirror of state_metrics_reset from blacktip_dpv.lisp.

    In the PR the function was updated to use setvar instead of re-define,
    meaning it only mutates already-existing heap bindings. We model this with
    a dict that must already contain the keys (pre-declared as mutable globals).
    """
    STATE_UNINITIALIZED = -1
    state_store['state_last_state'] = STATE_UNINITIALIZED
    # state_last_change_time would be set to (systime); use a sentinel here.
    state_store['state_last_change_time'] = 'NOW'
    state_store['state_last_reason'] = 'startup'


# =============================================================================
# Test Suites — VESC 7.00 compatibility (PR changes)
# =============================================================================

def test_validate_lut_header():
    """Test validate_lut_header — new/moved function in VESC 7.00 PR."""
    print("\n=== Testing validate_lut_header ===")

    MAGIC = DISPLAY_LUT_MAGIC
    VERSION = 1

    # Valid header: correct magic, version, and a nonzero num_items
    data = _make_lut_header(MAGIC, VERSION, 42)
    assert_eq(validate_lut_header(data, MAGIC, VERSION), 42,
              "validate_lut_header: valid header returns num_items")

    # Valid header with num_items == 1 (minimum realistic value)
    data = _make_lut_header(MAGIC, VERSION, 1)
    assert_eq(validate_lut_header(data, MAGIC, VERSION), 1,
              "validate_lut_header: num_items = 1 returns 1")

    # Valid header with num_items == 0 (edge case: returns 0, which is falsy —
    # matches LispBM where (not 0) is true, causing exit-error in load_lookup_tables)
    data = _make_lut_header(MAGIC, VERSION, 0)
    assert_eq(validate_lut_header(data, MAGIC, VERSION), 0,
              "validate_lut_header: num_items = 0 returns 0 (falsy, triggers error path)")

    # Wrong magic → None
    data = _make_lut_header(0xDEADBEEF, VERSION, 10)
    assert_eq(validate_lut_header(data, MAGIC, VERSION), None,
              "validate_lut_header: wrong magic returns None")

    # Wrong version → None
    data = _make_lut_header(MAGIC, 2, 10)
    assert_eq(validate_lut_header(data, MAGIC, VERSION), None,
              "validate_lut_header: wrong version returns None")

    # Both magic and version wrong → None (magic checked first)
    data = _make_lut_header(0xDEADBEEF, 99, 10)
    assert_eq(validate_lut_header(data, MAGIC, VERSION), None,
              "validate_lut_header: wrong magic and version returns None")

    # Large num_items (max u16 = 65535)
    data = _make_lut_header(MAGIC, VERSION, 65535)
    assert_eq(validate_lut_header(data, MAGIC, VERSION), 65535,
              "validate_lut_header: max u16 num_items")

    # Regression: magic bytes in big-endian order must NOT match the little-endian magic
    be_magic = int.from_bytes(MAGIC.to_bytes(4, 'little'), 'big')
    data = _make_lut_header(be_magic, VERSION, 10)
    assert_eq(validate_lut_header(data, MAGIC, VERSION), None,
              "validate_lut_header: big-endian magic does not match little-endian parse")


def test_debug_log():
    """Test debug_log conditional behaviour (moved to const block 2 in PR)."""
    print("\n=== Testing debug_log ===")

    log = []

    # debug_enabled == 1: message is logged
    debug_log(1, "test message", log)
    assert_eq(log, ["test message"],
              "debug_log: logs when debug_enabled=1")

    # debug_enabled == 0: message is NOT logged
    log.clear()
    debug_log(0, "should not appear", log)
    assert_eq(log, [],
              "debug_log: silent when debug_enabled=0")

    # debug_enabled == None (LispBM nil): message is NOT logged
    log.clear()
    debug_log(None, "should not appear", log)
    assert_eq(log, [],
              "debug_log: silent when debug_enabled=None (nil)")

    # debug_enabled == 2: NOT equal to 1, message is NOT logged
    log.clear()
    debug_log(2, "should not appear", log)
    assert_eq(log, [],
              "debug_log: silent when debug_enabled=2 (not exactly 1)")

    # Multiple messages accumulate when enabled
    log.clear()
    debug_log(1, "first", log)
    debug_log(1, "second", log)
    assert_eq(log, ["first", "second"],
              "debug_log: multiple messages accumulate")


def test_debug_log_format():
    """
    Test debug_log_format lazy-evaluation behaviour (defined in const block 1).

    The macro must NOT evaluate its expression argument when debug is disabled —
    this is the key property that prevents expensive str-merge / to-str calls in
    hot paths (set_speed_safe, motor control loop, etc.).
    """
    print("\n=== Testing debug_log_format ===")

    log = []
    eval_count = [0]  # mutable counter to detect unwanted evaluation

    def expensive_expr():
        eval_count[0] += 1
        return "expensive string"

    # debug_enabled == 1: expression IS evaluated and logged
    debug_log_format(1, expensive_expr, log)
    assert_eq(log, ["expensive string"],
              "debug_log_format: evaluates and logs when debug_enabled=1")
    assert_eq(eval_count[0], 1,
              "debug_log_format: expression evaluated exactly once when enabled")

    # debug_enabled == 0: expression is NOT evaluated (lazy)
    log.clear()
    eval_count[0] = 0
    debug_log_format(0, expensive_expr, log)
    assert_eq(log, [],
              "debug_log_format: no output when debug_enabled=0")
    assert_eq(eval_count[0], 0,
              "debug_log_format: expression NOT evaluated when debug_enabled=0 (lazy)")

    # debug_enabled == None: expression is NOT evaluated (lazy)
    log.clear()
    eval_count[0] = 0
    debug_log_format(None, expensive_expr, log)
    assert_eq(log, [],
              "debug_log_format: no output when debug_enabled=None")
    assert_eq(eval_count[0], 0,
              "debug_log_format: expression NOT evaluated when debug_enabled=None (lazy)")


def test_brightness_clamp():
    """
    Test brightness index clamping used in peripherals_setup (VESC 7.00 PR).

    peripherals_setup now uses: (clamp disp_brightness 0 (- (length BRIGHTNESS_LUT) 1))
    which maps any out-of-range setting to the nearest valid BRIGHTNESS_LUT index.
    """
    print("\n=== Testing brightness_clamp for peripherals_setup ===")

    # Valid range: 0..5 passes through unchanged
    assert_eq(brightness_index_for(0), 0,
              "brightness_clamp: 0 -> index 0 (min)")
    assert_eq(brightness_index_for(3), 3,
              "brightness_clamp: 3 -> index 3 (mid)")
    assert_eq(brightness_index_for(5), 5,
              "brightness_clamp: 5 -> index 5 (max)")

    # Below minimum: clamped to 0
    assert_eq(brightness_index_for(-1), 0,
              "brightness_clamp: -1 clamped to 0")
    assert_eq(brightness_index_for(-100), 0,
              "brightness_clamp: -100 clamped to 0")

    # Above maximum: clamped to 5
    assert_eq(brightness_index_for(6), 5,
              "brightness_clamp: 6 clamped to 5")
    assert_eq(brightness_index_for(100), 5,
              "brightness_clamp: 100 clamped to 5")

    # Verify the BRIGHTNESS_LUT register values are within the expected HT16K33 range
    for idx in range(len(BRIGHTNESS_LUT)):
        val = BRIGHTNESS_LUT[idx]
        assert_eq(val >= 224 and val <= 239, True,
                  f"brightness_clamp: BRIGHTNESS_LUT[{idx}]={val} in HT16K33 dimming range 224-239")

    # brightness_value_for should map correctly to BRIGHTNESS_LUT entries
    assert_eq(brightness_value_for(0), 224,
              "brightness_value_for: level 0 -> 224 (dimmest)")
    assert_eq(brightness_value_for(5), 239,
              "brightness_value_for: level 5 -> 239 (brightest)")


def test_i2c_init_sequence():
    """
    Test the I2C initialisation sequence emitted by peripherals_setup.

    VESC 7.00 introduced a bug where the first i2c-tx-rx after i2c-start is
    silently dropped. The fix is to send the HT16K33 oscillator-enable command
    (0x21) twice: the first write is sacrificial, the second reaches the chip.
    """
    print("\n=== Testing I2C init sequence (VESC 7.00 double-write workaround) ===")

    # Blacktip (scooter_type=0): only one display controller at address 0x70
    cmds = simulate_i2c_init_sequence(disp_brightness=3, scooter_type=0)

    assert_eq(len(cmds), 3,
              "i2c_init: Blacktip sends exactly 3 i2c commands")

    assert_eq(cmds[0], (0x70, [0x21]),
              "i2c_init: first command is sacrificial 0x21 to 0x70")
    assert_eq(cmds[1], (0x70, [0x21]),
              "i2c_init: second command is real oscillator-enable 0x21 to 0x70")
    assert_eq(cmds[0], cmds[1],
              "i2c_init: both initial 0x21 writes are identical (workaround)")
    assert_eq(cmds[2][0], 0x70,
              "i2c_init: brightness command targets address 0x70")

    # CudaX (scooter_type=1): second controller at 0x71, single 0x21 sufficient
    cmds_cuda = simulate_i2c_init_sequence(disp_brightness=3, scooter_type=1)
    assert_eq(len(cmds_cuda), 5,
              "i2c_init: CudaX sends exactly 5 i2c commands")
    assert_eq(cmds_cuda[3], (0x71, [0x21]),
              "i2c_init: CudaX second screen gets single 0x21 (bus already exercised)")
    assert_eq(cmds_cuda[4][0], 0x71,
              "i2c_init: CudaX brightness command targets address 0x71")

    # 0x70 address must NOT appear after the first 3 commands in CudaX mode
    addresses_after_3 = [addr for addr, _ in cmds_cuda[3:]]
    assert_eq(0x70 in addresses_after_3, False,
              "i2c_init: no further writes to 0x70 after the first controller init")

    # Regression: confirm that the old single-write approach would miss the oscillator.
    # A single 0x21 at index 0 would be the only oscillator command — 0x70 would get
    # brightness but never receive a working oscillator-enable on VESC 7.00.
    single_write_0x21_count = sum(1 for addr, data in cmds if addr == 0x70 and data == [0x21])
    assert_eq(single_write_0x21_count, 2,
              "i2c_init: exactly 2 oscillator-enable commands sent to 0x70 (not 1)")


def test_blacktip_display_timeout_sequence():
    """A lost off command must not leave the last display frame latched."""
    print("\n=== Testing defensive Blacktip display timeout sequence ===")

    cmds = simulate_blacktip_display_timeout_sequence()

    assert_eq(cmds[0], (0x70, [0] * 16),
              "display_timeout: blank framebuffer is written before display-off")
    assert_eq(cmds[1], (0x70, [0x80]),
              "display_timeout: first display-off command targets the Blacktip display")
    assert_eq(cmds[2], (0x70, [0x80]),
              "display_timeout: display-off command is retried")
    assert_eq(len(cmds), 3,
              "display_timeout: sequence contains blank plus two off writes")


def test_state_metrics_reset():
    """
    Test the state_metrics_reset behaviour after the setvar refactor.

    In the PR, the function changed from using `define` (which re-creates bindings)
    to `setvar` (which mutates pre-existing heap globals). The Python simulation
    requires the keys to already exist in the state store, mirroring the new
    requirement that mutable globals be pre-declared between the const blocks.
    """
    print("\n=== Testing state_metrics_reset (setvar refactor) ===")

    STATE_UNINITIALIZED = -1

    # Pre-declare all three mutable heap globals (as required by VESC 7.00 layout)
    state_store = {
        'state_last_state': 99,      # some previous state
        'state_last_change_time': 0,
        'state_last_reason': 'old_reason',
    }

    state_metrics_reset_simulate(state_store)

    assert_eq(state_store['state_last_state'], STATE_UNINITIALIZED,
              "state_metrics_reset: state_last_state reset to STATE_UNINITIALIZED (-1)")
    assert_eq(state_store['state_last_change_time'], 'NOW',
              "state_metrics_reset: state_last_change_time updated (systime sentinel)")
    assert_eq(state_store['state_last_reason'], 'startup',
              "state_metrics_reset: state_last_reason set to 'startup'")

    # All three keys must already exist (pre-declared globals) — setvar does not create new bindings
    assert_eq('state_last_state' in state_store, True,
              "state_metrics_reset: state_last_state key pre-exists (setvar pattern)")
    assert_eq('state_last_change_time' in state_store, True,
              "state_metrics_reset: state_last_change_time key pre-exists (setvar pattern)")
    assert_eq('state_last_reason' in state_store, True,
              "state_metrics_reset: state_last_reason key pre-exists (setvar pattern)")

    # Calling reset twice leaves deterministic values (idempotent aside from systime)
    state_metrics_reset_simulate(state_store)
    assert_eq(state_store['state_last_state'], STATE_UNINITIALIZED,
              "state_metrics_reset: idempotent — second call still gives UNINITIALIZED")
    assert_eq(state_store['state_last_reason'], 'startup',
              "state_metrics_reset: idempotent — second call still gives 'startup'")


def test_five_click_settings_and_migration():
    print("\n=== Testing five-click setting persistence and migration ===")

    defaults = bytes([0] * 33)
    assert_eq(defaults[32], 0, "five-click setting: default disabled")

    eeprom = {index: (index * 7) % 256 for index in range(32)}
    before = dict(eeprom)
    migrated = migrate_eeprom_v3(eeprom, 2)
    assert_eq(migrated[32], 0, "EEPROM v3: slot 32 initialized disabled")
    assert_eq({index: migrated[index] for index in range(32)}, before,
              "EEPROM v3: slots 0-31 preserved")
    assert_eq(migrated[127], 3, "EEPROM v3: schema marker advanced to 3")

    current = bytes(list(range(32)) + [1])
    accepted, received = receive_settings_simulate(migrated, current)
    assert_eq(accepted, True, "settings receive: 33-byte buffer accepted")
    assert_eq(received[32], 1, "settings receive: slot 32 round-trips enabled")

    accepted, rejected = receive_settings_simulate(received, bytes(32))
    assert_eq(accepted, False, "settings receive: buffer shorter than 33 rejected")
    assert_eq(rejected, received, "settings receive: rejected buffer changes nothing")


def test_production_defaults_reset():
    """Production profiles must start from complete firmware defaults."""
    print("\n=== Testing production defaults reset ===")
    root = Path(__file__).resolve().parents[1]
    ui_source = (root / 'ui.qml').read_text()

    assert_eq('function reset_defaults_for_profile(profile)' in ui_source, True,
              "production reset: common asynchronous reset entrypoint exists")
    assert_eq('mCommands.getMcconfDefault()' in ui_source and
               'mCommands.getAppConfDefault()' in ui_source, True,
               "production reset: requests complete motor and app defaults")
    mc_connections_start = ui_source.index('target: mMcConf')
    app_connections_start = ui_source.index('target: mAppConf')
    reset_start = ui_source.index('function reset_defaults_for_profile(profile)')
    reset_end = ui_source.index('function apply_reset_profile()', reset_start)
    assert_eq('mCommands.getAppConfDefault()' not in ui_source[reset_start:reset_end], True,
               "production reset: does not overlap motor and app default requests")
    assert_eq('mCommands.getAppConfDefault()' in ui_source[mc_connections_start:app_connections_start], True,
               "production reset: requests app defaults after motor defaults arrive")
    assert_eq('profileMotorDefaultsLoaded &&\n                    !profileAppDefaultsLoaded' in ui_source[app_connections_start:], True,
               "production reset: accepts app defaults only after motor defaults")
    assert_eq('!profileMotorDefaultsLoaded || !profileAppDefaultsLoaded' in ui_source, True,
              "production reset: waits for both default responses")
    assert_eq(ui_source.index('mCommands.getMcconfDefault()') <
              ui_source.index('function apply_defaults_blacktip()'), True,
              "production reset: default retrieval precedes Blacktip overrides")
    assert_eq('function reset_defaults_blacktip() {\n        reset_defaults_for_profile("blacktip")' in ui_source,
              True, "production reset: Blacktip uses the common reset")
    assert_eq('function reset_defaults_cudax() {\n        reset_defaults_for_profile("cudax")' in ui_source,
              True, "production reset: CudaX uses the common reset")
    assert_eq('HARDWARE_TEST_FIXTURE' in ui_source, False,
              "production reset: contains no test-fixture model")


def test_release_documentation():
    """Verify generated package metadata derives its version from the source README."""
    print("\n=== Testing release documentation ===")
    root = Path(__file__).resolve().parents[1]
    readme = (root / 'README.md').read_text()

    assert_eq('**After updating VESC controller firmware, use Reset Defaults**' in readme,
              True, "release documentation: distinguishes controller firmware updates")
    assert_eq('**A routine Blacktip DPV package update does not require Reset Defaults**' in readme,
              True, "release documentation: routine package updates do not require a reset")

    ui_source = (root / 'ui.qml').read_text()
    assert_eq('text: "Reset Defaults*"' in ui_source, True,
               "release documentation: UI uses the documented button label")

    version_match = re.search(r'^\*\*Version:\*\* (\S+)$', readme, re.MULTILINE)
    assert_eq(version_match is not None, True,
              "release documentation: declares a source version")
    if version_match is None:
        return

    subprocess.run([root / 'tools' / 'update_version.sh'], cwd=root, check=True)
    generated_readme = (root / 'README.dist.md').read_text()
    generated_ui = (root / 'ui.dist.qml').read_text()
    generated_readme_match = re.search(r'^\*\*Version:\*\* `([^`]+)`$',
                                       generated_readme, re.MULTILINE)
    generated_ui_match = re.search(
        r'readonly property string const_BLACKTIP_DPV_VERSION: "([^"]+)"',
        generated_ui)

    assert_eq(generated_readme_match is not None, True,
              "release metadata: generated README has a version")
    assert_eq(generated_ui_match is not None, True,
              "release metadata: generated UI has a version")
    if generated_readme_match is not None and generated_ui_match is not None:
        generated_version = generated_readme_match.group(1)
        assert_eq(generated_version.startswith(version_match.group(1) + '-'), True,
                  "release metadata: generated version derives from README version")
        assert_eq(generated_ui_match.group(1), generated_version,
                  "release metadata: generated README and UI use the same version")

    package_description = (root / 'pkgdesc.qml').read_text()
    assert_eq('pkgDescriptionMd: "README.dist.md"' in package_description and
              'pkgQml: "ui.dist.qml"' in package_description, True,
              "release metadata: package uses generated versioned artefacts")


def _safe_shutdown_state():
    return {
        'enable_five_click_shutdown': 1,
        'hw_name': '60_MK5',
        'fw_ver': (7, 0, 2),
        'speed': SPEED_OFF,
    }


def test_five_click_shutdown_decision():
    print("\n=== Testing five-click shutdown safety decision ===")
    safe = _safe_shutdown_state()

    cases = [
        ('feature disabled', 'enable_five_click_shutdown', 0),
        ('non-MK5 hardware', 'hw_name', '60'),
        ('unsupported beta 1 firmware', 'fw_ver', (7, 0, 1)),
        ('speed not off', 'speed', 4),
    ]
    for name, key, value in cases:
        state = dict(safe)
        state[key] = value
        assert_eq(request_five_click_shutdown_simulate(state), 0,
                  f"five clicks: {name} does not request shutdown")

    assert_eq(request_five_click_shutdown_simulate(safe), 1,
              "five clicks: valid stopped MK5 requests shutdown exactly once")
    stable = dict(safe, fw_ver=(7, 0, 0))
    assert_eq(request_five_click_shutdown_simulate(stable), 1,
              "firmware guard: stable 7.00 is supported")
    assert_eq(firmware_supports_shutdown((7, 1, 0)), True,
              "firmware guard: later 7.x release supported")
    assert_eq(firmware_supports_shutdown((7, 0)), False,
              "firmware guard: missing build component fails safe")


def test_startup_trigger_readiness():
    print("\n=== Testing startup trigger readiness ===")

    assert_eq(trigger_click_accepted(0, 0, 1), False,
              "startup trigger: presses are ignored before readiness")
    assert_eq(trigger_arm_after_ready_sample(1, 0), 1,
              "startup trigger: a post-ready released trigger is armed")
    assert_eq(trigger_arm_after_ready_sample(1, 1), 0,
              "startup trigger: a post-ready held trigger remains blocked")
    assert_eq(trigger_arm_after_release(1, 1), 0,
              "startup trigger: a held trigger does not arm at readiness")
    assert_eq(trigger_click_accepted(1, 0, 1), False,
              "startup trigger: held pre-ready press cannot start motor")
    assert_eq(trigger_arm_after_release(1, 0), 1,
              "startup trigger: release arms input after readiness")
    assert_eq(trigger_click_accepted(1, 1, 1), True,
              "startup trigger: new press after release is accepted")

    source = (Path(__file__).resolve().parents[1] / 'blacktip_dpv.lisp').read_text()
    state_off_start = source.index('(defun state_handler_off')
    state_off_end = source.index('(defun smart_cruise_upgrade_if_needed', state_off_start)
    state_off_source = source[state_off_start:state_off_end]
    assert_eq('(and (= trigger_input_ready 1) (= trigger_armed 1) (= sw_pressed 1))' in state_off_source,
              True, "startup trigger: stopped state requires ready and armed input")
    main_start = source.index('(defun main')
    trigger_loop_start = source.index('(start_trigger_loop)', main_start)
    ready_start = source.index("(setvar 'trigger_input_ready 1)", main_start)
    state_machine_start = source.index('(state_transition_to STATE_OFF "startup"', main_start)
    startup_tune_start = source.index('(spawn THREAD_STACK_CLICK_BEEP play_imperial_march)', main_start)
    assert_eq(trigger_loop_start < ready_start < state_machine_start < startup_tune_start, True,
              "startup trigger: readiness follows trigger setup but precedes optional audio")
    trigger_function_start = source.index('(defun start_trigger_loop')
    initial_gpio_sample = source.index("(gpio-read 'pin-ppm)", trigger_function_start)
    assert_eq(initial_gpio_sample < ready_start, True,
              "startup trigger: initial GPIO sample precedes readiness")
    post_ready_gpio_sample = source.index("(gpio-read 'pin-ppm)", ready_start)
    assert_eq(ready_start < post_ready_gpio_sample < state_machine_start, True,
              "startup trigger: released input is armed from a post-ready sample")


def test_click_and_beep_regressions():
    print("\n=== Testing click and beep regressions ===")
    # Existing stopped-state actions: 1=no-op, 2=start, 3=jump, 4=untangle.
    actions = {1: 'no-op', 2: 'start', 3: 'jump', 4: 'untangle', 5: 'shutdown'}
    assert_eq([actions[count] for count in range(1, 5)],
              ['no-op', 'start', 'jump', 'untangle'],
              "click actions: one through four unchanged")
    assert_eq(actions.get(6, 'unsupported'), 'unsupported',
              "click actions: six or more remain unsupported")

    source = (Path(__file__).resolve().parents[1] / 'blacktip_dpv.lisp').read_text()
    assert_eq('(define CLICKS_SHUTDOWN 5)' in source, True,
              "click namespace: shutdown count is five")
    assert_eq('(define BEEP_SMART_CRUISE_CHANGE 5)' in source, True,
              "beep namespace: Smart Cruise event remains five")
    assert_eq("(setvar 'click_beep BEEP_SMART_CRUISE_CHANGE)" in source, True,
              "Smart Cruise beep behaviour uses separated event constant")
    assert_eq('(shutdown true)' in source, True,
              "shutdown action: hardware shutdown extension used")
    assert_eq('(str-cmp hw_name "60_MK5")' in source, True,
              "shutdown capability: runtime recognizes the reported MK5 hardware name")
    assert_eq('(shutdown-hold ' in source, False,
              "shutdown action: shutdown-hold is never called")

    shutdown_start = source.index('(defun request_five_click_shutdown')
    shutdown_end = source.index('; Settings initialization', shutdown_start)
    shutdown_source = source[shutdown_start:shutdown_end]
    confirmation_steps = [
        "(setvar 'disp_num DISPLAY_OFF)",
        '(foc-beep 700 SHUTDOWN_TONE_DURATION beeps_vol)',
        '(foc-beep 575 SHUTDOWN_TONE_DURATION beeps_vol)',
        '(foc-beep 450 SHUTDOWN_TONE_DURATION beeps_vol)',
        '(foc-beep 325 SHUTDOWN_TONE_DURATION beeps_vol)',
        '(shutdown true)',
    ]
    confirmation_positions = [shutdown_source.index(step) for step in confirmation_steps]
    assert_eq(confirmation_positions, sorted(confirmation_positions),
              "shutdown confirmation: power symbol and descending tones precede shutdown")

    readme_source = (Path(__file__).resolve().parents[1] / 'README.md').read_text()
    deep_sleep_source = (Path(__file__).resolve().parents[1] / 'DEEP_SLEEP.md').read_text()
    assert_eq('OFF&#95;AFTER&#95;' in deep_sleep_source, True,
               "Deep Sleep guide rendering: shutdown settings use Qt-safe underscores")
    for video_id in ('l-zNqO2AnJg', 'Bld37fwkB-8', '1F8GzoRw_EM'):
        assert_eq(f'https://www.youtube.com/watch?v={video_id}' in deep_sleep_source, True,
                   f"Deep Sleep guide: links the instructional video {video_id}")
    assert_eq('./DEEP_SLEEP.md' in readme_source, True,
               "README navigation: links to the Deep Sleep guide")
    assert_eq('blacktip\\_dpv' in readme_source, False,
              "README rendering: package filenames do not use broken backslash escapes")
    assert_eq('\\* this model' in readme_source, False,
              "README rendering: Bluetooth note does not use a broken star escape")
    assert_eq('\u2705' in readme_source, False,
              "README rendering: unsupported check-mark glyphs are absent")

    ui_source = (Path(__file__).resolve().parents[1] / 'ui.qml').read_text()
    assert_eq(ui_source.count('new ArrayBuffer(33)'), 3,
              "QML settings: write and both reset buffers are 33 bytes")
    assert_eq(ui_source.count('setUint8(32, 0)'), 2,
              "QML defaults: Blacktip and CudaX disable five-click shutdown")
    payload_guard = 'if (dv.byteLength < 31)'
    first_settings_read = 'hardware_configuration.currentIndex =  dv.getUint8(19)'
    assert_eq(payload_guard in ui_source and
              ui_source.index(payload_guard) < ui_source.index(first_settings_read), True,
              "QML settings: truncated baseline payload is rejected before any reads")
    assert_eq('dv.byteLength > 32 && dv.getUint8(32) === 1' in ui_source, True,
              "QML settings: missing slot 32 safely defaults shutdown to disabled")
    assert_eq('params.hw === "60_MK5"' in ui_source, True,
              "QML shutdown capability: VESC Tool MK5 hardware name is recognized")
    assert_eq('enabled: fiveClickShutdownHardwareSupported && fiveClickShutdownFirmwareSupported' in ui_source,
              True, "QML shutdown option: unsupported hardware or firmware disables it")


# =============================================================================
# Packaged Lisp stripper (tools/strip_lisp.py)
# =============================================================================

STRIP_SCRIPT = Path(__file__).resolve().parents[1] / 'tools' / 'strip_lisp.py'
LISP_SOURCE = Path(__file__).resolve().parents[1] / 'blacktip_dpv.lisp'


def _load_stripper():
    """Import the very module the Makefile runs, not a copy of its logic."""
    spec = importlib.util.spec_from_file_location('strip_lisp', STRIP_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _run_stripper_cli(src_bytes, work_dir, dst_exists=False):
    """Run the stripper CLI on bytes. Returns (exit code, stderr, dst bytes)."""
    src = Path(work_dir) / 'in.lisp'
    dst = Path(work_dir) / 'out.lisp'
    src.write_bytes(src_bytes)
    if dst_exists:
        dst.write_bytes(b'stale output\n')
    elif dst.exists():
        dst.unlink()
    result = subprocess.run([sys.executable, str(STRIP_SCRIPT), str(src), str(dst)],
                            capture_output=True, text=True)
    out = dst.read_bytes() if dst.exists() else None
    return result.returncode, result.stderr, out


_FORM_SPLIT = re.compile(rb"[()\[\]{}'`]|,@|,|[^()\[\]{}'`,]+")


def _forms(stripper, data):
    """Nested form structure of a Lisp text built from the reader-level tokens.

    Strings and char literals stay one byte-exact leaf; atoms are split at
    brackets and quote characters. Line numbers are included, so a form that
    moved to another line is a difference.
    """
    stack = [[]]
    for line, kind, raw in stripper.tokenize(data)[0]:
        if kind != 'atom':
            stack[-1].append((line, kind, raw))
            continue
        for piece in _FORM_SPLIT.findall(raw):
            if piece in (b'(', b'[', b'{'):
                stack.append([])
            elif piece in (b')', b']', b'}'):
                done = stack.pop() if len(stack) > 1 else []
                stack[-1].append(done)
            else:
                stack[-1].append((line, 'atom', piece))
    return stack


def _tokens_equal(stripper, a, b):
    return stripper.tokenize(a)[0] == stripper.tokenize(b)[0]


def _differs(stripper, original, damaged):
    """True when the comparator (self-check or token comparison) objects."""
    try:
        stripper.verify(original, damaged)
    except stripper.StripError:
        return True
    return False


def _strip_or_report(stripper, data, name):
    """strip_checked, turning a StripError into a reported test failure."""
    try:
        return stripper.strip_checked(data)
    except stripper.StripError as e:
        assert_eq(f'{e.line}:{e.col}: {e.message}', 'stripped without error', name)
        return None, None


def test_strip_lisp_real_file():
    print("\n--- strip_lisp: real source ---")
    stripper = _load_stripper()
    src = LISP_SOURCE.read_bytes()
    out, removed = _strip_or_report(stripper, src, "strip real file: stripper and self-check accept the source")
    if out is None:
        return

    assert_eq(len(out) < len(src), True, "strip real file: output is smaller")
    assert_eq(out.count(b'\n'), src.count(b'\n'), "strip real file: line count identical")
    assert_eq(out.endswith(b'\n'), src.endswith(b'\n'), "strip real file: trailing newline preserved")
    src_tokens = stripper.tokenize(src)[0]
    out_tokens = stripper.tokenize(out)[0]
    assert_eq(len(src_tokens) > 1000, True, "strip real file: reader found the program (not a vacuous comparison)")
    assert_eq([(k, r) for _, k, r in out_tokens], [(k, r) for _, k, r in src_tokens],
              "strip real file: token sequence identical")
    assert_eq(out_tokens, src_tokens, "strip real file: every token on the same line")
    assert_eq(_forms(stripper, out), _forms(stripper, src), "strip real file: form structure identical")

    src_strings = [r for _, k, r in src_tokens if k == 'string']
    out_strings = [r for _, k, r in out_tokens if k == 'string']
    assert_eq(len(src_strings) > 0 and out_strings == src_strings, True,
              "strip real file: every string literal byte-identical")

    def directive_lines(data):
        return [(n, l) for n, l in enumerate(data.split(b'\n'), 1)
                if l.startswith((b'@const-start', b'@const-end'))
                or l.lstrip().startswith((b'@const-start', b'@const-end'))]

    def import_lines(data):
        return [l.strip() for l in data.split(b'\n') if l.lstrip().startswith(b'(import ')]

    src_dir = directive_lines(src)
    out_dir = directive_lines(out)
    assert_eq(len(src_dir) >= 4, True, "strip real file: source has the const directives")
    assert_eq([l.rstrip(b'\r') for _, l in out_dir], [l.strip() for _, l in src_dir],
              "strip real file: directive lines kept in order, in column 0")
    assert_eq([n for n, _ in out_dir], [n for n, _ in src_dir],
              "strip real file: directive lines on the same line numbers")
    assert_eq(len(import_lines(src)) >= 1 and import_lines(out) == import_lines(src), True,
              "strip real file: import lines kept in order")
    assert_eq(stripper.vesc_tool_imports(out)[0][1:3], stripper.vesc_tool_imports(src)[0][1:3],
              "strip real file: vesc_tool import path and tag unchanged")

    again, _ = stripper.strip_checked(out)
    assert_eq(again, out, "strip real file: stripping the output changes nothing (idempotent)")

    with tempfile.TemporaryDirectory() as work:
        code, err, cli_out = _run_stripper_cli(src, work)
        assert_eq((code, cli_out), (0, out), "strip real file: command line output equals the library output")


# (name, input, expected stripped output); each is also checked for token
# equivalence and line-count equality.
STRIP_CASES = [
    ("semicolon inside a string",
     b'(print "a;b") ; c\n', b'(print "a;b")\n'),
    ("string with leading-space continuation line",
     b'  (print "abc\n   def  \n  ghi")  ; c\n', b'(print "abc\n   def  \n  ghi")\n'),
    ("escaped quote inside a string",
     b'(a "x\\"y;z") ; c\n', b'(a "x\\"y;z")\n'),
    ("escaped backslash at the end of a string",
     b'  (b "p\\\\") ; q ; "r\n', b'(b "p\\\\")\n'),
    ("char literal semicolon",
     b'  (f \\#;) ; c\n', b'(f \\#;)\n'),
    ("char literal double quote",
     b'  (g \\#") ; "c\n  (h 1)\n', b'(g \\#")\n(h 1)\n'),
    ("char literal space",
     b'  (h \\# ) ; c\n', b'(h \\# )\n'),
    ("char literal space at end of line before a comment",
     b'  (h \\# ; c\n  )\n', b'(h \\# \n)\n'),
    ("char literal escapes",
     b'(list \\#\\n \\#\\" \\#\\\\ \\#\\s) ; c\n', b'(list \\#\\n \\#\\" \\#\\\\ \\#\\s)\n'),
    ("comment with quotes and apostrophes",
     b'(a 1) ; don\'t "quote\n(b 2) ; "x\n', b'(a 1)\n(b 2)\n'),
    ("comment-only line after a string line",
     b'(a "x")\n    ; it\'s "odd\n(b)\n', b'(a "x")\n\n(b)\n'),
    ("tab indentation and trailing tab before a comment",
     b'\t\t(a)\t; c\n', b'(a)\n'),
    ("interior tab and spacing are kept",
     b'  (a\tb    c)\n', b'(a\tb    c)\n'),
    ("CRLF line endings",
     b'  (a) ; c\r\n; only\r\n\r\n  (b "x\r\n  y")\r\n', b'(a)\r\n\r\n\r\n(b "x\r\n  y")\r\n'),
    ("no trailing newline after code",
     b'  (a) ; c', b'(a)'),
    ("no trailing newline after a comment line",
     b'(a)\n  ; c', b'(a)\n'),
    ("comment-only and blank lines become empty lines",
     b'; c\n   \n\t\n(a)\n', b'\n\n\n(a)\n'),
    ("const directives and import",
     b'  @const-start ; c\n   (import "generated/x.bin" \'x) ; c\n\t@const-end\n(a)\n',
     b'@const-start\n(import "generated/x.bin" \'x)\n@const-end\n(a)\n'),
    ("trailing whitespace before a comment",
     b'(a)   \t ; c\n', b'(a)\n'),
    ("trailing whitespace without a comment",
     b'(a)   \n', b'(a)\n'),
    ("trailing whitespace inside a string is data",
     b'(p "ab  \n  cd")\n', b'(p "ab  \n  cd")\n'),
    ("quote and quasiquote forms",
     b"  '(a b) ; c\n  `(a ,b ,@c)\n", b"'(a b)\n`(a ,b ,@c)\n"),
    ("UTF-8 in a comment is dropped, in a string is kept",
     '  (a "\u2013") ; \u2014 dash\n'.encode(), '(a "\u2013")\n'.encode()),
    ("already stripped input is unchanged",
     b'(a)\n(b "c")\n', b'(a)\n(b "c")\n'),
    ("empty file", b'', b''),
]

# (name, input, line, column) for input the stripper must reject.
STRIP_ERRORS = [
    ("unterminated string", b'(a)\n  (b "abc\n(c)\n', 2, 6),
    ("unterminated string at end of file", b'"abc', 1, 1),
    ("invalid escape in a string", b'(a "x\\qy")\n', 1, 6),
    ("backslash at the end of a line inside a string", b'(a "x\\\n y")\n', 1, 6),
    ("bare backslash", b'(a \\x)\n', 1, 4),
    ("unterminated char literal", b'(a \\#\n', 1, 4),
    ("unterminated char literal at end of file", b'(a \\#', 1, 4),
    ("unknown char literal escape", b'(a \\#\\q)\n', 1, 4),
    ("control character in code", b'(a)\n  (b\x01)\n', 2, 5),
    ("non-ASCII byte in code", b'(caf\xc3\xa9)\n', 1, 5),
    ("lone carriage return", b'(a)\r(b)\n', 1, 4),
    ("mixed line endings", b'(a)\r\n(b)\n', 2, 4),
    ("shebang first line", b'#!/bin/lbm\n(a)\n', 1, 1),
    ("import with a quote in its trailing comment",
     b'(import "x.bin" \'x) ; "q"\n', 1, 1),
    ("tab-indented import that vesc_tool would not see",
     b'\t(import "x.bin" \'x)\n', 1, 1),
]


def test_strip_lisp_edge_cases():
    print("\n--- strip_lisp: edge cases ---")
    stripper = _load_stripper()

    for name, src, expected in STRIP_CASES:
        out, _ = _strip_or_report(stripper, src, f"strip edge case, accepted: {name}")
        if out is None:
            continue
        assert_eq(out, expected, f"strip edge case, exact text: {name}")
        same = (out.count(b'\n') == src.count(b'\n')
                and _tokens_equal(stripper, src, out)
                and _forms(stripper, src) == _forms(stripper, out))
        assert_eq(same, True, f"strip edge case, tokens and lines equal: {name}")

    with tempfile.TemporaryDirectory() as work:
        for name, src, line, col in STRIP_ERRORS:
            try:
                stripper.strip_checked(src)
                got = None
            except stripper.StripError as e:
                got = (e.line, e.col)
            assert_eq(got, (line, col), f"strip error position: {name}")

            code, err, out = _run_stripper_cli(src, work, dst_exists=True)
            assert_eq((code != 0, f'in.lisp:{line}:{col}: error:' in err, out),
                      (True, True, None),
                      f"strip command line: non-zero exit, file:line:col, stale output removed: {name}")
        leftovers = sorted(p.name for p in Path(work).iterdir() if p.name not in ('in.lisp',))
        assert_eq(leftovers, [], "strip command line: failed runs leave no temporary or output file")

        code, err, out = _run_stripper_cli(b'', work)
        assert_eq((code, out), (0, b''), "strip command line: output equal to input is not an error")

        src = Path(work) / 'missing.lisp'
        result = subprocess.run([sys.executable, str(STRIP_SCRIPT), str(src), str(Path(work) / 'o.lisp')],
                                capture_output=True, text=True)
        assert_eq((result.returncode != 0, (Path(work) / 'o.lisp').exists()), (True, False),
                  "strip command line: unreadable source fails")

        # --map: stripped column + removed indentation = source column
        (Path(work) / 'm.lisp').write_bytes(b'(a)\n    (b "x\n  y") (c)\n\t\t(d)\n')
        def mapped(line, col):
            r = subprocess.run([sys.executable, str(STRIP_SCRIPT), '--map', str(line), str(col),
                                str(Path(work) / 'm.lisp')], capture_output=True, text=True)
            return r.stdout.strip()
        assert_eq([mapped(1, 2), mapped(2, 1), mapped(2, 4), mapped(3, 1), mapped(4, 1)],
                  ['2', '5', '8', '1', '3'],
                  "strip --map: source column = stripped column + removed indentation")


def test_strip_lisp_mutation_check():
    print("\n--- strip_lisp: the comparator is not vacuous ---")
    stripper = _load_stripper()
    src = LISP_SOURCE.read_bytes()
    out, _ = _strip_or_report(stripper, src, "mutation baseline: stripper accepts the source")
    if out is None:
        return
    assert_eq(_differs(stripper, src, out), False, "mutation baseline: genuine output passes")

    # drop a character inside a string literal
    tok = next(t for t in stripper.tokenize(out)[0] if t[1] == 'string' and len(t[2]) > 6)
    pos = out.index(tok[2]) + 3
    assert_eq(_differs(stripper, src, out[:pos] + out[pos + 1:]), True,
              "mutation: dropping a character inside a string is detected")

    # remove a closing parenthesis
    pos = out.rindex(b')')
    assert_eq(_differs(stripper, src, out[:pos] + out[pos + 1:]), True,
              "mutation: removing a closing parenthesis is detected")

    # move a token to another line (line numbers are part of the comparison)
    pos = out.index(b'\n(')
    assert_eq(_differs(stripper, src, out[:pos] + b' ' + out[pos + 1:] + b'\n'), True,
              "mutation: joining two lines is detected")

    # collapse leading spaces inside a multi-line string
    multi = b'(print "abc\n      def")\n(x)\n'
    good, _ = _strip_or_report(stripper, multi, "mutation baseline: multi-line string accepted")
    assert_eq(good, multi, "mutation baseline: multi-line string kept as is")
    damaged = good.replace(b'\n      def', b'\n def')
    assert_eq(_differs(stripper, multi, damaged), True,
              "mutation: collapsing leading spaces inside a string is detected")
    assert_eq(_tokens_equal(stripper, multi, damaged), False,
              "mutation: the plain token comparison also sees the collapsed string")

    # leftover comment, indentation and a missing directive are not 'stripped'
    base = b'(a)\n@const-start\n(b)\n'
    assert_eq(_differs(stripper, base, b'(a) ; c\n@const-start\n(b)\n'), True,
              "mutation: a comment left in the output is detected")
    assert_eq(_differs(stripper, base, b'(a)\n @const-start\n(b)\n'), True,
              "mutation: indentation left in the output is detected")
    assert_eq(_differs(stripper, base, b'(a)\n\n(b)\n'), True,
              "mutation: a dropped directive is detected")


def test_strip_lisp_native_reader():
    """Optional: compare the forms the LispBM reader produces for both files.

    Needs a native LispBM repl (for example the one built from the bldc
    release_7_00 tree, lispBM/lispBM/repl). Set LBM_REPL to its path. The test
    is skipped, with a printed notice, when LBM_REPL is not set.
    """
    print("\n--- strip_lisp: native LispBM reader ---")
    repl = os.environ.get('LBM_REPL', '')
    if not repl or not os.access(repl, os.X_OK):
        print("SKIPPED: set LBM_REPL to a native LispBM repl binary to compare the parsed "
              "forms of the source and the stripped file")
        return
    stripper = _load_stripper()
    src = LISP_SOURCE.read_bytes()
    out, _ = _strip_or_report(stripper, src, "native reader: stripper accepts the source")
    if out is None:
        return
    dump = ('(define prog (read-program (load-file (fopen "%s" "r"))))\n'
            '(define fh (fopen "%s" "w"))\n'
            '(define n 0)\n'
            '(loopforeach f prog (progn (fwrite fh (flatten f)) (setq n (+ n 1))))\n'
            '(fclose fh)\n'
            '(print (list (quote forms) n))\n')
    results = []
    with tempfile.TemporaryDirectory() as work:
        for label, data in (('source', src), ('stripped', out)):
            lisp = os.path.join(work, label + '.lisp')
            flat = os.path.join(work, label + '.bin')
            script = os.path.join(work, label + '.dump.lisp')
            with open(lisp, 'wb') as f:
                f.write(data)
            with open(script, 'w') as f:
                f.write(dump % (lisp, flat))
            run = subprocess.run([repl, '-H', '200000', '-M', '524288', '--terminate', '--silent',
                                  '--history_file=', '-s', script], capture_output=True, text=True)
            blob = open(flat, 'rb').read() if os.path.exists(flat) else None
            results.append((run.returncode, blob))
    assert_eq(results[0][0] == 0 and results[0][1] is not None and len(results[0][1]) > 1000, True,
              "native reader: source parsed into forms")
    assert_eq(results[1], results[0], "native reader: parsed forms of the stripped file identical to the source")



# =============================================================================
# Display path in a native LispBM repl (optional, needs LBM_REPL)
# =============================================================================

HARNESS_LOOP_OPEN = '(loopwhile-thd THREAD_STACK_DISPLAY t {'
HARNESS_IMPORT = '(import "generated/display_lut.bin" \'display_lut_bin)'
HARNESS_STUBS = """(define puts (lambda (s) nil))
(define loop_budget 0)
(define leds_g -1)
"""
# Driver for the cases. Each case runs ONE iteration of the real display loop
# synchronously (the thread is replaced by a loop that runs loop_budget times,
# so nothing races with the driver) and prints every i2c transfer.
HARNESS_DRIVER = """
(defun smart_cruise_leds_count () leds_g)
(defun i2c-tx-rx (addr data) (progn (print (list 'i2c addr data)) 0))
(defun run_case (st flip r1 r2 d leds) {
    (print (list 'case st flip r1 r2 d leds))
    (setvar 'scooter_type st)
    (setvar 'cudax_flip flip)
    (setvar 'rotation r1)
    (setvar 'rotation2 r2)
    (setvar 'disp_num d)
    (setvar 'last_disp_num -2)
    (setvar 'leds_g leds)
    (setvar 'loop_budget 1)
    (start_display_output_loop)
})
"""


def display_harness_script(source, lut, body):
    """Build a repl script from the real Lisp source.

    Everything from the boot sequence at the end of the file is dropped, the
    display table is defined from the given bytes instead of imported, the
    display loop sleeps 1 ms and runs one iteration per call instead of
    forever in a thread, and the timer bar LED count comes from a variable.
    The code under test is otherwise the source text unchanged. body is the
    Lisp that exercises it.
    """
    assert source.count(HARNESS_IMPORT) == 1 and source.count(HARNESS_LOOP_OPEN) == 1
    assert source.count('(define SLEEP_UI_UPDATE 0.25)') == 1
    end = source.rindex('\n(init)\n')
    text = source[:end] + '\n'
    define = '(define display_lut_bin (bufcreate %d))\n' % len(lut)
    define += ''.join('(bufset-u8 display_lut_bin %d %d)\n' % (i, b) for i, b in enumerate(lut) if b)
    text = text.replace(HARNESS_IMPORT, define)
    text = text.replace(HARNESS_LOOP_OPEN,
                        "(loopwhile (> loop_budget 0) {(setvar 'loop_budget (- loop_budget 1))")
    text = text.replace('(define SLEEP_UI_UPDATE 0.25)', '(define SLEEP_UI_UPDATE 0.001)')
    return HARNESS_STUBS + text + HARNESS_DRIVER + body


def run_display_harness(repl, script_text, timeout=600):
    with tempfile.TemporaryDirectory() as work:
        script = os.path.join(work, 'display.lisp')
        with open(script, 'w') as f:
            f.write(script_text)
        run = subprocess.run([repl, '-H', '200000', '-M', '1048576', '-C', '131072', '--terminate',
                              '--silent', '--history_file=', '-s', script],
                             capture_output=True, text=True, timeout=timeout)
    return run


def _lisp_list(values):
    return '(list ' + ' '.join(str(v) for v in values) + ')'


def parse_i2c_log(output):
    """Return [(case tuple, [(addr, data), ...]), ...] from the harness output."""
    cases = []
    for line in output.splitlines():
        line = ''.join(ch for ch in line if ' ' <= ch <= '~')
        match = re.match(r'^\(case ([-\d ]+)\)$', line)
        if match:
            cases.append((tuple(int(v) for v in match.group(1).split()), []))
            continue
        match = re.match(r'^\(i2c (\d+) (?:\[([\d ]*)\]|\(([\d ]*)\))\)$', line)
        if match and cases:
            data = match.group(2) if match.group(2) is not None else match.group(3)
            cases[-1][1].append((int(match.group(1)), [int(v) for v in data.split()]))
    return cases


def display_screen_address(scooter_type, cudax_flip, disp_num):
    """Mirror the screen selection in start_display_output_loop."""
    address = 0x70
    if scooter_type == 1:
        first_group = disp_num in (0, 1, 2, 3) or disp_num > 17
        if first_group and cudax_flip == 1:
            address = 0x71
        if not first_group and cudax_flip != 1:
            address = 0x71
    return address


def expected_display_traffic(frames, case):
    """What the display loop must send for a case.

    The rotation 0 row of the display (the 33 CSV rows), turned by the
    reference rotation, with the hand-written per-rotation timer bar overlay on
    the turned frame, then the display-on command. This is also what the
    earlier firmware, with a table of pre-rotated rows, sent.
    """
    scooter_type, cudax_flip, rotation, rotation2, disp_num, leds = case
    address = display_screen_address(scooter_type, cudax_flip, disp_num)
    used = rotation if address == 0x70 else rotation2
    base = [0] * 16 if disp_num == 99 else frames[disp_num]
    return [(address, legacy_timer_bar_overlay(rotate_frame(base, used), leds, used)), (address, [0x81])]


def display_cases(frames_to_draw=tuple(range(33)) + (99,), leds_counts=tuple(range(-1, 9))):
    cases = []
    for d in frames_to_draw:
        for leds in leds_counts:
            for r1 in range(4):
                cases.append((0, 0, r1, (r1 + 2) % 4, d, leds))
            for flip in (0, 1):
                for r1 in range(4):
                    for r2 in range(4):
                        cases.append((1, flip, r1, r2, d, leds))
    return cases


def display_case_driver(cases):
    return ''.join('(run_case %d %d %d %d %d %d)\n' % case for case in cases)


def test_display_native_rotation_and_i2c():
    """Optional: run the real rotation and the real display loop in a native repl.

    Set LBM_REPL to a native LispBM repl (see test_strip_lisp_native_reader).
    The repl runs rotate_display_frame for every frame and several turn counts,
    and one iteration of the real display loop for every frame, rotation
    setting, screen and timer bar LED count, recording the i2c transfers. They
    must equal the oracle: the rotation 0 CSV row turned by the reference
    rotation, plus the hand-written per-rotation timer bar overlay.
    """
    print("\n--- display path: native LispBM repl ---")
    repl = os.environ.get('LBM_REPL', '')
    if not repl or not os.access(repl, os.X_OK):
        print("SKIPPED: set LBM_REPL to a native LispBM repl binary to run the real "
              "rotate_display_frame and display loop and compare the i2c bytes")
        return
    source = LISP_SOURCE.read_text()
    rows, frames = _read_display_csv_frames()
    generator = _load_lut_generator()
    lut = generator.build_binary(generator.read_frames(DISPLAY_LUT_PATH))

    # Part 1: the real rotate_display_frame on every stored frame.
    turn_counts = (0, 1, 2, 3, 4, 5, 7, -1, -2)
    body = ('(define pb (bufcreate 16))\n(define sc (bufcreate 8))\n'
            '(define rot_frames (list %s))\n'
            '(define turn_counts (list %s))\n'
            '(loopforeach f rot_frames (loopforeach tn turn_counts {\n'
            '  (bufclear pb)\n'
            '  (looprange r 0 8 (bufset-u8 pb (+ (* r 2) 1) (ix f r)))\n'
            '  (rotate_display_frame pb sc tn)\n'
            "  (print (list 'rot tn (bufget-u8 pb 1) (bufget-u8 pb 3) (bufget-u8 pb 5) (bufget-u8 pb 7)\n"
            '    (bufget-u8 pb 9) (bufget-u8 pb 11) (bufget-u8 pb 13) (bufget-u8 pb 15)\n'
            '    (bufget-u8 pb 0) (bufget-u8 pb 2) (bufget-u8 pb 14)))\n'
            '}))\n') % (
                ' '.join(_lisp_list(frame[1::2]) for frame in frames),
                ' '.join(str(t) for t in turn_counts))
    run = run_display_harness(repl, display_harness_script(source, lut, body))
    got = []
    for line in run.stdout.splitlines():
        match = re.match(r'^\(rot ([-\d ]+)\)$', ''.join(c for c in line if ' ' <= c <= '~'))
        if match:
            got.append([int(v) for v in match.group(1).split()])
    expected = []
    for stored in frames:
        for turns in turn_counts:
            frame = rotate_frame(stored, turns)
            expected.append([turns] + frame[1::2] + [frame[0], frame[2], frame[14]])
    if not got and 'Error writing to flash' in run.stdout + run.stderr:
        print("SKIPPED: this repl cannot store the const blocks (try the repl_big build, "
              "or a repl started with a larger constant memory)")
        return
    assert_eq(len(got), len(expected), "native rotation: one result for each frame and turn count")
    if len(got) != len(expected):
        print("  repl output:")
        print("  " + "\n  ".join((run.stdout + run.stderr).strip().splitlines()[:8]))
        return
    assert_eq(got == expected, True,
              "native rotation: rotate_display_frame equals the reference rotation for every "
              "frame and turn count (including 4, 5, 7, -1, -2)")
    even_bytes_clear = all(result[9:] == [0, 0, 0] for result in got if result[0] % 4)
    assert_eq(even_bytes_clear, True,
              "native rotation: the even bytes of a rotated frame are 0")

    # Part 2: the real display loop, byte for byte.
    cases = display_cases()
    run = run_display_harness(repl, display_harness_script(source, lut, display_case_driver(cases)))
    logged = parse_i2c_log(run.stdout)
    assert_eq([c for c, _ in logged], cases,
              f"native display loop: {len(cases)} cases (frames x rotation settings x screens x "
              "LED counts) all ran")
    bad = [(case, sent) for case, sent in logged if sent != expected_display_traffic(frames, case)]
    if bad:
        print("  first difference:", bad[0][0])
        print("  sent:    ", bad[0][1])
        print("  expected:", expected_display_traffic(frames, bad[0][0]))
    assert_eq(len(bad), 0,
              "native display loop: the i2c bytes equal the rotated rotation 0 rows with the overlay")
    screens = {sent[0][0] for _, sent in logged}
    assert_eq(screens, {0x70, 0x71}, "native display loop: both screens were driven")
    # Non-vacuous: a wrong rotation, and no rotation at all, must not match.
    wrong_rotation = sum(1 for case, sent in logged
                         if sent != expected_display_traffic(
                             frames, case[:2] + ((case[2] + 1) % 4, (case[3] + 1) % 4) + case[4:]))
    assert_eq(wrong_rotation > len(logged) // 2, True,
              "native display loop: the comparison fails for a wrong rotation setting")

    # Part 3: the real display thread, at the stack size the source configures,
    # draws every rotation, screen and a timer bar without running out of stack.
    stack = re.search(r'\(define THREAD_STACK_DISPLAY (\d+)\)', source)
    assert_eq(stack is not None, True, "native display thread: stack size found in the source")
    thread_body = """
(defun smart_cruise_leds_count () leds_g)
(define ndraw 0)
(defun i2c-tx-rx (addr data) (progn (setvar 'ndraw (+ ndraw 1)) 0))
(defun trig (st flip r1 r2 d) {
    (setvar 'scooter_type st) (setvar 'cudax_flip flip) (setvar 'rotation r1) (setvar 'rotation2 r2)
    (setvar 'disp_num d) (setvar 'last_disp_num -2) (sleep 0.05)
})
(setvar 'leds_g 8)
(start_display_output_loop)
(sleep 0.05)
"""
    triggers = [(0, 0, r, 0, d) for r in range(4) for d in (5, 32, 99)]
    triggers += [(1, 0, 0, r, d) for r in range(4) for d in (5, 32, 99)]
    thread_body += ''.join('(trig %d %d %d %d %d)\n' % t for t in triggers)
    thread_body += "(print (list 'done ndraw))\n"
    text = display_harness_script(source, lut, '')
    text = text.replace("(loopwhile (> loop_budget 0) {(setvar 'loop_budget (- loop_budget 1))",
                        HARNESS_LOOP_OPEN)
    run = run_display_harness(repl, text + thread_body, timeout=120)
    done = re.search(r'\(done (\d+)\)', run.stdout)
    assert_eq(done.group(1) if done else None, str(2 * (len(triggers) + 1)),
              "native display thread: every redraw completed at THREAD_STACK_DISPLAY "
              "(%s words), no out_of_stack" % (stack.group(1) if stack else '?'))
    assert_eq('out_of_stack' in run.stdout, False,
              "native display thread: no stack overflow reported")


def test_rig_config5_fallback():
    """The rig-only profile must behave exactly like existing profile 1."""
    source = LISP_SOURCE.read_text()
    start = source.index('(defun update_settings_from_eeprom ()')
    end = source.index('(defun log_settings_1 ()', start)
    settings = source[start:end]
    assert_eq("(setvar 'hardware_configuration (eeprom-read-i 19))\n"
              "    ; Rig-only compatibility: treat fixture profile 5 as series 2 without\n"
              "    ; Bluetooth (profile 1). Leave the persisted setting untouched.\n"
              "    (if (= hardware_configuration 5) (setvar 'hardware_configuration 1))"
              in settings, True, 'rig profile 5 normalises only the RAM configuration')
    assert_eq("(if (<= hardware_configuration HARDWARE_BLACKTIP_MAX)" in settings, True,
              'rig profile does not reclassify CudaX 3 and 4')
    assert_eq("(eeprom-store-i" in settings or "(conf-set" in settings, False,
              'rig profile never writes persistent configuration')
    repl = os.environ.get('LBM_REPL', '')
    if not repl:
        print('SKIPPED: native rig profile execution requires LBM_REPL')
        return
    src = log_native_source()
    start = src.index('(defun update_settings_from_eeprom ()')
    end = src.index('(defun log_settings_1 ()', start)
    src = src[:start] + src[start:end].replace('(eeprom-read-i ', '(mock-rig-read ') + src[end:]
    start = src.index('(defun peripherals_setup ()')
    end = src.index('(defun validate_lut_header', start)
    src = (src[:start] + src[start:end].replace('(i2c-start ', '(mock-i2c-start ')
           .replace('(i2c-tx-rx ', '(mock-i2c-tx-rx ') + src[end:])
    src += '''
(define mock_rig_hw 0)
(define mock_rig_pins nil)
(define mock_rig_result nil)
(defun mock-rig-read (addr) (if (= addr 19) mock_rig_hw 0))
(defun mock-i2c-start (rate sda scl) (setvar 'mock_rig_pins (list sda scl)))
(defun mock-i2c-tx-rx (addr data) t)
(looprange hw 0 6 {
    (setvar 'mock_rig_hw hw)
    (update_settings_from_eeprom)
    (peripherals_setup)
    (setvar 'mock_rig_result (append mock_rig_result
        (list (list hardware_configuration scooter_type mock_rig_pins))))
})
mock_rig_result
'''
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'rig_profile.lisp'
        path.write_text(src)
        result = subprocess.run([repl, '-H', '2753', '-M', '262144', '-C', '262144',
                                 '--bldc_stubs', '--terminate', '-s', str(path)],
                                capture_output=True, text=True, timeout=60)
    values = [line[2:] for line in result.stdout.splitlines() if line.startswith('> ')]
    assert_eq(result.returncode, 0, 'native rig profile REPL exits normally')
    assert_eq(values[-1] if values else result.stdout[-500:],
              '((0 0 (pin-swdio pin-swclk)) (1 0 (pin-rx pin-tx)) '
              '(2 0 (pin-tx pin-rx)) (3 1 (pin-swdio pin-swclk)) '
              '(4 1 (pin-rx pin-tx)) (1 0 (pin-rx pin-tx)))',
              'native rig profile 5 equals 1; configurations 0–4 unchanged')


# =============================================================================
# Test Runner
# =============================================================================

def run_all_tests():
    """Run all test suites"""
    print("\n╔══════════════════════════════════════════╗")
    print("║  BlackTip DPV Smoke Tests                ║")
    print("╚══════════════════════════════════════════╝")

    test_clamp()
    test_validate_boolean()
    test_state_name_for()
    test_speed_percentage_at()
    test_calculate_rpm()
    test_motor_speed_command_centralisation()
    test_startup_tune_cancellation_for_motor_start()
    test_display_lut_structure()
    test_display_lut_binary_single_orientation()
    test_display_lut_generator_validation()
    test_display_rotation_reference()
    test_smart_cruise_timer_bar_rotation()
    test_validate_lut_header()
    test_debug_log()
    test_debug_log_format()
    test_brightness_clamp()
    test_i2c_init_sequence()
    test_blacktip_display_timeout_sequence()
    test_state_metrics_reset()
    test_five_click_settings_and_migration()
    test_production_defaults_reset()
    test_release_documentation()
    test_five_click_shutdown_decision()
    test_startup_trigger_readiness()
    test_click_and_beep_regressions()
    test_rig_config5_fallback()
    test_strip_lisp_real_file()
    test_strip_lisp_edge_cases()
    test_strip_lisp_mutation_check()
    test_strip_lisp_native_reader()
    test_display_native_rotation_and_i2c()

    print("\n══════════════════════════════════════════")
    print(f"  Results: {test_passes} passed, {test_failures} failed")
    print("══════════════════════════════════════════\n")


    if test_failures > 0:
        print("FAILED: Some tests did not pass")
        return 1
    else:
        print("SUCCESS: All tests passed!")
        return 0

if __name__ == "__main__":
    sys.exit(run_all_tests())
