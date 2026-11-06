#!/usr/bin/env python3
"""Generate binary file from display lookup table for efficient import.

The binary format is optimized for direct memory access without parsing.
It can be imported using the `import` statement and then loaded as a byte array.

assets/display_lut.csv holds one row per display, in rotation 0 (columns
index, name, b0 to b15). The firmware rotates the frame clockwise at run time
(rotate_display_frame in blacktip_dpv.lisp), so no other orientation is stored
anywhere. Row n of the CSV is display n of the firmware: its index must equal
its position, the name is only a label, and every row is one 16 byte frame.

Format (version 2):
    Header (8 bytes):
        magic: 0x4C555444 (ASCII "LUTD")
        version: u16 (2)
        num_frames: u16

    Frame data (num_frames * 16 bytes, frame n at offset 8 + 16 * n):
        Each frame is 16 bytes (8 column pairs of low/high bytes) in rotation 0.
        Version 1 stored all four rotations of every frame (frame n, rotation r
        at offset 8 + 64 * n + 16 * r); the version was raised so that the two
        layouts can never be mistaken for each other.

Usage::
    python tools/generate_lut_binary.py
"""
from __future__ import annotations

import csv
import struct
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = REPO_ROOT / "assets"
GENERATED_DIR = REPO_ROOT / "generated"
DISPLAY_CSV = ASSET_DIR / "display_lut.csv"
DISPLAY_BIN = GENERATED_DIR / "display_lut.bin"

# Magic number for display LUT binary file
MAGIC_DISPLAY = 0x4C555444  # ASCII "LUTD"
VERSION = 2

FRAME_BYTES = 16
MAX_FRAMES = 0xFFFF  # num_frames is a u16
CSV_COLUMNS = ["index", "name"] + [f"b{i}" for i in range(FRAME_BYTES)]


class LutError(Exception):
    """The display CSV does not describe a valid set of frames."""


def read_frames(path: Path | None = None) -> list[list[int]]:
    """Return the 16 bytes of every display of the CSV, in index order.

    Raises LutError, naming the CSV line, on the first problem: wrong header,
    missing or extra fields, a value that is not a byte, non-zero even bytes
    (they are not pixel data and the rotation relies on them being 0), a
    duplicate name, an index that is not the row position, or no rows at all.
    """
    frames: list[list[int]] = []
    names: dict[str, int] = {}
    with (path or DISPLAY_CSV).open(newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if header != CSV_COLUMNS:
            raise LutError(f"line 1: expected the columns {','.join(CSV_COLUMNS)}, got "
                           f"{','.join(header or [])}")
        for fields in reader:
            line = reader.line_num
            if len(fields) != len(CSV_COLUMNS):
                raise LutError(f"line {line}: expected {len(CSV_COLUMNS)} fields, got {len(fields)}")
            try:
                values = [int(value) for value in fields[:1] + fields[2:]]
            except ValueError as error:
                raise LutError(f"line {line}: {error}") from None
            index, data = values[0], values[1:]
            name = fields[1].strip()
            if index != len(frames):
                raise LutError(f"line {line}: '{name}' has index {index}, expected {len(frames)} "
                               f"(indices must be sequential from 0)")
            if not name:
                raise LutError(f"line {line}: display {index} has no name")
            if name in names:
                raise LutError(f"line {line}: name '{name}' is already used by display {names[name]}")
            if not all(0 <= value <= 255 for value in data):
                raise LutError(f"line {line}: '{name}': bytes must be in 0..255, got {data}")
            if any(data[0::2]):
                raise LutError(f"line {line}: '{name}': even bytes b0, b2, ... must be 0, got {data}")
            names[name] = index
            frames.append(data)
    if not frames:
        raise LutError("no display rows")
    if len(frames) > MAX_FRAMES:
        raise LutError(f"{len(frames)} rows, at most {MAX_FRAMES} fit the table")
    return frames


def build_binary(frames: list[list[int]]) -> bytes:
    """Serialise rotation 0 frames in the version 2 format."""
    data = struct.pack('<IHH', MAGIC_DISPLAY, VERSION, len(frames))
    for frame in frames:
        data += bytes(frame)
    return data


def generate_display_binary() -> None:
    """Generate binary file from display LUT CSV."""
    # Never leave a stale table behind if validation fails.
    DISPLAY_BIN.unlink(missing_ok=True)
    frames = read_frames()

    GENERATED_DIR.mkdir(exist_ok=True)
    DISPLAY_BIN.write_bytes(build_binary(frames))

    print(f"Generated {DISPLAY_BIN}")
    print(f"  Size: {DISPLAY_BIN.stat().st_size} bytes")
    print(f"  Frames: {len(frames)} (rotation 0; the firmware rotates them at run time)")


def main() -> int:
    """Generate the binary display table."""
    try:
        generate_display_binary()
    except (LutError, OSError) as error:
        print(f"generate_lut_binary: error: {DISPLAY_CSV}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
