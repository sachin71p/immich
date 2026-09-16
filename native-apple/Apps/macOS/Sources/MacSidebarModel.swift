import CoreModel
import Foundation
import LocalStore
import Rules

/// Every sidebar destination in the Photos-for-Mac style shell (brief task 1).
/// Navigation state only — the view layer maps each case to a store query + grid configuration.
public enum SidebarDestination: Sendable, Hashable {
  case library
  case collections
  case search
  case favorites
  case recentlySaved
  case map
  case people
  case memories
  case mediaPhotos
  case mediaVideos
  case mediaScreenshots
  case media(NativeMediaCollection)
  case space(String)
  case externalLibrary(String)
  case album(String)
  case allAlbums
  case imports
  case recentlyDeleted
  case duplicates
  case capturedByMe
  case camera(String)
  case hidden
  case archive
  case locked

  public var title: String {
    switch self {
    case .library: return "Library"
    case .collections: return "Collections"
    case .search: return "Search"
    case .favorites: return "Favorites"
    case .recentlySaved: return "Recently Saved"
    case .map: return "Map"
    case .people: return "People"
    case .memories: return "Memories"
    case .mediaPhotos: return "Photos"
    case .mediaVideos: return "Videos"
    case .mediaScreenshots: return "Screenshots"
    case .media(let collection): return collection.title
    case .space: return "Shared Library"
    case .externalLibrary: return "External Library"
    case .album: return "Album"
    case .allAlbums: return "All Albums"
    case .imports: return "Imports"
    case .recentlyDeleted: return "Recently Deleted"
    case .duplicates: return "Duplicates"
    case .capturedByMe: return "Captured by Me"
    case .camera(let model): return model
    case .hidden: return "Hidden"
    case .archive: return "Archive"
    case .locked: return "Locked"
    }
  }

  /// Resolved display title (U24/U25): `.space`/`.album`/`.externalLibrary` carry only an
  /// id, so the toolbar and window title resolve the live name from app state, falling back to
  /// the generic label when the entry hasn't synced yet. Main-actor: state is `@Observable`.
  @MainActor
  func title(in state: MacAppState) -> String {
    switch self {
    case .space(let id):
      return state.spaces.first { $0.space.id == id }?.space.name ?? title
    case .album(let id):
      return state.albums.first { $0.album.id == id }?.album.name ?? title
    case .externalLibrary(let id):
      return state.libraries.first { $0.library.id == id }?.library.name ?? title
    default:
      return title
    }
  }

  /// Destinations that render the timeline grid (full grid toolbar). Map, People, Memories,
  /// Collections, Search, All Albums and Duplicates render their own views with a minimal
  /// toolbar (U15/U16/U18).
  public var usesGridToolbar: Bool {
    switch self {
    case .map, .people, .memories, .collections, .search, .allAlbums, .duplicates:
      return false
    default:
      return true
    }
  }

  /// Empty-state copy for grid destinations (U23): shown when the snapshot is empty and the
  /// loader phase is `.loaded`. Nil for destinations with their own views.
  @MainActor
  func emptyState(in state: MacAppState) -> (title: String, message: String, symbol: String)? {
    switch self {
    case .library, .collections:
      return ("No Photos", "Your library is empty.", "photo")
    case .favorites:
      return ("No Favorites", "Click ♡ on a photo to add it.", "heart")
    case .recentlySaved:
      return ("No Recent Saves", "Newly saved photos will appear here.", "tray.and.arrow.down")
    case .mediaPhotos:
      return ("No Photos", "No photos in this view.", "photo")
    case .mediaVideos:
      return ("No Videos", "No videos in this view.", "video")
    case .mediaScreenshots:
      return ("No Screenshots", "No screenshots in this view.", "camera.viewfinder")
    case .media(let collection):
      return ("No \(collection.title)", "Nothing here yet.", collection.systemImage)
    case .space(let id):
      let name = state.spaces.first { $0.space.id == id }?.space.name ?? "shared library"
      return ("No Items", "No items in \(name) yet.", "person.2.circle")
    case .externalLibrary(let id):
      let name = state.libraries.first { $0.library.id == id }?.library.name ?? "external library"
      return ("No Items", "No items in \(name) yet.", "externaldrive")
    case .album(let id):
      let name = state.albums.first { $0.album.id == id }?.album.name ?? "this album"
      return ("Empty Album", "No photos in \(name) yet.", "rectangle.stack")
    case .imports:
      return ("No Imports", "Imported files will appear here.", "square.and.arrow.down")
    case .recentlyDeleted:
      return ("Trash Is Empty", "Deleted items appear here for 30 days.", "trash")
    case .capturedByMe:
      return ("No Photos by You", "Photos you captured will appear here.", "person.crop.circle.badge.checkmark")
    case .camera(let model):
      return ("No Photos", "No photos captured with \(model) yet.", "camera")
    case .hidden:
      return ("No Hidden Photos", "Hidden photos will appear here.", "eye.slash")
    case .archive:
      return ("No Archived Photos", "Archived photos will appear here.", "archivebox")
    case .locked:
      return ("Locked", "Unlock to view locked photos.", "lock")
    case .map, .people, .memories, .search, .allAlbums, .duplicates:
      return nil
    }
  }

  /// SF Symbol per destination (system components only — A0 Architecture, App Review 5.2.5).
  public var systemImage: String {
    switch self {
    case .library: return "photo.on.rectangle"
    case .collections: return "rectangle.grid.2x2"
    case .search: return "magnifyingglass"
    case .favorites: return "heart"
    case .recentlySaved: return "tray.and.arrow.down"
    case .map: return "map"
    case .people: return "person.2"
    case .memories: return "clock"
    case .mediaPhotos: return "photo"
    case .mediaVideos: return "video"
    case .mediaScreenshots: return "camera.viewfinder"
    case .media(let collection): return collection.systemImage
    case .space: return "person.2.circle"
    case .externalLibrary: return "externaldrive"
    case .album: return "rectangle.stack"
    case .allAlbums: return "rectangle.stack"
    case .imports: return "square.and.arrow.down"
    case .recentlyDeleted: return "trash"
    case .duplicates: return "rectangle.on.rectangle"
    case .capturedByMe: return "person.crop.circle.badge.checkmark"
    case .camera: return "camera"
    case .hidden: return "eye.slash"
    case .archive: return "archivebox"
    case .locked: return "lock"
    }
  }
}

/// Which store query backs a destination, so the grid view stays a thin switch over this enum.
/// DECISIONS §10: every purpose resolves through `TimelineScope` unless noted.
public enum DestinationQuery: Sendable, Hashable {
  /// Main timeline scope (explicit filter overrides prefs — DECISIONS §9).
  case timeline(ExplicitContainerFilter?)
  case favorites(ExplicitContainerFilter?)
  case recents(ExplicitContainerFilter?)
  case media(TimelineMediaKind, ExplicitContainerFilter?)
  case mediaCollection(NativeMediaCollection, ExplicitContainerFilter?)
  case album(String)
  case trash
  case hidden
  case archive
  case locked
  case imports
  case capturedByMe
  case camera(String)
  case map
  case people
  case memories
  case search
}

extension SidebarDestination {
  public var query: DestinationQuery {
    switch self {
    case .library: return .timeline(nil)
    case .collections: return .timeline(nil)
    case .search: return .search
    case .favorites: return .favorites(nil)
    case .recentlySaved: return .recents(nil)
    case .map: return .map
    case .people: return .people
    case .memories: return .memories
    case .mediaPhotos: return .media(.photo, nil)
    case .mediaVideos: return .media(.video, nil)
    case .mediaScreenshots: return .media(.screenshot, nil)
    case .media(let collection): return .mediaCollection(collection, nil)
    case .space(let id): return .timeline(.space(id))
    case .externalLibrary(let id): return .timeline(.library(id))
    case .album(let id): return .album(id)
    case .allAlbums: return .search
    case .imports: return .imports
    case .recentlyDeleted: return .trash
    case .duplicates: return .search
    case .capturedByMe: return .capturedByMe
    case .camera(let model): return .camera(model)
    case .hidden: return .hidden
    case .archive: return .archive
    case .locked: return .locked
    }
  }

  /// Dropping assets on an album adds them; dropping on a library/space moves them
  /// (with a confirm dialog) — brief task 1.
  public enum DropAction: Sendable, Hashable {
    case addToAlbum(String)
    case moveTo(MoveTarget)
    case none
  }

  public var dropAction: DropAction {
    switch self {
    case .album(let id): return .addToAlbum(id)
    case .space(let id): return .moveTo(.space(id))
    case .externalLibrary(let id): return .moveTo(.library(id))
    case .library: return .moveTo(.personal)
    default: return .none
    }
  }
}

/// The library-switcher popup options (same options as iOS — brief task 2).
public enum LibraryFilterOption: Sendable, Hashable {
  case all
  case personalOnly
  case space(String)
  case library(String)

  public var explicitFilter: ExplicitContainerFilter? {
    switch self {
    case .all: return nil
    case .personalOnly: return .personalOnly
    case .space(let id): return .space(id)
    case .library(let id): return .library(id)
    }
  }
}

/// Years / Months / All Photos segmented control — brief task 2.
public enum TimelineGrouping: String, Sendable, Hashable, CaseIterable {
  case years
  case months
  case all

  /// Years/Months page through month buckets; All Photos flattens every bucket newest-first.
  public var showsBucketHeaders: Bool {
    switch self {
    case .years, .months: return true
    case .all: return false
    }
  }

  /// Years groups month buckets (`yyyy-MM`) under year headers client-side.
  public var groupsByYear: Bool { self == .years }
}

/// Desktop timeline ordering for the native-style sort control: unified on
/// `CoreModel.TimelineOrder` (the app's old `String`-backed copy is deleted — nothing
/// persisted the raw value). `Equatable` is spelled out here until PhotosCore adds it,
/// so the sort menu can compare selections.
extension TimelineOrder: Equatable {
  public static func == (lhs: TimelineOrder, rhs: TimelineOrder) -> Bool {
    switch (lhs, rhs) {
    case (.newestFirst, .newestFirst), (.oldestFirst, .oldestFirst):
      return true
    case (.newestFirst, .oldestFirst), (.oldestFirst, .newestFirst):
      return false
    }
  }
}
