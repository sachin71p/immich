import Foundation

/// A candidate tool for the WP-E E6/E8 Tools tab. Tools are on-device-only: a tool
/// appears iff `isAvailable` is true, and the tab hides when none are (TEST-PLAN E8).
public struct EditTool: Sendable, Equatable {
  public var id: String
  public var title: String
  public var isAvailable: Bool

  public init(id: String, title: String, isAvailable: Bool) {
    self.id = id
    self.title = title
    self.isAvailable = isAvailable
  }
}

/// Data-driven registry for the Tools tab. Today no retouch-class tool is
/// implementable on-device in this WP, so the default registry is empty and the
/// tab hides; owner decision noted in the WP-E report. New tools plug in by
/// appending an `EditTool` with a real `isAvailable` probe.
public struct EditToolRegistry: Sendable, Equatable {
  public var tools: [EditTool]

  public init(tools: [EditTool] = []) {
    self.tools = tools
  }

  /// Only implemented tools, in registry order.
  public var visibleTools: [EditTool] { tools.filter(\.isAvailable) }

  /// False when no tool is implementable — the UI hides the tab (spec E8).
  public var shouldShowToolsTab: Bool { !visibleTools.isEmpty }
}
