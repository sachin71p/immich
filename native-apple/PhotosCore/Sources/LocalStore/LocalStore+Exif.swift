import CoreModel
import Foundation
import GRDB

/// Viewer inspector EXIF (WP5 item 6): a presentation-ready projection of the `assetExif` row
/// (columns in `Schema.swift` `v1_assets_exif`). Read-only like the rest of `LocalStore+Browse`;
/// this file wraps the existing `exif(for:)` fetch so the inspector never touches SQL.
public struct ExifSummary: Sendable, Hashable {
  public var description: String?
  public var dateTimeOriginal: Date?
  public var width: Int?
  public var height: Int?
  public var fileSizeInByte: Int?
  public var orientation: String?
  public var latitude: Double?
  public var longitude: Double?
  public var city: String?
  public var state: String?
  public var country: String?
  public var make: String?
  public var model: String?
  public var lensModel: String?
  public var fNumber: Double?
  public var focalLength: Double?
  public var iso: Int?
  public var exposureTime: String?
  public var profileDescription: String?

  public init(
    description: String? = nil,
    dateTimeOriginal: Date? = nil,
    width: Int? = nil,
    height: Int? = nil,
    fileSizeInByte: Int? = nil,
    orientation: String? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil,
    city: String? = nil,
    state: String? = nil,
    country: String? = nil,
    make: String? = nil,
    model: String? = nil,
    lensModel: String? = nil,
    fNumber: Double? = nil,
    focalLength: Double? = nil,
    iso: Int? = nil,
    exposureTime: String? = nil,
    profileDescription: String? = nil
  ) {
    self.description = description
    self.dateTimeOriginal = dateTimeOriginal
    self.width = width
    self.height = height
    self.fileSizeInByte = fileSizeInByte
    self.orientation = orientation
    self.latitude = latitude
    self.longitude = longitude
    self.city = city
    self.state = state
    self.country = country
    self.make = make
    self.model = model
    self.lensModel = lensModel
    self.fNumber = fNumber
    self.focalLength = focalLength
    self.iso = iso
    self.exposureTime = exposureTime
    self.profileDescription = profileDescription
  }

  init(_ exif: AssetExif) {
    self.init(
      description: exif.description,
      dateTimeOriginal: exif.dateTimeOriginal,
      width: exif.exifImageWidth,
      height: exif.exifImageHeight,
      fileSizeInByte: exif.fileSizeInByte,
      orientation: exif.orientation,
      latitude: exif.latitude,
      longitude: exif.longitude,
      city: exif.city,
      state: exif.state,
      country: exif.country,
      make: exif.make,
      model: exif.model,
      lensModel: exif.lensModel,
      fNumber: exif.fNumber,
      focalLength: exif.focalLength,
      iso: exif.iso,
      exposureTime: exif.exposureTime,
      profileDescription: exif.profileDescription)
  }

  /// Megapixels from the EXIF pixel dimensions, when both are known.
  public var megapixels: Double? {
    guard let width, let height, width > 0, height > 0 else { return nil }
    return Double(width * height) / 1_000_000
  }

  /// True when the row carries a usable map pin.
  public var hasLocation: Bool { latitude != nil && longitude != nil }

  /// "San Jose, California" — parts that sync filled in, in Photos order.
  public var placeString: String? {
    let parts = [city, state, country].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }
}

extension PhotosLocalStore {
  /// EXIF summary for the viewer inspector (WP5 item 6). Returns nil when sync has not
  /// stored an `assetExif` row for the asset; never throws for a missing row.
  public func exifSummary(assetId: String) async throws -> ExifSummary? {
    guard let exif = try await exif(for: assetId) else { return nil }
    return ExifSummary(exif)
  }
}
