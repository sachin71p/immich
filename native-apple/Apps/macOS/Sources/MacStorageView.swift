import CoreModel
import Media
import SwiftUI

// MARK: - Storage optimization (A6 macOS: "Optimize Mac Storage")

// Cache budget slider (same steps as iOS, desktop-sized default), per-library/album
// "Keep originals on this Mac" pins, usage breakdown per tier, and purge.
struct MacStorageView: View {
  @Bindable var state: MacAppState
  @State private var storage = StoragePrefs()
  @State private var budgetIndex: Double = 4
  @State private var cacheUsage: [MediaTier: Int] = [:]
  @State private var error: String?

  private var steps: [Int] { StoragePrefs.budgetStepsBytes }

  var body: some View {
    Group {
      Section("Originals Budget") {
        Slider(
          value: $budgetIndex, in: 0...Double(steps.count - 1), step: 1
        ) {
          Text("Originals budget")
        } minimumValueLabel: {
          Text(Self.formatBytes(steps.first ?? 0))
        } maximumValueLabel: {
          Text(Self.formatBytes(steps.last ?? 0))
        }
        .accessibilityIdentifier("storage-budget-slider")
        .onChange(of: budgetIndex) { _, _ in Task { await applyBudget() } }
        LabeledContent("Budget", value: Self.formatBytes(currentBudget))
        Text("Thumbnails are always kept; originals past this budget are evicted least-recently-used first. Pinned libraries below are never evicted.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Keep Originals on This Mac") {
        if state.libraries.isEmpty && state.albums.isEmpty {
          Text("Libraries and albums appear after the first sync.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        ForEach(state.libraries, id: \.library.id) { entry in
          Toggle(
            "Library: \(entry.library.name)",
            isOn: pinBinding(entry.library.id)
          )
          .accessibilityIdentifier("storage-pin-\(entry.library.id)")
        }
        ForEach(state.albums, id: \.album.id) { entry in
          Toggle(
            "Album: \(entry.album.name)",
            isOn: pinBinding(entry.album.id)
          )
          .accessibilityIdentifier("storage-pin-\(entry.album.id)")
        }
      }
      Section("Usage") {
        ForEach(MediaTier.allCases, id: \.self) { tier in
          LabeledContent(
            tier.rawValue.capitalized,
            value: Self.formatBytes(cacheUsage[tier] ?? 0))
        }
        LabeledContent("Total", value: Self.formatBytes(cacheUsage.values.reduce(0, +)))
        HStack {
          Button("Refresh Usage") { Task { await refreshUsage() } }
          Spacer()
          Button("Purge Unpinned…", role: .destructive) { Task { await purge() } }
            .accessibilityIdentifier("storage-purge")
        }
      }
      if let error {
        Section { Text(error).foregroundStyle(.red).font(.caption) }
      }
    }
    .task {
      await load()
    }
  }

  private var currentBudget: Int {
    steps[max(0, min(Int(budgetIndex), steps.count - 1))]
  }

  private func pinBinding(_ id: String) -> Binding<Bool> {
    Binding(
      get: { storage.isPinnedContainer(id) },
      set: { pinned in
        if pinned, !storage.pinnedContainerIds.contains(id) {
          storage.pinnedContainerIds.append(id)
        } else if !pinned {
          storage.pinnedContainerIds.removeAll { $0 == id }
        }
        Task { await saveStorage() }
      }
    )
  }

  private func load() async {
    guard let userId = state.userId else { return }
    storage = (try? await state.store.storagePrefs(for: userId)) ?? StoragePrefs()
    let budget = storage.originalTierBudgetBytes ?? StoragePrefs.macDefaultOriginalBudgetBytes
    if let index = steps.firstIndex(of: budget) {
      budgetIndex = Double(index)
    }
    await state.pipeline.setBudget(storage.originalTierBudgetBytes, for: .original)
    await refreshUsage()
  }

  private func applyBudget() async {
    storage.originalTierBudgetBytes = currentBudget
    storage.optimizeStorage = currentBudget < StoragePrefs.macDefaultOriginalBudgetBytes
    await state.pipeline.setBudget(currentBudget, for: .original)
    await saveStorage()
    await refreshUsage()
  }

  private func purge() async {
    for tier in MediaTier.allCases {
      let usage = await state.pipeline.usage()
      _ = await state.pipeline.evict(freeing: usage[tier] ?? 0, from: tier)
    }
    await refreshUsage()
  }

  private func refreshUsage() async {
    cacheUsage = await state.pipeline.usage()
  }

  private func saveStorage() async {
    guard let userId = state.userId else { return }
    do {
      try await state.store.setStoragePrefs(storage, for: userId)
    } catch is CancellationError {
      // Cancellation isn't a failure: keep the previous storage prefs.
    } catch {
      HeirloomLog.ui.error("Storage prefs save failed: \(error.localizedDescription, privacy: .public)")
      self.error = "Couldn't save storage settings."
    }
  }

  static func formatBytes(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
  }
}
