import Foundation

/// Undo/redo over whole-recipe snapshots plus copy/paste via JSON data (brief section 7).
/// Value type: UIs hold it in `@State` and assign back after each mutation.
public struct EditHistory: Sendable, Equatable {
  public static let maxDepth = 50

  /// The recipe currently shown in the UI.
  public var current: EditRecipe
  /// The recipe the session started from (for compare-hold and dirty checks).
  public var baseline: EditRecipe
  private var past: [EditRecipe]
  private var future: [EditRecipe]

  public init(initial: EditRecipe = EditRecipe()) {
    self.current = initial
    self.baseline = initial
    self.past = []
    self.future = []
  }

  public var canUndo: Bool { !past.isEmpty }
  public var canRedo: Bool { !future.isEmpty }
  public var isDirty: Bool { current != baseline }

  /// Records `next` as the new current state. Equal states are ignored (slider scrubbing
  /// through the same value does not flood the stack).
  public mutating func commit(_ next: EditRecipe) {
    guard next != current else { return }
    past.append(current)
    if past.count > Self.maxDepth { past.removeFirst() }
    current = next
    future.removeAll()
  }

  public mutating func undo() {
    guard let prev = past.popLast() else { return }
    future.append(current)
    current = prev
  }

  public mutating func redo() {
    guard let next = future.popLast() else { return }
    past.append(current)
    current = next
  }

  /// Reverts to the original (empty) state. The original asset bytes were never touched, so
  /// this is always lossless; callers additionally clear server state (see persistence).
  public mutating func revertToOriginal() {
    commit(EditRecipe())
  }

  // MARK: - Copy/paste between assets

  /// Serializes the current recipe for the pasteboard (stable, sorted-keys JSON).
  public func copiedData() throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return try enc.encode(CopiedEdits(format: EditRecipeKey.current, recipe: current))
  }

  /// Parses pasteboard data. Foreign/unknown payloads throw `EditHistoryError.incompatiblePaste`.
  public static func pastedRecipe(from data: Data) throws -> EditRecipe {
    let decoded = try JSONDecoder().decode(CopiedEdits.self, from: data)
    guard decoded.format == EditRecipeKey.current else {
      throw EditHistoryError.incompatiblePaste
    }
    return decoded.recipe
  }

  private struct CopiedEdits: Codable {
    var format: String
    var recipe: EditRecipe
  }
}

public enum EditHistoryError: Error, Sendable, Equatable {
  case incompatiblePaste
}
