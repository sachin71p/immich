# A5 plan — Backup & upload (prep)

Goal: durable Upload queue in PhotosCore + iOS PhotoKit scanner/background
extension + macOS import/agent, per phases/A5-upload-backup.md acceptance.

## Dependency status
Ready (A3/A4 reuse): `PhotosCore/Sources/LocalStore/*` GRDB store (asset table
already has `checksum`, `localIdentifier` cols — Schema.swift); `CoreModel/Prefs.swift`
`defaultUploadTarget` (explicit→pref→personal precedence); `SyncEngine/SyncCoordinator`
post-upload refresh pattern; `Media/MediaEndpoint` auth download (MacExporter reuse);
`Apps/macOS/MacDragDrop.swift` `MacImportChooserSheet` shell; `project.yml` extension
targets exist (BackgroundUpload w/ photos extension point, macOS Agent); `SettingsView`/
`MacSettingsView` prefs UI pattern; `ImmichAPI/ImmichConnection` bearer middleware.
NOT ready: `Upload/Upload.swift` is a 2-line stub (no queue/SHA1/dedupe/retry);
openapi filter (`openapi-generator-config.yaml`) lacks `uploadAsset`, `checkBulkUpload`,
`getAssetInfo` — `gen-api.sh` must add them; no PhotoKit scanner, no ImageCaptureCore
import, no app-group container (entitlements has keychain group only), no SMAppService wiring.

## Work list
1. `PhotosCore/Sources/Upload/UploadQueue.swift` — persistent queue (GRDB migration v2),
   SHA1, bulk-check dedupe, multipart POST /assets, spaceId resolution, live-pair order,
   retry/backoff, Wi-Fi/cellular/low-power gates.
2. `PhotosCore/Sources/Upload/SourceRules.swift` — per-source destination rules + prefs.
3. `PhotosCore/Tests/UploadQueueTests.swift` — persistence/resume, dedupe, precedence, ordering.
4. `Apps/iOS/Sources/PhotoKitScanner.swift` — album selection, change-token incremental,
   limited-library handling.
5. `Apps/iOS/Extensions/BackgroundUpload/Sources/BackgroundUploadExtension.swift` — real
   `PHBackgroundResourceUploadExtension` impl (jobs, retry, ack, termination).
6. `Apps/iOS/Sources/Settings.swift` — backup section (on/off, albums, rules, status).
7. `Apps/macOS/Sources/MacImport.swift` — ImageCaptureCore browser, thumbnails, import-all-new,
   delete-after-import, library chooser; wire `MacImportChooserSheet` to queue.
8. `Apps/macOS/Agent/Sources/HeirloomAgent.swift` — SMAppService login item, shared
   Keychain/LocalStore via app group; `Apps/Shared/Heirloom.entitlements` + `project.yml`.
9. `handoff/A5-scout.md` — upstream Flutter backup conventions (≤40 lines, phase pre-step).

## Acceptance
- `bash native-apple/scripts/verify.sh core` (swift build + PhotosCore tests incl. new file)
- `bash native-apple/scripts/verify.sh ios` (ext builds under signing setup)
- `bash native-apple/scripts/verify.sh mac` (agent builds)
- Full gate: `bash native-apple/scripts/verify.sh all`

## Open questions
1. Does `PHBackgroundResourceUploadExtension` need a restricted entitlement under our
   signing (Manual/adhoc vs Automatic+team)? Phase says verify early, note in handoff.
2. App-group ID for shared LocalStore/Keychain — new or existing? (affects entitlements.)
3. BGProcessingTask fallback: full queue runner or token-refresh only?
4. Edited-vs-original policy default: original-only, or also current edit?
5. Camera/SD delete-after-import default OFF? Confirm.
