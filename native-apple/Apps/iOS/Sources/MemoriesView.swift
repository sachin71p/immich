import CoreModel
import LocalStore
import SwiftUI

// MARK: - memories page (C6, native-23: full-width cards with title/date + play)

// Upstream memories (`Memory` + `memoryAsset` links) as full-width cards plus an
// "On This Day" card opening the day's grid. Tapping play opens the story player
// (auto-advance, music off by default — no licensed tracks are bundled).
struct MemoriesView: View {
  @EnvironmentObject var session: AppSession
  @State private var stories: [MemoryStory] = []
  @State private var onThisDayIds: [String] = []
  @State private var playingStory: MemoryStory?

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return formatter
  }()

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 16) {
        if stories.isEmpty && onThisDayIds.isEmpty {
          ContentUnavailableView(
            "No Memories Yet", systemImage: "clock",
            description: Text("Saved memories and on-this-day moments appear here."))
        }
        ForEach(stories) { story in
          memoryCard(story)
            .accessibilityIdentifier("memory-\(story.memoryId)")
        }
        if !onThisDayIds.isEmpty {
          NavigationLink {
            IdListDetail(title: "On This Day", ids: onThisDayIds)
              .environmentObject(session)
          } label: {
            onThisDayCard
          }
          .buttonStyle(.plain)
        }
      }
      .padding()
    }
    .navigationTitle("Memories")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("memories")
    .refreshable { await reload() }
    .task { await reload() }
    .fullScreenCover(item: $playingStory) { story in
      MemoryStoryPlayerView(story: story)
    }
  }

  @ViewBuilder
  private func memoryCard(_ story: MemoryStory) -> some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 20).fill(.gray.opacity(0.25))
        .frame(height: 320)
      if let first = story.assetIds.first {
        AssetThumbView(assetId: first)
          .frame(height: 320)
          .clipShape(RoundedRectangle(cornerRadius: 20))
      }
      LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 20))
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 2) {
          Text(story.title).font(.title2).fontWeight(.bold).foregroundStyle(.white)
          Text(Self.dateFormatter.string(from: story.memoryAt).uppercased())
            .font(.caption).foregroundStyle(.white.opacity(0.9))
        }
        Spacer()
        Button { playingStory = story } label: {
          Image(systemName: "play.fill")
            .font(.title3)
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(.gray.opacity(0.5))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("memory-play-\(story.memoryId)")
      }
      .padding()
    }
  }

  @ViewBuilder
  private var onThisDayCard: some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 20).fill(.gray.opacity(0.25))
        .frame(height: 320)
      if let first = onThisDayIds.first {
        AssetThumbView(assetId: first)
          .frame(height: 320)
          .clipShape(RoundedRectangle(cornerRadius: 20))
      }
      LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 20))
      VStack(alignment: .leading, spacing: 2) {
        Text("On This Day").font(.title2).fontWeight(.bold).foregroundStyle(.white)
        Text("\(onThisDayIds.count) Items")
          .font(.caption).foregroundStyle(.white.opacity(0.9))
      }
      .padding()
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
      onThisDayIds = try await store.onThisDayAssets(
        scope: scope,
        month: calendar.component(.month, from: now),
        day: calendar.component(.day, from: now)).map(\.id)
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
