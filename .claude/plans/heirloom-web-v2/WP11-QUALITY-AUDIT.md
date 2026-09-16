# WP11 — V2 static quality audit (a11y + perf) + host runbooks

Owner: Wave-4 quality auditor (static portion). Date: 2026-09-16.
Scope: `web/src/lib/components/heirloom/**`, `web/src/routes/(user)/v2/**`,
`web/src/lib/heirloom/heirloom-v2.css`, PLAN §§ WP11/17, WP3-VISUAL-MANIFEST §§3/5/6,
WP1-MEASUREMENTS §8, `refs/CAPTURE-LOG.md`.

Execution note: live-browser work (Playwright, axe run, perf timings, screenshots)
requires the host stack and was NOT attempted from here — no browsers launched, no
packages installed, no servers started. Every item below is tagged **STATIC**
(verified in source, file:line given) or **HOST-VERIFY** (needs runtime; never
presented as passed). PLAN §17 gates are quoted verbatim in §5.

Pre-existing tree state at audit time (`git status --short`): modified
`.claude/plans/deploy-heirloom-docker.md`, staged AM `OWNERSHIP.md/PLAN.md/WP0-PREFLIGHT.md`,
new `WP2-ROUTE-DATA-MATRIX.md/WP3-BASELINE.md/WP3-VISUAL-MANIFEST.md`,
untracked `WP1-*.md`, `refs/`, `web/src/lib/components/heirloom/`,
`web/src/lib/heirloom/`, `web/src/routes/(user)/v2/`; modified native-apple
Mac/iOS/SharedContainer/AppSession/ImmichConnection files. This audit writes ONLY
this file; no product files touched, no installs, no git operations beyond
`git status --short` + `git diff --stat`.

## 1. Static a11y audit

Severity scale: **H** = will fail the §17 axe gate or block keyboard use;
**M** = likely axe/manual finding or degraded AT experience; **L** = polish/robustness.

### 1.1 Landmarks and accessible names

- **A1 (H, STATIC)** — `role="grid"` without owned `row`/`gridcell` elements.
  `timeline/V2SquareTimeline.svelte:190` declares `role="grid"`; tiles are native
  `<button>`s (no `gridcell` role) inside plain `.hv2-row` divs (no `role="row"`),
  year/month headers are plain divs (`:212,:222`, not `rowheader`/`columnheader`).
  axe rule `aria-required-owned-elements` requires `grid` → `row` → `gridcell`;
  this fails the "zero serious findings" gate as written. **Owner:** grid agent.
  Fix options: (a) switch container to `role="list"` + tiles `role="listitem"`…
  simplest is plain group semantics since full grid keyboard patterns
  (aria-activedescendant/arrow-key spec) are handled by wrapper code, not ARIA;
  (b) add `role="row"` wrappers + `role="gridcell"` on tiles + `aria-rowindex`.
  Also `aria-rowcount={sourceAssets.length}` (`:192`) counts *assets*, not rows —
  wrong under either role; set to row count or drop until (b) lands.
- **A2 (M, STATIC)** — every grid tile named identically.
  `V2SquareTimeline.svelte:246` `aria-label="Photo"` on all tiles: no filename,
  date, or position distinguishes them in a screen-reader rotor. **Owner:** grid
  agent. Recommend `aria-label={asset.originalFileName + date}` (data already on
  `TimelineAsset`) — cheap, keeps visual text unchanged.
- **A3 (M, STATIC)** — selection state exposed as `aria-pressed` on tiles
  (`:247`). Pressed-toggle on a grid cell is ambiguous; with role fix (A1) this
  should become `aria-selected` on the cell/option. **Owner:** grid agent (fix with A1).
- **A4 (M, STATIC)** — map tiles container has `aria-label` with no role.
  `routes/(user)/v2/map/[[assetId=id]]/+page.svelte:111`: `<div … aria-label="Clustered
  photo map">` — AT ignores `aria-label` on a generic div. Give it
  `role="region"` (or `application` only if keyboard map control is implemented;
  it isn't — so `region`). **Owner:** map/feature agent.
- **A5 (L, STATIC)** — viewer/editor/inspector asides unnamed.
  `viewer/HeirloomViewer.svelte:437,441`: two `<aside>` (editor, inspector) with
  no `aria-label`; complementary landmarks without names. Add
  `aria-label="Editor"` / `aria-label="Info"`. Viewer root `section
  aria-label="Asset viewer"` (`:293-:299`) is fine. **Owner:** viewer agent.
- **A6 (L, STATIC)** — search results count not announced.
  `routes/(user)/v2/search/[[assetId=id]]/+page.svelte:156` count is a plain `<p>`;
  add `role="status"` so result arrival is announced. Same for map count headline
  (`map/+page.svelte:129`, currently `<h2>` only — keep heading, add a
  visually-hidden `role="status"` or `aria-live` twin). **Owner:** feature agents.
- **A7 (L, STATIC)** — `V2Shell` content landmark uses `aria-label` only
  (`shell/V2Shell.svelte:21`). Valid, but the sidebar nav (`aria-label="Heirloom
  library"`, `V2Sidebar.svelte:31`) + toolbar (`role="toolbar"
  aria-label="Heirloom view options"`, `V2Toolbar.svelte:43`) + per-route
  `<section aria-label=…>` compose correctly — no landmark gaps found. No skip
  link exists; acceptable for an app shell (sidebar is first tab stop) — record
  as HOST-VERIFY in keyboard pass.

### 1.2 Focus visibility, traps, restoration

- **A8 (M, STATIC)** — no roving tabindex in the grid: EVERY tile is in tab order.
  Tiles are native buttons with no `tabindex` management (`V2SquareTimeline` +
  `HeirloomGridInteractions`), so keyboard users Tab through all rendered tiles
  (bounded by virtualization, but still dozens) instead of one stop + arrows.
  Arrows work once inside (`HeirloomGridInteractions.svelte:276-291`); entry cost
  is the gap. **Owner:** interaction agent. Recommend roving `tabindex`
  (0 on focused/anchor tile, -1 rest) — keep arrows as-is.
- **A9 (L, STATIC — verified good)** — `V2Sheet.svelte:41-76` trap + Escape +
  `captureFocusRestore` (`sheet-logic.ts:183-192`, null-safe, contains-check) is
  correct; initial focus prefers `[data-autofocus]` (`:43-45`); overlay click
  never dismisses (documented cancel-must-be-explicit). NewAlbum/NewSpace put
  `data-autofocus` on the name field — correct. Confirm sheet autofocuses Cancel
  — correct for destructive flows.
- **A10 (M, STATIC)** — memory player has no focus trap or restoration.
  `memories/V2MemoryPlayer.svelte:118-124` renders `role="dialog"
  aria-modal="true"` but Tab leaves the dialog and `onClose` never restores
  focus (contrast with V2Sheet A9). **Owner:** memories/feature agent. Reuse
  `captureFocusRestore` + trap from `V2Sheet` (extract or duplicate narrowly).
- **A11 (L, STATIC)** — focus styles exist everywhere they must:
  sidebar links (`heirloom-v2.css:68`), sheet controls (`V2Sheet.svelte:173-180`),
  tiles (`V2SquareTimeline.svelte:312`). Unverified visually — HOST-VERIFY
  `:focus-visible` outline in axe/keyboard runbook (§6.1 step 3).
- **A12 (L, STATIC)** — viewer single-key shortcuts (`HeirloomViewer.svelte:224-234`,
  `r`/`i`, plus Space-preview in grid) have no disable/remap mechanism (WCAG 2.1.4
  single-character shortcuts). Shortcuts ignore inputs (`:205`) — good — but add a
  settings note or require a modifier. **Owner:** viewer/interaction agent (docs fix ok).

### 1.3 Announcements (modals/toasts/errors)

- **A13 (M, STATIC)** — V2 ships no `aria-live` region of its own; all success
  feedback goes through shared `toastManager` (`V2MoveSheet`, `V2NewSpaceSheet`,
  `V2ImportChooserSheet`, album page). No `Toast*` component exists under
  `web/src/lib/components/` (verified by listing) — the Toast implementation
  lives in `@immich/ui` or the classic shell and its `role="status"` /
  `aria-live="polite"` is UNCONFIRMED statically. Errors use `role="alert"`
  correctly everywhere (timeline `:195`, viewer-slot `:103`, sheet error
  `V2Sheet.svelte:93`, all route error states). **Owner:** quality/host runner —
  HOST-VERIFY toast announcement is an explicit axe-runbook step (§6.1.4); if the
  shared Toast lacks a live region, file against the classic Toast owner (shared
  file — lead lock applies, PLAN §12).
- **A14 (L, STATIC)** — selection-count changes (`V2SelectionToolbar.svelte:37`)
  and sidebar async album/space rows (`V2Sidebar.svelte:17-26`, no
  loading/empty announcement) are silent to AT. Acceptable for release gate;
  consider `aria-live="polite"` on the count span post-gate.

### 1.4 Keyboard-only path completeness

Traced statically end-to-end: sidebar links → source `<select>` → grouping buttons
→ zoom slider → grid tiles (Tab in, arrows/Shift-arrows/Cmd+A/Return/Space/Escape/
type-to-date in `HeirloomGridInteractions.svelte:271-352`, geometry-aware via
`squareColumns`) → selection toolbar buttons → sheets (trap, A9) → viewer
(arrows/Escape/`r`/`i`, `HeirloomViewer.svelte:199-235`) → memory player (A10 gap)
→ Load-more/retry buttons. DnD-only destinations have a keyboard path via the Move
sheet; external-library confirm is a real sheet. Gaps: **A8** (tab cost), **A10**
(player trap), **A15** below. Manage button (`V2Toolbar.svelte:87-94`) is
`disabled` with a "WP7" title — keyboard-focusable? No (`disabled` removes it);
acceptable only while WP7 sheets land — confirm no disabled-Manage ships at gate.
Unavailable sidebar rows (`V2Sidebar.svelte:83-90`) render `<span
aria-disabled="true">` — **A15 (M, STATIC)**: `aria-disabled` on a non-widget
span is inert to AT AND unreachable by keyboard, so the "Available with
management sheets" explanation is mouse-only (title tooltip). Either render them
as disabled buttons (focusable explanation via `aria-describedby`) or hide until
WP7 — do not ship focus-invisible placeholders at gate. **Owner:** shell agent.

### 1.5 Reduced motion / forced colors / hard-coded colors

- **A16 (M, STATIC)** — zero `prefers-reduced-motion` handling in V2. Grep over
  all V2 components + CSS: no match. Concrete motion: viewer canvas
  `transition-transform duration-200` (`HeirloomViewer.svelte:369`), tile/hover
  transitions, memory auto-advance (5 s timer is content, not CSS — exempt, and
  pause control exists). PLAN WP11 requires reduced-motion support "where
  practical". **Owner:** shell/viewer agent. Minimum: a
  `@media (prefers-reduced-motion: reduce)` block under `[data-heirloom-v2]`
  zeroing transitions/transforms.
- **A17 (M, STATIC)** — zero `forced-colors`/`forced-color-adjust` handling
  (same grep: no match). Selection/focus/drop outlines use `currentColor`
  (fine), but state is ALSO color-only in places (pressed-segment background,
  drop `allowed` vs `denied` solid-vs-dashed — dashed survives, ok). Minimum:
  `forced-color-adjust: none` audit on `.v2-btn-primary/.v2-btn-danger` + a
  `ButtonText` outline fallback for selected tiles. HOST-VERIFY with
  `forced-colors: active` emulation in axe runbook.
- **A18 (M, STATIC)** — hard-coded interactive colors likely below 4.5:1:
  `.v2-btn-primary{background:#0a84ff;color:#fff}` and `.v2-link-btn{color:#0a84ff}`
  (`V2Sheet.svelte:199-203,269-277`) — #0a84ff on white ≈ 3.6–4.0:1, fails AA for
  12–13 px text; error `#d70015` (`:141`) and secondary `#6e6e73`
  (`heirloom-v2.css:38`) pass on white but are unverified on the dark
  `--v2-sheet-background:#2c2c2e`. axe `color-contrast` in both themes decides —
  explicit runbook step (§6.1). **Owner:** shell/dialog agent (darken primary to
  `#0071e3`-family or restrict link-btn to ≥14 px bold; verify).
- **A19 (L, STATIC)** — dark theme rides `prefers-color-scheme` media queries
  (`heirloom-v2.css:165`, `V2Sheet.svelte:285`). If the host app themes via a
  class/dat­attribute instead of OS setting, V2 dark never engages in-app —
  HOST-VERIFY against the classic theme mechanism before baselining dark screenshots.

## 2. Static perf audit

Severity = risk to §17 perf gate (virtualized / no full DOM / no loops).

- **P1 (M, STATIC)** — O(n) id-string join per interaction in
  `HeirloomGridInteractions.svelte:138-149`: `syncOrder()` builds
  `list.map(id).join(',')` (≈100 KB+ string at 10k assets) on EVERY call, and it
  is called from the selection-prune effect (`:152-154`), plain click
  (`:187`), capture click (`:200`), arrows (`:277`), type-ahead (`:293`),
  select-all/clear/open/preview. Rapid arrow-key navigation = one full join +
  one full flatten per keypress (flatten itself re-iterates all manager
  months/days `:114-130`). Works, but the 10k keyboard/zoom probe will feel it.
  **Owner:** interaction agent. Fix: version-counter or length+ends checksum from
  the manager instead of a joined key (no behavior change).
- **P2 (M, STATIC)** — zoom slider fires `goto(replaceState)` per `oninput` tick
  (`V2Toolbar.svelte:31-36,73-82`) → each tick recomputes
  `buildSquareSections` + `layoutSquareGrid` O(n) (`V2SquareTimeline.svelte:101-104`).
  At 10k assets a 64→300 drag = dozens of full re-layouts. **Owner:** toolbar/grid
  agent. Fix: debounce `handleZoom` (~100 ms) or quantize; the anchor-restore
  effects (`:142-171`) already cover jump restoration.
- **P3 (L, STATIC — verified good)** — render set IS virtualized:
  `visibleSquareRows(layout, scrollTop, viewportHeight)` + 600 px overscan
  (`square-layout.ts:30`) + per-row `slice` (`V2SquareTimeline.svelte:235`);
  `data-rendered-tiles`/`data-total-assets` attributes (`:188-189`) give the 10k
  probe its assertion hook (`rendered ≪ total`). `ONSCROLL` sets state per event
  (`:114-118`, no rAF throttle) — recompute is O(visible rows), acceptable; host
  scroll probe decides.
- **P4 (L, STATIC — verified good)** — fetch-loop guards present: single manager
  driver effect (`V2SquareTimeline.svelte:69-73`, assets-set ⇒ never driven);
  search/media effects use `untrack` with dep-only subscriptions
  (`search/+page.svelte:66-70`, `media/photos/+page.svelte:35-38`); viewer-slot
  fetch is id-keyed with stale guard (`V2ViewerSlot.svelte:55-79`); sidebar and
  scope `ensureLoaded()` are cached-store calls. No uncontrolled loop found
  statically — the "settled network idle" assertion in the runbook (§6.2) confirms.
- **P5 (L, STATIC)** — `results.map(toTimelineAsset)` per result-set change
  (search + all three media pages) is O(n) full-remap per page append; fine at
  paged sizes, but do NOT reuse this pattern for the 10k corpus — the perf probe
  must use the manager path or a windowed list. Noted in runbook §6.2 probe 6.
- **P6 (L, STATIC)** — listener hygiene good: both `ResizeObserver`s disconnect
  on cleanup (`V2SquareTimeline.svelte:138`, `HeirloomGridInteractions.svelte:110`);
  sheet keydown listener removed (`V2Sheet.svelte:73`); memory interval cleared
  twice-safe (`V2MemoryPlayer.svelte`, effect return + `onDestroy`); per-route
  `new TimelineManager()` destroyed (`library/+page.svelte`). No leak found
  statically; heap-delta probe (§6.2 probe 5) confirms.
- **P7 (L, STATIC)** — sidebar album list renders unbounded (`V2Sidebar.svelte:67-78`,
  `getAllAlbums` full array, no virtualization). Fine for tens of albums; file as
  known limit, not a gate blocker. `Thumbnail` per rendered tile owns its own
  fetch/observers — bounded by P3's window; no action.

## 3. Mask-list cross-check (WP3 §3 vs WP1 §8 vs current components)

| # | Region | WP1 §8 | WP3 §3 | Component reality | Verdict |
|---|---|---|---|---|---|
| 1 | Map tiles/clusters | mask | mask (item 1) | tiles external; clusters zoom-dependent (`Map.svelte` via dynamic import) | AGREE — keep masked |
| 2 | Memory progress/scrub | mask (5 s advance) | mask (item 2) | `V2MemoryPlayer` progress segments + auto-advance | AGREE — keep masked; screenshot paused state |
| 3 | Grid thumbnails | mask ("grid cells, async thumbnails") | UNMASKED ("thumbnails from fixtures stay unmasked") | `Thumbnail` fetches async per tile | **CONFLICT — lead decision needed.** If e2e uses real server thumbs, WP1 wins (mask or thumb-stub). If WP3 fixture corpus stubs thumb URLs deterministically, WP3 wins — but no stub exists in `fixtures.ts` today. Default: follow WP1 (mask) until a deterministic thumb stub lands. **Owner: lead.** |
| 4 | Sidebar space/library/album rows + counts | mask | item 7 keeps them UNMASKED (seeded identicons) | `V2Sidebar` renders live `sharedSpaces` + `getAllAlbums` names | **CONFLICT.** WP3's identicon fixtures don't cover names/counts from live data. Either seed server fixtures with fixed names (then WP3 wins) or mask the dynamic rows (WP1 wins). **Owner: lead.** |
| 5 | Toasts | mask (whole toast, 4 s) | mask progress bars only (item 5) | `toastManager` shared; 4 s auto-dismiss per WP1 §7 | **GAP in WP3.** Whole-toast presence is timing-dependent; mask the toast region entirely per WP1, not just progress bars. **Owner: lead to amend WP3 §3.** |
| 6 | EXIF values / inspector dates (locale-sensitive) | mask | not listed | `DetailPanel` reused in viewer inspector; WP1 §5 confirms locale-sensitive format | **GAP in WP3 — add inspector EXIF/date mask (or pin locale+timezone in harness).** **Owner: lead.** |
| 7 | Suggestion chips / recents / type-ahead dropdown | mask | not listed | P3 capture state "date type-ahead open" (manifest §2) renders suggestions | **GAP in WP3 — mask the open type-ahead dropdown.** **Owner: lead.** |
| 8 | Fixture/relative dates, On This Day | mask | item 4 (clock escape hatch) | harness freezes clock (manifest §1.4) | AGREE — freeze is the fix; mask only with written justification |
| 9 | Video duration badges | — (not in §8) | conditional (item 3) | duration text from metadata | AGREE — keep conditional wording |
| 10 | Upload/import live progress % | — | mask (item 6) | `V2ImportChooserSheet` + upload store toasts | AGREE — capture idle + completed only |
| 11 | Scrollbars | — | normalize (item 8) | `scrollbar-gutter` note | AGREE |
| 12 | **Settings storage usage** (`navigator.storage.estimate`, `settings/+page.svelte`) | not listed | not listed | live byte count, machine-dependent | **GAP in BOTH — mask or stub in P20.** **Owner: lead.** |
| 13 | **Map count headline / people counts / search count** | counts masked (WP1) | not listed | live text (`v2-map-count`, `v2-people-count`, `v2-search-count`) | **Covered by WP1, missing in WP3 — amend WP3 §3 or pin fixture counts.** **Owner: lead.** |
| 14 | Search fixed 160 px tiles (WP1 §4) vs V2 zoom-driven results grid | — | — | search page passes `group="all" zoom={viewState.zoom}` | Behavior note, not a mask: V2 search intentionally follows global zoom; record as divergence in release report. |

Net: WP3 §3 needs three amendments before baselining (whole-toast mask, inspector
EXIF/date mask, type-ahead-dropdown mask) + two lead reconciliations (thumbnails,
sidebar rows) + one new entry (settings storage usage). Until amended, baselines
will flake on exactly these regions.

## 4. Host assumptions and non-findings (do not re-audit)

- Toast visual treatment + dismissal timing owned by the classic shell — out of scope.
- Classic `Thumbnail`, `DetailPanel`, `Map`, `EditorPanel`, `OcrButton`,
  `MoveToLibraryModal`, `fileUploadHandler` internals — reused as-is per PLAN §12.
- `svelte-i18n` keys, SDK behavior, server fixtures — assumed working; harness
  seeds them per manifest §1.
- No `prefers-*`/forced-colors test possible statically beyond the grep (zero hits
  confirmed) — emulation steps are in §6.1.

## 5. Gates reference (PLAN §17, verbatim)

- Visual: geometry ≤ 2 px; type baselines ≤ 2 px; pixel diff < 1% post-mask; no
  unexpected horizontal overflow; light AND dark pass.
- A11y: no serious automated findings; complete keyboard operation; visible focus
  + correct restoration; modals and toasts announced appropriately.
- Perf: large collections virtualized; no full-collection DOM render; no repeated
  uncontrolled fetch/layout loops; measurements + remaining risks documented.
- Regression: classic baselines unchanged; suites pass or unrelated failures
  documented; no accidental server/API change.

## 6. Host runbooks (copy-paste)

Prerequisites (host, from repo root): dev server + Docker stack up; fixture seed
loaded; viewport 1400×900; frozen clock per manifest §1.4. Build mode (dev/prod)
and machine recorded alongside every number (manifest §6).

### 6.1 Axe pass (P1–P22, light + dark)

`@axe-core/playwright` is NOT installed (confirmed: no `axe` hit in
`web/package.json`, `e2e/package.json`, root `package.json`; `manifest §5`).
**First runner owns the install** (WP3-BASELINE.md line 124 rule):

```bash
# install (e2e project owns Playwright): from repo root
cd e2e && pnpm add -D @axe-core/playwright
git diff --stat   # expect only e2e/package.json + pnpm-lock.yaml
```

Runner skeleton (new file `e2e/src/specs/web/v2-a11y.e2e-spec.ts`; assumes the
repo's existing Playwright web project + authenticated fixture session — reuse
whatever login helper current `src/specs/web` specs use):

```ts
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const PAIRS = [
  { id: 'P1', url: '/v2/library' },
  /* … P2–P20 per manifest §2 … */
  { id: 'P21', url: '/v2/library/<fixture-asset-id>' },
  { id: 'P22', url: '/v2/library?sheet=move' }, // representative sheet state
];

for (const theme of ['light', 'dark'] as const) {
  for (const { id, url } of PAIRS) {
    test(`${id} axe (${theme})`, async ({ page }) => {
      await page.emulateMedia({ colorScheme: theme });
      await page.goto(url);
      await page.getByTestId('v2-shell').waitFor();
      await page.waitForLoadState('networkidle');
      const r = await new AxeBuilder({ page })
        .include('main')
        .withTags(['wcag2a', 'wcag2aa'])
        .analyze();
      expect(
        r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical'),
        JSON.stringify(r.violations, null, 2),
      ).toEqual([]);
    });
  }
}
```

Covering §17-a11y beyond axe (same spec file or a `v2-a11y-kb` companion):

1. Landmarks per pair: `getByRole('navigation')` (sidebar),
   `getByRole('toolbar')`, `getByRole('grid')` (until A1 fix lands — then
   whatever role the fix chooses), `getByRole('dialog')` on open sheets/viewer.
2. Focus: scripted Tab traversal sidebar→grid→viewer→dialog→close with
   `keyboard.press` only; assert computed `:focus-visible` outline is non-none;
   assert focus returns to invoking thumbnail/control on close (A9/A10).
3. Announcements: open each sheet + trigger move/add toasts; assert
   `role="alert"` errors and Toast `role="status"`/`aria-live` (A13). TOAST
   GATE: if the shared Toast has no live region, STOP — file to Toast owner via
   lead (shared-file lock), do not paper over with a V2-only live region without
   lead sign-off (duplicate announcements).
4. Contrast: force `forced-colors: active` emulation + dark theme; specifically
   exercise `.v2-btn-primary`, `.v2-link-btn`, `.v2-row-sub`, sheet error text (A18).
5. Manual checkpoint (documented, not automated): VoiceOver pass on P1
   idle/selected + P21 viewer (manifest §5.4).

Known pre-existing axe failures to expect on first run (from this static audit —
confirm each at runtime, do not pre-exclude): A1 grid owned-elements, A4
aria-label-ignored, A15 aria-disabled-misuse, A18 color-contrast.

### 6.2 Perf probes (manifest §6 table + thresholds)

Harness: Playwright `test.step` timings + `performance` marks; Chromium
`performance.memory` where available. All six in one spec
(`e2e/src/specs/web/v2-perf.e2e-spec.ts`) so machine/build-mode headers are uniform.

| # | Probe | Steps | Pass threshold (§17-perf) |
|---|---|---|---|
| 1 | Initial library load | cold `goto /v2/library` → record LCP + time-to-first-thumbnail-row; assert `networkidle` settles | documented + idle settles (no loop = P4 confirmed live) |
| 2 | Sustained scroll | scripted wheel burst over P1 (group=all), rAF-delta p95 | no jank regression vs classic `/photos`; no layout-thrash loop |
| 3 | Zoom + regroup | cycle zoom 64→300 + years/months/all, measure re-layout ms | completes; `data-rendered-tiles` ≪ `data-total-assets` throughout (no full DOM) |
| 4 | Source switch | personal→space→library, swap ms + screenshot stale-frame check | no stale-source flash |
| 5 | Viewer open/close | thumbnail→viewer→close, both directions; heap delta before/after ×10 cycles | symmetric timing; heap delta bounded (no leaked listeners = P6 confirmed live) |
| 6 | 10k virtualization (**hard gate**) | bulk corpus via `fixtures.ts#makeAssetBatch(10000, seed)` (manifest §6: wire to bulk-import or mocked store — NEVER hand-render in a unit test); assert thumbnail DOM nodes < 5% of 10k; heap growth sublinear vs 1k corpus | **rendered nodes ≪ 10k; sublinear heap** |

Static risks to watch live: P1 join-key cost under probe 3/keyboard repeat; P2
per-tick `goto` during slider drag (if probe 3 janks, debounce lands here); P5
remap pattern (keep 10k corpus on the manager path).

### 6.3 Screenshot sequence (P1–P22, refs/CAPTURE-LOG.md recipe)

Host recipe base (from `refs/CAPTURE-LOG.md`): fixture app frontmost at 1400×900
(`--fixture-seed`), dark via `screencapture -l<winid>`, toggle appearance for
light, XCUITest/manual for states. Browser-side mirror per pair (manifest §2
states; masks = amended §3 per §3 of THIS doc):

- P1 library: idle, selected 1 + multi, years/months/all, source menu open, zoom
  min/max. P2 collections: idle, folder group. P3 search: idle, results,
  type-ahead open (**mask dropdown** until §3-amendment decides).
- P4 favorites (idle, selected), P5 recently-saved, P6 map (**mask tiles**),
  P7 people (+detail +merge dialog), P8 memories (cover, playback —
  **mask progress**, shoot paused).
- P9–P11 media filters; P10 durations unmasked unless variance demonstrated.
  P12 space (+member menu, unauthorized), P13 external library (+import progress),
  P14 album (+viewer-from-album, add-assets dialog).
- P15 imports (idle/in-progress/error — progress % masked, shoot idle+completed),
  P16 trash (+restore/delete dialog), P17 hidden (auth gate), P18 archive,
  P19 locked (gate + unlocked), P20 settings (each section; **mask storage-usage
  row** until stubbed).
- P21 viewer (open, info open/closed, prev/next, broken-asset, video).
  P22 sheets cross-route (selection toolbar, move/copy picker, create
  album/space, date edit, delete confirm, toasts — **mask whole toast region**).
- Every pair: light + dark, 1400×900, frozen clock; gate = §17-visual (2 px / 1%
  post-mask / no h-overflow).

## 7. Recommended owners (lead routing)

- Grid + interaction agent: A1/A2/A3 (grid roles/names), A8 (roving tabindex),
  P1 (join-key), P2 (zoom debounce).
- Shell/dialog agent: A15 (unavailable rows), A16/A17 (motion/forced-colors CSS),
  A18 (primary/link contrast).
- Viewer agent: A5 (aside labels), A12 (shortcut disclosure).
- Memories/feature agent: A10 (player trap/restore), A4 (map region), A6 (count announcements).
- Lead: §3 mask amendments (5 items), A1 role-choice sign-off, A13 Toast-owner
  escalation path, A19 theme-mechanism check, A14 post-gate live region.
- Host runner: §6.1 install + axe pass, §6.2 six probes, §6.3 P1–P22 captures.

## 8. Residual risks after static audit

1. Thumb determinism (mask conflict rows 3–4, §3) can invalidate every grid
   baseline if decided late — earliest lead decision in this doc.
2. Shared Toast live-region status (A13) is the single biggest §17-a11y unknown;
   it sits in code this project may not own.
3. Theme mechanism mismatch (A19) could void all dark baselines.
4. No unit/component test in this audit ran (static-only mandate) — recommend the
   host runner start with `cd web && pnpm exec vitest run
   src/lib/components/heirloom src/lib/heirloom` to catch regressions before the
   browser passes.
