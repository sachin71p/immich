import SwiftUI

/// Tools tab body (E4, Photos pattern): three circular tool buttons plus the
/// Heirloom-only Markup entry.
///
/// Clean Up and Extend are Apple-Intelligence-class generative tools: object
/// removal and outpainting have no client-side model in this build and cannot
/// be expressed in the persisted edit recipe, so they are surfaced with an
/// honest inline notice instead of pretending to work — tapping them explains
/// rather than silently no-ops. Reframe is real: it cycles centered aspect
/// presets through the persisted crop recipe with a live preview.
///
/// Identifiers: `editor-tool-cleanup`, `editor-tool-extend`,
/// `editor-tool-reframe` (+ `editor-tool-reframe-value` for the active
/// preset), `editor-tools-notice`, `editor-tools-markup`.
struct EditToolsPanel: View {
  var reframeLabel: String
  var onReframe: () -> Void
  var onCleanup: () -> Void
  var onExtend: () -> Void
  var onMarkup: () -> Void
  var notice: String?

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 32) {
        toolButton(
          id: "editor-tool-cleanup", title: "Clean Up", system: "eraser",
          action: onCleanup)
        toolButton(
          id: "editor-tool-extend", title: "Extend",
          system: "arrow.up.left.and.arrow.down.right", action: onExtend)
        toolButton(
          id: "editor-tool-reframe", title: "Reframe", system: "aspectratio",
          action: onReframe)
      }
      .padding(.top, 8)
      Text(reframeLabel)
        .font(.caption2).foregroundStyle(.secondary)
        .accessibilityIdentifier("editor-tool-reframe-value")
      if let notice {
        Text(notice)
          .font(.caption).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
          .accessibilityIdentifier("editor-tools-notice")
      }
      Button(action: onMarkup) {
        HStack {
          Image(systemName: "pencil.tip.crop.circle")
          VStack(alignment: .leading, spacing: 1) {
            Text("Markup").font(.subheadline)
            Text("Draw on the photo — ink flattens into the saved render.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right").font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
      }
      .accessibilityIdentifier("editor-tools-markup")
    }
    .padding(.vertical, 4)
  }

  private func toolButton(
    id: String, title: String, system: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        ZStack {
          Circle().fill(.white.opacity(0.12)).frame(width: 64, height: 64)
          Image(systemName: system).font(.title2)
        }
        Text(title).font(.caption)
      }
    }
    .accessibilityIdentifier(id)
  }
}
