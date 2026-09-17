import Foundation
import LocalStore
import SwiftUI

// MARK: - months view (WP2 §3, spec native-04)

// One section per month ("Sep 2026" header): a hero card with the month's key
// photo plus a 3-column row of day cards with the day number top-left. Tapping a
// day opens All. Driven by `bucketSummaries(.month)` for sections and
// `bucketSummaries(.day)` for the day cards — key thumbnails only.
// Formatters are static (global rule 7: never allocate per call).

struct MonthsView: View {
  @EnvironmentObject var session: AppSession
  var source: LibrarySource
  /// A year key ("2024") to scroll to on appear (Years drill-down).
  var scrollToYear: String?
  var onSelectDay: (String) -> Void

  @State private var months: [PhotosLocalStore.TimelineBucketSummary] = []
  @State private var daysByMonth: [String: [PhotosLocalStore.TimelineBucketSummary]] = [:]
  @State private var failed = false

  private static let monthParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    return formatter
  }()

  private static let monthTitle: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM yyyy"
    return formatter
  }()

  private var scopeKey: String {
    switch source {
    case .all: return "all"
    case .personal: return "personal"
    case .space(let id): return "space-\(id)"
    case .library(let id): return "library-\(id)"
    }
  }

  var body: some View {
    Group {
      if months.isEmpty && !failed {
        ProgressView()
          .accessibilityIdentifier("months-loading")
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
              ForEach(months, id: \.key) { month in
                Section {
                  monthBody(month)
                } header: {
                  Text(Self.title(for: month.key))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .background(.background)
                    .accessibilityIdentifier("month-header-\(month.key)")
                }
                .id("month-\(month.key)")
              }
            }
            .padding(.vertical, 8)
          }
          .onAppear { scrollToTarget(with: proxy) }
          .onChange(of: scrollToYear) { _, _ in scrollToTarget(with: proxy) }
        }
      }
    }
    .accessibilityIdentifier("months-view")
    .task(id: scopeKey) { await load() }
  }

  private func monthBody(_ month: PhotosLocalStore.TimelineBucketSummary) -> some View {
    VStack(spacing: 8) {
      // No maxWidth: rows stretch on their own; a greedy width plus the art's
      // intrinsic aspect breaks layout (see WP2 report).
      KeyAssetPhoto(assetId: month.keyAssetId)
        .frame(height: 200)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("month-hero-\(month.key)")
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
        ForEach(daysByMonth[month.key] ?? [], id: \.key) { day in
          Button { onSelectDay(day.key) } label: {
            ZStack(alignment: .topLeading) {
              // Square from the column width; .fit never overflows (unlike .fill,
              // which unions — see WP2 report). The art fills via scaledToFill.
              KeyAssetPhoto(assetId: day.keyAssetId)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
              Text(Self.dayNumber(for: day.key))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .shadow(radius: 3)
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("day-card-\(day.key)")
        }
      }
    }
    .padding(.horizontal)
  }

  private func scrollToTarget(with proxy: ScrollViewProxy) {
    guard let year = scrollToYear,
      let first = months.first(where: { $0.key.hasPrefix(year) })
    else { return }
    proxy.scrollTo("month-\(first.key)", anchor: .top)
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
    async let monthSummaries = try? store.bucketSummaries(scope: scope, granularity: .month)
    async let daySummaries = try? store.bucketSummaries(scope: scope, granularity: .day)
    let (loadedMonths, loadedDays) = await (monthSummaries, daySummaries)
    guard !Task.isCancelled else { return }
    guard let loadedMonths, let loadedDays else {
      failed = true
      return
    }
    months = loadedMonths
    var grouped: [String: [PhotosLocalStore.TimelineBucketSummary]] = [:]
    for day in loadedDays {
      grouped[String(day.key.prefix(7)), default: []].append(day)
    }
    daysByMonth = grouped
  }

  static func title(for monthKey: String) -> String {
    guard let date = monthParser.date(from: monthKey) else { return monthKey }
    return monthTitle.string(from: date)
  }

  static func dayNumber(for dayKey: String) -> String {
    String(dayKey.suffix(2))
  }
}
