import Foundation

/// A9.3: the story-player model shared by the iOS and macOS Memories views.
///
/// A `MemoryStory` binds one upstream `Memory` to the concrete asset ids the player pages
/// through. `MemoryStoryPlayer` is the pure auto-advance state machine (the SwiftUI views add
/// the timer + transitions on top), kept here so the advance/wrap/music-default behavior is
/// unit-tested without a host.
public struct MemoryStory: Sendable, Hashable, Identifiable {
  public var memoryId: String
  public var title: String
  public var memoryAt: Date
  public var assetIds: [String]

  public var id: String { memoryId }

  public init(memoryId: String, title: String, memoryAt: Date, assetIds: [String]) {
    self.memoryId = memoryId
    self.title = title
    self.memoryAt = memoryAt
    self.assetIds = assetIds
  }

  /// Display title for a story: the memory type made human-readable, with its date.
  public static func title(for memory: Memory) -> String {
    let type = memory.type
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
    let pretty = type.prefix(1).uppercased() + type.dropFirst()
    return pretty.isEmpty ? "Memory" : pretty
  }
}

/// Auto-advance state for one story. Music stays OFF by default — no licensed tracks are
/// bundled and no licensing work is in scope; the toggle only records the preference.
public struct MemoryStoryPlayer: Sendable, Hashable {
  public var story: MemoryStory
  /// Seconds each page stays on screen before auto-advancing.
  public var pageDuration: TimeInterval
  public private(set) var pageIndex: Int
  /// Decided A9.3: music defaults to off.
  public var musicEnabled: Bool

  public init(story: MemoryStory, pageDuration: TimeInterval = 5, musicEnabled: Bool = false) {
    self.story = story
    self.pageDuration = pageDuration
    self.pageIndex = 0
    self.musicEnabled = musicEnabled
  }

  public var pageCount: Int { story.assetIds.count }
  public var currentAssetId: String? {
    guard !story.assetIds.isEmpty else { return nil }
    return story.assetIds[min(pageIndex, story.assetIds.count - 1)]
  }

  /// Fractional progress (0…1) of the story, for the segmented progress bar.
  public var progress: Double {
    guard pageCount > 0 else { return 0 }
    return Double(min(pageIndex + 1, pageCount)) / Double(pageCount)
  }

  /// Advance one page. Returns false when the story just finished (caller dismisses or
  /// advances to the next story).
  @discardableResult
  public mutating func advance() -> Bool {
    guard pageIndex + 1 < pageCount else { return false }
    pageIndex += 1
    return true
  }

  public mutating func restart() { pageIndex = 0 }
}
