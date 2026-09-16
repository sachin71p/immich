# WP0 Preflight — Heirloom Web V2

Date: 2026-09-16
Lead agent, plan ref `.claude/plans/heirloom-web-v2/PLAN.md` (reference rev `464f9122be`).

## Worktree safety record (pre-existing changes, NOT ours — preserve)

Branch: `feat/shared-libraries`
HEAD: `f77bebddce9a2e9f688361deda56f1723806e5c7`
Note: HEAD has drifted past the plan reference rev `464f9122be`; subagents must work
against the current tree, not the reference rev.

Pre-existing unstaged modifications (recorded 2026-09-16, lead start sequence):

1. `M .claude/plans/deploy-heirloom-docker.md` (~378 lines changed)
2. `M native-apple/Apps/macOS/Sources/MacAppState.swift` (59 lines changed)
3. `M native-apple/PhotosCore/Sources/ImmichAPI/ImmichConnection.swift` (1 line)

Staged changes: none.
Untracked: `.claude/plans/heirloom-web-v2/` (this plan's own directory).

Rules in force: no `git reset/clean/checkout --`/stash/commit; narrow patches only;
stop on unexplained overlap with the three files above.

## Baseline inventory

- Package manager: `pnpm@11.24.0` (root `package.json`).
- Classic routes present under `web/src/routes/(user)/`: photos, albums, search,
  explore, people, map, memories, favorites, trash, archive, locked, sharing,
  shared-libraries, tags, workflows, utilities, folders, places, partners, etc.
- V2 surface: ABSENT — no `web/src/routes/(user)/v2`, no `web/src/lib/heirloom`,
  no `web/src/lib/components/heirloom`. Additive build starts from a clean slate.
- Native macOS sources present under `native-apple/Apps/macOS/Sources/`
  (MacMainWindow, MacSidebar/Model, MacViewer, MacSearchView, MacMapPlacesView,
  MacMemoriesView, MacSettings, MacStorageView, MacEditView, MacMenus,
  MacConnectView, HeirloomMacOSApp, plus MacGridView/MacSelection/MacDragDrop, etc.).

## Verification commands (repo standard, §16)

```bash
cd web
pnpm run check:typescript
pnpm run check:svelte
pnpm run lint
pnpm run test --run
pnpm run build
```

Docker-gated (only where Docker is available): `scripts/fork-test/run.sh e2e-web`.

## Wave 1 assignments

- Agent A (WP1 visual contract): docs/screenshots only under
  `.claude/plans/heirloom-web-v2/` paths owned by Agent A (see OWNERSHIP.md).
- Agent B (WP2 route/data matrix): `WP2-ROUTE-DATA-MATRIX.md` only; no server edits.
- Agent C (WP3 test baseline): baseline report + new V2 test helpers only.
- Lead (WP0): this note + `OWNERSHIP.md` + integration design; owns all shared-file locks.

Gate: no production code changes until WP1–WP3 are consolidated (§21 step 8).

## Parent-layout verification (lead, 2026-09-16)

- `web/src/routes/(user)/+layout.ts`: every child route load runs `authenticate()`
  (public only for shared-link routes). V2 routes under `(user)/v2/` inherit auth
  automatically — no V2 auth work required.
- `web/src/routes/(user)/+layout.svelte`: a global `$effect.pre` drives the classic
  `assetViewerManager` from `page.data.asset` and the `?at=` scroll-target param on
  EVERY child route, including future V2 pages. Wave 2 integration constraint: the
  V2 viewer variant must either reuse this manager or explicitly neutralize/hide
  the classic viewer inside the V2 root, or both viewers will react to V2 asset URLs.
- The parent layout also mounts the global `DragAndDropUploadOverlay` (`UploadCover`)
  for all children; V2 external-file-drop (WP6) must coordinate with, not duplicate, it.

## Wave 1 returns (lead consolidation log)

- **WP2 ACCEPTED 2026-09-16** (`WP2-ROUTE-DATA-MATRIX.md`, 21 routes + CRUD/admin/moves
  + URL params): verdict NO SERVER CHANGE REQUIRED. Key design inputs for Wave 2:
  media routes search-backed (buckets lack `type`); Rotate = documented browser
  exception; V2 prefs keyed separately from classic; bulk-timeline permission
  asymmetry inherited (R4). Open verifications: G2 upload-into-library (WP7 fixture
  run), G3 search-suggestion specifics (WP9). Product decisions R1 (Recently Saved
  semantics) + R2 (Imports semantics) need WP1 native evidence.
- **WP3 ACCEPTED 2026-09-16** (`WP3-BASELINE.md` + `WP3-VISUAL-MANIFEST.md` +
  `web/src/lib/heirloom-test/{fixtures,url-state}.ts`, helpers-only, no product
  imports): 65 web spec files; B1/B2 baselines green (18/18 route builder,
  15/15 library-source+timeline-util); full suite + tsc + Docker e2e deliberately
  deferred to later agents (first runner records failures as pre-existing).
  P1–P22 comparison pairs, 8-item mask list, axe + perf methods defined.
  axe-core NOT installed — Wave-4 decision.
- **WP1 PENDING** (Agent A still working): parity matrix + measurements + refs.
  No Wave 2 production work starts until WP1 lands (§21 step 8).
- **Agent C formal handoff received**: confirms scope as delivered; notes concurrent
  sibling activity (see below). No new files beyond the accepted WP3 set.
- **Concurrent user activity observed 2026-09-16**: `SharedContainer.swift`,
  `HeirloomMacOSApp.swift` (both unstaged), and `MacMainWindow.swift` (staged)
  changed during the Wave 1 window. Content (ad-hoc-signing group-container probe,
  saved-server-URL domain alignment, post-login sync-error toast) attributes to
  the user's concurrent host native work, not to agents. All three are hands-off,
  recorded in OWNERSHIP.md; the three sit in Agent A's read scope, so WP1 line
  citations for them must be re-verified at handoff review. Direct message to
  Agent A failed (tool rejected); the moving-target flag lives in OWNERSHIP.md.
- **Runtime auto-staging observed**: delivered agent diffs (and the pre-existing
  user mods) appear in the parent index as staged, uncommitted. Staging is not
  committing — the index is left alone; `git reset` remains banned.

## Wave 1 consolidation (lead sign-off 2026-09-16)

- **WP1 ACCEPTED.** Provenance discipline ([S]/[W]/[N]) verified by spot-check:
  `showsBucketHeaders`/`groupsByYear` (MacSidebarModel:166/174), flattening
  `numberOfSections → 1` (MacGridView:358), defaults `.months`/`120`
  (MacMainWindow:43/45), Manage-only-for-space (:257). No runtime screenshots —
  [N] items + host recipe in `refs/CAPTURE-LOG.md`; release visual gate stays open.
- **Lead decision D1 (WP1 §9): APPROVED — V2 implements visible year+month headers**
  (loader's intended model), diverging intentionally from shipped-flat native.
  Recorded for the release report.
- **Lead decision D2 (R1/R2 resolved by native evidence):** `case .recents, .imports`
  share one arm → `recentAssets(limit:1000)` (MacGridView:67-70). V2 maps BOTH
  `/v2/recently-saved` and `/v2/imports` to the recency composition (WP2
  recently-added pattern); labels differ, data matches native. No server work.
- **Rotate reconciled (WP1 §4 + WP2 §1):** native Rotate is display-only until
  persisted. V2 implements client-side display rotation (no server API exists or
  is proposed); persistence stays a documented exception. WP10 owns the wording.
- **Lead decision D3 (parent-layout viewer coupling):** `(user)/+layout.ts` loads
  `page.data.asset` for ANY route with an `assetId` param (`navigation.ts:23-25`)
  and the parent layout effect opens the classic viewer from it. V2 keeps the
  `[[assetId=id]]` convention (plan §7); the V2 viewer is therefore built as an
  EXPLICIT opt-in variant composed with `asset-viewer-manager` (never a fork),
  branching on the `/v2` route id so classic viewer rendering is untouched.
- **Lead-owned URL/state contract shipped:** `web/src/lib/heirloom/url-state.ts`
  (+`url-state.spec.ts`, 37/37 pass, 1.25 s). Pure functions, URL > V2 prefs >
  native defaults, per-field fallback, round-trip serialization. V2 pref keys
  (`heirloom-v2-*`) never touch classic keys. Wave 2 consumes this read-only.
- **MacGridView.swift `/tmp` debug logging** (thumbnail error trace) appeared in
  the window — attributed to user's concurrent host debugging, hands-off.

## Wave 2 partial return (lead verification 2026-09-16)

- **WP5 ACCEPTED (independent verification).** Agent delivered
  `heirloom/timeline/{square-layout.ts,square-layout.spec.ts,V2SquareTimeline.svelte}`.
  Lead ran `square-layout.spec.ts`: 28/28 pass. Shared-file lock held — zero diffs
  in timeline/managers/layout-utils/(user)+layout/route.ts/app.css. Composition
  confirmed: Thumbnail component + type-only TimelineManager imports (no fork).
  Agent handoff text truncated on delivery; substance verified directly from tree.
- **WP4/WP8 IN FLIGHT.** Shell + viewer files present on disk (full `v2/**` route
  tree, V2Shell/Sidebar/Toolbar, routes.ts + routes.spec, view-state.svelte.ts,
  heirloom-v2.css, tokens.ts, HeirloomViewer + viewer-variant.ts/spec). Lead ran
  `routes.spec.ts` + `viewer-variant.spec.ts`: 48/48 pass. Formal handoffs pending;
  no acceptance recorded until handoff review.
- **ESLint gate BLOCKED (pre-existing, environmental).** `pnpm exec eslint` crashes
  inside `@koddsson/eslint-plugin-tscompat` (`convertToMDNName`) on V2 files AND
  identically on pre-existing `src/lib/route.ts`. Not a V2 finding; lint must run
  on host/CI. Spec gates (vitest) are green and unaffected.
- **New concurrent user edits observed:** `native-apple/Apps/iOS/Sources/AppSession.swift`
  (unstaged), plus staged+unstaged movement in MacAppState.swift/MacMainWindow.swift.
  All hands-off, added to OWNERSHIP.md.
- **Ownership transfer:** `web/src/lib/heirloom/view-state.svelte.ts` (created by shell
  agent for V2 presentation state) assigned to shell agent retroactively; lead keeps
  `url-state.ts` only.

## Wave 2 consolidation (lead 2026-09-16)

- **WP4 ACCEPTED.** Verified from tree: `/v2` → `/v2/library` 307 redirect;
  20 skeleton pages covering all 21 §7 destinations; classic sidebar/nav untouched;
  CSS 25/25 selectors under `[data-heirloom-v2]` (only `@media` wrappers outside);
  V2-only `heirloom-v2-*` pref keys; live sidebar data (`sharedSpaces` +
  `getAllAlbums`); zero V2 links in classic chrome. `routes.spec` green (in the
  earlier 48/48 run).
- **WP5 ACCEPTED (checkbox now checked).** Structural audit substantiates the
  virtualization claim: rows derive from `visibleSquareRows(layout, scrollTop,
  viewportHeight)` with anchor capture/restore — only visible rows render.
  Live 10k-asset timing stays a Wave-4 perf-gate item.
- **WP8 PENDING** (viewer agent still working; HeirloomViewer + variant spec files
  on disk, 48/48 run included viewer-variant.spec).

## Wave 2 complete (lead 2026-09-16)

- **WP8 ACCEPTED.** 5 new files under `heirloom/viewer/` (component, variant logic,
  2 specs, README interface doc). Classic viewer/manager untouched. D3 branching
  (`isV2ViewerRoute` on `/v2` route id), native toolbar order, display-only rotation,
  Edit gated on the existing browser editor, classic actions composed (Delete/Move/
  EditorPanel). Lead ran viewer specs: 30/30 pass (fetch-abort teardown chatter in
  happy-dom is noise, not failure — both files green).
- **Integration state:** routes are pure placeholders (`V2SectionPlaceholder`);
  `V2ViewerSlot` has no viewer import yet. Grid→library and viewer→shell wiring is
  explicitly Wave 3 (WP9 slice 1) work, not a Wave 2 gap.

## Wave 3 partial (lead 2026-09-16)

- **WP7 ACCEPTED.** 11 new files under `heirloom/dialogs/` (V2Sheet shell + 8
  sheets + sheet-logic + spec + README), zero edits outside V2. Spec 23/23 pass.
  **G2 closed:** `AssetMediaCreateDto` carries `spaceId` but no `libraryId`
  (DTO-evidence in sheet-logic.ts) → external-library destinations go
  upload-then-move via V2MoveSheet. No server work, as predicted.
- **WP6 + WP9-slice-1 IN FLIGHT.**

## Wave 3 slice-1 accepted (lead 2026-09-16)

- **WP9-slice-1 ACCEPTED (substance verified).** Five routes render live square
  timelines: library + search (`[[assetId]]` shells), favorites + recently-saved
  (agent restructured to `[[assetId]]` subdirs for deep-linkable viewer — lead-approved
  deviation from §7, optional-param routing keeps bare URLs working), collections
  (composes classic AlbumsList per WP2). `V2ViewerSlot` renders HeirloomViewer.
  New specs route-options/drag-drop/keyboard/selection: 32/32 pass.
- **WP6 files present, handoff pending** (interactions/ + lib/heirloom/drag-drop.ts,
  specs green in the 32/32 run). No acceptance until handoff review.
- **WP6 ACCEPTED 2026-09-16.** Selection model, keyboard controller (grid-aware
  arrows via squareColumns, type-to-date 1 s buffer, Return/Space/Escape), drop
  targets + selection toolbar components, drag-drop payload module. Specs 21/21
  pass; containment re-verified (zero web edits outside heirloom/ + v2/).
- **WP9-slice-2 ACCEPTED 2026-09-16.** Map (`[[assetId]]`, split view, dynamic
  Map import without double-fetch), people (+person detail route), memories
  (shelf + player) pages + heirloom map/people/memories models. Specs 22/22 pass;
  containment clean.
- **Slice-3 restructure in flight (expected):** slice-3 stub dirs (media, spaces,
  libraries, albums, imports, trash, hidden, archive, locked, settings) are absent
  mid-flight — agent is restructuring (likely `[[assetId]]` nesting per slices 1-2
  precedent) within its owned paths. Restoration of all §7 routes verified at
  slice-3 handoff; missing routes at acceptance = rejection.
- **WP9-slice-3 ACCEPTED 2026-09-16.** All ten route groups restored (media ×3,
  spaces, libraries, albums, imports, trash, hidden, archive, locked, settings);
  zero placeholders repo-wide; containment clean; settings spec 9/9, slice-3
  composition spec 20/20. Agent's svelte-check-green claim INDEPENDENTLY CONFIRMED
  by lead (`check:svelte`: 0 errors, 0 warnings, exit 0). tsc found ONE error in
  the agent's own spec (AssetVisibility widening); lead applied a test-only
  `as const` fix, re-verified tsc clean + spec 20/20. No product code touched.
- **Manage wired (lead integration fix 2026-09-16).** The audit's A15 re-check
  caught a shipped-disabled Manage button; lead wired it to `V2ManageSpaceSheet`
  (open/update/leave/delete + refresh + redirect) in `V2Toolbar.svelte` (V2-only).
  Debugging svelte-check red herring: a file containing BOTH a binding named
  `state` AND the `$state` rune crashes the checker (legacy `$store` tokenizing
  collision → TS "Debug Failure" cascade). Renamed to `viewState`; rule for all
  V2 Svelte files: never declare a variable named `state` in a file using runes.
- **Final gates (lead, 2026-09-16):** full unit suite 82 files/832 pass
  (2 pre-existing skips), tsc clean, svelte-check 0/0, V2 specs 241/241.
  Zero classic/product diffs outside V2 areas. WP11 static accepted; axe/perf/
  screenshots/E2E host-pending with runbooks.
- **Lead decision D4 (WP10): Decision A RECORDED — reduced working browser editor.**
  Rationale: native editor scope (15 adjust params, filters, crop/perspective,
  portrait, markup, video tools, recipe compat) requires a WebGL/WASM or server
  rendering project of its own (Decision B); the V2 viewer already implements the
  A posture (existing browser tools only, macOS-only tools labeled, zero inert
  replicas). Decision B proceeds only if the user makes full editor parity a
  release requirement — it does not block the browsing release.
- **Ownership:** `lib/heirloom/route-options.ts` → slice-1 agent (retroactive).
