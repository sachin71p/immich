# Add a "Shared Albums" sidebar section (macOS)

## Context / root cause
The server's `AlbumUserRole` enum (server/src/enum.ts:67-71) has three values:
`editor`, `owner`, `viewer` — every album's creator gets an `AlbumUserV1` row with
`role: "owner"` (see `SyncAlbumUserV1Schema`, server/src/dtos/sync.dto.ts:219-225).

The Swift client's mirror, `AlbumUserRoleKind` (native-apple/PhotosCore/Sources/CoreModel/Enums.swift:21-24),
only has `.editor` and `.viewer` — no `.owner`. When `AlbumUserRecord.model` decodes an incoming
`role: "owner"` string (native-apple/PhotosCore/Sources/LocalStore/Records/AlbumRecords.swift:44-47:
`AlbumUserRoleKind(rawValue: role) ?? .viewer`), the `rawValue:` init fails and it silently falls
back to `.viewer`. So today every album owner's own membership row is stored locally as "viewer" —
there is no way to tell "my album" from "an album shared with me" client-side.

Fix the enum gap, then use the now-correct role to split the sidebar's "Albums" list into
"Albums" (role == .owner) and a new "Shared Albums" section (role != .owner), placed directly
below the existing "Shared Libraries" section per product decision.

## Changes

### 1. `native-apple/PhotosCore/Sources/CoreModel/Enums.swift` (~line 21-24)
Add the missing case so it matches the server exactly:
```swift
public enum AlbumUserRoleKind: String, Sendable, Codable, CaseIterable {
  case owner
  case editor
  case viewer
}
```

### 2. `native-apple/PhotosCore/Sources/LocalStore/LocalStore+LibraryLists.swift` (~line 65-73)
Change `memberAlbums(for:)` to also return each album's role for the given user, mirroring
the existing `memberSpaces(for:)` pattern just above it (line 10-36) which already does a
`JOIN ... role` + tuple return. New signature:
```swift
public func memberAlbums(for userId: String) async throws -> [(album: Album, role: AlbumUserRoleKind)]
```
Join `album` to `albumUser` on `albumUser.userId = ?`, order by `album.updatedAt DESC` (same as
today), decode `albumUser.role` the same way `memberSpaces` decodes `spaceMember.role`
(`AlbumUserRoleKind(rawValue: roleString) ?? .viewer` is fine as a defensive fallback now that
`.owner` exists and is the only value that previously mis-mapped).

### 3. `native-apple/Apps/macOS/Sources/MacAppState.swift`
- Change `var albums: [Album] = []` (line 32) to `var albums: [(album: Album, role: AlbumUserRoleKind)] = []`.
- Update the `refresh()` call site (~line 167, currently `albums = try await a...` — read the
  surrounding lines to find the exact `store.memberAlbums(for:)` call) to match the new return type
  (no logic change needed beyond the type now carrying role).

### 4. Update every consumer of `state.albums` (all currently assume `[Album]`; grep confirmed
   exactly these four call sites, no others):

- **`native-apple/Apps/macOS/Sources/MacSidebar.swift`** (~line 46-50): split the single
  `Section("Albums")` ForEach into two sections. Keep the existing `Section("Albums")` for
  `state.albums.filter { $0.role == .owner }.map(\.album)` (or filter the tuple directly and map
  `.album` in the `ForEach`), and add a **new** `Section("Shared Albums")` for
  `state.albums.filter { $0.role != .owner }`, placed immediately **after** the existing
  `Section("Shared Libraries")` block (which ends around line 45) and **before** the renamed
  `Section("External Libraries")` block. Use `ForEach(..., id: \.album.id)` and
  `row(.album(entry.album.id), title: entry.album.name)` (same `row(_:title:)` helper already used
  for shared spaces/external libraries above it — see how `Section("Shared Libraries")` and
  `Section("External Libraries")` do it for the exact pattern).
  New Album button (`onNewAlbum`) stays in the plain "Albums" (owned) section only.

- **`native-apple/Apps/macOS/Sources/MacLibrarySheets.swift:207`**: `List(state.albums, id: \.id)`
  → `List(state.albums, id: \.album.id) { entry in ... }` and use `entry.album` wherever the closure
  currently references `album` (read the surrounding ~20 lines to see exactly what fields of
  `album` are used inside the closure and update each reference — likely `album.name`, `album.id`
  for a move/add-to-album picker; shared albums should still be selectable here, so do NOT filter
  by role in this sheet, just adapt to the new tuple shape).

- **`native-apple/Apps/macOS/Sources/MacStorageView.swift:38,50`**: `state.albums.isEmpty` still
  works unchanged (tuple array `.isEmpty` is fine). `ForEach(state.albums) { album in ... }` (line 50)
  needs `id:` now since tuples aren't `Identifiable` — change to
  `ForEach(state.albums, id: \.album.id) { entry in ... }` and update inner references from `album.x`
  to `entry.album.x` (read the closure body first to find every reference).

- **`native-apple/Apps/macOS/Sources/MacMainWindow.swift:302`** (`reloadKey`): `state.albums.count`
  is unaffected — tuple arrays still have `.count`. No change needed here.

## Verification
After all edits, run from `native-apple/`:
```
xcodebuild -project Heirloom.xcodeproj -scheme Heirloom-macOS -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" CODE_SIGN_ENTITLEMENTS="" DEVELOPMENT_TEAM="" \
  build
```
Must end in `** BUILD SUCCEEDED **`. Do not run/install the app — just confirm it compiles.
Report back which files were changed and confirm the build result; do not attempt any other
changes beyond what's listed above.
