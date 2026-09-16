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

/// Desktop timeline ordering for the native-style sort control.
public enum TimelineOrder: String, Sendable, Hashable {
  case newestFirst
  case oldestFirst
}
