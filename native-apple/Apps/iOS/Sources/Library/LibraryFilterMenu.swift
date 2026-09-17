import SwiftUI

// MARK: - library filter menu (WP2 §2, spec native-06/07/08)

// The trailing-toolbar filter menu (`line.3.horizontal.decrease`, native glass).
// Sections mirror native: Sort (two large buttons), Filter: (checkmarks), Media
// Types ▸, Library View ▸ (absorbs the old top-left switcher), View Options ▸.
// Every row carries a stable label for the fixture UI tests.

struct LibraryFilterMenu: View {
  @EnvironmentObject var session: AppSession
  @Binding var sort: LibrarySort
  @Binding var filter: LibraryFilterItem
  @Binding var kinds: Set<LibraryMediaKind>
  @Binding var source: LibrarySource
  @Binding var aspectFit: Bool
  @Binding var hideScreenshots: Bool
  @Binding var hideSharedWithYou: Bool
  var onZoomIn: () -> Void
  var onZoomOut: () -> Void
  var onShowSources: () -> Void

  // Flat groups, not nested submenus: a `Menu`-in-`Menu` drill-in row is not
  // exposed to XCUITest (the submenu never opens under test), and `Section`
  // content is not exposed either — so every item sits one level deep as a
  // plain `Button`, separated by dividers (see WP2 report).
  var body: some View {
    Menu {
      sortSection
      Divider()
      filterSection
      Divider()
      mediaTypesSection
      Divider()
      libraryViewSection
      Divider()
      viewOptionsSection
    } label: {
      Label("Filter", systemImage: "line.3.horizontal.decrease")
    }
    .accessibilityIdentifier("library-filter-menu")
  }

  // MARK: - Sort

  private var sortSection: some View {
    Group {
      ForEach([LibrarySort.added, .captured], id: \.self) { option in
        Button {
          sort = option
        } label: {
          Label(
            option.title,
            systemImage: sort == option ? "checkmark" : "minus")
        }
        .accessibilityIdentifier("sort-\(option.rawValue)")
      }
    }
  }

  // MARK: - Filter:

  private var filterSection: some View {
    Group {
      ForEach(LibraryFilterItem.allCases, id: \.self) { item in
        Button {
          filter = item
        } label: {
          if filter == item {
            Label(item.title, systemImage: "checkmark")
          } else {
            Text(item.title)
          }
        }
        .accessibilityIdentifier("filter-\(filterAccessibilityName(item))")
      }
    }
  }

  // MARK: - Media Types

  private var mediaTypesSection: some View {
    Group {
      ForEach(LibraryMediaKind.allCases, id: \.self) { kind in
        Button {
          if kinds.contains(kind) {
            kinds.remove(kind)
          } else {
            kinds.insert(kind)
          }
        } label: {
          if kinds.contains(kind) {
            Label(kind.title, systemImage: "checkmark")
          } else {
            Text(kind.title)
          }
        }
        .accessibilityIdentifier("mediatype-\(kind.rawValue)")
      }
    }
  }

  // MARK: - Library View (replaces the top-left switcher)

  private var libraryViewSection: some View {
    Group {
      libraryRow(title: "Both Libraries", source: .all, id: "both")
      libraryRow(title: "Personal Library", source: .personal, id: "personal")
      ForEach(session.spaces) { space in
        libraryRow(title: space.name, source: .space(space.id), id: "space-\(space.id)")
      }
      ForEach(session.libraries) { library in
        libraryRow(title: library.name, source: .library(library.id), id: "library-\(library.id)")
      }
      Button("Show in Timeline…") { onShowSources() }
        .accessibilityIdentifier("libraryview-show-in-timeline")
    }
  }

  private func libraryRow(title: String, source: LibrarySource, id: String) -> some View {
    Button {
      self.source = source
    } label: {
      if self.source == source {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
    .accessibilityIdentifier("libraryview-\(id)")
  }

  // MARK: - View Options

  private var viewOptionsSection: some View {
    Group {
      Button("Zoom In") { onZoomIn() }
        .accessibilityIdentifier("viewoptions-zoom-in")
      Button("Zoom Out") { onZoomOut() }
        .accessibilityIdentifier("viewoptions-zoom-out")
      Button {
        aspectFit.toggle()
      } label: {
        if aspectFit {
          Label("Aspect Ratio Grid", systemImage: "checkmark")
        } else {
          Text("Aspect Ratio Grid")
        }
      }
      .accessibilityIdentifier("viewoptions-aspect-fit")
      Button {
        hideScreenshots.toggle()
      } label: {
        Text("Show Screenshots")
        if !hideScreenshots {
          Image(systemName: "checkmark")
        }
      }
      .accessibilityIdentifier("viewoptions-show-screenshots")
      Button {
        hideSharedWithYou.toggle()
      } label: {
        Text("Show Shared with You")
        if !hideSharedWithYou {
          Image(systemName: "checkmark")
        }
      }
      .accessibilityIdentifier("viewoptions-show-shared")
    }
  }
}

private func filterAccessibilityName(_ item: LibraryFilterItem) -> String {
  switch item {
  case .all: return "all-items"
  case .favorites: return "favorites"
  case .edited: return "edited"
  case .sharedWithYou: return "shared-with-you"
  case .capturedByMe: return "captured-by-me"
  case .notInAlbum: return "not-in-album"
  }
}
