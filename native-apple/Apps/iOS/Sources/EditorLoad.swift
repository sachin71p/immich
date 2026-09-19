import Foundation

/// WP-R (F1/F2/F3/F3b): bounded waits for the editor/video load path.
///
/// Profiling proved the editor is *idle*, not slow (~1% CPU, parked in
/// `__CFRunLoopRun`/`completeTaskWithClosure`): an `await` on the load path never
/// resolves and nothing falls back to the already-decoded preview. Every wait on
/// the Edit → canvas path must therefore be bounded and must leave the preview
/// in place on failure. Callers implement
/// "preview first, upgrade when it arrives, never replace with empty".
public enum EditorLoadError: Error, Equatable {
  case timedOut(seconds: Double)
}

public enum EditorLoadBudget {
  /// Present-gate when nothing is cached: the viewer is still visible underneath,
  /// so a short wait here never shows black.
  public static let cachedPreviewFetch: Double = 3
  /// Full-res original upgrade after the editor is already showing the preview.
  public static let fullOriginalUpgrade: Double = 30
  /// Video duration probe (`AVAsset.load(.duration)` + file download for edit).
  public static let videoDurationProbe: Double = 10
  /// Player-item readiness wait after the user taps play.
  public static let playerReady: Double = 5
}

/// Bounds `operation` by a `seconds` deadline. Returns the operation's value
/// when it wins; throws `EditorLoadError.timedOut` when the deadline wins, in
/// which case the loser is cancelled.
///
/// Deliberately MainActor-confined rather than a task group: the editor/video
/// load closures capture MainActor state (view properties, `AVPlayerItem`,
/// loader closures) that a `@Sendable` task-group child cannot touch. Both
/// halves run MainActor-confined, so the first-settled guard needs no extra
/// synchronization. Foundation-only, verifiable off-device.
///
/// On timeout this stops *waiting* but never cancels the loser: cancelling an
/// in-flight `AVAsset.load` can poison the shared asset and fail the player
/// item itself with a cancellation-flavored error (F2's "Operation Stopped").
/// A late result is ignored by the first-settled guard.
@MainActor
public func withMainActorTimeout<T: Sendable>(
  seconds: Double,
  operation: @MainActor @escaping () async throws -> T
) async throws -> T {
  precondition(seconds > 0, "withMainActorTimeout requires a positive deadline")
  return try await withCheckedThrowingContinuation { continuation in
    var settled = false
    func settle(_ result: Result<T, any Error>) {
      guard !settled else { return }
      settled = true
      continuation.resume(with: result)
    }
    let probe = Task { @MainActor in
      do {
        settle(.success(try await operation()))
      } catch {
        settle(.failure(error))
      }
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      settle(.failure(EditorLoadError.timedOut(seconds: seconds)))
    }
  }
}
