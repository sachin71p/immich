# Heirloom Web V2 — rollout and comparison document (WP12)

Date: 2026-09-16. Status: implementation complete, static gates green, runtime
gates host-pending (see §6).

## 1. What shipped

A new authenticated browser experience under `/v2` matching the native macOS
Heirloom app. `/v2` redirects (307) to `/v2/library`. Every classic route
(`/photos`, `/albums`, `/search`, …) is byte-identical and unlinked from V2 —
compare side-by-side via direct URLs. No server changes were made.

## 2. Route map (browser → native surface)

| Browser | Native |
| --- | --- |
| `/v2/library/[[assetId]]` | Library grid + toolbar + sidebar |
| `/v2/collections` | Collections grid (same query as Library) |
| `/v2/search/[[assetId]]` | Search (field + scope + suggestions + filters + results) |
| `/v2/favorites/[[assetId]]` | Favorites (headerless, limit 1000) |
| `/v2/recently-saved/[[assetId]]` | Recently Saved = Imports query (`recentAssets`) |
| `/v2/map/[[assetId]]` | Places/Map (map + selection grid split) |
| `/v2/people`, `/v2/people/[personId]/[[assetId]]` | People (minimal list + detail) |
| `/v2/memories` | Memories (stories shelf + On This Day + player) |
| `/v2/media/photos|videos|screenshots` | Media kinds (search-backed; screenshots = filename heuristic) |
| `/v2/spaces/[spaceId]` | Shared library + Manage sheet |
| `/v2/libraries/[libraryId]` | External library (upload-then-move) |
| `/v2/albums/[albumId]` | Album (album order + Add-to-Album) |
| `/v2/imports` | Same recency query as Recently Saved (D2) |
| `/v2/trash`, `/v2/hidden`, `/v2/archive`, `/v2/locked` | Visibility containers (Locked = personal-only) |
| `/v2/settings` | Browser-relevant settings subset (see §3) |

URL state: `source=all|personal|space:<uuid>|library:<uuid>`,
`group=years|months|all` (default `months`), `zoom=64..300` (default `120`).
Precedence: URL > V2 prefs (`heirloom-v2-*` keys) > native defaults. V2 prefs
never touch classic keys.

## 3. Browser exceptions (working or documented, never inert)

- macOS menu bar → V2 toolbar + shortcuts. Multi-window → URL-backed views.
- Quick Look → Heirloom viewer. Finder promises → explicit Download.
- Camera import → file picker + capture input. Background agent → unavailable
  explanation unless a real PWA feature lands. Cache budget → unavailable
  explanation. VisionKit/Live Text → macOS-only (server OCR retained).
- Viewer Rotate → display-only (no server field exists). Editor → Decision A:
  existing browser tools only, macOS-only tools labeled, zero inert replicas.
- V2 search follows global zoom (native uses fixed 160 px tiles) — recorded divergence.
- V2 Years/Months show visible headers (native ships flattened) — intentional D1
  divergence giving the segmented control visible meaning.

## 4. Test procedure (what ran here)

```bash
cd web
pnpm exec vitest run            # 82 files / 832 tests pass, 2 skipped (pre-existing skips)
pnpm exec tsc --noEmit          # clean
pnpm run check:svelte           # 0 errors, 0 warnings
```

ESLint crashes in `eslint-plugin-tscompat` on V2 AND pre-existing files —
environmental, host/CI must run lint.

## 5. Host runbooks (not run here — no Docker/browser authority)

- Axe pass: `WP11-QUALITY-AUDIT.md §6.1` (install `@axe-core/playwright` in `e2e/`
  first; P1–P22 light+dark; known static suspects A1-fixed/A4/A15/A18 to confirm).
- Perf probes: audit `§6.2` (load, scroll, zoom/regroup, source switch,
  viewer open/close, 10k virtualization asserting rendered ≪ total).
- Screenshots: `refs/CAPTURE-LOG.md` host recipe + `WP3-VISUAL-MANIFEST.md`
  (P1–P22, amended mask list items 1–14).
- E2E: `scripts/fork-test/run.sh e2e-web` (Docker Desktop required).

## 6. Known gaps and residual risks

1. No runtime screenshots exist ([N] provenance) — visual gate fully host-pending.
2. Axe/perf/E2E never executed here — static audit only; host runs decide the gates.
3. Toast announcement unconfirmed (implementation in `@immich/ui` package).
4. Dark theme follows OS `prefers-color-scheme` — verify against the app theme
   mechanism before dark baselines (A19).
5. Sidebar album list unvirtualized (fine for tens; known limit P7).
6. `V2Toolbar` Manage button ships disabled until WP7 sheets wire (A15 re-check at gate).
7. Screenshot filename heuristic needs WP1-fixture validation (WP2 §1).
8. Full editor parity (Decision B) is a separate milestone, not started.

## 7. Changed files (V2-only + plan docs)

New: `web/src/routes/(user)/v2/**` (~25 route files), full
`web/src/lib/components/heirloom/**` tree (shell/sidebar/toolbar/timeline/viewer/
search/map/memories/people/settings/dialogs/interactions/shared),
`web/src/lib/heirloom/**` (url-state, routes, view-state, tokens, drag-drop,
route-options, slice3-options, CSS + 8 specs), `web/src/lib/heirloom-test/**`
(WP3 helpers). Modified classic/product files: NONE (one test-only `as const`
fix lives in a V2 spec). Server changes: NONE.

## 8. Pre-existing worktree changes preserved (untouched)

`.claude/plans/deploy-heirloom-docker.md`; native-apple `MacAppState.swift`,
`MacMainWindow.swift`, `MacGridView.swift`, `HeirloomMacOSApp.swift`,
`SharedContainer.swift`, `AppSession.swift` (iOS), `ImmichConnection.swift`.
Nothing reset, stashed, or committed by any agent; no V2 link added to classic UI.
