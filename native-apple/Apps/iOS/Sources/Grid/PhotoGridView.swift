import Media
import SwiftUI

// MARK: - SwiftUI host

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
    return vc
  }

  func updateUIViewController(_ vc: PhotoGridViewController, context: Context) {
    vc.model = model
    vc.columns = columns
    vc.squareCells = squareCells
    vc.editMode = editMode
    vc.pipeline = pipeline
    vc.onRefresh = onRefresh
    vc.render()
    vc.setSelected(selectedIds)
    vc.scrollToScrubSection(scrubSection)
  }
}
