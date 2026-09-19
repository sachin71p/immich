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
  /// WP-V (V7): filmstrip slots (`nil` = placeholder awaiting its frame) plus
  /// the closed-caption control state. The strip container renders as soon as
  /// generation starts — frames stream in progressively, so a slow asset never
  /// blocks the chrome.
  @State private var filmstripActive = false
  @State private var filmstripThumbs: [UIImage?] = []
  @State private var ccAvailable = false
  @State private var ccOn = false

  var body: some View {
    ZStack {
      Group {
        if let player {
          PlayerControllerView(player: player)
            .accessibilityIdentifier("video-player-canvas")
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
      // WP-V (V7): thumbnail generation runs beside playback (F2's player,
      // retry, and error states below are untouched).
      .task(id: "filmstrip-\(asset.id)-\(attempt)") {
        await buildFilmstrip()
      }
      .onDisappear {
        stopObserving()
        player?.pause()
        player = nil
      }
      VStack {
        Spacer()
        // Glass scrubber pill (V7, pair `09`): frame-thumbnail filmstrip over
        // play · progress · time · CC · mute. It reserves the chrome's bottom
        // space so it always sits above the bar.
        if player != nil {
          VStack(spacing: 8) {
            if filmstripActive {
              VideoFilmstrip(
                thumbs: filmstripThumbs, progress: progress,
                onSeek: { seek(to: $0) }
              )
            }
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
              Text(scrubTimeLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
              Button {
                setCC(!ccOn)
              } label: {
                Image(systemName: ccOn ? "captions.bubble.fill" : "captions.bubble")
                  .font(.title3)
                  .foregroundStyle(.white.opacity(ccAvailable ? (ccOn ? 1 : 0.8) : 0.4))
                  .frame(width: 30, height: 30)
              }
              .accessibilityLabel("Closed Captions")
              .accessibilityValue(ccOn ? "On" : "Off")
              .accessibilityIdentifier("video-scrubber-cc")
              .disabled(!ccAvailable)
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
              .accessibilityIdentifier("video-scrubber-mute")
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
          .padding(.horizontal, 20)
          .padding(.bottom, ViewerLayout.bottomReserve)
          // Containment first: without it this pill id floods the controls and
          // the CC/mute ids stop resolving (same lesson as `video-page`).
          .accessibilityElement(children: .contain)
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
    // WP-V (V7): explicit containment BEFORE the identifier (the codebase
    // convention — `viewer-chrome-surface`, info panel). Reversed, the root's
    // identifier propagates onto every child and the chrome's own ids stop
    // resolving.
    .accessibilityElement(children: .contain)
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

  /// WP-V (V7): `elapsed / total` for the scrub row (fixture 0:07 reads `0:00 / 0:07`).
  private var scrubTimeLabel: String {
    let total = max(0, Int(durationSeconds.rounded()))
    let elapsed = min(total, max(0, Int((progress * durationSeconds).rounded())))
    return "\(VideoDurationFormat.string(seconds: elapsed)) / \(VideoDurationFormat.string(seconds: total))"
  }

  /// WP-V (V7): frame thumbnails for the filmstrip, generated from the same
  /// authed playback asset the player streams (F2 postmortem: `apiBaseURL`,
  /// never the raw server URL). Frames stream into their slots as they decode
  /// — the container is already up, so a long asset never blocks the chrome.
  /// Cancels with the view (task id) via `cancelAllCGImageGeneration`.
  private func buildFilmstrip() async {
    filmstripActive = false
    filmstripThumbs = []
    ccAvailable = false
    ccOn = false
    var total = Double(asset.durationSeconds ?? 0)
    if total <= 0 {
      // No record duration: wait briefly for the player's probe (F2 seeds this
      // first, so this loop rarely spins).
      for _ in 0..<50 {
        if Task.isCancelled { return }
        if durationSeconds > 0 { total = durationSeconds; break }
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
    }
    guard total > 0, !Task.isCancelled else { return }
    guard let base = session.apiBaseURL,
      let token = await session.bearerToken()
    else { return }
    let urlAsset = AVURLAsset(
      url: MediaEndpoint(serverURL: base, assetID: asset.id).videoPlaybackURL(),
      options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]])
    let generator = AVAssetImageGenerator(asset: urlAsset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 160, height: 160)
    let count = 12
    let times = (0..<count).map { i in
      NSValue(time: CMTime(
        seconds: total * (Double(i) + 0.5) / Double(count), preferredTimescale: 600))
    }
    // Slots first: the strip paints placeholders immediately, frames fill in.
    filmstripThumbs = [UIImage?](repeating: nil, count: count)
    filmstripActive = true
    // The generator calls back off-main: collect `CGImage`s (Sendable) across
    // the boundary and wrap them in `UIImage`s back on the main actor.
    struct GeneratorHolder: @unchecked Sendable { let generator: AVAssetImageGenerator }
    let holder = GeneratorHolder(generator: generator)
    // The completion handler is `@Sendable`: mutable accumulation lives in a
    // locked box, never in captured locals.
    final class FilmstripCollector: @unchecked Sendable {
      private let lock = NSLock()
      private var collected: [(Int, CGImage)] = []
      private var received = 0
      func append(_ item: (Int, CGImage)?, total: Int) -> [(Int, CGImage)]? {
        lock.withLock {
          if let item { collected.append(item) }
          received += 1
          return received >= total ? collected : nil
        }
      }
    }
    let collector = FilmstripCollector()
    let slots = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<[(Int, CGImage)], Never>) in
        generator.generateCGImagesAsynchronously(forTimes: times) {
          requestedTime, cgImage, _, result, _ in
          let item: (Int, CGImage)? =
            if let cgImage, result == .succeeded,
              let index = times.firstIndex(where: { $0.timeValue == requestedTime })
            {
              (index, cgImage)
            } else {
              nil
            }
          if let done = collector.append(item, total: count) {
            continuation.resume(returning: done)
          }
        }
      }
    } onCancel: {
      holder.generator.cancelAllCGImageGeneration()
    }
    if Task.isCancelled { return }
    for (index, cgImage) in slots where filmstripThumbs.indices.contains(index) {
      filmstripThumbs[index] = UIImage(cgImage: cgImage)
    }
    // Captions ride on the now-loaded asset: a real toggle when tracks exist,
    // honestly disabled when they don't (never a dead button).
    if let group = urlAsset.mediaSelectionGroup(forMediaCharacteristic: .legible),
      !group.options.isEmpty
    {
      ccAvailable = true
    }
  }

  /// WP-V (V7): toggle the legible track; no-op when the asset has none (the
  /// button is disabled there, so this is a backstop, not a path).
  private func setCC(_ on: Bool) {
    guard let item = player?.currentItem,
      let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
      !group.options.isEmpty
    else { return }
    if on {
      if let option = group.options.first { item.select(option, in: group) }
    } else {
      item.select(nil, in: group)
    }
    ccOn = on
  }
}

/// WP-V (V7): frame-thumbnail scrub strip (pair `09`). Tap seeks; the white
/// playhead tracks `progress` while playing. Tap-only (never a drag) so the
/// pager's own gestures — swipe down to dismiss, swipe up for info, sideways
/// to page — keep every touch that moves: the Slider below stays the
/// drag-scrub surface, as before.
private struct VideoFilmstrip: View {
  var thumbs: [UIImage?]
  var progress: Double
  var onSeek: (_ fraction: Double) -> Void

  var body: some View {
    GeometryReader { geo in
      HStack(spacing: 2) {
        ForEach(thumbs.indices, id: \.self) { index in
          Group {
            if let image = thumbs[index] {
              Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
            } else {
              Rectangle().fill(.white.opacity(0.15))
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .clipped()
          .clipShape(RoundedRectangle(cornerRadius: 4))
          .accessibilityIdentifier("video-scrubber-frame")
        }
      }
      .overlay(alignment: .leading) {
        Rectangle()
          .fill(.white)
          .frame(width: 2)
          .offset(x: min(max(progress, 0), 1) * geo.size.width)
      }
      .onTapGesture(coordinateSpace: .local) { location in
        let width = max(geo.size.width, 1)
        onSeek(min(max(location.x / width, 0), 1))
      }
    }
    .frame(height: 44)
    .accessibilityLabel("Video filmstrip scrubber")
    // Containment BEFORE the identifier (codebase convention): the strip keeps
    // its own id and the per-frame ids keep theirs.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("video-scrubber-filmstrip")
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
