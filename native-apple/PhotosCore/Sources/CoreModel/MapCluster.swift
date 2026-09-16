import Foundation

/// A9.4: grid-based map clustering over plain latitude/longitude pairs.
///
/// The map views on both platforms (MapKit, driven through an `MKMapView` controller) share
/// this pure clustering step: points that fall in the same web-mercator cell at the current
/// zoom level collapse into one `MapCluster`. Single-point cells pass through as one-item
/// clusters so the views render markers and clusters through one code path. No MapKit import —
/// the views map `MapCluster` onto `MKClusterAnnotation` themselves.
public struct MapClusterItem: Sendable, Hashable {
  public var id: String
  public var latitude: Double
  public var longitude: Double

  public init(id: String, latitude: Double, longitude: Double) {
    self.id = id
    self.latitude = latitude
    self.longitude = longitude
  }
}

public struct MapCluster: Sendable, Hashable, Identifiable {
  public var items: [MapClusterItem]

  /// Stable id derived from the sorted member ids, so SwiftUI diffing survives reloads.
  public var id: String { items.map(\.id).sorted().joined(separator: ",") }
  public var count: Int { items.count }
  public var isCluster: Bool { items.count > 1 }

  public var centroid: (latitude: Double, longitude: Double) {
    guard !items.isEmpty else { return (0, 0) }
    let lat = items.reduce(0.0) { $0 + $1.latitude } / Double(items.count)
    let lon = items.reduce(0.0) { $0 + $1.longitude } / Double(items.count)
    return (lat, lon)
  }

  public var memberIds: [String] { items.map(\.id) }

  public init(items: [MapClusterItem]) { self.items = items }

  public static func == (lhs: MapCluster, rhs: MapCluster) -> Bool { lhs.items == rhs.items }
  public func hash(into hasher: inout Hasher) { hasher.combine(items) }
}

public enum MapClusterer {
  /// Grid-cluster `items` for a map at `zoomLevel` (0…21, web-mercator). Higher zoom levels
  /// use smaller cells, so pinch-zooming in splits clusters apart. The cell span halves per
  /// zoom level from a 360° world at zoom 0.
  public static func cluster(_ items: [MapClusterItem], zoomLevel: Double) -> [MapCluster] {
    guard !items.isEmpty else { return [] }
    let zoom = min(max(zoomLevel, 0), 21)
    let cellSpan = 360.0 / pow(2.0, zoom)
    var cells: [String: [MapClusterItem]] = [:]
    var order: [String] = []
    for item in items {
      let x = Self.mercatorX(longitude: item.longitude)
      let y = Self.mercatorY(latitude: item.latitude)
      let key = "\(Int(floor(x / cellSpan))):\(Int(floor(y / cellSpan)))"
      if cells[key] == nil { order.append(key) }
      cells[key, default: []].append(item)
    }
    return order.compactMap { cells[$0] }.map { MapCluster(items: $0) }
  }

  /// Longitude → 0…360 pseudo-mercator X (linear; fine for clustering cells).
  static func mercatorX(longitude: Double) -> Double { longitude + 180.0 }

  /// Latitude → 0…360 pseudo-mercator Y (true mercator projection, clamped to ±85°).
  static func mercatorY(latitude: Double) -> Double {
    let clamped = min(max(latitude, -85.0), 85.0)
    let rad = clamped * .pi / 180.0
    let y = 180.0 / .pi * log(tan(.pi / 4.0 + rad / 2.0))
    return 180.0 - y
  }
}
