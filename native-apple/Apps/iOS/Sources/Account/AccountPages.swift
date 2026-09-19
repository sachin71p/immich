import SwiftUI

// MARK: - WP-P account pages (PLAN §3)

/// Full identity detail behind the tappable Account row (§3 decision 1):
/// display name, user ID, email, and server host. The row itself already
/// carries `settings-user-id` / `settings-user-email`, so this detail uses
/// its own identifiers and never duplicates them in one hierarchy.
struct AccountDetailView: View {
  @EnvironmentObject var session: AppSession
  @EnvironmentObject var profiles: AccountProfileStore

  var body: some View {
    List {
      Section {
        VStack(spacing: 6) {
          AccountAvatarView(name: profiles.profile?.name, diameter: 64)
          Text(profiles.profile?.name ?? "Loading…")
            .font(.title3)
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.vertical, 8)
      }
      Section("Account") {
        LabeledContent("Name", value: profiles.profile?.name ?? "—")
        LabeledContent("User ID", value: session.userId)
          .accessibilityIdentifier("account-detail-user-id")
          .textSelection(.enabled)
        LabeledContent(
          "Email", value: displayEmail)
          .accessibilityIdentifier("account-detail-user-email")
          .textSelection(.enabled)
      }
      Section {
        LabeledContent("Server", value: profiles.host ?? "—")
      }
      if session.isFixture {
        Section {
          Text("Fixture mode — mutations hit no server.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Account")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("account-detail")
    .task { await profiles.load(session: session) }
  }

  private var displayEmail: String {
    guard let email = profiles.profile?.email, !email.isEmpty else { return "—" }
    return email
  }
}

/// Invitations and Access Requests (§3 decision 3). There is no invitations
/// endpoint yet, so this states the true empty state instead of faking rows;
/// the settings row's badge stays hidden at zero.
struct InvitationsView: View {
  var body: some View {
    List {
      Section {
        ContentUnavailableView(
          "No Pending Invitations",
          systemImage: "envelope.open",
          description: Text(
            "Shared library invitations and access requests will appear here."))
      }
    }
    .navigationTitle("Invitations")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("invitations")
  }
}

/// Manage Keywords (§3 decision 6), pairing with the Add Keywords field in the
/// §2 info panel (owned by WP-I — this file never touches the panel). No
/// keyword store exists in PhotosCore yet, so this manages the user's keyword
/// vocabulary locally per user id; the panel can adopt the same key later.
struct ManageKeywordsView: View {
  @EnvironmentObject var session: AppSession
  @State private var keywords: [String] = []
  @State private var draft = ""

  var body: some View {
    List {
      Section {
        HStack {
          TextField("New keyword", text: $draft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("manage-keywords-field")
          Button("Add") { addDraft() }
            .disabled(normalized(draft).isEmpty)
            .accessibilityIdentifier("manage-keywords-add")
        }
      }
      Section {
        if keywords.isEmpty {
          ContentUnavailableView(
            "No Keywords Yet",
            systemImage: "tag",
            description: Text(
              "Add keywords here to build a reusable vocabulary, or add them to a photo from its info panel."))
        } else {
          ForEach(keywords, id: \.self) { keyword in
            Text(keyword)
              .accessibilityIdentifier("keyword-\(keyword)")
          }
          .onDelete { offsets in
            keywords.remove(atOffsets: offsets)
            save()
          }
        }
      }
    }
    .navigationTitle("Manage Keywords")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("manage-keywords")
    .task { load() }
  }

  private var storageKey: String { "heirloom.keywords.\(session.userId)" }

  private func load() {
    keywords = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
  }

  private func save() {
    UserDefaults.standard.set(keywords, forKey: storageKey)
  }

  private func normalized(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func addDraft() {
    let keyword = normalized(draft)
    guard !keyword.isEmpty, !keywords.contains(keyword) else { return }
    keywords.append(keyword)
    keywords.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    draft = ""
    save()
  }
}
