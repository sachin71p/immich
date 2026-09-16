# A6 plan — Storage optimization (prep)

Goal: iOS "Free up space" (R14 parity) + iOS/macOS cache budgets, per
phases/A6-storage-optimization.md acceptance.

## Dependency status
Ready (A3/A4/A5 reuse): `Media/TieredMediaCache.swift` budget surface (`setBudget`,
`evict`, `usage`, pins — the exact A6 drive surface) + `MediaTier` tiers/fallback order;
`MediaPipeline` offline best-cached-tier fallback; asset table has `checksum`,
`isFavorite`, `localIdentifier`; `deleteAssets` already in openapi filter;
`SettingsView`/`MacSettingsView` exist with `formatBytes` helpers; A5 Upload queue
records server-side checksums (candidate verification source).
NOT ready: no candidate-selection logic; server verify-at-deletion op NOT in filter
(`getAssetInfo` missing — must add via `gen-api.sh`); no cutoff/favorites/albums/N-days
prefs model; no `PHAssetChangeRequest.deleteAssets` batch flow; no usage/per-tier UI;
no per-library "keep originals" pins UI; `handoff/A6-scout.md` upstream options not done.

## Work list
1. `PhotosCore/Sources/Media/FreeUpSpace.swift` — candidate selector (cutoff, keep
   favorites default-on, keep albums, keep-last-N-days, server-missing/trashed exclude;
   server verify at deletion time, never local-DB-only).
2. `PhotosCore/Sources/CoreModel/StoragePrefs.swift` — cutoffs, toggles, per-tier budgets,
   per-library pins (Codable, UserMetadata-synced w/ SharedLibraryPrefs pattern).
3. `PhotosCore/Tests/FreeUpSpaceTests.swift` — selection matrix (cutoff/fav/albums/N-days/
   missing/trashed), batch sizing, budget/evict behavior.
4. `Apps/iOS/Sources/FreeUpSpaceView.swift` — preview (counts+bytes), batch delete w/
   system confirmation, Recently-Deleted explainer + Photos deep link, optional post-batch prompt.
5. `Apps/iOS/Sources/Settings.swift` — "Optimize storage" toggle, download-originals pins,
   usage-per-tier screen (drive `TieredMediaCache`).
6. `Apps/macOS/Sources/MacStorageView.swift` — budget slider, per-library/album keeps,
   usage breakdown, purge (wired into `MacSettingsView`).
7. `handoff/A6-scout.md` — upstream Flutter Free-Up-Space options/defaults/checks (≤30 lines).

## Acceptance
- `bash native-apple/scripts/verify.sh core` (new matrix tests green)
- `bash native-apple/scripts/verify.sh ios` (FreeUpSpaceView + settings build, smoke)
- `bash native-apple/scripts/verify.sh mac` (storage view builds)
- Full gate: `bash native-apple/scripts/verify.sh all`

## Open questions
1. Server verify-at-deletion: `getAssetInfo` per candidate vs batched search — which op,
   and trashed-visibility semantics (non-trashed + accessible check)?
2. Auto mode after backup batch: prompt UI shape? Never silent — confirm copy.
3. Recently-Deleted deep link target URL (Photos app scheme) — fixed string?
4. Per-library pin persistence: StoragePrefs vs LocalStore table?
5. macOS budget slider range/defaults — mirror iOS or desktop-sized?
