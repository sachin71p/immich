# WP-C — Window chrome, toolbar, sidebar, menu bar, search field

Read first: **`SPEC-TOOLBAR-SETTINGS.md` (binding, owner-reviewed)**, then `PLAN.md` (§0, §1 C-rows, §3) and `EVIDENCE.md` (Library and "Menu bar" bullets for both apps).
Photos reference: `evidence/photos-screens/01-library-allphotos.png`, `06-collections-top.png`,
`07-map.png`, and the menu contents listed in EVIDENCE.md.

Base: the Gate 1 merge. Current code: `MacMainWindow.swift` (toolbar :373–399), `MacSidebar*.swift`,
`MacMenus.swift`, and commands in `HeirloomMacOSApp.swift`.

## Steps

1. **Menu bar P0 (C1).**
   - Fix the duplicate View menu. Find both definitions: SwiftUI `CommandGroup`/`CommandMenu` plus the
     system View menu. Use `CommandGroup(replacing: .toolbar)` / `.sidebar` instead of a new
     `CommandMenu("View")`.
   - Build File / Image / View in Photos' order with Photos' shortcuts (EVIDENCE.md), limited to
     supported actions.
   - Commands act on the **focused scene value**: the viewer's current asset when the viewer is open,
     else the grid selection (`FocusedValue`). This fixes "Add to Album…" being disabled in the viewer.
   - View › Library ⌃1, Collections ⌃2, Pinned ›, Albums ›, Shared Libraries ›, Media Types ›,
     Utilities › navigate the sidebar.
   - View › Aspect Ratio Grid ⌥T, Zoom In/Out, Hide Sidebar ⌃⌘S.
   - Add a UI test that each top-level menu appears exactly once.
2. **Glass toolbar and title (C2).**
   - Unified toolbar style with macOS 27 glass (`.toolbarBackgroundVisibility(.hidden)` / system glass),
     so content scrolls beneath it.
   - Navigation title "Library" plus a subtitle bound to WP-G's visible date range or the selection count.
     Page titles: album name with "N Photos, M Videos · Month yyyy".
   - Back/forward buttons for drill-downs.
3. **Toolbar items (C3).** Photos order, per PLAN C3:
   - The scope icon menu replaces the "All Libraries" text pop-up. Heirloom scopes: All Libraries,
     Personal, each Shared Library.
   - Zoom capsule (− | +).
   - Years/Months/All Photos segmented control.
   - Filter icon menu: All Items, Favorites, Edited, Photos, Videos, plus Show Screenshots, Show Shared
     With Me.
   - Sort icon menu.
   - "…" menu: Sync Now, Import…, New Album…, Slideshow (if supported).
   - Info, Share, Favorite, Rotate.
   - Search field.
   - Remove the Select button (WP-G's selection model) and the standalone Sync button. Sync status goes in
     a small sidebar footer.
   - Toolbar customization is allowed (`NSToolbar` identifiers stable).
4. **Sidebar (C4).**
   - Library, Collections.
   - **Pinned:** owner-editable via right-click › Unpin and "Pin to Sidebar" from Collections. Default
     items: Favorites, Recently Saved, Map, Videos, Screenshots, People, Recently Deleted (lock icon
     plus authentication if Immich locked is enabled).
   - **Shared Libraries** (kept).
   - **Albums:** All Albums, then albums and folders with 16 pt rounded thumbnails of the key asset.
   - Remove Search and the Media Types section (they move to Collections and View › Media Types).
   - Persist expansion state and pins in UserDefaults.
5. **Search field (C5).**
   - `NSSearchToolbarItem`. On focus it shows a popover: Recently Viewed / Recently Edited / Recently
     Shared shortcuts.
   - Typing shows completions from `PhotosCore/Search` (WP-P provides `suggestions(for:) async ->
     [Suggestion(title, kind, count)]`) with counts.
   - Return or picking a suggestion navigates to the Search results destination. WP-P renders it; pass
     the query via the router.
   - Esc clears.
6. **Toolbar exactness (C7).** Implement `SPEC-TOOLBAR-SETTINGS.md` §1–§2 item by item (T-1…T-12, TV-1…TV-3; coordinate the TV rows with WP-V, which owns the viewer's items). Rebuild `pairs/T1` and `pairs/T2` from AFTER captures, with Heirloom now on top of Photos, and attach them.
7. **Settings (C8, C9).** Implement `SPEC-TOOLBAR-SETTINGS.md` §3: the four tabs, the label-column layout and the merged items. Keep every existing preference key working. **No "Download Originals" option.** Rebuild the `pairs/S1…S4` equivalents per tab.
8. **Extras (C6).** Hide Sidebar, full-screen toolbar behaviour, and the Shared Library suggestion banner.
   The banner is P2; decide with the owner.

## Proof (`reports/WP-C-REPORT.md`)
- Screenshots of the toolbar and sidebar beside Photos.
- Menu bar screenshots for File/Image/View beside Photos.
- UI tests: unique menus, ⌃1/⌃2 navigation, Add to Album enabled in the viewer (fixture), search
  suggestions appear.

## Design references (open these before coding)
`DESIGN-REFERENCE.md` pairs: **T1, T2, S1–S4, L1, L4, L5, L6, M1–M4, P2 (search field)**, in `evidence/design/pairs/`. Match the left side (Apple Photos).
Your report must include AFTER captures of the same screens (`scripts/heirloom-parity/pairs.sh` rebuilds
the pairs).

## Regression tests (mandatory; see `TEST-PLAN.md` §2)
Implement every test listed for **C1–C9 (C7–C9 tests are in SPEC-TOOLBAR-SETTINGS §5), and the router side of V15** in TEST-PLAN §2, in files under `Apps/macOS/Tests/<Area>/`,
`Apps/macOS/UITests/<Area>/` and/or `PhotosCore/Tests`.
- **Red first:** run each new test on base `9b9bb7f2e` (or on your branch before the fix) and record
  the failure, then fix and record the pass.
- Use `AXIDs` identifiers, the fixture library (`-HeirloomFixture`), `SyntheticEvents` for trackpad
  phases, and `GestureInputs` controllers for pinch and smart zoom. All of these come from WP-T.
- Report table: `ID | test(s) | red on base | green now | notes`. Only rows marked **H** in TEST-PLAN
  may lack an automated test.
