# PUNRI Lua Apps — Agent Guide

This public repository owns downloadable Lua applications and `catalog.json`.
The firmware consumes it as its `apps/` submodule; runtime/HAL changes belong in
the firmware repository, not here.

- Application folders and `catalog.json` live at the repository root.
- Preserve application IDs, versions, upstream credits, assets and saved-data
  compatibility. Do not bump versions as part of a repository move.
- Read `README.md` and the relevant application before editing. Radio apps
  require firmware API level 3; see `docs/radio-api.md`.
- After an explicitly authorized catalog update, regenerate exact file sizes
  and SHA-256 records with `python3 scripts/generate_app_catalog.py --write`.
  Verify with `python3 scripts/generate_app_catalog.py --check`.
- Keep Lua package file lists complete and ordered. `manifest.json`, the entry
  script and all required modules/assets must be included. `.install.json` is
  reserved for firmware-managed installation provenance.
- Test changes in the matching supported PUNRI simulator (Sticky, X4 Pro or
  X4 Classic), then on hardware. Desktop radio replay is not physical RF testing.
- Do not commit, push or publish application updates without explicit user
  instruction. Commit/push this repository before advancing the firmware's
  `apps/` gitlink; never pin an unpublished commit.
