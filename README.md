# PinPatch

PinPatch is a local-only iOS 17+ annotation overlay. Shake the current window, place a pin, crop the screenshot with four corner handles, add a note, and let the bundled Codex skill apply only the unprocessed UUID revisions.

The host app does not import or initialize PinPatch. Add the dynamic `PinPatch` Swift package product to the app target to enable it; remove that package product to remove its runtime and UI. No app source, `AppDelegate`, or `SceneDelegate` change is required.

## Requirements and guarantees

- iOS 17 or newer, Swift tools 5.9
- UIKit and SwiftUI host apps
- no external package dependency
- no `URLSession`, network framework, socket, telemetry, or upload path
- no iCloud container, CloudKit, Documents, or ubiquitous-item storage
- PinPatch storage excluded from device backup and protected with `completeUntilFirstUserAuthentication`
- failures remain inside PinPatch; production sources contain no `fatalError`, force unwrap, or assertion-based recovery

## Use

1. Shake the device to enable PinPatch. The successful toggle gives haptic feedback. A second event within 500 ms is ignored.
2. A shake is ignored while any `UITextInput` is first responder, including the PinPatch note editor.
3. In view mode, inspect existing noninteractive pins while the host app continues receiving touches, scrolling, gestures, keyboard input, and accessibility navigation outside PinPatch controls.
4. Choose **핀 찍기**, tap a target, adjust all four crop corners, choose an optional tag, and enter the requested change.
5. Open **목록** to edit or delete notes, select pins across screens and add one shared link instruction, copy/share Markdown, share a system-created ZIP, or delete everything after confirmation.

Each connected `UISceneSession` has a separate overlay, mode, active crop flow, and controls. A shake toggles only the scene containing the receiving window.

## Storage

PinPatch stores canonical UUID records under:

```text
Library/Application Support/PinPatch/
├── manifest.json
├── index.json
├── screens/<screenID>.json
├── pins/<pinID>/
│   ├── assets/screen.png
│   ├── assets/crop.png
│   ├── revisions/<revisionID>/pin.json
│   ├── revisions/<revisionID>/note.md
│   └── current.json
├── groups/<groupID>/
├── results/<pinID>.json
├── .staging/
└── .trash/
```

`screens`, `pins`, `groups`, and `results` are canonical. `index.json` is only a rebuildable list cache. Labels such as `1-1` are presentation values and are never used for filenames, links, or processing state.

New pins and groups are fully written and synchronized in `.staging` before one same-volume rename. Note edits write a new immutable revision, atomically replace `current.json`, and then remove the old revision. Startup removes abandoned staging, trash, and non-current revisions and rebuilds screen mappings or the index from canonical folders.

On a simulator, locate storage with:

```bash
find ~/Library/Developer/CoreSimulator/Devices -path '*/Library/Application Support/PinPatch' -type d
```

## Screen identity

UIKit fingerprints use the leaf controller type, normalized title, and modal state. SwiftUI fingerprints add the hosting controller's generic content type when public metadata exposes it, plus a digest of stable visible accessibility roles, traits, identifiers, fixed control/header labels, hierarchy depth, and coarse layout.

Title normalization applies Unicode NFC and whitespace cleanup, then masks only explicitly marked order/ID/UUID/date/time values. Ordinary numbers and room/stage/floor suffixes remain, so `301호` and `302호` are distinct.

Public API and zero-source-integration constraints impose these limits:

- UIKit screens with the same leaf controller type, normalized title, and modal state merge.
- SwiftUI screens with the same root type, semantic structure, normalized title, and modal state merge.
- A `NavigationStack` destination's concrete type is not always publicly available. Different destinations with no title or accessibility identifiers and the same accessibility structure can merge.
- SwiftUI does not expose every pure-SwiftUI semantic node through public UIKit accessibility-container APIs in every rendering state. When no semantic nodes are publicly visible, identity falls back to root type, normalized title, and modal state, so structurally different destinations can still merge.

Fingerprint version-only migrations retain the existing `screenID` through aliases. If the registry is absent or corrupt, PinPatch reconstructs it from existing pin revisions.

## Shake and interaction architecture

The only shake path is `UIWindow.motionEnded(_:with:)`. PinPatch connects it once, always calls the original implementation first, and handles only `.motionShake` completion. It does not hook `UIApplication.sendEvent`, use Core Motion, poll sensors, or install a fallback detector.

When disabled, the overlay window is removed. In view mode, its hit test returns views only for the floating button and open menu; marker views are noninteractive and excluded from accessibility. Pin placement uses a recognizer owned by the overlay and enabled only in edit mode, so no recognizer is added to a host window.

## Export and Codex skill

ZIP export asks `NSFileCoordinator` for a `.forUploading` snapshot of a prepared folder. The operating system creates the ZIP; PinPatch does not implement an archive format or choose per-file compression methods. It accepts only a nonempty regular output file and removes temporary export data when sharing ends.

The repository skill is at [`skills/pinpatch-apply`](skills/pinpatch-apply). Copy that directory into your Codex skills directory to install it. It scans current UUID revisions rather than `index.json`, exposes the screen and crop image paths for direct inspection, and records one-line results only after rechecking that the pin and revision are still current.

## Build and test

```bash
xcodebuild -scheme PinPatch \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/PinPatchDerivedData test

python3 -m unittest discover -s Tests/SkillScriptTests -v
```

Physical-device shake accuracy, VoiceOver traversal, multi-window interaction, disk-full behavior, and Windows archive extraction remain device/environment acceptance checks; see [`Docs/Validation.md`](Docs/Validation.md).
