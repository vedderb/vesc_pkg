#!/usr/bin/env python3
"""
BlackTip DPV Smoke Tests
Tests pure functions to catch regressions before flashing hardware
"""

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

    print("\n╔══════════════════════════════════════════╗")
    print(f"║  Results: {test_passes} passed, {test_failures} failed")
    print("╚══════════════════════════════════════════╝\n")

    if test_failures > 0:
        print("FAILED: Some tests did not pass")
        return 1
    else:
        print("SUCCESS: All tests passed!")
        return 0

if __name__ == "__main__":
    sys.exit(run_all_tests())
