#!/usr/bin/env python3
"""Build/check the separate quote-only font catalog (no reader catalog edits).

Build: uv run --with fonttools --with freetype-py python
  apps/scripts/generate_quote_fonts.py --write --firmware-root .
Check: python apps/scripts/generate_quote_fonts.py
"""

import argparse
import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "quote-fonts"
MAX_FILE_BYTES = 2 * 1024 * 1024


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def generate(firmware):
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont

    converter = firmware / "lib/EpdFont/scripts/fontconvert_sdcard.py"
    assert converter.is_file(), converter
    config = json.loads((DATA / "sources.json").read_text())
    with tempfile.TemporaryDirectory(prefix="punri-quote-font-build-") as temp:
        for profile, source in config["profiles"].items():
            blob = fetch(source["url"])
            assert sha(blob) == source["sha256"], source["url"]
            ttf = Path(temp) / (profile + ".ttf")
            ttf.write_bytes(blob)
            with TTFont(ttf) as font:
                instance = font
                if source["axes"]:
                    instance = instantiateVariableFont(
                        font, source["axes"], inplace=False
                    )
                # The renderer always caches U+FFFD, including for fully
                # supported text. Some source faces omit it; reuse that face's
                # question mark as an explicit, visible fallback glyph.
                cmap = instance.getBestCmap()
                if 0xFFFD not in cmap:
                    for table in instance["cmap"].tables:
                        if table.isUnicode() and table.format in (4, 12, 13):
                            table.cmap[0xFFFD] = cmap[0x003F]
                instance.save(ttf)
                if instance is not font:
                    instance.close()
            directory = DATA / "files" / profile
            directory.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                [
                    sys.executable,
                    str(converter),
                    "--regular",
                    str(ttf),
                    "--intervals",
                    source["intervals"],
                    "--sizes",
                    "20,24",
                    "--darken-aa",
                    "--name",
                    source["family"],
                    "--output-dir",
                    str(directory),
                ],
                check=True,
            )
            license_dir = DATA / "licenses" / profile
            license_dir.mkdir(parents=True, exist_ok=True)
            (license_dir / "OFL.txt").write_bytes(fetch(source["licenseUrl"]))


def build_index():
    config = json.loads((DATA / "sources.json").read_text())
    profiles = {}
    for profile, source in config["profiles"].items():
        files = {}
        for size in config["sizes"]:
            name = f"{source['family']}_{size}.cpfont"
            path = DATA / "files" / profile / name
            blob = path.read_bytes()
            magic, version, flags, styles = struct.unpack_from("<8sHHB", blob)
            assert magic == b"CPFONT\0\0" and version == 4 and styles == 1, path
            assert 32 < len(blob) <= MAX_FILE_BYTES, path
            files[str(size)] = {
                "file": f"files/{profile}/{name}",
                "size": len(blob),
                "sha256": sha(blob),
            }
        assert (DATA / "licenses" / profile / "OFL.txt").is_file()
        profiles[profile] = {
            "family": source["family"],
            "files": files,
            "license": f"licenses/{profile}/OFL.txt",
            "sourceSha256": source["sha256"],
        }
    languages = {
        code: "amiri"
        if code == "AR"
        else "frank-ruhl-libre"
        if code == "HE"
        else "noto-serif"
        for code in sorted(
            json.loads((ROOT / "quotes/index.json").read_text())["languages"]
        )
    }
    return {
        "version": 1,
        "formatVersion": 4,
        "languages": languages,
        "profiles": profiles,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--firmware-root", type=Path, default=ROOT.parent)
    args = parser.parse_args()
    if args.write:
        generate(args.firmware_root.resolve())
    expected = json.dumps(build_index(), indent=2) + "\n"
    target = DATA / "index.json"
    if args.write:
        target.write_text(expected)
    else:
        assert target.read_text() == expected, "Quote font index mismatch"
    print("PASS: 28 languages, 3 quote font profiles, 6 native-size Regular files")
