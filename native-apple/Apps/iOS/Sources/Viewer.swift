import AVFoundation
import AVKit
import CoreModel
import Editing
import LocalStore
import MapKit
import Media
import Rules
import Search
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - zoomable image (brief task 4: pinch / double-tap zoom, progressive tier upgrade)

struct ZoomableImageView: UIViewRepresentable {
  var image: UIImage?
  var onSingleTap: (() -> Void)? = nil

  func makeUIView(context: Context) -> UIScrollView {
    let scroll = UIScrollView()
    scroll.minimumZoomScale = 1
    scroll.maximumZoomScale = 6
    scroll.delegate = context.coordinator
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.isUserInteractionEnabled = true
    scroll.addSubview(imageView)
    context.coordinator.imageView = imageView
    let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoomToggle(_:)))
    doubleTap.numberOfTapsRequired = 2
    imageView.addGestureRecognizer(doubleTap)
    let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
    singleTap.require(toFail: doubleTap)
    imageView.addGestureRecognizer(singleTap)
    return scroll
  }

  func updateUIView(_ scroll: UIScrollView, context: Context) {
    context.coordinator.imageView?.image = image
    context.coordinator.onSingleTap = onSingleTap
    if let imageView = context.coordinator.imageView {
      imageView.frame = scroll.bounds
      imageView.contentMode = .scaleAspectFit
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, UIScrollViewDelegate {
    var imageView: UIImageView?
    var onSingleTap: (() -> Void)?

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc func zoomToggle(_ gesture: UITapGestureRecognizer) {
      guard let scroll = gesture.view?.superview as? UIScrollView else { return }
      scroll.setZoomScale(scroll.zoomScale > 1.5 ? 1 : 3, animated: true)
    }

    @objc func tapped() { onSingleTap?() }
  }
}

// MARK: - single asset page

struct ViewerPage: View {
  @EnvironmentObject var session: AppSession
  var assetId: String

  @State private var asset: Asset?
  @State private var image: UIImage?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if let asset, asset.type == .video {
        VideoPage(asset: asset)
      } else if let image {
        ZoomableImageView(image: image)
      } else {
        ProgressView()
          .tint(.white)
          .accessibilityIdentifier("viewer-loading")
      }
    }
    .task(id: assetId) {
      await load()
    }
  }

  private func load() async {
    guard let store = session.store else { return }
    asset = try? await store.asset(id: assetId)
    guard let asset, let pipeline = session.pipeline else { return }
    // Progressive tier upgrade (brief task 4): thumbnail first for instant paint, then preview,
    // then the full tier — each step replaces the previous image.
    for tier: MediaTier in [.thumbnail, .preview, .fullsize] {
      do {
        let loaded = try await pipeline.load(asset: asset, tier: tier)
        let next: UIImage? = switch loaded.content {
        case .placeholder(let img): img
        case .tier(_, let img, _): img
        }
        if let next { image = next }
        if tier == .fullsize { break }
      } catch {
        break
      }
    }
  }
}

/// Video playback with the bearer token attached (media routes are authenticated).
struct VideoPage: View {
  @EnvironmentObject var session: AppSession
  var asset: Asset
  @State private var player: AVPlayer?

  var body: some View {
    Group {
      if let player {
        VideoPlayer(player: player)
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
      player = AVPlayer(playerItem: item)
    }
  }
}

// MARK: - viewer (brief task 4)

/// Full-screen viewer: horizontal paging, progressive tiers, swipe-down dismiss with the grid
/// behind it, swipe-up info panel, and a permission-gated toolbar (brief task 9).
struct ViewerView: View {
  @EnvironmentObject var session: AppSession
  var ids: [String]
  var initialId: String?

  @State private var currentId: String?
  @State private var asset: Asset?
  @State private var showInfo = false
  @State private var showMoveSheet = false
  @State private var showAlbumPicker = false
  @State private var showEdit = false
  @State private var editPreview: UIImage?
  @State private var actionError: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()
        TabView(selection: $currentId) {
          ForEach(ids, id: \.self) { id in
            ViewerPage(assetId: id)
              .tag(id as String?)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .accessibilityIdentifier("viewer-pager")
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
        }
        ToolbarItemGroup(placement: .bottomBar) {
          if let asset {
            viewerToolbar(asset)
          }
        }
      }
      .sheet(isPresented: $showInfo) {
        if let asset {
          ViewerInfoPanel(asset: asset)
            .environmentObject(session)
            .presentationDetents([.medium, .large])
        }
      }
      .sheet(isPresented: $showMoveSheet) {
        if let currentId {
          MoveSheet(selectedIds: [currentId]) {
            Task { await reloadAsset() }
          }
          .environmentObject(session)
        }
      }
      .sheet(isPresented: $showAlbumPicker) {
        if let currentId {
          AlbumPickerSheet(assetIds: [currentId])
            .environmentObject(session)
        }
      }
      .fullScreenCover(isPresented: $showEdit) {
        if let asset, let editPreview, let base = session.serverURL {
          EditView(
            asset: asset, access: session.access, preview: editPreview,
            loadOriginalData: { try await downloadOriginal(asset) },
            loadVideoFile: asset.type == .video ? { try await downloadOriginalFile(asset) } : nil,
            persistence: RESTEditPersistence(
              serverURL: base, token: { await session.bearerToken() }),
            onDone: { _ in Task { await reloadAsset() } })
        }
      }
      .alert("Action failed", isPresented: Binding(
        get: { actionError != nil }, set: { if !$0 { actionError = nil } })
      ) {
        Button("OK") { actionError = nil }
      } message: {
        Text(actionError ?? "")
      }
      .task(id: currentId) { await reloadAsset() }
      .onAppear { currentId = initialId ?? ids.first }
      // Swipe-down dismiss (brief task 4): a fast downward drag closes the viewer.
      .gesture(
        DragGesture()
          .onEnded { value in
            if value.translation.height > 140 && abs(value.translation.width) < 80 {
              dismiss()
            }
          })
    }
  }

  @ViewBuilder
  private func viewerToolbar(_ asset: Asset) -> some View {
    let ctx = session.access
    let canDownload = Permissions.hasContainerAccess(asset.container, in: ctx)
    if canDownload {
      Button {
        share(asset)
      } label: { Label("Share", systemImage: "square.and.arrow.up") }
    }
    if Permissions.canFavorite(asset, in: ctx) {
      Button {
        mutate {
          guard let mutations = session.assetMutations else { return }
          try await mutations.setFavorite(ids: [asset.id], isFavorite: !asset.isFavorite)
        }
      } label: {
        Label("Favorite", systemImage: asset.isFavorite ? "heart.fill" : "heart")
      }
    }
    Button { showInfo = true } label: { Label("Info", systemImage: "info.circle") }
    if Permissions.canEdit(asset, in: ctx) {
      Button { openEdit(asset) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
    }
    if Permissions.canDelete(asset, in: ctx) {
      Button(role: .destructive) {
        mutate {
          try await session.assetMutations?.trash(ids: [asset.id])
          dismiss()
        }
      } label: { Label("Delete", systemImage: "trash") }
    }
    Menu {
      if Permissions.canMove(asset, to: .personal, in: ctx)
        || !MoveTargets.allowed(for: asset, in: ctx).isEmpty
      {
        Button("Move to…") { showMoveSheet = true }
      }
      if Permissions.canEdit(asset, in: ctx) {
        Button("Add to Album") { showAlbumPicker = true }
        Button(asset.visibility == .archive ? "Unarchive" : "Archive") {
          mutate {
            guard let mutations = session.assetMutations else { return }
            try await mutations.setArchived(
              ids: [asset.id], isArchived: asset.visibility != .archive)
          }
        }
        Button(asset.visibility == .hidden ? "Unhide" : "Hide") {
          mutate {
            guard let mutations = session.assetMutations else { return }
            try await mutations.setHidden(ids: [asset.id], isHidden: asset.visibility != .hidden)
          }
        }
        if canDownload {
          Button("Copy") { copyAsset(asset) }
        }
      }
    } label: {
      Label("More", systemImage: "ellipsis.circle")
    }
  }

  private func mutate(_ work: @escaping () async throws -> Void) {
    Task {
      do {
        try await work()
        try await session.refresh()
        await reloadAsset()
      } catch {
        actionError = error.localizedDescription
      }
    }
  }

  private func share(_ asset: Asset) {
    Task {
      guard let base = session.serverURL,
        let token = await session.bearerToken(),
        let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene }).first?.windows.first
      else { return }
      do {
        var request = URLRequest(
          url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL())
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(asset.originalFileName)
        try data.write(to: tmp)
        let activity = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
          popover.sourceView = window
        }
        window.rootViewController?.present(activity, animated: true)
      } catch {
        actionError = error.localizedDescription
      }
    }
  }

  private func copyAsset(_ asset: Asset) {
    Task {
      guard let base = session.serverURL,
        let token = await session.bearerToken()
      else { return }
      do {
        var request = URLRequest(
          url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL())
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        if asset.type == .video {
          UIPasteboard.general.setData(data, forPasteboardType: UTType.movie.identifier)
        } else if let image = UIImage(data: data) {
          UIPasteboard.general.image = image
        } else {
          UIPasteboard.general.string = asset.id
        }
      } catch {
        actionError = error.localizedDescription
      }
    }
  }

  private func openEdit(_ asset: Asset) {
    Task {
      do {
        let data = try await downloadOriginal(asset)
        if let image = UIImage(data: data) {
          editPreview = image
        } else {
          // Video: use the first frame as the editing preview.
          let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
          try data.write(to: tmp)
          editPreview = await firstFrame(of: tmp) ?? UIImage()
          try? FileManager.default.removeItem(at: tmp)
        }
        showEdit = true
      } catch {
        actionError = error.localizedDescription
      }
    }
  }

  private func downloadOriginal(_ asset: Asset) async throws -> Data {
    guard let base = session.serverURL, let token = await session.bearerToken() else {
      throw EditAccessError.notPermitted
    }
    var request = URLRequest(
      url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL())
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: request)
    return data
  }

  private func downloadOriginalFile(_ asset: Asset) async throws -> URL {
    let data = try await downloadOriginal(asset)
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension((asset.originalFileName as NSString).pathExtension)
    try data.write(to: tmp)
    return tmp
  }

  private func firstFrame(of url: URL) async -> UIImage? {
    // Synchronous thumbnail extraction on a background task (classic API — no
    // async-API availability questions on any deployment target).
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    do {
      let cg = try generator.copyCGImage(at: .zero, actualTime: nil)
      return UIImage(cgImage: cg)
    } catch {
      return nil
    }
  }

  private func reloadAsset() async {
    guard let currentId, let store = session.store else { return }
    asset = try? await store.asset(id: currentId)
  }
}

// MARK: - info panel (brief task 4: swipe-up panel; "All metadata" lands in A7)

/// Date, location mini-map, camera/lens/exposure summary, container, people, albums.
struct ViewerInfoPanel: View {
  @EnvironmentObject var session: AppSession
  var asset: Asset

  @State private var exif: AssetExif?
  @State private var people: [Person] = []
  @State private var albumNames: [String] = []

  var body: some View {
    NavigationStack {
      List {
        Section("Details") {
          if let date = asset.localDateTime {
            LabeledContent("Date", value: date.formatted(date: .long, time: .shortened))
          }
          LabeledContent("File", value: asset.originalFileName)
          if let w = asset.width, let h = asset.height {
            LabeledContent("Dimensions", value: "\(w) × \(h)")
          }
          LabeledContent("Container", value: containerName)
        }
        if let exif, exif.latitude != nil, exif.longitude != nil {
          Section("Location") {
            MiniMap(latitude: exif.latitude!, longitude: exif.longitude!)
              .frame(height: 160)
              .clipShape(RoundedRectangle(cornerRadius: 10))
            if let city = exif.city ?? exif.state ?? exif.country {
              Text(city)
            }
          }
        }
        Section("Camera") {
          if let make = exif?.make, let model = exif?.model {
            LabeledContent("Camera", value: "\(make) \(model)")
          }
          if let lens = exif?.lensModel {
            LabeledContent("Lens", value: lens)
          }
          HStack {
            if let iso = exif?.iso { Text("ISO \(iso)") }
            if let f = exif?.fNumber { Text(String(format: "ƒ/%.1f", f)) }
            if let exp = exif?.exposureTime { Text(exp) }
            if let focal = exif?.focalLength { Text(String(format: "%.0fmm", focal)) }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        if !people.isEmpty {
          Section("People") {
            ForEach(people) { person in Text(person.name) }
          }
        }
        if !albumNames.isEmpty {
          Section("Albums") {
            ForEach(albumNames, id: \.self) { Text($0) }
          }
        }
        FullExifBrowser(
          assetId: asset.id, serverURL: session.serverURL,
          tokenProvider: session.searchTokenProvider())
      }
      .navigationTitle("Info")
      .navigationBarTitleDisplayMode(.inline)
      .task {
        guard let store = session.store else { return }
        exif = try? await store.exif(for: asset.id)
        let mine = try? await store.peopleForOwner(session.userId)
        let owners = try? await store.peopleForOwner(asset.ownerId)
        people = Array((mine ?? []) + (owners ?? []).filter { p in !(mine ?? []).contains(p) })
        if let storeAlbums = try? await store.albumsForUser(session.userId) {
          var names: [String] = []
          for album in storeAlbums {
            if let rows = try? await store.albumAssets(albumId: album.id, limit: 10_000),
              rows.contains(where: { $0.id == asset.id })
            {
              names.append(album.name)
            }
          }
          albumNames = names
        }
      }
    }
  }

  private var containerName: String {
    switch asset.container {
    case .personal(let ownerId):
      return ownerId == session.userId ? "Personal Library" : "Personal Library (shared)"
    case .space(let id): return session.spaces.first { $0.id == id }?.name ?? "Shared Library"
    case .library(let id): return session.libraries.first { $0.id == id }?.name ?? "External Library"
    }
  }
}

struct MiniMap: View {
  var latitude: Double
  var longitude: Double

  var body: some View {
    Map(initialPosition: .region(region)) {
      Marker(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {}
    }
    .mapStyle(.standard)
  }

  private var region: MKCoordinateRegion {
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
  }
}
