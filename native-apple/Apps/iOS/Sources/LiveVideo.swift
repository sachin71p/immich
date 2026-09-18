import AVKit
import CoreModel
import Media
import Photos
import PhotosUI
import SwiftUI

// MARK: - live photos (A9.1)

///
/// Plays a server Live Photo (still + motion part via `Asset.livePhotoVideoId`) in a
/// `PHLivePhotoView`. Long-press plays the full motion; pointer hover plays a hint.
/// The still doubles as the placeholder while the motion part downloads.
struct LivePhotoPageView: View {
  @EnvironmentObject var session: AppSession
  var asset: Asset
  var motionAssetId: String
  var onSingleTap: (() -> Void)? = nil
  /// Shared LIVE-badge play trigger (WP3 chrome): each token bump plays the motion once.
  @ObservedObject var playRequest: LivePlayRequest

  @State private var livePhoto: PHLivePhoto?
  @State private var still: UIImage?
  @State private var failed = false

  var body: some View {
    Group {
      if let livePhoto {
        LivePhotoInnerView(
          livePhoto: livePhoto, placeholder: still,
          playToken: playRequest.token)
      } else if let still {
        Image(uiImage: still)
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else if failed {
        ContentUnavailableView(
          "Live Photo unavailable", systemImage: "livephoto",
          description: Text("The motion part could not be downloaded."))
      } else {
        ProgressView().tint(.white)
          .accessibilityIdentifier("livephoto-loading")
      }
    }
    .accessibilityIdentifier("livephoto-page")
    .onTapGesture { onSingleTap?() }
    .task(id: asset.id) { await load() }
  }

  private func load() async {
    guard let base = session.apiBaseURL,
      let token = await session.bearerToken()
    else {
      failed = true
      return
    }
    do {
      let stillData = try await authorizedDownload(
        url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL(), token: token)
      still = UIImage(data: stillData)
      let motionData = try await authorizedDownload(
        url: MediaEndpoint(serverURL: base, assetID: asset.id)
          .livePhotoMotionURL(motionAssetID: motionAssetId), token: token)
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

private struct LivePhotoInnerView: UIViewRepresentable {
  var livePhoto: PHLivePhoto
  var placeholder: UIImage?
  /// Bumped by the chrome's LIVE badge: plays the full motion once per new token.
  var playToken: Int = 0

  func makeUIView(context: Context) -> PHLivePhotoView {
    let view = PHLivePhotoView()
    view.contentMode = .scaleAspectFit
    view.livePhoto = livePhoto
    let press = UILongPressGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.playFull(_:)))
    press.minimumPressDuration = 0.15
    view.addGestureRecognizer(press)
    let hover = UIHoverGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.playHint(_:)))
    view.addGestureRecognizer(hover)
    context.coordinator.view = view
    context.coordinator.appliedToken = playToken
    return view
  }

  func updateUIView(_ view: PHLivePhotoView, context: Context) {
    context.coordinator.view = view
    if view.livePhoto == nil { view.livePhoto = livePhoto }
    // The LIVE badge's tap arrives as a new token on the already-built view.
    if playToken != context.coordinator.appliedToken {
      context.coordinator.appliedToken = playToken
      if playToken > 0 { view.startPlayback(with: .full) }
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject {
    weak var view: PHLivePhotoView?
    var appliedToken = 0

    @objc func playFull(_ gesture: UILongPressGestureRecognizer) {
      guard gesture.state == .began else { return }
      view?.startPlayback(with: .full)
    }

    @objc func playHint(_ gesture: UIHoverGestureRecognizer) {
      guard gesture.state == .began else { return }
      view?.startPlayback(with: .hint)
    }
  }
}

// MARK: - video (WP3 step 3, spec device-native-11)

/// AVKit video playback with a native-style glass scrubber pill (play/pause, progress,
/// mute) above the viewer chrome. The system playback controls stay off so the pill is
/// the single control surface; trimming lives behind the chrome's Adjust button
/// (`EditView` via `VideoEdit`). Streams from the server playback route.
struct VideoPage: View {
  @EnvironmentObject var session: AppSession
  var asset: Asset
  var onSingleTap: (() -> Void)? = nil

  @State private var player: AVPlayer?
  @State private var isPlaying = false
  @State private var isMuted = false
  @State private var progress: Double = 0
  @State private var durationSeconds: Double = 0
  @State private var isScrubbing = false
  @State private var timeObserver: Any?
  @State private var endObserver: NSObjectProtocol?
  @State private var failedObserver: NSObjectProtocol?
  /// WP-R (F2): a stream the server rejects must surface, never sit black.
  @State private var playbackFailed = false
  @State private var attempt = 0
  /// WP-R/F2-diag: exact player error surfaced in the failure UI (no device
  /// log streaming available; the owner reads it off the screen).
  @State private var playbackError: String?

  var body: some View {
    ZStack {
      Group {
        if let player {
          PlayerControllerView(player: player)
            .accessibilityIdentifier("videoPlayerCanvas")
            .onTapGesture { onSingleTap?() }
        } else if playbackFailed {
          VStack(spacing: 12) {
            ContentUnavailableView(
              "Video unavailable", systemImage: "play.slash",
              description: Text("The video could not be played."))
            Button("Retry") {
              playbackFailed = false
              attempt += 1
            }
            .buttonStyle(.bordered)
            .tint(.white)
          }
        } else {
          ProgressView().tint(.white)
        }
      }
      .task(id: "\(asset.id)-\(attempt)") {
        await makePlayer()
      }
      .onDisappear {
        stopObserving()
        player?.pause()
        player = nil
      }
      VStack {
        Spacer()
        // Glass scrubber pill (spec native-11): play/pause, progress, mute. It
        // reserves the chrome's bottom space so it always sits above the bar.
        if player != nil {
          HStack(spacing: 12) {
            Button {
              togglePlay()
            } label: {
              Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            Slider(value: $progress, in: 0...1, onEditingChanged: endScrub)
              .tint(.white)
              .accessibilityLabel("Seek")
            Button {
              isMuted.toggle()
              player?.isMuted = isMuted
            } label: {
              Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(isMuted ? 0.6 : 1))
                .frame(width: 30, height: 30)
            }
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
          .padding(.horizontal, 20)
          .padding(.bottom, ViewerLayout.bottomReserve)
          .accessibilityIdentifier("video-scrubber")
        }
      }
      // WP-R (F2): mid-stream failure keeps the last frame but must offer a way
      // out — overlay retry instead of a dead player.
      // Above the pill in ZStack order: the pill used to cover this button.
      if playbackFailed, player != nil {
        VStack {
          Spacer()
          if let playbackError {
            Text(playbackError)
              .font(.caption2).foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 24)
          }
          Button("Video failed — Retry") {
            playbackFailed = false
            attempt += 1
          }
          .buttonStyle(.bordered)
          .tint(.white)
          .padding(.bottom, ViewerLayout.bottomReserve)
        }
      }
    }
    .accessibilityIdentifier("video-page")
  }

  private func makePlayer() async {
    stopObserving()
    progress = 0
    isPlaying = false
    playbackFailed = false
    // WP-R (F2): the scrubber must work even when the AV duration probe fails —
    // seed from the asset record first; the probe below only refines it.
    if durationSeconds <= 0, let known = asset.durationSeconds, known > 0 {
      durationSeconds = Double(known)
    }
    guard let base = session.apiBaseURL,
      let token = await session.bearerToken()
    else { return }
    let url = MediaEndpoint(serverURL: base, assetID: asset.id).videoPlaybackURL()
    let urlAsset = AVURLAsset(
      url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]])
    let item = AVPlayerItem(asset: urlAsset)
    let created = AVPlayer(playerItem: item)
    created.isMuted = isMuted
    player = created
    // WP-R (F2): bound the probe — the old unbounded `load(.duration)` left
    // `durationSeconds == 0` forever on failure, freezing the scrubber thumb.
    if let seconds = try? await withMainActorTimeout(
      seconds: EditorLoadBudget.videoDurationProbe,
      operation: { try await item.asset.load(.duration).seconds }),
      seconds.isFinite, seconds > 0
    {
      durationSeconds = seconds
    }
    // WP-R (F2): honour a play tap that landed before readiness, and surface a
    // rejected stream instead of sitting black with a dead scrubber.
    try? await withMainActorTimeout(seconds: EditorLoadBudget.playerReady, operation: {
      while item.status == .unknown {
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 100_000_000)
      }
    })
    if item.status == .failed {
      playbackFailed = true
      isPlaying = false
      // F2-diag: full error identity (domain + code + server response). The
      // one-line summary alone ("Operation Stopped") cannot name the cause.
      var parts: [String] = []
      if let err = item.error as NSError? {
        parts.append("domain=\(err.domain) code=\(err.code)")
        parts.append(err.localizedDescription)
      }
      if let ev = item.errorLog()?.events.last {
        let uri = ev.uri.map { String($0.suffix(80)) } ?? "?"
        parts.append("http=\(ev.errorStatusCode) uri=\(uri)")
      }
      if !parts.isEmpty { playbackError = parts.joined(separator: " | ") }
      return
    }
    if item.status == .readyToPlay, isPlaying {
      created.play()
    }
    // Both blocks run on .main, so they touch @State synchronously through the
    // assumed actor (the observer/notify APIs don't carry that statically).
    timeObserver = created.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
    ) { [weak created] _ in
      MainActor.assumeIsolated {
        guard let created, let current = created.currentItem else { return }
        let elapsed = current.currentTime().seconds
        guard elapsed.isFinite, durationSeconds > 0, !isScrubbing else { return }
        progress = min(max(elapsed / durationSeconds, 0), 1)
      }
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
    ) { _ in
      MainActor.assumeIsolated {
        isPlaying = false
        progress = 1
      }
    }
    // WP-R (F2): a mid-stream failure surfaces with a retry instead of freezing
    // on the last frame with a dead scrubber.
    failedObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
    ) { _ in
      MainActor.assumeIsolated {
        isPlaying = false
        playbackFailed = true
      }
    }
  }

  private func stopObserving() {
    if let timeObserver, let player {
      player.removeTimeObserver(timeObserver)
    }
    timeObserver = nil
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    self.endObserver = nil
    if let failedObserver {
      NotificationCenter.default.removeObserver(failedObserver)
    }
    self.failedObserver = nil
  }

  private func togglePlay() {
    guard let player else { return }
    if isPlaying {
      player.pause()
      isPlaying = false
    } else {
      if progress >= 1 { seek(to: 0) }
      player.play()
      isPlaying = true
    }
  }

  private func endScrub(_ editing: Bool) {
    isScrubbing = editing
    if !editing { seek(to: progress) }
  }

  private func seek(to fraction: Double) {
    guard let player, durationSeconds > 0 else { return }
    progress = fraction
    player.seek(to: CMTime(seconds: fraction * durationSeconds, preferredTimescale: 600))
  }
}

private struct PlayerControllerView: UIViewControllerRepresentable {
  var player: AVPlayer

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = player
    controller.showsPlaybackControls = false
    controller.allowsPictureInPicturePlayback = false
    controller.updatesNowPlayingInfoCenter = true
    return controller
  }

  func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
    if controller.player !== player { controller.player = player }
  }
}
