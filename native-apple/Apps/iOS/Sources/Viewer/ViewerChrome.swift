import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI

// MARK: - viewer chrome (WP3 step 3, spec device-native-11/12/14)

/// Layout coupling between the SwiftUI chrome and the in-page video scrubber pill
/// (`VideoPage` reserves this space so the pill always sits above the chrome).
enum ViewerLayout {
  static let bottomReserve: CGFloat = 152
  static let filmstripHeight: CGFloat = 52
  static let barButtonSize: CGFloat = 52
}

/// Cached date formatters for the title pill (global rule 6: never allocate per call).
enum ViewerDateText {
  private static let day: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter
  }()

  private static let time: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  /// (line1, line2) for the centre pill: location over date · time, or date over time.
  static func pillLines(date: Date?, city: String?) -> (String, String) {
    guard let date else { return (city ?? "", "") }
    let dayString = day.string(from: date)
    let timeString = time.string(from: date)
    if let city, !city.isEmpty { return (city, "\(dayString)  \(timeString)") }
    return (dayString, timeString)
  }
}

/// Shared play trigger for the current Live Photo: a reference so the already-built
/// page host sees each tap (`LIVE` badge → `LivePhotoPageView` playback).
final class LivePlayRequest: ObservableObject {
  @Published var token = 0
}

/// Top overlay: glass back chevron, centre location/date pill, "…" menu.
struct ViewerTopBar: View {
  var line1: String
  var line2: String
  var menu: AnyView
  var onBack: () -> Void

  var body: some View {
    HStack(alignment: .center) {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: ViewerLayout.barButtonSize, height: ViewerLayout.barButtonSize)
          .glassEffect(.regular.tint(.black.opacity(0.35)), in: .circle)
      }
      .accessibilityLabel("Back")
      .accessibilityIdentifier("viewer-back")
      Spacer()
      VStack(spacing: 1) {
        Text(line1)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
        if !line2.isEmpty {
          Text(line2)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
      .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
      Spacer()
      Menu { menu }
      label: {
        Image(systemName: "ellipsis")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: ViewerLayout.barButtonSize, height: ViewerLayout.barButtonSize)
          .glassEffect(.regular.tint(.black.opacity(0.35)), in: .circle)
      }
      .accessibilityLabel("More")
    }
  }
}

/// Badge row under the top bar: LIVE (tap to play) and "From <owner>" for space assets.
struct ViewerBadgeRow: View {
  var isLive: Bool
  var ownerName: String?
  var onPlayLive: () -> Void

  var body: some View {
    HStack {
      if isLive {
        Button(action: onPlayLive) {
          HStack(spacing: 4) {
            Image(systemName: "livephoto")
            Text("LIVE")
              .font(.caption.weight(.semibold))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
        }
        .accessibilityLabel("Play Live Photo")
      }
      if let ownerName, !ownerName.isEmpty {
        HStack(spacing: 4) {
          Image(systemName: "person.circle.fill")
          Text("From \(ownerName)")
            .font(.caption.weight(.semibold))
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
        .accessibilityLabel("Shared by \(ownerName)")
      }
      Spacer()
    }
  }
}

/// Neighbour filmstrip (tap to jump). Hidden for single-item viewers.
struct ViewerFilmstrip: View {
  var ids: [String]
  var currentIndex: Int
  var session: AppSession
  var onJump: (Int) -> Void

  private var window: [Int] {
    let lo = max(0, currentIndex - 12)
    let hi = min(ids.count - 1, currentIndex + 12)
    guard lo <= hi else { return [] }
    return Array(lo...hi)
  }

  var body: some View {
    if ids.count > 1 {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(window, id: \.self) { index in
              ViewerThumb(
                id: ids[index], session: session, isCurrent: index == currentIndex
              )
              .id(index)
              .onTapGesture { onJump(index) }
            }
          }
          .padding(.horizontal, 2)
        }
        .frame(height: ViewerLayout.filmstripHeight)
        .onChange(of: currentIndex) { _, index in
          withAnimation { proxy.scrollTo(index, anchor: .center) }
        }
        .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
      }
      .accessibilityIdentifier("viewer-filmstrip")
    }
  }
}

private struct ViewerThumb: View {
  var id: String
  var session: AppSession
  var isCurrent: Bool

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Rectangle().fill(.white.opacity(0.15))
      }
    }
    .frame(width: 44, height: ViewerLayout.filmstripHeight)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      if isCurrent {
        RoundedRectangle(cornerRadius: 8)
          .stroke(.white, lineWidth: 2)
      }
    }
    .task(id: id) { await load() }
  }

  private func load() async {
    guard let store = session.store else { return }
    guard let asset = try? await store.asset(id: id) else { return }
    if FixtureArtwork.isFixtureAsset(id) {
      // Fixture assets render generated art off-main, like the grid cells.
      image = await Task.detached(priority: .userInitiated) {
        FixtureArtwork.image(for: asset)
      }.value
      return
    }
    guard let pipeline = session.pipeline else { return }
    if let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail) {
      switch loaded.content {
      case .placeholder(let img): image = img
      case .tier(_, let img, _): image = img
      }
    }
  }
}

/// Bottom glass bar: Share · Favorite · Info · Adjust · Trash, permission-gated.
struct ViewerGlassBar: View {
  var asset: Asset
  var access: AccessContext
  var isFavorite: Bool
  var onShare: () -> Void
  var onFavorite: () -> Void
  var onInfo: () -> Void
  var onAdjust: () -> Void
  var onTrash: () -> Void

  var body: some View {
    HStack(spacing: 18) {
      if Permissions.hasContainerAccess(asset.container, in: access) {
        barButton("Share", system: "square.and.arrow.up", action: onShare)
      }
      if Permissions.canFavorite(asset, in: access) {
        barButton(
          "Favorite", system: isFavorite ? "heart.fill" : "heart", action: onFavorite)
      }
      barButton("Info", system: "info.circle", action: onInfo)
      if Permissions.canEdit(asset, in: access) {
        barButton("Adjust", system: "slider.horizontal.3", action: onAdjust)
      }
      if Permissions.canDelete(asset, in: access) {
        barButton("Trash", system: "trash", action: onTrash)
      }
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 12)
    .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
  }

  private func barButton(_ label: String, system: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: system)
        .font(.title3)
        .foregroundStyle(.white)
        .frame(width: 30, height: 30)
    }
    .accessibilityLabel(label)
  }
}

/// The "…" menu content (native-14 subset): only actions with a real target exist —
/// `AssetMutations` offers no duplicate, slideshow, save-as-video or date/location
/// adjustment, so those are omitted per plan ("if supported"). Add/Move open the
/// existing sheets (flat items rather than submenus).
struct ViewerMoreMenu: View {
  var asset: Asset
  var access: AccessContext
  var isOwnerPersonal: Bool
  var onCopy: () -> Void
  var onAddToAlbum: () -> Void
  var onMoveTo: () -> Void
  var onArchive: () -> Void
  var onHide: () -> Void
  var onLock: () -> Void

  var body: some View {
    if Permissions.canEdit(asset, in: access) {
      Button("Copy", systemImage: "doc.on.doc", action: onCopy)
    }
    if Permissions.canEdit(asset, in: access) {
      Button(asset.visibility == .hidden ? "Unhide" : "Hide", systemImage: "eye.slash") {
        onHide()
      }
    }
    if Permissions.canEdit(asset, in: access) {
      Button("Add to Album", systemImage: "rectangle.stack.badge.plus") { onAddToAlbum() }
      if Permissions.canMove(asset, to: .personal, in: access)
        || !MoveTargets.allowed(for: asset, in: access).isEmpty
      {
        Button("Move to…", systemImage: "folder") { onMoveTo() }
      }
      Button(asset.visibility == .archive ? "Unarchive" : "Archive", systemImage: "archivebox") {
        onArchive()
      }
      if isOwnerPersonal {
        Button(
          asset.visibility == .locked ? "Unlock" : "Lock",
          systemImage: "lock"
        ) {
          onLock()
        }
      }
    }
  }
}
