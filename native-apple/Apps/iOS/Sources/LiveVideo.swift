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

  @State private var livePhoto: PHLivePhoto?
  @State private var still: UIImage?
  @State private var failed = false

  var body: some View {
    Group {
      if let livePhoto {
        LivePhotoInnerView(livePhoto: livePhoto, placeholder: still)
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
    .task(id: asset.id) { await load() }
  }

  private func load() async {
    guard let base = session.serverURL,
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
    return view
  }

  func updateUIView(_ view: PHLivePhotoView, context: Context) {
    context.coordinator.view = view
    if view.livePhoto == nil { view.livePhoto = livePhoto }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject {
    weak var view: PHLivePhotoView?

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

// MARK: - video (A9.1)

/// AVKit video playback: system scrubber, automatic HDR, and HLS-style streaming from the
/// server playback route. Mute toggles instantly on the player; Trim hands off to the A8
/// editor (`EditView` via `VideoEdit`) instead of duplicating trim UI.
struct VideoPage: View {
  @EnvironmentObject var session: AppSession
  var asset: Asset
  var onTrim: (Asset) -> Void

  @State private var player: AVPlayer?
  @State private var isMuted = false

  var body: some View {
    ZStack {
      Group {
        if let player {
          PlayerControllerView(player: player)
        } else {
          ProgressView().tint(.white)
        }
      }
      .task {
        guard let base = session.serverURL,
          let token = await session.bearerToken()
        else { return }
        let url = MediaEndpoint(serverURL: base, assetID: asset.id).videoPlaybackURL()
        let urlAsset = AVURLAsset(
          url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]])
        let item = AVPlayerItem(asset: urlAsset)
        let created = AVPlayer(playerItem: item)
        created.isMuted = isMuted
        player = created
      }
      VStack {
        Spacer()
        HStack {
          Spacer()
          Button {
            isMuted.toggle()
            player?.isMuted = isMuted
          } label: {
            Label(
              isMuted ? "Unmute" : "Mute",
              systemImage: isMuted ? "speaker.slash.fill" : "speaker.fill")
          }
          Button { onTrim(asset) } label: {
            Label("Trim", systemImage: "scissors")
          }
        }
        .tint(.white)
        .padding()
        .background(.black.opacity(0.35))
      }
    }
    .accessibilityIdentifier("video-page")
  }
}

private struct PlayerControllerView: UIViewControllerRepresentable {
  var player: AVPlayer

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = player
    controller.showsPlaybackControls = true
    controller.allowsPictureInPicturePlayback = true
    controller.updatesNowPlayingInfoCenter = true
    return controller
  }

  func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
    if controller.player !== player { controller.player = player }
  }
}
