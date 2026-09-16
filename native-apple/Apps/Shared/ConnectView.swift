import Security
import SwiftUI
import ImmichAPI

struct ConnectView: View {
  @State private var serverURL = "https://"
  @State private var email = ""
  @State private var password = ""
  @State private var status = ""

  var body: some View {
    Form {
      Text("Connect to server").font(.title2)
      TextField("Server URL", text: $serverURL)
      TextField("Email", text: $email)
      SecureField("Password", text: $password)
      Button("Connect") { connect() }
      if !status.isEmpty { Text(status) }
    }.padding()
  }

  private func connect() {
    Task {
      do {
        guard let url = URL(string: serverURL) else { throw ConnectionError.insecureServerURL }
        let connection = try ImmichConnection(serverURL: url)
        try await connection.ping()
        let token = try await connection.login(email: email, password: password)
        SharedTokenStore.saveBestEffort(token)
        SharedContainer.sharedDefaults.set(url.absoluteString, forKey: SharedContainer.serverURLKey)
        status = "Connected"
      } catch {
        status = "Could not connect: \(error.localizedDescription)"
      }
    }
  }
}

enum SharedTokenStore {
  static func save(_ token: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.immich.heirloom",
      kSecAttrAccount as String: "access-token",
      kSecAttrAccessGroup as String: "$(AppIdentifierPrefix)com.immich.heirloom.shared",
      kSecValueData as String: Data(token.utf8),
    ]
    SecItemDelete(query as CFDictionary)
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
  }
}

enum KeychainError: Error { case unexpectedStatus(OSStatus) }
