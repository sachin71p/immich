import CoreModel
import MapKit
import SwiftUI

/// A9.4: the map controller behind Places. An `MKMapView` renders one annotation per
/// `MapCluster` (pre-computed by the shared, unit-tested `MapClusterer`), so markers and
/// clusters flow through one path. Tapping an annotation reports its member asset ids for
/// the selection grid below the map; zooming re-clusters through the reported zoom level.
final class PhotoClusterAnnotation: NSObject, MKAnnotation {
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

struct ClusteredMapView: UIViewRepresentable {
  var clusters: [MapCluster]
  var onSelect: ([String]) -> Void
  var onZoomChange: (Double) -> Void

  func makeUIView(context: Context) -> MKMapView {
    let map = MKMapView()
    map.delegate = context.coordinator
    map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "photo")
    return map
  }

  func updateUIView(_ map: MKMapView, context: Context) {
    context.coordinator.onSelect = onSelect
    context.coordinator.onZoomChange = onZoomChange
    let wanted = Set(clusters.map(\.id))
    let current = Set(
      map.annotations.compactMap { ($0 as? PhotoClusterAnnotation)?.cluster.id })
    guard wanted != current else { return }
    map.removeAnnotations(map.annotations)
    map.addAnnotations(clusters.map(PhotoClusterAnnotation.init))
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, MKMapViewDelegate {
    var onSelect: (([String]) -> Void)?
    var onZoomChange: ((Double) -> Void)?
    private var lastZoom: Double = -1

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      guard let photo = annotation as? PhotoClusterAnnotation else { return nil }
      let view = mapView.dequeueReusableAnnotationView(
        withIdentifier: "photo", for: photo) as? MKMarkerAnnotationView
      view?.glyphText = photo.cluster.isCluster ? "\(photo.cluster.count)" : nil
      view?.markerTintColor = photo.cluster.isCluster ? .systemBlue : .systemRed
      view?.displayPriority = .required
      return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
      guard let photo = view.annotation as? PhotoClusterAnnotation else { return }
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
