import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI

/// A9.3 (macOS) sidebar Memories: saved-memory stories with an auto-advance player plus an
/// "On this day" shelf. Music stays OFF by default — no licensed tracks are bundled and no
/// licensing work is in scope; the toggle only records the preference.
struct MacMemoriesView: View {
  @Bindable var state: MacAppState
  @State private var stories: [MemoryStory] = []
  @State private var onThisDay: [TimelineRow] = []
  @State private var playingStory: MemoryStory?

  var body: some View {
    List {
      Section("Stories") {
        if stories.isEmpty {
          Text("No saved memories yet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
              ForEach(stories) { story in
                Button { playingStory = story } label: {
                  VStack {
                    if let first = story.assetIds.first {
                      MacStoryCover(assetId: first, pipeline: state.pipeline, store: state.store)
                        .frame(width: 120, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                      RoundedRectangle(cornerRadius: 8)
                        .fill(.gray.opacity(0.3))
                        .frame(width: 120, height: 150)
                    }
                    Text(story.title)
                      .font(.caption)
                      .lineLimit(1)
                  }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mac-memory-\(story.memoryId)")
              }
            }
          }
        }
      }
      Section("On This Day") {
        if onThisDay.isEmpty {
          Text("Nothing captured on this date in past years.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          ForEach(onThisDay) { row in
            HStack {
              MacStoryCover(assetId: row.id, pipeline: state.pipeline, store: state.store)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
              Text(row.localDateTime?.formatted(date: .long, time: .omitted) ?? "No date")
                .font(.subheadline)
            }
          }
        }
      }
    }
    .accessibilityIdentifier("mac-memories")
    .task { await reload() }
    .sheet(item: $playingStory) { story in
      MacStoryPlayerView(story: story, pipeline: state.pipeline, store: state.store)
        .frame(minWidth: 700, minHeight: 520)
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

private struct MacStoryCover: View {
  var assetId: String
  var pipeline: MediaPipeline
  var store: PhotosLocalStore
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
        let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail)
      else { return }
      switch loaded.content {
      case .placeholder(let img): image = img
      case .tier(_, let img, _): image = img
      }
    }
  }
}

/// Full-screen story player with auto-advance and a music toggle (default off).
struct MacStoryPlayerView: View {
  var story: MemoryStory
  var pipeline: MediaPipeline
  var store: PhotosLocalStore
  @Environment(\.dismiss) private var dismiss
  @State private var player: MemoryStoryPlayer
  @State private var musicEnabled = false
  @State private var image: NSImage?

  init(story: MemoryStory, pipeline: MediaPipeline, store: PhotosLocalStore) {
    self.story = story
    self.pipeline = pipeline
    self.store = store
    _player = State(initialValue: MemoryStoryPlayer(story: story))
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack {
        HStack {
          Text(story.title).font(.headline).foregroundStyle(.white)
          Spacer()
          Toggle("Music", isOn: $musicEnabled)
            .toggleStyle(.switch)
            .foregroundStyle(.white)
            .tint(.gray)
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
          } else {
            ProgressView().controlSize(.large)
          }
        }
        .id(player.currentAssetId)
        Spacer()
      }
    }
    .accessibilityIdentifier("mac-memory-player")
    .task(id: player.currentAssetId) { await loadCurrent() }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(player.pageDuration))
        withAnimation {
          player.musicEnabled = musicEnabled
          if !player.advance() { dismiss() }
        }
        await loadCurrent()
      }
    }
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
