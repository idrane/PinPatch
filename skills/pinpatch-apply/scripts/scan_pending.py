#!/usr/bin/env python3
"""Scan canonical PinPatch UUID folders for unprocessed current revisions."""

from __future__ import annotations

import argparse
import json
import os
import sys
import uuid
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, help="PinPatch storage root")
    return parser.parse_args()


def canonical_uuid(value: Any) -> str:
    return str(uuid.UUID(str(value))).lower()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def discover_roots() -> list[Path]:
    explicit = os.environ.get("PINPATCH_ROOT")
    if explicit:
        return [Path(explicit).expanduser().resolve()]
    base = Path.home() / "Library/Developer/CoreSimulator/Devices"
    pattern = "*/data/Containers/Data/Application/*/Library/Application Support/PinPatch"
    return sorted(path.resolve() for path in base.glob(pattern) if path.is_dir())


def choose_root(explicit: Path | None) -> Path:
    if explicit is not None:
        root = explicit.expanduser().resolve()
        if not root.is_dir():
            raise ValueError(f"PinPatch root does not exist: {root}")
        return root
    roots = discover_roots()
    if len(roots) == 1:
        return roots[0]
    if not roots:
        raise ValueError("no PinPatch root found; pass --root or set PINPATCH_ROOT")
    choices = "\n".join(f"  {root}" for root in roots)
    raise ValueError(f"multiple PinPatch roots found; pass --root:\n{choices}")


def load_screens(root: Path, warnings: list[str]) -> dict[str, dict[str, Any]]:
    screens: dict[str, dict[str, Any]] = {}
    for path in sorted((root / "screens").glob("*.json")):
        try:
            record = read_json(path)
            screen_id = canonical_uuid(record["screenID"])
            screens[screen_id] = record
        except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
            warnings.append(f"ignored invalid screen {path}: {error}")
    return screens


def load_groups(root: Path, warnings: list[str]) -> list[dict[str, Any]]:
    groups: list[dict[str, Any]] = []
    for folder in sorted((root / "groups").iterdir()) if (root / "groups").is_dir() else []:
        try:
            record = read_json(folder / "group.json")
            record["groupID"] = canonical_uuid(record["groupID"])
            record["pinIDs"] = [canonical_uuid(value) for value in record.get("pinIDs", [])]
            groups.append(record)
        except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
            warnings.append(f"ignored invalid group {folder}: {error}")
    return groups


def result_matches(root: Path, pin_id: str, revision_id: str) -> bool:
    path = root / "results" / f"{pin_id}.json"
    if not path.is_file():
        return False
    try:
        result = read_json(path)
        return (
            canonical_uuid(result["pinID"]) == pin_id
            and canonical_uuid(result["processedRevisionID"]) == revision_id
        )
    except (OSError, ValueError, KeyError, json.JSONDecodeError):
        return False


def scan(root: Path) -> dict[str, Any]:
    warnings: list[str] = []
    screens = load_screens(root, warnings)
    groups = load_groups(root, warnings)
    pending: list[dict[str, Any]] = []
    pins_root = root / "pins"
    folders = sorted(pins_root.iterdir()) if pins_root.is_dir() else []

    for folder in folders:
        if not folder.is_dir():
            continue
        try:
            folder_pin_id = canonical_uuid(folder.name)
            current = read_json(folder / "current.json")
            revision_id = canonical_uuid(current["revisionID"])
            revision_root = folder / "revisions" / revision_id
            record_path = revision_root / "pin.json"
            note_path = revision_root / "note.md"
            screen_image = folder / "assets/screen.png"
            crop_image = folder / "assets/crop.png"
            record = read_json(record_path)
            pin_id = canonical_uuid(record["pinID"])
            record_revision_id = canonical_uuid(record["revisionID"])
            screen_id = canonical_uuid(record["screenID"])
            if pin_id != folder_pin_id or record_revision_id != revision_id:
                raise ValueError("folder, current.json, and pin.json UUIDs disagree")
            if not screen_image.is_file() or not crop_image.is_file():
                raise ValueError("current pin is missing a screenshot or crop")
            if result_matches(root, pin_id, revision_id):
                continue
            note = note_path.read_text(encoding="utf-8")
            attached_groups = [group for group in groups if pin_id in group["pinIDs"]]
            pending.append(
                {
                    "pinID": pin_id,
                    "revisionID": revision_id,
                    "screenID": screen_id,
                    "note": note,
                    "record": record,
                    "screen": screens.get(screen_id),
                    "groups": attached_groups,
                    "recordPath": str(record_path.resolve()),
                    "notePath": str(note_path.resolve()),
                    "screenImagePath": str(screen_image.resolve()),
                    "cropImagePath": str(crop_image.resolve()),
                }
            )
        except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
            warnings.append(f"ignored invalid pin {folder}: {error}")

    pending.sort(key=lambda item: (str(item["record"].get("createdAt", "")), item["pinID"]))
    return {"root": str(root), "pendingCount": len(pending), "pending": pending, "warnings": warnings}


def main() -> int:
    try:
        root = choose_root(parse_args().root)
        print(json.dumps(scan(root), ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except (OSError, ValueError) as error:
        print(f"scan_pending: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
