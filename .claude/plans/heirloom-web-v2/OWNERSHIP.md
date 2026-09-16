# Heirloom Web V2 — File Ownership Table

Live table. Only the lead edits this file. One editor per file at all times.

## Pre-existing user work (hands-off for all agents)

| Path | Status | Owner |
| --- | --- | --- |
| `.claude/plans/deploy-heirloom-docker.md` | modified, unstaged | user (do not touch) |
| `native-apple/Apps/macOS/Sources/MacAppState.swift` | modified, unstaged | user (do not touch) |
| `native-apple/PhotosCore/Sources/ImmichAPI/ImmichConnection.swift` | modified, unstaged | user (do not touch) |
| `native-apple/Apps/macOS/Sources/MacMainWindow.swift` | modified, STAGED (runtime auto-staged agent/user diffs; do not unstage — `git reset` is banned) | user-concurrent (do not touch; Agent A read scope — moving target) |
| `native-apple/Apps/macOS/Sources/HeirloomMacOSApp.swift` | modified, unstaged | user-concurrent (do not touch; Agent A read scope — moving target) |
| `native-apple/Apps/Shared/SharedContainer.swift` | modified, unstaged | user-concurrent (do not touch) |
| `native-apple/Apps/iOS/Sources/AppSession.swift` | modified, unstaged | user-concurrent (do not touch) |
| `native-apple/Apps/macOS/Sources/MacAppState.swift` | staged + unstaged | user-concurrent (do not touch) |
| `web/src/lib/heirloom/view-state.svelte.ts` | new, shell-agent-owned | shell agent (transferred 2026-09-16) |

Runtime note: delivered agent diffs are auto-staged into the parent index
(staged, uncommitted). Staging is not committing — leave the index alone.
Never run `git reset` to unstage.

## Lead-owned (locked shared hot spots — subagents read-only)

- `web/src/routes/(user)/+layout.svelte`, `+layout.ts`
- `web/src/lib/components/timeline/Timeline.svelte`, `Thumbnail.svelte`
- `web/src/lib/managers/VirtualScrollManager/`, `web/src/lib/managers/timeline-manager/`
- `web/src/lib/utils/layout-utils.ts`
- `web/src/lib/components/asset-viewer/`, `web/src/lib/managers/asset-viewer-manager.svelte.ts`
- `web/src/lib/route.ts`, `web/src/app.css`
- `.claude/plans/heirloom-web-v2/PLAN.md`, `WP0-PREFLIGHT.md`, this file

## Agent A — WP1 visual contract (read-only + owned docs)

Reads: all `native-apple/Apps/macOS/Sources/*.swift` source-of-truth files.
Writes ONLY:
- `.claude/plans/heirloom-web-v2/WP1-PARITY-MATRIX.md`
- `.claude/plans/heirloom-web-v2/WP1-MEASUREMENTS.md`
- `.claude/plans/heirloom-web-v2/refs/` (reference screenshots)

## Agent B — WP2 route/data matrix (read-only + owned doc)

Reads: web SDK/stores/components/route files listed in PLAN §5.
Writes ONLY:
- `.claude/plans/heirloom-web-v2/WP2-ROUTE-DATA-MATRIX.md`

No server edits. No production code edits.

## Agent C — WP3 test baseline (owned test helpers + report)

Reads: repo-wide test inventory (unit/component/Playwright/fork-E2E).
Writes ONLY:
- `.claude/plans/heirloom-web-v2/WP3-BASELINE.md`
- `.claude/plans/heirloom-web-v2/WP3-VISUAL-MANIFEST.md`
- New V2 helper files under `web/src/lib/heirloom-test/` (helpers only, no product code)

## Wave 2 assignments (active 2026-09-16)

- Shell agent (WP4): `web/src/routes/(user)/v2/**` (ALL route files incl.
  `[[assetId]]` shells) + `heirloom/shell/**` + `heirloom/sidebar/**` +
  `heirloom/toolbar/**` + `lib/heirloom/routes.ts` + `lib/heirloom/tokens.ts` +
  `lib/heirloom/heirloom-v2.css`. Reads `lib/heirloom/url-state.ts` (lead-owned).
- Grid agent (WP5): `heirloom/timeline/**` ONLY (new V2 grid components).
  Shared timeline files stay LEAD-LOCKED — no edits; propose diffs to lead.
- Viewer agent (WP8): `heirloom/viewer/**` ONLY (V2 viewer variant components).
  Route wrappers belong to the shell agent; the viewer exposes a component
  interface for `[[assetId]]` shells. `asset-viewer-manager` read/reuse only.
- Lead retains: `lib/heirloom/url-state.ts`, all pre-existing shared files,
  integration, plan checklist.

## Wave 3 assignments (active 2026-09-16; shell agent delivered, WP9 fills stubs)

- WP6 interaction agent: `heirloom/interactions/**` (new) + `lib/heirloom/drag-drop.ts`
  (transferred from lead). Shared selection files stay LEAD-LOCKED — propose diffs.
- WP7 management agent: `heirloom/dialogs/**` (new) only.
- WP9 slice-1 agent (core timeline routes): page files under `v2/library/**`,
  `v2/search/**`, `v2/favorites/**`, `v2/recently-saved/**`, `v2/collections/**` +
  `heirloom/shared/V2ViewerSlot.svelte` (wires HeirloomViewer into shells).
  All other `v2/**` pages stay stub-reserved.
- Lead retains: `url-state.ts`, all shared locks, integration, plan checklist.

## Wave 3 assignments (continued 2026-09-16)

- WP9 slice-2 agent: page files under `v2/map/**`, `v2/people/**`, `v2/memories/**`
  + `heirloom/map/**`, `heirloom/memories/**`, `heirloom/people/**` (new).
- WP9 slice-3 agent: page files under `v2/media/**`, `v2/spaces/**`,
  `v2/libraries/**`, `v2/albums/**`, `v2/imports/**`, `v2/trash/**`, `v2/hidden/**`,
  `v2/archive/**`, `v2/locked/**`, `v2/settings/**` + `heirloom/settings/**` (new)
  + `heirloom/search/**` (new; may extend the slice-1 search page ONLY for
  scope-selector integration — explicit transfer).
- `lib/heirloom/route-options.ts` → slice-1 agent (retroactive, delivered).

## Wave 4 assignments (active 2026-09-16)

- Quality agent (static): read-only audit over `heirloom/**` + `v2/**`; writes ONLY
  `.claude/plans/heirloom-web-v2/WP11-QUALITY-AUDIT.md` (findings + host runbooks).
  No product edits, no dependency installs (axe install decision stays a host call).
  (Delivered 2026-09-16.)

## Wave 4 fix batch (active 2026-09-16; all prior feature agents terminal)

- Fix agent owns temporary edit rights to these V2-ONLY files (transfer recorded):
  `timeline/V2SquareTimeline.svelte` (A1/A2/A3/A8), `interactions/*` (A8/P1),
  `v2/map/[[assetId=id]]/+page.svelte` (A4), `viewer/HeirloomViewer.svelte`
  (A5/A12/A16), `v2/search/[[assetId=id]]/+page.svelte` (A6),
  `v2/map` count headline (A6), `memories/V2MemoryPlayer.svelte` (A10),
  `sidebar/V2Sidebar.svelte` (A15), `heirloom-v2.css` (A16/A17),
  `dialogs/V2Sheet.svelte` + `lib/heirloom/tokens.ts` (A18),
  `toolbar/V2Toolbar.svelte` (P2).
- A13 toast: `toastManager` lives in `@immich/ui` (external package) — host axe run
  decides; a failure routes to the UI-package release process, never a V2 edit.
- Lead retains: WP12 documentation + rollout report, final verification, release report.
