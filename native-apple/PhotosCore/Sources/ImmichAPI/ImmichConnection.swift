import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// A small app-facing facade over the generated operations selected in the OpenAPI filter.
public struct ImmichConnection: Sendable {
  private let client: Client

  public init(serverURL: URL) throws {
    guard serverURL.scheme?.lowercased() == "https", serverURL.host != nil else {
      throw ConnectionError.insecureServerURL
    }
    client = Client(serverURL: serverURL, transport: URLSessionTransport())
  }

  public func ping() async throws {
    let output = try await client.pingServer(.init())
    guard case let .ok(response) = output, case let .json(body) = response.body, body.res == "pong" else {
      throw ConnectionError.unexpectedPingResponse
    }
  }

  public func login(email: String, password: String) async throws -> String {
    let input = Operations.Login.Input(body: .json(.init(email: email, password: password)))
    let output = try await client.login(input)
    guard case let .created(response) = output, case let .json(body) = response.body else {
      throw ConnectionError.unexpectedLoginResponse
    }
    return body.accessToken
  }
}

public enum ConnectionError: Error, Sendable {
  case insecureServerURL
  case unexpectedPingResponse
  case unexpectedLoginResponse
}
