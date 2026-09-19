import CoreModel
import LocalStore
import MapKit
import Media
import SwiftUI

// MARK: - section header ("Title ›" + collapse chevron, native-15…18)

struct CollectionSectionHeader<Destination: View>: View {
  var title: String
  var section: CollectionsSection
  var collapsed: Bool
  var onToggleCollapse: () -> Void
  var destination: (() -> Destination)?

  var body: some View {
    HStack {
      if let destination {
        NavigationLink(destination: destination()) {
          HStack(spacing: 2) {
            Text(title).font(.title3).fontWeight(.semibold)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
      } else {
        Text(title).font(.title3).fontWeight(.semibold)
      }
      Spacer()
      Button {
        onToggleCollapse()
      } label: {
        Image(systemName: "chevron.down")
          .font(.caption)
          .foregroundStyle(.blue)
          .rotationEffect(.degrees(collapsed ? -90 : 0))
          .frame(width: 28, height: 28)
          .background(.gray.opacity(0.2))
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("collections-collapse-\(section.rawValue)")
    }
    .padding(.horizontal)
  }
}

// Section header without a destination page (Recent Days, Media Types, Utilities).
struct CollectionPlainHeader: View {
  var title: String
  var section: CollectionsSection
  var collapsed: Bool
  var onToggleCollapse: () -> Void

  var body: some View {
    HStack {
      Text(title).font(.title3).fontWeight(.semibold)
      Spacer()
      Button {
        onToggleCollapse()
      } label: {
        Image(systemName: "chevron.down")
          .font(.caption)
          .foregroundStyle(.blue)
          .rotationEffect(.degrees(collapsed ? -90 : 0))
          .frame(width: 28, height: 28)
          .background(.gray.opacity(0.2))
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("collections-collapse-\(section.rawValue)")
    }
    .padding(.horizontal)
  }
}

// MARK: - thumbnails (pipeline-backed; fixture art flows through the same path)

// One asset thumbnail. Replaces `RowThumbnail` (no per-row store fetch: the caller
// passes the id; the pipeline serves fixture art and the thumbhash placeholder tier).
struct AssetThumbView: View {
  @EnvironmentObject var session: AppSession
  var assetId: String
  var contentMode: ContentMode = .fill

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
      } else {
        Rectangle().fill(.gray.opacity(0.25))
      }
    }
    .task(id: assetId) {
      guard let store = session.store, let pipeline = session.pipeline,
        let asset = try? await store.asset(id: assetId),
        let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail)
      else { return }
      switch loaded.content {
      case .placeholder(let img): image = img
      case .tier(_, let img, _): image = img
      }
    }
  }
}

// Face card image: the Immich person thumbnail endpoint through the existing
// `personThumbnail` media path (cached `person:` tier, no ad-hoc fetches), falling
// back to the person's cover asset (fixture mode has no person thumbnails).
struct PersonFaceView: View {
  @EnvironmentObject var session: AppSession
  var personId: String
  var faceAssetId: String?

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
      } else {
        Rectangle().fill(.gray.opacity(0.25))
          .overlay { Image(systemName: "person.fill").foregroundStyle(.secondary) }
      }
    }
    .task(id: personId) {
      if let pipeline = session.pipeline {
        do {
          for try await loaded in await pipeline.personThumbnail(id: personId) {
            switch loaded.content {
            case .placeholder(let img): image = img
            case .tier(_, let img, _): image = img
            }
            break
          }
          if image != nil { return }
        } catch {}
      }
      guard let store = session.store, let pipeline = session.pipeline,
        let faceAssetId, let asset = try? await store.asset(id: faceAssetId),
        let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail)
      else { return }
      switch loaded.content {
      case .placeholder(let img): image = img
      case .tier(_, let img, _): image = img
      }
    }
  }
}

// MARK: - tiles (rounded, title overlay bottom-left, native-16…19)

// Square photo tile with a bottom-left title overlay.
struct PhotoTitleTile: View {
  var assetId: String?
  var title: String
  var subtitle: String?

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.25))
      if let assetId {
        AssetThumbView(assetId: assetId)
          .clipShape(RoundedRectangle(cornerRadius: 16))
      }
      VStack(alignment: .leading, spacing: 0) {
        Text(title).font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
          .lineLimit(2)
        if let subtitle {
          Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.85))
        }
      }
      .padding(10)
      .shadow(color: .black.opacity(0.6), radius: 4)
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

// Face card with a name overlay (native-16 People rows, native-21 grid).
struct FaceTile: View {
  var person: PersonTileData

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.25))
      PersonFaceView(personId: person.id, faceAssetId: person.faceAssetId)
        .clipShape(RoundedRectangle(cornerRadius: 16))
      Text(person.summary.name.isEmpty ? "Unnamed" : person.summary.name)
        .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
        .lineLimit(1).padding(10)
        .shadow(color: .black.opacity(0.6), radius: 4)
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityIdentifier("person-\(person.summary.name.isEmpty ? person.id : person.summary.name)")
  }
}

// Two-column pill with an SF Symbol (Media Types, Utilities — native-17/18).
struct CollectionPill: View {
  var title: String
  var systemImage: String
  var locked: Bool = false
  var count: Int?

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 22)
      Text(title).font(.subheadline).lineLimit(1)
      Spacer()
      if let count {
        Text("\(count)").font(.caption).foregroundStyle(.secondary)
      }
      if locked {
        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .background(.gray.opacity(0.22))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityIdentifier("utility-\(title)")
  }
}

// MARK: - hero cover (native-20: key photo, title, item count, play where one exists)

struct HeroCoverHeader: View {
  var coverId: String?
  var title: String
  var subtitle: String
  var onPlay: (() -> Void)?

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Rectangle().fill(.gray.opacity(0.25)).frame(height: 240)
      if let coverId {
        AssetThumbView(assetId: coverId)
          .frame(height: 240)
          .clipped()
      }
      LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        .frame(height: 240)
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.title2).fontWeight(.bold).foregroundStyle(.white)
          Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.9))
        }
        Spacer()
        if let onPlay {
          Button(action: onPlay) {
            Image(systemName: "play.fill")
              .font(.title3)
              .foregroundStyle(.white)
              .frame(width: 48, height: 48)
              .background(.gray.opacity(0.5))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("hero-play")
        }
      }
      .padding()
    }
  }
}


// MARK: - map snapshot tile (LP7)

// Replaces the gray `map.fill` placeholder behind both Places entry points
// (the pinned-grid Map tile and the wide Places section tile) with a native
// map snapshot centred on the library's geotagged assets. The snapshot is
// rendered once per session identity off the main thread via
// `MKMapSnapshotter`; while it loads — or when the library has no located
// assets or the snapshot fails (offline simulator) — the previous gray tile
// renders as the explicit fallback so the tile never paints empty.
struct MapSnapshotTile: View {
  @EnvironmentObject var session: AppSession

  /// Caption overlay: the located-places count when known, else "Map".
  var subtitle: String?
  /// Label shown under the caption on the wide tile; nil on the square tile.
  var footnote: String?

  @State private var snapshot: UIImage?
  @State private var didAttemptLoad = false

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if let snapshot {
        Image(uiImage: snapshot)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .accessibilityIdentifier("places-tile-snapshot")
      } else {
        RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.25))
        Image(systemName: "map.fill")
          .font(.largeTitle).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityIdentifier("places-tile-map-fallback")
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(subtitle ?? "Map")
          .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
          .shadow(color: .black.opacity(0.6), radius: 4)
        if let footnote {
          Text(footnote)
            .font(.caption).foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.6), radius: 4)
        }
      }
      .padding(10)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .task { await load() }
  }

  private func load() async {
    guard !didAttemptLoad, let store = session.store else { return }
    didAttemptLoad = true
    let key = session.userId
    if let cached = SnapshotCache.shared.get(key) {
      snapshot = cached
      return
    }
    guard let scope = try? await session.timelineScope() else { return }
    // Bounded (200) pin sample: the tile only needs a region, never the
    // full located set, so this stays cheap regardless of library size.
    let pins = (try? await store.locatedAssets(scope: scope, limit: 200)) ?? []
    guard !pins.isEmpty else { return }
    let lats = pins.map(\.latitude)
    let lons = pins.map(\.longitude)
    let center = CLLocationCoordinate2D(
      latitude: (lats.min()! + lats.max()!) / 2,
      longitude: (lons.min()! + lons.max()!) / 2)
    let latSpan = max((lats.max()! - lats.min()!) * 1.4, 0.05)
    let lonSpan = max((lons.max()! - lons.min()!) * 1.4, 0.05)
    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(
      center: center,
      span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
    options.size = CGSize(width: 512, height: 512)
    options.scale = 2
    options.showsPointsOfInterest = false
    guard let image = try? await MKMapSnapshotter(options: options).start().image
    else { return }
    SnapshotCache.shared.set(image, key: key)
    snapshot = image
  }
}

/// One snapshot per session identity, shared by the square and wide tiles.
/// Lock-guarded (same pattern as `ArtCache`): `NSCache` is not `Sendable`
/// under Swift 6 strict concurrency.
private final class SnapshotCache: @unchecked Sendable {
  static let shared = SnapshotCache()
  private let lock = NSLock()
  private var images: [String: UIImage] = [:]

  func get(_ key: String) -> UIImage? {
    lock.withLock { images[key] }
  }

  func set(_ image: UIImage, key: String) {
    lock.withLock { images[key] = image }
  }
}
