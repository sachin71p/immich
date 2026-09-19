import AppKit
import SnapshotTesting
import XCTest

/// WP-T T2 sample: snapshot scaffolding over synthetic fixture media only —
/// never personal photos. Baselines live in `Tests/__Snapshots__/` and include
/// the OS major version in the file name (handled by SnapshotTesting).
/// Re-record deliberately with `SNAPSHOT_RECORD=1` and review the diff.
/// Runs via `verify.sh mac-unit`.
final class FixtureSnapshotTests: XCTestCase {
  /// The pipeline check: an `NSImageView` rendering deterministic fixture bytes
  /// at the T2 reference sizes. Feature WPs add per-view snapshots beside this.
  func testFixtureThumbnailView() {
    let data = FixtureMedia.pngData(seed: "asset-base-beach-1", width: 512, height: 384)
    let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 512, height: 384))
    view.image = NSImage(data: data)
    view.imageScaling = .scaleAxesIndependently
    assertSnapshot(
      of: view, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: "light")
    view.appearance = NSAppearance(named: .darkAqua)
    assertSnapshot(
      of: view, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: "dark")
  }
}
