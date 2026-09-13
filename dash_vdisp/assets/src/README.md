# Asset sources

The `.bin` files here are Dash35B's original 480x320 artwork. The icons actually
used by this package were produced by downscaling these index maps, not the PNGs:
some of the PNGs carry their shape in RGB rather than alpha, so reading alpha
alone turns them into solid blocks.

`.bin` layout: width u16 BE, height u16 BE, bpp u8, then indexed pixels packed
continuously MSB-first with no row alignment. The trailing partial byte is
truncated, which is what VESC Tool itself emits.
