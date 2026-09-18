import CoreModel
import ImmichAPI
import LocalStore
import Media
import SwiftUI

// MARK: - account profile store (WP5 T3)

/// The signed-in user's profile for the account UI. Loaded once per session identity:
/// from `/users/me` on a real server, from the local mirror (or fixture defaults)
/// in fixture mode, where no server exists. Never surfaces the raw UUID as a name.
@MainActor
final class AccountProfileStore: ObservableObject {
  @Published var profile: CurrentUserProfile?
  @Published var host: String?
  private var loadedFor: String?

  func load(session: AppSession) async {
    let key = "\(session.userId)|\(session.serverURL?.absoluteString ?? "")|\(session.isFixture)"
    if loadedFor == key, profile != nil { return }
    loadedFor = key
    host = session.serverURL?.host ?? session.serverURL?.absoluteString
    if session.isFixture {
      if let store = session.store,
        let mirror = try? await store.user(id: session.userId),
        !mirror.name.trimmingCharacters(in: .whitespaces).isEmpty
      {
        profile = CurrentUserProfile(id: mirror.id, name: mirror.name, email: mirror.email)
      } else {
        profile = CurrentUserProfile(
          id: session.userId, name: "Fixture User", email: "")
      }
      return
    }
    guard let connection = session.connection else { return }
    // A network failure leaves the previous (or nil) profile; the sheet shows a
    // retry instead of an error banner.
    if let fetched = try? await connection.currentUser() {
      profile = fetched
    }
  }
}

// MARK: - account sheet (WP5 T3/T4)

/// The account sheet: identity, sync, upload/backup, timeline sources, storage,
/// shared libraries, sign-out (confirmed) and a version-only About. Section bodies
/// are the `SettingsView` components, reused in place.
struct AccountSheet: View {
  @EnvironmentObject var session: AppSession
  @EnvironmentObject var profiles: AccountProfileStore
  @State private var showSources = false
  @State private var showSignOutConfirm = false
  @State private var cacheUsage: [MediaTier: Int] = [:]
  @State private var storage = StoragePrefs()
  @Environment(\.dismiss) private var dismiss

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
  }()

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 12) {
            AccountAvatarView(name: profiles.profile?.name, diameter: 52)
            VStack(alignment: .leading, spacing: 2) {
              Text(profiles.profile?.name ?? "Loading…")
                .font(.headline)
                .accessibilityIdentifier("account-name")
              if let email = profiles.profile?.email, !email.isEmpty {
                Text(email)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              Text(profiles.host ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 4)
        }
        Section("Sync") {
          Button("Sync Now") {
            Task { await session.syncNow() }
          }
          .disabled(session.isSyncing)
          .accessibilityIdentifier("account-sync-now")
          LabeledContent("Last synced", value: lastSyncedText)
          if session.isSyncing {
            ProgressView("Syncing…")
          }
          if let lastError = session.lastError {
            Text(lastError)
              .foregroundStyle(.red)
              .font(.caption)
          }
        }
        Section("Upload") {
          UploadTargetPicker()
            .environmentObject(session)
        }
        BackupSettingsSection()
          .environmentObject(session)
        Section("Timeline") {
          Button("Timeline Sources…") { showSources = true }
        }
        Section("Storage") {
          NavigationLink("Free Up Space…") {
            FreeUpSpaceView()
              .environmentObject(session)
          }
          Toggle(
            "Optimize Storage",
            isOn: Binding(
              get: { storage.optimizeStorage },
              set: { new in setOptimizeStorage(new) }))
          Text("Optimize keeps thumbnails and shrinks originals to \(SettingsView.formatBytes(StoragePrefs.iOSDefaultOriginalBudgetBytes)). Turn it off to download originals.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Section("Cache Usage") {
          ForEach(MediaTier.allCases, id: \.self) { tier in
            LabeledContent(
              tier.rawValue.capitalized,
              value: SettingsView.formatBytes(cacheUsage[tier] ?? 0))
          }
        }
        Section("Shared Libraries") {
          NavigationLink("Manage…") {
            SpacesListView()
              .environmentObject(session)
          }
          .accessibilityIdentifier("account-shared-libraries")
        }
        Section {
          Button("Sign Out", role: .destructive) {
            showSignOutConfirm = true
          }
          .accessibilityIdentifier("account-signout")
        }
        Section("About") {
          LabeledContent("Version", value: Self.appVersion)
        }
      }
      .navigationTitle("Account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $showSources) {
        TimelineSourcesSheet()
          .environmentObject(session)
      }
      .alert("Sign Out?", isPresented: $showSignOutConfirm) {
        Button("Sign Out", role: .destructive) {
          session.signOut()
        }
        Button("Cancel", role: .cancel) {}
      }
      .task {
        await profiles.load(session: session)
        if let pipeline = session.pipeline {
          cacheUsage = await pipeline.usage()
        }
        if let store = session.store {
          storage = (try? await store.storagePrefs(for: session.userId)) ?? StoragePrefs()
        }
      }
    }
    .accessibilityIdentifier("account-sheet")
  }

  private var lastSyncedText: String {
    guard let last = session.lastSyncAt else { return "Never" }
    return Self.relativeFormatter.localizedString(for: last, relativeTo: Date())
  }

  private func setOptimizeStorage(_ enabled: Bool) {
    storage.optimizeStorage = enabled
    storage.originalTierBudgetBytes = enabled ? StoragePrefs.iOSDefaultOriginalBudgetBytes : nil
    Task {
      if let store = session.store {
        try? await store.setStoragePrefs(storage, for: session.userId)
      }
      await session.pipeline?.setBudget(storage.originalTierBudgetBytes, for: .original)
      if let pipeline = session.pipeline {
        cacheUsage = await pipeline.usage()
      }
    }
  }

  private static var appVersion: String {
    let short =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    return build.isEmpty ? short : "\(short) (\(build))"
  }
}
