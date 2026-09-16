import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI

/// WP6 slice A (U19): People grid + person detail. Moved out of
/// MacMainWindow.swift (which keeps only the `MacPeopleView(state:)` call site).
///
/// - Face grid: 120 pt circles via `pipeline.personThumbnail(id:)` (WP1), name
///   (or "Add Name") + photo count, named-first-then-count sort (done in SQL by
///   `peopleSummaries`), name search filter, Show-Hidden toggle.
/// - Click selects a person detail (internal navigation state — the sidebar
///   selection stays on People because it lives in MacMainWindow): that
///   person's photos in the standard `MacCollectionGridView` (Months grouping),
///   titled by name. Back returns to the grid.
/// - No rename control: the API client has no `updatePerson`.
struct MacPeopleView: View {
  @Bindable var state: MacAppState
  @State private var people: [PersonSummary] = []
  @State private var filter = ""
  @State private var showHidden = false
  @State private var selected: PersonSummary?

  private var visible: [PersonSummary] {
    people.filter { person in
      (showHidden || !person.isHidden)
        && (filter.isEmpty || person.name.localizedCaseInsensitiveContains(filter))
    }
  }

  var body: some View {
    if let person = selected {
      MacPersonDetailView(person: person, state: state) { selected = nil }
    } else {
      VStack(spacing: 0) {
        HStack {
          Text("People").font(.title2)
          Spacer()
          TextField("Search names", text: $filter)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
          Toggle("Show Hidden", isOn: $showHidden)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        if visible.isEmpty {
          ContentUnavailableView(
            people.isEmpty ? "No People" : "No Matches",
            systemImage: "person.2",
            description: Text(
              people.isEmpty
                ? "Faces will appear here after sync."
                : "No one matches \"\(filter)\"."))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 20) {
              ForEach(visible) { person in
                PersonFaceCell(person: person, pipeline: state.pipeline) { selected = person }
              }
            }
            .padding(16)
          }
        }
      }
      .accessibilityIdentifier("mac-people")
      .task { await reload() }
    }
  }

  private func reload() async {
    guard let userId = state.userId else { return }
    // peopleSummaries sorts named-first, then by count (SQL ORDER BY) — no
    // client re-sort, so large lists stay cheap.
    people = (try? await state.store.peopleSummaries(userId: userId)) ?? []
    if let current = selected,
      !people.contains(where: { $0.id == current.id })
    {
      selected = nil
    }
  }
}

/// Circular 120 pt face cell: name (or "Add Name") + photo count.
private struct PersonFaceCell: View {
  var person: PersonSummary
  var pipeline: MediaPipeline
  var action: () -> Void
  @State private var image: NSImage?

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Group {
          if let image {
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
          } else {
            Circle().fill(.gray.opacity(0.25))
          }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        Text(person.name.isEmpty ? "Add Name" : person.name)
          .font(.headline)
          .lineLimit(1)
          .foregroundStyle(person.name.isEmpty ? .secondary : .primary)
        Text("\(person.assetCount) photo\(person.assetCount == 1 ? "" : "s")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("mac-person-\(person.id)")
    .task(id: person.id) {
      // First yield is the memory/disk placeholder or cached tier; later
      // yields upgrade to network quality. Every yield replaces the image.
      do {
        for try await loaded in await pipeline.personThumbnail(id: person.id) {
          switch loaded.content {
          case .placeholder(let img): image = img
          case .tier(_, let img, _): image = img
          }
        }
      } catch {}
    }
  }
}

/// One person's photos in the standard grid (Months), titled by name.
private struct MacPersonDetailView: View {
  var person: PersonSummary
  var state: MacAppState
  var onBack: () -> Void
  @State private var snapshot = TimelineGridSnapshot.empty
  @State private var selectedIds = Set<String>()
  @State private var itemSize: CGFloat = 160
  @State private var generation = 0

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button { onBack() } label: { Label("People", systemImage: "chevron.left") }
        Text(person.name.isEmpty ? "Unnamed" : person.name).font(.title2)
        Spacer()
        Text("\(snapshot.rows.count) item\(snapshot.rows.count == 1 ? "" : "s")")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      MacCollectionGridView(
        snapshot: snapshot,
        lastPatch: (snapshot.revision, []),
        pipeline: state.pipeline,
        store: state.store,
        exporter: nil,
        itemSize: itemSize,
        selectedIds: $selectedIds,
        onSelectionChange: { _ in },
        onOpen: { _ in },
        onPreview: { _ in },
        onToggleFavorite: { _ in },
        onMagnify: { itemSize = MacTimelineLayout.clampedItemSide(itemSize + $0) }
      )
    }
    .accessibilityIdentifier("mac-person-detail")
    .task(id: person.id) { await reload() }
  }

  private func reload() async {
    guard let userId = state.userId else { return }
    do {
      let ctx = try await state.store.timelineContext(for: userId)
      let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
      let rows = try await state.store.personAssets(personId: person.id, scope: scope)
      generation += 1
      snapshot = MacGridSnapshotBuilder.monthSnapshot(rows: rows, generation: generation)
    } catch {}
  }
}

/// WP6 slice A shared builder (People detail + Memories "Show all photos"):
/// newest-first rows → contiguous same-month `.month` sections → snapshot.
enum MacGridSnapshotBuilder {
  static func monthSnapshot(rows: [TimelineRow], generation: Int) -> TimelineGridSnapshot {
    var sections: [TimelineSourceSection] = []
    var currentKey = "\u{0}"
    var current: [TimelineRow] = []
    var currentHeader: String? = nil
    for row in rows {
      let key = monthKey(for: row.localDateTime)
      if key != currentKey, !current.isEmpty {
        sections.append(TimelineSourceSection(header: currentHeader, kind: .month, rows: current))
        current = []
      }
      currentKey = key
      currentHeader = key.isEmpty ? "Unknown" : TimelineBucketTitle.title(forKey: key, kind: .month)
      current.append(row)
    }
    if !current.isEmpty {
      sections.append(TimelineSourceSection(header: currentHeader, kind: .month, rows: current))
    }
    return TimelineGridSnapshot.build(
      sections: sections, order: .newestFirst, include: { _ in true }, generation: generation)
  }

  private static func monthKey(for date: Date?) -> String {
    guard let date else { return "" }
    let parts = Calendar.current.dateComponents([.year, .month], from: date)
    guard let year = parts.year, let month = parts.month else { return "" }
    return String(format: "%04d-%02d", year, month)
  }
}
