import CoreModel
import Foundation
import ImmichAPI
import Media

/// Live `BackedUpChecksumVerifier`: batched `POST /assets/bulk-upload-check` calls.
/// `reject` + `duplicate` proves the bytes exist server-side; `accept` means missing and
/// `isTrashed` means deleted — both are excluded from the verified set. Already in the
/// OpenAPI filter (`checkBulkUpload`), so no generator change is needed.
public struct ServerChecksumVerifier: BackedUpChecksumVerifier {
  public let connection: ImmichConnection
  public var batchSize: Int

  public init(connection: ImmichConnection, batchSize: Int = 100) {
    self.connection = connection
    self.batchSize = batchSize
  }

  public func verified(checksums: [String]) async throws -> Set<String> {
    let unique = Array(Set(checksums))
    guard !unique.isEmpty else { return [] }
    let size = max(batchSize, 1)
    var confirmed = Set<String>()
    var index = unique.startIndex
    while index < unique.endIndex {
      let end = unique.index(index, offsetBy: size, limitedBy: unique.endIndex) ?? unique.endIndex
      let chunk = Array(unique[index..<end])
      let input = Operations.checkBulkUpload.Input(
        body: .json(.init(assets: chunk.map {
          Components.Schemas.AssetBulkUploadCheckItem(checksum: $0, id: $0)
        })))
      let output = try await connection.client.checkBulkUpload(input)
      guard case let .ok(response) = output, case let .json(body) = response.body else {
        throw FreeUpSpaceVerificationError.unexpectedResponse
      }
      for result in body.results {
        let isDuplicate = result.action.rawValue == "reject" && result.reason?.rawValue == "duplicate"
        if isDuplicate && !(result.isTrashed ?? false) {
          confirmed.insert(result.id)
        }
      }
      index = end
    }
    return confirmed
  }
}

public enum FreeUpSpaceVerificationError: Error, Sendable {
  case unexpectedResponse
}
