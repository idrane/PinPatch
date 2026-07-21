#!/usr/bin/env python3
"""Fail when PinPatch v1 source invariants drift."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE_FILES = sorted((ROOT / "Sources").rglob("*"))
SOURCE_FILES = [path for path in SOURCE_FILES if path.suffix in {".swift", ".m", ".h"}]
SOURCES = "\n".join(path.read_text(encoding="utf-8") for path in SOURCE_FILES)
PACKAGE = (ROOT / "Package.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)
    print(f"ok: {message}")


def main() -> int:
    try:
        require("swift-tools-version: 5.9" in PACKAGE, "Swift tools version is 5.9")
        require(".iOS(.v17)" in PACKAGE, "minimum deployment is iOS 17")
        require("type: .dynamic" in PACKAGE, "product is a dynamic library")
        require(".package(" not in PACKAGE, "no external package dependency")

        banned_network = [
            "URLSession", "import Network", "CoreMotion", "CMMotion", "socket(",
            "CloudKit", "ubiquitousItem", "isUbiquitousItem", "telemetry",
        ]
        for token in banned_network:
            require(token not in SOURCES, f"source excludes {token}")
        require("sendEvent" not in SOURCES, "shake path does not hook UIApplication.sendEvent")

        crash_patterns = [r"\bfatalError\s*\(", r"\bassert\s*\(", r"\bassertionFailure\s*\(",
                          r"\bprecondition(?:Failure)?\s*\(", r"\btry!\b", r"\bas!\b"]
        for pattern in crash_patterns:
            require(re.search(pattern, SOURCES) is None, f"source excludes crash primitive {pattern}")

        shake_file = ROOT / "Sources/PinPatchBootstrap/PPShakeHook.m"
        shake_source = shake_file.read_text(encoding="utf-8")
        require("+ (void)load" in shake_source, "referenced Objective-C shake class owns automatic +load bootstrap")
        require("class_addMethod(" in shake_source, "inherited motion responder is overridden only on UIWindow")
        require("PinPatchOriginalMotionEnded(window, @selector(motionEnded:withEvent:)" in shake_source,
                "original responder is invoked with its original selector")
        require("method_exchangeImplementations" not in shake_source, "shake hook does not exchange inherited responder selectors")
        other_motion_files = [
            path for path in SOURCE_FILES
            if path != shake_file and "motionEnded" in path.read_text(encoding="utf-8")
        ]
        require(not other_motion_files, "no secondary shake implementation exists")

        host_gesture_files = [ROOT / "Sources/PinPatch/Runtime.swift", ROOT / "Sources/PinPatch/ScreenInspector.swift"]
        require(
            all("addGestureRecognizer" not in path.read_text(encoding="utf-8") for path in host_gesture_files),
            "runtime installs no gesture recognizer on host windows or views",
        )
        require(re.search(r"[\"/]result/", SOURCES) is None, "no singular result directory path exists")
        require('"results"' in SOURCES, "canonical results directory is present")
        return 0
    except AssertionError as error:
        print(f"audit failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
