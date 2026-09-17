import SwiftUI

// MARK: - account avatar button (WP5 T3)

/// The account avatar (initials over the accent tint, person-glyph fallback) that opens
/// the account sheet. WP4 mounts this in the Collections toolbar; until then Search
/// hosts one so the sheet is reachable and tour-covered.
struct AccountButton: View {
  @EnvironmentObject var session: AppSession
  @StateObject private var profiles = AccountProfileStore()
  @State private var showSheet = false

  var body: some View {
    Button {
      showSheet = true
    } label: {
      AccountAvatarView(name: profiles.profile?.name, diameter: 28)
    }
    .accessibilityIdentifier("account-button")
    .accessibilityLabel("Account")
    .sheet(isPresented: $showSheet) {
      AccountSheet()
        .environmentObject(session)
        .environmentObject(profiles)
    }
    .task {
      await profiles.load(session: session)
    }
  }
}

/// Circular avatar: initials when a name is known, a person glyph otherwise.
struct AccountAvatarView: View {
  var name: String?
  var diameter: CGFloat = 28

  var body: some View {
    Group {
      if let initials = Self.initials(for: name) {
        Text(initials)
          .font(.system(size: diameter * 0.38, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: diameter, height: diameter)
          .background(Circle().fill(Color.accentColor))
      } else {
        Image(systemName: "person.crop.circle.fill")
          .resizable()
          .frame(width: diameter, height: diameter)
          .foregroundStyle(.secondary)
      }
    }
  }

  static func initials(for name: String?) -> String? {
    guard let name else { return nil }
    let parts = name.split(separator: " ").prefix(2).map { String($0.prefix(1)) }
    let joined = parts.joined().uppercased()
    return joined.isEmpty ? nil : joined
  }
}
