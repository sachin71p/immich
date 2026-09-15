import Foundation
import ImmichAPI

/// Raw `POST /sync/stream` transport. Bypasses the generated `Operations.getSyncStream` — the OpenAPI
/// document has no `content` for its 200 response (`@Res()` in `server/src/controllers/sync.controller.ts`
/// bypasses Nest's DTO serialization, so swift-openapi-generator can't see a body type to generate — see
/// the A1 handoff) and its request `types` enum is stale (`SyncRequestTypes`). `URLSession.bytes(for:)`'s
/// `AsyncBytes.lines` gives bounded-memory, line-at-a-time reads of the chunked NDJSON response, which is
/// exactly what a typed generated client couldn't have given us here anyway.
struct SyncStreamClient: Sendable {
  let connection: ImmichConnection
  var urlSession: URLSession = .shared

  /// Opens the stream and yields each raw JSON-lines line's UTF-8 bytes.
  func lines(types: [String], reset: Bool) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var request = URLRequest(url: connection.serverURL.appendingPathComponent("sync/stream"))
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          if let token = await connection.tokenStore.get() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          }
          request.httpBody = try JSONSerialization.data(withJSONObject: ["types": types, "reset": reset])

          let (bytes, response) = try await urlSession.bytes(for: request)
          if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SyncStreamError.httpStatus(http.statusCode)
          }
          for try await line in bytes.lines {
            try Task.checkCancellation()
            continuation.yield(Data(line.utf8))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

enum SyncStreamError: Error, Sendable {
  case httpStatus(Int)
}
