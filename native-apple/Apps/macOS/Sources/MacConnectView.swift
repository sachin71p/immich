import ImmichAPI
import SwiftUI

/// macOS sign-in (A0 "Connect to server" screen, wired to `MacAppState` so a successful login
/// lands straight in the library; the shared `ConnectView` stays iOS-owned).
struct MacConnectView: View {
  @Bindable var state: MacAppState
  @State private var serverURL: String
  @State private var email = ""
  @State private var password = ""
  @State private var status = ""
  @State private var isWorking = false

  init(state: MacAppState) {
    self.state = state
    _serverURL = State(initialValue: state.serverURL.absoluteString)
  }

  var body: some View {
    Form {
      Text("Connect to server").font(.title2)
      TextField("Server URL", text: $serverURL).accessibilityIdentifier("connect-url")
      TextField("Email", text: $email).accessibilityIdentifier("connect-email")
      SecureField("Password", text: $password).accessibilityIdentifier("connect-password")
      Button("Connect") { connect() }
        .disabled(isWorking)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("connect-button")
      if !status.isEmpty { Text(status).accessibilityIdentifier("connect-status") }
    }
    .accessibilityIdentifier(AXIDs.connectForm)
    .padding()
    .frame(minWidth: 360)
  }

  private func connect() {
    isWorking = true
    status = ""
    Task { @MainActor in
      do {
        guard let url = URL(string: serverURL) else { throw ConnectionError.insecureServerURL }
        let probe = try ImmichConnection(serverURL: url)
        try await probe.ping()
        let token = try await probe.login(email: email, password: password)
        try await state.completeLogin(serverURL: url, token: token)
        await state.syncNow()
      } catch {
        status = "Could not connect: \(error.localizedDescription)"
      }
      isWorking = false
    }
  }
}
