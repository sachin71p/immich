import CoreModel
import LocalStore
import SwiftUI

// MARK: - memories (A9.3)

///
/// Upstream memories (`Memory` + `memoryAsset` links) as a story player with auto-advance,
/// plus an "On this day" shelf computed client-side from capture dates. Music stays OFF by
/// default — no licensed tracks are bundled and no licensing work is in scope; the toggle
/// only records the preference.
struct MemoriesView: View {
  @EnvironmentObject var session: AppSession
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
                      RowThumbnail(rowId: first)
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                      RoundedRectangle(cornerRadius: 10)
                        .fill(.gray.opacity(0.3))
                        .frame(width: 120, height: 160)
                    }
                    Text(story.title)
                      .font(.caption)
                      .lineLimit(1)
                  }
                }
                .accessibilityIdentifier("memory-\(story.memoryId)")
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
              RowThumbnail(rowId: row.id)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
              VStack(alignment: .leading) {
                Text(row.localDateTime?.formatted(date: .long, time: .omitted) ?? "No date")
                  .font(.subheadline)
                if let date = row.localDateTime {
                  Text("\(Calendar.current.component(.year, from: date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Memories")
    .accessibilityIdentifier("memories")
    .refreshable { await reload() }
    .task { await reload() }
    .fullScreenCover(item: $playingStory) { story in
      MemoryStoryPlayerView(story: story)
    }
  }

  private func reload() async {
    guard let store = session.store, !session.userId.isEmpty else { return }
    do {
      let memories = try await store.savedMemories(forOwner: session.userId)
      var built: [MemoryStory] = []
      for memory in memories {
        let ids = try await store.assetIds(forMemory: memory.id)
        guard !ids.isEmpty else { continue }
        built.append(MemoryStory(
          memoryId: memory.id, title: MemoryStory.title(for: memory),
          memoryAt: memory.memoryAt, assetIds: ids))
      }
      stories = built
      let scope = try await session.timelineScope()
      let now = Date()
      let calendar = Calendar.current
      onThisDay = try await store.onThisDayAssets(
        scope: scope,
        month: calendar.component(.month, from: now),
        day: calendar.component(.day, from: now))
    } catch {
      // L2: cancellation is never a user-facing error.
      if !error.isCancellation { session.lastError = error.localizedDescription }
    }
  }
}

/// Full-screen story player: auto-advances every `pageDuration` seconds, shows segmented
/// progress, and offers previous/next tap zones plus a music toggle (default off).
struct MemoryStoryPlayerView: View {
  @EnvironmentObject var session: AppSession
  var story: MemoryStory
  @Environment(\.dismiss) private var dismiss
  @State private var player: MemoryStoryPlayer
  @AppStorage("heirloom.memoryMusic") private var musicEnabled = false

  init(story: MemoryStory) {
    self.story = story
    _player = State(initialValue: MemoryStoryPlayer(story: story))
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack {
        StoryProgressBar(progress: player.progress, pageCount: player.pageCount)
          .padding(.horizontal)
          .padding(.top, 8)
        HStack {
          Text(story.title)
            .font(.headline)
            .foregroundStyle(.white)
          Spacer()
          Button {
            musicEnabled.toggle()
            player.musicEnabled = musicEnabled
          } label: {
            Label(
              "Music",
              systemImage: musicEnabled ? "music.note" : "music.note.list")
          }
          .tint(musicEnabled ? .white : .gray)
          Button { dismiss() } label: {
            Label("Close", systemImage: "xmark")
          }
          .tint(.white)
        }
        .padding(.horizontal)
        if musicEnabled {
          Text("Music on — no licensed tracks are bundled with this build.")
            .font(.caption2)
            .foregroundStyle(.gray)
        }
        Spacer()
        if let current = player.currentAssetId {
          StoryPageImage(assetId: current)
            .id(current)
            .transition(.opacity)
        } else {
          Text("This memory has no photos.")
            .foregroundStyle(.white)
        }
        Spacer()
      }
    }
    .accessibilityIdentifier("memory-player")
    .onAppear { player.musicEnabled = musicEnabled }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(player.pageDuration))
        withAnimation {
          if !player.advance() { dismiss() }
        }
      }
    }
    .gesture(
      DragGesture(minimumDistance: 20)
        .onEnded { value in
          if value.translation.width < -40 {
            withAnimation { if !player.advance() { dismiss() } }
          } else if value.translation.width > 40, player.pageIndex > 0 {
            withAnimation { player.restart() }
          }
        })
  }
}

private struct StoryProgressBar: View {
  var progress: Double
  var pageCount: Int

  var body: some View {
    GeometryReader { geometry in
      Capsule()
        .fill(.white.opacity(0.3))
        .overlay(alignment: .leading) {
          Capsule()
            .fill(.white)
            .frame(width: geometry.size.width * progress)
        }
    }
    .frame(height: 3)
    .accessibilityIdentifier("memory-progress")
  }
}

private struct StoryPageImage: View {
  @EnvironmentObject var session: AppSession
  var assetId: String
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        ProgressView().tint(.white)
      }
    }
    .task(id: assetId) {
      guard let store = session.store, let pipeline = session.pipeline,
        let asset = try? await store.asset(id: assetId),
        let loaded = try? await pipeline.load(asset: asset, tier: .preview)
      else { return }
      switch loaded.content {
      case .placeholder(let img): image = img
      case .tier(_, let img, _): image = img
      }
    }
  }
}
