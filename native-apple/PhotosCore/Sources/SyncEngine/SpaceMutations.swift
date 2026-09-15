import CoreModel
import ImmichAPI
import LocalStore

/// Brief task 5: "space CRUD + members" — DECISIONS §4 (owner and contributor both get full space-
/// management rights except delete/leave/transfer, gated in the app layer via `Rules.Permissions` before
/// these are even offered).
public struct SpaceMutations: Sendable {
  let connection: ImmichConnection
  let localStore: PhotosLocalStore

  public init(connection: ImmichConnection, localStore: PhotosLocalStore) {
    self.connection = connection
    self.localStore = localStore
  }

  @discardableResult
  public func createSpace(name: String, description: String? = nil) async throws -> Space {
    let input = Operations.create.Input(body: .json(.init(description: description, name: name)))
    let output = try await connection.client.create(input)
    guard case let .created(response) = output, case let .json(body) = response.body else {
      throw AssetMutationError.unexpectedResponse
    }
    let space = Space(id: body.id, name: body.name, description: body.description, createdAt: body.createdAt, updatedAt: body.updatedAt)
    try await localStore.upsertSpace(space)
    return space
  }

  public func updateSpace(id: String, name: String? = nil, description: String? = nil) async throws {
    let input = Operations.update.Input(path: .init(id: id), body: .json(.init(description: description, name: name)))
    let output = try await connection.client.update(input)
    guard case let .ok(response) = output, case let .json(body) = response.body else {
      throw AssetMutationError.unexpectedResponse
    }
    let space = Space(id: body.id, name: body.name, description: body.description, createdAt: body.createdAt, updatedAt: body.updatedAt)
    try await localStore.upsertSpace(space)
  }

  /// Owner-only server-side (DECISIONS §4); relocates the space's assets back to personal.
  public func deleteSpace(id: String) async throws {
    let input = Operations.delete.Input(path: .init(id: id))
    _ = try await connection.client.delete(input)
    try await localStore.deleteSpaceLocally(id: id)
  }

  public func addMembers(userIds: [String], toSpace spaceId: String) async throws {
    let input = Operations.addMembers.Input(path: .init(id: spaceId), body: .json(.init(userIds: userIds)))
    _ = try await connection.client.addMembers(input)
    // Role/showInTimeline default server-side; the next sync tick fills in the authoritative row. An
    // optimistic contributor placeholder keeps the member list responsive in the meantime.
    for userId in userIds {
      try await localStore.upsertSpaceMember(
        SpaceMember(spaceId: spaceId, userId: userId, role: .contributor, showInTimeline: true)
      )
    }
  }

  public func removeMember(userId: String, fromSpace spaceId: String) async throws {
    let input = Operations.removeMember.Input(path: .init(id: spaceId, userId: userId))
    _ = try await connection.client.removeMember(input)
    try await localStore.removeSpaceMemberLocally(spaceId: spaceId, userId: userId)
  }
}
