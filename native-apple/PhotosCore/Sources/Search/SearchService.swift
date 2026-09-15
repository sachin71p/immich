import CoreModel
import Foundation

/// One exiftool value in the `GET /assets/:id/exif/full` groups payload (S7 task 1). Binary
/// blobs arrive stripped as `{ binary: true, bytes }` — the `.binary` case surfaces that so the UI
/// shows a size instead of garbage.
public enum FullExifValue: Sendable, Hashable, Codable {
  case string(String)
  case number(Double)
  case boolean(Bool)
  case binary(bytes: Int?)
  case unknown

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let v = try? container.decode(String.self) { self = .string(v); return }
    if let v = try? container.decode(Double.self) { self = .number(v); return }
    if let v = try? container.decode(Bool.self) { self = .boolean(v); return }
    if let dict = try? container.decode([String: Int].self), dict["binary"] == 1 || dict["binary"] != nil {
      self = .binary(bytes: dict["bytes"])
      return
    }
    self = .unknown
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let v): try container.encode(v)
    case .number(let v): try container.encode(v)
    case .boolean(let v): try container.encode(v)
    case .binary: try container.encode(["binary": 1])
    case .unknown: try container.encodeNil()
    }
  }

  /// Display text for the metadata browser; nil when there is nothing worth showing.
  public var displayText: String? {
    switch self {
    case .string(let v): return v.isEmpty ? nil : v
    case .number(let v): return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    case .boolean(let v): return v ? "Yes" : "No"
    case .binary(let bytes):
      guard let bytes else { return "Binary data" }
      return "Binary data (\(bytes) bytes)"
    case .unknown: return nil
    }
  }
}

/// `{ groups: Record<group, Record<tag, unknown>> }` from `GET /assets/:id/exif/full` (S7).
public struct FullExif: Sendable, Hashable, Codable {
  public var groups: [String: [String: FullExifValue]]

  public init(groups: [String: [String: FullExifValue]] = [:]) {
    self.groups = groups
  }

  public var groupNames: [String] { groups.keys.sorted() }

  public func entries(in group: String) -> [(key: String, value: FullExifValue)] {
    (groups[group] ?? [:]).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
  }

  /// Case-insensitive tag/value search across all groups for the browser's search field.
  public func matching(_ text: String) -> [(group: String, key: String, value: FullExifValue)] {
    guard !text.isEmpty else { return [] }
    let needle = text.lowercased()
    var out: [(group: String, key: String, value: FullExifValue)] = []
    for group in groupNames {
      for (key, value) in entries(in: group) {
        let hay = "\(group) \(key) \(value.displayText ?? "")".lowercased()
        if hay.contains(needle) { out.append((group, key, value)) }
      }
    }
    return out
  }
}

/// Per-asset in-memory cache for the full-exif payload (A7 task 1: "cached per asset").
/// Negative results (offline external asset → 404) are NOT cached — reachability can change.
public actor FullExifCache {
  private var entries: [String: FullExif] = [:]

  public init() {}

  public func cached(assetId: String) -> FullExif? { entries[assetId] }

  public func store(_ exif: FullExif, assetId: String) { entries[assetId] = exif }

  public func evict(assetId: String) { entries.removeValue(forKey: assetId) }

  public func evictAll() { entries.removeAll() }
}

public enum SearchServiceError: Error, Sendable {
  case missingToken
  case badStatus(Int)
  case undecodableResponse
}

/// Server search + full-exif client (A7 tasks 1–2). Hand-written URLSession calls with the
/// Bearer [REDACTED] (same pattern as `MediaServer` + the viewer share path) rather than the
/// generated OpenAPI client: the S7 operations (`getAssetFullExif`, fork scope fields) postdate
/// the last committed OpenAPI snapshot, so generated types may not exist yet on the host that
/// runs codegen. Bodies mirror `MetadataSearchDto` / `SmartSearchDto` via
/// `SearchFilter.metadataBody` / `smartBody` (pure, unit-tested param mapping).
public struct SearchService: Sendable {
  public var baseURL: URL
  public var tokenProvider: @Sendable () async -> String?
  public var session: URLSession
  public var fullExifCache: FullExifCache

  public init(
    baseURL: URL,
    tokenProvider: @Sendable @escaping () async -> String? = { nil },
    session: URLSession = .shared,
    fullExifCache: FullExifCache = FullExifCache()
  ) {
    self.baseURL = baseURL
    self.tokenProvider = tokenProvider
    self.session = session
    self.fullExifCache = fullExifCache
  }

  // MARK: - full exif (A7 task 1)

  /// Grouped exiftool dump, cached per asset. Throws on 404 (offline external asset) so the
  /// info panel can show "unavailable" instead of stale data.
  public func fullExif(assetId: String) async throws -> FullExif {
    if let cached = await fullExifCache.cached(assetId: assetId) { return cached }
    let data = try await get(path: "assets/\(assetId)/exif/full")
    let decoded = (try? JSONDecoder().decode(FullExifResponse.self, from: data)) ?? FullExifResponse(groups: [:])
    let exif = FullExif(groups: decoded.groups)
    await fullExifCache.store(exif, assetId: assetId)
    return exif
  }

  private struct FullExifResponse: Decodable {
    var groups: [String: [String: FullExifValue]]
  }

  // MARK: - search (A7 task 2)

  /// Asset ids for `filter`: CLIP smart search when a text query is present, metadata search
  /// otherwise. Callers hydrate rows from the local mirror (`store.assets(ids:)`).
  public func searchIds(filter: SearchFilter, size: Int = 100) async throws -> [String] {
    let (path, body): (String, [String: Any]) =
      filter.query.isEmpty
        ? ("search/metadata", filter.metadataBody(size: size))
        : ("search/smart", filter.smartBody(size: size))
    let data = try await post(path: path, json: body)
    guard let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
      throw SearchServiceError.undecodableResponse
    }
    return decoded.assets.items.map(\.id)
  }

  private struct SearchResponse: Decodable {
    struct Assets: Decodable {
      struct Item: Decodable { var id: String }
      var items: [Item]
    }
    var assets: Assets
  }

  // MARK: - suggestions (A7 task 2, endpoint used as-is)

  /// `GET /search/suggestions?type=<SearchSuggestionType>` with the fork scope params. The
  /// server may return null entries (known upstream TODO) — those are dropped.
  public func suggestions(kind: SuggestionKind, scope: SearchScope, extra: [String: String] = [:]) async throws -> [String] {
    guard let type = kind.serverType else { return [] }
    var items: [URLQueryItem] = [URLQueryItem(name: "type", value: type)]
    let scopeParams = scope.serverScopeParameters()
    if let v = scopeParams.spaceId { items.append(URLQueryItem(name: "spaceId", value: v)) }
    if let v = scopeParams.libraryId { items.append(URLQueryItem(name: "libraryId", value: v)) }
    if scopeParams.personalOnly { items.append(URLQueryItem(name: "personalOnly", value: "true")) }
    for (key, value) in extra { items.append(URLQueryItem(name: key, value: value)) }
    let data = try await get(path: "search/suggestions", query: items)
    return ((try? JSONDecoder().decode([String?].self, from: data)) ?? []).compactMap { $0 }.filter { !$0.isEmpty }
  }

  // MARK: - transport

  private func authorized(path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
    guard let token = await tokenProvider(), !token.isEmpty else { throw SearchServiceError.missingToken }
    var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    if !query.isEmpty { components.queryItems = query }
    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }

  private func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
    let request = try await authorized(path: path, query: query)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw SearchServiceError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return data
  }

  private func post(path: String, json: [String: Any]) async throws -> Data {
    var request = try await authorized(path: path)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: json)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw SearchServiceError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return data
  }
}
