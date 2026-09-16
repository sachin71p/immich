# WP3 — V2 deterministic visual/functional manifest

Reference environment: **1400 × 900 viewport, light + dark themes** (PLAN §15-visual, §17-visual).
Every comparison pair is: **classic route vs V2 route vs native reference** (native ref confirmed/filled by WP1
PARITY-MATRIX; "likely none" marks expectations only — WP1 decides).

## 1. Deterministic fixture setup

1. Seed: fixed fixture corpus (see `web/src/lib/heirloom-test/fixtures.ts`) — seeded PRNG (`mulberry32`),
   fixed UUIDs (`00000000-0000-4000-8000-<n>`), fixed capture timestamps anchored to a frozen "now"
   (`2026-01-15T12:00:00Z`; mirrors the `vi.setSystemTime` pattern in `timeline-util.spec.ts`).
2. Corpus shape per source: personal assets (photos, videos, screenshots), one space, one external library,
   favorites, trash, hidden, archive, locked, one album, one person with faces, one memory, map GPS points.
3. Server-backed runs (Playwright/Docker): create fixtures via existing `e2e/src` generators where possible;
   otherwise plant the same logical corpus and record the seed in the report. Client-only runs (Storybook-less
   component shots): import `fixtures.ts` directly.
4. Clock: freeze to fixture "now" (Playwright `clock.install` / `vi.setSystemTime`) so relative group titles
   ("today", "yesterday") and memories are stable.
5. Network: block/stall map-tile and ML-embedding endpoints; map tiles are always masked (see §3).
6. Order: sort fixtures by capture time desc, tie-break by id — stable across runs.

## 2. Comparison pairs (all PLAN §7 routes)

`C` = classic route, `V` = V2 route, `N` = native ref (WP1 to confirm; notes are expectations).

| # | V2 route | Classic counterpart (C) | Native ref (N) | States to capture |
|---|---|---|---|---|
| P1 | `/v2/library` | `/photos` (or timeline home) | Library grid | idle, selected (1 + multi), each grouping (years/months/all), source menu open, zoom min/max |
| P2 | `/v2/collections` | `/albums` (+folders view) | Albums/Collections | idle, empty-ish, folder group |
| P3 | `/v2/search` | `/search` | Search | idle, results, date type-ahead open |
| P4 | `/v2/favorites` | favorites view | Favorites | idle, selected |
| P5 | `/v2/recently-saved` | recently-added view | Recents | idle |
| P6 | `/v2/map` | `/map` | Places/Map | grid-synced, marker selected (**tiles masked**) |
| P7 | `/v2/people` | `/people` | People | idle, person detail, merge/manage dialog |
| P8 | `/v2/memories` | memories surface | Memories | cover, playback (**mask playback progress**) |
| P9 | `/v2/media/photos` | photos filter | likely none — record explicit "no native surface" | idle |
| P10 | `/v2/media/videos` | videos filter | likely none | idle, duration badges (**mask durations if encoder-dependent**) |
| P11 | `/v2/media/screenshots` | screenshots filter | likely none | idle |
| P12 | `/v2/spaces/[spaceId]` | space view | Shared library | idle, member menu, unauthorized state |
| P13 | `/v2/libraries/[libraryId]` | external library view | likely none | idle, import progress |
| P14 | `/v2/albums/[albumId]` | `/albums/[id]` | Album | idle, viewer open from album, add-assets dialog |
| P15 | `/v2/imports` | upload/import surface | Import | idle, in-progress, error |
| P16 | `/v2/trash` | trash | Recently Deleted | idle, restore/delete dialog |
| P17 | `/v2/hidden` | hidden | Hidden | idle, auth-gate if any |
| P18 | `/v2/archive` | archive | likely none | idle |
| P19 | `/v2/locked` | locked folder | Locked | locked gate, unlocked idle |
| P20 | `/v2/settings` | `/settings` (browser-relevant subset) | Settings | each section; **only V2-owned settings** |
| P21 | viewer (all `[[assetId=id]]` routes + album viewer) | classic asset viewer | Viewer + inspector | viewer open, info open/closed, nav prev/next, broken-asset, video |
| P22 | dialogs/sheets (cross-route) | same dialogs on classic | share/action sheets | selection toolbar, move/copy target picker, create album/space, date edit, delete confirm, toasts |

Acceptance per pair (gates §17-visual): major-component geometry ≤ 2 px, type baselines ≤ 2 px,
post-mask pixel diff < 1%, no unexpected horizontal overflow, light **and** dark pass.

## 3. Screenshot mask list (exhaustive — mask ONLY these)

1. Map tiles and any network-fetched imagery (P6) — nondeterministic external content.
2. Memory playback progress / scrub positions (P8) — time-dependent.
3. Video duration badges **only if** encoder-dependent variance is demonstrated; otherwise unmasked (P10/P21).
4. Relative clock text that escapes the frozen clock (e.g. "x minutes ago" rendered client-side from real
   `Date.now`) — prefer fixing the freeze over masking; mask only with written justification.
5. Toast auto-dismiss progress bars.
6. Upload/import live progress percentages (capture idle + completed states unmasked instead).
7. User avatar photos in member menus — use seeded identicon/initial fixtures so these stay **unmasked**;
   mask only real-user photos if a shared dev server leaks in.
8. Scrollbar rendering (platform-dependent) — mask or normalize via CSS (`scrollbar-gutter: stable` + overlay
   scrollbars off in the harness).
9. Toast region entirely (WP11 audit row 5: 4 s auto-dismiss makes presence timing-dependent; supersedes
   item 5's progress-bars-only wording).
10. Viewer inspector EXIF values + locale-sensitive dates (WP11 row 6) — or pin locale+timezone in the
    harness and record the pin.
11. Open type-ahead/suggestion dropdowns (WP11 row 7).
12. Settings storage-usage bytes (`navigator.storage.estimate`, P20 — WP11 row 12).
13. Count headlines: map `v2-map-count`, people `v2-people-count`, search `v2-search-count` (WP11 row 13) —
    or pin fixture counts and record the seed.
14. Grid thumbnails (WP11 row 3): follow WP1 (mask) until a deterministic thumbnail stub lands in
    `fixtures.ts`; sidebar space/library/album name rows (WP11 row 4): mask unless the server fixtures
    are seeded with fixed names.

Everything else — sidebar, toolbar, grid geometry, typography, thumbnails from fixtures — stays **unmasked**.
Any new mask requested later must be appended here with reason + approver (lead).

## 4. Functional harness notes (for Wave-2/3 agents)

- URL-state cases live in `web/src/lib/heirloom-test/url-state.ts`: builder + normalization vectors per
  PLAN §9 (source/group/zoom precedence, invalid-value normalization, no-reload-loop rule).
- Back/forward restoration, selection/range/select-all/clear, viewer page/info/close, create-album/add-assets,
  move-allowed/move-rejected, import, search/open-result, map/grid sync, visibility changes — each maps to one
  Playwright spec file named `v2-<area>.e2e-spec.ts` beside the pair it covers; classic-route regression specs
  stay untouched.
- Role/permission boundaries reuse fork-E2E `spaces`/`library-members` fixtures; denial-status expectations
  follow the decided contract (denials on fork surfaces → 403; upstream endpoints unchanged).

## 5. Accessibility method (runnable by Wave-4 a11y agent)

`axe-core` is **not currently installed** (verified 2026-09-16 in `web/`, `e2e/`, root manifests) — the a11y
agent installs `@axe-core/playwright` (package.json change is theirs, not WP3's).

1. **Automated**: `AxeBuilder({ include: ['main'] }).analyze()` per pair (P1–P22), light + dark; gate = zero
   serious/critical findings (§17-a11y). Exclude masked regions from the takeover, not from axe.
2. **Role checks** (no new deps, runnable now): for each pair assert `getByRole` landmarks —
   `navigation` (sidebar), `toolbar`, `grid` (timeline; `aria-rowcount` = fixture size), `dialog` on open,
   `img` names from fixture alts. Missing-name failures are V2 bugs, not harness gaps.
3. **Keyboard**: scripted traversal per primary workflow (sidebar→grid→viewer→dialog→close) using
   `keyboard.press` only; assert focus visibility (`:focus-visible` computed outline) and focus restoration
   to the invoking thumbnail/control on dialog close (§17: modals/toasts announced — assert `role=status`
   / `aria-live` presence + accessible name).
4. **Manual checkpoint** (documented, not automated): VoiceOver/NVDA pass on P1 idle/selected + P21 viewer.

## 6. Performance method (runnable by Wave-4 perf agent)

Harness: Playwright `test.step` timings + `page.evaluate` marks; Chromium `performance.memory` where
available; record machine + build mode (dev vs prod) alongside every number.

| Probe | Method | Gate (§17-perf) |
|---|---|---|
| Initial V2 library load | cold load P1 → `largest-contentful-paint` + time-to-first-thumbnail-row | documented; no uncontrolled fetch loops (assert settled network idle) |
| Sustained scroll | scripted wheel burst over P1 (all-grouping), frame-time p95 via rAF deltas | no jank regression vs classic; no layout-thrash loops |
| Zoom + regroup | cycle zoom 64→300 + groups years/months/all, measure re-layout ms | completes without full-collection DOM render |
| Source switch | personal→space→library, measure swap ms + stale-frame check | no stale-source flash in screenshots |
| Viewer open/close | thumbnail→viewer→close, measure both directions | symmetric, no leaked listeners (heap delta bounded) |
| 10k-asset virtualization | generated 10k corpus; assert rendered thumbnail DOM nodes ≪ 10k (e.g. < 5%) and heap growth sublinear vs 1k corpus | **virtualized, no full DOM render** (hard gate) |

Perf corpus generator: extend `fixtures.ts#makeAssetBatch(count, seed)` (already stubbed for scale) — the
perf agent wires it to a bulk-import or mocked store; do not hand-render 10k nodes in unit tests.
