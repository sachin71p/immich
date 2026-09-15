import CoreModel
import ImmichAPI
import LocalStore

/// Brief task 5: "prefs" — DECISIONS §9. `PUT /users/me/preferences` only exposes the `sharedLibraries`
/// slice we own here; other preference groups are left untouched (`nil` fields are omitted server-side).
public struct PrefsMutations: Sendable {
  let connection: ImmichConnection
  let localStore: PhotosLocalStore

  public init(connection: ImmichConnection, localStore: PhotosLocalStore) {
    self.connection = connection
    self.localStore = localStore
  }

  public func update(_ prefs: SharedLibraryPrefs, for userId: String) async throws {
    let target: Components.Schemas.SharedLibrariesUpdate.defaultUploadTargetPayload
    switch prefs.defaultUploadTarget {
    case .personal:
      target = .case1(.init(_type: .personal))
    case .space(let spaceId):
      target = .case2(.init(_type: .space, spaceId: spaceId))
    }
    let sharedLibraries = Components.Schemas.SharedLibrariesUpdate(
      defaultUploadTarget: target,
      hiddenOwnedLibraryIds: prefs.hiddenOwnedLibraryIds,
      showPersonalInTimeline: prefs.showPersonalInTimeline
    )
    let input = Operations.updateMyPreferences.Input(body: .json(.init(sharedLibraries: sharedLibraries)))
    _ = try await connection.client.updateMyPreferences(input)
    try await localStore.setPrefs(prefs, for: userId)
  }
}
