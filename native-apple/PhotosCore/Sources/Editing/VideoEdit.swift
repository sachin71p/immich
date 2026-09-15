import AVFoundation
import CoreGraphics
import Foundation

/// UI-free video/live-photo export (brief section 6): trim, mute, rotate via AVFoundation.
/// The source file is only ever read; the export lands in a temp file the caller uploads.
public enum VideoEdit {
  public struct ExportResult: Sendable {
    public var fileURL: URL
    public var uti: String
    public var durationSeconds: Double
    public init(fileURL: URL, uti: String, durationSeconds: Double) {
      self.fileURL = fileURL
      self.uti = uti
      self.durationSeconds = durationSeconds
    }
  }

  /// Exports `sourceURL` applying `recipe`. Videos get trim/mute/quarter-turn rotation;
  /// Live Photo motion parts additionally accept `livePhotoKeyFrame` (handled by
  /// `extractKeyFrame` — the still is uploaded as its own rendered asset; see persistence).
  public static func export(sourceURL: URL, recipe: VideoRecipe) async throws -> ExportResult {
    let asset = AVURLAsset(url: sourceURL)
    let duration = try await asset.load(.duration).seconds
    let start = max(0, recipe.trimStart ?? 0)
    let end = min(duration, recipe.trimEnd ?? duration)
    guard end > start else { throw VideoEditError.emptyTrimRange }

    let composition = AVMutableComposition()
    guard
      let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
      let compVideo = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw VideoEditError.noVideoTrack }
    let range = CMTimeRange(
      start: CMTime(seconds: start, preferredTimescale: 600),
      duration: CMTime(seconds: end - start, preferredTimescale: 600))
    try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
    compVideo.preferredTransform = quarterTurnTransform(
      recipe.quarterTurns, naturalSize: try await videoTrack.load(.naturalSize),
      base: try await videoTrack.load(.preferredTransform))

    if !recipe.muted {
      for audio in try await asset.loadTracks(withMediaType: .audio) {
        if let compAudio = composition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        {
          try compAudio.insertTimeRange(range, of: audio, at: .zero)
        }
      }
    }

    let outURL =
      FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    guard
      let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
    else { throw VideoEditError.exportSessionUnavailable }
    do {
      try await session.export(to: outURL, as: .mp4)
    } catch {
      throw VideoEditError.exportFailed(String(describing: error))
    }
    return ExportResult(fileURL: outURL, uti: "public.mpeg-4", durationSeconds: end - start)
  }

  /// Extracts the Live Photo key frame as JPEG data (uploaded as the rendered still; the
  /// motion part goes through `export`). Best-effort: exact-frame accuracy, not
  /// sample-precise compositing.
  public static func extractKeyFrame(sourceURL: URL, at seconds: Double, quality: Double = 0.92) async throws
    -> Data
  {
    let asset = AVURLAsset(url: sourceURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let cg = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGImage, Error>) in
      generator.generateCGImageAsynchronously(
        for: CMTime(seconds: seconds, preferredTimescale: 600)
      ) { image, _, error in
        if let image {
          cont.resume(returning: image)
        } else {
          cont.resume(throwing: error ?? VideoEditError.keyFrameUnavailable)
        }
      }
    }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
      throw VideoEditError.encoderUnavailable
    }
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationSetProperties(
      dest, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw VideoEditError.encoderUnavailable }
    return data as Data
  }

  /// Clockwise quarter turns composed over the track's own preferred transform.
  static func quarterTurnTransform(
    _ turns: Int, naturalSize: CGSize, base: CGAffineTransform
  ) -> CGAffineTransform {
    let t = ((turns % 4) + 4) % 4
    guard t != 0 else { return base }
    // Rotate about the frame center: translate to origin, rotate clockwise, translate back
    // into the (possibly swapped) frame.
    let w = naturalSize.width
    let h = naturalSize.height
    let rotation = CGAffineTransform(rotationAngle: -CGFloat(t) * .pi / 2.0)
    let centered = CGAffineTransform(translationX: -w / 2, y: -h / 2)
      .concatenating(rotation)
    let swap = (t % 2 == 1)
    let back = CGAffineTransform(translationX: (swap ? h : w) / 2, y: (swap ? w : h) / 2)
    return base.concatenating(centered.concatenating(back))
  }
}

public enum VideoEditError: Error, Sendable, Equatable {
  case noVideoTrack
  case emptyTrimRange
  case exportSessionUnavailable
  case exportFailed(String)
  case keyFrameUnavailable
  case encoderUnavailable
}
