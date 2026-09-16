import CoreModel
import LocalStore
import Media
import SwiftUI

// MARK: - SwiftUI host (interim: bridges LibraryGridModel onto the WP1 setters)

/// Interim wrapper keeping LibraryView/SearchView compiling until step 9 swaps them onto
/// `AssetGridView`. Translates the hydrated model into a `GridSnapshot` (sections from
/// buckets, titles from key shape) and drives only the cheap setters — no unconditional
/// render path. Removed in step 9.
struct PhotoGridView: UIViewControllerRepresentable {
  var model: LibraryGridModel
  var columns: Int
  var squareCells: Bool
  var editMode: Bool
  var selectedIds: Set<String>
  var pipeline: MediaPipeline?
  var onTap: (String) -> Void
  var onSelectionChange: (Set<String>) -> Void
  var onPrefetch: ([String]) -> Void
  var onPinchColumns: (Int) -> Void
  /// S1: pull-to-refresh handler. Defaulted to nil so non-Library grids (e.g. Search results)
  /// keep compiling unchanged and get no refresh control behavior.
  var onRefresh: (() async -> Void)? = nil
  /// Date-scrubber section index; the VC scrolls only when this value changes.
  var scrubSection: Int

  func makeUIViewController(context: Context) -> PhotoGridViewController {
    let vc = PhotoGridViewController()
    vc.onTap = { onTap($0) }
    vc.onSelectionChange = { onSelectionChange($0) }
    vc.onPrefetch = { onPrefetch($0) }
    vc.onPinchColumns = { onPinchColumns($0) }
    vc.onRefresh = onRefresh
    vc.pipeline = pipeline
    return vc
  }

  func updateUIViewController(_ vc: PhotoGridViewController, context: Context) {
    vc.pipeline = pipeline
    vc.onRefresh = onRefresh
    vc.rowProvider = { [model] in model.rowsById[$0] }
    vc.dateProvider = { [model] in model.rowsById[$0]?.localDateTime }
    // Old `squareCells == false` (aspect mode) ≈ aspect-fit rendering on square cells.
    vc.setAspectFit(!squareCells)
    vc.setColumns(columns, animated: false)
    vc.setEditMode(editMode)
    vc.applySnapshot(Self.snapshot(for: model), animating: false)
    vc.setSelection(selectedIds)
    vc.scrollToSection(scrubSection, animated: false)
  }

  private static var generation = 0

  private static func snapshot(for model: LibraryGridModel) -> GridSnapshot {
    generation += 1
    var sections: [GridSnapshot.Section] = []
    var indexById: [String: IndexPath] = [:]
    var allIds: [String] = []
    for (sectionOffset, bucket) in model.buckets.enumerated() {
      let ids = model.rowIdsByBucket[bucket.key] ?? []
      for (itemOffset, id) in ids.enumerated() {
        indexById[id] = IndexPath(item: itemOffset, section: sectionOffset)
      }
      allIds.append(contentsOf: ids)
      sections.append(
        GridSnapshot.Section(
          key: bucket.key, title: title(for: bucket.key), ids: ids,
          startDate: nil, endDate: nil))
    }
    return GridSnapshot(
      generation: generation, sections: sections, indexById: indexById, allIds: allIds)
  }

  private static func title(for key: String) -> String {
    switch key.count {
    case 4: return GridSnapshot.title(for: key, granularity: .year)
    case 7: return GridSnapshot.title(for: key, granularity: .month)
    case 10: return GridSnapshot.title(for: key, granularity: .day)
    default: return key
    }
  }
}
