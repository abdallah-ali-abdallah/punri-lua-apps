#!/usr/bin/env python3
"""Build the 1-bit world and icon assets from their editable source data."""

import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def inside(x: float, y: float, polygon: list[tuple[float, float]]) -> bool:
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


def project(point: list[float], width: int, height: int) -> tuple[float, float]:
    longitude, latitude = point
    return (longitude + 180.0) * width / 360.0, (90.0 - latitude) * height / 180.0


def load_land(source: dict, width: int, height: int) -> list[list[list[tuple[float, float]]]]:
    path = ROOT / "tools" / source["source_file"]
    contents = path.read_bytes()
    if hashlib.sha256(contents).hexdigest() != source["source_sha256"]:
        raise ValueError(f"Natural Earth source digest mismatch: {path}")
    geojson = json.loads(contents)
    if geojson.get("type") != "FeatureCollection":
        raise ValueError("Natural Earth source is not a GeoJSON FeatureCollection")
    land: list[list[list[tuple[float, float]]]] = []
    for feature in geojson.get("features", []):
        geometry = feature.get("geometry") or {}
        if geometry.get("type") != "Polygon":
            raise ValueError(f"unsupported Natural Earth geometry: {geometry.get('type')}")
        rings = [[project(point, width, height) for point in ring] for ring in geometry.get("coordinates", [])]
        if rings and all(len(ring) >= 3 for ring in rings):
            land.append(rings)
    if not land:
        raise ValueError("Natural Earth source contains no usable land polygons")
    return land


def build_world() -> None:
    source = json.loads((ROOT / "tools" / "world-map.json").read_text(encoding="utf-8"))
    width, height = source["width"], source["height"]
    if source.get("projection") != "equirectangular":
        raise ValueError("World Clock expects an equirectangular source map")
    dark: set[tuple[int, int]] = set()
    for rings in load_land(source, width, height):
        min_x = max(0, math.floor(min(x for ring in rings for x, _ in ring)))
        max_x = min(width - 1, math.ceil(max(x for ring in rings for x, _ in ring)))
        min_y = max(0, math.floor(min(y for ring in rings for _, y in ring)))
        max_y = min(height - 1, math.ceil(max(y for ring in rings for _, y in ring)))
        for y in range(min_y, max_y + 1):
            for x in range(min_x, max_x + 1):
                # Even/odd filling makes enclosed lake rings white again.
                if sum(inside(x + 0.5, y + 0.5, ring) for ring in rings) % 2:
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
