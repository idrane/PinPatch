---
name: pinpatch-apply
description: Inspect unprocessed PinPatch iOS UI notes and screenshots from local simulator or exported storage, make the smallest matching code changes, run relevant tests, and atomically record one-line UUID-based results. Use when asked to apply, process, fix, or review notes captured with PinPatch.
---

# Apply PinPatch Notes

Process only the current unhandled revision of each PinPatch pin. Treat UUID folders as canonical, inspect images directly, preserve unrelated user changes, and never create a commit.

## Locate and scan

Resolve all resource paths relative to the directory containing this `SKILL.md`; do not assume the user's repository has a `scripts` directory. Run:

```bash
python3 <pinpatch-apply-skill-directory>/scripts/scan_pending.py
```

Pass `--root "/path/to/Library/Application Support/PinPatch"` when discovery reports zero or multiple roots. An explicitly exported PinPatch folder is also valid.

Use the script output as the work queue. It scans `pins`, `screens`, `groups`, and `results`; it intentionally ignores `index.json`. Do not identify pins by display labels such as `1-1`.

Read [references/schema.md](references/schema.md) if a record needs manual diagnosis.

## Inspect each pending revision

For every pending item:

1. Open both `screenImagePath` and `cropImagePath` with the available image-viewing tool.
2. Read `note`, `record`, `screen`, and every attached group instruction.
3. Use accessibility identifiers, controller chains, view/root types, actions, and coordinates only as search hints. Find the actual implementation with `rg` before editing.
4. When a group spans pins, interpret its common instruction once and apply it consistently to all members, including members on other screens.

Do not infer identity from screen or pin numbering. Use only `screenID`, `pinID`, `revisionID`, and `groupID`.

## Change and verify code

Make only the code changes needed by the current notes. Preserve existing local modifications and project conventions. Do not add networking, upload artifacts, or send PinPatch data outside the machine.

Run the narrowest relevant tests first, then broader tests when the change crosses shared behavior. Do not create a git commit.

## Record results

Immediately before recording, rescan or let the result script verify that the pin still exists and `current.json` still points to the processed revision.

Run one command per pin:

```bash
python3 <pinpatch-apply-skill-directory>/scripts/record_result.py \
  --root "/path/to/PinPatch" \
  --pin-id "<pin UUID>" \
  --revision-id "<revision UUID>" \
  --status resolved \
  --summary "Changed the checkout button spacing and verified its UI test."
```

Use `resolved` after a code change, `no-change` when the requested state is already present, and `blocked` only when a concrete blocker remains after local investigation. Keep the summary to one useful line. Record a result for every processed pin, even when multiple pins share one code change.

If the script rejects a stale revision, do not overwrite the result. Rescan and process the new current revision instead.

## Safety boundaries

- Treat `index.json` as a disposable cache, never as source of truth.
- Do not edit PinPatch note, screenshot, current revision, screen, or group source files.
- Do not record success before tests or before confirming the requested behavior in code.
- Stop cleanly if protected data is unavailable or storage cannot be read; do not change host-app runtime behavior to work around it.
