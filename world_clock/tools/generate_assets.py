#!/usr/bin/env python3
"""Build the 1-bit world and icon assets from the editable CC0 map source."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def inside(x: float, y: float, polygon: list[list[int]]) -> bool:
    result = False
    previous = len(polygon) - 1
    for current, point in enumerate(polygon):
        px, py = point
        qx, qy = polygon[previous]
        if (py > y) != (qy > y) and x < (qx - px) * (y - py) / (qy - py) + px:
            result = not result
        previous = current
    return result


def write_raw(path: Path, width: int, height: int, dark: set[tuple[int, int]]) -> None:
    data = bytearray([0xFF] * ((width * height + 7) // 8))
    for x, y in dark:
        index = y * width + x
        data[index // 8] &= ~(1 << (7 - index % 8))
    path.write_bytes(data)


def build_world() -> None:
    source = json.loads((ROOT / "tools" / "world-map.json").read_text(encoding="utf-8"))
    width, height = source["width"], source["height"]
    dark: set[tuple[int, int]] = set()
    for y in range(height):
        for x in range(width):
            if any(inside(x + 0.5, y + 0.5, polygon) for polygon in source["polygons"]):
                dark.add((x, y))
    write_raw(ROOT / "world.raw", width, height, dark)


def build_icon() -> None:
    # A small clock face with two hands. Icon raw is the documented 32x32 form.
    dark: set[tuple[int, int]] = set()
    for y in range(32):
        for x in range(32):
            dx, dy = x - 15.5, y - 15.5
            radius = dx * dx + dy * dy
            if 82 <= radius <= 112:
                dark.add((x, y))
    for x, y in [(16, 8), (16, 9), (16, 10), (16, 11), (16, 12), (17, 16), (18, 16), (19, 16), (20, 16), (21, 16)]:
        dark.add((x, y))
    write_raw(ROOT / "icon.raw", 32, 32, dark)


if __name__ == "__main__":
    build_world()
    build_icon()
