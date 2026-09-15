import AppKit
import CoreModel
import LocalStore
import Media
import SwiftUI

/// Asset viewer (brief task 3): in-window and full-screen, arrow-key paging, pinch/scroll zoom
/// with tier upgrade (thumbnail → preview → original through `MediaPipeline`), floating Info
/// inspector (⌘I), favorite (.), rotate (⌘R, display-only until A8 persists edits), delete (⌘⌫),
/// move to… (⌘⇧M), add to album.
struct MacViewerView: View {
  @Bindable var state: MacAppState
  var assetId: String
  @State private var asset: Asset?
  @State private var image: NSImage?
  @State private var loadedTier: MediaTier?
  @State private var rotation: Double = 0
  @State private var showingInspector = false
  @State private var showingMove = false
  @State private var showingAddToAlbum = false
  @State private var error: String?
  @Environment(\.openWindow) private var openWindow

  private var assetActions: MacAssetActions {
    MacAssetActions(
      favorite: { toggleFavorite() },
      rotate: { rotation += 90 },
      trash: { trash() },
      move: { showingMove = true },
      addToAlbum: { showingAddToAlbum = true },
      toggleInspector: { showingInspector.toggle() },
      openViewer: {},
      preview: {}
    )
  }

  private var siblings: [String] { state.viewerContext }
  private var index: Int? { siblings.firstIndex(of: assetId) }

  var body: some View {
    ZStack {
      if let image {
        MacZoomableImageView(image: image, onZoomBeyondPreview: upgradeTier)
          .rotationEffect(.degrees(rotation))
      } else {
        ProgressView().controlSize(.large)
      }
      if let error {
        Text(error).foregroundStyle(.red).font(.caption).padding()
      }
    }
    .frame(minWidth: 640, minHeight: 480)
    .navigationTitle(asset?.originalFileName ?? "Viewer")
    .focusedValue(\.macAssetActions, assetActions)
    .toolbar {
      ToolbarItemGroup {
        Button { toggleFavorite() } label: {
          Label("Favorite", systemImage: (asset?.isFavorite ?? false) ? "heart.fill" : "heart")
        }
        Button { rotation += 90 } label: { Label("Rotate", systemImage: "rotate.right") }
        Button { trash() } label: { Label("Delete", systemImage: "trash") }
        Button { showingMove = true } label: { Label("Move to…", systemImage: "folder") }
        Button { showingAddToAlbum = true } label: { Label("Add to Album", systemImage: "rectangle.stack.badge.plus") }
        Button { showingInspector.toggle() } label: { Label("Info", systemImage: "info.circle") }
      }
    }
    .inspector(isPresented: $showingInspector) {
      if let asset {
        MacInfoPanel(asset: asset, state: state)
      }
    }
    .sheet(isPresented: $showingMove) {
      MacMoveSheet(state: state, assetIds: [assetId]) { _ in showingMove = false }
    }
    .sheet(isPresented: $showingAddToAlbum) {
      MacAddToAlbumSheet(state: state, assetIds: [assetId]) { showingAddToAlbum = false }
    }
    .onKeyPress(.leftArrow) { page(by: -1); return .handled }
    .onKeyPress(.rightArrow) { page(by: 1); return .handled }
    .task(id: assetId) { await load(tier: .preview) }
  }

  private func page(by delta: Int) {
    guard let index, !siblings.isEmpty else { return }
    let next = siblings[(index + delta + siblings.count) % siblings.count]
    openWindow(value: MacWindow.viewer(next))
  }

  private func load(tier: MediaTier) async {
    do {
      guard let fresh = try await state.store.asset(id: assetId) else { return }
      asset = fresh
      let loaded = try await state.pipeline.load(asset: fresh, tier: tier)
      switch loaded.content {
      case .placeholder(let image): self.image = image
      case .tier(_, let image, _): self.image = image
      }
      loadedTier = tier
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func upgradeTier() {
    guard loadedTier != .original, asset != nil else { return }
    Task { await load(tier: .original) }
  }

  private func toggleFavorite() {
    guard let asset else { return }
    Task {
      do {
        try await state.assetMutations().setFavorite(ids: [assetId], isFavorite: !asset.isFavorite)
        self.asset = try await state.store.asset(id: assetId)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func trash() {
    Task {
      do {
        try await state.assetMutations().trash(ids: [assetId])
        await state.refresh()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/// NSScrollView magnifier: pinch/scroll zoom; crossing 2× fires `onZoomBeyondPreview` once so the
/// viewer upgrades to the original tier (brief task 3).
struct MacZoomableImageView: NSViewRepresentable {
  var image: NSImage
  var onZoomBeyondPreview: () -> Void

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 1
    scrollView.maxMagnification = 8
    let imageView = NSImageView(image: image)
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.imageAlignment = .alignCenter
    scrollView.documentView = imageView
    context.coordinator.observe(scrollView: scrollView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.update(action: onZoomBeyondPreview)
    (scrollView.documentView as? NSImageView)?.image = image
  }

  func makeCoordinator() -> Coordinator { Coordinator(action: onZoomBeyondPreview) }

  /// Main-thread-confined zoom state carried across the @Sendable notification closure.
  final class ZoomState: @unchecked Sendable {
    weak var scrollView: NSScrollView?
    var onZoom: () -> Void = {}
    var fired = false
  }

  final class Coordinator: NSObject {
    private let state = ZoomState()
    private var observer: NSObjectProtocol?

    init(action: @escaping () -> Void) {
      state.onZoom = action
    }

    func update(action: @escaping () -> Void) {
      state.onZoom = action
    }

    func observe(scrollView: NSScrollView) {
      state.scrollView = scrollView
      let state = self.state
      observer = NotificationCenter.default.addObserver(
        forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main
      ) { _ in
        MainActor.assumeIsolated {
          guard !state.fired, let view = state.scrollView, view.magnification > 2 else { return }
          state.fired = true
          state.onZoom()
        }
      }
    }

    deinit {
      if let observer { NotificationCenter.default.removeObserver(observer) }
    }
  }
}

/// Floating Info panel content (⌘I): everything the local mirror knows about the asset.
struct MacInfoPanel: View {
  var asset: Asset
  var state: MacAppState

  var body: some View {
    Form {
      Section("Info") {
        LabeledContent("Name", value: asset.originalFileName)
        if let date = asset.localDateTime {
          LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .shortened))
        }
        LabeledContent("Container", value: containerName)
        LabeledContent("Owner", value: asset.ownerId)
        if let w = asset.width, let h = asset.height {
          LabeledContent("Dimensions", value: "\(w) × \(h)")
        }
        LabeledContent("Favorite", value: asset.isFavorite ? "Yes" : "No")
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 260)
  }

  private var containerName: String {
    switch asset.container {
    case .personal: return "Personal Library"
    case .space(let id):
      return state.spaces.first(where: { $0.space.id == id })?.space.name ?? "Shared Library"
    case .library(let id):
      return state.libraries.first(where: { $0.library.id == id })?.library.name ?? "External Library"
    }
  }
}
