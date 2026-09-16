import AppKit
import AVKit
import CoreModel
import Media
import Photos
import PhotosUI
import SwiftUI

// MARK: - video (A9.1, macOS)

///
/// AVPlayerView playback: system scrubber, automatic HDR, streaming from the server
/// playback route. Trim hands off to the A8 editor (`MacEditView`) via `onTrim`.
struct MacVideoPageView: View {
  var asset: Asset
  var state: MacAppState
  var onTrim: () -> Void

  @State private var player: AVPlayer?

  var body: some View {
    ZStack {
      Group {
        if let player {
          MacPlayerView(player: player)
        } else {
          ProgressView().controlSize(.large)
        }
      }
      // Per-asset task (WP5 item 9): paging away cancels this task, which pauses the old
      // player before the new page's player is built — audio never bleeds across pages.
      .task(id: asset.id) {
        guard let token = await state.connection.tokenStore.get() else { return }
        let url = MediaEndpoint(serverURL: state.serverURL, assetID: asset.id).videoPlaybackURL()
        let urlAsset = AVURLAsset(
          url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]])
        let created = AVPlayer(playerItem: AVPlayerItem(asset: urlAsset))
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
  }
}

private struct MacPlayerView: NSViewRepresentable {
  var player: AVPlayer

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.player = player
    view.controlsStyle = .inline
    return view
  }

  func updateNSView(_ view: AVPlayerView, context: Context) {
    if view.player !== player { view.player = player }
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
