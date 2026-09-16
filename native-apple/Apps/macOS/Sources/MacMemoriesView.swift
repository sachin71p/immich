import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI

/// WP6 slice A (U20): Photos-style memory cards + story player.
///
/// - Stories get cards in the top section; "On This Day" is grouped by year
///   (one card per year, newest first).
/// - Cards: preview-tier cover at 16:10 with 12 pt radius, title + item count.
/// - Click plays `MacStoryPlayerView` (Close, ‹ › buttons + arrow keys,
///   auto-advance, pause on click); "Show all photos" opens that memory's
///   photos in the standard grid. Empty state when there is nothing.
/// - Music stays OFF by default (A9.3) — the toggle only records the preference.
struct MacMemoriesView: View {
  @Bindable var state: MacAppState
  @State private var stories: [MemoryStory] = []
  @State private var onThisDay: [TimelineRow] = []
  @State private var playingStory: MemoryStory?
  @State private var gridTitle = ""
  @State private var gridSnapshot = TimelineGridSnapshot.empty
  @State private var gridGeneration = 0

  /// On-This-Day rows grouped by capture year, newest year first.
  private var yearsNewestFirst: [(year: Int, rows: [TimelineRow])] {
    let grouped = Dictionary(grouping: onThisDay) { row in
      row.localDateTime.map { Calendar.current.component(.year, from: $0) } ?? 0
    }
    return grouped.sorted { $0.key > $1.key }.map { (year: $0.key, rows: $0.value) }
  }

  var body: some View {
    if !gridTitle.isEmpty {
      memoryGrid
    } else if stories.isEmpty && onThisDay.isEmpty {
      ContentUnavailableView(
        "No Memories",
        systemImage: "clock",
        description: Text("Memories from past years will appear here."))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("mac-memories")
      .task { await reload() }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if !stories.isEmpty {
            memorySection(title: "Memories") {
              ForEach(stories) { story in
                Button { playingStory = story } label: {
                  MacMemoryCard(
                    title: story.title,
                    subtitle: story.memoryAt.formatted(date: .long, time: .omitted),
                    count: story.assetIds.count,
                    coverId: story.assetIds.first,
                    pipeline: state.pipeline, store: state.store)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mac-memory-\(story.memoryId)")
              }
            }
          }
          if !onThisDay.isEmpty {
            memorySection(title: "On This Day") {
              ForEach(yearsNewestFirst, id: \.year) { year, rows in
                let yearsAgo = Calendar.current.component(.year, from: Date()) - year
                let ago = yearsAgo <= 0 ? nil : " · \(yearsAgo) year\(yearsAgo == 1 ? "" : "s") ago"
                Button {
                  playingStory = MemoryStory(
                    memoryId: "on-this-day-\(year)",
                    title: "On This Day",
                    memoryAt: rows.first?.localDateTime ?? Date(),
                    assetIds: rows.map(\.id))
                } label: {
                  MacMemoryCard(
                    title: "On This Day",
                    subtitle: (rows.first?.localDateTime?.formatted(date: .long, time: .omitted) ?? "\(year)") + (ago ?? ""),
                    count: rows.count,
                    coverId: rows.first?.id,
                    pipeline: state.pipeline, store: state.store)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mac-memory-on-this-day-\(year)")
              }
            }
          }
        }
        .padding(16)
      }
      .accessibilityIdentifier("mac-memories")
      .task { await reload() }
      .sheet(item: $playingStory) { story in
        MacStoryPlayerView(story: story, pipeline: state.pipeline, store: state.store) {
          showAllPhotos(story: story)
        }
        .frame(minWidth: 700, minHeight: 520)
      }
    }
  }

  private func memorySection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.title2)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16, content: content)
    }
  }

  private var memoryGrid: some View {
    MacMemoryGridView(
      title: gridTitle, snapshot: gridSnapshot, state: state,
      onBack: { gridTitle = "" })
  }

  private func showAllPhotos(story: MemoryStory) {
    playingStory = nil
    Task {
      let rows = (try? await state.store.timelineRows(ids: story.assetIds)) ?? []
      gridGeneration += 1
      gridSnapshot = MacGridSnapshotBuilder.monthSnapshot(rows: rows, generation: gridGeneration)
      gridTitle = story.title
    }
  }

  private func reload() async {
    guard let userId = state.userId else { return }
    do {
      let memories = try await state.store.savedMemories(forOwner: userId)
      var built: [MemoryStory] = []
      for memory in memories {
        let ids = try await state.store.assetIds(forMemory: memory.id)
        guard !ids.isEmpty else { continue }
        built.append(MemoryStory(
          memoryId: memory.id, title: MemoryStory.title(for: memory),
          memoryAt: memory.memoryAt, assetIds: ids))
      }
      stories = built
      let ctx = try await state.store.timelineContext(for: userId)
      let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
      let now = Date()
      let calendar = Calendar.current
      onThisDay = try await state.store.onThisDayAssets(
        scope: scope,
        month: calendar.component(.month, from: now),
        day: calendar.component(.day, from: now))
    } catch {}
  }
}

/// One memory's photos in the standard grid (Months), with a Back button.
private struct MacMemoryGridView: View {
  var title: String
  var snapshot: TimelineGridSnapshot
  var state: MacAppState
  var onBack: () -> Void
  @State private var selectedIds = Set<String>()
  @State private var itemSize: CGFloat = 160

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button { onBack() } label: { Label("Memories", systemImage: "chevron.left") }
        Text(title).font(.title2)
        Spacer()
        Text("\(snapshot.rows.count) item\(snapshot.rows.count == 1 ? "" : "s")")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      MacCollectionGridView(
        snapshot: snapshot,
        lastPatch: (snapshot.revision, []),
        pipeline: state.pipeline,
        store: state.store,
        exporter: nil,
        itemSize: itemSize,
        selectedIds: $selectedIds,
        onSelectionChange: { _ in },
        onOpen: { _ in },
        onPreview: { _ in },
        onToggleFavorite: { _ in },
        onMagnify: { itemSize = MacTimelineLayout.clampedItemSide(itemSize + $0) }
      )
    }
    .accessibilityIdentifier("mac-memory-grid")
  }
}

/// Photos-style card: preview-tier 16:10 cover, 12 pt radius, title + count.
private struct MacMemoryCard: View {
  var title: String
  var subtitle: String
  var count: Int
  var coverId: String?
  var pipeline: MediaPipeline
  var store: PhotosLocalStore

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Group {
        if let coverId {
          MacStoryCover(assetId: coverId, pipeline: pipeline, store: store, tier: .preview)
        } else {
          Rectangle().fill(.gray.opacity(0.3))
        }
      }
      .aspectRatio(16.0 / 10.0, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      Text(title).font(.headline).lineLimit(1)
      Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
      Text("\(count) item\(count == 1 ? "" : "s")")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

private struct MacStoryCover: View {
  var assetId: String
  var pipeline: MediaPipeline
  var store: PhotosLocalStore
  var tier: MediaTier = .thumbnail
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Rectangle().fill(.gray.opacity(0.3))
      }
    }
    .task(id: assetId) {
      guard let asset = try? await store.asset(id: assetId),
        let loaded = try? await pipeline.load(asset: asset, tier: tier)
      else { return }
      switch loaded.content {
      case .placeholder(let img): image = img
      case .tier(_, let img, _): image = img
      }
    }
  }
}

/// Full-screen story player: Close, ‹ › buttons + arrow keys, auto-advance,
/// pause on click, and "Show all photos".
struct MacStoryPlayerView: View {
  var story: MemoryStory
  var pipeline: MediaPipeline
  var store: PhotosLocalStore
  var onShowAll: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var player: MemoryStoryPlayer
  @State private var musicEnabled = false
  @State private var paused = false
  @State private var image: NSImage?

  init(story: MemoryStory, pipeline: MediaPipeline, store: PhotosLocalStore, onShowAll: @escaping () -> Void = {}) {
    self.story = story
    self.pipeline = pipeline
    self.store = store
    self.onShowAll = onShowAll
    _player = State(initialValue: MemoryStoryPlayer(story: story))
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack {
        HStack {
          Button { retreat() } label: { Label("Previous", systemImage: "chevron.left") }
            .tint(.white)
            .disabled(player.pageIndex == 0)
          Text(story.title).font(.headline).foregroundStyle(.white)
          Spacer()
          Toggle("Music", isOn: $musicEnabled)
            .toggleStyle(.switch)
            .foregroundStyle(.white)
            .tint(.gray)
          Button("Show all photos", action: onShowAll).tint(.white)
          Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
            .tint(.white)
        }
        .padding(.horizontal)
        if musicEnabled {
          Text("Music on — no licensed tracks are bundled with this build.")
            .font(.caption)
            .foregroundStyle(.gray)
        }
        Spacer()
        Group {
          if let image {
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .onTapGesture { paused.toggle() }
          } else {
            ProgressView().controlSize(.large)
          }
        }
        .id(player.currentAssetId)
        Spacer()
        if paused {
          Text("Paused — click the photo to resume.")
            .font(.caption)
            .foregroundStyle(.gray)
        }
        Text("\(min(player.pageIndex + 1, player.pageCount)) of \(player.pageCount)")
          .font(.caption)
          .foregroundStyle(.gray)
          .padding(.bottom, 8)
      }
    }
    .accessibilityIdentifier("mac-memory-player")
    .focusable()
    .onKeyPress(.leftArrow) { retreat(); return .handled }
    .onKeyPress(.rightArrow) { advance(); return .handled }
    .task(id: player.currentAssetId) { await loadCurrent() }
    .task {
      // 0.5 s ticks accumulate only while unpaused, so pause freezes the timer
      // instead of skipping pages.
      var elapsed: TimeInterval = 0
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(0.5))
        guard !paused else { continue }
        elapsed += 0.5
        if elapsed >= player.pageDuration {
          elapsed = 0
          player.musicEnabled = musicEnabled
          if !player.advance() { dismiss() }
          await loadCurrent()
        }
      }
    }
  }

  private func advance() {
    player.musicEnabled = musicEnabled
    if !player.advance() { dismiss() } else { Task { await loadCurrent() } }
  }

  private func retreat() {
    // MemoryStoryPlayer has no retreat (PhotosCore is frozen for this slice):
    // rebuild at the previous index via restart + advances (page counts are tiny).
    guard player.pageIndex > 0 else { return }
    let target = player.pageIndex - 1
    player.restart()
    for _ in 0..<target { player.advance() }
    Task { await loadCurrent() }
  }

  private func loadCurrent() async {
    guard let id = player.currentAssetId,
      let asset = try? await store.asset(id: id),
      let loaded = try? await pipeline.load(asset: asset, tier: .preview)
    else { return }
    switch loaded.content {
    case .placeholder(let img): image = img
    case .tier(_, let img, _): image = img
    }
  }
}
