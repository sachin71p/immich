import CoreGraphics
import CoreImage
import Foundation

#if canImport(UIKit)
  import UIKit
  public typealias MarkupPlatformColor = UIColor
#elseif canImport(AppKit)
  import AppKit
  public typealias MarkupPlatformColor = NSColor
#endif

/// macOS vector markup element. Serializable — round-trips through `MarkupRecipe.elements`
/// so Mac edits survive save/reload. (iOS uses PencilKit; see `hasFlattenedInk`.)
public enum MacMarkupElement: Sendable, Codable, Equatable {
  case pen(points: [NormalizedPoint], width: Double, colorHex: String)
  case line(from: NormalizedPoint, to: NormalizedPoint, width: Double, colorHex: String)
  case arrow(from: NormalizedPoint, to: NormalizedPoint, width: Double, colorHex: String)
  case rectangle(origin: NormalizedPoint, size: NormalizedSize, width: Double, colorHex: String)
  case ellipse(origin: NormalizedPoint, size: NormalizedSize, width: Double, colorHex: String)
  case text(at: NormalizedPoint, string: String, fontSize: Double, colorHex: String)

  private enum Kind: String, Codable { case pen, line, arrow, rectangle, ellipse, text }
  private enum Keys: String, CodingKey {
    case kind, points, from, to, origin, size, at, string, fontSize, width, colorHex
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    switch try c.decode(Kind.self, forKey: .kind) {
    case .pen:
      self = .pen(
        points: try c.decode([NormalizedPoint].self, forKey: .points),
        width: try c.decode(Double.self, forKey: .width),
        colorHex: try c.decode(String.self, forKey: .colorHex))
    case .line:
      self = .line(
        from: try c.decode(NormalizedPoint.self, forKey: .from),
        to: try c.decode(NormalizedPoint.self, forKey: .to),
        width: try c.decode(Double.self, forKey: .width),
        colorHex: try c.decode(String.self, forKey: .colorHex))
    case .arrow:
      self = .arrow(
        from: try c.decode(NormalizedPoint.self, forKey: .from),
        to: try c.decode(NormalizedPoint.self, forKey: .to),
        width: try c.decode(Double.self, forKey: .width),
        colorHex: try c.decode(String.self, forKey: .colorHex))
    case .rectangle:
      self = .rectangle(
        origin: try c.decode(NormalizedPoint.self, forKey: .origin),
        size: try c.decode(NormalizedSize.self, forKey: .size),
        width: try c.decode(Double.self, forKey: .width),
        colorHex: try c.decode(String.self, forKey: .colorHex))
    case .ellipse:
      self = .ellipse(
        origin: try c.decode(NormalizedPoint.self, forKey: .origin),
        size: try c.decode(NormalizedSize.self, forKey: .size),
        width: try c.decode(Double.self, forKey: .width),
        colorHex: try c.decode(String.self, forKey: .colorHex))
    case .text:
      self = .text(
        at: try c.decode(NormalizedPoint.self, forKey: .at),
        string: try c.decode(String.self, forKey: .string),
        fontSize: try c.decode(Double.self, forKey: .fontSize),
        colorHex: try c.decode(String.self, forKey: .colorHex))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    switch self {
    case .pen(let points, let width, let colorHex):
      try c.encode(Kind.pen, forKey: .kind)
      try c.encode(points, forKey: .points)
      try c.encode(width, forKey: .width)
      try c.encode(colorHex, forKey: .colorHex)
    case .line(let from, let to, let width, let colorHex):
      try c.encode(Kind.line, forKey: .kind)
      try c.encode(from, forKey: .from)
      try c.encode(to, forKey: .to)
      try c.encode(width, forKey: .width)
      try c.encode(colorHex, forKey: .colorHex)
    case .arrow(let from, let to, let width, let colorHex):
      try c.encode(Kind.arrow, forKey: .kind)
      try c.encode(from, forKey: .from)
      try c.encode(to, forKey: .to)
      try c.encode(width, forKey: .width)
      try c.encode(colorHex, forKey: .colorHex)
    case .rectangle(let origin, let size, let width, let colorHex):
      try c.encode(Kind.rectangle, forKey: .kind)
      try c.encode(origin, forKey: .origin)
      try c.encode(size, forKey: .size)
      try c.encode(width, forKey: .width)
      try c.encode(colorHex, forKey: .colorHex)
    case .ellipse(let origin, let size, let width, let colorHex):
      try c.encode(Kind.ellipse, forKey: .kind)
      try c.encode(origin, forKey: .origin)
      try c.encode(size, forKey: .size)
      try c.encode(width, forKey: .width)
      try c.encode(colorHex, forKey: .colorHex)
    case .text(let at, let string, let fontSize, let colorHex):
      try c.encode(Kind.text, forKey: .kind)
      try c.encode(at, forKey: .at)
      try c.encode(string, forKey: .string)
      try c.encode(fontSize, forKey: .fontSize)
      try c.encode(colorHex, forKey: .colorHex)
    }
  }
}

public struct NormalizedSize: Sendable, Codable, Equatable {
  public var width: Double
  public var height: Double
  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}

public enum MarkupColor {
  /// `#RRGGBB` or `#RRGGBBAA` hex.
  public static func cgColor(_ hex: String) -> CGColor {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }
    var value: UInt64 = 0
    Scanner(string: h).scanHexInt64(&value)
    let r, g, b, a: CGFloat
    if h.count == 8 {
      r = CGFloat((value >> 24) & 0xff) / 255
      g = CGFloat((value >> 16) & 0xff) / 255
      b = CGFloat((value >> 8) & 0xff) / 255
      a = CGFloat(value & 0xff) / 255
    } else {
      r = CGFloat((value >> 16) & 0xff) / 255
      g = CGFloat((value >> 8) & 0xff) / 255
      b = CGFloat(value & 0xff) / 255
      a = 1
    }
    return CGColor(red: r, green: g, blue: b, alpha: a)
  }
}

/// Renders `elements` into a transparent overlay `CGImage` at `pixelSize`, then composites
/// it over `base` ("flattened into render" — decided contract 2). Coordinates are
/// normalized origin-upper-left, matching `NormalizedRect`/`NormalizedPoint`.
public func renderMarkupOverlay(_ elements: [MacMarkupElement], pixelSize: CGSize) -> CGImage? {
  guard !elements.isEmpty, pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
  guard let ctx = CGContext(
    data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height),
    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return nil }
  // Work in a top-left-origin space to match normalized coordinates.
  ctx.translateBy(x: 0, y: pixelSize.height)
  ctx.scaleBy(x: 1, y: -1)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  for el in elements {
    drawElement(el, in: ctx, size: pixelSize)
  }
  return ctx.makeImage()
}

private func point(_ p: NormalizedPoint, in size: CGSize) -> CGPoint {
  CGPoint(x: CGFloat(p.x) * size.width, y: CGFloat(p.y) * size.height)
}

private func drawElement(_ el: MacMarkupElement, in ctx: CGContext, size: CGSize) {
  switch el {
  case .pen(let points, let width, let colorHex):
    ctx.setStrokeColor(MarkupColor.cgColor(colorHex))
    ctx.setLineWidth(CGFloat(width) * min(size.width, size.height) / 1000.0 + 1)
    let pts = points.map { point($0, in: size) }
    guard let first = pts.first else { return }
    ctx.move(to: first)
    for p in pts.dropFirst() { ctx.addLine(to: p) }
    ctx.strokePath()
  case .line(let from, let to, let width, let colorHex):
    ctx.setStrokeColor(MarkupColor.cgColor(colorHex))
    ctx.setLineWidth(CGFloat(width))
    ctx.move(to: point(from, in: size))
    ctx.addLine(to: point(to, in: size))
    ctx.strokePath()
  case .arrow(let from, let to, let width, let colorHex):
    let a = point(from, in: size)
    let b = point(to, in: size)
    ctx.setStrokeColor(MarkupColor.cgColor(colorHex))
    ctx.setFillColor(MarkupColor.cgColor(colorHex))
    ctx.setLineWidth(CGFloat(width))
    ctx.move(to: a)
    ctx.addLine(to: b)
    ctx.strokePath()
    let angle = atan2(b.y - a.y, b.x - a.x)
    let head = CGFloat(width) * 4 + 8
    ctx.move(to: b)
    ctx.addLine(to: CGPoint(x: b.x - head * cos(angle - 0.45), y: b.y - head * sin(angle - 0.45)))
    ctx.addLine(to: CGPoint(x: b.x - head * cos(angle + 0.45), y: b.y - head * sin(angle + 0.45)))
    ctx.closePath()
    ctx.fillPath()
  case .rectangle(let origin, let rsize, let width, let colorHex):
    ctx.setStrokeColor(MarkupColor.cgColor(colorHex))
    ctx.setLineWidth(CGFloat(width))
    let o = point(origin, in: size)
    ctx.stroke(CGRect(
      x: o.x, y: o.y, width: CGFloat(rsize.width) * size.width,
      height: CGFloat(rsize.height) * size.height))
  case .ellipse(let origin, let rsize, let width, let colorHex):
    ctx.setStrokeColor(MarkupColor.cgColor(colorHex))
    ctx.setLineWidth(CGFloat(width))
    let o = point(origin, in: size)
    ctx.strokeEllipse(in: CGRect(
      x: o.x, y: o.y, width: CGFloat(rsize.width) * size.width,
      height: CGFloat(rsize.height) * size.height))
  case .text(let at, let string, let fontSize, let colorHex):
    // CoreGraphics-only text (no AppKit/UIKit dependency in the engine): draw with a
    // system font at a size scaled to the image.
    let scaled = max(8, CGFloat(fontSize) * min(size.width, size.height) / 1000.0)
    guard let font = CGFont("Helvetica" as CFString) else { return }
    ctx.setFillColor(MarkupColor.cgColor(colorHex))
    ctx.textPosition = point(at, in: size)
    ctx.setFont(font)
    ctx.setFontSize(scaled)
    let glyphs = string.utf16.map { CGGlyph($0) }
    ctx.showGlyphs(glyphs, at: [ctx.textPosition])
  }
}

/// Composites a markup overlay over the rendered base. The overlay is scaled to the base
/// extent when sizes differ (e.g. preview overlay onto a full-res render).
public func flattenMarkup(_ overlay: CIImage, onto base: CIImage) -> CIImage {
  let baseExtent = base.extent
  var ov = overlay
  let oe = overlay.extent
  if oe != baseExtent {
    let sx = baseExtent.width / max(1, oe.width)
    let sy = baseExtent.height / max(1, oe.height)
    ov = overlay.transformed(
      by: CGAffineTransform(scaleX: sx, y: sy).concatenating(
        CGAffineTransform(translationX: baseExtent.minX - oe.minX * sx, y: baseExtent.minY - oe.minY * sy)))
  }
  let comp = CIFilter(name: "CISourceOverCompositing")
  comp?.setValue(ov, forKey: kCIInputImageKey)
  comp?.setValue(base, forKey: kCIInputBackgroundImageKey)
  return comp?.outputImage ?? base
}
