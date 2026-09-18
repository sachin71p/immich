import CoreModel
import LocalStore
import MapKit
import SwiftUI

// MARK: - inline info panel (WP3 step 4, spec device-native-13)

/// Slides up over the photo (Info button or swipe up); swipe down on the grabber or
/// Info again closes it. Cards: caption (display only — no description mutation
/// exists), date · file, camera, map + place + library, people chips, albums.
/// People/albums load here on open (indexed queries); swiping never pays for them.
struct ViewerInfoPanel: View {
  @EnvironmentObject var session: AppSession
  var asset: Asset
  var exif: AssetExif?
  var containerName: String
  var onClose: () -> Void

  @State private var people: [Person] = []
  @State private var albumNames: [String] = []

  var body: some View {
    VStack(spacing: 0) {
      // Full-width grabber button: tap closes; drags pass through to the panel's
      // close drag (a Button yields its touch once it moves). A plain container
      // can't be aimed reliably — outer layout modifiers join its AX frame.
      Button(action: onClose) {
        Capsule()
          // WP-L L3: adaptive faint text (white 0.5 dark / tertiary light).
          .fill(HeirloomAppearance.chromeTertiaryText)
          .frame(width: 40, height: 5)
          .frame(maxWidth: .infinity)
          .padding(.top, 10)
          .padding(.bottom, 12)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close info panel")
      .accessibilityIdentifier("viewer-info-grabber")
      ScrollView {
        VStack(spacing: 12) {
          if let caption = exif?.description, !caption.isEmpty {
            infoCard {
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.bubble")
                  .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
                Text(caption)
                  .foregroundStyle(HeirloomAppearance.chromePrimaryText)
              }
            }
          }
          infoCard {
            VStack(alignment: .leading, spacing: 8) {
              Text(InfoDateText.headline(for: asset.localDateTime))
                .font(.headline)
                .foregroundStyle(HeirloomAppearance.chromePrimaryText)
                .accessibilityIdentifier("viewer-info-date")
              HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                  .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
                Text(asset.originalFileName)
                  .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
              }
              .font(.subheadline)
            }
          }
          if let camera = InfoCamera(exif: exif, asset: asset) {
            infoCard {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Text(camera.title)
                    .font(.headline)
                    .foregroundStyle(HeirloomAppearance.chromePrimaryText)
                  Spacer()
                  if !camera.format.isEmpty {
                    Text(camera.format)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(HeirloomAppearance.chromePrimaryText)
                      .padding(.horizontal, 10)
                      .padding(.vertical, 4)
                      .background(HeirloomAppearance.chromeSubtleFill, in: .capsule)
                  }
                }
                .accessibilityIdentifier("viewer-info-camera")
                if !camera.subtitle.isEmpty {
                  Text(camera.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
                }
                if !camera.dimensions.isEmpty {
                  Text(camera.dimensions)
                    .font(.subheadline)
                    .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
                }
                if !camera.exposure.isEmpty {
                  HStack {
                    ForEach(camera.exposure, id: \.self) { cell in
                      Text(cell)
                        .frame(maxWidth: .infinity)
                    }
                  }
                  .font(.caption)
                  .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
                }
              }
            }
          }
          if let lat = exif?.latitude, let lon = exif?.longitude {
            infoCard {
              VStack(alignment: .leading, spacing: 8) {
                MiniMap(latitude: lat, longitude: lon)
                  .frame(height: 200)
                  .clipShape(RoundedRectangle(cornerRadius: 12))
                if !placeLabel.isEmpty {
                  HStack {
                    Text(placeLabel)
                      .font(.subheadline)
                      .foregroundStyle(HeirloomAppearance.chromePrimaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(HeirloomAppearance.chromeTertiaryText)
                  }
                }
                Text("Library: \(containerName)")
                  .font(.subheadline)
                  .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
              }
            }
            .accessibilityIdentifier("viewer-info-map")
          }
          if !people.isEmpty {
            infoCard {
              VStack(alignment: .leading, spacing: 8) {
                Text("People")
                  .font(.headline)
                  .foregroundStyle(HeirloomAppearance.chromePrimaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 12) {
                    ForEach(people) { person in
                      VStack(spacing: 4) {
                        Circle()
                          .fill(HeirloomAppearance.chromeSubtleFill)
                          .frame(width: 44, height: 44)
                          .overlay {
                            Text(initials(of: person.name))
                              .font(.headline)
                              .foregroundStyle(HeirloomAppearance.chromePrimaryText)
                          }
                        Text(person.name)
                          .font(.caption)
                          .foregroundStyle(HeirloomAppearance.chromePrimaryText)
                      }
                    }
                  }
                }
              }
            }
          }
          if !albumNames.isEmpty {
            infoCard {
              VStack(alignment: .leading, spacing: 8) {
                Text("Albums")
                  .font(.headline)
                  .foregroundStyle(HeirloomAppearance.chromePrimaryText)
                ForEach(albumNames, id: \.self) { name in
                  HStack {
                    Image(systemName: "rectangle.stack")
                      .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
                    Text(name)
                      .foregroundStyle(HeirloomAppearance.chromePrimaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(HeirloomAppearance.chromeTertiaryText)
                  }
                  .font(.subheadline)
                }
              }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
      }
      // WP-L L3: appearance test surface — the sheet's own scroll content.
      // Contain (like the panel root) keeps the card ids addressable.
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("info-sheet-surface")
    }
    // WP-L L3: grouped-background card in light, dark card in dark.
    .background(HeirloomAppearance.infoCardBackground, in: RoundedRectangle(cornerRadius: 20))
    // Explicit containment: without it the panel's identifier collapses the whole
    // subtree (grabber label included) into a single element and the children
    // stop being addressable.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("viewer-info-panel")
    .gesture(
      DragGesture(minimumDistance: 30)
        .onEnded { value in
          if value.translation.height > 100 && abs(value.translation.width) < 80 {
            onClose()
          }
        })
    .task(id: asset.id) {
      await load()
    }
  }

  private func infoCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      content()
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HeirloomAppearance.infoCardBackground, in: RoundedRectangle(cornerRadius: 20))
  }

  private var placeLabel: String {
    [exif?.city, exif?.state, exif?.country]
      .compactMap { $0?.isEmpty == false ? $0 : nil }
      .joined(separator: ", ")
  }

  private func initials(of name: String) -> String {
    let parts = name.split(separator: " ")
    let first = parts.first?.first.map(String.init) ?? ""
    let last = parts.dropFirst().first?.first.map(String.init) ?? ""
    let result = first + last
    return result.isEmpty ? "?" : result
  }

  /// People depicting this asset (indexed per-person membership checks) and the
  /// albums containing it (one indexed join). Runs only while the panel is open.
  private func load() async {
    guard let store = session.store else { return }
    let mine = (try? await store.peopleForOwner(session.userId)) ?? []
    let others =
      asset.ownerId == session.userId
      ? [] : ((try? await store.peopleForOwner(asset.ownerId)) ?? [])
    var matched: [Person] = []
    for person in mine + others where !matched.contains(person) {
      let ids = try? await store.assetIds(forPerson: person.id, limit: 500)
      if ids?.contains(asset.id) == true, !person.name.isEmpty {
        matched.append(person)
      }
    }
    people = matched
    albumNames = (try? await store.albumsContaining(assetId: asset.id).map(\.name)) ?? []
  }
}

/// Weekday · date · time headline (global rule 6: static formatters).
enum InfoDateText {
  private static let weekday: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE"
    return formatter
  }()

  private static let day: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  private static let time: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  static func headline(for date: Date?) -> String {
    guard let date else { return "" }
    return "\(weekday.string(from: date)) · \(day.string(from: date)) · \(time.string(from: date))"
  }
}

/// Camera card model (nil when the exif has no camera block at all).
struct InfoCamera {
  var title: String
  var format: String
  var subtitle: String
  var dimensions: String
  var exposure: [String]

  init?(exif: AssetExif?, asset: Asset) {
    guard let exif,
      exif.make != nil || exif.model != nil || exif.lensModel != nil
        || exif.fNumber != nil || exif.focalLength != nil || exif.iso != nil
    else { return nil }
    let make = (exif.make ?? "").trimmingCharacters(in: .whitespaces)
    let model = (exif.model ?? "").trimmingCharacters(in: .whitespaces)
    let modelLine = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
    title = modelLine.isEmpty ? "Camera" : modelLine
    format = (asset.originalFileName as NSString).pathExtension.uppercased()
    var detail: [String] = []
    if let lens = exif.lensModel, !lens.isEmpty { detail.append(lens) }
    if let focal = exif.focalLength { detail.append(String(format: "%.0f mm", focal)) }
    if let f = exif.fNumber { detail.append(String(format: "ƒ/%.1f", f)) }
    subtitle = detail.joined(separator: " — ")
    let w = asset.width ?? exif.exifImageWidth
    let h = asset.height ?? exif.exifImageHeight
    if let w, let h, w > 0, h > 0 {
      let mp = Double(w * h) / 1_000_000
      let mpText = mp >= 10 ? "\(Int(mp.rounded())) MP" : String(format: "%.1f MP", mp)
      dimensions = "\(mpText) · \(w) × \(h)"
    } else {
      dimensions = ""
    }
    var cells: [String] = []
    if let iso = exif.iso { cells.append("ISO \(iso)") }
    if let focal = exif.focalLength { cells.append(String(format: "%.0f mm", focal)) }
    if let f = exif.fNumber { cells.append(String(format: "ƒ/%.1f", f)) }
    if let exp = exif.exposureTime, !exp.isEmpty { cells.append(exp) }
    exposure = cells
  }
}

struct MiniMap: View {
  var latitude: Double
  var longitude: Double

  var body: some View {
    Map(initialPosition: .region(region)) {
      Marker(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {}
    }
    .mapStyle(.standard)
  }

  private var region: MKCoordinateRegion {
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
  }
}
