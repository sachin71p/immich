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

// MARK: - view prefs adopted from Photos (WP-P, PLAN §3 decision 5)

/// Photos-parity view settings. Persisted per device; shelves read them where the
/// owning surface supports it. Dismissal writers use the reset prefixes below.
@MainActor
enum HeirloomViewPrefs {
  @AppStorage("heirloom.zoomToFill") static var zoomToFill = false
  @AppStorage("heirloom.showRatings") static var showRatings = false
  @AppStorage("heirloom.showFeatured") static var showFeatured = true
  @AppStorage("heirloom.showHolidayEvents") static var showHolidayEvents = true

  /// Local-only suggestion state owned by the Reset buttons (PLAN §3 decision 5).
  /// Dismissal writers use these prefixes; the resets below clear them.
  static let suggestedMemoriesPrefix = "heirloom.suggested-memories."
  static let peopleSuggestionsPrefix = "heirloom.people-suggestions."

  static func resetSuggestedMemories() {
    removeKeys(withPrefix: suggestedMemoriesPrefix)
  }

  static func resetPeopleSuggestions() {
    removeKeys(withPrefix: peopleSuggestionsPrefix)
  }

  private static func removeKeys(withPrefix prefix: String) {
    let defaults = UserDefaults.standard
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
      defaults.removeObject(forKey: key)
    }
  }
}

// MARK: - account sheet (WP5 T3/T4; WP-P §3 merge)

/// The account sheet: Photos-style centred identity block (§3 decision 1), an
/// explicit Sync section kept alongside the identity `Last synced` line
/// (§3 decision 2), one merged Shared Libraries section (§3 decision 3),
/// Heirloom storage wording preserved verbatim (§3 decision 4), adopted Photos
/// view settings (§3 decision 5), and a Manage Keywords entry (§3 decision 6).
struct AccountSheet: View {
  @EnvironmentObject var session: AppSession
  @EnvironmentObject var profiles: AccountProfileStore
  @State private var showSources = false
  @State private var showSignOutConfirm = false
  @State private var showResetMemoriesConfirm = false
  @State private var showResetPeopleConfirm = false
  @State private var resetNotice: String?
  @State private var cacheUsage: [MediaTier: Int] = [:]
  @State private var storage = StoragePrefs()
  @State private var photoCount: Int?
  @State private var videoCount: Int?
  @Environment(\.dismiss) private var dismiss

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
  }()

  private static let countFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
  }()

  var body: some View {
    NavigationStack {
      List {
        identitySection
        accountSection
        syncSection
        sharedLibrariesSection
        keywordsSection
        viewSection
        featuredSection
        uploadSection
        backupSection
        timelineSection
        storageSection
        cacheSection
        signOutSection
        aboutSection
        if let resetNotice {
          Section { Text(resetNotice).font(.caption).foregroundStyle(.secondary) }
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
      .alert(
        "Reset Suggested Memories?",
        isPresented: $showResetMemoriesConfirm
      ) {
        Button("Reset") {
          HeirloomViewPrefs.resetSuggestedMemories()
          resetNotice = "Suggested memories were reset. New suggestions appear as they are generated."
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Clears locally dismissed memory suggestions. Saved memories are kept.")
      }
      .alert(
        "Reset People & Pets Suggestions?",
        isPresented: $showResetPeopleConfirm
      ) {
        Button("Reset") {
          HeirloomViewPrefs.resetPeopleSuggestions()
          resetNotice = "People and pets suggestions were reset."
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Clears locally dismissed people and pets suggestions. Named people are kept.")
      }
      .task {
        await profiles.load(session: session)
        await loadCounts()
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

  // MARK: identity (§3 decision 1 — closes P1/P2)

  @ViewBuilder
  private var identitySection: some View {
    Section {
      VStack(spacing: 6) {
        AccountAvatarView(name: profiles.profile?.name, diameter: 72)
          .accessibilityIdentifier("settings-avatar")
        Text(profiles.profile?.name ?? "Loading…")
          .font(.title3)
          .fontWeight(.semibold)
          .accessibilityIdentifier("account-name")
        Text(libraryCountsText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("settings-library-counts")
        Text("Last Synced \(lastSyncedText)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("settings-last-synced")
      }
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)
      .padding(.vertical, 8)
    }
  }

  /// The tappable Account detail row: the user ID and email live here
  /// (standing owner requirement), with the server host in its own row.
  @ViewBuilder
  private var accountSection: some View {
    Section {
      NavigationLink {
        AccountDetailView()
          .environmentObject(session)
          .environmentObject(profiles)
      } label: {
        HStack {
          Text("Account")
          Spacer()
          // LP9: email-primary — the email is the row's primary value; the
          // user ID stays visible (P2 standing rule) but demoted to a
          // secondary caption beneath it. The header block above never shows
          // the UUID at all.
          VStack(alignment: .trailing, spacing: 2) {
            if let email = profiles.profile?.email, !email.isEmpty {
              Text(email)
                .lineLimit(1)
                .accessibilityIdentifier("settings-user-email")
              Text(session.userId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("settings-user-id")
            } else {
              Text(session.userId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("settings-user-id")
            }
          }
        }
      }
      .accessibilityIdentifier("settings-account-row")
      LabeledContent("Server", value: profiles.host ?? "—")
    }
  }

  // MARK: sync (§3 decision 2 — both the identity line and this button stay)

  @ViewBuilder
  private var syncSection: some View {
    Section("Sync") {
      // `account-sync-now` is the pre-merge identifier (preserved); the
      // wrapper carries the WP-P identifier so both generations resolve.
      HStack {
        Button("Sync Now") {
          Task { await session.syncNow() }
        }
        .disabled(session.isSyncing)
        .accessibilityIdentifier("account-sync-now")
      }
      .accessibilityIdentifier("settings-sync-now")
      LabeledContent("Last synced", value: lastSyncedText)
      if session.isSyncing {
        ProgressView("Syncing…")
          .accessibilityIdentifier("settings-syncing")
      }
      if let lastError = session.lastError {
        Text(lastError)
          .foregroundStyle(.red)
          .font(.caption)
      }
    }
  }

  // MARK: shared libraries (§3 decision 3 — one merged section)

  @ViewBuilder
  private var sharedLibrariesSection: some View {
    Section("Shared Libraries") {
      NavigationLink("Manage…") {
        SpacesListView()
          .environmentObject(session)
      }
      .accessibilityIdentifier("account-shared-libraries")
      NavigationLink {
        InvitationsView()
      } label: {
        HStack {
          Text("Invitations and Access Requests")
          Spacer()
          if pendingInvitationCount > 0 {
            Text("\(pendingInvitationCount)")
              .font(.caption)
              .foregroundStyle(.white)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(Capsule().fill(.red))
          }
        }
      }
      .accessibilityIdentifier("settings-invitations")
    }
  }

  /// No invitations endpoint exists yet, so the badge reads 0 and the
  /// destination states that plainly instead of faking rows.
  private var pendingInvitationCount: Int { 0 }

  // MARK: keywords (§3 decision 6)

  @ViewBuilder
  private var keywordsSection: some View {
    Section {
      NavigationLink("Manage Keywords") {
        ManageKeywordsView()
          .environmentObject(session)
      }
      .accessibilityIdentifier("settings-manage-keywords")
    }
  }

  // MARK: adopted Photos view settings (§3 decision 5)

  @ViewBuilder
  private var viewSection: some View {
    Section("View") {
      Toggle(
        "Zoom to Fill Screen",
        isOn: Binding(
          get: { HeirloomViewPrefs.zoomToFill },
          set: { HeirloomViewPrefs.zoomToFill = $0 }))
        .accessibilityIdentifier("settings-zoom-to-fill")
      Text("Fill the screen edge to edge when viewing photos. Off shows the whole image.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Toggle(
        "Show Ratings Controls",
        isOn: Binding(
          get: { HeirloomViewPrefs.showRatings },
          set: { HeirloomViewPrefs.showRatings = $0 }))
        .accessibilityIdentifier("settings-show-ratings")
    }
  }

  @ViewBuilder
  private var featuredSection: some View {
    Section("Featured") {
      Toggle(
        "Show Featured Content",
        isOn: Binding(
          get: { HeirloomViewPrefs.showFeatured },
          set: { HeirloomViewPrefs.showFeatured = $0 }))
        .accessibilityIdentifier("settings-show-featured")
      Text("Show featured photos and memories in Collections.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Toggle(
        "Show Holiday Events",
        isOn: Binding(
          get: { HeirloomViewPrefs.showHolidayEvents },
          set: { HeirloomViewPrefs.showHolidayEvents = $0 }))
        .accessibilityIdentifier("settings-show-holiday-events")
      Button("Reset Suggested Memories") { showResetMemoriesConfirm = true }
        .accessibilityIdentifier("settings-reset-memories")
      Button("Reset People & Pets Suggestions") { showResetPeopleConfirm = true }
        .accessibilityIdentifier("settings-reset-people-suggestions")
    }
  }

  // MARK: preserved Heirloom sections (P4 — §3 decision 4 keeps storage wording)

  @ViewBuilder
  private var uploadSection: some View {
    Section("Upload") {
      UploadTargetPicker()
        .environmentObject(session)
    }
  }

  @ViewBuilder
  private var backupSection: some View {
    BackupSettingsSection()
      .environmentObject(session)
  }

  @ViewBuilder
  private var timelineSection: some View {
    Section("Timeline") {
      // The open sheet's root carries the same identifier (ScreenshotTour
      // opens it from Library); both resolve, before and after presentation.
      Button("Timeline Sources…") { showSources = true }
        .accessibilityIdentifier("timeline-sources")
    }
  }

  @ViewBuilder
  private var storageSection: some View {
    Section("Storage") {
      NavigationLink("Free Up Space…") {
        FreeUpSpaceView()
          .environmentObject(session)
      }
      .accessibilityIdentifier("settings-freeup")
      Toggle(
        "Optimize Storage",
        isOn: Binding(
          get: { storage.optimizeStorage },
          set: { new in setOptimizeStorage(new) }))
        .accessibilityIdentifier("settings-optimize-storage")
      Text("Optimize keeps thumbnails and shrinks originals to \(SettingsView.formatBytes(StoragePrefs.iOSDefaultOriginalBudgetBytes)). Turn it off to download originals.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var cacheSection: some View {
    Section("Cache Usage") {
      ForEach(MediaTier.allCases, id: \.self) { tier in
        LabeledContent(
          tier.rawValue.capitalized,
          value: SettingsView.formatBytes(cacheUsage[tier] ?? 0))
      }
    }
    .accessibilityIdentifier("settings-cache-usage")
  }

  @ViewBuilder
  private var signOutSection: some View {
    Section {
      Button("Sign Out", role: .destructive) {
        showSignOutConfirm = true
      }
      .accessibilityIdentifier("account-signout")
    }
  }

  @ViewBuilder
  private var aboutSection: some View {
    Section("About") {
      LabeledContent("Version", value: Self.appVersion)
    }
  }

  // MARK: data

  private var libraryCountsText: String {
    guard let photoCount, let videoCount else { return "Loading library…" }
    let photos = Self.countFormatter.string(from: NSNumber(value: photoCount)) ?? "\(photoCount)"
    let videos = Self.countFormatter.string(from: NSNumber(value: videoCount)) ?? "\(videoCount)"
    return "\(photos) Photos, \(videos) Videos"
  }

  private func loadCounts() async {
    guard let store = session.store, !session.userId.isEmpty else { return }
    do {
      let scope = try await session.timelineScope()
      let counts = try await store.mediaKindCounts(scope: scope)
      var photos = 0
      var videos = 0
      for (kind, n) in counts {
        switch kind {
        case .video: videos += n
        case .photo, .livePhoto, .panorama, .screenshot: photos += n
        }
      }
      photoCount = photos
      videoCount = videos
    } catch {
      if !error.isCancellation { session.lastError = error.localizedDescription }
    }
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
