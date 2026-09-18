# CloudKit for Heirloom: Photo & Metadata Sync — Research Report

Date: 2026-09-17
Scope: Should Heirloom (self-hosted Immich fork; NestJS + Postgres server on homelab; native iOS/macOS/tvOS apps doing on-device ML) use CloudKit to sync photos and/or ML metadata among devices and the Heirloom server?

---

## 1. CloudKit databases, quotas, record/asset limits, rate limits

### Database types and who pays
- **Private database**: data is stored in the *user's own iCloud account* and counts against **their personal iCloud storage quota** (the free 5 GB tier, or whatever paid iCloud+ tier they have). Apple's own framing: "Store private data securely in your users' iCloud accounts for limitless scale as your user base grows." [CloudKit overview](https://developer.apple.com/icloud/cloudkit/)
- **Public database**: data counts against the **developer's/app's own CloudKit allotment**, not the user's iCloud quota. Apple currently advertises "up to 1PB of storage for your app's public data" for public DB. [CloudKit overview](https://developer.apple.com/icloud/cloudkit/)
- **Shared database**: a view over records another user has shared with the current user via `CKShare`; storage is still billed to the *record owner's* private database quota.
- I could not find a current, authoritative Apple page enumerating exact private-DB per-user request-rate/storage numbers (Apple's marketing page for CloudKit no longer states them plainly — checked directly, confirmed absent: [developer.apple.com/icloud/cloudkit](https://developer.apple.com/icloud/cloudkit/)). Historically-cited numbers from developer forums (**UNVERIFIED, and may be stale**): ~10 GB asset storage / 100 MB structured "data" storage / 40 requests-per-second per user for free accounts, scaling with the user's paid iCloud tier and app popularity. [Apple Developer Forums thread 665612](https://developer.apple.com/forums/thread/665612), [thread 93336](https://developer.apple.com/forums/thread/93336), [thread 80756](https://developer.apple.com/forums/thread/80756). Treat exact figures as **UNVERIFIED** — Apple has changed these before without notice; always design for graceful `CKError.quotaExceeded` / `CKError.requestRateLimited` handling rather than hardcoding numbers.

### CKRecord / CKAsset size limits
- **CKRecord (non-asset fields): 1 MB per record.** This is well-documented historically via CloudKit Web Services docs. [Data Size Limits](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html)
- **CKAsset**: assets are stored out-of-band (not counted against the 1 MB record limit). Current developer consensus/forum guidance: a single `CKAsset` can be very large — commonly cited **up to ~50 GB** via the native CloudKit framework (subject to the user having enough remaining iCloud storage) — not the older "50 MB" figure, which appears to be a **CloudKit Web Services–specific ceiling**, not a native-framework one. [Forums thread 651358](https://developer.apple.com/forums/thread/651358), [thread 127555](https://developer.apple.com/forums/thread/127555). **Mark the exact current ceiling UNVERIFIED** — Apple does not appear to publish a single canonical number in current docs; apps must handle `CKError.quotaExceeded` regardless. Large-asset sync (multi-GB ProRAW/video) is not "free" engineering even if technically permitted — you still need chunked/background/resumable handling.

### Rate limits / batch limits
- Per-request save/delete batch limit for `CKModifyRecordsOperation`-style writes: **250 records per batch** (saves + deletes combined) is the number given in current CKSyncEngine documentation (see §2). [CKSyncEngine docs](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5) (fetched 2026-09-17).
- Older CloudKit Web Services docs and forum threads cite similar but not identical figures for pre-CKSyncEngine APIs (200–400 items per request depending on operation type, 200 asset-upload tokens per request). [ProcedureKit issue #288](https://github.com/ProcedureKit/ProcedureKit/issues/288), [Forums thread 774403](https://developer.apple.com/forums/thread/774403). Treat any one of these as authoritative only for the specific operation type/SDK version cited; **use `CKSyncEngine`'s built-in batch-splitting behavior rather than hardcoding a limit.**
- Exceeding a limit surfaces as `CKError.Code.limitExceeded`; standard mitigation is "split the batch in half and retry." [Forums thread 774403](https://developer.apple.com/forums/thread/774403)
- `CKSyncEngine` automatically retries `notAuthenticated`, `accountTemporarilyUnavailable`, `networkFailure`, `networkUnavailable`, `requestRateLimited` (respecting server retry-after), `serviceUnavailable`, `zoneBusy`. It does **not** auto-resolve `serverRecordChanged` — that's on you. [CKSyncEngine docs](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)

---

## 2. Sync APIs

### CKSyncEngine — platform availability (verified from live Apple docs, fetched 2026-09-17)
```
iOS:          17.0+
iPadOS:       17.0+
Mac Catalyst: 17.0+
macOS:        14.0+
tvOS:         17.0+
watchOS:      10.0+
visionOS:     not listed as available
```
[CKSyncEngine class docs](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)

Key mechanics, quoted/paraphrased from the live doc:
- One `CKSyncEngine` instance targets **one database**; you'd run separate instances for private vs. shared DB.
- **"Don't use `CKSyncEngine` to sync your app's public database."** — explicitly documented restriction. Public DB sync must use lower-level `CKDatabase`/operation APIs directly.
- It auto-discovers or creates a `CKDatabaseSubscription` to get silent push notifications of remote changes, then schedules a fetch.
- Sync is **only automatic when signed into iCloud, on network, and system conditions are good** — if signed out, "the sync engine won't perform any sync tasks at all." This is a first-class failure mode Heirloom must design around (see §7).
- You must persist the engine's opaque state token yourself across launches.
- Requires the **CloudKit** and **Remote notifications** entitlements/capabilities.

### NSPersistentCloudKitContainer / SwiftData + CloudKit
- Both layer on Core Data's CloudKit mirroring, and share the same schema constraints:
  - **No unique constraints** — CloudKit's schema has no concept of one, since it isn't a relational DB. [Forums thread 656380](https://developer.apple.com/forums/thread/656380)
  - **All attributes must be optional or have a default value**; non-optional attributes with no default are forbidden. [Fatbobman: rules for adapting models](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)
  - **All relationships must be optional.**
  - **SwiftData's CloudKit integration (as of iOS 18) is private-database-only** — it does **not** support `CKShare`/shared DB or the public DB. If you need shared/public DB with a SwiftData model, you must drop to `NSPersistentCloudKitContainer` directly (optionally coexisting with SwiftData). [Alexander Logan: SwiftData meets iCloud](https://alexanderlogan.co.uk/blog/wwdc23/08-cloudkit-swift-data), [Fatbobman](https://fatbobman.com/en/posts/coredatawithcloudkit-2/)
- Practical implication for Heirloom: ML metadata models (face boxes, embeddings, labels) would need nullable fields and no uniqueness guarantees at the CloudKit layer even if enforced in your own Postgres schema — dedup/uniqueness logic has to be app-level.

### CKDatabaseSubscription + silent push
- **Only valid for private and shared databases, and only for custom zones** — "cannot be used to monitor changes in the public database or changes in the default zone of the private and shared databases." [CKDatabaseSubscription docs](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription)
- Requires `Background Modes > Remote notifications` capability; Xcode/CloudKit auto-provisions the APNs entitlement when CloudKit capability is enabled.
- This is a **device-side-only** notification mechanism — see §3 for why a Linux server cannot receive these.

### Conflict handling
- Standard `CKError.Code.serverRecordChanged` conflict flow: CloudKit hands you three record versions (client, server, ancestor) in the error's `userInfo`; you must merge onto the **server record** (it carries the correct change tag) and retry the save. [Apple Developer Forums / general CloudKit conflict guidance](https://developer.apple.com/forums/thread/719333)
- `CKSyncEngine` does **not** auto-resolve this — it's explicitly called out as something "you need to handle yourself." [CKSyncEngine docs](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)
- `CKShare` supports family/cross-account sharing of specific record zones; sharing semantics are a separate, non-trivial subsystem (participant roles, permissions, accepting share URLs) — no need for Heirloom unless you want to share a library across different Apple IDs (see §7 failure modes: family members are commonly on **different** Apple IDs).

---

## 3. Server access to CloudKit (the crux of this question)

This is the most important finding for Heirloom's architecture.

- **Server-to-server keys (ECDSA P-256 key pair registered in CloudKit Dashboard) work ONLY against the PUBLIC database.** Confirmed directly: "a server-to-server key allows a server script to authenticate with CloudKit and make API calls to the **public database** with the inherited privileges of the creator of the key... server to server keys only allow calls to the public database, not the private database." [CloudKit Web Services Reference](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html), corroborated by multiple current forum threads on server-to-server auth. [Forums thread 777574](https://developer.apple.com/forums/thread/777574), [thread 785207](https://developer.apple.com/forums/thread/785207)
- **Accessing a specific user's PRIVATE database from any server requires a per-user `ckWebAuthToken`.** That token is obtained one of two ways: (a) **CloudKit JS** running a client-side Apple ID sign-in flow in a web page, which fires an event containing the `ckWebAuthToken`; or (b) natively, via **`CKFetchWebAuthTokenOperation`** run from your app (using your CloudKit Dashboard API token), which mints a web-usable token tied to that signed-in user. [CKFetchWebAuthTokenOperation docs](https://developer.apple.com/documentation/cloudkit/ckfetchwebauthtokenoperation), [CloudKit Web Services setup](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html)
- **Token lifetime**: the web auth token is a **single-round-trip rotating token** — "each token is intended for a single round trip to the server... once the response is received, the previous token is no longer valid." The *session* it represents **expires 30 minutes after creation by default**, or **2 weeks** if the user checked "Keep me signed in" during the Apple ID sign-in dialog. [CloudKit Web Services setup docs](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html) — this means a headless NestJS server cannot hold a long-lived credential to a user's private DB; the app has to periodically refresh/hand off a fresh token, which requires the user's device to be reachable and the user to re-authenticate roughly biweekly at best.
- **A Linux Node.js server CAN speak CloudKit Web Services** — it's plain REST over HTTPS with request signing (ECDSA P-256, SHA-256 digest of the body, custom `X-Apple-CloudKit-Request-*` headers). There's no OS restriction; you generate the key pair with OpenSSL (`openssl ecparam -name prime256v1 -genkey -noout`), register the public key in CloudKit Dashboard, and sign requests yourself. [CloudKit Web Services Reference](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html), [Apple's own Node.js server-to-server sample](https://developer.apple.com/library/archive/samplecode/CloudAtlas/Listings/Node_node_client_s2s_README_md.html) (Apple ships this exact sample). But — critically — that sample and the whole server-to-server key mechanism is **scoped to the public database only** (previous bullet). There is no "Node CloudKit" library maintained by Apple for private-DB server access with any durability; community wrappers exist (e.g. `capacitor-cloudkit` for getting a `ckWebAuthToken` cross-platform) but they still bottom out in the same 30-min/2-week token. [capacitor-cloudkit](https://github.com/nkalupahana/capacitor-cloudkit)
- **Server-side push for private-DB changes: not available to a third-party server.** `CKDatabaseSubscription` delivers silent APNs pushes to *devices running your app* (needs the device's own push token + your app's APNs certs/entitlement) — it is not a mechanism a Linux server can subscribe to on its own. A server could only ever "hear about" private-DB changes indirectly, by an app instance forwarding what it received, or by polling CloudKit Web Services with a live (and short-lived) user token. **This effectively rules out CloudKit private DB as a push channel into the Heirloom NestJS server.**

**Bottom line for §3**: CloudKit private database is designed as a **device-to-device** sync fabric via Apple frameworks, gated by the user's own iCloud sign-in. It is not designed, and does not have durable/first-class support, for a self-hosted third-party server to read/write/subscribe to a specific user's private data on an ongoing basis. Public database is server-friendly but is *shared across all users of the app* and billed to Heirloom's developer account — wrong shape for private family-photo metadata.

---

## 4. tvOS

- CKSyncEngine, CKDatabaseSubscription, and CloudKit generally are available on **tvOS 17.0+** per the same platform table as iOS/macOS. [CKSyncEngine docs](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)
- tvOS apps have **only 500 KB of guaranteed persistent local storage** ("On-Demand Resources" and similar caches aside) — the rest goes into the Caches directory, which **the system may purge at any time while the app isn't running**, with no warning. This is a longstanding, well-known constraint that has deterred emulator/game developers from tvOS entirely. [AppleInsider](https://appleinsider.com/articles/24/05/20/apple-tv-hardware-storage-limits-will-keep-most-emulators-away), [9to5Mac](https://9to5mac.com/2024/05/20/tvos-restriction-game-apple-tv/), [Apple Developer Forums thread 16967](https://developer.apple.com/forums/thread/16967)
- Practical implication: a tvOS Heirloom app **cannot reliably keep a durable `CKSyncEngine` state token or a local metadata cache** across long idle periods — any sync-engine state persisted to the Caches directory (the only large-storage option) is subject to eviction, forcing a full state rebuild. tvOS should be treated as a **thin, ephemeral, read-mostly client** (browse via server API / stream from server or iCloud, don't rely on local durable state) rather than a full sync-engine participant.

---

## 5. Privacy / encryption

- **Advanced Data Protection (ADP)**: when a user enables it, CloudKit private-DB fields you explicitly mark as encrypted (via the `encryptedValues` property on `CKRecord`) plus **all `CKAsset`s** get end-to-end encryption where only the user's own trusted devices hold the keys. [Apple ADP support doc](https://support.apple.com/en-mk/guide/security/sec973254c5f/web), [apple/sample-cloudkit-encryption README](https://github.com/apple/sample-cloudkit-encryption/blob/main/README.md)
- `encryptedValues` covers most scalar/collection types (`NSString`, `NSNumber`, `NSDate`, `NSData`, `CLLocation`, `NSArray`) but **not `CKReference`** fields, and you should *not* separately mark `CKAsset` fields as encrypted since they're encrypted by default. [Apple encrypting-user-data doc via community mirror](https://github.com/livingston/apple-docs/blob/main/documentation/CloudKit/encrypting-user-data.md)
- **Implication for server access**: if a user has ADP on (increasingly Apple's recommended default), any CloudKit field/asset your schema marks encrypted becomes **cryptographically inaccessible to Apple's own servers, and by extension to any CloudKit Web Services caller including a Heirloom server** — even with a valid `ckWebAuthToken`, you get ciphertext, not plaintext, unless the request originates from one of the user's own trusted, ADP-enrolled devices. This compounds the §3 conclusion: server-side access to private-DB content is not just contractually narrow, it can be **cryptographically impossible** for ADP users.

---

## 6. Can/should CloudKit transport photo *originals*? — compare vs. iCloud Photos

- **iCloud Photos (PhotoKit) already does this job for free**, for the narrow case of "sync originals across a single user's own devices signed into the same iCloud account." It is Apple's dedicated, battle-tested photo-sync pipeline — CloudKit is not needed to move a photo from a user's iPhone to their own Mac; standard iCloud Photo Library already does that outside of any Heirloom code.
- **`PHCloudIdentifier`** exists precisely to solve "the same photo has a different local identifier per device": `cloudIdentifiers(forLocalIdentifiers:)` / `localIdentifiers(forCloudIdentifiers:)` let an app map an asset between devices sharing one iCloud Photos library, "designed to work best when running on an account signed in to iCloud Photos, but they will work even if the account is signed out." [PHCloudIdentifier docs](https://developer.apple.com/documentation/photos/phcloudidentifier), [WWDC21 session 10046 "Improve access to Photos in your app"](https://developer.apple.com/videos/play/wwdc2021/10046/?time=711)
- Using **CloudKit CKAsset** to also transport the original photo bytes would be **redundant with iCloud Photos** for the iPhone↔Mac case, would consume the user's iCloud storage a second time (once for iCloud Photos, again for your CKAsset copy) unless you carefully dedup, and buys you nothing iCloud Photos doesn't already do for device-to-device transport. Its only unique value would be *device-to-device transport when iCloud Photos syncing is off* (Heirloom explicitly does not want to depend on iCloud Photos being enabled, since a homelab-first, self-hosted product should work independently of Apple's cloud) — but if Heirloom doesn't want to depend on iCloud Photos, transporting originals through **your own Heirloom server** (already the source of truth) is more consistent with the product's "your own homelab, not Apple's cloud" positioning, and sidesteps double-charging the user's iCloud quota with multi-GB photo/video libraries.
- **Verdict for originals: do not use CloudKit.** Use direct device↔Heirloom-server upload/download (which you already have) for the photo bytes. This is also the only path consistent with "[No full originals download in Heirloom]" memory constraint (budgeted cache only) — CloudKit as a *photo* transport pushes toward keeping full-resolution copies broadly replicated, which cuts against that existing product decision.

---

## 7. Alternatives — pros/cons, and recommendation

### (a) Heirloom server as sole source of truth (REST + WebSocket/APNs push through the server)
**Pros:** One consistent data model across iOS/macOS/tvOS/web; no dependency on the user's Apple ID or iCloud quota/state; works for users not signed into iCloud at all; trivially supports multiple family members on different Apple IDs pointed at the same self-hosted library (a core Immich/Heirloom use case); full control over conflict resolution and history; no 1 MB record / 30-min-token / ADP-encryption surprises.
**Cons:** You must build and operate your own push/notify path (APNs directly from the NestJS server for iOS/macOS wake-ups, or a WebSocket kept warm) instead of getting it "for free" from CloudKit subscriptions; you own reliability/scaling.

### (b) CloudKit private DB as a device-to-device side channel for device-local, low-stakes state (processing leases, "which device is doing OCR on asset X", ephemeral settings), with the server remaining authoritative
**Pros:** Zero server infrastructure for these low-value, high-churn, per-user-device coordination signals; free automatic replication + silent push between a user's *own* Apple-ID-signed-in devices; useful specifically for "who's already processing this asset" leases so iPhone and Mac don't duplicate ML work.
**Cons:** Only works between devices sharing one Apple ID (breaks for multi-person households on separate Apple IDs sharing one Heirloom library — a stated deployment scenario per your memory notes); does nothing if the user isn't signed into iCloud; the 1 MB CKRecord and ~250-record/batch limits are irrelevant at this small scale, but every failure mode in §3/§5/§7 below still applies (ADP encryption, token issues N/A since server never touches this DB, but *the server also can't see this data* — which is fine, since it's meant to be device-local coordination, not authoritative state). This is a legitimate, narrow use.

### (c) `NSUbiquitousKeyValueStore` for tiny cross-device settings
**Pros:** Dead simple; **1 MB total per user, up to 1024 keys, 1 MB per individual value**, keys ≤ 64 bytes UTF-8 [Apple iCloud Design Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForKey-ValueDataIniCloud.html), [Forums thread 81766](https://developer.apple.com/forums/thread/81766). Fine for e.g. "last-viewed album" or a UI preference toggle synced across a user's own devices.
**Cons:** Far too small for any ML metadata (a single 512–768-float embedding alone is 2–3 KB; thousands of faces would blow the 1 MB budget fast); same single-Apple-ID limitation as (b); not a fit for Heirloom's actual metadata volume.

### Failure modes checklist (apply to (b)/(c), not needed for (a))
- User not signed into iCloud → CKSyncEngine "stays dormant," zero sync. Must not be a hard dependency.
- Different Apple IDs across family members sharing one Heirloom library → CloudKit private DB is per-Apple-ID; there is no shared private DB across people without `CKShare`, which adds real complexity (share URLs, participant management) for a feature (device coordination) that doesn't need cross-person visibility at all.
- Server needs multiple users mapped to different Apple IDs → confirmed impossible for the server to reach into each one's private DB durably (§3); reinforces that the **server cannot be a CloudKit private-DB participant**, only individual devices can.
- Quota exhaustion → `CKError.quotaExceeded`; for (b)/(c) this is unlikely given tiny payloads, but design to degrade gracefully (skip lease coordination, fall back to server-side "processedBy" locking) rather than fail hard.
- Offline → CKSyncEngine queues locally and flushes on reconnect; fine for the side-channel use case since the server doesn't depend on it.

### Recommendation
1. **Metadata (face boxes, embeddings, labels, OCR text, duplicate groups, processedBy) → Heirloom server/Postgres is the sole source of truth**, delivered to devices via your existing REST API plus a server-driven push/WebSocket mechanism (APNs sent directly by your NestJS server using your own Apple Push key, or a persistent WebSocket while foregrounded/backgrounded-allowed). This is (a). Rationale: works across Apple IDs, works signed-out-of-iCloud, avoids CloudKit's 1 MB/250-record/token-lifetime/ADP-encryption constraints entirely, and matches "self-hosted, homelab-owned" as the actual product thesis.
2. **Photo/video originals → transport via your own server**, not CloudKit `CKAsset` and not reliance on iCloud Photos. This avoids double-billing the user's iCloud quota and keeps Heirloom independent of Apple's cloud for its core value proposition, consistent with the existing "no full-originals in Heirloom app, budgeted cache only" decision.
3. **Optional, narrow use of CloudKit private DB (b)**: purely as an *optimization/coordination side-channel* between a single user's own Apple devices — e.g., "which of my devices is currently running Vision face-detection on asset X" leases, or push-me-awake hints — never as a source of truth, and with the server's own "processedBy"/locking logic as the required fallback since this channel can silently be absent (signed out, quota, ADP not blocking here since server doesn't read it, multi-person households). Skip this unless you specifically want to avoid iPhone and Mac double-processing the same asset and don't want to build that coordination server-side; it is genuinely optional, and building it purely server-side (a device claims a lease via your existing REST API) is simpler and doesn't have the Apple-ID-per-household gap.
4. **tvOS**: treat as a thin client only. Given the 500 KB persistent-storage ceiling and unreliable Caches survival, don't give it a `CKSyncEngine` role or local durable metadata cache — have it stream from the Heirloom server (or from iCloud Photos for playback) each session.
5. **Background upload of originals from iPhone**: use Apple's new (iOS 26.1) `PHBackgroundResourceUploadExtension` / (iOS 27+) `PHBackgroundResourceUploadJobExtension` (see §8) as the *transport mechanism* to your own server — this is unrelated to CloudKit and is the right way to get reliable background originals-upload to a self-hosted endpoint. Note the real constraint below before committing to it.

---

## 8. Background upload of PHAsset originals (iOS 26.1 / iOS 27)

Verified directly from Apple's live docs (fetched 2026-09-17): [Uploading asset resources in the background](https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background)

- **API names**: `PHBackgroundResourceUploadExtension` (introduced iOS 26.1; **deprecated as of iOS 27**) and its successor `PHBackgroundResourceUploadJobExtension` (async protocol, iOS 27.0 / macOS 27.0 / Mac Catalyst 27.0+). macOS/Mac Catalyst only ever get the newer protocol.
- It's a **Generic Extension target** (`EXExtensionPointIdentifier` = `com.apple.photos.background-upload`) that your host app enables via `PHPhotoLibrary.shared().setUploadJobExtensionEnabled(true)`, requiring full-library `.readWrite` photo authorization.
- The system schedules your extension's `processJobs()` opportunistically based on **network availability, power state, and device activity** — you don't control timing directly, only report `.completed` / `.processing` / `.failure`.
- **Not available in iOS Simulator** — must test on a physical device.
- **Info.plist requires `BackgroundUploadURLBase`** (a `String`, e.g. `https://api.example.com`) — Apple states this is required "for network access validation." This is a static, compile-time base URL baked into the app/extension. For Heirloom's actual multi-tenant, user-configured-homelab-URL model (every self-hoster points at their own domain/IP), **this is the real, load-bearing constraint**: a single hardcoded base URL doesn't fit "user types in their own server address" unless Heirloom mediates through one stable Heirloom-controlled domain (e.g., a fixed relay/redirect host) rather than each user's raw homelab URL. This exact problem is actively being discussed by the **Immich** project itself, confirming it's a real, currently-unsolved constraint for self-hosted apps, not a theoretical one. [immich-app/immich discussion #23245](https://github.com/immich-app/immich/discussions/23245), plus follow-on discussions [#23358](https://github.com/immich-app/immich/discussions/23358), [#23583](https://github.com/immich-app/immich/discussions/23583), [#23296](https://github.com/immich-app/immich/discussions/23296), [#25777](https://github.com/immich-app/immich/discussions/25777).
- Contrary to one early community claim that the request "can only contain the asset data itself" with no metadata — **Apple's own sample code sets custom HTTP headers** (`Authorization`, `X-Filename`, etc.) on the `URLRequest` passed to `PHAssetResourceUploadJobChangeRequest.creationRequestForJob(destination:resource:)`, and reads back arbitrary `responseHeaderFields` from your server's response. So **per-asset metadata like `deviceAssetId`/`deviceId` can ride as request headers** even though the body is the raw asset bytes (no multipart/form-data support) — this is more flexible than the earliest Immich community assessment suggested, though it still requires your server's upload endpoint to accept "headers + raw body" rather than "multipart form."
- **Resumability**: your server must implement the (draft) IETF "Resumable Uploads for HTTP" protocol: respond to a preflight `OPTIONS` with `200` + an `Upload-Limit` header (max bytes you accept) or `501` to opt out of resumability; and during the actual `POST`, send a `104 (Upload Resumption Supported)` informational response with a `Location` header before your final response. Both the OPTIONS preflight and the 104 informational response are described as required ("Your API must include both").
- **Inflight job limit**: the system enforces a cap on concurrently queued jobs (`PHPhotosError.limitExceeded` when exceeded) — you must `acknowledge()` completed/failed jobs to free capacity, and design `processJobs()` to run incrementally across many invocations rather than trying to drain the whole library in one call, since the system also imposes a per-invocation runtime limit (relaxed only under a `Developer Mode` toggle for testing, not in production).
- The system can also purge/terminate the extension at any time (`willTerminate()` callback) and may pause via `.processing` returns when transient limits are hit, or expire your `PHPersistentChangeToken` (`persistentChangeTokenExpired`), requiring a resync.

**Verdict on §8**: this is the correct, Apple-sanctioned mechanism for reliable background originals-upload to Heirloom's own server (not CloudKit), and it is materially better than pre-26.1 approaches (`BGTaskScheduler`/`URLSession` background sessions foreground-triggered only). But it is **not yet a drop-in fit for a self-hosted, user-configurable-URL product** because of the static `BackgroundUploadURLBase` requirement — Heirloom will likely need either (a) a stable Heirloom-operated relay/redirect domain that then forwards to each user's actual homelab URL, or (b) to wait/track how Immich itself resolves this (their discussions are open and active as of this writing), before adopting it as the primary upload path. Immich's own maintainers appear to be tracking this live — worth periodically checking discussions #23245/#23358/#23583/#23296/#25777 for a resolution pattern Heirloom could copy.

---

## Sources (all cited inline above; consolidated list)
- https://developer.apple.com/icloud/cloudkit/
- https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5
- https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription
- https://developer.apple.com/documentation/cloudkit/ckfetchwebauthtokenoperation
- https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html
- https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html
- https://developer.apple.com/library/archive/samplecode/CloudAtlas/Listings/Node_node_client_s2s_README_md.html
- https://developer.apple.com/documentation/photos/phcloudidentifier
- https://developer.apple.com/videos/play/wwdc2021/10046/?time=711
- https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background
- https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForKey-ValueDataIniCloud.html
- https://support.apple.com/en-mk/guide/security/sec973254c5f/web
- https://github.com/apple/sample-cloudkit-encryption/blob/main/README.md
- https://github.com/livingston/apple-docs/blob/main/documentation/CloudKit/encrypting-user-data.md
- https://alexanderlogan.co.uk/blog/wwdc23/08-cloudkit-swift-data
- https://fatbobman.com/en/posts/coredatawithcloudkit-2/
- https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/
- https://developer.apple.com/forums/thread/656380
- https://developer.apple.com/forums/thread/665612 , /93336 , /80756 (UNVERIFIED quota figures)
- https://developer.apple.com/forums/thread/651358 , /127555 (UNVERIFIED CKAsset ceiling)
- https://developer.apple.com/forums/thread/774403
- https://github.com/ProcedureKit/ProcedureKit/issues/288
- https://developer.apple.com/forums/thread/719333
- https://developer.apple.com/forums/thread/777574 , /785207
- https://github.com/nkalupahana/capacitor-cloudkit
- https://appleinsider.com/articles/24/05/20/apple-tv-hardware-storage-limits-will-keep-most-emulators-away
- https://9to5mac.com/2024/05/20/tvos-restriction-game-apple-tv/
- https://developer.apple.com/forums/thread/16967
- https://github.com/immich-app/immich/discussions/23245 , /23358 , /23583 , /23296 , /25777
