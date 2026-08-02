#!/usr/bin/env python3
"""
BlackTip DPV Smoke Tests
Tests pure functions to catch regressions before flashing hardware
"""

import struct
import sys

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
    test_validate_lut_header()
    test_debug_log()
    test_debug_log_format()
    test_brightness_clamp()
    test_i2c_init_sequence()
    test_blacktip_display_timeout_sequence()
    test_state_metrics_reset()

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
