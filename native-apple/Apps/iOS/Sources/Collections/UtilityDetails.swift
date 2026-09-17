import CoreModel
import LocalStore
import SwiftUI

// MARK: - utility + media-type detail screens (WP4 §4)

// Utilities and media types get a simple large title plus the grid (no hero).
// Every screen resolves ids in its own `.task` (caller order kept) and reloads on
// pull-to-refresh; limits are raised far above the row-query defaults so the grid
// behind a count of N actually shows N items (P9: counts and grids must agree).
private let detailLimit = 100_000

struct FavoritesDetailView: View {
  @EnvironmentObject var session: AppSession
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: "Favorites", ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let scope = try? await session.timelineScope()
    else { return }
    ids = (try? await store.favoriteAssets(scope: scope, limit: detailLimit).map(\.id)) ?? []
  }
}

struct RecentsDetailView: View {
  @EnvironmentObject var session: AppSession
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: "Recently Saved", ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let scope = try? await session.timelineScope()
    else { return }
    ids = (try? await store.recentAssets(scope: scope, limit: detailLimit).map(\.id)) ?? []
  }
}

struct MediaTypeDetailView: View {
  @EnvironmentObject var session: AppSession
  var collection: NativeMediaCollection
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: collection.title, ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let scope = try? await session.timelineScope()
    else { return }
    ids = (try? await store.mediaAssets(scope: scope, collection: collection, limit: detailLimit).map(\.id)) ?? []
  }
}

struct TrashDetailView: View {
  @EnvironmentObject var session: AppSession
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: "Recently Deleted", ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let manage = try? await session.manageScope()
    else { return }
    ids = (try? await store.trashedAssets(scope: manage, limit: detailLimit).map(\.id)) ?? []
  }
}

struct HiddenDetailView: View {
  @EnvironmentObject var session: AppSession
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: "Hidden", ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let manage = try? await session.manageScope()
    else { return }
    ids = (try? await store.visibilityAssets(.hidden, scope: manage, limit: detailLimit).map(\.id)) ?? []
  }
}

struct ArchiveDetailView: View {
  @EnvironmentObject var session: AppSession
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: "Archive", ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let manage = try? await session.manageScope()
    else { return }
    ids = (try? await store.visibilityAssets(.archive, scope: manage, limit: detailLimit).map(\.id)) ?? []
  }
}

struct CapturedByMeDetailView: View {
  @EnvironmentObject var session: AppSession
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: "Captured by Me", ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let manage = try? await session.manageScope()
    else { return }
    ids = (try? await store.capturedByUser(session.userId, scope: manage, limit: detailLimit).map(\.id)) ?? []
  }
}

struct LockedDetailView: View {
  @EnvironmentObject var session: AppSession
  @State private var ids: [String]?
  @State private var denied = false

  var body: some View {
    Group {
      if denied {
        ContentUnavailableView(
          "Locked Is Unavailable", systemImage: "lock.fill",
          description: Text("Authentication failed."))
      } else {
        IdListDetail(title: "Locked", ids: ids)
      }
    }
    .task { await load() }
  }

  private func load() async {
    guard await LockedMediaAuthentication.authenticate() else {
      denied = true
      return
    }
    guard let store = session.store else { return }
    ids = (try? await store.lockedAssets(currentUserId: session.userId, limit: detailLimit).map(\.id)) ?? []
  }
}

struct CameraModelDetailView: View {
  @EnvironmentObject var session: AppSession
  var model: String
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: model, ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let manage = try? await session.manageScope()
    else { return }
    ids = (try? await store.assets(cameraModel: model, scope: manage, limit: detailLimit).map(\.id)) ?? []
  }
}

struct CameraCategoryDetailView: View {
  @EnvironmentObject var session: AppSession
  var category: CameraCategory
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: category.name, ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let manage = try? await session.manageScope()
    else { return }
    var assets: [Asset] = []
    for model in category.models {
      assets += (try? await store.assets(cameraModel: model, scope: manage, limit: detailLimit)) ?? []
    }
    ids = assets
      .sorted { ($0.localDateTime ?? .distantPast) > ($1.localDateTime ?? .distantPast) }
      .map(\.id)
  }
}

struct DayDetailView: View {
  @EnvironmentObject var session: AppSession
  var day: DayTileData
  @State private var ids: [String]?

  var body: some View {
    IdListDetail(title: day.label, ids: ids)
      .task { await load() }
      .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store,
      let scope = try? await session.timelineScope()
    else { return }
    ids = (try? await store.dayAssetIds(scope: scope, dayKey: day.key)) ?? []
  }
}
