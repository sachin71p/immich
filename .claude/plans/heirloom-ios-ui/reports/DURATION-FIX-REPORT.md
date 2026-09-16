# Duration fix report — iOS video badges 1000x too long

Branch `fix/heirloom-ios-duration` (from `b38ea8217`), worktree `../immich-ios-duration`.

## Commits

- `0a0b2da1f` `fix(core): convert sync duration ms to seconds, add shared badge formatter`
- `a15114479` `fix(core): rescale stored video durations ms to s via v4 migration`
- `80363591b` `fix(ios): use shared video duration formatter in grid badges`

Files: `PhotosCore/Sources/SyncEngine/WireTypes.swift`,
`PhotosCore/Sources/CoreModel/DurationFormat.swift` (new),
`PhotosCore/Sources/LocalStore/Schema.swift` (`v4_asset_duration_ms_to_s`),
`PhotosCore/Package.swift` (GRDB on the test target only),
`PhotosCore/Tests/DurationFixTests.swift` (new),
`Apps/iOS/Sources/LibraryGrid.swift`. No macOS files touched.

## Test results

- `swift test --package-path native-apple/PhotosCore`: 167 tests, 22 suites, all pass
  (includes 9 new `DurationFixTests`: wire `110708→111`, `1300→1`, `0→0`, `nil→nil`;
  migration seed-110708→111 with NULL untouched; formatter `5→0:05`, `111→1:51`, `3903→1:05:03`).
- `make build-ios`: BUILD SUCCEEDED. `bash native-apple/scripts/verify.sh ios`: TEST SUCCEEDED
  (4 UI tests, 0 failures). Device Release `xcodebuild … -destination 'generic/platform=iOS' … build`:
  BUILD SUCCEEDED, nothing installed.

## Every duration entry point found, and handling

- `WireAsset.duration` (sync `AssetV2`, incl. partner/album/space/library variants — one shared
  struct): server ms → `durationSeconds = ms/1000 rounded`. Fixed. There is no `SyncAssetV1`
  wire type and no REST `AssetResponseDto` mapping in PhotosCore, so nothing else to convert
  on the read path.
- `asset.durationSeconds` rows synced before the fix: one-shot `v4_asset_duration_ms_to_s`
  (`UPDATE … ROUND(durationSeconds/1000.0) … WHERE NOT NULL`), registered after existing
  migrations, old ones untouched, runs exactly once via GRDB. Sync checkpoints need no reset:
  re-delivered assets upsert through the fixed mapping and converge to seconds.
- `LibraryGrid.formatDuration` (`%d:%02d`, hours dropped): replaced with shared
  `CoreModel.VideoDurationFormat` (`m:ss` < 1h, `h:mm:ss` ≥ 1h, integer math, `0:01` minimum
  for positive durations, `0:00` clamp otherwise). No macOS badge/formatter exists, so the
  move strands no macOS call sites (macOS only uses `durationSeconds` in `FixtureSeed` and
  `durationMs` in `MacEditView`, both already correct).
- Upload/backup paths (left alone, already ms-correct): `Upload.swift`/`EditPersistence`
  send `duration` multipart field from `durationMs`; `BackupScanner` builds it as
  `Int(PHAsset.duration * 1000)` (Photos `duration` is seconds); iOS/macOS edit views do
  `Int(result.durationSeconds * 1000)`. Local AV/`CMTime` durations (`VideoEdit`,
  `EditView` trims, `MacEditView.macLoadDuration`) never touch server units.

## Built .app

`native-apple/.build/DerivedData-device/Build/Products/Release-iphoneos/Heirloom-iOS.app`
(Device Release, built only — never installed; no device, server, push, PR, or merge touched).
