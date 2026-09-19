import AppKit
import AVKit
import CoreModel
import Media
import Photos
import PhotosUI
import SwiftUI

// MARK: - playback loader (V3, shared by the SwiftUI page and VideoPageController)

/// Builds the video player through the production loader path (playback route
/// + `Authorization` header) and gates on `isPlayable` before returning, so a
/// player that never becomes ready surfaces its `AVPlayerItem.status` + error
/// through `HeirloomLog` instead of spinning silently (V3).
struct VideoPlaybackLoader: Sendable {
  var serverURL: URL
  var token: @Sendable () async -> String?

  enum Outcome {
    case ready(AVPlayer, AVPlayerItem)
    case failed(String)
  }

  func load(assetID: String) async -> Outcome {
    guard let token = await token() else {
      HeirloomLog.media.error("video load missing token asset=\(assetID, privacy: .public)")
      return .failed("Not signed in.")
    }
    let url = MediaEndpoint(serverURL: serverURL, assetID: assetID).videoPlaybackURL()
    let urlAsset = AVURLAsset(
      url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]])
    do {
      let playable = try await urlAsset.load(.isPlayable)
      guard playable else {
        HeirloomLog.media.error(
          "video not playable asset=\(assetID, privacy: .public) url=\(url.absoluteString, privacy: .public)")
        return .failed("This video could not be played.")
      }
    } catch {
      HeirloomLog.media.error(
        "video load failed asset=\(assetID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
      return .failed(error.localizedDescription)
    }
    let item = AVPlayerItem(asset: urlAsset)
    return .ready(AVPlayer(playerItem: item), item)
  }
}

// MARK: - video (A9.1, macOS, V3/V4)

///
/// AVPlayerView playback: system scrubber, automatic HDR, streaming from the server
/// playback route. Trim hands off to the A8 editor (`MacEditView`) via `onTrim`.
struct MacVideoPageView: View {
  var asset: Asset
  var state: MacAppState
  var onTrim: () -> Void
  var onArrowKey: ((Int) -> Void)? = nil

  @State private var player: AVPlayer?
  @State private var loadError: String?
  /// Current playback time for TEST-PLAN V3 UI (`viewer.video.time` advances).
  @State private var timeString = "0:00"

  private var loader: VideoPlaybackLoader {
    VideoPlaybackLoader(
      serverURL: state.serverURL,
      token: { [connection = state.connection] in await connection.tokenStore.get() })
  }

  var body: some View {
    ZStack {
      Group {
        if let player {
          MacPlayerView(player: player, onArrowKey: onArrowKey, timeString: timeString)
        } else if let loadError {
          ContentUnavailableView(
            "Video unavailable", systemImage: "video.slash",
            description: Text(loadError))
        } else {
          ProgressView().controlSize(.large)
        }
      }
      // Per-asset task (WP5 item 9): paging away cancels this task, which pauses the old
      // player before the new page's player is built — audio never bleeds across pages.
      .task(id: asset.id) {
        loadError = nil
        switch await loader.load(assetID: asset.id) {
        case .ready(let created, _):
          player = created
          created.play()
          // Release on close (item 9): when this task is cancelled the handler pauses the old
          // player and drops the reference, so the AVPlayer deallocates with the page.
          await withTaskCancellationHandler(operation: {
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(24 * 3600)) }
          }, onCancel: {
            Task { @MainActor in
              created.pause()
              if player === created { player = nil }
            }
          })
        case .failed(let message):
          loadError = message
        }
      }
      .onDisappear {
        player?.pause()
        player = nil
      }
      VStack {
        Spacer()
        HStack {
          Spacer()
          // Mute/volume live in the player view's own inline controls; Trim is app
          // behavior (hands off to the editor), so it stays as an overlay button.
          Button(action: onTrim) {
            Label("Trim", systemImage: "scissors")
          }
        }
        .padding()
        .background(.black.opacity(0.35))
      }
    }
    .accessibilityIdentifier("mac-video-page")
    .task(id: player) {
      guard let player else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { continue }
        timeString = Self.formatTime(seconds)
      }
    }
  }

  private static func formatTime(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    return "\(total / 60):\(String(format: "%02d", total % 60))"
  }
}

private struct MacPlayerView: NSViewRepresentable {
  var player: AVPlayer
  var onArrowKey: ((Int) -> Void)? = nil
  var timeString: String = "0:00"

  func makeNSView(context: Context) -> PagingAVPlayerView {
    let view = PagingAVPlayerView()
    view.player = player
    view.controlsStyle = .inline
    view.onArrowKey = onArrowKey
    // TEST-PLAN V3 UI: viewer.video.time advances during playback.
    view.setAccessibilityIdentifier(AXIDs.viewerVideoTime)
    view.setAccessibilityValue(timeString)
    return view
  }

  func updateNSView(_ view: PagingAVPlayerView, context: Context) {
    if view.player !== player { view.player = player }
    view.onArrowKey = onArrowKey
    view.setAccessibilityValue(timeString)
  }
}

// MARK: - live photos (A9.1, macOS)

/// Server Live Photo in a `PHLivePhotoView`: press-and-hold plays the full motion,
/// hovering plays a hint.
struct MacLivePhotoPageView: View {
  var asset: Asset
  var motionAssetId: String
  var state: MacAppState

  @State private var livePhoto: PHLivePhoto?
  @State private var still: NSImage?
  @State private var failed = false
  /// Bumped on LIVE-badge hover; the inner view plays the hint on each bump (item 9).
  @State private var hintTick = 0

  var body: some View {
    Group {
      if let livePhoto {
        MacLivePhotoInnerView(livePhoto: livePhoto, hintTick: hintTick)
          .overlay(alignment: .topLeading) {
            Label("Live", systemImage: "livephoto")
              .font(.caption.weight(.semibold))
              .labelStyle(.titleAndIcon)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(.thinMaterial, in: Capsule())
              .padding(12)
              .onHover { hovering in
                if hovering { hintTick += 1 }
              }
          }
      } else if let still {
        Image(nsImage: still)
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else if failed {
        ContentUnavailableView(
          "Live Photo unavailable", systemImage: "livephoto",
          description: Text("The motion part could not be downloaded."))
      } else {
        ProgressView().controlSize(.large)
      }
    }
    .accessibilityIdentifier("mac-livephoto-page")
    .task(id: asset.id) { await load() }
  }

  private func load() async {
    guard let token = await state.connection.tokenStore.get() else {
      failed = true
      return
    }
    do {
      let stillData = try await authorizedDownload(
        url: MediaEndpoint(serverURL: state.serverURL, assetID: asset.id).originalURL(),
        token: token)
      still = NSImage(data: stillData)
      let motionData = try await authorizedDownload(
        url: MediaEndpoint(serverURL: state.serverURL, assetID: asset.id)
          .livePhotoMotionURL(motionAssetID: motionAssetId),
        token: token)
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("live-\(asset.id)", isDirectory: true)
      try? FileManager.default.removeItem(at: dir)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let stillURL = dir.appendingPathComponent(
        "still.\((asset.originalFileName as NSString).pathExtension)")
      try stillData.write(to: stillURL)
      let motionURL = dir.appendingPathComponent("motion.mov")
      try motionData.write(to: motionURL)
      livePhoto = await withCheckedContinuation { continuation in
        PHLivePhoto.request(
          withResourceFileURLs: [stillURL, motionURL],
          placeholderImage: still,
          targetSize: CGSize(width: 1024, height: 1024),
          contentMode: PHImageContentMode.aspectFit
        ) { photo, _ in
          continuation.resume(returning: photo)
        }
      }
      if livePhoto == nil { failed = true }
    } catch {
      failed = true
    }
  }

  private func authorizedDownload(url: URL, token: String) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: request)
    return data
  }
}

private struct MacLivePhotoInnerView: NSViewRepresentable {
  var livePhoto: PHLivePhoto
  var hintTick: Int = 0

  func makeNSView(context: Context) -> PHLivePhotoView {
    let view = PHLivePhotoView()
    view.livePhoto = livePhoto
    let press = NSPressGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.playFull(_:)))
    press.minimumPressDuration = 0.2
    view.addGestureRecognizer(press)
    context.coordinator.view = view
    context.coordinator.startHoverTracking(in: view)
    return view
  }

  func updateNSView(_ view: PHLivePhotoView, context: Context) {
    context.coordinator.view = view
    if view.livePhoto == nil { view.livePhoto = livePhoto }
    // LIVE-badge hover (item 9): each tick replays the motion hint. Long-press still
    // plays the full motion via the press recognizer below.
    if hintTick != context.coordinator.lastHintTick {
      context.coordinator.lastHintTick = hintTick
      if hintTick > 0 { view.startPlayback(with: .hint) }
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  @MainActor
  final class Coordinator: NSObject {
    weak var view: PHLivePhotoView?
    var lastHintTick = 0

    @objc func playFull(_ gesture: NSPressGestureRecognizer) {
      guard gesture.state == .began else { return }
      view?.startPlayback(with: .full)
    }

    func startHoverTracking(in view: NSView) {
      let area = NSTrackingArea(
        rect: view.bounds,
        options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
        owner: self, userInfo: nil)
      view.addTrackingArea(area)
    }

    @objc func mouseEntered(with event: NSEvent) {
      view?.startPlayback(with: .hint)
    }
  }
}
