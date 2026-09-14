# A5 — Backup & upload (iOS background upload, macOS import + agent)

Depends on: A3, A4 · Reads: A0 Architecture+Rules · DECISIONS §6, §9 · handoff S4.
Pre-step: scout the upstream Flutter app's backup logic (`mobile/lib`, backup/upload services) for checksum and
dedupe conventions (`/assets/bulk-upload-check`, device asset ids, live-photo handling) — report ≤40 lines to
`handoff/A5-scout.md`, then implement.

## Tasks (Core: `Upload` module)
1. Upload queue (persistent in LocalStore): SHA1 checksum, bulk-upload-check dedupe, multipart upload with
   `spaceId` target resolution: explicit (per source rule) → user preference → personal; live-photo pairs (upload
   motion first, link), edited-vs-original policy (upload original; optionally also current edit), retry/backoff,
   progress, Wi-Fi/cellular/low-power rules.
2. Source rules: map each source (iOS device album, macOS folder, camera/SD card import) to a destination
   container (e.g. "Camera Roll → Mobile" library, "SD card → Camera" library).

## iOS
3. PhotoKit scanner: selected device albums, incremental via persistent change tokens (`PHPhotoLibrary` change
   history), limited-library handling.
4. `PHBackgroundResourceUploadExtension` target (iOS 26.1+): process system-scheduled upload jobs, retry, ack
   completion, handle termination (follow Apple's documented steps). Foreground/BGProcessingTask fallback.
   Verify early whether the extension needs a restricted entitlement for your signing setup; note result in handoff.
5. Settings UI: backup on/off, albums, destination rules, network rules, status.

## macOS
6. Import: files/folders (drag-in from A4), cameras & SD cards via ImageCaptureCore (device browser, thumbnails,
   select, "import all new", delete-after-import option), destination library chooser, duplicate skip.
7. Optional: back up the Mac's Apple Photos library via PhotoKit (same scanner as iOS where APIs allow).
8. Menu-bar agent (login item via `SMAppService`): runs sync + upload queue while the main app is closed;
   shares Keychain + LocalStore (app group container).

## Tests
Core: queue persistence/resume, dedupe, target resolution precedence, live-pair ordering. UI smoke for settings.

Verify: `native-apple/scripts/verify.sh all`.
