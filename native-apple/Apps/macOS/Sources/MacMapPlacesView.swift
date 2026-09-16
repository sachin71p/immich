import CoreModel
import LocalStore
import MapKit
import Media
import Rules
import SwiftUI

/// WP6 slice B (U18, Map): all located points, screen-space clustered.
///
/// - Points come from `store.locatedAssetPoints(scope:)` (WP1, no limit) off-main.
/// - On region change (debounced 150 ms) `binMapPoints` projects to screen space
///   and grid-bins (cell ≈ 60 pt) in a detached task — never on the main actor —
///   producing ≤ 1,500 annotations; the map diffs add/remove only.
/// - Annotation = rounded-square representative thumbnail (memory cache, then async)
///   + count badge. Cluster click zooms in (count > 1, below max zoom), otherwise
///   the side panel shows those photos in `MacCollectionGridView` (snapshot from
///   `timelineRows(ids:)`). No result cap: the header shows "N photos in this area"
///   from the binned visible counts.
struct MacMapPlacesView: View {
  @Bindable var state: MacAppState
  var openViewer: (String) -> Void

  @State private var points: [LocatedPoint] = []
  @State private var bins: [MapBin] = []
  @State private var visibleCount = 0
  @State private var zoom: Double = 3
  @State private var selectedBinId: String?
  @State private var snapshot = TimelineGridSnapshot.empty
  @State private var selectedIds = Set<String>()
  @State private var itemSize: CGFloat = 120
  @State private var generation = 0
  @State private var rebinTask: Task<Void, Never>?

  private var selectedBin: MapBin? { bins.first { $0.id == selectedBinId } }

  var body: some View {
    HSplitView {
      MacBinnedMapView(
        bins: bins,
        pipeline: state.pipeline,
        onSelect: select(bin:),
        onViewport: scheduleRebin(viewport:zoom:)
      )
      .frame(minWidth: 300)
      .accessibilityIdentifier("mac-places-map")
      VStack(alignment: .leading, spacing: 0) {
        Text(headerText)
          .font(.headline)
          .padding(.horizontal)
          .padding(.vertical, 8)
          .accessibilityIdentifier("mac-places-count")
        if selectedBin != nil {
          MacCollectionGridView(
            snapshot: snapshot,
            lastPatch: (snapshot.revision, []),
            pipeline: state.pipeline,
            store: state.store,
            exporter: nil,
            itemSize: itemSize,
            selectedIds: $selectedIds,
            onSelectionChange: { _ in },
            onOpen: { openViewer($0) },
            onPreview: { _ in },
            onToggleFavorite: { _ in },
            onMagnify: { itemSize = MacTimelineLayout.clampedItemSide(itemSize + $0) }
          )
        } else {
          ContentUnavailableView(
            "No Selection",
            systemImage: "map",
            description: Text("Select a cluster to browse its photos."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(minWidth: 220, idealWidth: 320)
    }
    .task(id: state.timelineVersion) { await loadPoints() }
  }

  private var headerText: String {
    let area = "\(visibleCount) photo\(visibleCount == 1 ? "" : "s") in this area"
    guard let bin = selectedBin else { return area }
    return "\(bin.count) selected · \(area)"
  }

  private func loadPoints() async {
    guard let userId = state.userId else { return }
    do {
      let ctx = try await state.store.timelineContext(for: userId)
      let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
      // GRDB reads on its own thread; the await never blocks the main actor.
      points = try await state.store.locatedAssetPoints(scope: scope)
      scheduleRebin(viewport: lastViewport, zoom: zoom)
    } catch {}
  }

  /// Latest viewport seen (world fallback until the map reports its region).
  @State private var lastViewport = MapViewport.world

  /// Debounced 150 ms rebin: superseded pans cancel, binning runs detached.
  private func scheduleRebin(viewport: MapViewport, zoom: Double) {
    lastViewport = viewport
    self.zoom = zoom
    rebinTask?.cancel()
    let current = points
    rebinTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      let result = await Task.detached(priority: .userInitiated) {
        binMapPoints(current, viewport: viewport)
      }.value
      guard !Task.isCancelled else { return }
      bins = result.bins
      visibleCount = result.visibleCount
      if let selected = selectedBinId, !bins.contains(where: { $0.id == selected }) {
        selectedBinId = nil
      }
    }
  }

  private func select(bin: MapBin) {
    // Drill in while the cluster hides detail; at max zoom (or a single photo)
    // the side panel shows the cluster's photos instead.
    if bin.count > 1 && zoom < MapBin.maxDrillZoom {
      MacBinnedMapView.zoomIn(on: bin)
      return
    }
    selectedBinId = bin.id
    Task { await show(bin: bin) }
  }

  private func show(bin: MapBin) async {
    do {
      let rows = try await state.store.timelineRows(ids: Array(bin.memberIds))
      generation += 1
      snapshot = MacGridSnapshotBuilder.monthSnapshot(rows: rows, generation: generation)
      selectedIds = []
    } catch {}
  }
}

// MARK: - binning (pure, Sendable — runs in a detached task)

/// Viewport captured on-main, consumed off-main by `binMapPoints`.
struct MapViewport: Sendable, Hashable {
  var centerLatitude: Double
  var centerLongitude: Double
  var spanLatitude: Double
  var spanLongitude: Double
  var width: Double
  var height: Double

  static var world: MapViewport {
    MapViewport(
      centerLatitude: 20, centerLongitude: 0, spanLatitude: 120, spanLongitude: 360,
      width: 800, height: 600)
  }
}

/// One screen-space grid cell: representative thumbnail id + full count.
/// `memberIds` is capped at the `timelineRows(ids:)` limit — the side panel shows
/// up to that many; `count` stays exact for the badge and header.
struct MapBin: Sendable, Hashable, Identifiable {
  var id: String
  var count: Int
  var representativeId: String
  var latitude: Double
  var longitude: Double
  var memberIds: [String]

  static let cellPoints = 60.0
  static let maxAnnotations = 1500
  static let maxMemberIds = 2000
  static let maxDrillZoom = 18.0

  /// Cheap diff key for the on-main annotation sync: comparing full `memberIds`
  /// arrays there would cost O(ids) per annotation per rebin. Centroid quantized
  /// to ~11 m so drift re-renders the pin instead of leaving it stale.
  var fingerprint: String {
    "\(representativeId)#\(count)#\(round(latitude * 10000))#\(round(longitude * 10000))"
  }
}

/// Grid-bin `points` in screen space for `viewport`: mercator-project (same family
/// as `MapClusterer`, so cells track the MapKit view), keep on-screen points,
/// collapse each ≈60 pt cell into one `MapBin`. Off-main safe: pure math.
func binMapPoints(
  _ points: [LocatedPoint], viewport: MapViewport
) -> (bins: [MapBin], visibleCount: Int) {
  let spanLng = max(viewport.spanLongitude, 0.0001)
  let spanLat = max(viewport.spanLatitude, 0.0001)
  guard viewport.width > 0, viewport.height > 0 else { return ([], 0) }
  // Mercator bounds of the visible region (Y flips: north is smaller).
  let cx = viewport.centerLongitude + 180.0
  let northY = binMercatorY(latitude: viewport.centerLatitude + spanLat / 2)
  let southY = binMercatorY(latitude: viewport.centerLatitude - spanLat / 2)
  let minX = cx - spanLng / 2
  let rangeY = max(southY - northY, 0.0001)

  // `total` stays exact for badges/counts while `ids` caps at the row-query
  // limit; the centroid divides by `total`. (Dict-held tuples are values — mutate
  // a local copy and write back, never `cells[key]!.field +=`.)
  var cells: [String: (lat: Double, lng: Double, total: Int, ids: [String])] = [:]
  var order: [String] = []
  var visible = 0
  for point in points {
    let mx = point.longitude + 180.0
    let my = binMercatorY(latitude: point.latitude)
    let px = (mx - minX) / spanLng * viewport.width
    let py = (my - northY) / rangeY * viewport.height
    guard px >= 0, px <= viewport.width, py >= 0, py <= viewport.height else { continue }
    visible += 1
    let key = "\(Int(px / MapBin.cellPoints)):\(Int(py / MapBin.cellPoints))"
    if cells[key] == nil {
      cells[key] = (0, 0, 0, [])
      order.append(key)
    }
    if var cell = cells[key] {
      cell.lat += point.latitude
      cell.lng += point.longitude
      cell.total += 1
      if cell.ids.count < MapBin.maxMemberIds {
        cell.ids.append(point.id)
      }
      cells[key] = cell
    }
  }
  var bins = order.compactMap { key -> MapBin? in
    guard let cell = cells[key], cell.total > 0, !cell.ids.isEmpty else { return nil }
    return MapBin(
      id: key, count: cell.total, representativeId: cell.ids[0],
      latitude: cell.lat / Double(cell.total), longitude: cell.lng / Double(cell.total),
      memberIds: cell.ids)
  }
  // Cap the annotation set at the largest clusters; the header count stays exact.
  if bins.count > MapBin.maxAnnotations {
    bins = Array(bins.sorted { $0.count > $1.count }.prefix(MapBin.maxAnnotations))
  }
  return (bins, visible)
}

/// Latitude → 0…360 pseudo-mercator Y (mirrors `MapClusterer`, clamped to ±85°).
private func binMercatorY(latitude: Double) -> Double {
  let clamped = min(max(latitude, -85.0), 85.0)
  let rad = clamped * .pi / 180.0
  let y = 180.0 / .pi * log(tan(.pi / 4.0 + rad / 2.0))
  return 180.0 - y
}

// MARK: - map view (diff add/remove only)

/// `MKMapView` rendering one annotation per `MapBin`, diffed by id: annotations
/// for unchanged bins are never touched, so pans only add/remove the delta.
struct MacBinnedMapView: NSViewRepresentable {
  var bins: [MapBin]
  var pipeline: MediaPipeline
  var onSelect: (MapBin) -> Void
  var onViewport: (MapViewport, Double) -> Void

  /// Drill-in target set by the SwiftUI side; the coordinator picks it up on the
  /// live map (the representable itself never holds the `MKMapView`).
  private static var drillTarget = LockedDrillTarget()

  static func zoomIn(on bin: MapBin) {
    drillTarget.request(latitude: bin.latitude, longitude: bin.longitude)
  }

  func makeNSView(context: Context) -> MKMapView {
    let map = MKMapView()
    map.delegate = context.coordinator
    return map
  }

  func updateNSView(_ map: MKMapView, context: Context) {
    let coordinator = context.coordinator
    coordinator.pipeline = pipeline
    coordinator.onSelect = onSelect
    coordinator.onViewport = onViewport
    coordinator.applyDrillTarget(on: map)
    // Diff by bin id; a changed bin (same cell, new members) is remove + add.
    let wanted = Dictionary(uniqueKeysWithValues: bins.map { ($0.id, $0) })
    var toRemove: [MKAnnotation] = []
    var liveIds = Set<String>()
    for annotation in map.annotations {
      guard let pin = annotation as? MapBinAnnotation else { continue }
      if wanted[pin.bin.id]?.fingerprint == pin.bin.fingerprint {
        liveIds.insert(pin.bin.id)
      } else {
        toRemove.append(annotation)
      }
    }
    if !toRemove.isEmpty { map.removeAnnotations(toRemove) }
    let toAdd = wanted.values.filter { !liveIds.contains($0.id) }.map(MapBinAnnotation.init)
    if !toAdd.isEmpty { map.addAnnotations(toAdd) }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  @MainActor
  final class Coordinator: NSObject, MKMapViewDelegate {
    var pipeline: MediaPipeline?
    var onSelect: ((MapBin) -> Void)?
    var onViewport: ((MapViewport, Double) -> Void)?

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      guard let pin = annotation as? MapBinAnnotation else { return nil }
      let view =
        mapView.dequeueReusableAnnotationView(withIdentifier: "mapBin")
        as? MapThumbAnnotationView ?? MapThumbAnnotationView(annotation: pin, reuseIdentifier: "mapBin")
      view.annotation = pin
      if let pipeline { view.configure(bin: pin.bin, pipeline: pipeline) }
      return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
      guard let pin = view.annotation as? MapBinAnnotation else { return }
      onSelect?(pin.bin)
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
      report(mapView)
    }

    func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
      report(mapView)
    }

    func applyDrillTarget(on map: MKMapView) {
      guard let target = MacBinnedMapView.drillTarget.take() else { return }
      let span = map.region.span
      map.setRegion(
        MKCoordinateRegion(
          center: CLLocationCoordinate2D(latitude: target.0, longitude: target.1),
          span: MKCoordinateSpan(
            latitudeDelta: max(span.latitudeDelta / 4, 0.001),
            longitudeDelta: max(span.longitudeDelta / 4, 0.001))),
        animated: true)
    }

    private func report(_ map: MKMapView) {
      let region = map.region
      let size = map.bounds.size
      guard size.width > 0, size.height > 0 else { return }
      let spanLng = max(region.span.longitudeDelta, 0.0001)
      let zoom = min(max(log2(360.0 / spanLng), 0), 21)
      onViewport?(
        MapViewport(
          centerLatitude: region.center.latitude, centerLongitude: region.center.longitude,
          spanLatitude: region.span.latitudeDelta, spanLongitude: region.span.longitudeDelta,
          width: size.width, height: size.height),
        zoom)
    }
  }
}

/// Main-actor box for the drill-in request (set from SwiftUI, consumed by the
/// coordinator on the live map). A lock guards the handoff; last write wins.
private final class LockedDrillTarget: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: (Double, Double)?

  func request(latitude: Double, longitude: Double) {
    lock.withLock { pending = (latitude, longitude) }
  }

  func take() -> (Double, Double)? {
    lock.withLock {
      let value = pending
      pending = nil
      return value
    }
  }
}

final class MapBinAnnotation: NSObject, MKAnnotation {
  var bin: MapBin

  init(bin: MapBin) { self.bin = bin }

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: bin.latitude, longitude: bin.longitude)
  }
}

/// Rounded-square representative thumbnail + count badge, composited into one
/// image. Memory cache first (`cachedImage` is synchronous); otherwise the first
/// `stream` yield replaces the gray placeholder. Async loads cancel on reuse.
@MainActor
final class MapThumbAnnotationView: MKAnnotationView {
  private static let side: CGFloat = 46
  private var loadTask: Task<Void, Never>?

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
    canShowCallout = false
    displayPriority = .required
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func prepareForReuse() {
    super.prepareForReuse()
    loadTask?.cancel()
    loadTask = nil
    image = nil
  }

  func configure(bin: MapBin, pipeline: MediaPipeline) {
    loadTask?.cancel()
    if let cg = pipeline.cachedImage(id: bin.representativeId, tier: .thumbnail) {
      image = Self.composited(thumb: NSImage(cgImage: cg, size: .zero), count: bin.count)
      return
    }
    image = Self.composited(thumb: nil, count: bin.count)
    let repId = bin.representativeId
    let count = bin.count
    loadTask = Task { @MainActor [weak self] in
      do {
        for try await loaded in await pipeline.stream(
          id: repId, thumbhash: nil, tier: .thumbnail
        ) {
          let nsImage: NSImage?
          switch loaded.content {
          case .placeholder(let img): nsImage = img
          case .tier(_, let img, _): nsImage = img
          }
          self?.image = Self.composited(thumb: nsImage, count: count)
          break
        }
      } catch {}
    }
  }

  /// 46 pt rounded-square thumbnail with a Photos-style count pill. Pure drawing —
  /// cheap enough to run per annotation without caching.
  private static func composited(thumb: NSImage?, count: Int) -> NSImage {
    let side = Self.side
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    let clip = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    clip.addClip()
    if let thumb {
      thumb.draw(in: rect)
    } else {
      NSColor.quaternaryLabelColor.setFill()
      rect.fill()
    }
    if count > 1 {
      let label = count > 99 ? "99+" : "\(count)"
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: NSColor.white,
      ]
      let textSize = (label as NSString).size(withAttributes: attrs)
      let pill = NSRect(
        x: side - textSize.width - 14, y: 4, width: textSize.width + 10, height: 20)
      NSColor.systemBlue.setFill()
      NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
      (label as NSString).draw(
        at: NSPoint(x: pill.minX + 5, y: 6), withAttributes: attrs)
    }
    image.unlockFocus()
    return image
  }
}
