import CoreModel
import LocalStore
import SwiftUI

// MARK: - grid detail host (WP4 §4: every detail screen is an AssetGridView)

// All Collections detail screens share this host: an optional hero cover header
// over the WP1 `AssetGridView` (5 columns like native-20), opening the viewer via
// `ViewerRoute` (ids resolved once per navigation; WP3 pages it lazily).
struct GridDetailView: View {
  @EnvironmentObject var session: AppSession
  var title: String
  var source: AssetGridSource
  var header: AnyView? = nil

  @State private var columns = 5
  @State private var viewerRequest: ViewerRequest?

  var body: some View {
    AssetGridView(
      source: source,
      store: session.store,
      pipeline: session.pipeline,
      columns: $columns,
      aspectFit: false,
      onOpen: { route in
        viewerRequest = ViewerRequest(ids: route.resolveIds(), initialId: route.startId)
      },
      header: header,
      showsSectionHeaders: false
    )
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("detail-grid")
    .fullScreenCover(item: $viewerRequest) { request in
      ViewerView(ids: request.ids, initialId: request.initialId)
    }
  }
}
// Detail over an explicitly loaded id list (album, person, utility collections):
// ids resolve in the hosting screen's `.task` (caller order kept: date desc for
// albums, relevance for search-like lists), then the grid takes over. Hosts show
// a spinner until the first id batch lands and reload on pull-to-refresh.
struct IdListDetail: View {
  var title: String
  var ids: [String]?
  var header: AnyView? = nil

  var body: some View {
    Group {
      if let ids {
        GridDetailView(title: title, source: .ids(ids), header: header)
      } else {
        ProgressView().navigationTitle(title)
      }
    }
  }
}
