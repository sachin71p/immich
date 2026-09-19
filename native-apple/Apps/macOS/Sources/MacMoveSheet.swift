import CoreModel
import LocalStore
import Rules
import SwiftUI

/// "Move to…" sheet (brief task 3, ⌘⇧M): lists only allowed targets — `MoveTargets.allowed`
/// per DECISIONS §6, intersected across the whole expanded selection (rule 5: one failing group
/// fails that group; the sheet offers targets valid for every selected group). Moves into an
/// external library need an explicit confirm (brief task 1); the result toast surfaces per-asset
/// `moved | noop | error(reason)`.
struct MacMoveSheet: View {
  @Bindable var state: MacAppState
  var assetIds: [String]
  var onDone: (_ results: [MoveResult]) -> Void

  /// Tagged List rows so currents and targets never share a `ForEach` identity,
  /// even when the cross-group union offers another group's current container.
  enum SheetRow: Hashable {
    case current(MoveTarget)
    case target(MoveTarget)
  }

  @State private var targets: [MoveTarget] = []
  @State private var currentContainers: [MoveTarget] = []
  @State private var selected: MoveTarget?
  @State private var pendingConfirm: MoveTarget?
  @State private var error: String?
  @State private var isWorking = false

  private var sheetRows: [SheetRow] {
    currentContainers.map(SheetRow.current) + targets.map(SheetRow.target)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Move \(assetIds.count) item\(assetIds.count == 1 ? "" : "s") to…")
        .font(.headline)
        .accessibilityIdentifier("move-sheet-title")
      if let error {
        Text(error).foregroundStyle(.red).font(.caption)
      }
      if targets.isEmpty && !isWorking {
        Text("No available destinations for this selection.")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("move-sheet-empty")
      } else {
        List {
          // One ForEach over tagged rows: a target can equal another group's current
          // container (union across groups), and two sibling `ForEach(..., id: \.self)`
          // would hand SwiftUI duplicate identities — rows duplicate and targets vanish.
          ForEach(sheetRows, id: \.self) { row in
            switch row {
            case .current(let current):
              HStack {
                Label(Self.title(for: current, state: state), systemImage: Self.icon(for: current))
                Spacer()
                Text("Current").font(.caption).foregroundStyle(.secondary)
              }
              .foregroundStyle(.secondary)
              .disabled(true)
              .accessibilityIdentifier("move-current-\(Self.key(for: current))")
            case .target(let target):
              Button {
                selected = target
              } label: {
                HStack {
                  Label(Self.title(for: target, state: state), systemImage: Self.icon(for: target))
                  Spacer()
                  if selected == target {
                    Image(systemName: "checkmark")
                  }
                }
              }
              .buttonStyle(.plain)
              .disabled(isWorking)
              .accessibilityIdentifier("move-target-\(Self.key(for: target))")
            }
          }
        }
        .frame(minHeight: 160)
      }
      HStack {
        Spacer()
        if isWorking {
          ProgressView().controlSize(.small)
        }
        Button("Cancel") { onDone([]) }
          .keyboardShortcut(.cancelAction)
          .disabled(isWorking)
        Button("Move") { confirmOrPerform() }
          .keyboardShortcut(.defaultAction)
          .disabled(selected == nil || isWorking)
          .accessibilityIdentifier("move-sheet-confirm")
      }
    }
    .padding()
    .frame(minWidth: 320)
    .task { await computeTargets() }
    .alert(
      Self.confirmTitle(for: pendingConfirm, count: assetIds.count, state: state),
      isPresented: Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } })
    ) {
      Button("Move", role: .destructive) {
        if let target = pendingConfirm { Task { await performMove(to: target) } }
      }
      Button("Cancel", role: .cancel) { pendingConfirm = nil }
    } message: {
      Text(Self.confirmMessage(for: pendingConfirm, state: state))
    }
  }

  private func confirmOrPerform() {
    guard let target = selected else { return }
    // WP4 Step 2: space moves confirm exactly like library moves; personal applies directly.
    switch target {
    case .space, .library: pendingConfirm = target
    case .personal: Task { await performMove(to: target) }
    }
  }

  /// WP4 Step 2: space moves use the same confirmation as library moves.
  static func confirmTitle(for target: MoveTarget?, count: Int, state: MacAppState?) -> String {
    guard let target else { return "Move?" }
    if case .space = target {
      return "Move \(count) item\(count == 1 ? "" : "s") to \(title(for: target, state: state))?"
    }
    return "Move into external library?"
  }

  static func confirmMessage(for target: MoveTarget?, state: MacAppState?) -> String {
    guard let target else { return "" }
    if case .space = target {
      return "Members of \(title(for: target, state: state)) will see them."
    }
    return "Files leave the import path once moved. This cannot be undone automatically."
  }

  private func computeTargets() async {
    do {
      guard let userId = state.userId else { return }
      let groups = try await state.expandGroups(ids: assetIds)
      let ctx = try await state.store.accessContext(for: userId)
      // One asset failing fails its whole group (rule 5: intersect per asset within a
      // group); other groups still proceed, so the sheet offers the union across groups and
      // the per-asset `moved | noop | error(reason)` results surface in the result toast.
      var offered = Set<MoveTarget>()
      for group in groups {
        var groupTargets: Set<MoveTarget>?
        for asset in group {
          let allowed = MoveTargets.allowed(for: asset, in: ctx)
          groupTargets = groupTargets.map { $0.intersection(allowed) } ?? allowed
        }
        offered.formUnion(groupTargets ?? [])
      }
      targets = offered.sorted(by: Self.order)
      currentContainers = Set(groups.flatMap { $0 }.map { Self.currentTarget(of: $0.container) })
        .sorted(by: Self.order)
    } catch is CancellationError {
      // Cancellation isn't a failure: leave the sheet as-is with no error.
    } catch {
      HeirloomLog.ui.error("Move targets failed: \(error.localizedDescription, privacy: .public)")
      self.error = error.localizedDescription
    }
  }

  /// `MoveTargets.allowed` never offers the current container (rule 7), so the sheet
  /// renders it separately as a disabled "Current" row (WP4 Step 2, U13 clarity).
  static func currentTarget(of container: Container) -> MoveTarget {
    switch container {
    case .personal: return .personal
    case .space(let id): return .space(id)
    case .library(let id): return .library(id)
    }
  }

  private func performMove(to target: MoveTarget) async {
    isWorking = true
    HeirloomQuitGuard.shared.isMoveInProgress = true
    defer {
      isWorking = false
      HeirloomQuitGuard.shared.isMoveInProgress = false
    }
    do {
      let results = try await state.assetMutations().move(ids: assetIds, to: target)
      await state.refresh()
      pendingConfirm = nil
      onDone(results)
    } catch is CancellationError {
      // Cancellation isn't a failure: leave the sheet open with no error.
    } catch {
      HeirloomLog.ui.error("Move failed: \(error.localizedDescription, privacy: .public)")
      self.error = error.localizedDescription
    }
  }

  static func order(_ lhs: MoveTarget, _ rhs: MoveTarget) -> Bool {
    title(for: lhs, state: nil) < title(for: rhs, state: nil)
  }

  static func title(for target: MoveTarget, state: MacAppState?) -> String {
    switch target {
    case .personal: return "Personal Library"
    case .space(let id):
      if let name = state?.spaces.first(where: { $0.space.id == id })?.space.name { return name }
      return "Shared Library"
    case .library(let id):
      if let name = state?.libraries.first(where: { $0.library.id == id })?.library.name { return name }
      return "External Library"
    }
  }

  static func key(for target: MoveTarget) -> String {
    switch target {
    case .personal: return "personal"
    case .space(let id): return "space-\(id)"
    case .library(let id): return "library-\(id)"
    }
  }

  static func icon(for target: MoveTarget) -> String {
    switch target {
    case .personal: return "person"
    case .space: return "person.2.circle"
    case .library: return "externaldrive"
    }
  }
}
