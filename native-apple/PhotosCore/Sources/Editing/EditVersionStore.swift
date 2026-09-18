import CoreModel
import Foundation

/// D6a version store: a per-asset PERSISTED stack of recipe versions, cap 10,
/// living BESIDE the single-slot recipe store (`EditRecipeKey.current`).
/// The single-slot store is untouched — this stack is a separate KV entry
/// (`EditVersionKey.current`) holding `EditVersionPayload`.
///
/// Semantics (WP-E D6/D6a):
/// - Each Done appends a new version; versions are never overwritten.
/// - Tap-to-restore appends the restored recipe as a NEW version.
/// - Cancel discards the in-progress edit (never touches the stack).
/// - Beyond cap 10 the oldest versions are pruned.
///
/// Forward-compat: every field decodes with `decodeIfPresent`, so old
/// persisted versions — including ones lacking D1–D4 keys (sibling
/// workstreams) — decode with identity defaults and render identically.
public enum EditVersionKey {
  public static let current = "fork.editVersions.v2"
  public static let legacy = "fork.editVersions.v1"
}

/// One persisted Done: the full recipe plus when it was saved.
public struct EditRecipeVersion: Sendable, Codable, Equatable {
  public var id: String
  public var savedAt: Date
  public var recipe: EditRecipe
  public var renderedAssetId: String?

  public init(
    id: String = UUID().uuidString,
    savedAt: Date = Date(),
    recipe: EditRecipe,
    renderedAssetId: String? = nil
  ) {
    self.id = id
    self.savedAt = savedAt
    self.recipe = recipe
    self.renderedAssetId = renderedAssetId
  }

  private enum CodingKeys: String, CodingKey {
    case id, savedAt, recipe, renderedAssetId
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let id: String = {
      guard let outer = (try? c.decodeIfPresent(String.self, forKey: .id)) else {
        return UUID().uuidString
      }
      return outer ?? UUID().uuidString
    }()
    let savedAt: Date = {
      guard let outer = (try? c.decodeIfPresent(Date.self, forKey: .savedAt)) else {
        return Date(timeIntervalSince1970: 0)
      }
      return outer ?? Date(timeIntervalSince1970: 0)
    }()
    // The recipe itself is required — but its SECTION keys all decode with
    // identity defaults (see AdjustRecipe), so old versions missing newer
    // keys still decode and render identically.
    let recipe = try c.decode(EditRecipe.self, forKey: .recipe)
    let renderedAssetId = (try? c.decodeIfPresent(String.self, forKey: .renderedAssetId)) ?? nil
    self.init(id: id, savedAt: savedAt, recipe: recipe, renderedAssetId: renderedAssetId)
  }
}

/// The per-asset version stack. Oldest version first; `append` prunes the
/// oldest beyond `maxVersions`. Value type: UIs hold it in `@State`.
public struct EditVersionStore: Sendable, Codable, Equatable {
  public static let maxVersions = 10

  /// Oldest first.
  public var versions: [EditRecipeVersion]

  public init(versions: [EditRecipeVersion] = []) {
    self.versions = Array(versions.suffix(Self.maxVersions))
  }

  public var count: Int { versions.count }
  public var isEmpty: Bool { versions.isEmpty }
  public var latest: EditRecipeVersion? { versions.last }

  /// Appends `recipe` as a new version; never overwrites. Prunes the oldest
  /// beyond the cap. Returns the stored version.
  @discardableResult
  public mutating func append(
    _ recipe: EditRecipe,
    renderedAssetId: String? = nil,
    savedAt: Date = Date(),
    id: String = UUID().uuidString
  ) -> EditRecipeVersion {
    let v = EditRecipeVersion(id: id, savedAt: savedAt, recipe: recipe, renderedAssetId: renderedAssetId)
    versions.append(v)
    if versions.count > Self.maxVersions {
      versions.removeFirst(versions.count - Self.maxVersions)
    }
    return v
  }

  /// Tap-to-restore: appends the version at `index` as a NEW version (never
  /// overwrites) and returns its recipe for the session to commit. Out of
  /// range returns nil and leaves the stack untouched.
  public mutating func restore(
    at index: Int, savedAt: Date = Date(), id: String = UUID().uuidString
  ) -> EditRecipe? {
    guard versions.indices.contains(index) else { return nil }
    let source = versions[index]
    append(source.recipe, renderedAssetId: source.renderedAssetId, savedAt: savedAt, id: id)
    return source.recipe
  }

  /// Same as `restore(at:)` by version id. Unknown id returns nil untouched.
  public mutating func restore(
    id: String, savedAt: Date = Date(), newId: String = UUID().uuidString
  ) -> EditRecipe? {
    guard let index = versions.firstIndex(where: { $0.id == id }) else { return nil }
    return restore(at: index, savedAt: savedAt, id: newId)
  }

  private enum CodingKeys: String, CodingKey {
    case versions
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // Missing key (pre-D6a payloads) decodes to an empty stack.
    let versions = (try? c.decodeIfPresent([EditRecipeVersion].self, forKey: .versions)) ?? nil
    self.init(versions: versions ?? [])
  }
}

/// The metadata-KV value stored under `EditVersionKey.current`. Mirrors
/// `EditPersistencePayload` so the stack rides the same `/metadata` path.
public struct EditVersionPayload: Sendable, Codable, Equatable {
  public var format: String
  public var sourceAssetId: String
  public var versions: [EditRecipeVersion]

  public init(sourceAssetId: String, versions: [EditRecipeVersion]) {
    self.format = EditVersionKey.current
    self.sourceAssetId = sourceAssetId
    self.versions = versions
  }

  private enum CodingKeys: String, CodingKey {
    case format, sourceAssetId, versions
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let format = ((try? c.decodeIfPresent(String.self, forKey: .format)) ?? nil) ?? EditVersionKey.current
    let sourceAssetId = try c.decode(String.self, forKey: .sourceAssetId)
    let versions = ((try? c.decodeIfPresent([EditRecipeVersion].self, forKey: .versions)) ?? nil) ?? []
    self.format = format
    self.sourceAssetId = sourceAssetId
    self.versions = versions
  }
}

extension RESTEditPersistence {
  // MARK: - Version stack KV (`/assets/:id/metadata`, beside the recipe key, v2 with v1 dual-read)

  public func fetchVersions(assetId: String) async throws -> EditVersionPayload? {
    if let payload = try await fetchVersions(assetId: assetId, key: EditVersionKey.current) {
      return payload
    }
    // E1 dual-read fallback: v1 versions decode with identity defaults (as today) and
    // normalize to the v2 format tag in memory; the next save persists v2 and deletes v1.
    guard var legacy = try await fetchVersions(assetId: assetId, key: EditVersionKey.legacy) else {
      return nil
    }
    legacy.format = EditVersionKey.current
    return legacy
  }

  private func fetchVersions(assetId: String, key: String) async throws -> EditVersionPayload? {
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
    let (data, status) = try await get(path: "assets/\(assetId)/metadata/\(encoded)")
    guard status != 404 else { return nil }
    try Self.check(status: status, data: data)
    struct Entry: Decodable { var value: EditVersionPayload }
    do {
      return try JSONDecoder().decode(Entry.self, from: data).value
    } catch {
      throw EditPersistenceError.decode(String(describing: error))
    }
  }

  public func saveVersions(_ payload: EditVersionPayload) async throws {
    var tagged = payload
    tagged.format = EditVersionKey.current
    struct Item: Encodable { var key: String; var value: EditVersionPayload }
    struct Body: Encodable { var items: [Item] }
    let body = try JSONEncoder().encode(Body(items: [Item(key: EditVersionKey.current, value: tagged)]))
    let (data, status) = try await put(path: "assets/\(tagged.sourceAssetId)/metadata", json: body)
    try Self.check(status: status, data: data)
    // Lazy migration hygiene, mirroring saveRecipe (best-effort; v2 is the source of truth).
    try? await deleteMetadataKey(assetId: tagged.sourceAssetId, key: EditVersionKey.legacy)
  }
}
