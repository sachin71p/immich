import Foundation

/// Offline-capable asset filter over the LocalStore `asset` + `assetExif` mirror (A7 task 3).
/// Lives in CoreModel so both `LocalStore` (executes it as SQL) and `Search` (owns the DSL
/// and server mapping) can use it without a dependency cycle. Every field is optional; set
/// fields AND together. Server-only dimensions (CLIP smart query, OCR, tags) live on
/// `SearchFilter` in the Search module, not here.
public struct LocalAssetFilter: Sendable, Hashable, Codable {
  public var make: String?
  public var model: String?
  public var lensModel: String?
  public var city: String?
  public var state: String?
  public var country: String?
  public var isoMin: Int?
  public var isoMax: Int?
  public var fNumberMin: Double?
  public var fNumberMax: Double?
  public var focalLengthMin: Double?
  public var focalLengthMax: Double?
  public var exposureTimeMin: Double?
  public var exposureTimeMax: Double?
  public var fileSizeMin: Int?
  public var fileSizeMax: Int?
  public var widthMin: Int?
  public var heightMin: Int?
  public var fileExtensions: [String]?
  public var mimeTypes: [String]?
  public var projectionType: String?
  public var hasLocation: Bool?
  public var orientation: String?
  public var fpsMin: Double?
  public var fpsMax: Double?
  public var rating: Int?
  public var mediaType: AssetKind?
  public var isFavorite: Bool?
  public var takenAfter: Date?
  public var takenBefore: Date?
  public var personIds: [String]?

  public init(
    make: String? = nil,
    model: String? = nil,
    lensModel: String? = nil,
    city: String? = nil,
    state: String? = nil,
    country: String? = nil,
    isoMin: Int? = nil,
    isoMax: Int? = nil,
    fNumberMin: Double? = nil,
    fNumberMax: Double? = nil,
    focalLengthMin: Double? = nil,
    focalLengthMax: Double? = nil,
    exposureTimeMin: Double? = nil,
    exposureTimeMax: Double? = nil,
    fileSizeMin: Int? = nil,
    fileSizeMax: Int? = nil,
    widthMin: Int? = nil,
    heightMin: Int? = nil,
    fileExtensions: [String]? = nil,
    mimeTypes: [String]? = nil,
    projectionType: String? = nil,
    hasLocation: Bool? = nil,
    orientation: String? = nil,
    fpsMin: Double? = nil,
    fpsMax: Double? = nil,
    rating: Int? = nil,
    mediaType: AssetKind? = nil,
    isFavorite: Bool? = nil,
    takenAfter: Date? = nil,
    takenBefore: Date? = nil,
    personIds: [String]? = nil
  ) {
    self.make = make
    self.model = model
    self.lensModel = lensModel
    self.city = city
    self.state = state
    self.country = country
    self.isoMin = isoMin
    self.isoMax = isoMax
    self.fNumberMin = fNumberMin
    self.fNumberMax = fNumberMax
    self.focalLengthMin = focalLengthMin
    self.focalLengthMax = focalLengthMax
    self.exposureTimeMin = exposureTimeMin
    self.exposureTimeMax = exposureTimeMax
    self.fileSizeMin = fileSizeMin
    self.fileSizeMax = fileSizeMax
    self.widthMin = widthMin
    self.heightMin = heightMin
    self.fileExtensions = fileExtensions
    self.mimeTypes = mimeTypes
    self.projectionType = projectionType
    self.hasLocation = hasLocation
    self.orientation = orientation
    self.fpsMin = fpsMin
    self.fpsMax = fpsMax
    self.rating = rating
    self.mediaType = mediaType
    self.isFavorite = isFavorite
    self.takenAfter = takenAfter
    self.takenBefore = takenBefore
    self.personIds = personIds
  }

  /// True when no predicate is set — callers can skip the filtered query path.
  public var isEmpty: Bool { self == LocalAssetFilter() }

  /// Exposure times are stored as text (`"1/125"`, `"0.004"`); the local query converts
  /// fractions to seconds with a SQL expression, so the DSL parses here for the server mapping.
  public static func seconds(from exposureTime: String) -> Double? {
    let trimmed = exposureTime.trimmingCharacters(in: .whitespaces)
    if trimmed.contains("/") {
      let parts = trimmed.split(separator: "/").map { Double($0.trimmingCharacters(in: .whitespaces)) }
      guard parts.count == 2, let num = parts[0], let den = parts[1], den != 0 else { return nil }
      return num / den
    }
    return Double(trimmed)
  }
}
