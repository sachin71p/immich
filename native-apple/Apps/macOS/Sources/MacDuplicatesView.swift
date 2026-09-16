import CoreModel
import Media
import SwiftUI
import SyncEngine

/// Review surface backed by Immich's duplicate-groups endpoint. Groups are deliberately not
/// filtered to the current timeline/source picker: the server has already applied every library
/// membership the user may access.
struct MacDuplicatesView: View {
  @Bindable var state: MacAppState
  var openViewer: (String) -> Void
  @State private var groups: [DuplicateGroup] = []
  @State private var assetsByID: [String: Asset] = [:]
  @State private var isLoading = false
  @State private var error: String?

  var body: some View {
    Group {
      if isLoading {
        ProgressView("Finding duplicates…")
      } else if let error {
        ContentUnavailableView("Duplicates unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
      } else if groups.isEmpty {
        ContentUnavailableView("No Duplicates Found", systemImage: "rectangle.on.rectangle")
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(groups) { group in
              VStack(alignment: .leading, spacing: 8) {
                Text("Duplicate group · \(group.assetIds.count) items")
                  .font(.headline)
                HStack(alignment: .top, spacing: 10) {
                  ForEach(group.assetIds, id: \.self) { id in
                    Button { openViewer(id) } label: {
                      VStack(alignment: .leading, spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                          MacDuplicateThumb(
                            assetId: id, thumbhash: assetsByID[id]?.thumbhash,
                            pipeline: state.pipeline)
                          if group.suggestedKeepAssetIds.contains(id) {
                            Image(systemName: "checkmark.circle.fill")
                              .font(.title3)
                              .foregroundStyle(.green)
                              .background(.white, in: Circle())
                              .padding(6)
                          }
                        }
                        Text(assetsByID[id]?.originalFileName ?? "Loading photo…")
                          .lineLimit(2)
                          .frame(width: 130, alignment: .leading)
                      }
                      .padding(10)
                      .frame(width: 150, alignment: .leading)
                      .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                  }
                }
                Text("Green check marks Immich’s suggested item to keep. Open an item to review or remove it.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .padding()
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
          }
          .padding()
        }
      }
    }
    .navigationTitle("Duplicates")
    .task { await load() }
  }

/// Group-item thumbnail: first pipeline yield (placeholder or cached tier) is enough,
/// same pattern as the Collections cover tile. Resolution controls ("Keep best / Trash
/// others") are deliberately absent: the generated API client only includes
/// `getAssetDuplicates` — `resolveDuplicates`/`deleteDuplicates` are not in
/// `openapi-generator-config.yaml`'s filter, and extending that filter means editing an
/// existing PhotosCore file, which WP6 forbids. Per §6 the control isn't shown.
private struct MacDuplicateThumb: View {
  var assetId: String
  var thumbhash: String?
  var pipeline: MediaPipeline
  @State private var image: NSImage?

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor))
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Image(systemName: "photo")
          .font(.title2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 130, height: 96)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .task(id: assetId) {
      do {
        for try await first in await pipeline.stream(
          id: assetId, thumbhash: thumbhash, tier: .thumbnail
        ) {
          switch first.content {
          case .placeholder(let img): image = img
          case .tier(_, let img, _): image = img
          }
          break
        }
      } catch {
        // Placeholder remains; the filename label below still identifies the item.
      }
    }
  }
}

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let result = try await DuplicateService(connection: state.connection).groups()
      groups = result
      let ids = result.flatMap(\.assetIds)
      assetsByID = Dictionary(uniqueKeysWithValues: (try await state.store.assets(ids: ids)).map { ($0.id, $0) })
    } catch {
      self.error = error.localizedDescription
    }
  }
}
