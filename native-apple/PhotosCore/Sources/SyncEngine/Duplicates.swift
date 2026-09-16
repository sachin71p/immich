import Foundation
import ImmichAPI

/// Server-authored duplicate groups. Immich calculates these across all libraries the caller is
/// permitted to read, so clients must not re-scope or reimplement the detection locally.
public struct DuplicateGroup: Sendable, Hashable, Identifiable {
  public var id: String
  public var assetIds: [String]
  public var suggestedKeepAssetIds: Set<String>

  public init(id: String, assetIds: [String], suggestedKeepAssetIds: Set<String>) {
    self.id = id
    self.assetIds = assetIds
    self.suggestedKeepAssetIds = suggestedKeepAssetIds
  }
}

public struct DuplicateService: Sendable {
  private let connection: ImmichConnection

  public init(connection: ImmichConnection) {
    self.connection = connection
  }

  public func groups() async throws -> [DuplicateGroup] {
    let output = try await connection.client.getAssetDuplicates(.init())
    guard case let .ok(response) = output, case let .json(groups) = response.body else {
      throw AssetMutationError.unexpectedResponse
    }
    return groups.map {
      DuplicateGroup(
        id: $0.duplicateId, assetIds: $0.assets.map(\.id),
        suggestedKeepAssetIds: Set($0.suggestedKeepAssetIds))
    }
  }
}
