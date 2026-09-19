import CoreModel
import Foundation

/// The metadata-KV value stored under `EditRecipeKey.current`. `value` must be a JSON object
/// (`AssetMetadataUpsertItemSchema`); `renderedAssetId` is a pre-E1 leftover linking the
/// rendered full-res upload back to this recipe — E1 rendition saves leave it nil (the
/// rendition lives on the same asset, so no separate asset exists) while old payloads
/// carrying an id still decode.
public struct EditPersistencePayload: Sendable, Codable, Equatable {
  public var format: String
  public var sourceAssetId: String
  public var savedAt: Date
  public var recipe: EditRecipe
  public var renderedAssetId: String?

  public init(
    sourceAssetId: String, savedAt: Date = Date(), recipe: EditRecipe,
    renderedAssetId: String? = nil
  ) {
    self.format = EditRecipeKey.current
    self.sourceAssetId = sourceAssetId
    self.savedAt = savedAt
    self.recipe = recipe
    self.renderedAssetId = renderedAssetId
  }
}

/// A full-resolution client render ready to PUT as the asset's rendition. The original
/// bytes are never modified; revert = delete the rendition + delete the recipe key +
/// clear upstream edits.
public struct RenderedUpload: Sendable {
  public var data: Data
  public var filename: String
  public var contentType: String
  public var fileCreatedAt: Date
  public var fileModifiedAt: Date
  /// Space upload target, carried over from the source asset (fork `spaceId` upload field).
  public var spaceId: String?
  /// Duration in milliseconds (video/live-photo motion uploads).
  public var durationMs: Int?

  public init(
    data: Data, filename: String, contentType: String, fileCreatedAt: Date,
    fileModifiedAt: Date, spaceId: String? = nil, durationMs: Int? = nil
  ) {
    self.data = data
    self.filename = filename
    self.contentType = contentType
    self.fileCreatedAt = fileCreatedAt
    self.fileModifiedAt = fileModifiedAt
    self.spaceId = spaceId
    self.durationMs = durationMs
  }

  /// `IMG_1234.heic` -> `IMG_1234-edited.jpg` (markup flattens to source format; JPEG fallback).
  public static func editedFilename(for originalFileName: String, fileExtension ext: String) -> String {
    let base = (originalFileName as NSString).deletingPathExtension
    return "\(base.isEmpty ? "edited" : base)-edited.\(ext)"
  }
}

public enum EditPersistenceError: Error, Sendable, Equatable {
  case notAuthenticated
  case http(status: Int, body: String)
  case decode(String)
  case network(String)
}

/// Persistence split: upstream ops -> `/edits`, everything else -> recipe KV (v2) +
/// rendition PUT on the same asset. Plain REST on purpose: the generated OpenAPI client
/// does not include these operations in its filter, and this keeps Editing free of
/// ImmichAPI/codegen dependencies.
public protocol EditPersistence: Sendable {
  /// Dual-read: tries the v2 recipe key first, falls back to the v1 key (normalized to
  /// the v2 format tag in memory); nil when neither exists.
  func fetchRecipe(assetId: String) async throws -> EditPersistencePayload?
  /// Writes the v2 recipe key only, then best-effort deletes the v1 key (lazy migration).
  func saveRecipe(_ payload: EditPersistencePayload) async throws
  func deleteRecipe(assetId: String) async throws
  func applyUpstreamEdits(assetId: String, items: [UpstreamEditItem]) async throws
  func clearUpstreamEdits(assetId: String) async throws
  /// PUTs the render as the asset's rendition (`PUT /assets/:id/rendition`, multipart
  /// `assetData` file part like the asset upload path). No separate asset is ever created:
  /// the timeline keeps showing one item, thumbs derive from the rendition, and upstream
  /// `asset_edit` applies on top of the rendition at serve time. The recipe KV is saved
  /// separately via `saveRecipe` so callers control ordering.
  func uploadRendition(assetId: String, upload: RenderedUpload) async throws
}

public struct RESTEditPersistence: EditPersistence, Sendable {
  public var serverURL: URL
  public var token: @Sendable () async -> String?
  public var session: URLSession

  public init(
    serverURL: URL, token: @Sendable @escaping () async -> String?,
    session: URLSession = .shared
  ) {
    self.serverURL = serverURL
    self.token = token
    self.session = session
  }

  // MARK: - Recipe KV (`/assets/:id/metadata`, v2 with v1 dual-read)

  public func fetchRecipe(assetId: String) async throws -> EditPersistencePayload? {
    if let payload = try await fetchRecipe(assetId: assetId, key: EditRecipeKey.current) {
      return payload
    }
    // E1 dual-read fallback: a v1 entry decodes with identity defaults for missing keys
    // (as today) and normalizes to the v2 format tag in memory; the next save persists
    // v2 and deletes v1.
    guard var legacy = try await fetchRecipe(assetId: assetId, key: EditRecipeKey.legacy) else {
      return nil
    }
    legacy.format = EditRecipeKey.current
    return legacy
  }

  private func fetchRecipe(assetId: String, key: String) async throws -> EditPersistencePayload? {
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
    let (data, status) = try await get(path: "assets/\(assetId)/metadata/\(encoded)")
    guard status != 404 else { return nil }
    try Self.check(status: status, data: data)
    struct Entry: Decodable { var value: EditPersistencePayload }
    do {
      return try JSONDecoder().decode(Entry.self, from: data).value
    } catch {
      throw EditPersistenceError.decode(String(describing: error))
    }
  }

  public func saveRecipe(_ payload: EditPersistencePayload) async throws {
    var tagged = payload
    tagged.format = EditRecipeKey.current
    struct Item: Encodable { var key: String; var value: EditPersistencePayload }
    struct Body: Encodable { var items: [Item] }
    let body = try JSONEncoder().encode(Body(items: [Item(key: EditRecipeKey.current, value: tagged)]))
    let (data, status) = try await put(path: "assets/\(tagged.sourceAssetId)/metadata", json: body)
    try Self.check(status: status, data: data)
    // Lazy migration hygiene: the v2 write is the source of truth, so dropping the
    // stale v1 key is best-effort (a lingering v1 is harmless — reads prefer v2).
    try? await deleteMetadataKey(assetId: tagged.sourceAssetId, key: EditRecipeKey.legacy)
  }

  public func deleteRecipe(assetId: String) async throws {
    try await deleteMetadataKey(assetId: assetId, key: EditRecipeKey.current)
    try? await deleteMetadataKey(assetId: assetId, key: EditRecipeKey.legacy)
  }

  /// Deletes one metadata-KV entry, tolerating absence. Shared by the recipe and
  /// version-stack paths (both migrate v1 -> v2 lazily).
  func deleteMetadataKey(assetId: String, key: String) async throws {
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
    let (data, status) = try await delete(path: "assets/\(assetId)/metadata/\(encoded)")
    if status == 404 { return }
    try Self.check(status: status, data: data)
  }

  // MARK: - Upstream edits (`/assets/:id/edits`)

  public func applyUpstreamEdits(assetId: String, items: [UpstreamEditItem]) async throws {
    guard !items.isEmpty else { return }
    let body = try EditSplitter.editsBody(items)
    let (data, status) = try await put(path: "assets/\(assetId)/edits", json: body)
    try Self.check(status: status, data: data)
  }

  public func clearUpstreamEdits(assetId: String) async throws {
    let (data, status) = try await delete(path: "assets/\(assetId)/edits")
    if status == 404 { return }
    try Self.check(status: status, data: data)
  }

  // MARK: - Rendition (`PUT /assets/:id/rendition`)

  public func uploadRendition(assetId: String, upload: RenderedUpload) async throws {
    // Multipart file field mirrors the asset upload path (`assetData`); the server
    // stores the bytes as the asset's `edited` file and answers the asset DTO.
    let (body, boundary) = Self.renditionBody(upload: upload)
    var req = try await authorized("assets/\(assetId)/rendition")
    req.httpMethod = "PUT"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    let (data, status) = try await send(req, body: body)
    try Self.check(status: status, data: data)
  }

  /// Builds the rendition multipart body. Public + deterministic for tests (fixed
  /// boundary when supplied): the `assetData` file part carries the render, as on the
  /// asset upload path.
  public static func renditionBody(
    upload: RenderedUpload, boundary: String = "heirloom-\(UUID().uuidString)"
  ) -> (Data, String) {
    multipartBody(
      fields: [("filename", upload.filename)],
      fileField: "assetData", filename: upload.filename,
      contentType: upload.contentType, fileData: upload.data, boundary: boundary)
  }

  // MARK: - HTTP plumbing (pure, unit-testable body builders below)

  private func authorized(_ path: String) async throws -> URLRequest {
    guard let tok = await token(), !tok.isEmpty else { throw EditPersistenceError.notAuthenticated }
    var req = URLRequest(url: serverURL.appendingPathComponent(path))
    req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    return req
  }

  func get(path: String) async throws -> (Data, Int) {
    var req = try await authorized(path)
    req.httpMethod = "GET"
    return try await send(req, body: nil)
  }

  func put(path: String, json: Data) async throws -> (Data, Int) {
    var req = try await authorized(path)
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return try await send(req, body: json)
  }

  private func delete(path: String) async throws -> (Data, Int) {
    var req = try await authorized(path)
    req.httpMethod = "DELETE"
    return try await send(req, body: nil)
  }

  private func send(_ req: URLRequest, body: Data?) async throws -> (Data, Int) {
    do {
      if let body {
        let (data, resp) = try await session.upload(for: req, from: body)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? -1)
      } else {
        let (data, resp) = try await session.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? -1)
      }
    } catch {
      throw EditPersistenceError.network(String(describing: error))
    }
  }

  static func check(status: Int, data: Data) throws {
    guard (200..<300).contains(status) else {
      throw EditPersistenceError.http(
        status: status, body: String(data: data, encoding: .utf8) ?? "<binary>")
    }
  }

  /// Builds a multipart/form-data body. Public + deterministic for tests (fixed boundary
  /// when supplied).
  public static func multipartBody(
    fields: [(String, String)], fileField: String, filename: String, contentType: String,
    fileData: Data, boundary: String = "heirloom-\(UUID().uuidString)"
  ) -> (Data, String) {
    var body = Data()
    func append(_ s: String) { body.append(Data(s.utf8)) }
    for (name, value) in fields {
      append("--\(boundary)\r\n")
      append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      append("\(value)\r\n")
    }
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
    append("Content-Type: \(contentType)\r\n\r\n")
    body.append(fileData)
    append("\r\n--\(boundary)--\r\n")
    return (body, boundary)
  }
}
