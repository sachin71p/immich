import Rules
import SwiftUI

// MARK: - library screen (grid + switcher + zoom + scrubber + selection)

struct LibraryView: View {
  @EnvironmentObject var session: AppSession
  @StateObject private var loader = LibraryGridLoader()
  @State private var source: LibrarySource = .all
  @State private var zoom: LibraryZoomLevel = .months
  @State private var columns: Int = 3
  @State private var squareCells = false
  @State private var editMode = false
  @State private var selectedIds = Set<String>()
  @State private var scrubIndex = 0
  @State private var viewerRequest: ViewerRequest?
  @State private var showMoveSheet = false
  @State private var showSourcesSheet = false
  @State private var actionError: String?

  var body: some View {
    NavigationStack {
      // S2: session errors are visible — a dismissible banner with Retry above the grid.
      if let syncError = session.lastError {
        HStack {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.yellow)
          Text(syncError)
            .font(.caption)
            .lineLimit(2)
          Spacer()
          Button("Retry") { Task { await refreshAll() } }
            .accessibilityIdentifier("sync-error-retry")
          Button { session.lastError = nil } label: {
            Image(systemName: "xmark")
          }
          .accessibilityIdentifier("sync-error-dismiss")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.15))
        .accessibilityIdentifier("sync-error-banner")
      }
      ZStack(alignment: .trailing) {
        PhotoGridView(
          model: loader.model, columns: columns, squareCells: squareCells, editMode: editMode,
          selectedIds: selectedIds, pipeline: session.pipeline,
          onTap: { id in
            viewerRequest = ViewerRequest(ids: loader.model.allRowIds, initialId: id)
          },
          onSelectionChange: { selectedIds = $0 },
          onPrefetch: { ids in
            // Fixture art is served from the cell-warmed cache; never hit the network for it.
            let real = ids.filter { !FixtureArtwork.isFixtureAsset($0) }
            guard !real.isEmpty else { return }
            Task { await session.pipeline?.prefetch(ids: real, tier: .thumbnail) }
          },
          onPinchColumns: { columns = $0 },
          onRefresh: { await refreshAll() },
          scrubSection: scrubIndex
        )
        .accessibilityIdentifier("library-grid")
        .ignoresSafeArea(edges: .bottom)
        // Date scrubber (brief task 1).
        if loader.model.buckets.count > 1 {
          Slider(value: Binding(
            get: { Double(scrubIndex) },
            set: { scrubIndex = Int($0) }
          ), in: 0...Double(max(0, loader.model.buckets.count - 1)), step: 1)
          .rotationEffect(.degrees(-90))
          .frame(width: 160)
          .offset(x: 56)
          .accessibilityIdentifier("date-scrubber")
        }
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          // Library switcher (brief task 2, Apple-style menu).
          Menu {
            Button("Both Libraries") { pickSource(.all) }
            Button("Personal Library") { pickSource(.personal) }
            ForEach(session.spaces) { space in
              Button(space.name) { pickSource(.space(space.id)) }
            }
            ForEach(session.libraries) { library in
              Button(library.name) { pickSource(.library(library.id)) }
            }
            Divider()
            Button("Show in Timeline…") { showSourcesSheet = true }
          } label: {
            Label(sourceTitle, systemImage: "photo.stack")
          }
          .accessibilityIdentifier("library-switcher")
        }
        ToolbarItem(placement: .principal) {
          VStack(spacing: 0) {
            Text("Library").font(.headline)
            Text(librarySubtitle).font(.caption2).foregroundStyle(.secondary)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: 10) {
            Button { columns = max(2, columns - 1) } label: { Image(systemName: "minus") }
            Button { columns = min(10, columns + 1) } label: { Image(systemName: "plus") }
            Button(editMode ? "Done" : "Select") {
              editMode.toggle()
              if !editMode { selectedIds = [] }
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 4) {
          if editMode {
            SelectionActionBar(
              selectedIds: selectedIds,
              onClear: { selectedIds = [] },
              onMove: { showMoveSheet = true },
              onError: { actionError = $0 }
            )
          }
          Picker("Zoom", selection: $zoom) {
            ForEach(LibraryZoomLevel.allCases) { level in
              Text(level.title).tag(level)
            }
          }
          .pickerStyle(.segmented)
          .padding(.horizontal)
          Toggle("Square", isOn: $squareCells)
            .font(.caption)
            .padding(.horizontal)
        }
        .background(.thinMaterial)
      }
      // S1: re-keyed on `timelineVersion` so rows appear once a sync lands, without waiting
      // for a source/zoom change.
      .task(id: "\(sourceKey)-\(session.timelineVersion)") { await reload() }
      .onChange(of: zoom) { _, new in
        columns = new.defaultColumns
        Task { await reload() }
      }
      .fullScreenCover(item: $viewerRequest) { request in
        ViewerView(ids: request.ids, initialId: request.initialId)
      }
      .sheet(isPresented: $showMoveSheet) {
        MoveSheet(selectedIds: Array(selectedIds)) {
          selectedIds = []
          editMode = false
          Task { await refreshAll() }
        }
        .environmentObject(session)
      }
      .sheet(isPresented: $showSourcesSheet) {
        TimelineSourcesSheet()
          .environmentObject(session)
      }
      .alert("Action failed", isPresented: Binding(
        get: { actionError != nil }, set: { if !$0 { actionError = nil } })
      ) {
        Button("OK") { actionError = nil }
      } message: {
        Text(actionError ?? "")
      }
    }
  }

  private var sourceKey: String {
    switch source {
    case .all: return "all"
    case .personal: return "personal"
    case .space(let id): return "space-\(id)"
    case .library(let id): return "library-\(id)"
    }
  }

  private var sourceTitle: String {
    switch source {
    case .all: return "Library"
    case .personal: return "Personal"
    case .space(let id): return session.spaces.first { $0.id == id }?.name ?? "Shared Library"
    case .library(let id): return session.libraries.first { $0.id == id }?.name ?? "Library"
    }
  }

  private var librarySubtitle: String {
    // S2: sync progress is visible — indeterminate state only (the coordinator exposes no counts).
    if session.isSyncing { return "Syncing…" }
    let dates = loader.model.rowsById.values.compactMap(\.localDateTime).sorted()
    guard let first = dates.first, let last = dates.last
    else { return "No Photos · Pull down to sync" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
  }

  private func pickSource(_ new: LibrarySource) {
    source = new
    selectedIds = []
    editMode = false
    scrubIndex = 0
  }

  private func reload() async {
    guard let store = session.store else { return }
    do {
      let scope = try await session.timelineScope(explicit: source.filter)
      await loader.load(scope: scope, granularity: zoom.granularity, store: store)
    } catch {
      session.lastError = error.localizedDescription
    }
  }

  func refreshAll() async {
    await session.syncNow()
    await reload()
  }
}

/// Viewer launch request (full-screen cover item).
struct ViewerRequest: Identifiable {
  var ids: [String]
  var initialId: String?
  var id: String { initialId ?? ids.joined(separator: ",") }
}
