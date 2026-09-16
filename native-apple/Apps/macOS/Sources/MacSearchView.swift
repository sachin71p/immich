import AppKit
import CoreModel
import LocalStore
import Media
import Rules
import Search
import SwiftUI

/// macOS search (A7 task 2): same DSL as iOS `SearchView` — smart query, metadata filters,
/// scope selector, suggestion chips, recent searches — with results in the shared
/// `MacCollectionGridView` (single "Results" section) and viewer/preview wired like the
/// main grid.
struct MacSearchView: View {
  @Bindable var state: MacAppState
  /// Opens the asset inline in the hosting `MacLibraryBrowser`, same as a grid double-click.
  var onOpenViewer: (String) -> Void

  @State private var query = ""
  @State private var scope: SearchScope = .all
  @State private var make = ""
  @State private var favoritesOnly = false
  @State private var hasLocation: Bool? = nil
  @State private var mediaType: AssetKind? = nil
  @State private var rows: [TimelineRow] = []
  @State private var assetsById: [String: Asset] = [:]
  @State private var isSearching = false
  @State private var searchError: String?
  @State private var hasSearched = false
  @State private var recents: [SearchFilter] = []
  @State private var chip: SuggestionKind? = nil
  @State private var suggestions: [String] = []
  @State private var selectedIds = Set<String>()

  var body: some View {
    VStack(spacing: 0) {
      searchField
      scopePicker
      if !hasSearched {
        idleContent
      } else {
        resultsContent
      }
    }
    .navigationTitle("Search")
    .accessibilityIdentifier("mac-search-view")
    .task { await loadRecents() }
  }

  private var searchField: some View {
    HStack {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField("Search photos", text: $query)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("mac-search-field")
        .onSubmit { Task { await runSearch() } }
      Button("Search") { Task { await runSearch() } }
        .accessibilityIdentifier("mac-search-submit")
    }
    .padding(8)
  }

  private var scopePicker: some View {
    Picker("Scope", selection: $scope) {
      Text("All").tag(SearchScope.all)
      Text("Personal").tag(SearchScope.personal)
      ForEach(state.spaces, id: \.space.id) { entry in
        Text(entry.space.name).tag(SearchScope.space(entry.space.id))
      }
      ForEach(state.libraries, id: \.library.id) { entry in
        Text(entry.library.name).tag(SearchScope.library(entry.library.id))
      }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal, 8)
    .accessibilityIdentifier("mac-search-scope")
    .onChange(of: scope) { _, _ in
      if hasSearched { Task { await runSearch() } }
    }
  }

  private var idleContent: some View {
    List {
      Section("Suggestions") {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            ForEach(SuggestionKind.allCases, id: \.self) { kind in
              Button {
                chip = (chip == kind) ? nil : kind
                Task { await loadSuggestions() }
              } label: {
                Label(kind.title, systemImage: kind.systemImage)
              }
              .buttonStyle(.bordered)
              .tint(chip == kind ? .accentColor : .secondary)
            }
          }
        }
        if chip != nil {
          ForEach(suggestions, id: \.self) { suggestion in
            Button { applySuggestion(suggestion) } label: { Text(suggestion) }
          }
        }
      }
      DisclosureGroup("Filters") {
        TextField("Camera make", text: $make)
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
        Button("Apply filters") { Task { await runSearch() } }
      }
      if !recents.isEmpty {
        Section("Recent searches") {
          ForEach(Array(recents.enumerated()), id: \.offset) { _, recent in
            Button { Task { await applyAndSearch(recent) } } label: {
              Text(recent.query.isEmpty ? "Filtered search" : recent.query).lineLimit(1)
            }
          }
          Button("Clear", role: .destructive) {
            Task {
              guard let userId = state.userId else { return }
              try? await RecentSearchStore(store: state.store, userId: userId).clear()
              await loadRecents()
            }
          }
        }
      }
    }
  }

  private var resultsContent: some View {
    Group {
      if isSearching {
        ProgressView()
      } else if rows.isEmpty {
        ContentUnavailableView(
          "No results", systemImage: "magnifyingglass",
          description: Text(searchError ?? "Try a different query or widen the scope."))
      } else {
        MacCollectionGridView(
          sections: [MacGridSection(header: "Results", rows: rows)],
          assetsById: assetsById,
          rowDates: rows.map { Self.dateString($0.localDateTime) },
          pipeline: state.pipeline,
          exporter: macExporter(),
          itemSize: 160,
          selectedIds: $selectedIds,
          onSelectionChange: { _ in },
          onOpen: openViewer,
          onPreview: showPreview,
          onToggleFavorite: { id in toggleFavorite(id) },
          onMagnify: { _ in }
        )
        .accessibilityIdentifier("mac-search-results")
      }
    }
  }

  private func toggleFavorite(_ id: String) {
    Task {
      guard let asset = assetsById[id] else { return }
      try? await state.assetMutations().setFavorite(ids: [id], isFavorite: !asset.isFavorite)
      await runSearch()
    }
  }

  // MARK: - execution

  private func currentFilter() -> SearchFilter {
    var local = LocalAssetFilter()
    if !make.isEmpty { local.make = make }
    if favoritesOnly { local.isFavorite = true }
    local.hasLocation = hasLocation
    local.mediaType = mediaType
    return SearchFilter(query: query.trimmingCharacters(in: .whitespaces), local: local, scope: scope)
  }

  private func resolvedScope(for filter: SearchFilter) async throws -> ContainerScope {
    guard let userId = state.userId else { return .empty }
    let context = try await state.store.timelineContext(for: userId)
    let base = TimelineScope.resolve(purpose: .timeline, context: context)
    return filter.scope.resolve(local: base, context: context)
  }

  private func runSearch() async {
    let filter = currentFilter()
    isSearching = true
    searchError = nil
    defer { isSearching = false }
    do {
      let resolved = try await resolvedScope(for: filter)
      let localRows = try await state.store.filterAssets(filter.local, scope: resolved)
      if filter.wantsServerSearch {
        let tokenStore = state.connection.tokenStore
        let service = SearchService(
          baseURL: state.serverURL,
          tokenProvider: { @Sendable in await tokenStore.get() })
        do {
          let ids = try await service.searchIds(filter: filter)
          let assets = try await state.store.assets(ids: ids)
          setResults(assets, order: ids)
        } catch {
          setRows(localRows)
          searchError = "Server search unavailable — showing offline results."
        }
      } else {
        setRows(localRows)
      }
      hasSearched = true
      if let userId = state.userId {
        try? await RecentSearchStore(store: state.store, userId: userId).record(filter)
        await loadRecents()
      }
    } catch {
      searchError = error.localizedDescription
      hasSearched = true
    }
  }

  private func setRows(_ rows: [TimelineRow]) {
    Task {
      let assets = (try? await state.store.assets(ids: rows.map(\.id))) ?? []
      setResults(assets, order: rows.map(\.id))
    }
  }

  private func setResults(_ assets: [Asset], order: [String]) {
    let byId = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    let orderedRows = order.compactMap { id -> TimelineRow? in
      guard let asset = byId[id] else { return nil }
      return TimelineRow(
        id: asset.id, thumbhash: asset.thumbhash, aspectRatio: 1, mediaKind: .photo,
        isFavorite: asset.isFavorite, isTrashed: false, isArchived: asset.visibility == .archive,
        localDateTime: asset.localDateTime)
    }
    rows = orderedRows
    assetsById = byId
  }

  private func macExporter() -> MacExporter {
    let tokenStore = state.connection.tokenStore
    return MacExporter(
      serverURL: state.serverURL,
      tokenProvider: { @Sendable in await tokenStore.get() })
  }

  private func openViewer(id: String) {
    state.viewerContext = rows.map(\.id)
    onOpenViewer(id)
  }

  private func showPreview(id: String) {
    Task { @MainActor in
      var asset = assetsById[id]
      if asset == nil { asset = try? await state.store.asset(id: id) }
      guard let asset else { return }
      MacPreviewPanel.show(asset: asset, pipeline: state.pipeline)
    }
  }

  // MARK: - suggestions + recents

  private func loadSuggestions() async {
    guard let kind = chip else {
      suggestions = []
      return
    }
    if kind.serverType == nil {
      guard let userId = state.userId else {
        suggestions = []
        return
      }
      let mine = (try? await state.store.peopleForOwner(userId)) ?? []
      suggestions = mine.map(\.name).sorted()
      return
    }
    let tokenStore = state.connection.tokenStore
    let service = SearchService(
      baseURL: state.serverURL,
      tokenProvider: { @Sendable in await tokenStore.get() })
    suggestions = (try? await service.suggestions(kind: kind, scope: scope)) ?? []
  }

  private func applySuggestion(_ suggestion: String) {
    guard let kind = chip else { return }
    switch kind {
    case .people:
      Task {
        guard let userId = state.userId else { return }
        let mine = (try? await state.store.peopleForOwner(userId)) ?? []
        if let person = mine.first(where: { $0.name == suggestion }) {
          var filter = currentFilter()
          filter.local.personIds = [person.id]
          await applyAndSearch(filter)
        }
      }
    case .places:
      var filter = currentFilter()
      filter.local.city = suggestion
      Task { await applyAndSearch(filter) }
    case .camera:
      make = suggestion
      Task { await runSearch() }
    case .lens:
      var filter = currentFilter()
      filter.local.lensModel = suggestion
      Task { await applyAndSearch(filter) }
    case .fileType:
      var filter = currentFilter()
      filter.local.fileExtensions = [suggestion]
      Task { await applyAndSearch(filter) }
    }
  }

  private func applyAndSearch(_ filter: SearchFilter) async {
    query = filter.query
    make = filter.local.make ?? ""
    favoritesOnly = filter.local.isFavorite ?? false
    hasLocation = filter.local.hasLocation
    mediaType = filter.local.mediaType
    scope = filter.scope
    await runSearch()
  }

  private func loadRecents() async {
    guard let userId = state.userId else { return }
    recents = (try? await RecentSearchStore(store: state.store, userId: userId).recents()) ?? []
  }

  private static func dateString(_ date: Date?) -> String {
    guard let date else { return "" }
    return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
  }
}

/// macOS all-metadata browser (A7 task 1) for `MacInfoPanel`: grouped DisclosureGroups with a
/// filter field; per-row context menu copies the value or the `Group:Tag` name via NSPasteboard.
struct MacFullExifBrowser: View {
  var assetId: String
  var state: MacAppState

  @State private var exif: FullExif?
  @State private var searchText = ""
  @State private var loadError: String?

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
          Button("Copy value") { NSPasteboard.general.setString(text, forType: .string) }
        }
        Button("Copy tag name") {
          NSPasteboard.general.setString("\(group):\(key)", forType: .string)
        }
      }
  }

  private func load() async {
    if let cached = await Self.cache.cached(assetId: assetId) {
      exif = cached
      return
    }
    do {
      let tokenStore = state.connection.tokenStore
      let service = SearchService(
        baseURL: state.serverURL,
        tokenProvider: { @Sendable in await tokenStore.get() },
        fullExifCache: Self.cache)
      exif = try await service.fullExif(assetId: assetId)
    } catch {
      loadError = "Full metadata unavailable (\(error.localizedDescription))."
    }
  }
}
