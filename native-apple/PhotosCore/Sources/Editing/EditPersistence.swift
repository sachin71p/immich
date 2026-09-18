import CoreModel
import Foundation

/// The metadata-KV value stored under `EditRecipeKey.current`. `value` must be a JSON object
/// (`AssetMetadataUpsertItemSchema`); `renderedAssetId` links the rendered full-res upload
/// back to this recipe (decided contract 2).
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

/// A full-resolution client render ready to upload as a NEW asset. The original asset is
/// never modified; revert = delete the recipe key + clear upstream edits (+ optionally trash
/// the rendered asset through the normal asset-mutation path).
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

/// Persistence split (decided contract 1): upstream ops -> `/edits`, everything else ->
/// recipe KV + rendered upload. Plain REST on purpose: the generated OpenAPI client does not
/// include these operations in its filter, and this keeps Editing free of ImmichAPI/codegen
/// dependencies. No server changes required (decided contract 2).
public protocol EditPersistence: Sendable {
  func fetchRecipe(assetId: String) async throws -> EditPersistencePayload?
  func saveRecipe(_ payload: EditPersistencePayload) async throws
  func deleteRecipe(assetId: String) async throws
  func applyUpstreamEdits(assetId: String, items: [UpstreamEditItem]) async throws
  func clearUpstreamEdits(assetId: String) async throws
  /// Uploads the render as a NEW asset and returns its id. The recipe KV (with
  /// `renderedAssetId`) is saved separately via `saveRecipe` so callers control ordering.
  func uploadRendered(sourceAssetId: String, upload: RenderedUpload, recipe: EditRecipe) async throws -> String
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

  // MARK: - Recipe KV (`/assets/:id/metadata`)

  public func fetchRecipe(assetId: String) async throws -> EditPersistencePayload? {
    let key = EditRecipeKey.current.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? EditRecipeKey.current
    let (data, status) = try await get(path: "assets/\(assetId)/metadata/\(key)")
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
    struct Item: Encodable { var key: String; var value: EditPersistencePayload }
    struct Body: Encodable { var items: [Item] }
    let body = try JSONEncoder().encode(Body(items: [Item(key: EditRecipeKey.current, value: payload)]))
    let (data, status) = try await put(path: "assets/\(payload.sourceAssetId)/metadata", json: body)
    try Self.check(status: status, data: data)
  }

  public func deleteRecipe(assetId: String) async throws {
    let key = EditRecipeKey.current.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? EditRecipeKey.current
    let (data, status) = try await delete(path: "assets/\(assetId)/metadata/\(key)")
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

  // MARK: - Rendered upload (`POST /assets`)

  public func uploadRendered(
    sourceAssetId: String, upload: RenderedUpload, recipe: EditRecipe
  ) async throws -> String {
    // The recipe travels WITH the upload (`metadata` field) so the new asset is linked to
    // the source even if the follow-up `saveRecipe` never lands.
    let link = EditPersistencePayload(sourceAssetId: sourceAssetId, recipe: recipe)
    let linkData = try JSONEncoder().encode(link)
    let linkString = String(data: linkData, encoding: .utf8) ?? "{}"
    let metadataField = #"[{"key":"\#(EditRecipeKey.current)","value":\#(linkString)}]"#
    var fields: [(String, String)] = [
      ("deviceAssetId", "heirloom-edit-\(UUID().uuidString)"),
      ("deviceId", "heirloom"),
      ("fileCreatedAt", ISO8601DateFormatter().string(from: upload.fileCreatedAt)),
      ("fileModifiedAt", ISO8601DateFormatter().string(from: upload.fileModifiedAt)),
      ("filename", upload.filename),
      ("metadata", metadataField),
    ]
    if let spaceId = upload.spaceId { fields.append(("spaceId", spaceId)) }
    if let ms = upload.durationMs { fields.append(("duration", String(ms))) }
    let (body, boundary) = Self.multipartBody(
      fields: fields, fileField: "assetData", filename: upload.filename,
      contentType: upload.contentType, fileData: upload.data)
    var req = try await authorized("assets")
    req.httpMethod = "POST"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    let (data, status) = try await send(req, body: body)
    try Self.check(status: status, data: data)
    struct Created: Decodable { var id: String }
    do {
      return try JSONDecoder().decode(Created.self, from: data).id
    } catch {
      throw EditPersistenceError.decode(String(describing: error))
    }
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
