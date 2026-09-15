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

  @State private var targets: [MoveTarget] = []
  @State private var pendingConfirm: MoveTarget?
  @State private var error: String?
  @State private var isWorking = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Move \(assetIds.count) item\(assetIds.count == 1 ? "" : "s") to…")
        .font(.headline)
        .accessibilityIdentifier("move-sheet-title")
      if let error {
        Text(error).foregroundStyle(.red).font(.caption)
      }
      if isWorking {
        ProgressView().controlSize(.small)
      } else if targets.isEmpty {
        Text("No available destinations for this selection.")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("move-sheet-empty")
      } else {
        List(targets, id: \.self) { target in
          Button {
            tapped(target)
          } label: {
            Label(Self.title(for: target, state: state), systemImage: Self.icon(for: target))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("move-target-\(Self.key(for: target))")
        }
        .frame(minHeight: 160)
      }
    }
    .padding()
    .frame(minWidth: 320)
    .task { await computeTargets() }
    .alert(
      "Move into external library?",
      isPresented: Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } })
    ) {
      Button("Move", role: .destructive) {
        if let target = pendingConfirm { Task { await performMove(to: target) } }
      }
      Button("Cancel", role: .cancel) { pendingConfirm = nil }
    } message: {
      Text("Files leave the import path once moved. This cannot be undone automatically.")
    }
  }

  private func tapped(_ target: MoveTarget) {
    // Brief task 1: moves onto a library always confirm; space/personal moves apply directly.
    if case .library = target { pendingConfirm = target } else { Task { await performMove(to: target) } }
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
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func performMove(to target: MoveTarget) async {
    isWorking = true
    defer { isWorking = false }
    do {
      let results = try await state.assetMutations().move(ids: assetIds, to: target)
      await state.refresh()
      pendingConfirm = nil
      onDone(results)
    } catch {
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
