import CoreModel
import Media
import SwiftUI

/// Settings window (brief task 7): server/account, default upload target (DECISIONS §9 R3),
/// import destination default, timeline sources (§9 R8), cache/offline (usage + budgets, A6 owns
/// policy), agent login-item toggle placeholder (A5 wires SMAppService).
struct MacSettingsView: View {
  @Bindable var state: MacAppState
  @State private var error: String?
  @State private var pendingCount = 0
  @State private var isDraining = false
  @State private var agentEnabled = false
  @State private var agentNote = ""

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
        MacStorageView(state: state)
      }
      Section("Uploads in Flight") {
        LabeledContent("Pending uploads", value: "\(pendingCount)")
          .accessibilityIdentifier("settings-pending-count")
        Button("Upload Now") { Task { await drainNow() } }
          .disabled(isDraining)
          .accessibilityIdentifier("settings-upload-now")
      }
      Section("Background Agent") {
        // A5 brief task 8: SMAppService login item runs sync + the upload queue while the
        // main app is closed (agent target `Heirloom-Agent`). Failures (e.g. the helper
        // not embedded in this build) surface inline instead of failing silently.
        Toggle(
          "Sync in the background",
          isOn: Binding(
            get: { agentEnabled },
            set: { value in Task { await setAgent(enabled: value) } }
          )
        )
        .accessibilityIdentifier("settings-agent-toggle")
        if !agentNote.isEmpty {
          Text(agentNote).font(.caption).foregroundStyle(.secondary)
        }
      }
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
    }
    .formStyle(.grouped)
    .frame(minWidth: 420, minHeight: 480)
    .task {
      pendingCount = (try? await state.store.pendingUploadCount()) ?? 0
      refreshAgentStatus()
    }
  }

  private var uploadTargetBinding: Binding<SharedLibraryPrefs.UploadTarget> {
    Binding(
      get: { state.prefs.defaultUploadTarget },
      set: { value in Task { await updatePrefs { $0.defaultUploadTarget = value } } }
    )
  }

  private var importDestinationBinding: Binding<String> {
    Binding(
      get: { UserDefaults.standard.string(forKey: "Heirloom.importDestination") ?? "default" },
      set: { UserDefaults.standard.set($0, forKey: "Heirloom.importDestination") }
    )
  }

  private func refreshAgentStatus() {
    agentEnabled = MacAgentLoginItem.isEnabled
    agentNote = MacAgentLoginItem.statusNote
  }

  private func setAgent(enabled: Bool) async {
    do {
      try MacAgentLoginItem.setEnabled(enabled)
      agentEnabled = enabled
      agentNote = MacAgentLoginItem.statusNote
    } catch is CancellationError {
      // Cancellation isn't a failure: leave the toggle where it was.
    } catch {
      HeirloomLog.ui.error("Background agent failed: \(error.localizedDescription, privacy: .public)")
      self.error = "Couldn't change the background agent."
    }
  }

  private func drainNow() async {
    isDraining = true
    defer { isDraining = false }
    _ = await state.uploadQueue.drain(prefs: state.prefs)
    pendingCount = (try? await state.store.pendingUploadCount()) ?? 0
  }

  private func updatePrefs(_ mutate: (inout SharedLibraryPrefs) -> Void) async {
    guard let userId = state.userId else { return }
    var prefs = state.prefs
    mutate(&prefs)
    do {
      try await state.prefsMutations().update(prefs, for: userId)
      state.prefs = prefs
    } catch is CancellationError {
      // Cancellation isn't a failure: keep the previous prefs.
    } catch {
      HeirloomLog.ui.error("Settings save failed: \(error.localizedDescription, privacy: .public)")
      self.error = "Couldn't save settings."
    }
  }

  static func formatBytes(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
  }
}
