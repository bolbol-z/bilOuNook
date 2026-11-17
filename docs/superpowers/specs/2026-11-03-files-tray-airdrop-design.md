# Files Tray + AirDrop — design

Date: 2026-11-03
Status: approved (user option 1, 2026-11-03)

## Intent

Drag files onto the notch; they land in a Files Tray. Share them, including
multiple files, via the native macOS sharing UI (`NSSharingServicePicker`).
Inspired by NotchNook's Files/AirDrop panel.

## Decision

**Option 1 — Files tab + drag overlay** (approved):

- New `Files` tab after `Nook` (`[NookModule(), TrayModule()]` in the shared
  registry; `TrayModule: id="files", title="Files", icon="tray.fill"`).
- The Files tab renders the reference layout: a dashed "Files Tray" panel on
  the left and a solid blue "AirDrop" panel on the right. Reference image:
  an external design reference (not included in this repository).
- On a file drag entering the notch zone, `FileDropMonitor` expands the notch
  and switches to the Files tab. No always-visible drop overlay; the panel
  itself is always the drop target.
- When the drag session ends (drop or mouse up anywhere), `isActive` flips
  back to false; the Files tab stays open for the user to see/share the tray.

## Why not the alternatives

- **Third widget in the Nook page** — resizes the existing 420pt canvas for
  everyone and breaks the Media/Calendar layout contract.
- **Drag-only drop zone** — forces the user to keep dragging to interact; no
  persistent tray, no selection model, worse for sharing more than one file.

## Components

- `TrayStore` (`@MainActor @Observable`): `items`, `selection`, `rejectedCount`,
  `add/stage/remove/clear/toggleSelection/effectiveSelection`. Validation is
  file existence only; duplicates filtered by canonical URL.
  - **Access model**: BilouNook is not sandboxed, so ordinary user files are
    referenced in place; we never copy bytes. Security scopes are taken on
    staged URLs (process-wide) and released on remove/clear
    (`stopAccessingSecurityScopedResource`). Provider temp files that vanish
    after quit are out of scope — no persistence across launches (session
    only). Sharing failures surface to the picker; we never claim success.
- `FileDropMonitor` (AppKit global+local monitors for `.leftMouseDragged` and
  `.leftMouseUp`): detects file drags (`.fileURL`/`.fileContents` in the
  drag pasteboard) over the notch hot zone; flips the panel click-through off
  for the drag session and requests open with the new `.drag` trigger; reuses
  `InteractionRegion.hotZone` and the coordinator's own click-through rule.
- `FilesTrayView` (the Files tab): dashed drop zone `.onDrop(of: [.fileURL])`
  with `isTargeted` highlight; horizontal chip scroll; **no four-file cap**;
  for 5+ files a stacked preview cell with a badge showing the true count,
  chips remain scrollable so every file is reachable; per-item remove on
  hover; clear-all button; tap toggles multi-selection; empty state.
- `TrayShareView`: invisible NSView bridge anchoring
  `NSSharingServicePicker(items: selectedURLs)`; never `ShareLink` (we need
  the native picker for AirDrop specifically). Selection wins; empty
  selection shares everything.
- `TraySharePresenter` / `TrayShareAnchor`: plumbing from SwiftUI into the
  picker without fake AirDrop UI and without calling share until the user
  actually taps.

## Reused components

- `NotchState.requestOpen` (new `.drag` trigger), `InteractionRegion.hotZone`,
  `NotchCoordinator` click-through pattern, `ModuleRegistry`/`NotchModule`
  contract, `ModuleShellView` tab bar, `ModuleTabLayout` pills (2nd pill),
  `TabPillMetrics`, `NookLayout` constants, `NotchGeometryCache`.

## Layout (420×118, 2× backing, hardware notch overlay)

```
margin 8          gap 6        margin 8
┌─────────────────┬─────────────┐  ← y = 34 (rowTop), height 75, bottom 9
│  Tray panel     │ AirDrop     │
│  dashed border  │ solid blue  │
│  250pt          │ 142pt       │
└─────────────────┴─────────────┘
```

Reference measured colors: dashed panel `white 22%`, AirDrop panel
`#00467A`, accent `#0C84FF`, glyph azure `#5AA9FF`.

## What verifies this works

- `TrayStoreTests` — 9 tests: add/dedupe/cap-less count/reject missing/
  directories/selection/remove/clear/stage-reference/rejection counter.
- `FilesTraySnapshotTests` — 4 snapshots into `build/screens/`:
  empty tray, two files, six files with selection, and the full 420×118 notch
  with the Files tab selected (pills visible, 5pt grid, notch overlay).
- Full test suite + `scripts/smoke.sh` + Release build.

Drops are accepted on the entire 420×75 Files row (both panels + padding); never on the media/calendar page, the tab bar, or while closed.

## Remaining / not done

- No persistence across launches (items are cleared on quit; scope is held
  for the process lifetime only).
- Image thumbnails are not generated; the system file icon (`NSWorkspace`)
  is used — acceptable per spec ("native file icon **or thumbnail**").
- Manual verification (drop by hand, click-through, share picker) is
  UNVERIFIED — the CLI/test environment cannot launch the GUI.
