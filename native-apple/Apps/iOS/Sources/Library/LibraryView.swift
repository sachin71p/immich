import Rules
import SwiftUI

// MARK: - library screen (grid + switcher + zoom + selection)

struct LibraryView: View {
  @EnvironmentObject var session: AppSession
  @StateObject private var selection = GridSelectionModel()
  @State private var source: LibrarySource = .all
  @State private var zoom: LibraryZoomLevel = .months
  @State private var columns: Int = 3
  @State private var gridSource: AssetGridSource?
  @State private var visibleFirst: Date?
  @State private var visibleLast: Date?
  @State private var viewerRequest: ViewerRequest?
  @State private var showMoveSheet = false
  @State private var showSourcesSheet = false
  @State private var actionError: String?

  /// Shared subtitle formatter — built once (the per-call `DateFormatter` here was
  /// 13.8% of main-thread time in the baseline trace).
  private static let subtitleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return formatter
  }()

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
      Group {
        if let gridSource {
          AssetGridView(
            source: gridSource,
            store: session.store,
            pipeline: session.pipeline,
            columns: $columns,
            aspectFit: false,
            selection: selection,
            onOpen: { route in
              viewerRequest = ViewerRequest(
                ids: route.resolveIds(), initialId: route.startId)
            },
            onRefresh: { await refreshAll() },
            onVisibleRange: { first, last in
              visibleFirst = first
              visibleLast = last
            },
            showsSectionHeaders: zoom != .all,
            reloadToken: session.timelineVersion
          )
          .accessibilityIdentifier("library-grid")
        } else {
          ProgressView()
            .accessibilityIdentifier("library-grid")
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
            Button { columns = max(1, columns - 1) } label: { Image(systemName: "minus") }
            Button { columns = min(13, columns + 1) } label: { Image(systemName: "plus") }
            Button(selection.isSelecting ? "Done" : "Select") {
              selection.isSelecting.toggle()
              if !selection.isSelecting { selection.clear() }
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 4) {
          if selection.isSelecting {
            SelectionActionBar(
              selectedIds: selection.ids,
              onClear: { selection.clear() },
              onMove: { showMoveSheet = true },
              onError: { if !$0.isCancellationMessage { actionError = $0 } }
            )
          }
          Picker("Zoom", selection: $zoom) {
            ForEach(LibraryZoomLevel.allCases) { level in
              Text(level.title).tag(level)
            }
          }
          .pickerStyle(.segmented)
          .padding(.horizontal)
        }
        .background(.thinMaterial)
      }
      // S1: re-keyed on source, zoom and `timelineVersion` so rows appear once a sync
      // lands, without waiting for a source/zoom change.
      .task(id: "\(sourceKey)-\(zoom.rawValue)-\(session.timelineVersion)") {
        await resolveSource()
      }
      .onChange(of: zoom) { _, new in
        columns = new.defaultColumns
      }
      .fullScreenCover(item: $viewerRequest) { request in
        ViewerView(ids: request.ids, initialId: request.initialId)
      }
      .sheet(isPresented: $showMoveSheet) {
        MoveSheet(selectedIds: Array(selection.ids)) {
          selection.clear()
          selection.isSelecting = false
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
    guard let first = visibleFirst, let last = visibleLast
    else { return "No Photos · Pull down to sync" }
    return
      "\(Self.subtitleFormatter.string(from: first)) – \(Self.subtitleFormatter.string(from: last))"
  }

  private func pickSource(_ new: LibrarySource) {
    source = new
    selection.clear()
    selection.isSelecting = false
  }

  private func resolveSource() async {
    guard let store = session.store else { return }
    // L2: a stale cancellation banner from a previous launch never survives a fresh load.
    await ErrorFilter.clearStaleCancellation(in: session)
    do {
      let scope = try await session.timelineScope(explicit: source.filter)
      // The store is unused here beyond the nil check — the grid resolves the timeline
      // itself — but without a store there is nothing to show.
      _ = store
      gridSource = .timeline(scope: scope, granularity: zoom.granularity)
    } catch {
      // L2: `.task(id:)` restarts cancel in-flight loads — cancellation is not an error.
      if !error.isCancellation { session.lastError = error.localizedDescription }
    }
  }

  func refreshAll() async {
    await session.syncNow()
    await resolveSource()
  }
}

/// Viewer launch request (full-screen cover item). WP3 replaces the array with a pager
/// driven directly by `ViewerRoute`.
struct ViewerRequest: Identifiable {
  var ids: [String]
  var initialId: String?
  var id: String { initialId ?? ids.joined(separator: ",") }
}
