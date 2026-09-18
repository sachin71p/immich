import SwiftUI

/// Tick-ruler value dial (Photos-style value control, E3): a draggable tick
/// strip with a fixed centre marker, replacing the plain `Slider`. Dragging
/// scrubs continuously and live-updates the binding; release snaps to `step`.
///
/// Identifiers: the strip is `editor-value-dial`, the fixed marker is
/// `editor-value-dial-centre` (both asserted by `EditorUITests`).
///
/// Accessibility structure (E3 probes): an identified container absorbs the
/// identifiers of explicitly-modified descendants, so the strip and the
/// marker are Button siblings under an UNIDENTIFIED stack — Buttons always
/// expose, and with no identified ancestor their ids survive.
struct RulerDial: View {
  @Binding var value: Double
  var range: ClosedRange<Double>
  var step: Double = 1
  var format: String

  @State private var anchor: Double?

  private static let ptsPerStep: Double = 11

  var body: some View {
    VStack(spacing: 2) {
      ZStack {
        Button(action: {}) {
          GeometryReader { _ in
            Canvas { ctx, size in
              stripTicks(ctx: ctx, size: size)
            }
          }
          .frame(height: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editor-value-dial")
        .accessibilityLabel("Value")
        .accessibilityValue(format)
        .accessibilityAdjustableAction { direction in
          switch direction {
          case .increment:
            value = min(range.upperBound, value + step)
          case .decrement:
            value = max(range.lowerBound, value - step)
          @unknown default:
            break
          }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 1)
          .onChanged { g in
            if anchor == nil { anchor = value }
            let next =
              (anchor ?? value) - Double(g.translation.width) / Self.ptsPerStep * step
            value = min(range.upperBound, max(range.lowerBound, next))
          }
          .onEnded { _ in
            value = min(
              range.upperBound,
              max(range.lowerBound, (value / step).rounded() * step))
            anchor = nil
          })
        // 3 pt wide: the dead tap zone in the middle of the strip is nil.
        Button(action: {}) {
          RoundedRectangle(cornerRadius: 1.5)
            .fill(.yellow)
            .frame(width: 3, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dial centre marker")
        .accessibilityIdentifier("editor-value-dial-centre")
      }
      Text(format).font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  private func stripTicks(ctx: GraphicsContext, size: CGSize) {
    let w = size.width
    let base = round((value - range.lowerBound) / step)
    let n = Int(ceil(w / 2 / Self.ptsPerStep)) + 2
    for k in -n...n {
      let idx = Int(base) + k
      let v = range.lowerBound + Double(idx) * step
      guard v >= range.lowerBound, v <= range.upperBound else { continue }
      let x = w / 2 + (v - value) / step * Self.ptsPerStep
      let long = idx % 10 == 0
      let len = long ? 20.0 : (idx % 5 == 0 ? 14 : 8)
      var p = Path()
      p.move(to: CGPoint(x: x, y: (size.height - len) / 2))
      p.addLine(to: CGPoint(x: x, y: (size.height + len) / 2))
      ctx.stroke(
        p, with: .color(long ? .white : .gray), lineWidth: long ? 2 : 1)
    }
  }
}
