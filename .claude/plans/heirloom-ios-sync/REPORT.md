# Heirloom iOS sync fix — REPORT

Branch `fix/heirloom-ios-sync`, worktree `../immich-ios-sync`, cut from `perf/heirloom-macos`
tip `333bbee95`. No merge, no push, nothing installed to the device. Main checkout untouched
(except this untracked report file, placed next to PLAN.md as instructed).

## Commits (11, all `fix(ios): …`, per plan step)

- `8dd458c3f` Step 1 — auto-sync: `isSyncing` / `lastSyncAt` / `timelineVersion` on `AppSession`;
  `syncNow()` guards re-entry, clears `lastError` + stamps + bumps version on success, ignores
  `CancellationError`, logs via `HeirloomLog.sync`; `start()` fires `Task { await syncNow() }`;
  `reload()` skips the rebuild when signed in with the same server URL + token and only tops up
  the sync when never-run or > 60 s stale (S3). Fixture reload no longer reseeds a live store.
- `bc8090cc1` Step 2 — `UIRefreshControl` + `alwaysBounceVertical` in `PhotoGridViewController`,
  `onRefresh` plumbed through `PhotoGridView` (defaulted nil so Search results compile unchanged),
  wired to `refreshAll()`; ineffective `.refreshable` removed. New `SyncUITests.swift`.
- `dc5e5efc6` Step 3 — Library `.task(id:)` key is now `"\(sourceKey)-\(session.timelineVersion)"`.
- `919c4e54e` Step 4 — subtitle shows Syncing… / date range / "No Photos · Pull down to sync";
  dismissible error banner with Retry over the grid; Settings gains Sync section (Sync Now row
  disabled while syncing, Last-synced relative time, last error). Settings UI test added.
- `c0e516f3d` Step 5 — `sharedDefaults` decided once (`static let`); `resolveServerURLString(chosen:fallback:)`
  migrates a `.standard`-stranded server URL into the chosen suite; `ConnectView` writes and
  `AppSession` reads/clears through the new accessors. Helper verified by compiling the real
  `SharedContainer.swift` with swiftc + a scratch harness (`/tmp/s5main`, 5/5 checks pass:
  nil-when-empty, migrate, chosen-wins, same-suite, empty-string fallthrough). No unit-test
  target exists for `Apps/Shared`, so this scratch compile is the verification.
- Step 6 — no commit: `UIBackgroundModes: processing` + `BGTaskSchedulerPermittedIdentifiers`
  were already in `project.yml` AND the generated pbxproj. See Finding F1 (they don't reach bundles).
- `7d5a3e9e3` Step 7 — S6 fix: `keychainAccessGroup` is now runtime-resolved from the new
  `HeirloomAppIdentifierPrefix` Info.plist key (added to the iOS target in `project.yml` +
  `xcodegen`), with guards falling back to the legacy literal; `AppSession`/`ConnectView`
  keychain queries use the central accessor; group-first-then-nil order preserved so old tokens work.
- `3ae16030d` Step 8 — `HeirloomLog.store` store-path line and `HeirloomLog.sync` session-start
  (host + user-id prefix) lines; sync start/finish/failure + duration landed in step 1.
- `2d36c9488`, `a70b24442`, `e37e32aa6`, `b38ea8217` — verification-driven fixes (below).

## Verification results

- `make build-ios` (simulator, needs `scripts/gen-api.sh` first — `make` doesn't run it): **SUCCEEDED**.
- Device Release build (generic/platform=iOS, `-allowProvisioningUpdates`, team 599Z443923):
  **SUCCEEDED**. Nothing installed (not authorized).
- `bash native-apple/scripts/verify.sh ios`: **exit 0 — all suites pass**: A3Smoke (29 s),
  A9Extras (26 s), Sync `testPullToRefreshEnds` (19 s), Sync `testSettingsSyncNowRowExists` (15 s).
- Fixes needed to get there: Swift 6 `nonisolated(unsafe)` on the shared suite; poll-loop instead
  of `waitForExpectations` (MainActor-isolated in this SDK); `isAccessibilityElement` attempt
  (insufficient — see F3); label-based Settings tab tap (tabItem identifiers propagate flakily).
- Device checks from PLAN Verification §3 (install, `heirloom.sqlite` growth, ~102k rows, grid
  fills with no action) were **NOT run** — install requires the owner. The auto-sync path that
  serves them is implemented (`start()` → `syncNow()`), but unproven on device.

## S6 finding (verified)

The suspicion is confirmed: `"$(AppIdentifierPrefix)…"` in Swift source never expands, so every
group-scoped Keychain call used an invalid access group and `saveBestEffort`/`loadBestEffort`
survived purely on the no-group fallback — consistent with the device reaching the server while
the group plist held only the probe key. The runtime-prefix resolution is implemented, but see
F2: under this machine's Xcode 27.0 (27A266a) the `HeirloomAppIdentifierPrefix` key never reaches
built bundles, so the code keeps the legacy behavior here (tokens keep working — no regression;
the improvement activates wherever the toolchain emits the key).

## Findings

- **F1 — plan step 6's premise is wrong on this toolchain.** The BG plist entries have been in
  `project.yml`/pbxproj all along, yet NO bundle on this machine contains them: not my sim +
  device builds, not the owner's earlier builds in other DerivedData dirs. This matches the
  plan's device evidence ("Registration rejected … not advertised"), i.e. the S5 console error
  will persist for builds from this toolchain. Selectively dropped: `BGTaskSchedulerPermittedIdentifiers`,
  `UIBackgroundModes`, `CFBundleName`, `HeirloomAppIdentifierPrefix`. Emitted fine:
  `CFBundleDisplayName`, `UISupportedInterfaceOrientations`, `NSPhotoLibraryUsageDescription`
  (mine). Values resolve correctly in `-showBuildSettings`; the drop happens inside Xcode 27's
  `builtin-infoPlistUtility` step for reasons I could not determine (empty base plist confirmed,
  no INFOPLIST_FILE conflict, no build warnings). Recommendation: verify on the owner's Xcode
  (possibly different version) and, if it also drops them, switch the iOS target to a static
  `Info.plist` instead of `INFOPLIST_KEY_`.
- **F2 — S6 activation blocked by F1** (see above). Fallback order = old tokens keep working.
- **F3 — real crash found by the new test, fixed.** Opening Settings killed the app with
  `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__` (`PHPhotoLibrary` auth from `BackupSettingsSection`,
  no `NSPhotoLibraryUsageDescription` anywhere in the project — pre-existing gap). Added the key
  to the iOS target in `project.yml`; Settings now opens (test proves it). Any prior device build
  would crash the same way on opening Settings.
- **F4 — `verify.sh ios` regenerates without `DEVELOPMENT_TEAM`** (the Makefile exports it;
  `verify.sh` doesn't), so every `verify.sh` run rewrites all `DevelopmentTeam` lines to the
  unexpanded `"${DEVELOPMENT_TEAM}"` string, which then breaks device builds ("requires a
  development team" — env can't override a project-level setting). Always re-run
  `DEVELOPMENT_TEAM=599Z443923 xcodegen generate` afterwards; I left the tree in that state.
  Note `git add` on the tracked-but-gitignored `project.pbxproj` needs `-f`.
- Counts in sync logs: unavailable — `SyncCoordinator.syncNow()` returns did-run only, no
  progress stream; UI is indeterminate by design (noted in code).
- Refresh-test residual gap: the UIRefreshControl never appears in the XCUI tree, so the test
  asserts swipe → grid accessibility value back to `idle` → grid intact, plus code-reviewed
  wiring (`didPullToRefresh` awaits `onRefresh` before `endRefreshing`). A refresh that never
  triggers would still read `idle`; the endRefreshing ordering is review-covered, not test-covered.

## Step 3 — other store-reading tabs (NOT re-keyed; files outside the owned list)

- `Collections.swift`: `.task { reload() }` (225), per-row `.task(id: rowId)` (60), manage-scope
  tasks (281–282, 295–296), connection task (337–338).
- `SearchView.swift`: recents (48), results (126), search run (216–222), chips (279–304),
  scope (354), loader (398).
- `Spaces.swift`: list reload (147), space timeline (189–195), library scope (394–396).
- `Albums.swift`: reload (94, 120), pagers (321–322, 352–353, 446–448).
- `MemoriesView.swift`: reload (79, 86–98), sections (171), asset (225).
- Suggested one-line pattern per site: `.task(id: session.timelineVersion) { await reload() }`
  (needs `session` in scope; all these views already hold it as `@EnvironmentObject`).

## Remaining / handoff

1. Owner: install the Release device build to "Sachin's iPhone" and run PLAN Verification §3
   (`heirloom.sqlite` appears + grows; ~102k rows; grid fills unaided). If the sqlite file still
   never appears, log what `SharedContainer.databaseURL()` returns (now in logs via `HeirloomLog.store`).
2. Decide F1: confirm BG keys on the owner's toolchain or move iOS to a static Info.plist; until
   then the BG "Registration rejected" console error stands.
3. Optional: re-key the five tabs above on `timelineVersion`; add per-record sync counts to
   `SyncCoordinator` if progress display is ever wanted.
4. Watch: `BackupScheduler.scheduleNext()` uses `BGTaskScheduler.submit`, deprecated in iOS 27
   (build warning, pre-existing, untouched).
