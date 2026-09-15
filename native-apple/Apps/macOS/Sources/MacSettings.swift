import CoreModel
import Media
import SwiftUI

/// Settings window (brief task 7): server/account, default upload target (DECISIONS §9 R3),
/// import destination default, timeline sources (§9 R8), cache/offline (usage + budgets, A6 owns
/// policy), agent login-item toggle placeholder (A5 wires SMAppService).
struct MacSettingsView: View {
  @Bindable var state: MacAppState
  @State private var cacheUsage: [MediaTier: Int] = [:]
  @State private var error: String?

  var body: some View {
    Form {
      Section("Account") {
        LabeledContent("Server", value: state.serverURL.absoluteString)
        LabeledContent("User", value: state.userId ?? "Not signed in")
        Button("Log Out") { Task { await state.logout() } }
      }
      Section("Uploads") {
        Picker("Default upload target", selection: uploadTargetBinding) {
          Text("Personal Library").tag(SharedLibraryPrefs.UploadTarget.personal)
          ForEach(state.spaces, id: \.space.id) { entry in
            Text(entry.space.name).tag(SharedLibraryPrefs.UploadTarget.space(entry.space.id))
          }
        }
        .accessibilityIdentifier("settings-upload-target")
        Picker("Import destination", selection: importDestinationBinding) {
          Text("Follow default upload target").tag("default")
          Text("Personal Library").tag("personal")
          ForEach(state.spaces, id: \.space.id) { entry in
            Text(entry.space.name).tag("space:\(entry.space.id)")
          }
        }
        .accessibilityIdentifier("settings-import-destination")
      }
      Section("Timeline Sources") {
        Toggle(
          "Show personal library",
          isOn: Binding(
            get: { state.prefs.showPersonalInTimeline },
            set: { value in Task { await updatePrefs { $0.showPersonalInTimeline = value } } }
          )
        )
        ForEach(state.spaces, id: \.space.id) { entry in
          Text(entry.space.name).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("settings-timeline-spaces")
        Text("Per-space and per-library toggles live in each library's manage view; hiding an owned external library is below.")
          .font(.caption)
          .foregroundStyle(.secondary)
        ForEach(state.libraries, id: \.library.id) { entry in
          Toggle(
            "Show \(entry.library.name)",
            isOn: Binding(
              get: { !state.prefs.hiddenOwnedLibraryIds.contains(entry.library.id) },
              set: { value in
                Task {
                  await updatePrefs {
                    if value {
                      $0.hiddenOwnedLibraryIds.removeAll { $0 == entry.library.id }
                    } else if !$0.hiddenOwnedLibraryIds.contains(entry.library.id) {
                      $0.hiddenOwnedLibraryIds.append(entry.library.id)
                    }
                  }
                }
              }
            )
          )
        }
      }
      Section("Cache & Offline") {
        ForEach(MediaTier.allCases, id: \.self) { tier in
          LabeledContent(
            tier.rawValue.capitalized,
            value: Self.formatBytes(cacheUsage[tier] ?? 0)
          )
        }
        Button("Refresh Usage") { Task { cacheUsage = await state.pipeline.usage() } }
      }
      Section("Background Agent") {
        // Placeholder until A5: SMAppService login-item wiring lives with the agent target.
        Toggle(
          "Sync in the background (coming soon)",
          isOn: Binding(
            get: { UserDefaults.standard.bool(forKey: "PhotosFork.agentEnabled") },
            set: { UserDefaults.standard.set($0, forKey: "PhotosFork.agentEnabled") }
          )
        )
        .disabled(true)
        .accessibilityIdentifier("settings-agent-toggle")
      }
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
    }
    .formStyle(.grouped)
    .frame(minWidth: 420, minHeight: 480)
    .task { cacheUsage = await state.pipeline.usage() }
  }

  private var uploadTargetBinding: Binding<SharedLibraryPrefs.UploadTarget> {
    Binding(
      get: { state.prefs.defaultUploadTarget },
      set: { value in Task { await updatePrefs { $0.defaultUploadTarget = value } } }
    )
  }

  private var importDestinationBinding: Binding<String> {
    Binding(
      get: { UserDefaults.standard.string(forKey: "PhotosFork.importDestination") ?? "default" },
      set: { UserDefaults.standard.set($0, forKey: "PhotosFork.importDestination") }
    )
  }

  private func updatePrefs(_ mutate: (inout SharedLibraryPrefs) -> Void) async {
    guard let userId = state.userId else { return }
    var prefs = state.prefs
    mutate(&prefs)
    do {
      try await state.prefsMutations().update(prefs, for: userId)
      state.prefs = prefs
    } catch {
      self.error = error.localizedDescription
    }
  }

  static func formatBytes(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
  }
}
