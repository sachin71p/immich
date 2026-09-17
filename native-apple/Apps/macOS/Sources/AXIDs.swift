import Foundation

/// Accessibility identifier contract shared by the app and its tests (WP-T,
/// TEST-PLAN T3). UI tests must use only these — never labels or coordinates.
///
/// Feature WPs add `.accessibilityIdentifier(AXIDs.…)` calls in their own view
/// files; this file publishes the constants. Identifiers already in use by the
/// committed suite predate the contract and are remapped by their owning WPs.
enum AXIDs {
  // MARK: - sidebar

  static let sidebar = "sidebar"

  static func sidebarDestination(_ name: String) -> String { "sidebar.\(name)" }

  static let sidebarLibrary = "sidebar.library"
  static let sidebarCollections = "sidebar.collections"
  static let sidebarSearch = "sidebar.search"
  static let sidebarFavorites = "sidebar.favorites"
  static let sidebarRecentlySaved = "sidebar.recently-saved"
  static let sidebarMap = "sidebar.map"
  static let sidebarPeople = "sidebar.people"
  static let sidebarMemories = "sidebar.memories"
  static let sidebarPhotos = "sidebar.photos"
  static let sidebarVideos = "sidebar.videos"
  static let sidebarScreenshots = "sidebar.screenshots"
  static let sidebarAllAlbums = "sidebar.all-albums"
  static let sidebarImports = "sidebar.imports"
  static let sidebarRecentlyDeleted = "sidebar.recently-deleted"
  static let sidebarDuplicates = "sidebar.duplicates"
  static let sidebarCapturedByMe = "sidebar.captured-by-me"
  static let sidebarHidden = "sidebar.hidden"
  static let sidebarArchive = "sidebar.archive"
  static let sidebarLocked = "sidebar.locked"

  static func sidebarSpace(_ spaceId: String) -> String { "sidebar.space.\(spaceId)" }
  static func sidebarSharedLibrary(_ libraryId: String) -> String { "sidebar.sharedLibrary.\(libraryId)" }
  static func sidebarAlbum(_ albumId: String) -> String { "sidebar.album.\(albumId)" }

  // MARK: - toolbar

  static func toolbarItem(_ name: String) -> String { "toolbar.\(name)" }

  static let toolbarSidebarToggle = "toolbar.sidebarToggle"
  static let toolbarScope = "toolbar.scope"
  static let toolbarZoom = "toolbar.zoom"
  static let toolbarGrouping = "toolbar.grouping"
  static let toolbarFilter = "toolbar.filter"
  static let toolbarSort = "toolbar.sort"
  static let toolbarMore = "toolbar.more"
  static let toolbarInfo = "toolbar.info"
  static let toolbarShare = "toolbar.share"
  static let toolbarFavorite = "toolbar.favorite"
  static let toolbarRotate = "toolbar.rotate"
  static let toolbarEdit = "toolbar.edit"
  static let toolbarSearch = "toolbar.search"
  static let toolbarSync = "toolbar.sync"

  // MARK: - grid

  static let grid = "asset-grid"

  static func gridCell(_ assetId: String) -> String { "grid.cell.\(assetId)" }
  static func gridYearCard(_ year: Int) -> String { "grid.yearCard.\(year)" }
  static func gridMonthCard(year: Int, month: Int) -> String {
    String(format: "grid.monthCard.%04d-%02d", year, month)
  }

  // MARK: - viewer

  static let viewer = "viewer"

  static func viewerPage(_ assetId: String) -> String { "viewer.page.\(assetId)" }
  static let viewerZoomSlider = "viewer.zoomSlider"
  static let viewerTitle = "viewer.title"
  static let viewerSubtitle = "viewer.subtitle"
  static let viewerChevronPrev = "viewer.chevron.prev"
  static let viewerChevronNext = "viewer.chevron.next"
  static let viewerVideoTime = "viewer.video.time"

  // MARK: - inspector / edit

  static let inspector = "inspector"
  static let editMode = "edit.mode"

  static func editTab(_ name: String) -> String { "edit.tab.\(name)" }
  static let editDone = "edit.done"
  static let editCancel = "edit.cancel"

  // MARK: - connect (WP-F F3: signed-in launch never shows the form)

  static let connectForm = "connect.form"

  // MARK: - collections / search

  static func collectionsShelf(_ name: String) -> String { "collections.shelf.\(name)" }
  static let searchField = "search.field"
  static let searchResults = "search.results"
}
