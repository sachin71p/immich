import LocalStore
import SwiftUI

// MARK: - years view (WP2 §3, spec native-05)

// Vertical list of full-width rounded (≈16 pt) cards, one per year, with the key
// photo and the year label top-left. Tapping a year opens Months scrolled to it.
// Driven by `bucketSummaries(.year)` — key thumbnails only.

struct YearsView: View {
  @EnvironmentObject var session: AppSession
  var source: LibrarySource
  var onSelectYear: (String) -> Void

  private var scopeKey: String {
    switch source {
    case .all: return "all"
    case .personal: return "personal"
    case .space(let id): return "space-\(id)"
    case .library(let id): return "library-\(id)"
    }
  }

  @State private var years: [PhotosLocalStore.TimelineBucketSummary] = []
  @State private var failed = false

  var body: some View {
    Group {
      if years.isEmpty && !failed {
        ProgressView()
          .accessibilityIdentifier("years-loading")
      } else {
        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(years, id: \.key) { year in
              Button { onSelectYear(year.key) } label: {
                ZStack(alignment: .topLeading) {
                  // No maxWidth: stack rows stretch on their own; a greedy width
                  // plus the art's intrinsic aspect breaks layout (see report).
                  KeyAssetPhoto(assetId: year.keyAssetId)
                    .frame(height: 180)
                    .clipped()
                  Text(year.key)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("year-card-\(year.key)")
            }
          }
          .padding(.horizontal)
          .padding(.vertical, 8)
        }
      }
    }
    .accessibilityIdentifier("years-view")
    .task(id: scopeKey) { await load() }
  }

  private func load() async {
    failed = false
    guard let store = session.store,
      let scope = try? await session.timelineScope(explicit: source.filter)
    else {
      failed = true
      return
    }
    guard !Task.isCancelled else { return }
    if let summaries = try? await store.bucketSummaries(scope: scope, granularity: .year) {
      years = summaries
    } else {
      failed = true
    }
  }
}
