import Foundation
import Testing

@testable import ImmichAPI

/// Guards the DEBUG-only loopback carve-out in `ImmichConnection.isPermittedServerURL`.
///
/// Production reachability is HTTPS-only (A0: Tailscale MagicDNS, no ATS exceptions). DEBUG builds
/// additionally allow plain HTTP to loopback so the app can run against the local e2e stack. These
/// tests exist so that carve-out cannot silently widen to arbitrary hosts.
struct ConnectionSecurityTests {
  @Test func httpsIsAlwaysPermitted() {
    #expect(ImmichConnection.isPermittedServerURL(URL(string: "https://immich.example.ts.net")!))
    #expect(ImmichConnection.isPermittedServerURL(URL(string: "https://localhost:2285")!))
  }

  @Test func nonLoopbackHttpIsRejected() {
    for raw in [
      "http://immich.example.com",
      "http://192.168.7.177:2283",
      "http://localhost.evil.com:2285",
      "http://notlocalhost",
    ] {
      #expect(!ImmichConnection.isPermittedServerURL(URL(string: raw)!), "should reject \(raw)")
    }
  }

  @Test func nonHttpSchemesAndHostlessURLsAreRejected() {
    #expect(!ImmichConnection.isPermittedServerURL(URL(string: "ftp://localhost")!))
    #expect(!ImmichConnection.isPermittedServerURL(URL(string: "file:///tmp/x")!))
    #expect(!ImmichConnection.isPermittedServerURL(URL(string: "https:///nohost")!))
  }

  #if DEBUG
    @Test func loopbackHttpIsPermittedInDebugOnly() {
      for raw in ["http://localhost:2285", "http://127.0.0.1:2285", "http://LOCALHOST:2285"] {
        #expect(ImmichConnection.isPermittedServerURL(URL(string: raw)!), "should allow \(raw)")
      }
    }

    @Test func initAcceptsLoopbackHttpInDebug() throws {
      let connection = try ImmichConnection(serverURL: URL(string: "http://localhost:2285")!)
      #expect(connection.serverURL.host == "localhost")
    }
  #endif
}

/// Guards `ImmichConnection.normalizedAPIBaseURL`.
///
/// The OpenAPI spec's server is the relative `/api`, so the client must be built with that base.
/// A raw origin makes the client hit `/server/ping`, which returns the web app's HTML with HTTP 200 —
/// a valid response that is not `pong`, surfacing as an opaque `unexpectedPingResponse`.
struct APIBaseURLTests {
  private func normalized(_ raw: String) -> String {
    ImmichConnection.normalizedAPIBaseURL(URL(string: raw)!).absoluteString
  }

  @Test func appendsAPIToAnOrigin() {
    #expect(normalized("https://host.tailnet.ts.net") == "https://host.tailnet.ts.net/api")
    #expect(normalized("https://host.tailnet.ts.net/") == "https://host.tailnet.ts.net/api")
    #expect(normalized("http://localhost:2285") == "http://localhost:2285/api")
  }

  @Test func isIdempotent() {
    #expect(normalized("https://host/api") == "https://host/api")
    #expect(normalized("https://host/api/") == "https://host/api")
    #expect(normalized(normalized("https://host")) == "https://host/api")
  }

  @Test func preservesAReverseProxyBasePath() {
    #expect(normalized("https://host/photos") == "https://host/photos/api")
    #expect(normalized("https://host/photos/") == "https://host/photos/api")
    #expect(normalized("https://host/photos/api") == "https://host/photos/api")
  }

  @Test func doesNotMatchAPrefixThatMerelyStartsWithAPI() {
    #expect(normalized("https://host/apifoo") == "https://host/apifoo/api")
  }

  @Test func dropsQueryAndFragment() {
    #expect(normalized("https://host?token=abc") == "https://host/api")
    #expect(normalized("https://host/api#section") == "https://host/api")
  }

  @Test func connectionExposesTheNormalizedBase() throws {
    let connection = try ImmichConnection(serverURL: URL(string: "https://host.tailnet.ts.net")!)
    #expect(connection.serverURL.absoluteString == "https://host.tailnet.ts.net/api")
  }
}
