import CoreModel
import LocalStore
import MapKit
import Media
import Rules
import SwiftUI

/// A9.4 (macOS): clustered map + selection grid, mirroring the iOS Places experience.
/// An `MKMapView` controller renders one annotation per `MapCluster` (shared `MapClusterer`);
/// tapping an annotation fills the selection grid below; double-clicking a thumbnail opens
/// the viewer.
struct MacMapPlacesView: View {
  @Bindable var state: MacAppState
  var openViewer: (String) -> Void

  @State private var points: [MapPoint] = []
  @State private var assets: [Asset] = []
  @State private var zoomLevel: Double = 3
  @State private var selectedIds: [String] = []

  private var clusters: [MapCluster] {
    MapClusterer.cluster(
      points.map { MapClusterItem(id: $0.id, latitude: $0.latitude, longitude: $0.longitude) },
      zoomLevel: zoomLevel)
  }

  private var selectedAssets: [Asset] {
    let wanted = Set(selectedIds)
    return assets.filter { wanted.contains($0.id) }
  }

  var body: some View {
    HSplitView {
      MacClusteredMapView(
        clusters: clusters,
        onSelect: { selectedIds = $0 },
        onZoomChange: { zoomLevel = $0 }
      )
      .frame(minWidth: 300)
      .accessibilityIdentifier("mac-places-map")
      VStack(alignment: .leading) {
        Text(selectedIds.isEmpty ? "\(points.count) located photos" : "\(selectedAssets.count) selected")
          .font(.headline)
          .padding(.horizontal)
          .accessibilityIdentifier("mac-places-count")
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))]) {
            ForEach(selectedIds.isEmpty ? assets : selectedAssets, id: \.id) { asset in
              Button { openViewer(asset.id) } label: {
                MacMapThumbnail(asset: asset, pipeline: state.pipeline)
                  .frame(width: 96, height: 96)
                  .clipShape(RoundedRectangle(cornerRadius: 6))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal)
        }
      }
      .frame(minWidth: 220, idealWidth: 320)
    }
    .task { await load() }
  }

  private func load() async {
    guard let userId = state.userId else { return }
    do {
      let ctx = try await state.store.timelineContext(for: userId)
      let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
      points = try await state.store.mapPoints(scope: scope)
      assets = try await state.store.assets(ids: points.map(\.id))
    } catch {}
  }
}

/// One thumbnail cell for the selection grid (thumbnail tier through `MediaPipeline`).
struct MacMapThumbnail: View {
  var asset: Asset
  var pipeline: MediaPipeline?
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
    .task(id: asset.id) {
      guard let pipeline,
        let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail)
      else { return }
      switch loaded.content {
      case .placeholder(let img): image = img
      case .tier(_, let img, _): image = img
      }
    }
  }
}

final class MacPhotoClusterAnnotation: NSObject, MKAnnotation {
  var cluster: MapCluster

  init(cluster: MapCluster) { self.cluster = cluster }

  var coordinate: CLLocationCoordinate2D {
    let c = cluster.centroid
    return CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
  }

  var title: String? {
    cluster.isCluster ? "\(cluster.count) photos" : nil
  }
}

struct MacClusteredMapView: NSViewRepresentable {
  var clusters: [MapCluster]
  var onSelect: ([String]) -> Void
  var onZoomChange: (Double) -> Void

  func makeNSView(context: Context) -> MKMapView {
    let map = MKMapView()
    map.delegate = context.coordinator
    map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "photo")
    return map
  }

  func updateNSView(_ map: MKMapView, context: Context) {
    context.coordinator.onSelect = onSelect
    context.coordinator.onZoomChange = onZoomChange
    let wanted = Set(clusters.map(\.id))
    let current = Set(
      map.annotations.compactMap { ($0 as? MacPhotoClusterAnnotation)?.cluster.id })
    guard wanted != current else { return }
    map.removeAnnotations(map.annotations)
    map.addAnnotations(clusters.map(MacPhotoClusterAnnotation.init))
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, MKMapViewDelegate {
    var onSelect: (([String]) -> Void)?
    var onZoomChange: ((Double) -> Void)?
    private var lastZoom: Double = -1

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      guard let photo = annotation as? MacPhotoClusterAnnotation else { return nil }
      let view = mapView.dequeueReusableAnnotationView(
        withIdentifier: "photo", for: photo) as? MKMarkerAnnotationView
      view?.glyphText = photo.cluster.isCluster ? "\(photo.cluster.count)" : nil
      view?.markerTintColor = photo.cluster.isCluster ? .systemBlue : .systemRed
      view?.displayPriority = .required
      return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
      guard let photo = view.annotation as? MacPhotoClusterAnnotation else { return }
      onSelect?(photo.cluster.memberIds)
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
      let span = max(mapView.region.span.longitudeDelta, 0.0001)
      let zoom = min(max(log2(360.0 / span), 0), 21)
      guard abs(zoom - lastZoom) >= 0.5 else { return }
      lastZoom = zoom
      onZoomChange?(zoom)
    }
  }
}
