import Rules
import SwiftUI

// MARK: - library screen (WP2: native chrome + zoom levels)

// Native Photos Library: large "Library" title with the visible-range subtitle,
// a glass filter menu + Select in the trailing toolbar, a glass Years·Months·All
// switch in the tab-bar accessory, separate Years/Months views driven by
// `bucketSummaries`, and native select mode (top filter + "…" + ✕, bottom
// Share / N Selected / Trash replacing the tab bar). The All grid stays the WP1
// `AssetGridView` — this screen only passes small values across the boundary.

struct LibraryView: View {
  @EnvironmentObject var session: AppSession
  @StateObject private var selection = GridSelectionModel()

  // MARK: persisted chrome state (`heirloom.*` naming)

  @AppStorage("heirloom.librarySort") private var sortRaw = LibrarySort.captured.rawValue
  @AppStorage("heirloom.libraryFilter") private var filterRaw = LibraryFilterItem.all.rawValue
  @AppStorage("heirloom.libraryMediaKinds") private var kindsRaw = ""
  @AppStorage("heirloom.librarySource") private var sourceRaw = "all"
  @AppStorage("heirloom.libraryAspectFit") private var aspectFit = false
  @AppStorage("heirloom.hideScreenshots") private var hideScreenshots = false
  @AppStorage("heirloom.hideSharedWithYou") private var hideSharedWithYou = false
  @AppStorage("heirloom.libraryZoom") private var zoomRaw = LibraryZoomLevel.all.rawValue
  @AppStorage("heirloom.libraryColumns") private var columns = 5

  @State private var gridSource: AssetGridSource?
  @State private var itemCount = 0
  @State private var visibleFirst: Date?
  @State private var visibleLast: Date?
  /// WP-G G6: true while the All grid is being dragged or decelerating — the
  /// header subtitle swaps between the item count (rest) and date range.
  @State private var isGridScrolling = false
  /// Dwell that keeps the range up briefly after the grid settles (cancels on
  /// new activity).
  @State private var scrollDwellTask: Task<Void, Never>?
  @State private var viewerRequest: ViewerRequest?
  @State private var showMoveSheet = false
  @State private var showAlbumPicker = false
  @State private var showSourcesSheet = false
  @State private var monthsScrollYear: String?
  @State private var actionError: String?

  /// Shared subtitle formatter — built once (the per-call `DateFormatter` here was
  /// 13.8% of main-thread time in the baseline trace).
  private static let subtitleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return formatter
  }()

  // Getters only (setters would need mutating self — bindings write the raws).
  private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .captured }

  private var filter: LibraryFilterItem { LibraryFilterItem(rawValue: filterRaw) ?? .all }

  private var kinds: Set<LibraryMediaKind> {
    Set(kindsRaw.split(separator: ",").compactMap { LibraryMediaKind(rawValue: String($0)) })
  }

  private var source: LibrarySource { Self.source(from: sourceRaw) }

  private var zoom: LibraryZoomLevel { LibraryZoomLevel(rawValue: zoomRaw) ?? .all }

  var body: some View {
    NavigationStack {
      Group {
        switch zoom {
        case .years:
          YearsView(source: source) { year in
            monthsScrollYear = year
            zoomRaw = LibraryZoomLevel.months.rawValue
          }
        case .months:
          MonthsView(source: source, scrollToYear: monthsScrollYear) { _ in
            // No scroll-to-day API on the WP1 grid contract (see WP2 report) —
            // the day tap opens All, which keeps its existing position.
            zoomRaw = LibraryZoomLevel.all.rawValue
          }
        case .all:
          allGrid
        }
      }
      .navigationTitle("Library")
      .navigationBarTitleDisplayMode(.large)
      .navigationSubtitle(librarySubtitle)
      .toolbar {
        if selection.isSelecting {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              exitSelect()
            } label: {
              Label("Done selecting", systemImage: "xmark")
            }
            .accessibilityIdentifier("select-exit")
          }
          ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 10) {
              filterMenu
              SelectMoreMenu(
                selectedIds: selection.ids,
                showAlbumPicker: $showAlbumPicker,
                showMoveSheet: $showMoveSheet
              ) { message in
                if !message.isCancellationMessage { actionError = message }
              }
            }
          }
        } else {
          // C4: the item count lives in the header, not as a persistent line
          // under the bottom pills (the `library-count` element is gone).
          ToolbarItem(placement: .topBarLeading) {
            Text(countLabel)
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("chrome-header-count")
          }
          ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 10) {
              filterMenu
              Button("Select") { selection.isSelecting = true }
                .accessibilityIdentifier("select-toggle")
            }
          }
        }
      }
      // Bottom chrome lives in a safeAreaInset, not `tabViewBottomAccessory`:
      // the accessory needs the new `Tab` content API, but MainTabs (WP5-owned)
      // still uses `tabItem`, under which the accessory never renders (the zoom
      // control and select toolbar were invisible to tests and users — see WP2
      // report). Revisit when WP5 moves MainTabs to `Tab`.
      .safeAreaInset(edge: .bottom) {
        if selection.isSelecting {
          SelectionActionBar(
            selectedIds: selection.ids,
            onClear: { exitSelect() },
            onError: { if !$0.isCancellationMessage { actionError = $0 } }
          )
          .background(.thinMaterial)
        } else {
          // C1: one floating bar — [library] [Years │ Months │ All] [search] —
          // instead of a pills row above the tab bar. C3: the search slot is
          // the separate search circle. The `library-zoom` identifier is kept
          // for the existing zoom tests; the select-mode branch above is
          // WP-M's and is untouched.
          HStack(spacing: 12) {
            Button {
              zoomRaw = LibraryZoomLevel.all.rawValue
            } label: {
              Image(systemName: "photo")
            }
            .accessibilityIdentifier("chrome-library-button")
            Picker("Zoom", selection: zoomBinding) {
              ForEach([LibraryZoomLevel.years, .months, .all]) { level in
                Text(level.title).tag(level)
              }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("library-zoom")
            Button {
              session.requestedTab = "search"
            } label: {
              Image(systemName: "magnifyingglass")
            }
            .accessibilityIdentifier("chrome-search-circle")
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .padding(.horizontal)
          // Container semantics: the bar keeps its own identifier AND exposes
          // the segment control / search circle inside it (a bare identifier
          // collapses the subtree into one element and hides the children).
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("chrome-floating-bar")
        }
      }
      .tabBarMinimizeBehavior(.onScrollDown)
      // Select mode replaces the tab bar with the bottom toolbar above.
      .toolbar(selection.isSelecting ? .hidden : .visible, for: .tabBar)
      .safeAreaInset(edge: .top) {
        if let banner = realError {
          HStack {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text(banner)
              .font(.caption)
              .lineLimit(2)
            Spacer()
            Button("Retry") { Task { await refreshAll() } }
              .accessibilityIdentifier("sync-error-retry")
            Button {
              session.lastError = nil
            } label: {
              Image(systemName: "xmark")
            }
            .accessibilityIdentifier("sync-error-dismiss")
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .padding(.horizontal)
          .accessibilityIdentifier("sync-error-banner")
        }
      }
      .task(id: filterTaskKey) {
        await resolveGrid()
      }
      .fullScreenCover(item: $viewerRequest) { request in
        ViewerView(ids: request.ids, initialId: request.initialId)
      }
      .sheet(isPresented: $showMoveSheet) {
        MoveSheet(selectedIds: Array(selection.ids)) {
          exitSelect()
          Task { await refreshAll() }
        }
        .environmentObject(session)
      }
      .sheet(isPresented: $showAlbumPicker) {
        AlbumPickerSheet(assetIds: Array(selection.ids))
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
    .overlay(alignment: .top) {
      // WP-G parity mirrors (G6/G7): near-invisible 1pt texts carrying the
      // header subtitle + time level for the parity tests. The visible header
      // is the navigation subtitle (no stable AX handle); visible chrome is
      // untouched — WP-C owns it.
      VStack(spacing: 0) {
        Text(librarySubtitle)
          .accessibilityIdentifier("grid-header-subtitle")
        Text(zoom.rawValue)
          .accessibilityIdentifier("grid-time-level")
          .accessibilityValue(zoom.rawValue)
      }
      .frame(width: 1, height: 1)
      .opacity(0.01)
    }
  }

  // MARK: - pieces

  private var filterMenu: some View {
    LibraryFilterMenu(
      sort: sortBinding,
      filter: filterBinding,
      kinds: kindsBinding,
      source: sourceBinding,
      aspectFit: $aspectFit,
      hideScreenshots: $hideScreenshots,
      hideSharedWithYou: $hideSharedWithYou,
      onZoomIn: { columns = min(13, columns + 1) },
      onZoomOut: { columns = max(1, columns - 1) },
      onShowSources: { showSourcesSheet = true }
    )
  }

  private var allGrid: some View {
    Group {
      if let gridSource {
        AssetGridView(
          source: gridSource,
          store: session.store,
          pipeline: session.pipeline,
          columns: $columns,
          aspectFit: aspectFit,
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
          showsSectionHeaders: false,
          reloadToken: session.timelineVersion,
          currentUserId: session.access.currentUserId,
          onPinchEdge: handlePinchEdge,
          onScrollActive: { active in
            // WP-G G6 dwell: the range stays up through deceleration and for
            // 2.5 s after settle (Photos-like lingering); cancelled by new
            // activity. The dwell is what the scroll test observes.
            scrollDwellTask?.cancel()
            if active {
              isGridScrolling = true
            } else {
              scrollDwellTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(2_500))
                guard !Task.isCancelled else { return }
                isGridScrolling = false
              }
            }
          },
          session: session
        )
        .accessibilityIdentifier("library-grid")
      } else {
        ProgressView()
          .accessibilityIdentifier("library-grid")
      }
    }
  }

  /// WP-G G6: the header subtitle is the item count at rest and swaps to the
  /// visible date range while scrolling (Photos behaviour, pair 01). Syncing
  /// keeps its existing treatment. The range arrives asynchronously from the
  /// grid, so before it lands the count stands in — never "No Photos" while
  /// the count says otherwise.
  private var librarySubtitle: String {
    if session.isSyncing, let first = visibleFirst, let last = visibleLast {
      return "\(rangeString(first: first, last: last)) · Syncing…"
    }
    if session.isSyncing { return "Syncing…" }
    if isGridScrolling, let first = visibleFirst, let last = visibleLast {
      return rangeString(first: first, last: last)
    }
    if itemCount == 0 {
      return "No Photos · Pull down to sync"
    }
    return "\(itemCount.formatted()) Items"
  }

  private func rangeString(first: Date, last: Date) -> String {
    "\(Self.subtitleFormatter.string(from: first)) – \(Self.subtitleFormatter.string(from: last))"
  }

  /// WP-G G7: pinch-past-edge from the grid couples column density to the time
  /// level — zooming out past max density steps All → Months → Years, zooming
  /// back in reverses it — so the Years/Months/All pills move with the pinch
  /// instead of staying pinned. Re-entering All lands dense (9 columns) to
  /// continue the continuum rather than jumping to the persisted width.
  private func handlePinchEdge(out: Bool) {
    switch (zoom, out) {
    case (.all, true):
      zoomRaw = LibraryZoomLevel.months.rawValue
    case (.months, true):
      zoomRaw = LibraryZoomLevel.years.rawValue
    case (.months, false):
      columns = 9
      zoomRaw = LibraryZoomLevel.all.rawValue
    case (.years, false):
      zoomRaw = LibraryZoomLevel.months.rawValue
    default:
      break
    }
  }

  private var countLabel: String {
    let base = "\(itemCount.formatted()) Items"
    return session.isSyncing ? "\(base) · Syncing…" : base
  }

  /// Real errors only: cancellations never surface (global rule 7).
  private var realError: String? {
    guard let text = session.lastError, !text.isEmpty, !text.isCancellationMessage
    else { return nil }
    return text
  }

  // aspectFit is a pure display flag (no re-resolve); columns persist per AppStorage.
  private var filterTaskKey: String {
    "\(sourceRaw)-\(zoom.rawValue)-\(sortRaw)-\(filterRaw)-\(kindsRaw)-\(hideScreenshots)-\(hideSharedWithYou)-\(session.timelineVersion)"
  }

  private func exitSelect() {
    selection.clear()
    selection.isSelecting = false
  }

  private func resolveGrid() async {
    guard let store = session.store else { return }
    // L2: a stale cancellation banner from a previous launch never survives a fresh load.
    await ErrorFilter.clearStaleCancellation(in: session)
    do {
      let scope = try await session.timelineScope(explicit: source.filter)
      let userId = session.access.currentUserId
      if zoom == .all {
        let resolved = try await resolveLibraryGrid(
          scope: scope,
          granularity: LibraryZoomLevel.all.granularity,
          sort: sort,
          filter: filter,
          kinds: kinds,
          hideScreenshots: hideScreenshots,
          hideSharedWithYou: hideSharedWithYou,
          store: store,
          userId: userId
        )
        guard !Task.isCancelled else { return }
        gridSource = resolved.source
        itemCount = resolved.count
      } else {
        // Years/Months views fetch their own buckets; the count still comes from
        // the compact index so the bottom label stays correct on every level.
        let index = try await store.timelineIndex(scope: scope)
        guard !Task.isCancelled else { return }
        itemCount = index.entries.count
      }
    } catch {
      // L2: `.task(id:)` restarts cancel in-flight loads — cancellation is not an error.
      if !error.isCancellation { session.lastError = error.localizedDescription }
    }
  }

  func refreshAll() async {
    await session.syncNow()
    await resolveGrid()
  }

  // MARK: - bindings over @AppStorage raw values

  private var sortBinding: Binding<LibrarySort> {
    Binding(
      get: { sort },
      set: { sortRaw = $0.rawValue })
  }

  private var filterBinding: Binding<LibraryFilterItem> {
    Binding(
      get: { filter },
      set: { filterRaw = $0.rawValue })
  }

  private var kindsBinding: Binding<Set<LibraryMediaKind>> {
    Binding(
      get: { kinds },
      set: { kindsRaw = $0.map(\.rawValue).sorted().joined(separator: ",") })
  }

  private var sourceBinding: Binding<LibrarySource> {
    Binding(
      get: { source },
      set: {
        sourceRaw = Self.sourceKey($0)
        selection.clear()
        selection.isSelecting = false
      })
  }

  private var zoomBinding: Binding<LibraryZoomLevel> {
    Binding(
      get: { zoom },
      set: { zoomRaw = $0.rawValue })
  }

  // MARK: - source persistence

  static func sourceKey(_ source: LibrarySource) -> String {
    switch source {
    case .all: return "all"
    case .personal: return "personal"
    case .space(let id): return "space-\(id)"
    case .library(let id): return "library-\(id)"
    }
  }

  static func source(from raw: String) -> LibrarySource {
    if raw == "personal" { return .personal }
    if raw.hasPrefix("space-") { return .space(String(raw.dropFirst("space-".count))) }
    if raw.hasPrefix("library-") { return .library(String(raw.dropFirst("library-".count))) }
    return .all
  }
}

/// Viewer launch request (full-screen cover item). WP3 replaces the array with a pager
/// driven directly by `ViewerRoute`.
struct ViewerRequest: Identifiable {
  var ids: [String]
  var initialId: String?
  var id: String { initialId ?? ids.joined(separator: ",") }
}
