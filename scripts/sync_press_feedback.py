#!/usr/bin/env python3
"""Copy the canonical press module into every independently installable app."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY_APPS = (
    "2048", "blockdrop", "chess", "codex", "dashboard", "dice", "hourglass",
    "solitaire", "sudoku", "tictactoe", "watertracker", "wordle",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    modules = [("press_feedback.lua", "press_feedback.lua", sorted(ROOT.glob("*/manifest.json"))),
               ("legacy_feedback.lua", "feedback.lua", [ROOT / name / "manifest.json" for name in LEGACY_APPS])]
    for canonical, packaged, manifests in modules:
        source = (ROOT / "shared" / canonical).read_bytes()
        for manifest in manifests:
            if not manifest.is_file():
                parser.exit(1, f"Missing application manifest: {manifest}\n")
            target = manifest.parent / packaged
            if not target.exists() or target.read_bytes() != source:
                stale.append(str(target.relative_to(ROOT)))
                if not args.check:
                    target.write_bytes(source)
    if args.check and stale:
        parser.exit(1, "Outdated press feedback modules: " + ", ".join(stale) + "\n")
    print(f"{'Checked' if args.check else 'Synchronized'} press feedback in {len(list(ROOT.glob('*/manifest.json')))} apps and {len(LEGACY_APPS)} legacy adapters")


if __name__ == "__main__":
    main()
