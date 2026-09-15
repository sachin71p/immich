import CoreGraphics
import Foundation

/// The upstream edit actions the server understands (`PUT /assets/:id/edits` —
/// server/src/dtos/editing.dto.ts `AssetEditAction`): crop, rotate, mirror. Anything else
/// lives in the recipe KV + rendered upload.
public enum UpstreamEditAction: String, Sendable, Codable {
  case crop, rotate, mirror
}

public enum MirrorAxis: String, Sendable, Codable {
  case horizontal, vertical
}

/// One `{action, parameters}` item of `AssetEditsCreateDto`. Encodes to exactly the JSON the
/// server validates: crop `{x, y, width, height}` ints; rotate `{angle}` in `{0,90,180,270}`;
/// mirror `{axis}`. Duplicate actions are rejected server-side, so `split` emits at most one
/// crop, one rotate, and one mirror per axis.
public struct UpstreamEditItem: Sendable, Codable, Equatable {
  public var action: UpstreamEditAction
  public var parameters: Parameters

  public enum Parameters: Sendable, Codable, Equatable {
    case crop(x: Int, y: Int, width: Int, height: Int)
    case rotate(angle: Int)
    case mirror(axis: MirrorAxis)

    private enum CodingKeys: String, CodingKey { case x, y, width, height, angle, axis }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      if let angle = try c.decodeIfPresent(Int.self, forKey: .angle) {
        self = .rotate(angle: angle)
      } else if let axis = try c.decodeIfPresent(MirrorAxis.self, forKey: .axis) {
        self = .mirror(axis: axis)
      } else {
        self = .crop(
          x: try c.decode(Int.self, forKey: .x), y: try c.decode(Int.self, forKey: .y),
          width: try c.decode(Int.self, forKey: .width), height: try c.decode(Int.self, forKey: .height))
      }
    }

    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .crop(let x, let y, let w, let h):
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(w, forKey: .width)
        try c.encode(h, forKey: .height)
      case .rotate(let angle):
        try c.encode(angle, forKey: .angle)
      case .mirror(let axis):
        try c.encode(axis, forKey: .axis)
      }
    }
  }

  public init(action: UpstreamEditAction, parameters: Parameters) {
    self.action = action
    self.parameters = parameters
  }
}

/// The persistence split for one recipe (decided contract 1).
public struct EditSplit: Sendable, Equatable {
  /// Items for `PUT /assets/:id/edits` (empty when the recipe has no upstream-expressible ops).
  public var upstream: [UpstreamEditItem]
  /// True when the recipe KV + rendered upload path is required.
  public var needsClientRender: Bool

  public init(upstream: [UpstreamEditItem], needsClientRender: Bool) {
    self.upstream = upstream
    self.needsClientRender = needsClientRender
  }
}

public enum EditSplitError: Error, Sendable, Equatable {
  /// The crop rect collapses to zero pixels at this image size — refuse rather than send an
  /// edit the server would reject (`width`/`height` must be >= 1).
  case degenerateCrop
}

public enum EditSplitter {
  /// Splits `recipe` against `imageSize` (full-resolution pixel size of the SOURCE asset —
  /// upstream crop params are absolute pixels in the source frame).
  public static func split(_ recipe: EditRecipe, imageSize: CGSize) throws -> EditSplit {
    var items: [UpstreamEditItem] = []
    if let crop = recipe.crop {
      if let rect = crop.rect {
        let px = rect.pixels(in: imageSize).integral
        guard px.width >= 1, px.height >= 1 else { throw EditSplitError.degenerateCrop }
        items.append(UpstreamEditItem(
          action: .crop,
          parameters: .crop(x: Int(px.minX), y: Int(px.minY), width: Int(px.width), height: Int(px.height))))
      }
      if crop.quarterTurns % 4 != 0 {
        items.append(UpstreamEditItem(
          action: .rotate, parameters: .rotate(angle: (crop.quarterTurns % 4) * 90)))
      }
      if crop.flipHorizontal {
        items.append(UpstreamEditItem(action: .mirror, parameters: .mirror(axis: .horizontal)))
      }
      if crop.flipVertical {
        items.append(UpstreamEditItem(action: .mirror, parameters: .mirror(axis: .vertical)))
      }
    }
    return EditSplit(upstream: items, needsClientRender: recipe.requiresClientRender)
  }

  /// Encodes the `PUT /assets/:id/edits` body: `{"edits": [{action, parameters}, ...]}`.
  public static func editsBody(_ items: [UpstreamEditItem]) throws -> Data {
    struct Body: Encodable { var edits: [UpstreamEditItem] }
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return try enc.encode(Body(edits: items))
  }
}
