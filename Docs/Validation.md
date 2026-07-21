# Validation matrix

## Automated in this repository

- Swift package manifest resolves with no external dependencies.
- The complete package builds for a generic iOS Simulator destination.
- Title normalization keeps `Room 301` and `Room 302` distinct while masking explicit order IDs.
- A fingerprint version change preserves the existing `screenID` after restart.
- A screen's first pin creates one shared full-screen screenshot, later pins keep it unchanged, and the last pin deletion removes it.
- A failure before pin commit leaves no visible pin directory.
- A failure after a new revision directory is committed but before `current.json` swaps leaves the old revision current; the next startup removes the orphan.
- Deleted screen registry files and corrupt `index.json` rebuild from canonical pin folders.
- System folder-upload coordination produces a nonempty ZIP signature and Markdown includes stable UUIDs.
- The Codex scanner ignores corrupt `index.json`; UUID-matched results remove only the matching revision from the queue.
- The result writer rejects a stale revision and writes a normalized one-line result atomically.

## Source audit

- Exactly one shake implementation path exists: `UIWindow.motionEnded` in `PPShakeHook.m`.
- No `UIApplication.sendEvent`, Core Motion, sensor polling, URLSession, network framework, socket, telemetry, or third-party package dependency is present.
- All persistent identity and result paths use UUIDs and the directory name `results`.
- No host-window gesture recognizer is installed.
- Production code contains no `fatalError`, force unwrap, `assert`, `preconditionFailure`, or forced cast.

## Physical device acceptance

These checks require hardware or external applications and are not claimed by simulator unit tests:

1. Perform 100 normal shakes on an iPhone. Exclude events inside the 500 ms debounce window and while a `UITextInput` is first responder; require zero other misses and zero duplicate toggles.
2. Verify haptic feedback for each successful enable and disable.
3. Exercise a UIKit screen and a SwiftUI `NavigationStack` destination: shake, pin, capture, four-corner crop, note, list, edit, link, Markdown, and ZIP.
4. In disabled and view modes, regress host taps, scrolling, custom gestures, keyboard input, and VoiceOver focus/activation.
5. Open two iPad scenes and verify overlay state, edit mode, crop flow, and markers do not cross scenes.
6. Lock the device before first unlock and confirm PinPatch operations fail quietly while the host app remains usable; unlock and retry.
7. Fill the simulator/device storage or inject filesystem denial and confirm no partial canonical pin appears and the host app remains alive.
8. Restart after each storage checkpoint and require either a complete pin or no pin; never accept a partial pin.
9. Inspect the PinPatch root backup resource value and confirm it remains excluded after relaunch.
10. Extract an exported ZIP with macOS Archive Utility/Finder, Windows Explorer, 7-Zip, `unzip -t`, and Python `zipfile`.

The design does not add a second shake detector when a hardware run fails. Diagnose whether the host's custom `UIWindow` override calls `super.motionEnded` first; any fallback requires a separate product decision because the v1 contract fixes one detection path.
