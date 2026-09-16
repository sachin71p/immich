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

  /// Production requires HTTPS — A0 pins server reachability to Tailscale MagicDNS
  /// (`https://<host>.<tailnet>.ts.net`) with no ATS exceptions.
  ///
  /// DEBUG builds additionally accept plain HTTP to loopback, because the e2e stack
  /// (`docker-compose.fork.yml`, port 2285) serves HTTP only and there is otherwise no way to run
  /// the app against the deterministic test world. Release builds are unchanged: HTTPS or nothing.
  static func isPermittedServerURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
      return false
    }
    if scheme == "https" {
      return true
    }
    #if DEBUG
      return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    #else
      return false
    #endif
  }

  /// Resolves a user-entered server URL to the API base the generated client expects.
  ///
  /// `immich-openapi-specs.json` declares `servers: [{ url: "/api" }]` and operation paths relative
  /// to it (`pingServer` is `/server/ping`), so the client must be constructed with the `/api` base.
  /// Users enter the server's origin — `https://host.tailnet.ts.net` — and a raw origin makes the
  /// client request `/server/ping`, which the server answers with the web app's HTML: HTTP 200, but
  /// not `pong`, surfacing as an opaque `unexpectedPingResponse`.
  ///
  /// Idempotent, and preserves a non-root base path (`https://host/photos` → `https://host/photos/api`)
  /// for reverse-proxy deployments.
  static func normalizedAPIBaseURL(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }
    // An API base carries neither of these; dropping them keeps request URLs well-formed.
    components.query = nil
    components.fragment = nil

    var path = components.path
    while path.hasSuffix("/") {
      path.removeLast()
    }
    if path != "/api", !path.hasSuffix("/api") {
      path += "/api"
    }
    components.path = path
    return components.url ?? url
  }

  public init(serverURL: URL, accessToken: String? = nil) throws {
    guard Self.isPermittedServerURL(serverURL) else {
      throw ConnectionError.insecureServerURL
    }
    let serverURL = Self.normalizedAPIBaseURL(serverURL)
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
