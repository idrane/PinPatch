# PinPatch storage schema

Treat the UUID folders below as canonical. `index.json` is a disposable UI cache and may be absent, stale, or corrupt.

```text
PinPatch/
├── manifest.json
├── index.json
├── screens/<screenID>.json
├── pins/<pinID>/
│   ├── assets/screen.png
│   ├── assets/crop.png
│   ├── revisions/<revisionID>/pin.json
│   ├── revisions/<revisionID>/note.md
│   └── current.json
├── groups/<groupID>/group.json
├── groups/<groupID>/note.md
└── results/<pinID>.json
```

`current.json` selects the only live revision. A pin is pending when `results/<pinID>.json` is absent, invalid, or its `processedRevisionID` differs from the current `revisionID`.

Identifiers are stable UUIDs:

- `screenID`: persistent screen identity
- `pinID`: persistent pin identity
- `revisionID`: one immutable note revision
- `groupID`: cross-screen common instruction identity

Visible labels such as `1-1` are recalculated presentation values. Never use them in filenames, links, lookups, or results.

Screen fingerprints contain framework, leaf controller kind, optional SwiftUI root type and semantic digest, normalized title, modal state, and algorithm version. They are search context, not source-code paths.

SwiftUI limitation: public APIs cannot always reveal a `NavigationStack` destination's concrete type or expose every pure-SwiftUI semantic node through UIKit accessibility containers. Screens with the same publicly visible hosting root type, normalized title, modal state, and accessibility semantic structure can merge. UIKit screens with the same leaf controller kind, normalized title, and modal state can also merge.

Write results only through `scripts/record_result.py`. It validates the current revision immediately before an atomic replace and writes:

```json
{
  "pinID": "uuid",
  "processedRevisionID": "uuid",
  "status": "resolved | no-change | blocked",
  "summary": "one line"
}
```
