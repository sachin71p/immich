import Foundation

/// Format classification for an asset's original file — brief task 5 (HEIC/RAW/ProRAW/HDR).
/// The server exposes no ProRAW flag, so every DNG is treated as a RAW original; viewers must
/// always render these kinds from original bytes, never from a transcoded rendition.
public struct MediaFormatInfo: Sendable, Hashable {
  public enum Kind: String, Sendable, Hashable, CaseIterable {
    case jpeg
    case png
    case webp
    case gif
    case heic
    case raw
    case video
    case other
  }

  /// The dynamic-range flag viewers bind to the platform HDR rendering path.
  public enum DynamicRange: String, Sendable, Hashable {
    case sdr
    case hdr
  }

  public var kind: Kind
  public var dynamicRange: DynamicRange
  /// RAW/HEIC/video must be viewed from original bytes; renditions are display-only.
  public var shouldViewOriginal: Bool

  public init(kind: Kind, dynamicRange: DynamicRange, shouldViewOriginal: Bool) {
    self.kind = kind
    self.dynamicRange = dynamicRange
    self.shouldViewOriginal = shouldViewOriginal
  }

  /// Default for the row-based pipeline path, which has no file name to classify: SDR and
  /// safe to view from renditions (never original bytes).
  public static let standardDefault = MediaFormatInfo(
    kind: .other, dynamicRange: .sdr, shouldViewOriginal: false)

  /// Classifies from the original file name; `profileDescription` is `AssetExif.profileDescription`.
  public static func classify(fileName: String, profileDescription: String? = nil) -> MediaFormatInfo {
    let ext = (fileName as NSString).pathExtension.lowercased()
    let kind: Kind
    switch ext {
    case "jpg", "jpeg": kind = .jpeg
    case "png": kind = .png
    case "webp": kind = .webp
    case "gif": kind = .gif
    case "heic", "heif", "hif": kind = .heic
    case "dng", "arw", "cr2", "cr3", "nef", "nrw", "rw2", "orf", "pef", "srw", "raf", "rwl",
      "iiq", "3fr", "tif", "tiff":
      kind = .raw
    case "mov", "mp4", "m4v", "mkv", "avi", "webm": kind = .video
    default: kind = .other
    }
    let dynamicRange: DynamicRange = isHDRProfile(profileDescription) ? .hdr : .sdr
    return MediaFormatInfo(
      kind: kind,
      dynamicRange: dynamicRange,
      shouldViewOriginal: kind == .raw || kind == .heic || kind == .video
    )
  }

  private static func isHDRProfile(_ profileDescription: String?) -> Bool {
    guard let profileDescription, !profileDescription.isEmpty else { return false }
    let lower = profileDescription.lowercased()
    return ["dolby", "hlg", "smpte", "2084", "2100", "hdr"].contains { lower.contains($0) }
  }
}
