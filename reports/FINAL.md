# FINAL — Heirloom iOS native-Photos UI (W1 + W2)

Branch: `feat/shared-libraries` (all work merged; per-WP branches retained in history).
Device: iPhone 17 Pro Max, iOS 27, ~102k assets (102,627 items on device).
Simulator gates: iPhone 17 / 17 Pro Max. Release `.app` installed on the phone (data + sign-in kept).

## Gate results (merged tree)

- `make build-ios`: GREEN.
- `swift test --package-path native-apple/PhotosCore`: 192/193. Sole red is the WP1
  `timelineRows 102k < 400ms` timing gate (6.1 s on a loaded host; green in isolation
  and on quiet runs — load-sensitive, not a code break).
- `bash native-apple/scripts/verify.sh ios`: GREEN 19/19, 0 failures — A3Smoke 1,
  A9Extras 1, CollectionsPerf 1, GridPerf 2, LibraryChrome 6, ScreenshotTour 1,
  Sync 2, Viewer 5.
- Device: Release build installed, launched, Library verified on-screen (below).
  Instrumented hang trace SKIPPED (see §Open items).

## Budgets: before → after

| Metric | Before | After | Evidence |
|---|---|---|---|
| Cold launch → first real thumbnails | ~10 s ("No Photos") | sim firstPaint 984 ms; device shows instant thumbnails (timing unmeasured) | GridPerfUITests; gate2-library-all.png |
| Hangs in scenario | 10, worst 2.1 s | sim zero post-settle stalls; device trace VOID (open) | GridPerfUITests; §Open items |
| render() main-thread share | 41% | cheap generation-gated setters (device number open) | code + sim stalls |
| Thumbhash on main | 23–34% | off-main `ThumbhashCache`, cache-hit-only sync path | code + sim stalls |
| Viewer open | 0.9 s hang | O(1) `ViewerRoute`; sim hang-guard green (device unmeasured) | ViewerUITests |
| Years/Months/All switch | multi-second | year/month cards + drill-down, key-photo only (sim-tested) | LibraryChromeUITests |
| Collections first paint / counts | slow, unbounded | shells-first + single-query counts (ms print unrecovered from xcresult) | CollectionsPerfUITests |
| Sync while idle | full rebuild | index diff + 2 s debounce (device hang data void) | code |
| Video badges | 1000× (ms shown as s) | ms→s mapping + v4 migration + `VideoDurationFormat` | DurationFixTests 9/9 |

## Audit rows

`03-audit.md` statused 59/59: all FIXED except P2 (device hangs — trace void) and T5
(BG keys dropped by Xcode from product plist — needs a `project.yml` decision), plus
device-unmeasured notes on P1/P6/P7/P8.

## Side-by-side pairs (paths only; contain personal photos — never commit)

- Library: `shots/device-native-02-library-scrolled.png` ↔
  `reports/gate2-shots/gate2-library-all.png`
- Tour (sim): `reports/gate2-shots/` `01-library-all`…`10-viewer-more-menu` (13 PNGs)
- Gate 1: `reports/gate1-shots/` (29 PNGs incl. `gate1-library-grid.png`)
- Reference set: `shots/device-native-*.png`; baseline: `shots/device-heirloom-*.png`

## Deviations from PLAN (accepted at review)

- WP2 zoom control in `safeAreaInset`, not `tabViewBottomAccessory` (accessory needs
  the new `Tab` API; WP5 has since moved MainTabs to `Tab` — revisit).
- WP2 filter menu uses nested submenus; drilled-in rows lose accessibility ids on
  iOS 27 (leaves tapped by label; ids kept for top level / future OS).
- WP3 `albumsContaining` additive PhotosCore query (replaces O(albums×assets) scan).
- WP5 `Settings.swift` survives as sections reused by the account sheet.
- WP5 hosts `AccountButton` until the orchestrator follow-up swapped it into
  Collections (done, `1f8bc6591`).

## Open items

1. Device hang trace: void twice (link drops at record start). Simulator
   evidence is strong (zero stalls), but P2 stays OPEN until a clean device trace.
2. T5 `BGTaskSchedulerPermittedIdentifiers`: documented open, needs owner call.
3. WP1 `timelineRows` 400 ms gate flakes under host load (green isolated).

## Tier accounting

- implementer (sonnet): WP0, WP1, WP2 (+closer, +menu fix), WP3, WP4 (+finisher),
  WP5, duration fix — code, tests, reports.
- verifier (sonnet): merge/build gates, Gate 1 + Gate 2 build gates, 2 trace
  summaries (1 void, 1 void).
- scout (haiku): WP1 + WP2–WP5 prep maps.
- orchestrator (opus): reviews, 7 merges, conflict resolutions, device
  install/launch/screenshots, audit status + FINAL.
