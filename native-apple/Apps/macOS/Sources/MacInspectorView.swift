import CoreModel
import LocalStore
import MapKit
import Media
import SwiftUI

/// Photos-style Info panel for the viewer (WP5 item 6, ⌘I): caption, date/time, camera, file,
/// location with a cached map snapshot, and library/owner.
///
/// Caption/title are read-only: the server bulk-update DTO accepts a description, but the app's
/// mutation layer (`AssetMutations`) exposes no description write and WP5 may not add one outside
/// its owned files, so there is no end-to-end path from this view. Reported in `WP5-REPORT.md`.
/// People names are omitted for the same reason: the `face` table exists in the mirror, but WP1
/// reported no per-asset face-name query and new WP5 files may only add read-only LocalStore
/// queries under `LocalStore/` — a face-name lookup needs no new table access, but the person-name
/// join was never part of the WP1 contract, so this stays out until a later WP wires it.
struct MacInspectorView: View {
  var asset: Asset
  var state: MacAppState

  @State private var exif: ExifSummary?
  @State private var ownerName: String?
  @State private var mapImage: NSImage?

  private var format: MediaFormatInfo {
    MediaFormatInfo.classify(
      fileName: asset.originalFileName, profileDescription: exif?.profileDescription)
  }

  var body: some View {
    Form {
      Section("Caption") {
        // Read-only until a description mutation path exists (see header note).
        if let caption = exif?.description, !caption.isEmpty {
          Text(caption)
        } else {
          Text("No description").foregroundStyle(.secondary)
        }
      }
      Section("Date & Time") {
        if let date = asset.localDateTime ?? exif?.dateTimeOriginal {
          LabeledContent("Taken", value: date.formatted(date: .long, time: .shortened))
        } else {
          LabeledContent("Taken", value: "Unknown")
        }
      }
      Section("Camera") {
        if let camera = cameraString {
          LabeledContent("Camera", value: camera)
        }
        if let lens = exif?.lensModel, !lens.isEmpty {
          LabeledContent("Lens", value: lens)
        }
        if let f = exif?.fNumber {
          LabeledContent("Aperture", value: "ƒ/\(formatAperture(f))")
        }
        if let exposure = exposureString {
          LabeledContent("Exposure", value: exposure)
        }
        if let iso = exif?.iso {
          LabeledContent("ISO", value: "ISO \(iso)")
        }
        if let focal = exif?.focalLength {
          LabeledContent("Focal Length", value: "\(formatMillimeters(focal)) mm")
        }
        if cameraString == nil, exif?.lensModel == nil, exif?.fNumber == nil,
          exif?.iso == nil, exif?.focalLength == nil, exposureString == nil
        {
          Text("No camera information").foregroundStyle(.secondary)
        }
      }
      Section("File") {
        if let dimensions = dimensionsString {
          LabeledContent("Dimensions", value: dimensions)
        }
        if let mp = exif?.megapixels {
          LabeledContent("Megapixels", value: String(format: "%.1f MP", mp))
        }
        if let size = fileSizeString {
          LabeledContent("Size", value: size)
        }
        LabeledContent("Name", value: asset.originalFileName)
        HStack {
          Text("Format")
          Spacer()
          ForEach(formatBadges, id: \.self) { badge in
            Text(badge)
              .font(.caption2.weight(.semibold))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.quaternary, in: Capsule())
          }
        }
      }
      if let place = exif?.placeString {
        Section("Location") {
          Text(place)
          if let mapImage {
            Image(nsImage: mapImage)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      Section("Library") {
        LabeledContent("Container", value: containerName)
        LabeledContent("Owner", value: ownerName ?? asset.ownerId)
          .task(id: asset.ownerId) {
            ownerName = try? await state.store.user(id: asset.ownerId)?.name
          }
        LabeledContent("Favorite", value: asset.isFavorite ? "Yes" : "No")
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 280, idealWidth: 300)
    .task(id: asset.id) {
      mapImage = nil
      exif = try? await state.store.exifSummary(assetId: asset.id)
      await loadMapSnapshot()
    }
  }

  // MARK: - formatted rows

  private var cameraString: String? {
    let parts = [exif?.make, exif?.model].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard !parts.isEmpty else { return nil }
    // make + model often repeat ("Apple iPhone 15 Pro"); collapse a duplicated prefix.
    if parts.count == 2, parts[1].hasPrefix(parts[0]) { return parts[1] }
    return parts.joined(separator: " ")
  }

  private var exposureString: String? {
    guard let raw = exif?.exposureTime?.trimmingCharacters(in: .whitespaces), !raw.isEmpty
    else { return nil }
    return raw.hasSuffix("s") ? raw : "\(raw) s"
  }

  private var dimensionsString: String? {
    let w = exif?.width ?? asset.width
    let h = exif?.height ?? asset.height
    guard let w, let h else { return nil }
    return "\(w) × \(h)"
  }

  private var fileSizeString: String? {
    guard let bytes = exif?.fileSizeInByte else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  private func formatAperture(_ f: Double) -> String {
    f.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", f) : String(format: "%.1f", f)
  }

  private func formatMillimeters(_ mm: Double) -> String {
    mm.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", mm) : String(format: "%.1f", mm)
  }

  /// Format badges from `MediaFormatInfo` (WP5 item 6): kind (HEIC/RAW/…) plus HDR.
  private var formatBadges: [String] {
    var badges: [String] = []
    switch format.kind {
    case .jpeg: badges.append("JPEG")
    case .png: badges.append("PNG")
    case .webp: badges.append("WebP")
    case .gif: badges.append("GIF")
    case .heic: badges.append("HEIC")
    case .raw: badges.append("RAW")
    case .video: badges.append("Video")
    case .other: badges.append("Image")
    }
    if format.dynamicRange == .hdr { badges.append("HDR") }
    return badges
  }

  private var containerName: String {
    switch asset.container {
    case .personal: return "Personal Library"
    case .space(let id):
      return state.spaces.first(where: { $0.space.id == id })?.space.name ?? "Shared Library"
    case .library(let id):
      return state.libraries.first(where: { $0.library.id == id })?.library.name ?? "External Library"
    }
  }

  // MARK: - map snapshot

  /// Non-interactive snapshot with a pin, cached per asset (WP5 item 6). `NSCache` is
  /// documented thread-safe; every touch here runs on the main actor (SwiftUI `.task`).
  private static let mapCache = NSCache<NSString, NSImage>()

  @MainActor
  private func loadMapSnapshot() async {
    guard let lat = exif?.latitude, let lon = exif?.longitude else { return }
    let id = asset.id
    let key = id as NSString
    if let cached = Self.mapCache.object(forKey: key) {
      mapImage = cached
      return
    }
    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(
      center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
    options.size = CGSize(width: 560, height: 320)
    options.mapType = .standard
    options.showsBuildings = false
    let snapshotter = MKMapSnapshotter(options: options)
    // The snapshotter's completion runs on the main thread, but `Snapshot` is not Sendable,
    // so it must not cross into the continuation: composite synchronously in the handler and
    // transfer only TIFF `Data` (Sendable) back to the main-actor task.
    let tiff: Data? = await withCheckedContinuation { continuation in
      snapshotter.start { snapshot, _ in
        guard let snapshot else { continuation.resume(returning: nil); return }
        continuation.resume(returning: Self.compositedSnapshot(snapshot, coordinate: coordinate))
      }
    }
    // The page may have changed while the snapshot was in flight; never show a stale pin.
    guard id == asset.id, let tiff, let image = NSImage(data: tiff) else { return }
    Self.mapCache.setObject(image, forKey: key)
    mapImage = image
  }

  /// Snapshot + pin, encoded so the cached image is final. Runs synchronously in the
  /// snapshotter's main-thread completion handler.
  private static func compositedSnapshot(
    _ snapshot: MKMapSnapshotter.Snapshot, coordinate: CLLocationCoordinate2D
  ) -> Data? {
    let image = NSImage(size: snapshot.image.size)
    image.lockFocus()
    snapshot.image.draw(at: .zero, from: NSZeroRect, operation: .copy, fraction: 1)
    let pin = snapshot.point(for: coordinate)
    let pinRect = NSRect(x: pin.x - 6, y: pin.y - 6, width: 12, height: 12)
    NSColor.systemRed.setFill()
    NSBezierPath(ovalIn: pinRect).fill()
    NSColor.white.setStroke()
    NSBezierPath(ovalIn: pinRect.insetBy(dx: 2, dy: 2)).stroke()
    image.unlockFocus()
    return image.tiffRepresentation
  }
}
