import CoreModel
import LocalStore
import Media
import SwiftUI

// MARK: - settings (brief task 8)

/// Server/account, default upload target, timeline sources, cache usage (A6 fills in policy;
/// usage is already readable), about.
struct SettingsView: View {
  @EnvironmentObject var session: AppSession
  @State private var showSources = false
  @State private var cacheUsage: [MediaTier: Int] = [:]
  @State private var error: String?

  var body: some View {
    NavigationStack {
      List {
        Section("Account") {
          LabeledContent("Server", value: session.serverURL?.absoluteString ?? "—")
          LabeledContent("User", value: session.userId)
          if session.isFixture {
            Text("Fixture mode — mutations hit no server.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Button("Sign Out", role: .destructive) {
            session.signOut()
          }
        }
        Section("Upload") {
          UploadTargetPicker()
            .environmentObject(session)
        }
        Section("Timeline") {
          Button("Timeline Sources…") { showSources = true }
          Toggle(
            "Show Personal Library",
            isOn: Binding(
              get: { session.prefs.showPersonalInTimeline },
              set: { new in setPrefs { $0.showPersonalInTimeline = new } }))
        }
        Section("Cache") {
          // A6 fills in budget policy; usage is already readable via the pipeline (A2 surface).
          ForEach(MediaTier.allCases, id: \.self) { tier in
            LabeledContent(
              tier.rawValue.capitalized,
              value: Self.formatBytes(cacheUsage[tier] ?? 0))
          }
        }
        Section("About") {
          LabeledContent("PhotosFork", value: "iOS · shared-libraries fork")
          Text("Follow Apple Photos interaction patterns; never Apple artwork or the Photos name.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let error {
          Section { Text(error).foregroundStyle(.red).font(.caption) }
        }
      }
      .navigationTitle("Settings")
      .sheet(isPresented: $showSources) {
        TimelineSourcesSheet()
          .environmentObject(session)
      }
      .task {
        if let pipeline = session.pipeline {
          cacheUsage = await pipeline.usage()
        }
      }
    }
    .accessibilityIdentifier("settings")
  }

  private func setPrefs(_ edit: (inout SharedLibraryPrefs) -> Void) {
    Task {
      do {
        var prefs = session.prefs
        edit(&prefs)
        try await session.prefsMutations?.update(prefs, for: session.userId)
        try await session.refresh()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  static func formatBytes(_ bytes: Int) -> String {
    let mb = Double(bytes) / 1_000_000
    if mb < 1000 { return String(format: "%.1f MB", mb) }
    return String(format: "%.2f GB", mb / 1000)
  }
}

/// Default upload target picker (DECISIONS §9 R3): personal or one member space.
struct UploadTargetPicker: View {
  @EnvironmentObject var session: AppSession
  @State private var error: String?

  var body: some View {
    Picker(
      "Default Upload Target",
      selection: Binding(
        get: { targetKey(session.prefs.defaultUploadTarget) },
        set: { key in
          Task {
            do {
              var prefs = session.prefs
              prefs.defaultUploadTarget = key == "personal" ? .personal : .space(key)
              try await session.prefsMutations?.update(prefs, for: session.userId)
              try await session.refresh()
            } catch {
              self.error = error.localizedDescription
            }
          }
        })
    ) {
      Text("Personal Library").tag("personal")
      ForEach(session.spaces) { space in
        Text(space.name).tag(space.id)
      }
    }
    if let error {
      Text(error).foregroundStyle(.red).font(.caption)
    }
  }

  private func targetKey(_ target: SharedLibraryPrefs.UploadTarget) -> String {
    switch target {
    case .personal: return "personal"
    case .space(let id): return id
    }
  }
}

// MARK: - "Show in timeline" management sheet (brief task 2, DECISIONS §9)

/// Toggles which containers appear on the timeline: personal (preference), each shared library
/// (`space_member.showInTimeline`), each shared external library. Library-member toggles have no
/// wired client endpoint (the generator can only include one of the two `updateMyTimeline`
/// operationIds — A1 handoff) so they display read-only; see the handoff open issues.
struct TimelineSourcesSheet: View {
  @EnvironmentObject var session: AppSession
  @State private var spaceToggles: [String: Bool] = [:]
  @State private var libraryToggles: [String: Bool] = [:]
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Personal") {
          Toggle(
            "Show Personal Library",
            isOn: Binding(
              get: { session.prefs.showPersonalInTimeline },
              set: { new in setPrefs { $0.showPersonalInTimeline = new } }))
        }
        Section("Shared Libraries") {
          ForEach(session.spaces) { space in
            Toggle(
              space.name,
              isOn: Binding(
                get: { spaceToggles[space.id] ?? true },
                set: { new in setSpaceToggle(space.id, show: new) }))
          }
        }
        Section("External Libraries") {
          ForEach(session.libraries) { library in
            HStack {
              Toggle(
                library.name,
                isOn: Binding(
                  get: { libraryToggles[library.id] ?? true },
                  set: { _ in }))
                .disabled(true)
              Spacer()
            }
          }
          Text("Library timeline toggles need a wired library-member endpoint (open issue).")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let error {
          Section { Text(error).foregroundStyle(.red).font(.caption) }
        }
      }
      .navigationTitle("Timeline Sources")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task { await load() }
    }
    .accessibilityIdentifier("timeline-sources")
  }

  private func load() async {
    guard let store = session.store else { return }
    do {
      let ctx = try await store.timelineContext(for: session.userId)
      spaceToggles = Dictionary(
        uniqueKeysWithValues: ctx.spaceMemberships.map { ($0.spaceId, $0.showInTimeline) })
      libraryToggles = Dictionary(
        uniqueKeysWithValues: ctx.libraryMemberships.map { ($0.libraryId, $0.showInTimeline) })
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func setPrefs(_ edit: (inout SharedLibraryPrefs) -> Void) {
    Task {
      do {
        var prefs = session.prefs
        edit(&prefs)
        try await session.prefsMutations?.update(prefs, for: session.userId)
        try await session.refresh()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func setSpaceToggle(_ spaceId: String, show: Bool) {
    spaceToggles[spaceId] = show
    Task {
      do {
        try await session.spaceMutations?.setShowInTimeline(spaceId: spaceId, show: show)
        try await session.refresh()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}
