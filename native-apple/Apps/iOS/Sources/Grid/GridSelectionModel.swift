import Combine

// MARK: - grid selection model (WP1 §8, W2 contract)

/// Selection state shared between `AssetGridView` and its host screen (WP2's select
/// mode, WP4's album grids). A reference type so the UIKit controller and any number of
/// SwiftUI hosts read the same truth without copying id sets through view updates.
///
/// Main-thread confined by convention (every writer — the VC delegate, the host screen —
/// runs on the main actor); deliberately not `@MainActor`-isolated so SwiftUI view
/// initializers can hold the reference without an isolation hop.
final class GridSelectionModel: ObservableObject {
  /// Selected asset ids.
  @Published var ids = Set<String>()
  /// Whether the grid shows selection affordances (drives `setEditMode`, never a
  /// snapshot or layout reset).
  @Published var isSelecting = false

  func clear() {
    ids = []
  }
}
