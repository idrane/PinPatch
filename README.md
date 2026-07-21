# PinPatch

> Shake your app. Pin what is wrong. Let Codex patch it.

PinPatch is the tool I wanted every time someone sent me a screenshot with a message like “this button feels off.” The screenshot showed the problem, but not the screen, the exact UI element, or whether somebody had already fixed it.

With PinPatch, a tester can shake a running iOS app, pin the problem in place, crop the important area, and leave a short instruction. Codex can then read that feedback, find the relevant code, make the smallest useful change, run the appropriate tests, and record what happened.

I built PinPatch for the **Developer Tools** category of [OpenAI Build Week](https://openai.devpost.com/). It is local-first: there is no account, dashboard, telemetry, or feedback server.

## The problem

Visual feedback loses context surprisingly fast. A screenshot gets separated from the app state, “move this up” becomes ambiguous, and the developer has to reproduce the screen before even looking for the right file. When several revisions of the same note are floating around, it is also easy for an agent to apply stale feedback twice.

PinPatch keeps the useful context together:

- the full screen and a precise crop
- a stable screen, pin, and revision identity
- an optional tag and natural-language instruction
- accessibility and view-controller hints for code search
- grouped instructions spanning multiple screens
- explicit processing results, so Codex never silently reapplies stale work

## The short version

```text
Tester                           Codex
──────                           ─────
Shake the running app
  → tap the UI problem
  → crop + write a note
  → share ZIP or keep locally  → scan pending UUID revisions
                               → inspect screen + crop
                               → find the real implementation
                               → make the smallest code change
                               → run relevant tests
                               → record resolved / no-change / blocked
```

The iOS package captures the evidence. The bundled `pinpatch-apply` Codex skill does the reasoning-heavy work. Feedback stays on the device or simulator unless the tester explicitly exports a portable ZIP.

## Why I made it this way

- **It should be easy to try.** Add one dynamic Swift Package product. There is no `AppDelegate`, `SceneDelegate`, or feature-code integration.
- **The note should live next to the problem.** Every pin includes the full screen, a precise crop, target hints, and a plain-language request.
- **Codex should receive a workflow, not a vague prompt.** The included skill covers discovery, image inspection, code search, verification, and result recording.
- **Old feedback should stay old.** Stable UUIDs and immutable note revisions stop stale exports from silently being applied again.
- **A debugging tool should not become a data pipeline.** The package has no networking, telemetry, cloud container, or upload path.
- **The host app comes first.** Normal touches and accessibility navigation pass through in view mode, and PinPatch failures stay inside PinPatch.

## 3-minute demo path

This is the quickest way for a judge to see the full loop:

1. Run an iOS app with the `PinPatch` product attached and shake the simulator or device.
2. Choose **Add Pin**, tap the UI problem, adjust the crop, and write a request.
3. Open **Pin List** and export the feedback, or leave it in the simulator for Codex to discover.
4. Ask Codex: `Apply the pending PinPatch feedback.`
5. Review the code change, the relevant test result, and the recorded PinPatch outcome.

Pins can also be grouped across screens when one instruction affects several UI elements, but that is optional for the basic test path.

## How Codex and GPT-5.6 were used

I used Codex powered by GPT-5.6 throughout the build, not as a last-minute API badge. The most useful part was being able to move between product reasoning, implementation, and verification without losing the constraints of the project.

- **Planning and architecture:** GPT-5.6 helped turn my “no host source edits and no network” rule into a dynamic Swift package, a single shake hook, scene-specific overlay state, and UUID-based local storage.
- **Implementation:** I used Codex to build and refine the UIKit overlay, four-corner crop flow, screenshot capture, Markdown/ZIP export, recovery behavior, and UIKit/SwiftUI screen inspection.
- **Testing:** Codex helped turn edge cases into Swift and Python tests, audit the package for forbidden networking and unsafe crash paths, and separate simulator-tested behavior from device-only acceptance checks.
- **The developer workflow itself:** I built the `pinpatch-apply` skill with Codex so GPT-5.6 can inspect screenshots and metadata, connect them to an unfamiliar codebase, make a focused edit, verify it, and record a result without reprocessing stale revisions.

The boundary is intentional: PinPatch captures trustworthy local evidence, while GPT-5.6 handles the part that benefits from judgment—understanding a visual request and tracing it to the right implementation. That keeps the runtime small and deterministic while giving Codex much better context than a screenshot alone.

## Quick start

### Supported platforms

- iOS 17+
- Swift 5.9+
- UIKit or SwiftUI host apps
- Xcode with Swift Package Manager
- Codex for applying captured notes

### Install the iOS package

1. In Xcode, choose **File → Add Package Dependencies**.
2. Enter `https://github.com/idrane/PinPatch`.
3. Add the dynamic **PinPatch** product to the app target.
4. Build and run. No import or initialization call is needed.

Remove the package product from the target to remove the runtime and UI completely.

### Install the Codex skill

Copy [`skills/pinpatch-apply`](skills/pinpatch-apply) into your Codex skills directory:

```bash
mkdir -p ~/.codex/skills
cp -R skills/pinpatch-apply ~/.codex/skills/pinpatch-apply
```

Restart Codex if it was already open. The skill activates when you ask Codex to apply, process, fix, or review feedback captured with PinPatch.

### Testing path for judges

The repository includes a valid sample export at [`Tests/SkillFixtures/PinPatch`](Tests/SkillFixtures/PinPatch), so the developer-tool path can be tested without first modifying another iOS app.

```bash
# Validate the sample queue
python3 skills/pinpatch-apply/scripts/scan_pending.py \
  --root Tests/SkillFixtures/PinPatch

# Run the skill workflow tests
python3 -m unittest discover -s Tests/SkillScriptTests -v
```

The first command should list the pending fixture revision. The second runs the skill workflow tests. To run the complete iOS package test suite:

```bash
xcodebuild -scheme PinPatch \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/PinPatchDerivedData test
```

## Architecture

The host app does not import or initialize PinPatch. Add the dynamic `PinPatch` Swift package product to the app target to enable it; remove that package product to remove its runtime and UI. No app source, `AppDelegate`, or `SceneDelegate` change is required.

## Requirements and guarantees

- iOS 17 or newer, Swift tools 5.9
- UIKit and SwiftUI host apps
- no external package dependency
- no `URLSession`, network framework, socket, telemetry, or upload path
- no iCloud container, CloudKit, Documents, or ubiquitous-item storage
- PinPatch storage excluded from device backup and protected with `completeUntilFirstUserAuthentication`
- failures remain inside PinPatch; production sources contain no `fatalError`, force unwrap, or assertion-based recovery

## In-app usage

1. Shake the device to enable PinPatch. The successful toggle gives haptic feedback. A second event within 500 ms is ignored.
2. A shake is ignored while any `UITextInput` is first responder, including the PinPatch note editor.
3. In view mode, inspect existing noninteractive pins while the host app continues receiving touches, scrolling, gestures, keyboard input, and accessibility navigation outside PinPatch controls.
4. Choose **Add Pin**, tap a target, adjust all four crop corners, choose an optional tag, and enter the requested change.
5. Open **Pin List** to edit or delete notes, select pins across screens and add one shared link instruction, copy or share Markdown, share a system-created ZIP, or delete everything after confirmation.

Each connected `UISceneSession` has a separate overlay, mode, active crop flow, and controls. A shake toggles only the scene containing the receiving window.

## Storage

PinPatch stores canonical UUID records under:

```text
Library/Application Support/PinPatch/
├── manifest.json
├── index.json
├── screens/<screenID>.json
├── screens/<screenID>/screen.png
├── pins/<pinID>/
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

New pins and groups are fully written and synchronized in `.staging` before same-volume renames. The first completed pin for a screen saves one shared full-screen screenshot under that screen ID; later pins reuse it, and deleting the screen's last pin removes it. Note edits write a new immutable revision, atomically replace `current.json`, and then remove the old revision. Startup removes abandoned staging, trash, non-current revisions, and orphan screen screenshots, and rebuilds screen mappings or the index from canonical folders.

On a simulator, locate storage with:

```bash
find ~/Library/Developer/CoreSimulator/Devices -path '*/Library/Application Support/PinPatch' -type d
```

## Screen identity

Screen fingerprints use only the normalized title explicitly exposed by the visible navigation controller. Accessibility headers, framework type, hosting-controller type, SwiftUI root type, and presentation style are not identity inputs because they were either inconsistent or identical across observed screens.

Title normalization applies Unicode NFC and whitespace cleanup, then masks only explicitly marked order/ID/UUID/date/time values. Ordinary numbers and room, stage, and floor labels remain, so `Room 301` and `Room 302` are distinct.

Public API and zero-source-integration constraints impose these limits:

- Screens with the same normalized title merge regardless of UIKit or SwiftUI implementation details.
- All untitled screens merge. Give navigation destinations distinct titles when they must have separate Screen IDs.

Fingerprint version-only migrations retain the existing `screenID` through aliases. If the registry is absent or corrupt, PinPatch reconstructs it from existing pin revisions.

## Shake and interaction architecture

The only shake path is `UIWindow.motionEnded(_:with:)`. PinPatch connects it once, always calls the original implementation first, and handles only `.motionShake` completion. It does not hook `UIApplication.sendEvent`, use Core Motion, poll sensors, or install a fallback detector.

When disabled, the overlay window is removed. In view mode, its hit test returns views only for the floating button and open menu; marker views are noninteractive and excluded from accessibility. Pin placement uses a recognizer owned by the overlay and enabled only in edit mode, so no recognizer is added to a host window.

## Export and Codex skill

ZIP export asks `NSFileCoordinator` for a `.forUploading` snapshot of a prepared folder. The operating system creates the ZIP; PinPatch does not implement an archive format or choose per-file compression methods. It accepts only a nonempty regular output file and removes temporary export data when sharing ends.

The repository skill is at [`skills/pinpatch-apply`](skills/pinpatch-apply). Copy that directory into your Codex skills directory to install it. It handles live simulator storage plus one or many supplied ZIPs and export folders, safely prepares and scans batch inputs, exposes screen and crop image paths for direct inspection, and records one-line results only after rechecking that each pin and revision is still current.

## Build and test reference

```bash
xcodebuild -scheme PinPatch \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/PinPatchDerivedData test

python3 -m unittest discover -s Tests/SkillScriptTests -v
```

Physical-device shake accuracy, VoiceOver traversal, multi-window interaction, disk-full behavior, and Windows archive extraction remain device/environment acceptance checks; see [`Docs/Validation.md`](Docs/Validation.md).
