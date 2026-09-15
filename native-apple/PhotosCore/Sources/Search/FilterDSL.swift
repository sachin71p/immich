import CoreModel
import Foundation
import Rules

/// Library scope selector for search (A7 task 2, orchestrator-decided): personal / space /
/// library / all — mirrors the S7 server `spaceId`, `libraryId`, `personalOnly` filters.
public enum SearchScope: Sendable, Hashable, Codable {
  case all
  case personal
  case space(String)
  case library(String)

  /// Access-checked local scope: `all` keeps the caller's resolved timeline scope; anything
  /// else narrows through the explicit filter (unmembered containers resolve empty — §9).
  public func resolve(local base: ContainerScope, context: TimelineContext) -> ContainerScope {
    switch self {
    case .all: return base
    case .personal: return TimelineScope.resolve(purpose: .timeline, context: withFilter(.personalOnly, context))
    case .space(let id): return TimelineScope.resolve(purpose: .timeline, context: withFilter(.space(id), context))
    case .library(let id): return TimelineScope.resolve(purpose: .timeline, context: withFilter(.library(id), context))
    }
  }

  private func withFilter(_ filter: ExplicitContainerFilter, _ context: TimelineContext) -> TimelineContext {
    var ctx = context
    ctx.explicitFilter = filter
    return ctx
  }

  /// Fork scope fields for the S7 search DTOs (`spaceId` / `libraryId` / `personalOnly`).
  public func serverScopeParameters() -> (spaceId: String?, libraryId: String?, personalOnly: Bool) {
    switch self {
    case .all: return (nil, nil, false)
    case .personal: return (nil, nil, true)
    case .space(let id): return (id, nil, false)
    case .library(let id): return (nil, id, false)
    }
  }

  public var title: String {
    switch self {
    case .all: return "All"
    case .personal: return "Personal"
    case .space: return "Space"
    case .library: return "Library"
    }
  }
}

/// The shared filter DSL (A7 task 4): a CLIP smart query plus offline-capable metadata
/// predicates plus scope. Server-only dimensions (`tagIds`, OCR text) ride along for the
/// server mapping; local filtering uses `local` only.
public struct SearchFilter: Sendable, Hashable, Codable {
  public var query: String
  public var local: LocalAssetFilter
  public var scope: SearchScope
  public var tagIds: [String]

  public init(query: String = "", local: LocalAssetFilter = LocalAssetFilter(), scope: SearchScope = .all, tagIds: [String] = []) {
    self.query = query
    self.local = local
    self.scope = scope
    self.tagIds = tagIds
  }

  /// True when the filter carries anything a server round-trip could answer beyond the mirror.
  public var wantsServerSearch: Bool { !query.isEmpty || !tagIds.isEmpty }

  // MARK: - URL-like serialization (saved searches / smart albums later)

  nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  /// `q=…&scope=space:abc&make=…&isoMin=…` — stable key order, omits unset fields.
  public var serialized: String {
    var parts: [String] = []
    func add(_ key: String, _ value: String?) {
      guard let value, !value.isEmpty else { return }
      let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
      parts.append("\(key)=\(encoded)")
    }
    add("q", query.isEmpty ? nil : query)
    switch scope {
    case .all: break
    case .personal: parts.append("scope=personal")
    case .space(let id): add("scope", "space:\(id)")
    case .library(let id): add("scope", "library:\(id)")
    }
    let l = local
    add("make", l.make); add("model", l.model); add("lens", l.lensModel)
    add("city", l.city); add("state", l.state); add("country", l.country)
    add("projection", l.projectionType); add("orientation", l.orientation)
    if let v = l.isoMin { parts.append("isoMin=\(v)") }
    if let v = l.isoMax { parts.append("isoMax=\(v)") }
    if let v = l.fNumberMin { parts.append("fMin=\(v)") }
    if let v = l.fNumberMax { parts.append("fMax=\(v)") }
    if let v = l.focalLengthMin { parts.append("focalMin=\(v)") }
    if let v = l.focalLengthMax { parts.append("focalMax=\(v)") }
    if let v = l.exposureTimeMin { parts.append("expMin=\(v)") }
    if let v = l.exposureTimeMax { parts.append("expMax=\(v)") }
    if let v = l.fileSizeMin { parts.append("sizeMin=\(v)") }
    if let v = l.fileSizeMax { parts.append("sizeMax=\(v)") }
    if let v = l.widthMin { parts.append("wMin=\(v)") }
    if let v = l.heightMin { parts.append("hMin=\(v)") }
    if let v = l.fpsMin { parts.append("fpsMin=\(v)") }
    if let v = l.fpsMax { parts.append("fpsMax=\(v)") }
    if let v = l.rating { parts.append("rating=\(v)") }
    if let v = l.mediaType { parts.append("type=\(v.rawValue)") }
    if let v = l.isFavorite { parts.append("fav=\(v ? "1" : "0")") }
    if let v = l.hasLocation { parts.append("loc=\(v ? "1" : "0")") }
    if let v = l.takenAfter { add("after", Self.iso.string(from: v)) }
    if let v = l.takenBefore { add("before", Self.iso.string(from: v)) }
    if let exts = l.fileExtensions, !exts.isEmpty { add("ext", exts.joined(separator: ",")) }
    if let mimes = l.mimeTypes, !mimes.isEmpty { add("mime", mimes.joined(separator: ",")) }
    if let ids = l.personIds, !ids.isEmpty { add("people", ids.joined(separator: ",")) }
    if !tagIds.isEmpty { add("tags", tagIds.joined(separator: ",")) }
    return parts.joined(separator: "&")
  }

  public init?(serialized: String) {
    var query = ""
    var local = LocalAssetFilter()
    var scope = SearchScope.all
    var tagIds: [String] = []
    guard !serialized.isEmpty else { return nil }
    for pair in serialized.split(separator: "&") {
      let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
      guard kv.count == 2 else { continue }
      let key = kv[0]
      let value = kv[1].removingPercentEncoding ?? kv[1]
      switch key {
      case "q": query = value
      case "scope":
        if value == "personal" { scope = .personal }
        else if value.hasPrefix("space:") { scope = .space(String(value.dropFirst(6))) }
        else if value.hasPrefix("library:") { scope = .library(String(value.dropFirst(8))) }
      case "make": local.make = value
      case "model": local.model = value
      case "lens": local.lensModel = value
      case "city": local.city = value
      case "state": local.state = value
      case "country": local.country = value
      case "projection": local.projectionType = value
      case "orientation": local.orientation = value
      case "isoMin": local.isoMin = Int(value)
      case "isoMax": local.isoMax = Int(value)
      case "fMin": local.fNumberMin = Double(value)
      case "fMax": local.fNumberMax = Double(value)
      case "focalMin": local.focalLengthMin = Double(value)
      case "focalMax": local.focalLengthMax = Double(value)
      case "expMin": local.exposureTimeMin = Double(value)
      case "expMax": local.exposureTimeMax = Double(value)
      case "sizeMin": local.fileSizeMin = Int(value)
      case "sizeMax": local.fileSizeMax = Int(value)
      case "wMin": local.widthMin = Int(value)
      case "hMin": local.heightMin = Int(value)
      case "fpsMin": local.fpsMin = Double(value)
      case "fpsMax": local.fpsMax = Double(value)
      case "rating": local.rating = Int(value)
      case "type": local.mediaType = AssetKind(rawValue: value)
      case "fav": local.isFavorite = value == "1"
      case "loc": local.hasLocation = value == "1"
      case "after": local.takenAfter = Self.iso.date(from: value)
      case "before": local.takenBefore = Self.iso.date(from: value)
      case "ext": local.fileExtensions = value.split(separator: ",").map(String.init)
      case "mime": local.mimeTypes = value.split(separator: ",").map(String.init)
      case "people": local.personIds = value.split(separator: ",").map(String.init)
      case "tags": tagIds = value.split(separator: ",").map(String.init)
      default: continue
      }
    }
    self.init(query: query, local: local, scope: scope, tagIds: tagIds)
  }

  // MARK: - server param mapping (S7 DTOs)

  /// POST /search/metadata body — mirrors `MetadataSearchDto` plus the fork `spaceId` /
  /// `libraryId` / `personalOnly` scope fields and the S7 extended range filters.
  public func metadataBody(size: Int = 100) -> [String: Any] {
    let scopeParams = scope.serverScopeParameters()
    var body: [String: Any] = ["size": size, "withExif": true]
    if let v = scopeParams.spaceId { body["spaceId"] = v }
    if let v = scopeParams.libraryId { body["libraryId"] = v }
    if scopeParams.personalOnly { body["personalOnly"] = true }
    let l = local
    func set(_ key: String, _ value: Any?) { if let value { body[key] = value } }
    set("make", l.make); set("model", l.model); set("lensModel", l.lensModel)
    set("city", l.city); set("state", l.state); set("country", l.country)
    set("isoMin", l.isoMin); set("isoMax", l.isoMax)
    set("fNumberMin", l.fNumberMin); set("fNumberMax", l.fNumberMax)
    set("focalLengthMin", l.focalLengthMin); set("focalLengthMax", l.focalLengthMax)
    set("exposureTimeMin", l.exposureTimeMin); set("exposureTimeMax", l.exposureTimeMax)
    set("fileSizeMin", l.fileSizeMin); set("fileSizeMax", l.fileSizeMax)
    set("widthMin", l.widthMin); set("heightMin", l.heightMin)
    set("projectionType", l.projectionType); set("orientation", l.orientation)
    set("fpsMin", l.fpsMin); set("fpsMax", l.fpsMax)
    set("rating", l.rating)
    if let v = l.hasLocation { body["hasLocation"] = v }
    if let v = l.mediaType { body["type"] = v.rawValue }
    if let v = l.isFavorite { body["isFavorite"] = v }
    if let v = l.takenAfter { body["takenAfter"] = Self.iso.string(from: v) }
    if let v = l.takenBefore { body["takenBefore"] = Self.iso.string(from: v) }
    if let exts = l.fileExtensions, !exts.isEmpty {
      body["fileExtensions"] = exts
      body["originalFileName"] = exts.map { "*.\($0)" }.joined(separator: "|")
    }
    if let mimes = l.mimeTypes, !mimes.isEmpty { body["mimeTypes"] = mimes }
    if let ids = l.personIds, !ids.isEmpty { body["personIds"] = ids }
    if !tagIds.isEmpty { body["tagIds"] = tagIds }
    if !query.isEmpty { body["description"] = query }
    return body
  }

  /// POST /search/smart body — the CLIP query plus the dimensions SmartSearchDto shares
  /// with metadata search.
  public func smartBody(size: Int = 100) -> [String: Any] {
    let scopeParams = scope.serverScopeParameters()
    var body: [String: Any] = ["query": query, "size": size, "withExif": true]
    if let v = scopeParams.spaceId { body["spaceId"] = v }
    if let v = scopeParams.libraryId { body["libraryId"] = v }
    if scopeParams.personalOnly { body["personalOnly"] = true }
    let l = local
    func set(_ key: String, _ value: Any?) { if let value { body[key] = value } }
    set("make", l.make); set("model", l.model); set("lensModel", l.lensModel)
    set("city", l.city); set("state", l.state); set("country", l.country)
    set("rating", l.rating)
    if let v = l.mediaType { body["type"] = v.rawValue }
    if let v = l.isFavorite { body["isFavorite"] = v }
    if let v = l.takenAfter { body["takenAfter"] = Self.iso.string(from: v) }
    if let v = l.takenBefore { body["takenBefore"] = Self.iso.string(from: v) }
    if let ids = l.personIds, !ids.isEmpty { body["personIds"] = ids }
    if !tagIds.isEmpty { body["tagIds"] = tagIds }
    return body
  }
}

/// Suggestion chip kinds (A7 task 2: people, places, camera, lens, file type).
/// `serverType` is the `SearchSuggestionType` wire value passed to
/// `GET /search/suggestions` as-is; `nil` means the server has no such suggestion type and
/// the chip is served from the local mirror instead (people names — there is no server
/// people-suggestion variant, so this is a documented client-side fill, not a protocol change).
public enum SuggestionKind: Sendable, CaseIterable {
  case people
  case places
  case camera
  case lens
  case fileType

  public var serverType: String? {
    switch self {
    case .people: return nil
    case .places: return "city"
    case .camera: return "camera-make"
    case .lens: return "camera-lens-model"
    case .fileType: return "file-extension"
    }
  }

  public var title: String {
    switch self {
    case .people: return "People"
    case .places: return "Places"
    case .camera: return "Camera"
    case .lens: return "Lens"
    case .fileType: return "File type"
    }
  }

  public var systemImage: String {
    switch self {
    case .people: return "person.2"
    case .places: return "mappin"
    case .camera: return "camera"
    case .lens: return "circle.circle"
    case .fileType: return "doc"
    }
  }
}
