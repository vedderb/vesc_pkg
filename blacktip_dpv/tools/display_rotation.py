"""Reference rotation of a 16 byte display frame, defined from the geometry.

Used by tools/preview_display.py and tests/run_tests.py. It is the Python
statement of the rule that rotate_display_frame in blacktip_dpv.lisp
implements; the tests check the firmware against it for every frame.

A frame is 16 bytes: the even bytes are not pixel data (they are always 0) and
the odd byte 2a + 1 holds the pixels of row a (a = 0 is the top row of the
physical view). Physical column b (b = 0 is the left column) of that row is
bit COLUMN_BITS[b] of the byte, so the bit order along a row is 7, 0, 1, 2, 3,
4, 5, 6. This is the view that preview_display.py draws.

One clockwise quarter turn of the physical view moves pixel (row a, column b)
to (row b, column 7 - a). The top-left pixel (0, 0) goes to the top-right
corner (0, 7).
"""
from __future__ import annotations

from typing import List, Sequence

FRAME_BYTES = 16
GRID_SIZE = 8
# Bit number of a row byte that drives physical column 0..7.
COLUMN_BITS = [7, 0, 1, 2, 3, 4, 5, 6]


def frame_to_grid(frame: Sequence[int]) -> List[List[int]]:
    """Return the pixels of a frame as grid[row][column], each 0 or 1."""
    return [[(frame[2 * a + 1] >> COLUMN_BITS[b]) & 1 for b in range(GRID_SIZE)]
            for a in range(GRID_SIZE)]


def grid_to_frame(grid: Sequence[Sequence[int]]) -> List[int]:
    """Return the 16 byte frame (even bytes 0) that shows the pixel grid."""
    frame = [0] * FRAME_BYTES
    for a in range(GRID_SIZE):
        for b in range(GRID_SIZE):
            if grid[a][b]:
                frame[2 * a + 1] |= 1 << COLUMN_BITS[b]
    return frame


def rotate_grid_clockwise(grid: Sequence[Sequence[int]]) -> List[List[int]]:
    """One clockwise quarter turn: pixel (a, b) moves to (b, 7 - a)."""
    rotated = [[0] * GRID_SIZE for _ in range(GRID_SIZE)]
    for a in range(GRID_SIZE):
        for b in range(GRID_SIZE):
            rotated[b][GRID_SIZE - 1 - a] = grid[a][b]
    return rotated


def rotate_frame(frame: Sequence[int], turns: int) -> List[int]:
    """Rotate a frame clockwise by turns quarter turns, taken modulo 4.

    Any integer is accepted (a negative count is a counter-clockwise turn). A
    turn count that is a multiple of 4 returns the frame unchanged; any other
    count returns only the pixels, with the even bytes 0.
    """
    if turns % 4 == 0:
        return list(frame)
    grid = frame_to_grid(frame)
    for _ in range(turns % 4):
        grid = rotate_grid_clockwise(grid)
    return grid_to_frame(grid)
