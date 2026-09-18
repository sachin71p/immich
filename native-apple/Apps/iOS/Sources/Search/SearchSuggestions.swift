import CoreModel
import Foundation
import LocalStore
import Search

/// Local-first suggestion loading for the Search screen (WP5 S2a).
///
/// Server `search/suggestions` returns `[]` whenever the app is offline or in fixture
/// mode, which used to leave every non-people chip reading "No suggestions". The
/// mirror answers all five kinds locally; the server is only a fallback when the
/// local answer is empty (a fresh account with no exif yet).
@MainActor
enum SearchSuggestionLoader {
  static func suggestions(
    for kind: SuggestionKind, session: AppSession, uiScope: SearchScope
  ) async -> [String] {
    if let local = try? await localSuggestions(for: kind, session: session), !local.isEmpty {
      return local
    }
    guard !session.isFixture, let serverURL = session.serverURL else { return [] }
    let service = SearchService(
      baseURL: serverURL, tokenProvider: session.searchTokenProvider())
    return (try? await service.suggestions(kind: kind, scope: uiScope)) ?? []
  }

  /// All five kinds at once for the idle suggestion pills. One scope query total.
  static func allSuggestions(
    session: AppSession, uiScope: SearchScope
  ) async -> [SuggestionKind: [String]] {
    var out: [SuggestionKind: [String]] = [:]
    for kind in SuggestionKind.allCases {
      out[kind] = await suggestions(for: kind, session: session, uiScope: uiScope)
    }
    return out
  }

  private static func localSuggestions(
    for kind: SuggestionKind, session: AppSession
  ) async throws -> [String] {
    guard let store = session.store else { return [] }
    let scope = try await session.timelineScope()
    switch kind {
    case .people:
      return try await store.namedPeople(forOwner: session.userId).map(\.name).sorted()
    case .places:
      return try await store.distinctCities(scope: scope)
    case .camera:
      // Server `camera-make` chips carry makes, so the local chips do too (unique,
      // most-photographed first). Tapping one sets the `make` filter.
      var seen = Set<String>()
      return try await store.cameraModels(scope: scope).compactMap { model -> String? in
        guard let make = model.make, !make.isEmpty, seen.insert(make).inserted else { return nil }
        return make
      }
    case .lens:
      return try await store.distinctLensModels(scope: scope)
    case .fileType:
      return try await store.distinctFileExtensions(scope: scope)
    }
  }
}
