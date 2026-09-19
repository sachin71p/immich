import AVFoundation
import SwiftUI

/// Video trim filmstrip (E5, Photos pattern): a play button beside a
/// frame-thumbnail strip with yellow trim handles. Thumbnails are real decoded
/// frames (`AVAssetImageGenerator` over the loader-supplied file); before they
/// arrive the strip renders placeholder boxes so the control shell — and its
/// identifiers — exist synchronously.
///
/// Identifiers: `editor-trim-filmstrip`, `editor-trim-handle-start`,
/// `editor-trim-handle-end`, `editor-trim-play` (all asserted by
/// `EditorUITests`). Trim playback itself is owned by `EditView`, which
/// overlays an `AVKit.VideoPlayer` on the canvas.
struct EditTrimFilmstrip: View {
  var duration: Double
  var start: Double
  var end: Double
  var thumbs: [UIImage]
  var isPlaying: Bool
  var onTrim: (Double, Double) -> Void
  var onPlay: () -> Void

  @State private var anchorStart: Double?
  @State private var anchorEnd: Double?

  private var startFrac: Double { duration > 0 ? start / duration : 0 }
  private var endFrac: Double { duration > 0 ? end / duration : 1 }

  var body: some View {
    HStack(spacing: 8) {
      Button(action: onPlay) {
        ZStack {
          RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12))
            .frame(width: 44, height: 48)
          Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.body)
        }
      }
      .accessibilityIdentifier("editor-trim-play")
      GeometryReader { geo in
        let w = geo.size.width
        // Unidentified stack: the `editor-trim-filmstrip` id lives on the
        // thumbnail strip itself, so the sibling handle buttons keep theirs
        // (an identified container absorbs nested ids — E5 probes).
        ZStack(alignment: .leading) {
          thumbStrip
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("editor-trim-filmstrip")
          HStack(spacing: 0) {
            Color.black.opacity(0.55).frame(width: max(0, w * startFrac))
            Spacer(minLength: 0)
            Color.black.opacity(0.55).frame(width: max(0, w * (1 - endFrac)))
          }
          .frame(height: 44)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .allowsHitTesting(false)
          handle(
            id: "editor-trim-handle-start", x: w * startFrac,
            drag: { dx in
              if anchorStart == nil { anchorStart = startFrac }
              let f = clamp01((anchorStart ?? startFrac) + dx / max(1, w))
              onTrim(f * duration, end)
            },
            end: { anchorStart = nil })
          handle(
            id: "editor-trim-handle-end", x: w * endFrac,
            drag: { dx in
              if anchorEnd == nil { anchorEnd = endFrac }
              let f = clamp01((anchorEnd ?? endFrac) + dx / max(1, w))
              onTrim(start, f * duration)
            },
            end: { anchorEnd = nil })
        }
      }
      .frame(height: 48)
    }
  }

  private var thumbStrip: some View {
    HStack(spacing: 0) {
      if thumbs.isEmpty {
        ForEach(0..<8, id: \.self) { _ in
          RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.08))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(1)
        }
      } else {
        ForEach(0..<thumbs.count, id: \.self) { i in
          Image(uiImage: thumbs[i])
            .resizable().aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(1)
        }
      }
    }
  }

  private func handle(
    id: String, x: Double, drag: @escaping (Double) -> Void,
    end: @escaping () -> Void
  ) -> some View {
    // Button carrier: a bare Shape never enters the accessibility hierarchy
    // (E5 probes), but Buttons always expose. The tap action is empty — this
    // is a drag affordance — while the drag runs simultaneously beside it.
    Button(action: {}) {
      RoundedRectangle(cornerRadius: 4)
        .fill(.yellow)
        .frame(width: 10, height: 48)
    }
    .buttonStyle(.plain)
    .position(x: x, y: 24)
    .accessibilityLabel("Trim handle")
    .accessibilityIdentifier(id)
    .simultaneousGesture(
        DragGesture(minimumDistance: 1)
          .onChanged { g in drag(Double(g.translation.width)) }
          .onEnded { _ in end() })
  }

  private func clamp01(_ f: Double) -> Double { min(1, max(0, f)) }

  /// Real decoded frames for the strip, evenly spaced across `duration`.
  /// Failures yield fewer (or zero) images — never a throw — so the shell
  /// always renders.
  static func generateThumbs(fileURL: URL, duration: Double, count: Int = 14) async
    -> [UIImage]
  {
    guard duration > 0, count > 0 else { return [] }
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 112, height: 112)
    let times: [NSValue] = (0..<count).map { i in
      NSValue(
        time: CMTime(
          seconds: max(0.05, duration * (Double(i) + 0.5) / Double(count)),
          preferredTimescale: 600))
    }
    return await withCheckedContinuation { continuation in
      let box = ThumbBox(count: count)
      generator.generateCGImagesAsynchronously(forTimes: times) {
        requested, cg, _, _, _ in
        box.resolve(
          index: times.firstIndex(of: NSValue(time: requested)), image: cg,
          done: { continuation.resume(returning: $0) })
      }
    }
  }
}

/// Sendable accumulator for the (possibly off-main) thumbnail callbacks.
private final class ThumbBox: @unchecked Sendable {
  private let lock = NSLock()
  private var out: [CGImage?]
  private var pending: Int

  init(count: Int) {
    out = [CGImage?](repeating: nil, count: count)
    pending = count
  }

  func resolve(
    index: Int?, image: CGImage?,
    done: ([UIImage]) -> Void
  ) {
    lock.lock()
    if let index, out.indices.contains(index) { out[index] = image }
    pending -= 1
    let finished = pending <= 0
    let images = out.compactMap { $0 }.map { UIImage(cgImage: $0) }
    lock.unlock()
    if finished { done(images) }
  }
}
