import CoreModel
import Foundation
import ImmichAPI
import LocalStore
import MapKit
import SwiftUI

// MARK: - info panel (WP-I, PLAN §2 verbatim — closes V4)
//
// Photos' panel top to bottom (pairs/05, photos/13, photos/14):
// grabber · [Siri row OMITTED: no server-side semantic search exists —
// do not ship dead buttons] · Add a Caption (writes back to the Immich
// asset description via updateAssets) · date card with Adjust + filename ·
// device card with format badge · capture card with dimensions + divided
// EXIF strip · map card with place name + Adjust · Add Keywords (local
// per-asset store paired with WP-P's Manage Keywords vocabulary — the
// generated API filter has no tag operations yet) · provenance row.
// The viewer's bottom toolbar stays visible over the sheet (Viewer.swift
// bottomReserve — untouched, WP-V owns it).
//
// V5: the grabber Button keeps `viewer-info-grabber` (ViewerUITests aims
// it via app.buttons); the wrapper adds `info-sheet-grabber` (InfoPanel
// V5 test) as a .contain container. One panel-level drag gesture + the
// button tap — no duplicated gestures fighting the pager.
struct ViewerInfoPanel: View {
  @EnvironmentObject var session: AppSession
  var asset: Asset
  var exif: AssetExif?
  var containerName: String
  var onClose: () -> Void

  @State private var caption = ""
  @State private var captionStatus: CaptionStatus = .idle
  @State private var dateOverride: Date?
  @State private var coordOverride: Coord?
  @State private var showDateEditor = false
  @State private var showMapEditor = false
  @State private var ownerName: String?
  @State private var assetKeywords: [String] = []
  @State private var keywordDraft = ""

  var body: some View {
    VStack(spacing: 0) {
      // Grabber: wrapper carries info-sheet-grabber (V5), the Button keeps
      // viewer-info-grabber. A plain container can't be aimed reliably —
      // outer layout modifiers join its AX frame; the Button yields its
      // touch once the drag moves, so the panel-level close drag still fires.
      VStack(spacing: 0) {
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
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("info-sheet-grabber")
      ScrollView {
        VStack(spacing: 12) {
          captionField
          mainCard
          mapCard
          keywordsField
          provenanceRow
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
    .sheet(isPresented: $showDateEditor) {
      DateAdjustSheet(
        date: effectiveDate ?? Date(),
        onSave: { picked in
          Task { await saveDate(picked) }
          showDateEditor = false
        },
        onCancel: { showDateEditor = false }
      )
    }
    .sheet(isPresented: $showMapEditor) {
      LocationAdjustSheet(
        latitude: effectiveCoords?.latitude,
        longitude: effectiveCoords?.longitude,
        onSave: { lat, lon in
          Task { await saveLocation(latitude: lat, longitude: lon) }
          showMapEditor = false
        },
        onCancel: { showMapEditor = false }
      )
    }
    .task(id: asset.id) {
      caption = exif?.description ?? ""
      captionStatus = .idle
      dateOverride = nil
      coordOverride = nil
      keywordDraft = ""
      assetKeywords = UserDefaults.standard.stringArray(forKey: assetKeywordsKey) ?? []
      ownerName = nil
      if let store = session.store,
        let user = try? await store.user(id: asset.ownerId), !user.name.isEmpty
      {
        ownerName = user.name
      }
    }
  }

  // MARK: §2.3 — Add a Caption (writes back to the asset description)

  private var captionField: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField("Add a Caption", text: $caption)
        .textInputAutocapitalization(.sentences)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(HeirloomAppearance.chromeSubtleFill, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(HeirloomAppearance.chromePrimaryText)
        .accessibilityIdentifier("info-caption-field")
        .onSubmit { Task { await saveCaption() } }
      if !captionStatusIsIdle {
        Text(captionStatusText)
          .font(.caption)
          .foregroundStyle(
            captionStatusIsError
              ? .red : HeirloomAppearance.chromeTertiaryText)
          .padding(.horizontal, 16)
      }
    }
  }

  // MARK: §2.4–2.6 — date / device / capture card (one visual card, dividers)

  private var mainCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
          Text(InfoDateText.headline(for: effectiveDate))
            .font(.headline)
            .foregroundStyle(HeirloomAppearance.chromePrimaryText)
            .accessibilityIdentifier("viewer-info-date")
          Spacer()
          Button("Adjust") { showDateEditor = true }
            .font(.subheadline)
            .foregroundStyle(.blue)
            .accessibilityIdentifier("info-date-adjust")
        }
        HStack(spacing: 8) {
          Image(systemName: "cloud")
            .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
          Text(asset.originalFileName)
            .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .font(.subheadline)
      }
      .padding(14)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("info-date-card")

      Divider()

      HStack {
        Text(deviceTitle)
          .font(.subheadline)
          .foregroundStyle(HeirloomAppearance.chromePrimaryText)
        Spacer()
        if !formatBadge.isEmpty {
          Text(formatBadge)
            .font(.caption.weight(.semibold))
            .foregroundStyle(HeirloomAppearance.chromePrimaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(HeirloomAppearance.chromeSubtleFill, in: .capsule)
        }
        if isHDR {
          Text("HDR")
            .font(.caption.weight(.semibold))
            .foregroundStyle(HeirloomAppearance.chromePrimaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(HeirloomAppearance.chromeSubtleFill, in: .capsule)
        }
      }
      .padding(14)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("info-device-card")

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        if !captureSubtitle.isEmpty {
          Text(captureSubtitle)
            .font(.subheadline)
            .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
        }
        if !dimensionsLine.isEmpty {
          Text(dimensionsLine)
            .font(.subheadline)
            .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
        }
        if captureSubtitle.isEmpty, dimensionsLine.isEmpty {
          Text("No capture details")
            .font(.caption)
            .foregroundStyle(HeirloomAppearance.chromeTertiaryText)
        }
      }
      .padding(14)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("info-capture-card")

      Divider()

      // The divided EXIF strip closes the card — its own test surface.
      HStack(spacing: 0) {
        ForEach(Array(exifCells.enumerated()), id: \.offset) { index, cell in
          Text(cell)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(cell)
          if index < exifCells.count - 1 {
            Divider()
              .frame(height: 14)
          }
        }
        if exifCells.isEmpty {
          Text("No exposure details")
            .frame(maxWidth: .infinity)
        }
      }
      .font(.caption)
      .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
      .padding(.horizontal, 14)
      .padding(.bottom, 14)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("info-exif-strip")
    }
    .background(HeirloomAppearance.infoCardBackground, in: RoundedRectangle(cornerRadius: 20))
  }

  // MARK: §2.7 — map card

  private var mapCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let coords = effectiveCoords {
        MiniMap(latitude: coords.latitude, longitude: coords.longitude)
          .frame(height: 180)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      } else {
        RoundedRectangle(cornerRadius: 12)
          .fill(HeirloomAppearance.chromeSubtleFill)
          .frame(height: 120)
          .overlay {
            VStack(spacing: 6) {
              Image(systemName: "mappin.slash")
                .foregroundStyle(HeirloomAppearance.chromeTertiaryText)
              Text("No Location")
                .font(.subheadline)
                .foregroundStyle(HeirloomAppearance.chromeTertiaryText)
            }
          }
      }
      HStack {
        Button {
          showMapEditor = true
        } label: {
          HStack(spacing: 4) {
            Text(placeLabel)
              .font(.subheadline)
              .foregroundStyle(.blue)
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(HeirloomAppearance.chromeTertiaryText)
          }
        }
        Spacer()
        Button("Adjust") { showMapEditor = true }
          .font(.subheadline)
          .foregroundStyle(.blue)
          .accessibilityIdentifier("info-map-adjust")
      }
    }
    .padding(14)
    .background(HeirloomAppearance.infoCardBackground, in: RoundedRectangle(cornerRadius: 20))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("info-map-card")
  }

  // MARK: §2.8 — Add Keywords (local per-asset store + shared vocabulary)

  private var keywordsField: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !assetKeywords.isEmpty {
        FlowChips(keywords: assetKeywords) { keyword in
          removeKeyword(keyword)
        }
      }
      TextField("Add Keywords", text: $keywordDraft)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(HeirloomAppearance.chromeSubtleFill, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(HeirloomAppearance.chromePrimaryText)
        .accessibilityIdentifier("info-keywords-field")
        .onSubmit { addKeywordDraft() }
    }
  }

  // MARK: §2.9 — provenance row

  private var provenanceRow: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(HeirloomAppearance.chromeSubtleFill)
        .frame(width: 40, height: 40)
        .overlay {
          Text(initials(of: ownerDisplayName))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HeirloomAppearance.chromePrimaryText)
        }
        .accessibilityHidden(true)
      Text("Added by \(ownerShortName) to \(containerName)")
        .font(.subheadline)
        .foregroundStyle(HeirloomAppearance.chromeSecondaryText)
      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HeirloomAppearance.infoCardBackground, in: RoundedRectangle(cornerRadius: 20))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("info-provenance-row")
  }

  // MARK: derived values

  private var effectiveDate: Date? {
    dateOverride ?? exif?.dateTimeOriginal ?? asset.localDateTime
  }

  private struct Coord: Equatable {
    var latitude: Double
    var longitude: Double
  }

  private var effectiveCoords: Coord? {
    if let coordOverride { return coordOverride }
    if let lat = exif?.latitude, let lon = exif?.longitude {
      return Coord(latitude: lat, longitude: lon)
    }
    return nil
  }

  private var deviceTitle: String {
    let make = (exif?.make ?? "").trimmingCharacters(in: .whitespaces)
    let model = (exif?.model ?? "").trimmingCharacters(in: .whitespaces)
    let line = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
    return line.isEmpty ? "Camera" : line
  }

  private var formatBadge: String {
    (asset.originalFileName as NSString).pathExtension.uppercased()
  }

  private var isHDR: Bool {
    (exif?.profileDescription ?? "").localizedCaseInsensitiveContains("hdr")
  }

  /// Photos aperture text (pair 05: `ƒ1.78` — slashless, up to 2 decimals).
  private static func apertureText(_ f: Double) -> String {
    var raw = String(format: "%.2f", f)
    while raw.hasSuffix("0") { raw.removeLast() }
    if raw.hasSuffix(".") { raw.removeLast() }
    return "ƒ\(raw)"
  }

  private var captureSubtitle: String {
    var detail: [String] = []
    if let lens = exif?.lensModel, !lens.isEmpty { detail.append(lens) }
    if let focal = exif?.focalLength { detail.append(String(format: "%.0f mm", focal)) }
    if let f = exif?.fNumber { detail.append(Self.apertureText(f)) }
    return detail.joined(separator: " — ")
  }

  private var dimensionsLine: String {
    let w = asset.width ?? exif?.exifImageWidth
    let h = asset.height ?? exif?.exifImageHeight
    var parts: [String] = []
    if let w, let h, w > 0, h > 0 {
      let mp = Double(w * h) / 1_000_000
      parts.append(mp >= 10 ? "\(Int(mp.rounded())) MP" : String(format: "%.1f MP", mp))
      parts.append("\(w) × \(h)")
    }
    if let bytes = exif?.fileSizeInByte, bytes > 0 {
      parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
    }
    return parts.joined(separator: " · ")
  }

  private var exifCells: [String] {
    var cells: [String] = []
    if let iso = exif?.iso { cells.append("ISO \(iso)") }
    if let focal = exif?.focalLength { cells.append(String(format: "%.0f mm", focal)) }
    if let f = exif?.fNumber { cells.append(Self.apertureText(f)) }
    if let exp = exif?.exposureTime, !exp.isEmpty {
      cells.append(exp.hasSuffix("s") ? exp : "\(exp) s")
    }
    return cells
  }

  private var placeLabel: String {
    let label = [exif?.city, exif?.state, exif?.country]
      .compactMap { $0?.isEmpty == false ? $0 : nil }
      .joined(separator: ", ")
    return label.isEmpty ? "Unknown Location" : label
  }

  private var ownerDisplayName: String {
    if asset.ownerId == session.userId { return ownerName ?? "You" }
    return ownerName ?? "Unknown"
  }

  private var ownerShortName: String {
    asset.ownerId == session.userId ? "You" : ownerDisplayName
  }

  private func initials(of name: String) -> String {
    let parts = name.split(separator: " ")
    let first = parts.first?.first.map(String.init) ?? ""
    let last = parts.dropFirst().first?.first.map(String.init) ?? ""
    let result = first + last
    return result.isEmpty ? "?" : result
  }

  // MARK: write-back (app-layer updateAssets — no PhotosCore change)

  private enum CaptionStatus {
    case idle, saving, saved, error(String)
  }

  private var captionStatusIsIdle: Bool {
    if case .idle = captionStatus { return true }
    return false
  }

  private var captionStatusIsError: Bool {
    if case .error = captionStatus { return true }
    return false
  }

  private var captionStatusText: String {
    switch captionStatus {
    case .idle: return ""
    case .saving: return "Saving…"
    case .saved: return "Saved"
    case .error(let message): return message
    }
  }

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private func pushUpdate(
    description: String? = nil,
    dateTimeOriginal: String? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil
  ) async throws {
    guard let connection = session.connection else {
      throw PanelWriteError.offline
    }
    let input = Operations.updateAssets.Input(
      body: .json(
        .init(
          dateTimeOriginal: dateTimeOriginal, description: description,
          ids: [asset.id],
          latitude: latitude, longitude: longitude)))
    _ = try await connection.client.updateAssets(input)
  }

  private func saveCaption() async {
    let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
    // Matches the on-appear prefill: nothing changed, nothing to push.
    guard text != (exif?.description ?? "") else {
      captionStatus = .idle
      return
    }
    captionStatus = .saving
    do {
      try await pushUpdate(description: text)
      captionStatus = .saved
    } catch {
      captionStatus = .error(error.isCancellation ? "Cancelled" : "Couldn't save caption — will retry on next sync")
    }
  }

  private func saveDate(_ date: Date) async {
    dateOverride = date
    do {
      try await pushUpdate(dateTimeOriginal: Self.isoFormatter.string(from: date))
    } catch {
      // The picked date stays on screen; the server push retries on next sync.
    }
  }

  private func saveLocation(latitude: Double, longitude: Double) async {
    coordOverride = Coord(latitude: latitude, longitude: longitude)
    do {
      try await pushUpdate(latitude: latitude, longitude: longitude)
    } catch {
      // Coords stay on screen; the server push retries on next sync.
    }
  }

  // MARK: keywords (WP-P vocabulary pairing)

  private var assetKeywordsKey: String { "heirloom.assetKeywords.\(asset.id)" }
  private var vocabularyKey: String { "heirloom.keywords.\(session.userId)" }

  private func addKeywordDraft() {
    let keyword = keywordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty, !assetKeywords.contains(keyword) else {
      keywordDraft = ""
      return
    }
    assetKeywords.append(keyword)
    assetKeywords.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    UserDefaults.standard.set(assetKeywords, forKey: assetKeywordsKey)
    // Pair with Manage Keywords: a panel keyword joins the reusable vocabulary.
    var vocabulary = UserDefaults.standard.stringArray(forKey: vocabularyKey) ?? []
    if !vocabulary.contains(keyword) {
      vocabulary.append(keyword)
      vocabulary.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
      UserDefaults.standard.set(vocabulary, forKey: vocabularyKey)
    }
    keywordDraft = ""
  }

  private func removeKeyword(_ keyword: String) {
    assetKeywords.removeAll { $0 == keyword }
    UserDefaults.standard.set(assetKeywords, forKey: assetKeywordsKey)
  }
}

private enum PanelWriteError: Error {
  case offline
}

/// Date Adjust sheet (§2.4): a real write-back path, not a dead button.
private struct DateAdjustSheet: View {
  var date: Date
  var onSave: (Date) -> Void
  var onCancel: () -> Void
  @State private var picked: Date

  init(date: Date, onSave: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
    self.date = date
    self.onSave = onSave
    self.onCancel = onCancel
    _picked = State(initialValue: date)
  }

  var body: some View {
    NavigationStack {
      DatePicker("Date Taken", selection: $picked)
        .datePickerStyle(.graphical)
        .padding()
        .navigationTitle("Adjust Date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: onCancel)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { onSave(picked) }
          }
        }
    }
    .accessibilityIdentifier("info-date-editor")
    .presentationDetents([.medium])
  }
}

/// Map Adjust sheet (§2.7): a real write-back path, not a dead button.
private struct LocationAdjustSheet: View {
  var onSave: (Double, Double) -> Void
  var onCancel: () -> Void
  @State private var latitudeText: String
  @State private var longitudeText: String
  @State private var error: String?

  init(
    latitude: Double?, longitude: Double?,
    onSave: @escaping (Double, Double) -> Void, onCancel: @escaping () -> Void
  ) {
    self.onSave = onSave
    self.onCancel = onCancel
    _latitudeText = State(initialValue: latitude.map { String($0) } ?? "")
    _longitudeText = State(initialValue: longitude.map { String($0) } ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Latitude", text: $latitudeText)
          .keyboardType(.numbersAndPunctuation)
        TextField("Longitude", text: $longitudeText)
          .keyboardType(.numbersAndPunctuation)
        if let error {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
      .navigationTitle("Adjust Location")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard let lat = Double(latitudeText), (-90...90).contains(lat),
              let lon = Double(longitudeText), (-180...180).contains(lon)
            else {
              error = "Enter latitude −90…90 and longitude −180…180."
              return
            }
            onSave(lat, lon)
          }
        }
      }
    }
    .accessibilityIdentifier("info-map-editor")
    .presentationDetents([.medium])
  }
}

/// Wrapping keyword chips with per-chip remove.
private struct FlowChips: View {
  var keywords: [String]
  var onRemove: (String) -> Void

  var body: some View {
    FlowLayout {
      ForEach(keywords, id: \.self) { keyword in
        HStack(spacing: 6) {
          Text(keyword)
            .font(.subheadline)
            .foregroundStyle(HeirloomAppearance.chromePrimaryText)
          Button {
            onRemove(keyword)
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.caption)
              .foregroundStyle(HeirloomAppearance.chromeTertiaryText)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove keyword \(keyword)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(HeirloomAppearance.chromeSubtleFill, in: .capsule)
      }
    }
  }
}

/// Left-aligned wrapping layout for keyword chips.
private struct FlowLayout<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    // A LazyVGrid with adaptive columns wraps left-aligned without a custom
    // Layout implementation.
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 90), spacing: 8, alignment: .leading)],
      alignment: .leading, spacing: 8
    ) {
      content
    }
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
