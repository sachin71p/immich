# WP0-LOGGING slice report (Wave 1, first commit)

## Files changed
- `native-apple/PhotosCore/Sources/CoreModel/Log.swift` (new): `public enum HeirloomLog`
  with static `os.Logger`s, subsystem `com.immich.heirloom`, categories `timeline`, `media`,
  `sync`, `store`, `ui`; plus `public enum HeirloomSignpost` with signpost-name constants
  (`gridLoad`, `snapshotBuild`, `layoutPrepare`, `thumbnailFetch`, `thumbnailDecode`,
  `viewerOpen`) and `interval(_:_:)` sync + async helpers.
- `native-apple/Apps/macOS/Sources/MacAppState.swift` (one smoke line in `refresh()`):
  `HeirloomLog.sync.debug("refresh userId=...")`.

## Skipped per brief
- `Apps/macOS/Sources/HeirloomLog.swift` NOT created: `MacAppState.swift` already
  `import CoreModel`, so the app sees the API directly (confirmed by a successful app build).
- No `project.yml` change and no manual `make xcodegen`: both the SPM `CoreModel` target
  and the app target use directory globs (`Apps/macOS/Sources`), so the new file is picked
  up automatically. (`make build-macos` runs xcodegen anyway; it produced no tree diff.)

## Commit
`debc46550` (`feat(photoscore): add HeirloomLog logging API`, 2 files, +61)
on branch `perf/heirloom-macos-wp0` in worktree `../immich-wp0`.

## Test output
- `swift build --package-path native-apple/PhotosCore --target CoreModel` → Build complete.
- `swift test --package-path native-apple/PhotosCore` → 129 tests in 18 suites, all passed.
- `make build-macos` (Debug; Release knob is WP0 step 1, out of scope) → **BUILD SUCCEEDED**.
  Two pre-existing warnings only (`SyncEngine` missing declared deps on `Nuke`/`Media`
  per dependency scan) — untouched by this slice.

## Deviations / contract notes (exact signatures)
- Signpost names are `static let`s on `HeirloomSignpost` in lowerCamelCase
  (`HeirloomSignpost.gridLoad: StaticString`, etc.), not bare `GridLoad` globals —
  Swift convention; raw values are the brief's PascalCase strings (`"GridLoad"`, …).
- `HeirloomSignpost.interval(_ name: StaticString, _ body:)` sync variant forwards to
  `signposter.withIntervalSignpost(name, around: body)` (this SDK labels the closure `around:`).
- The SDK's `OSSignposter` has **no async `withIntervalSignpost` overload**, so the async
  variant brackets manually: `beginInterval(name)` + `defer { endInterval(name, state) }`
  around `try await body()`. Same interval semantics; noted in a code comment.
- `OSSignposter(subsystem:category:)` initializer and `Logger(subsystem:category:)` used
  as briefed; signposter category is `timeline` (the harness's primary instrument).

## Open issues / blockers
- None for this slice. Local-build prerequisite (not committed, gitignored by
  `native-apple/.gitignore`): `ImmichAPI/openapi.yaml` was absent in the worktree and had
  to be generated via `bash native-apple/scripts/gen-api.sh` (copies repo-root
  `open-api/immich-openapi-specs.json`) before any `swift build`/`swift test` could plan.
  Later WPs will hit the same step.
