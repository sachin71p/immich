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
  // LP3 (pair 04): Photos-scale neighbour thumbs — the 52pt strip read oversized
  // next to Photos. bottomReserve is untouched (the video scrubber contract).
  static let filmstripHeight: CGFloat = 36
  static let filmstripThumbWidth: CGFloat = 32
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

  private static let weekday: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE"
    return formatter
  }()

  private static let time: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  /// (line1, line2) for the centre pill: place over weekday · time, or
  /// date over weekday · time when no place is known (LP3, pair `04` — Photos
  /// shows `Monday 7:43 PM`, never repeating the date line).
  static func pillLines(date: Date?, city: String?) -> (String, String) {
    guard let date else { return (city ?? "", "") }
    let line2 = detailLine(date: date)
    if let city, !city.isEmpty { return (city, line2) }
    return (day.string(from: date), line2)
  }

  /// LP3 detail line: weekday + time only (`Friday · 7:13 PM`). The date lives
  /// on line 1 already, so repeating it here doubled the pill toward 2× Photos.
  static func detailLine(date: Date) -> String {
    "\(weekday.string(from: date)) · \(time.string(from: date))"
  }
}

/// Shared play trigger for the current Live Photo: a reference so the already-built
/// page host sees each tap (`LIVE` badge → `LivePhotoPageView` playback).
final class LivePlayRequest: ObservableObject {
  @Published var token = 0
}

/// Shared display-only enhance toggle (V2): a reference so the already-built
/// page host sees each tap. Preview only — it never writes to the asset.
final class EnhanceState: ObservableObject {
  @Published var on = false
}

/// Top overlay: glass back chevron, centre place/date pill, enhance, "…" menu.
struct ViewerTopBar: View {
  var line1: String
  var line2: String
  var menu: AnyView
  var onBack: () -> Void
  /// V2 enhance affordance (stills only — the caller hides it for video/live).
  var showEnhance = false
  var enhanceOn = false
  var onEnhance: () -> Void = {}

  var body: some View {
    HStack(alignment: .center) {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .font(.title3.weight(.semibold))
          .foregroundStyle(HeirloomAppearance.chromePrimaryText)
          .frame(width: ViewerLayout.barButtonSize, height: ViewerLayout.barButtonSize)
          // WP-L L1: white-based pills in light, black-based in dark (pair L02).
          .glassEffect(
            .regular.tint(HeirloomAppearance.chromeTintBase.opacity(0.35)), in: .circle)
      }
      .accessibilityLabel("Back")
      .accessibilityIdentifier("viewer-back")
      Spacer()
      VStack(spacing: 1) {
        Text(line1)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(HeirloomAppearance.chromePrimaryText)
          // V1: the place slot (place name when known, date fallback).
          .accessibilityIdentifier("viewer-title-place")
        if !line2.isEmpty {
          Text(line2)
            .font(.caption)
            .foregroundStyle(HeirloomAppearance.chromePrimaryText)
            // LP3: weekday + time slot (Photos pair `04` — no date repeat).
            .accessibilityIdentifier("viewer-title-weekday")
        }
      }
      // LP3 (pair 04): tighter capsule toward the Photos pill size.
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
      .glassEffect(
        .regular.tint(HeirloomAppearance.chromeTintBase.opacity(0.35)), in: .capsule)
      Spacer()
      if showEnhance {
        Button(action: onEnhance) {
          Image(systemName: "wand.and.stars")
            .font(.title3.weight(.semibold))
            .foregroundStyle(HeirloomAppearance.chromePrimaryText)
            .opacity(enhanceOn ? 1 : 0.75)
            .frame(width: ViewerLayout.barButtonSize, height: ViewerLayout.barButtonSize)
            .glassEffect(
              .regular.tint(HeirloomAppearance.chromeTintBase.opacity(0.35)), in: .circle)
        }
        .accessibilityLabel("Enhance")
        .accessibilityValue(enhanceOn ? "On" : "Off")
        .accessibilityIdentifier("viewer-enhance")
      }
      Menu { menu }
      label: {
        Image(systemName: "ellipsis")
          .font(.title3.weight(.semibold))
          .foregroundStyle(HeirloomAppearance.chromePrimaryText)
          .frame(width: ViewerLayout.barButtonSize, height: ViewerLayout.barButtonSize)
          .glassEffect(
            .regular.tint(HeirloomAppearance.chromeTintBase.opacity(0.35)), in: .circle)
      }
      .accessibilityLabel("More")
    }
  }
}

/// Badge row under the top bar: LIVE (tap to play), people (V1), and
/// "From <owner>" for space assets.
struct ViewerBadgeRow: View {
  var isLive: Bool
  var ownerName: String?
  /// V1 people badge: names depicting this asset (empty hides the badge).
  var peopleNames: [String] = []
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
          .foregroundStyle(HeirloomAppearance.chromePrimaryText)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .glassEffect(
            .regular.tint(HeirloomAppearance.chromeTintBase.opacity(0.35)), in: .capsule)
        }
        .accessibilityLabel("Play Live Photo")
        .accessibilityIdentifier("viewer-live-badge")
      }
      if !peopleNames.isEmpty {
        HStack(spacing: 4) {
          Image(systemName: "person.2.circle.fill")
          Text(peopleNames.prefix(2).joined(separator: ", "))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
        }
        .foregroundStyle(HeirloomAppearance.chromePrimaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(
          .regular.tint(HeirloomAppearance.chromeTintBase.opacity(0.35)), in: .capsule)
        .accessibilityLabel("People in this photo: \(peopleNames.joined(separator: ", "))")
        .accessibilityIdentifier("viewer-title-people")
      }
      if let ownerName, !ownerName.isEmpty {
        HStack(spacing: 4) {
          Image(systemName: "person.circle.fill")
          Text("From \(ownerName)")
            .font(.caption.weight(.semibold))
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(HeirloomAppearance.chromePrimaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(
          .regular.tint(HeirloomAppearance.chromeTintBase.opacity(0.35)), in: .capsule)
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
        Rectangle().fill(HeirloomAppearance.chromeSubtleFill)
      }
    }
    .frame(width: ViewerLayout.filmstripThumbWidth, height: ViewerLayout.filmstripHeight)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      if isCurrent {
        RoundedRectangle(cornerRadius: 8)
          .stroke(HeirloomAppearance.chromePrimaryText, lineWidth: 2)
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

/// Bottom toolbar (V3, pair `04`): three glass groups — `[share]` ·
/// `[favorite info adjust]` · `[trash]` — with the same per-button permission
/// gates and labels the single pill had.
struct ViewerGlassBar: View {
  var asset: Asset
  var access: AccessContext
  var isFavorite: Bool
  var onShare: () -> Void
  var onFavorite: () -> Void
  var onInfo: () -> Void
  var onAdjust: () -> Void
  var onTrash: () -> Void

  private var canShare: Bool { Permissions.hasContainerAccess(asset.container, in: access) }
  private var canStar: Bool { Permissions.canFavorite(asset, in: access) }
  private var canAdjust: Bool { Permissions.canEdit(asset, in: access) }
  private var canTrash: Bool { Permissions.canDelete(asset, in: access) }

  var body: some View {
    HStack(spacing: 10) {
      if canShare {
        group {
          barButton("Share", system: "square.and.arrow.up", action: onShare)
        }
        .accessibilityIdentifier("viewer-toolbar-share")
      }
      // Info is unconditional, so the middle group always exists.
      group {
        if canStar {
          barButton(
            "Favorite", system: isFavorite ? "heart.fill" : "heart", action: onFavorite)
        }
        barButton("Info", system: "info.circle", action: onInfo)
        if canAdjust {
          barButton("Adjust", system: "slider.horizontal.3", action: onAdjust)
        }
      }
      .accessibilityIdentifier("viewer-toolbar-actions")
      if canTrash {
        group {
          barButton("Trash", system: "trash", action: onTrash)
        }
        .accessibilityIdentifier("viewer-toolbar-delete")
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: 18) {
      content()
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 12)
    .glassEffect(
      .regular.tint(HeirloomAppearance.chromeTintBase.opacity(0.35)), in: .capsule)
  }

  private func barButton(_ label: String, system: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: system)
        .font(.title3)
        .foregroundStyle(HeirloomAppearance.chromePrimaryText)
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
