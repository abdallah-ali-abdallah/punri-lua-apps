#!/usr/bin/env python3
"""Reproduce the app's 32x32 line icon and panel-oriented 1-bit asset."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
pixels = [[1] * 32 for _ in range(32)]
rects = [(4, 1, 24, 30), (7, 4, 18, 10), (13, 5, 4, 2), (13, 10, 4, 2)]
rects += [(x, y, 5, 4) for y in (16, 22, 27) for x in (7, 14, 21)]
for x, y, w, h in rects:
    for xx in range(x, x + w): pixels[y][xx] = pixels[y + h - 1][xx] = 0
    for yy in range(y, y + h): pixels[yy][x] = pixels[yy][x + w - 1] = 0
for x in range(10, 21): pixels[8][x] = 0
rotated = [[1] * 32 for _ in range(32)]
for y in range(32):
    for x in range(32): rotated[31 - x][y] = pixels[y][x]
raw = bytearray()
for row in rotated:
    for offset in range(0, 32, 8):
        raw.append(sum(row[offset + bit] << (7 - bit) for bit in range(8)))
(root / "icon.raw").write_bytes(raw)
svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">',
       '<rect width="32" height="32" fill="white"/>', '<g fill="none" stroke="black" stroke-width="1">']
svg += [f'<rect x="{x + .5}" y="{y + .5}" width="{w - 1}" height="{h - 1}"/>' for x, y, w, h in rects]
svg += ['<path d="M10 8.5H21"/>', '</g></svg>']
(root / "icon.svg").write_text("\n".join(svg) + "\n")
