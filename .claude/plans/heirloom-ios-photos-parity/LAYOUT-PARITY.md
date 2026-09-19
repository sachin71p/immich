# iOS Photos Layout-Parity Plan (from 18 stitched pairs)

## Goal
Close the visible layout gaps between Heirloom iOS and native Photos across the 15 dark pairs (01–15) plus 3 light halves (L01/L02/L05) in `.claude/plans/heirloom-ios-photos-parity/assets/pairs/`, starting with the main Library view.

## Success Criteria
- Library at every zoom matches Photos column/density range; floating date badge appears while pinched/fast-scrolling (G5 green).
- Viewer, info panel, editor, search, collections, and context menu match Photos layout element-for-element except named non-goals.
- Re-captured pairs show no unexplained structural differences; Wave-5 pair tour stays green.

## Context And Current Facts
- Pairs are stitched Photos-side / Heirloom-side captures on the owner's iPhone 17 Pro Max (Release). Light halves are mixed-mode: L01/L02 Heirloom sides were captured in dark mode (moon in status bar), so light-adaptation judgments need re-capture, not code reads.
- Grid core is healthy: data path 1–25 ms, early-out + keyed retain + source cache shipped (parity-f, PR #4). Remaining work is chrome, density, and data plumbing — no loader changes.
- Grounded code sites (verified this run):
  - Zoom range: `Library/LibraryView.swift:313-314` caps at 13 columns; Photos pinched-out shows ~15–20.
  - Floating badge code EXISTS (`Grid/PhotoGridViewController.swift:70-74,282-288`) but never appears in pairs and the G5 UI test is red — trigger/wiring, not new construction.
  - Viewer backdrop already adapts via `HeirloomAppearance.viewerBackdrop` (`Viewer/ViewerPager.swift:128-130`); L02 darkness is likely capture-mode, not a code gap.
  - Info panel EXIF gap is UI-side: `Viewer/ViewerInfoPanel.swift:250` renders "No exposure details".
  - Duplicate is deliberately omitted: `Grid/GridContextMenu.swift:17` (`AssetMutations` has no API) — the menu icon row can still ship without it.
  - Map tile is a text placeholder: `Collections.swift:259`.
- Non-goals (platform or server-blocked, not layout): Live Photos + LIVE badge, Apple Intelligence (Ask Siri, Image Search, visual lookup), iCloud-only surfaces (shared-library suggestion banner, iCloud account sheet), Memories content (server feature), Duplicate action (needs `AssetMutations` API).

## Constraints And Non-goals
- No behavior changes to loader/prefetch paths; chrome and data-plumbing only.
- Search-role tab, deep-link (`requestedTab` + `pendingRoute`) and minimize-behavior contracts stay intact (WP5 turf — coordinate, don't duplicate).
- See non-goals list above; settings-screen coverage (Photos toggles) is noted, not scheduled.

## Key Decisions
- Library first (LP1–LP2), then viewer/info (LP3–LP4), then secondary surfaces (LP5–LP9). Density + badge are the highest-visibility wins.
- Re-capture before judging: L01/L02 Heirloom sides and the Photos filter menu (pair 02 compares against an unopened menu) must be re-shot in matched modes before LP2/LP3 close.
- Duplicate stays out (server API missing); the menu icon row ships with Copy/Hide/Share/Favorite only.

## Recommended Approach
Small per-surface work packages on agent branches merging to integration, each ending with a pair re-capture. No new architecture; reuse existing tokens, mirrors, and harnesses.

## Work Plan
- **LP1 Library density + floating badge** (Grid): raise max columns 13 → Photos range (~18–20) at `LibraryView.swift:313-314`; diagnose G5 badge trigger (badge exists, never shows; G5 test red) and wire to pinch/fast-scroll; extend `GridPrefetchPolicyTests`-style coverage + G5 green.
- **LP2 Library header + tab chrome** (Library): verify title/subtitle color + large-title collapse vs Photos dark pair; verify tab-bar labels (Heirloom shows text, Photos icon-only — version check); verify Years/Months/All pill minimize parity; re-capture Photos filter menu and align menu content/order.
- **LP3 Viewer chrome** (Viewer): compact two-line date pill toward Photos size; filmstrip thumb sizing; re-capture L02 Heirloom side in LIGHT mode to confirm `viewerBackdrop` adaptation before any code change.
- **LP4 Info panel data** (Viewer + server DTO): wire EXIF row (ISO/focal/ev/aperture/shutter) replacing "No exposure details"; camera line ("Main Camera — 24 mm ƒ1.78") + format badges; original filename instead of asset UUID (needs `originalFileName` plumbed; check `search.dto`/upload-path work from T1).
- **LP5 Editor naming + style badge** (Editor): video mode tab "Styles" → "Filters" (photo mode keeps Styles, pair 07); verify current-style canvas badge (GOLD equivalent) presence.
- **LP6 Search visual recents** (Search): thumbnail+label recent cards replacing the empty placeholder; check chip-row trailing fade.
- **LP7 Collections map tile** (Collections): native map-snapshot tile replacing the text placeholder; collapse chevrons already match.
- **LP8 Context-menu icon row** (Grid): Copy/Hide/Share/Favorite icon header row above the list menu; Duplicate explicitly out (server API).
- **LP9 Account polish** (Account): email-primary, UUID demoted/hidden; settings-toggle coverage recorded as backlog.

## Validation Plan
- Each package: targeted UI test or AX assert where one exists (G5 for LP1; appearance pairs for LP3), plus `PairCaptureUITests` re-capture of its pair(s) and side-by-side review against `assets/pairs/`.
- Full `ParityGridUITests` class on device (Release) after LP1–LP2; viewer/editor suites after LP3–LP5. Budgets stay device-only per F6/WP-B.
- Highest-risk validation: LP1 density change interaction with prefetch windows (F5) — run fastScroll + pinch tests together, not separately.

## Risks / Rollback
- Density-range change alters prefetch/windowing math — F5 neighbor tests are the tripwire; each package reverts independently (per-surface branches).
- EXIF/filename plumbing may need server DTO changes outside native-apple — confirm `exifInfo`/`originalFileName` availability before LP4 starts; split server/client PRs if needed.
- Re-captures depend on the owner's device + Release runs; light-mode halves must be mode-matched this time.

## Open Questions
None — light-mode ambiguity is answered by re-capture (LP3), not by asking.
