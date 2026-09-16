import Testing
@testable import SyncEngine

/// [WP3FIX] Gate-3 root fix, decision level: a timer-driven sync that applied nothing must not
/// bump the grid's `timelineVersion` (the full `syncWithResult` session needs a server, so the
/// reload contract on `SyncResult` is pinned here; `MacAppState.syncNow` wires it through).
@Suite struct SyncResultTests {
  @Test("timer sync with no applied changes does not reload the timeline")
  func timerNoChangeNoReload() {
    let result = SyncCoordinator.SyncResult(didRun: true, appliedChanges: false)
    #expect(result.shouldReloadTimeline(userInitiated: false) == false)
  }

  @Test("user-initiated syncs keep the historical always-reload behavior")
  func userInitiatedAlwaysReloads() {
    let result = SyncCoordinator.SyncResult(didRun: true, appliedChanges: false)
    #expect(result.shouldReloadTimeline(userInitiated: true) == true)
  }

  @Test("applied changes reload regardless of initiator")
  func appliedChangesReload() {
    let result = SyncCoordinator.SyncResult(didRun: true, appliedChanges: true)
    #expect(result.shouldReloadTimeline(userInitiated: false) == true)
    #expect(result.shouldReloadTimeline(userInitiated: true) == true)
  }

  @Test("dropped syncs never reload")
  func droppedNeverReloads() {
    let result = SyncCoordinator.SyncResult(didRun: false, appliedChanges: false)
    #expect(result.shouldReloadTimeline(userInitiated: true) == false)
    #expect(result.shouldReloadTimeline(userInitiated: false) == false)
  }
}
