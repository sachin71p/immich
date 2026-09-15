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
}
