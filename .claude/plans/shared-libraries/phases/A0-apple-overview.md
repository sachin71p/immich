# A0 — Apple track overview + workspace scaffold

Every A-phase implementer reads the "Architecture" and "Rules" sections of this file first. The A0 *task* is
the scaffold at the bottom.

## Architecture
Top-level dir `native-apple/` in the fork (new dir → zero upstream merge conflicts).
```
native-apple/
  project.yml                 # XcodeGen spec (agents edit YAML, never .pbxproj); `xcodegen generate`
  PhotosCore/                 # Swift package shared by iOS + macOS (all business logic lives here)
    Package.swift
    Sources/
      ImmichAPI/              # generated client (swift-openapi-generator) from open-api/immich-openapi-specs.json
      CoreModel/              # value types: Asset, Exif, Album, Space, Library, Member, Container, Prefs
      Rules/                  # mirrors DECISIONS §4 §6 §9 §10: canEdit/canFavorite, move targets, timeline scope
      LocalStore/             # GRDB SQLite mirror + queries (timeline buckets, filters, search index)
      SyncEngine/             # /sync/stream JSON-lines client, acks, backfill, reset, triggers
      Media/                  # image pipeline (Nuke), thumbhash, tiered disk cache + budgets, video/live URLs
      Upload/                 # upload queue, SHA1 checksum, bulk-upload-check dedupe, target resolution
      Editing/                # Core Image engine: recipe model, renderer, presets (UI-free)
      Search/                 # smart/metadata search API + local filter DSL
    Tests/                    # Swift Testing; runs with `swift test` on macOS, no simulator needed
  Apps/
    iOS/                      # SwiftUI shell + UIKit UICollectionView grid; extensions below
      Extensions/BackgroundUpload/   # PHBackgroundResourceUploadExtension (iOS 26.1+)
      Extensions/PhotoEditing/       # "Get full quality"/edit inside Apple Photos (A9)
      Extensions/Share/              # "Save to <library>"
      Extensions/Widgets/            # memories/favorites widget (A9)
    macOS/                    # SwiftUI shell + AppKit NSCollectionView grid
      Agent/                  # login-item menu-bar helper (SMAppService) for background sync/upload
  scripts/verify.sh           # single entry point for verifiers (see Rules)
```
- Targets: iOS 26.1+, macOS 26+. Swift 6 language mode, strict concurrency. Dependencies (SPM): GRDB, Nuke,
  swift-openapi-generator + OpenAPIRuntime + OpenAPIURLSession. No other third-party code without orchestrator approval.
- Server reachability: HTTPS via Tailscale MagicDNS (`https://<host>.<tailnet>.ts.net`, `tailscale serve` cert). No ATS exceptions.
- Auth: Immich login (`/auth/login`) → access token in Keychain (shared access group for extensions + mac agent).
- The local DB is the UI's only data source; network fills it (sync) and the media cache. UI never blocks on network
  for grid scrolling (thumbhash → thumbnail → preview → original, progressive).
- Everything requirement-related (R1–R17) is implemented once in PhotosCore; apps are presentation only.
- Design fidelity: follow Apple Photos *interaction patterns* (grid zoom levels, library switcher, sidebar, viewer
  gestures, info panel, edit tools layout). Use SF Symbols and system components. Never copy Apple artwork, icons,
  filter LUTs or the "Photos" name (App Review 5.2.5). Working app name: placeholder `PhotosFork` (rename later in project.yml).

## Rules for all A-phases
- Read: this file's Architecture + Rules, your phase file, DECISIONS sections it names, dependency handoffs.
- Put logic in PhotosCore with unit tests; keep app targets thin. Mirror server rules exactly (cite DECISIONS §).
- API types come only from the generated `ImmichAPI` module. If an endpoint you need is missing, write
  `BLOCKED: missing endpoint …` — do not hand-roll HTTP calls for server features.
- Verification entry point: `native-apple/scripts/verify.sh [core|ios|mac|all]`:
  - core: `cd native-apple/PhotosCore && swift build && swift test`
  - ios: `cd native-apple && xcodegen generate && xcodebuild -project PhotosFork.xcodeproj -scheme PhotosFork-iOS -destination 'platform=iOS Simulator,name=iPhone 17' build test`
  - mac: `... -scheme PhotosFork-macOS -destination 'platform=macOS' build test`
  (Pick an installed simulator name at A0 and write it into verify.sh.) Simulator/unsigned builds need no paid
  developer account; device installs and extensions on device do (or SideStore, see project notes).
- Snapshot/UI tests: at most a handful per phase (launch, grid renders fixture DB, viewer opens). Core logic is
  covered by `swift test`.
- Fixtures: `PhotosCore/Tests/Fixtures/` holds recorded JSON-lines sync streams and API responses; tests never hit a real server.
  World sync fixtures are recorded from the e2e world by `record-sync.ts` (TESTING.md §4); `e2e/fork-assets/rules-cases.json`
  must pass in Swift `Rules` tests (AP-02). Apple case ids: TESTING.md §5 "Apple" rows.

## A0 task — scaffold (depends on S0; can run before the server phases finish)
1. Create the tree above with empty-but-compiling modules, `project.yml` (iOS app, macOS app, extension targets
   declared but minimal), `scripts/verify.sh`, `.gitignore` for build products and the generated `.xcodeproj`.
2. Configure swift-openapi-generator as a build plugin (or a `scripts/gen-api.sh` pre-generation step if the plugin is
   too slow) reading `../../open-api/immich-openapi-specs.json`; include only operations the apps use (filter list
   in `openapi-generator-config.yaml`, extend it in later phases).
3. Minimal apps: iOS and macOS launch to a "Connect to server" screen (URL + email + password) that calls
   `/server/ping` and `/auth/login` through ImmichAPI and stores the token in Keychain.
4. Add `native-apple/README.md` (build steps, tool install: `brew install xcodegen`, simulator requirement).

Verify: `native-apple/scripts/verify.sh all`.
