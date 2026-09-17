import CoreModel
import LocalStore
import Media
import Rules
import Search
import SwiftUI
import UIKit

/// Search screen (WP5 S1–S4, spec `device-native-22`): a search-role tab with the
/// system search field, Recents image cards + suggestion pills when the query is empty,
/// and debounced results in the WP1 `AssetGridView`. Offline instant results come from
/// the LocalStore exif mirror; a text query also fans out to server smart/metadata
/// search. Scope and Filters live in the toolbar, not in rows.
struct SearchView: View {
  @EnvironmentObject var session: AppSession

  @State private var query = ""
  @State private var scope: SearchScope = .all
  @State private var make = ""
  @State private var model = ""
  @State private var lens = ""
  @State private var favoritesOnly = false
  @State private var hasLocation: Bool? = nil
  @State private var mediaType: AssetKind? = nil
  @State private var resultIds: [String] = []
  @State private var resultColumns = 3
  @State private var searchToken = 0
  @State private var searchGeneration = 0
  @State private var isSearching = false
  @State private var searchError: String?
  @State private var recents: [SearchFilter] = []
  @State private var recentTopIds: [Int: String] = [:]
  @State private var showAllRecents = false
  @State private var suggestions: [SuggestionKind: [String]] = [:]
  @State private var peopleByName: [String: String] = [:]
  @State private var viewerIds: [String] = []
  @State private var viewerStart: String?
  @State private var showViewer = false
  @State private var showFilters = false
  @State private var searchTask: Task<Void, Never>?

  private static let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM yyyy"
    return formatter
  }()

  /// Results show for a typed query or an active metadata filter; otherwise Recents + pills.
  private var hasActiveFilters: Bool {
    !make.isEmpty || !model.isEmpty || !lens.isEmpty || favoritesOnly || hasLocation != nil
      || mediaType != nil
  }

  private var isShowingResults: Bool {
    !query.trimmingCharacters(in: .whitespaces).isEmpty || hasActiveFilters
  }

  var body: some View {
    NavigationStack {
      Group {
        if isShowingResults {
          resultsContent
        } else {
          idleContent
        }
      }
      .navigationTitle("Search")
      // The search-role tab renders this as the floating bottom field (plus mic
      // where the system offers one); typing debounces into `runSearch` below.
      .searchable(text: $query, placement: .automatic, prompt: "Search photos")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          HStack(spacing: 4) {
            scopeMenu
            Button {
              showFilters = true
            } label: {
              Label("Filters", systemImage: "line.3.horizontal.decrease")
            }
            .accessibilityIdentifier("search-filters-button")
            AccountButton()
          }
        }
      }
      .sheet(isPresented: $showFilters) {
        NavigationStack {
          filtersForm
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                  showFilters = false
                  triggerSearch()
                }
                .accessibilityIdentifier("search-apply-filters")
              }
            }
        }
      }
      .fullScreenCover(isPresented: $showViewer) {
        ViewerView(ids: viewerIds, initialId: viewerStart)
          .environmentObject(session)
      }
      .task(id: query) {
        guard isShowingResults else { return }
        // 300 ms debounce; a newer keystroke cancels this task, so stale
        // queries never overwrite fresher results.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        await runSearch()
      }
      .task {
        await loadIdle()
      }
    }
    .accessibilityIdentifier("search-view")
  }

  // MARK: - toolbar: scope menu (the "All → Library View" filter, as a menu)

  private var scopeMenu: some View {
    Menu {
      Picker("Scope", selection: $scope) {
        Text("All").tag(SearchScope.all)
        Text("Personal").tag(SearchScope.personal)
        ForEach(session.spaces, id: \.id) { space in
          Text(space.name).tag(SearchScope.space(space.id))
        }
        ForEach(session.libraries, id: \.id) { library in
          Text(library.name).tag(SearchScope.library(library.id))
        }
      }
    } label: {
      Label(scopeTitle, systemImage: "folder")
    }
    .accessibilityIdentifier("search-scope")
    .onChange(of: scope) { _, _ in
      if isShowingResults { triggerSearch() }
    }
  }

  private var scopeTitle: String {
    switch scope {
    case .all: return "All"
    case .personal: return "Personal"
    case .space(let id): return session.spaces.first { $0.id == id }?.name ?? "Space"
    case .library(let id): return session.libraries.first { $0.id == id }?.name ?? "Library"
    }
  }

  /// Manual trigger (scope/filter/apply changes): cancels the in-flight search so a
  /// slow query cannot overwrite the newer one; `searchGeneration` drops stragglers
  /// that already passed their last suspension point.
  private func triggerSearch() {
    searchTask?.cancel()
    searchTask = Task { await runSearch() }
  }

  // MARK: - idle: Recents image cards + suggestion pills (spec native-22)

  private var idleContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        recentsSection
        suggestionsSection
      }
      .padding()
    }
  }

  private var visibleRecents: Array<(offset: Int, element: SearchFilter)>.SubSequence {
    let all = Array(recents.enumerated())
    return showAllRecents ? all[...] : all.prefix(6)
  }

  private var recentsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Recents").font(.headline)
        Spacer()
        if !recents.isEmpty {
          Button("Clear", role: .destructive) {
            Task {
              guard let store = session.store else { return }
              try? await RecentSearchStore(store: store, userId: session.userId).clear()
              await loadIdle()
            }
          }
          .font(.subheadline)
          Button {
            showAllRecents.toggle()
          } label: {
            Image(systemName: showAllRecents ? "chevron.up" : "chevron.right")
          }
          .accessibilityIdentifier("search-recents-expand")
        }
      }
      if recents.isEmpty {
        Text("Recent searches show here with a preview of the top result.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 12) {
            ForEach(visibleRecents, id: \.offset) { offset, recent in
              Button { applyRecent(recent) } label: {
                VStack(alignment: .leading, spacing: 4) {
                  RecentCardThumb(assetId: recentTopIds[offset])
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                  Text(recentLabel(recent))
                    .font(.caption)
                    .lineLimit(2)
                    .frame(width: 96, alignment: .leading)
                }
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .accessibilityIdentifier("search-recents")
  }

  private var suggestionsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      pillGroup(title: "People", pills: suggestions[.people] ?? [], kind: .people)
      pillGroup(title: "Places", pills: suggestions[.places] ?? [], kind: .places)
      pillGroup(title: "Camera", pills: suggestions[.camera] ?? [], kind: .camera)
      pillGroup(title: "Lens", pills: suggestions[.lens] ?? [], kind: .lens)
      pillGroup(
        title: "File type",
        pills: (suggestions[.fileType] ?? []).map { $0.uppercased() },
        kind: .fileType)
      Text("More").font(.headline)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          Button("Videos") {
            var filter = currentFilter()
            filter.query = ""
            filter.local.mediaType = .video
            Task { await applyAndSearch(filter) }
          }
          .buttonStyle(.bordered)
          ForEach(Self.recentMonthRanges(), id: \.label) { month in
            Button(month.label) {
              var filter = currentFilter()
              filter.query = ""
              filter.local.takenAfter = month.start
              filter.local.takenBefore = month.end
              Task { await applyAndSearch(filter) }
            }
            .buttonStyle(.bordered)
          }
        }
      }
    }
    .accessibilityIdentifier("search-suggestions")
  }

  private func pillGroup(title: String, pills: [String], kind: SuggestionKind) -> some View {
    Group {
      if !pills.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text(title).font(.headline)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(pills.prefix(12), id: \.self) { pill in
                Button(pill) { applySuggestion(pill, kind: kind) }
                  .buttonStyle(.bordered)
              }
            }
          }
        }
      }
    }
  }

  /// Month ranges for the "recent months" pills, newest first.
  private static func recentMonthRanges(count: Int = 4) -> [(label: String, start: Date, end: Date)] {
    let calendar = Calendar.current
    let now = Date()
    guard
      let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
    else { return [] }
    return (0..<count).compactMap { back in
      guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth),
        let end = calendar.date(byAdding: .month, value: 1, to: start)
      else { return nil }
      return (monthFormatter.string(from: start), start, end)
    }
  }

  // MARK: - filters (toolbar sheet now, same fields as before)

  private var filtersForm: some View {
    Form {
      TextField("Camera make", text: $make).textInputAutocapitalization(.never)
      TextField("Camera model", text: $model).textInputAutocapitalization(.never)
      TextField("Lens", text: $lens).textInputAutocapitalization(.never)
      Toggle("Favorites only", isOn: $favoritesOnly)
      Picker("Media type", selection: $mediaType) {
        Text("Any").tag(nil as AssetKind?)
        Text("Photo").tag(AssetKind.image as AssetKind?)
        Text("Video").tag(AssetKind.video as AssetKind?)
      }
      Picker("Location", selection: $hasLocation) {
        Text("Any").tag(nil as Bool?)
        Text("Has location").tag(true as Bool?)
        Text("No location").tag(false as Bool?)
      }
      if hasActiveFilters {
        Button("Reset", role: .destructive) {
          make = ""
          model = ""
          lens = ""
          favoritesOnly = false
          hasLocation = nil
          mediaType = nil
        }
      }
    }
  }

  // MARK: - results

  private var resultsContent: some View {
    ZStack {
      if isSearching {
        ProgressView().accessibilityIdentifier("search-loading")
      } else if resultIds.isEmpty {
        ContentUnavailableView(
          "No results", systemImage: "magnifyingglass",
          description: Text(searchError ?? "Try a different query or widen the scope."))
      } else {
        // Results reuse the WP1 `AssetGridView` with an explicit id list (server
        // relevance order preserved). `ViewerRoute` hands the viewer the loader's
        // current order; the full-screen presentation matches the old behavior
        // until WP3's lazy pager lands.
        AssetGridView(
          source: .ids(resultIds),
          store: session.store,
          pipeline: session.pipeline,
          columns: $resultColumns,
          onOpen: { route in
            viewerIds = route.resolveIds()
            viewerStart = route.startId
            showViewer = true
          },
          showsSectionHeaders: false,
          reloadToken: searchToken
        )
        .accessibilityIdentifier("search-results")
      }
    }
  }

  // MARK: - search execution

  private func currentFilter() -> SearchFilter {
    var local = LocalAssetFilter()
    if !make.isEmpty { local.make = make }
    if !model.isEmpty { local.model = model }
    if !lens.isEmpty { local.lensModel = lens }
    if favoritesOnly { local.isFavorite = true }
    local.hasLocation = hasLocation
    local.mediaType = mediaType
    return SearchFilter(query: query.trimmingCharacters(in: .whitespaces), local: local, scope: scope)
  }

  private func runSearch() async {
    guard let store = session.store else { return }
    searchGeneration += 1
    let generation = searchGeneration
    let filter = currentFilter()
    isSearching = true
    searchError = nil
    defer { isSearching = false }
    do {
      let base = try await session.timelineScope()
      let context = try await store.timelineContext(for: session.userId)
      let resolved = filter.scope.resolve(local: base, context: context)
      // Offline instant results first — the grid paints from the mirror even with no network.
      let localRows = try await store.filterAssets(filter.local, scope: resolved)
      guard generation == searchGeneration else { return }
      if filter.wantsServerSearch, !session.isFixture, let serverURL = session.serverURL {
        let tokenStore = session.connection?.tokenStore
        let service = SearchService(
          baseURL: serverURL,
          tokenProvider: { @Sendable in await tokenStore?.get() })
        do {
          let ids = try await service.searchIds(filter: filter)
          // Server order is relevance order — the grid pages rows itself via assetsLite.
          guard generation == searchGeneration else { return }
          setIds(ids)
        } catch {
          // Server failed (offline, 4xx): fall back to the local rows already computed.
          guard generation == searchGeneration else { return }
          setIds(localRows.map(\.id))
          searchError = "Server search unavailable — showing offline results."
        }
      } else {
        setIds(localRows.map(\.id))
      }
      try? await RecentSearchStore(store: store, userId: session.userId).record(filter)
      await loadIdle()
    } catch {
      guard generation == searchGeneration else { return }
      searchError = error.localizedDescription
    }
  }

  @MainActor
  private func setIds(_ ids: [String]) {
    resultIds = ids
    searchToken += 1
  }

  // MARK: - suggestions + recents

  /// Idle data: recents (+ each recent's top-result thumbnail id), the person
  /// id lookup, and all five suggestion kinds via the local-first loader.
  private func loadIdle() async {
    guard let store = session.store else { return }
    recents = (try? await RecentSearchStore(store: store, userId: session.userId).recents()) ?? []
    suggestions = await SearchSuggestionLoader.allSuggestions(session: session, uiScope: scope)
    if let store = session.store {
      let named = (try? await store.namedPeople(forOwner: session.userId)) ?? []
      peopleByName = Dictionary(uniqueKeysWithValues: named.map { ($0.name, $0.id) })
    }
    await loadRecentTopIds()
  }

  /// Top-result asset id per visible recent, for the Recents image cards.
  private func loadRecentTopIds() async {
    guard let store = session.store else { return }
    var tops: [Int: String] = [:]
    do {
      let base = try await session.timelineScope()
      let context = try await store.timelineContext(for: session.userId)
      for (offset, recent) in recents.enumerated().prefix(12) {
        let resolved = recent.scope.resolve(local: base, context: context)
        if let top = try? await store.filterAssets(recent.local, scope: resolved, limit: 1).first {
          tops[offset] = top.id
        }
      }
    } catch {
      // Thumbnails are decorative; the labels still work.
    }
    recentTopIds = tops
  }

  private func applySuggestion(_ suggestion: String, kind: SuggestionKind) {
    switch kind {
    case .people:
      if let id = peopleByName[suggestion] {
        var filter = currentFilter()
        filter.query = ""
        filter.local.personIds = [id]
        Task { await applyAndSearch(filter) }
      }
    case .places:
      var filter = currentFilter()
      filter.query = ""
      filter.local.city = suggestion
      Task { await applyAndSearch(filter) }
    case .camera:
      make = suggestion
      triggerSearch()
    case .lens:
      lens = suggestion
      triggerSearch()
    case .fileType:
      var filter = currentFilter()
      filter.query = ""
      filter.local.fileExtensions = [suggestion.lowercased()]
      Task { await applyAndSearch(filter) }
    }
  }

  private func applyAndSearch(_ filter: SearchFilter) async {
    query = filter.query
    make = filter.local.make ?? ""
    model = filter.local.model ?? ""
    lens = filter.local.lensModel ?? ""
    favoritesOnly = filter.local.isFavorite ?? false
    hasLocation = filter.local.hasLocation
    mediaType = filter.local.mediaType
    scope = filter.scope
    await runSearch()
  }

  private func applyRecent(_ recent: SearchFilter) {
    Task { await applyAndSearch(recent) }
  }

  private func recentLabel(_ filter: SearchFilter) -> String {
    if !filter.query.isEmpty { return filter.query }
    if let make = filter.local.make { return "Camera: \(make)" }
    if let city = filter.local.city { return "Place: \(city)" }
    return "Filtered search"
  }
}

// MARK: - recent-card thumbnail (WP5 S1)

/// Small pipeline-backed thumbnail for a Recents card. Decorative: a gray fill when
/// the asset is gone or still loading.
struct RecentCardThumb: View {
  @EnvironmentObject var session: AppSession
  var assetId: String?
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Rectangle().fill(.gray.opacity(0.3))
      }
    }
    .task(id: assetId) {
      guard let assetId, let store = session.store, let pipeline = session.pipeline,
        let asset = try? await store.asset(id: assetId),
        let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail)
      else { return }
      switch loaded.content {
      case .placeholder(let img): image = img
      case .tier(_, let img, _): image = img
      }
    }
  }
}

// MARK: - all-metadata browser (A7 task 1)

/// Grouped, searchable, copyable view of `GET /assets/:id/exif/full`, cached per asset.
/// Shown in the viewer info panel below the local-mirror summary.
struct FullExifBrowser: View {
  var assetId: String
  var serverURL: URL?
  var tokenProvider: (@Sendable () async -> String?)?

  @State private var exif: FullExif?
  @State private var searchText = ""
  @State private var loadError: String?
  @State private var copied = false

  private static let cache = FullExifCache()

  var body: some View {
    Section("All metadata") {
      if let exif {
        TextField("Search metadata", text: $searchText)
        if searchText.isEmpty {
          ForEach(exif.groupNames, id: \.self) { group in
            DisclosureGroup(group) {
              ForEach(exif.entries(in: group), id: \.key) { entry in
                exifRow(group: group, key: entry.key, value: entry.value)
              }
            }
          }
        } else {
          ForEach(Array(exif.matching(searchText).enumerated()), id: \.offset) { _, match in
            exifRow(group: match.group, key: match.key, value: match.value)
          }
        }
      } else if let loadError {
        Text(loadError).font(.caption).foregroundStyle(.secondary)
      } else {
        ProgressView().controlSize(.small)
      }
    }
    .task { await load() }
  }

  private func exifRow(group: String, key: String, value: FullExifValue) -> some View {
    LabeledContent(key, value: value.displayText ?? "\u{2014}")
      .contextMenu {
        if let text = value.displayText {
          Button("Copy value") { UIPasteboard.general.string = text }
        }
        Button("Copy tag name") { UIPasteboard.general.string = "\(group):\(key)" }
      }
  }

  private func load() async {
    guard let serverURL, let tokenProvider else {
      loadError = "Full metadata needs a server connection."
      return
    }
    if let cached = await Self.cache.cached(assetId: assetId) {
      exif = cached
      return
    }
    do {
      let service = SearchService(
        baseURL: serverURL, tokenProvider: tokenProvider, fullExifCache: Self.cache)
      exif = try await service.fullExif(assetId: assetId)
    } catch {
      loadError = "Full metadata unavailable (\(error.localizedDescription))."
    }
  }
}

extension AppSession {
  /// Token closure for `SearchService` / `FullExifBrowser` — reads the live Keychain-backed
  /// token so search calls never use a stale copy.
  func searchTokenProvider() -> @Sendable () async -> String? {
    let tokenStore = connection?.tokenStore
    return { @Sendable in await tokenStore?.get() }
  }
}
