#!/usr/bin/env python3
"""Atomically record a one-line result for a current PinPatch revision."""

from __future__ import annotations

import argparse
import json
import os
import sys
import uuid
from pathlib import Path
from typing import Any, Callable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--pin-id", required=True)
    parser.add_argument("--revision-id", required=True)
    parser.add_argument("--status", required=True, choices=("resolved", "no-change", "blocked"))
    parser.add_argument("--summary", required=True)
    return parser.parse_args()


def canonical_uuid(value: Any) -> str:
    return str(uuid.UUID(str(value))).lower()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def verify_current(root: Path, pin_id: str, revision_id: str) -> None:
    pin_root = root / "pins" / pin_id
    if not pin_root.is_dir():
        raise ValueError(f"pin no longer exists: {pin_id}")
    current = read_json(pin_root / "current.json")
    if canonical_uuid(current["revisionID"]) != revision_id:
        raise ValueError(f"stale revision for {pin_id}; rescan before recording")
    record = read_json(pin_root / "revisions" / revision_id / "pin.json")
    if canonical_uuid(record["pinID"]) != pin_id or canonical_uuid(record["revisionID"]) != revision_id:
        raise ValueError("pin.json UUIDs do not match the requested current revision")


def atomic_write(path: Path, data: bytes, revalidate: Callable[[], None]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / f".{uuid.uuid4()}.tmp"
    descriptor: int | None = None
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        written = 0
        while written < len(data):
            count = os.write(descriptor, data[written:])
            if count <= 0:
                raise OSError("result write made no progress")
            written += count
        os.fsync(descriptor)
        if os.fstat(descriptor).st_size != len(data):
            raise OSError("temporary result size does not match encoded data")
        os.close(descriptor)
        descriptor = None
        revalidate()
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if descriptor is not None:
            os.close(descriptor)
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def main() -> int:
    args = parse_args()
    try:
        root = args.root.expanduser().resolve()
        pin_id = canonical_uuid(args.pin_id)
        revision_id = canonical_uuid(args.revision_id)
        summary = " ".join(args.summary.split())
        if not summary:
            raise ValueError("summary must not be empty")
        verify = lambda: verify_current(root, pin_id, revision_id)
        verify()
        result = {
            "pinID": pin_id,
            "processedRevisionID": revision_id,
            "status": args.status,
            "summary": summary,
        }
        payload = (json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
        atomic_write(root / "results" / f"{pin_id}.json", payload, verify)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"record_result: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
