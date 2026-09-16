# Heirloom iOS — "No Photos" on device: sync is never triggered

Diagnosed 2026-09-16 on the owner's device "Sachin's iPhone" (UDID `00008150-0002604111A1401C`,
iOS 27.0), with bundle `com.immich.heirloom.ios` and server `https://heirloom.sapatel.duckdns.org`
(80k photos + 22k videos).

## Evidence
- **Symptom:** the Library tab shows "No Photos". The app is signed in (MainTabs visible), and pulling
  down does nothing.
- **The app reached the server:** the device URL cache (`Library/Caches/com.immich.heirloom.ios/Cache.db`)
  shows only `GET /api/server/ping` and `GET /api/users/me` (10:40). `Library/Application Support/media-cache`
  exists, which `AppSession.start()` creates.
- **No database on the device:** `heirloom.sqlite` is absent from both the app-group container
  `group.com.immich.heirloom.shared` (whole container copied via `devicectl … copy from --source /`) and
  the app container.
  - Not yet explained. Verify it after the fix (see Acceptance). If the file still never appears, the
    store path is wrong and must be investigated before anything else.
- **Console on relaunch** (`devicectl device process launch --console`): `Registration rejected;
  com.immich.heirloom.backup-processing is not advertised in the application's Info.plist`.
- **Preferences mismatch:** the app-container plist `com.immich.heirloom.ios.plist` holds
  `Heirloom.serverURL`. The group plist holds only `.heirloom-access-probe`.

## Root causes (verified in code)
- **S1 No reachable sync trigger.** `AppSession.syncNow()` (`Apps/iOS/Sources/AppSession.swift:167`) is
  called only from `LibraryGrid.refreshAll()` (`LibraryGrid.swift:685`), which is reached through:
  - `.refreshable` (`LibraryGrid.swift:616`), attached to a view whose scrolling content is
    `PhotoGridView`, a `UIViewControllerRepresentable` around a UIKit `UICollectionView`. SwiftUI's
    refresh action is only honoured by `List`/`ScrollView`, so the pull gesture does nothing.
  - `MoveSheet`'s completion, which needs photos selected first, so it's unreachable on an empty library.

  `start()`/`reload()` never sync, and no Sync Now control exists.
- **S2 Silent errors.** `session.lastError` is assigned in several places but never displayed in the UI
  (only read by `BackupScheduler`).
- **S3 `reload()` re-runs `start()` on every foreground** (`HeirloomIOSApp.swift` `.onChange(of: scenePhase)`).
  That rebuilds the connection, store, sync coordinator and pipeline each time, which is wasteful and
  can race an in-flight sync.
- **S4 `SharedContainer.sharedDefaults` isn't deterministic.** It re-probes on every access and may
  return the group suite on one call and `.standard` on another. `ConnectView` wrote `serverURL` into
  `.standard`; later reads may consult the group suite and not find it.
- **S5 Missing `BGTaskSchedulerPermittedIdentifiers`** entry for `com.immich.heirloom.backup-processing`.
- **S6 (suspected, verify)** Keychain queries use the literal string
  `"$(AppIdentifierPrefix)com.immich.heirloom.shared"` in Swift source (`ConnectView.swift`,
  `AppSession.swift` `SharedTokenStore.load`, `SharedContainer.keychainAccessGroup`). Build-setting
  variables aren't expanded in Swift string literals, so `kSecAttrAccessGroup` is invalid unless
  `saveBestEffort`/`loadBestEffort` fall back. Check what those do. If they rely on the fallback, resolve
  the real prefix at runtime: add an `AppIdentifierPrefix` Info.plist key via `project.yml` (value
  `$(AppIdentifierPrefix)`, which Info.plist processing *does* expand) and read it with `Bundle.main`.

## Fix (single work package)
Branch `fix/heirloom-ios-sync`, in its own worktree, cut from the current tip of `perf/heirloom-macos`
so the `HeirloomLog` API (from WP0) is available. Another orchestrator session is actively merging into
`perf/heirloom-macos` in the main checkout: **don't work in the main checkout, and don't merge.**

Owned files:
- `Apps/iOS/Sources/AppSession.swift`, `HeirloomIOSApp.swift`, `LibraryGrid.swift`, and the iOS
  Settings view file (find it)
- `Apps/Shared/SharedContainer.swift`, `Apps/Shared/ConnectView.swift`
- iOS target sections of `native-apple/project.yml`

`SharedContainer.swift` and `ConnectView.swift` are shared with macOS: keep their public API unchanged.

1. **Automatic sync (S1, S3)**
   - Add `@Published var isSyncing`, `lastSyncAt: Date?` and `timelineVersion: Int` to `AppSession`.
   - `syncNow()`:
     - no-op if already syncing;
     - sets `isSyncing`;
     - on success clears `lastError`, sets `lastSyncAt` and bumps `timelineVersion`;
     - on failure sets `lastError` (human text; ignore `CancellationError`) and logs via
       `HeirloomLog.sync`.
   - If `SyncCoordinator` exposes progress (applied item counts or a stream), publish
     `syncProgress: String?` ("Syncing… 12,340 items"); otherwise show an indeterminate state.
   - After a successful `start()`, fire `Task { await syncNow() }`.
   - `reload()`: if already signed in with the same server URL and token, don't rebuild. Just trigger
     `syncNow()` when `lastSyncAt` is nil or older than 60 s.
2. **Pull to refresh that works (S1)**
   - In `PhotoGridViewController`, add a `UIRefreshControl` to the collection view and set
     `alwaysBounceVertical = true`, so an empty grid can still be pulled.
   - Add `var onRefresh: (() async -> Void)?`. The control's action runs it in a `Task`, then calls
     `endRefreshing()` on the main actor.
   - Pass it from `PhotoGridView` (new parameter), wired to `refreshAll()`. Remove the ineffective
     `.refreshable`.
3. **Grid reload after sync.** `LibraryGrid`'s `.task(id:)` key includes `session.timelineVersion`, so
   rows appear once the sync lands. Other iOS tabs that read the store (Collections, Search, Shared)
   should also key their reloads on `timelineVersion`; list them in the report.
4. **Visible status (S2)**
   - The Library subtitle shows "Syncing…"/progress while syncing. Otherwise it shows the date range,
     or "No Photos · Pull down to sync" when empty.
   - When `lastError != nil`, show a dismissible banner above the grid with **Retry**.
   - The Settings tab gets a "Sync Now" row (disabled while syncing), "Last synced <relative time>",
     and the last error.
5. **Deterministic shared defaults (S4)**
   - `sharedDefaults` decides once per process (a `static let`).
   - Reading `serverURL`: if it's missing from the chosen suite but present in `.standard`, migrate it
     into the chosen suite.
   - `ConnectView` writes through the same accessor. Test the logic with a unit-testable helper that
     takes injected suites, if the PhotosCore/app test targets allow it.
6. **Info.plist (S5).** Add `BGTaskSchedulerPermittedIdentifiers: [com.immich.heirloom.backup-processing]`
   and the `processing` background mode, if `BackupScheduler` uses BGProcessingTask, via `project.yml`
   for the iOS app target. Run `make xcodegen`.
7. **Keychain access group (S6).** Verify, then fix as described above if needed. Existing tokens must
   keep working: try the resolved group first, then no group.
8. **Logging.** Add `HeirloomLog.sync` / `HeirloomLog.store` lines for: start (server host, user id
   prefix), store path chosen, sync start/finish/failure with duration and counts.

## Verification
1. Build: `make build-ios` (simulator), and a device build:
   ```bash
   xcodebuild -project native-apple/Heirloom.xcodeproj -scheme Heirloom-iOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath <worktree>/native-apple/.build/DerivedData-device -allowProvisioningUpdates build
   ```
   `DEVELOPMENT_TEAM=599Z443923` is exported by the Makefile; pass it explicitly if you call
   xcodebuild directly.
2. iOS UI tests (`-useFixtureStore`): pull-to-refresh on the grid triggers `refreshAll` (in fixture
   mode `sync` is nil, so assert that the refresh control ends), and the Settings Sync Now row exists.
3. On device (only if the owner asks you to install; the orchestrator/owner normally does):
   ```bash
   xcrun devicectl device install app --device 00008150-0002604111A1401C <path>/Heirloom-iOS.app
   ```
   then launch. Within 60 s, `xcrun devicectl device info files --device … --domain-type appGroupDataContainer --domain-identifier group.com.immich.heirloom.shared`
   must list `heirloom.sqlite` with a growing size. Copy it off (`device copy from`) and run
   `sqlite3 heirloom.sqlite "select count(*) from asset"`, which should approach ~102k after the
   initial sync completes. The grid shows photos without any user action.
   **If `heirloom.sqlite` still doesn't appear, stop:** log the path `SharedContainer.databaseURL()`
   returns and investigate before continuing.
4. Report: `.claude/plans/heirloom-ios-sync/REPORT.md`, covering changes, commits, build/test results,
   S6 findings, device verification results, and any remaining issues. Don't push or merge.
