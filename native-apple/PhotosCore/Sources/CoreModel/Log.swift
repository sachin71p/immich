import Foundation
import os

/// Central logging entry point for Heirloom and PhotosCore.
///
/// Why one enum: `os.Logger` needs a fixed subsystem + category pair per call site, and
/// scattering those strings across modules guarantees typos and split categories. Every
/// module logs through these five shared loggers so Console filtering and the WP0/WP7
/// `os_signpost` profiling harness see one consistent taxonomy.
public enum HeirloomLog {
  private static let subsystem = "com.immich.heirloom"

  /// Grid snapshot, layout and cell-configuration diagnostics (WP2/WP3 hot paths).
  public static let timeline = Logger(subsystem: subsystem, category: "timeline")
  /// Thumbnail fetch/decode pipeline and disk-cache diagnostics (R9).
  public static let media = Logger(subsystem: subsystem, category: "media")
  /// Sync protocol, connection and upload-queue diagnostics.
  public static let sync = Logger(subsystem: subsystem, category: "sync")
  /// Local-store queries, mutations and fixture seeding diagnostics.
  public static let store = Logger(subsystem: subsystem, category: "store")
  /// View lifecycle, navigation and user-action diagnostics.
  public static let ui = Logger(subsystem: subsystem, category: "ui")
}

/// Interval signposts for the WP0/WP7 Instruments harness (`profile.sh` records the
/// `os_signpost` instrument; `summarize.py` aggregates per-name count/p50/p95/max).
///
/// Why a wrapper instead of raw `OSSignposter`: call sites stay one-liners and the set of
/// profiled interval names stays closed, so the harness never has to chase ad-hoc strings.
/// `OSSignposter` is `Sendable` and these helpers hold no mutable state, so they are safe
/// to call from any actor or thread under Swift 6 strict concurrency.
public enum HeirloomSignpost {
  // MARK: - Interval names (the closed set the perf harness aggregates)

  public static let gridLoad: StaticString = "GridLoad"
  public static let snapshotBuild: StaticString = "SnapshotBuild"
  public static let layoutPrepare: StaticString = "LayoutPrepare"
  public static let thumbnailFetch: StaticString = "ThumbnailFetch"
  public static let thumbnailDecode: StaticString = "ThumbnailDecode"
  public static let viewerOpen: StaticString = "ViewerOpen"
  /// WP-F F3: cold-launch first thumbnails (disk snapshot → thumbhash placeholders).
  public static let launchFirstThumbnails: StaticString = "Launch.FirstThumbnails"
  /// WP-F F1/F3: navigation back to Library serving the snapshot (target ≤ 150 ms).
  public static let libraryReturn: StaticString = "Library.Return"
  /// WP-F F4: filter/media/album page first paint (target ≤ 1 s).
  public static let pageFirstPaint: StaticString = "Page.FirstPaint"
  /// WP-F F2: store timeline/filter query interval (cold ≤ 1.5 s, warm ≤ 300 ms).
  public static let timelineQuery: StaticString = "Timeline.Query"
  /// WP-E E2/E7: chrome + proxy on screen (budget: 300 ms; the original loads async after).
  public static let editOpen: StaticString = "EditOpen"

  private static let signposter = OSSignposter(subsystem: "com.immich.heirloom", category: "timeline")

  /// Runs `body` inside a signpost interval named `name` (sync variant).
  public static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
    try signposter.withIntervalSignpost(name, around: body)
  }

  /// Runs `body` inside a signpost interval named `name` (async variant).
  ///
  /// Why manual begin/end: this SDK's `OSSignposter` only offers a synchronous
  /// `withIntervalSignpost`, so the async path brackets the interval explicitly.
  public static func interval<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
    let state = signposter.beginInterval(name)
    defer { signposter.endInterval(name, state) }
    return try await body()
  }
}
