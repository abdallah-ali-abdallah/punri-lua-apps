#!/usr/bin/env python3
"""Generate or verify the integrity-bound App Store catalog.

The human-maintained catalog keeps application metadata and an ordered list of
package paths.  This tool derives every file size and SHA-256 digest from the
repository, checks manifest identity, and emits the deterministic schema-v2
catalog consumed by the firmware.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "catalog.json"
DEFAULT_APPS_ROOT = ROOT
OFFICIAL_REPOSITORY = "abdallah-ali-abdallah/punri-lua-apps"
OFFICIAL_SOURCE_IDENTITY = f"{OFFICIAL_REPOSITORY}:catalog.json"
MAX_APP_ID_BYTES = 64
MAX_RELATIVE_PATH_BYTES = 240
MAX_PACKAGE_FILES = 63  # The installer reserves slot 64 for .install.json.
MAX_FILE_BYTES = 64 * 1024 * 1024
KNOWN_CAPABILITIES = {"buttons", "storage", "touch"}
DEFAULT_CAPABILITIES = ["buttons", "storage"]
APP_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*\Z")
SEMVER = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
    r"(?:-(?:(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\Z"
)


class CatalogError(ValueError):
    """The catalog cannot be represented safely as schema v2."""


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise CatalogError(f"cannot read valid JSON from {path}: {error}") from error


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_app_id(app_id: Any) -> str:
    if not isinstance(app_id, str) or not APP_ID.fullmatch(app_id):
        raise CatalogError(f"invalid app id: {app_id!r}")
    if len(app_id.encode("utf-8")) > MAX_APP_ID_BYTES:
        raise CatalogError(f"app id exceeds {MAX_APP_ID_BYTES} UTF-8 bytes: {app_id}")
    return app_id


def validate_relative_path(value: Any) -> str:
    if not isinstance(value, str) or not value:
        raise CatalogError(f"invalid empty/non-string package path: {value!r}")
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError as error:
        raise CatalogError(f"package path is not valid Unicode: {value!r}") from error
    if len(encoded) > MAX_RELATIVE_PATH_BYTES:
        raise CatalogError(f"package path exceeds {MAX_RELATIVE_PATH_BYTES} UTF-8 bytes: {value}")
    if value.startswith("/") or value.endswith("/") or "\\" in value or ":" in value:
        raise CatalogError(f"unsafe package path: {value}")
    if any(ord(character) < 0x20 or 0x7F <= ord(character) <= 0x9F for character in value):
        raise CatalogError(f"control character in package path: {value!r}")
    if any(segment in ("", ".", "..") for segment in value.split("/")):
        raise CatalogError(f"unsafe package path segment: {value}")
    if value == ".install.json":
        raise CatalogError(".install.json is reserved for installer provenance")
    return value


def validate_semver(value: Any, field: str) -> str:
    if not isinstance(value, str) or len(value) > 96 or not SEMVER.fullmatch(value):
        raise CatalogError(f"{field} must be strict semantic versioning: {value!r}")
    return value


def validate_min_api(value: Any) -> int:
    if type(value) is not int or value < 1:
        raise CatalogError(f"min_api must be a positive integer: {value!r}")
    return value


def validate_capabilities(value: Any) -> list[str]:
    if not isinstance(value, list):
        raise CatalogError("capabilities must be an array")
    capabilities: list[str] = []
    for capability in value:
        if not isinstance(capability, str) or capability not in KNOWN_CAPABILITIES:
            raise CatalogError(f"unknown capability: {capability!r}")
        if capability in capabilities:
            raise CatalogError(f"duplicate capability: {capability}")
        capabilities.append(capability)
    return capabilities


def catalog_paths(app: dict[str, Any]) -> list[str]:
    files = app.get("files")
    if not isinstance(files, list) or not files or len(files) > MAX_PACKAGE_FILES:
        raise CatalogError(f"{app.get('id', '<unknown>')} must list 1..{MAX_PACKAGE_FILES} files")
    paths: list[str] = []
    folded: set[str] = set()
    for item in files:
        raw_path = item.get("path") if isinstance(item, dict) else item
        path = validate_relative_path(raw_path)
        collision_key = path.casefold()
        if collision_key in folded:
            raise CatalogError(f"duplicate/case-colliding package path: {path}")
        folded.add(collision_key)
        paths.append(path)
    return paths


def regular_contained_file(app_directory: Path, relative_path: str) -> Path:
    candidate = app_directory / relative_path
    try:
        resolved_root = app_directory.resolve(strict=True)
        resolved = candidate.resolve(strict=True)
    except OSError as error:
        raise CatalogError(f"missing package file: {candidate}") from error
    if not resolved.is_relative_to(resolved_root) or not resolved.is_file():
        raise CatalogError(f"package path leaves app directory or is not a file: {relative_path}")
    return resolved


def rebuild_app(app: Any, apps_root: Path) -> dict[str, Any]:
    if not isinstance(app, dict):
        raise CatalogError("every apps entry must be an object")
    app_id = validate_app_id(app.get("id"))
    app_directory = apps_root / app_id
    manifest_path = regular_contained_file(app_directory, "manifest.json")
    manifest = read_json(manifest_path)
    if not isinstance(manifest, dict):
        raise CatalogError(f"{manifest_path} must contain an object")

    version = validate_semver(app.get("version"), f"{app_id}.version")
    entry = validate_relative_path(app.get("entry", manifest.get("entry", "main.lua")))
    if not entry.endswith(".lua"):
        raise CatalogError(f"{app_id}.entry must end in .lua: {entry}")
    min_api = validate_min_api(app.get("min_api", manifest.get("min_api", 1)))
    capabilities = validate_capabilities(
        app.get("capabilities", manifest.get("capabilities", DEFAULT_CAPABILITIES))
    )

    if manifest.get("id") != app_id or manifest.get("version") != version:
        raise CatalogError(f"{app_id}: catalog id/version do not match manifest.json")
    if manifest.get("entry", "main.lua") != entry:
        raise CatalogError(f"{app_id}: catalog entry does not match manifest.json")
    if "min_api" in manifest and manifest["min_api"] != min_api:
        raise CatalogError(f"{app_id}: catalog min_api does not match manifest.json")

    paths = catalog_paths(app)
    if "manifest.json" not in paths:
        raise CatalogError(f"{app_id}: manifest.json is not listed")
    if entry not in paths:
        raise CatalogError(f"{app_id}: entry script {entry} is not listed")

    file_integrity: list[dict[str, Any]] = []
    for relative_path in paths:
        package_file = regular_contained_file(app_directory, relative_path)
        size = package_file.stat().st_size
        if size > MAX_FILE_BYTES:
            raise CatalogError(f"{app_id}/{relative_path} exceeds {MAX_FILE_BYTES} bytes")
        file_integrity.append({"path": relative_path, "size": size, "sha256": sha256_file(package_file)})

    def required_string(field: str) -> str:
        value = app.get(field)
        if not isinstance(value, str) or not value:
            raise CatalogError(f"{app_id}.{field} must be a non-empty string")
        return value

    return {
        "id": app_id,
        "name": required_string("name"),
        "version": version,
        "author": required_string("author"),
        "description": required_string("description"),
        "entry": entry,
        "min_api": min_api,
        "capabilities": capabilities,
        # Keep the legacy path list so already-released clients can still
        # install complete multi-file apps. PUNRI requires the parallel
        # integrity list to match these paths exactly and in the same order.
        "files": paths,
        "file_integrity": file_integrity,
    }


def build_catalog(catalog_path: Path, apps_root: Path) -> dict[str, Any]:
    current = read_json(catalog_path)
    if not isinstance(current, dict) or not isinstance(current.get("apps"), list):
        raise CatalogError("catalog root must contain an apps array")
    rebuilt_apps = [rebuild_app(app, apps_root) for app in current["apps"]]
    app_ids = [app["id"].casefold() for app in rebuilt_apps]
    if len(set(app_ids)) != len(app_ids):
        raise CatalogError("catalog contains duplicate/case-colliding app ids")
    return {
        "schema": 2,
        "source": OFFICIAL_SOURCE_IDENTITY,
        "repo": OFFICIAL_REPOSITORY,
        "branch": "main",
        "apps": rebuilt_apps,
    }


def render_catalog(catalog: dict[str, Any]) -> str:
    return json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--apps-root", type=Path, default=DEFAULT_APPS_ROOT)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="fail if the checked-in catalog is stale")
    mode.add_argument("--write", action="store_true", help="rewrite the catalog with current file metadata")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    catalog_path = args.catalog.resolve()
    apps_root = args.apps_root.resolve()
    try:
        generated = render_catalog(build_catalog(catalog_path, apps_root))
        if args.write:
            catalog_path.write_text(generated, encoding="utf-8")
            print(f"Wrote schema-v2 App Store catalog: {catalog_path}")
            return 0

        current = catalog_path.read_text(encoding="utf-8")
        if current == generated:
            print(f"App Store catalog is current: {catalog_path}")
            return 0
        print("App Store catalog is stale; run scripts/generate_app_catalog.py --write", file=sys.stderr)
        sys.stderr.writelines(
            difflib.unified_diff(
                current.splitlines(keepends=True),
                generated.splitlines(keepends=True),
                fromfile=str(catalog_path),
                tofile=f"{catalog_path} (generated)",
            )
        )
        return 1
    except (CatalogError, OSError) as error:
        print(f"App Store catalog error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
