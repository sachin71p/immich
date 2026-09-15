import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// Holds the current bearer token so it can be attached to every authenticated request and updated
/// after login/logout without recreating the `Client`. A0 Architecture: "access token in Keychain" —
/// the Keychain read/write itself lives in the app layer; this actor just holds the in-memory copy
/// the middleware reads from.
public actor TokenStore {
  private var token: String?

  public init(token: String? = nil) {
    self.token = token
  }

  public func set(_ token: String?) {
    self.token = token
  }

  public func get() -> String? {
    token
  }
}

/// Attaches `Authorization: Bearer <token>` to every request once a token is set; no-op before login.
struct BearerAuthMiddleware: ClientMiddleware {
  let tokenStore: TokenStore

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var request = request
    if let token = await tokenStore.get() {
      request.headerFields[.authorization] = "Bearer \(token)"
    }
    return try await next(request, body, baseURL)
  }
}

/// A small app-facing facade over the generated operations selected in the OpenAPI filter.
///
/// `client` is exposed directly (rather than re-wrapped one call at a time) so every module that needs
/// an authenticated operation — `SyncEngine`'s acks, `Rules`-driven mutations, later phases' Upload/Media
/// calls — uses the same generated `Operations`/`Components.Schemas` types without PhotosCore growing a
/// second, hand-maintained copy of the API surface. `openapi-generator-config.yaml`'s `filter.operations`
/// list remains the single source of truth for which server operations the app can call.
public struct ImmichConnection: Sendable {
  public let serverURL: URL
  public let tokenStore: TokenStore
  public let client: Client

  public init(serverURL: URL, accessToken: String? = nil) throws {
    guard serverURL.scheme?.lowercased() == "https", serverURL.host != nil else {
      throw ConnectionError.insecureServerURL
    }
    self.serverURL = serverURL
    let tokenStore = TokenStore(token: accessToken)
    self.tokenStore = tokenStore
    self.client = Client(
      serverURL: serverURL,
      transport: URLSessionTransport(),
      middlewares: [BearerAuthMiddleware(tokenStore: tokenStore)]
    )
  }

  public func ping() async throws {
    let output = try await client.pingServer(.init())
    guard case let .ok(response) = output, case let .json(body) = response.body, body.res == "pong" else {
      throw ConnectionError.unexpectedPingResponse
    }
  }

  public func login(email: String, password: String) async throws -> String {
    let input = Operations.login.Input(body: .json(.init(email: email, password: password)))
    let output = try await client.login(input)
    guard case let .created(response) = output, case let .json(body) = response.body else {
      throw ConnectionError.unexpectedLoginResponse
    }
    await tokenStore.set(body.accessToken)
    return body.accessToken
  }

  /// The signed-in user's id — `SyncEngine` needs this to tell "I lost access" apart from "someone else
  /// did" (DECISIONS §8) and to build `Rules.AccessContext`/`TimelineContext`.
  public func currentUserId() async throws -> String {
    let output = try await client.getMyUser(.init())
    guard case let .ok(response) = output, case let .json(body) = response.body else {
      throw ConnectionError.unexpectedCurrentUserResponse
    }
    return body.id
  }
}

public enum ConnectionError: Error, Sendable {
  case insecureServerURL
  case unexpectedPingResponse
  case unexpectedLoginResponse
  case unexpectedCurrentUserResponse
}
