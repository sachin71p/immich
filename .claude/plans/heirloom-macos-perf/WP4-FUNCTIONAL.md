# WP4 — Functional fixes: every control works as designed

Read `PLAN.md` first. **Prerequisite:** WP2 is merged. Runs in parallel with WP3 and WP5. Owned files:
- `MacMoveSheet.swift`, `MacLibrarySheets.swift`, `MacImport.swift`, `MacSidebarModel.swift`,
  `MacSidebar.swift`, `MacMenus.swift`, `MacStorageView.swift`, `MacSettings.swift`,
  `MacDragDrop.swift`, `MacSelection.swift`, `HeirloomMacOSApp.swift`, `MacConnectView.swift`,
  `Apps/macOS/UITests/**`, `Apps/macOS/Sources/FixtureSeed.swift`
- `MacMainWindow.swift`, which WP2 has finished: toolbar, sheets wiring and titles only. Don't touch
  `MacTimelineGridPane` internals.

Destructive flows (trash, lock, move, album create/delete, shared-library create, import) must be
verified only with XCUITest under `--fixture-seed` or against `make mock-server`, **never** against the
owner's real server.

## Step 1 — Control inventory (do this first; don't trust `01-map.md` or `06-facts.md` §4)
Read every file in `Apps/macOS/Sources`. For every `Button`, `Menu`, `Toggle`, `Picker`,
`CommandMenu`/`CommandGroup` item, toolbar item, `.contextMenu`, `.onKeyPress`, `.keyboardShortcut`,
sheet and alert, record:

| file:line | label / shortcut | where visible | action target | real effect? (yes / toast-only / no-op / stub / broken) | fix |

Save this table as `reports/WP4-CONTROLS.md`. Every row that isn't "yes" must be fixed in this WP, or
explicitly assigned to WP5 (viewer files) or WP6 (Memories/Map/People/Collections/Search files), with a
reason.

## Step 2 — Known defects (from `05-ui-audit.md`)
- **U12 Move sheet trap** (verified: `MacMoveSheet` has no Cancel button and no Escape handling):
  - Add a bottom button row: Cancel (`.keyboardShortcut(.cancelAction)`) and a disabled-until-chosen
    **Move** (`.defaultAction`).
  - Tapping a row selects it (checkmark); Move performs the move.
  - Show the current container as a disabled row with "Current" (U13 clarity).
  - Space moves require confirmation, the same as library moves ("Move N items to <name>? Members of
    <name> will see them.").
  - Show a progress state while moving and an error inline.
  - Apply the same Cancel/Escape/default-button pattern to **every** sheet: `MacAddToAlbumSheet`,
    `MacNewAlbumSheet`, `MacNewSpaceSheet`, `MacSpaceManageSheet`, `MacImportChooserSheet`,
    `MacCameraImportView`. Verify each one yourself.
- **Quit while a sheet is open**: ⌘Q and AppleScript `quit` must work. In `HeirloomMacOSApp`, add an
  `NSApplicationDelegateAdaptor` whose `applicationShouldTerminate` returns `.terminateNow` (sheets hold
  no unsaved data), except while an upload or move is in progress. In that case, ask with an NSAlert
  ("Quit anyway? N uploads in progress").
- **U5 toolbar shift**: give the title/subtitle block a fixed `frame(width: 260, alignment: .leading)`
  with truncation, so toolbar items don't move when the subtitle changes.
- **U15/U16/U18 toolbar per destination**: grid-only items (Years/Months/All Photos, zoom −/+, aspect
  toggle, filter menu, sort, Select, Rotate, Favorite, Info, Share) appear only when the detail view is
  the grid. Map, People, Memories, Collections, Search, All Albums and Duplicates get their own minimal
  toolbar: title, Sync, Search field.
- **U24/U25 titles**: `SidebarDestination.title` returns generic text for `.space`, `.album` and
  `.externalLibrary`. Add `func title(in state: MacAppState) -> String` that resolves the names, and use
  it for the toolbar title and window title.
- **U17 footer**: after WP2 the footer reads the current snapshot. Verify that Recently Saved and other
  destinations show their own counts.
- **U23 empty states**: when `snapshot.rows.isEmpty && loader.phase == .loaded`, show
  `ContentUnavailableView` with a per-destination message ("No Selfies", "No Favorites — Click ♡ on a
  photo to add it", "No Screenshots", …) and a relevant SF Symbol.
- **U27 Rotate** (grid toolbar, Image › Rotate Clockwise ⌘R, and context menu):
  - Investigate `PhotosCore/Sources/Editing` and `MacEditView.swift`: is there a persisted edit path
    that can apply a 90° rotation to an asset (a recipe save plus server upload)?
    - **If yes:** implement `rotate` in `gridActions` for all selected assets through that path, with a
      progress toast and failure reporting. Post `MacAssetChange.edited(ids:)`.
    - **If no:** remove Rotate from the grid toolbar and context menu, and disable the menu item in grid
      context with the tooltip "Open a photo to rotate". No silent no-ops.
  - Record the decision in the report. WP5 needs it for the viewer: write it at the top of
    `reports/WP4-REPORT.md` as soon as it's decided.
- **U3/U26**: log every mutation failure via `HeirloomLog.ui` with the error. User-facing toasts get
  human text, never `localizedDescription` of a `CancellationError`.
- **Share toolbar button**: must open `NSSharingServicePicker` with the originals of the selected assets
  (download to a temp dir via `MacExporter`, with progress for > 3 items). Disable it with nothing
  selected.
- **Info toolbar button in grid**: opens the viewer with the inspector shown (current behavior), or, if
  WP5 adds a standalone inspector, shows that. Keep the current behavior unless WP5 reports otherwise.
- **Sidebar**:
  - "New…" under Shared Libraries and "New Album…" must open their sheets and create the object
    (mock-server verified).
  - Albums disclosure must expand and collapse and persist its state.
  - Drag-to-album and drag-to-shared-library drop targets must work (fixture test).
- **Settings and Storage**: every control persists and has an effect. Record it in the controls table.

## Step 3 — UI tests (XCUITest, `--fixture-seed`)
Extend `MacSmokeTests` (or add files) with:
- open each sidebar destination and assert its title;
- Move sheet: opens, Cancel closes, Escape closes, ⌘Q works while it's open (use
  `XCUIApplication.terminate` as a fallback check);
- each sheet: Cancel and Escape close it;
- select 2 items, favorite, then assert the heart badge (accessibility value);
- trash in fixture mode, then the item is gone from the grid without a full reload (assert the
  remaining count);
- toolbar items hidden on Map/People/Memories.

If `FixtureSeed` lacks the data (a space, an album), extend it.

## Acceptance
- Every row in `WP4-CONTROLS.md` is "yes", or assigned to WP5/WP6 with a reason.
- The Release build, PhotosCore tests and macOS UI tests pass.
- Report: `reports/WP4-REPORT.md`, with the Rotate decision at the top.
