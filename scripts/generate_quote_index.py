#!/usr/bin/env python3
"""Validate quote CSVs and generate their exact download size/hash manifest."""

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "quotes"


def build_index():
    languages = {}
    for path in sorted(ROOT.glob("*.csv")):
        data = path.read_bytes()
        rows = list(
            csv.reader(io.StringIO(data.decode("utf-8-sig"), newline=""), strict=True)
        )
        assert rows[0] == ["quote", "author", "date"], path
        assert len(rows) == 21, (path, "expected 20 quotes")
        assert len({row[0] for row in rows[1:]}) == 20, (path, "duplicate quote")
        for row in rows[1:]:
            assert len(row) == 3 and row[0].strip(), (path, row)
            assert all(
                len(field.encode()) <= bound
                for field, bound in zip(row, [1024, 192, 32])
            ), path
        languages[path.stem] = {
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "quotes": 20,
        }
    assert len(languages) == 28, "expected all 28 PUNRI languages"
    return (
        json.dumps({"version": 1, "languages": languages}, ensure_ascii=False, indent=2)
        + "\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    expected = build_index()
    path = ROOT / "index.json"
    if args.write:
        path.write_text(expected)
    else:
        assert path.read_text() == expected, "quote index differs; run with --write"
    print("PASS: 28 languages, 560 quotes, exact sizes and SHA-256")
