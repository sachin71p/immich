import Foundation

/// Video badge durations, in whole seconds (`Asset.durationSeconds`). Plain integer math — no
/// per-call formatter allocation on the grid's render path. Positive durations always render at
/// least `0:01`; non-positive input (shouldn't happen for a video badge) clamps to `0:00`.
public enum VideoDurationFormat {
  public static func string(seconds: Int) -> String {
    guard seconds > 0 else { return "0:00" }
    if seconds < 3600 {
      return String(format: "%d:%02d", seconds / 60, seconds % 60)
    } else {
      return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
  }
}
