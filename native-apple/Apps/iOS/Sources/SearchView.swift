import CoreModel
import LocalStore
import Media
import Rules
import Search
import SwiftUI
import UIKit

/// Search screen (A7 task 2): smart query + metadata filters + library scope selector, suggestion
/// chips, recent searches, and a results grid reusing the A3 `PhotoGridView` (same view that
/// backs the library, fed a single "Results" bucket). Offline instant results come from the
/// LocalStore exif mirror; a text query (or tags) also fans out to server smart/metadata search.
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
  @State private var isSearching = false
  @State private var searchError: String?
  @State private var hasSearched = false
  @State private var recents: [SearchFilter] = []
  @State private var chip: SuggestionKind? = nil
  @State private var suggestions: [String] = []
  @State private var viewerRequest: ViewerRequest?

  var body: some View {
    NavigationStack {
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
      .fullScreenCover(item: $viewerRequest) { request in
        ViewerView(ids: request.ids, initialId: request.initialId)
      }
      .task { await loadRecents() }
    }
    .accessibilityIdentifier("search-view")
  }

  // MARK: - search field + scope

  private var searchField: some View {
    HStack {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField("Search photos", text: $query)
        .textInputAutocapitalization(.never)
        .accessibilityIdentifier("search-field")
        .onSubmit { Task { await runSearch() } }
      if !query.isEmpty {
        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
          .foregroundStyle(.secondary)
      }
      Button("Search") { Task { await runSearch() } }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("search-submit")
    }
    .padding(.horizontal)
    .padding(.top, 8)
  }

  private var scopePicker: some View {
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
    .pickerStyle(.menu)
    .padding(.horizontal)
    .padding(.vertical, 8)
    .accessibilityIdentifier("search-scope")
    .onChange(of: scope) { _, _ in
      if hasSearched { Task { await runSearch() } }
    }
  }

  // MARK: - idle: chips, suggestions, recents, filters

  private var idleContent: some View {
    List {
      Section("Suggestions") {
        chipRow
        if chip != nil {
          if suggestions.isEmpty {
            Text("No suggestions").font(.caption).foregroundStyle(.secondary)
          } else {
            ForEach(suggestions, id: \.self) { suggestion in
              Button { applySuggestion(suggestion) } label: {
                HStack {
                  Text(suggestion)
                  Spacer()
                  Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
      filtersSection
      if !recents.isEmpty {
        Section("Recent searches") {
          ForEach(Array(recents.enumerated()), id: \.offset) { _, recent in
            Button { applyRecent(recent) } label: {
              Text(recentLabel(recent)).lineLimit(1)
            }
          }
          Button("Clear", role: .destructive) {
            Task {
              guard let store = session.store else { return }
              try? await RecentSearchStore(store: store, userId: session.userId).clear()
              await loadRecents()
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  private var chipRow: some View {
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
  }

  private var filtersSection: some View {
    DisclosureGroup("Filters") {
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
      Button("Apply filters") { Task { await runSearch() } }
        .accessibilityIdentifier("search-apply-filters")
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
        // WP5 moves search onto its own screen; until then results reuse AssetGridView
        // with an explicit id list (server relevance order preserved).
        AssetGridView(
          source: .ids(resultIds),
          store: session.store,
          pipeline: session.pipeline,
          columns: $resultColumns,
          onOpen: { route in
            viewerRequest = ViewerRequest(ids: route.resolveIds(), initialId: route.startId)
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
      if filter.wantsServerSearch, !session.isFixture, let serverURL = session.serverURL {
        let tokenStore = session.connection?.tokenStore
        let service = SearchService(
          baseURL: serverURL,
          tokenProvider: { @Sendable in await tokenStore?.get() })
        do {
          let ids = try await service.searchIds(filter: filter)
          // Server order is relevance order — the grid pages rows itself via assetsLite.
          setIds(ids)
        } catch {
          // Server failed (offline, 4xx): fall back to the local rows already computed.
          setIds(localRows.map(\.id))
          searchError = "Server search unavailable — showing offline results."
        }
      } else {
        setIds(localRows.map(\.id))
      }
      hasSearched = true
      try? await RecentSearchStore(store: store, userId: session.userId).record(filter)
      await loadRecents()
    } catch {
      searchError = error.localizedDescription
      hasSearched = true
    }
  }

  @MainActor
  private func setIds(_ ids: [String]) {
    resultIds = ids
    searchToken += 1
  }

  // MARK: - suggestions + recents

  private func loadSuggestions() async {
    guard let kind = chip, let store = session.store else {
      suggestions = []
      return
    }
    if kind.serverType == nil {
      // People: no server suggestion variant — serve names from the local mirror.
      let mine = (try? await store.peopleForOwner(session.userId)) ?? []
      suggestions = mine.map(\.name).sorted()
      return
    }
    guard !session.isFixture, let serverURL = session.serverURL else {
      suggestions = []
      return
    }
    let tokenStore = session.connection?.tokenStore
    let service = SearchService(
      baseURL: serverURL, tokenProvider: { @Sendable in await tokenStore?.get() })
    suggestions = (try? await service.suggestions(kind: kind, scope: scope)) ?? []
  }

  private func applySuggestion(_ suggestion: String) {
    guard let kind = chip else { return }
    switch kind {
    case .people:
      Task {
        guard let store = session.store else { return }
        let mine = (try? await store.peopleForOwner(session.userId)) ?? []
        if let person = mine.first(where: { $0.name == suggestion }) {
          var filter = currentFilter()
          filter.local.personIds = [person.id]
          await applyAndSearch(filter)
        }
      }
    case .places:
      var filter = currentFilter()
      filter.local.city = suggestion
      query = ""
      Task { await applyAndSearch(filter) }
    case .camera:
      make = suggestion
      Task { await runSearch() }
    case .lens:
      lens = suggestion
      Task { await runSearch() }
    case .fileType:
      var filter = currentFilter()
      filter.local.fileExtensions = [suggestion]
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

  private func loadRecents() async {
    guard let store = session.store else { return }
    recents = (try? await RecentSearchStore(store: store, userId: session.userId).recents()) ?? []
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
