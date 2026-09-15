import CoreModel
import ImmichAPI
import LocalStore

/// Brief task 5: album CRUD + add/remove — DECISIONS §4 "every album member of any role may add and
/// remove any asset in the album" (no role check needed on the client side beyond membership, which the
/// caller already has since it's showing the album).
public struct AlbumMutations: Sendable {
  let connection: ImmichConnection
  let localStore: PhotosLocalStore

  public init(connection: ImmichConnection, localStore: PhotosLocalStore) {
    self.connection = connection
    self.localStore = localStore
  }

  /// Server assigns the album id, so the "optimistic" local write here is really just applying the
  /// server's response immediately instead of waiting for the next sync tick to pick up the `AlbumV2` row.
  @discardableResult
  public func createAlbum(name: String, description: String? = nil, assetIds: [String] = []) async throws -> Album {
    let input = Operations.createAlbum.Input(body: .json(.init(albumName: name, assetIds: assetIds, description: description)))
    let output = try await connection.client.createAlbum(input)
    guard case let .created(response) = output, case let .json(body) = response.body else {
      throw AssetMutationError.unexpectedResponse
    }
    let album = Album(
      id: body.id, name: body.albumName, description: body.description, createdAt: body.createdAt,
      updatedAt: body.updatedAt, thumbnailAssetId: body.albumThumbnailAssetId,
      isActivityEnabled: body.isActivityEnabled, order: body.order?.rawValue ?? "desc"
    )
    try await localStore.upsertAlbumLocally(album)
    try await localStore.addAssets(assetIds, toAlbum: album.id)
    return album
  }

  public func deleteAlbum(id: String) async throws {
    let input = Operations.deleteAlbum.Input(path: .init(id: id))
    _ = try await connection.client.deleteAlbum(input)
    try await localStore.deleteAlbumLocally(id: id)
  }

  /// Renames the album (`PATCH /albums/{id}`) — album-level setting, gated by role in the app
  /// layer (DECISIONS §4).
  public func renameAlbum(id: String, name: String) async throws {
    let input = Operations.updateAlbumInfo.Input(
      path: .init(id: id), body: .json(.init(albumName: name)))
    _ = try await connection.client.updateAlbumInfo(input)
    if var album = try await localStore.album(id: id) {
      album.name = name
      try await localStore.upsertAlbumLocally(album)
    }
  }

  @discardableResult
  public func addAssets(_ assetIds: [String], toAlbum albumId: String) async throws -> Bool {
    let input = Operations.addAssetsToAlbum.Input(path: .init(id: albumId), body: .json(.init(ids: assetIds)))
    _ = try await connection.client.addAssetsToAlbum(input)
    try await localStore.addAssets(assetIds, toAlbum: albumId)
    return true
  }

  @discardableResult
  public func removeAssets(_ assetIds: [String], fromAlbum albumId: String) async throws -> Bool {
    let input = Operations.removeAssetFromAlbum.Input(path: .init(id: albumId), body: .json(.init(ids: assetIds)))
    _ = try await connection.client.removeAssetFromAlbum(input)
    try await localStore.removeAssets(assetIds, fromAlbum: albumId)
    return true
  }

  /// Shares the album with users — `PUT /albums/{id}/users` (brief task 7 "share with users").
  /// New members join as viewers (DECISIONS §4: any member may add/remove assets; role only gates
  /// album-level settings).
  public func shareWithUsers(_ userIds: [String], albumId: String) async throws {
    let input = Operations.addUsersToAlbum.Input(
      path: .init(id: albumId),
      body: .json(.init(albumUsers: userIds.map { .init(role: .viewer, userId: $0) })))
    _ = try await connection.client.addUsersToAlbum(input)
    for userId in userIds {
      try await localStore.upsertAlbumMember(AlbumMember(albumId: albumId, userId: userId, role: .viewer))
    }
  }

  public func removeUser(_ userId: String, fromAlbum albumId: String) async throws {
    let input = Operations.removeUserFromAlbum.Input(path: .init(id: albumId, userId: userId))
    _ = try await connection.client.removeUserFromAlbum(input)
    try await localStore.removeAlbumMemberLocally(albumId: albumId, userId: userId)
  }
}
