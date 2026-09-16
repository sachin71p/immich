import CoreModel
import Foundation
import SwiftUI

// Canvas catalogue for every macOS screen that can be meaningfully constructed without a live
// server, camera, or media file. Open this file and use the Canvas variant picker to inspect a
// screen; all stateful previews use `MacPreviewFixture` and therefore never touch Immich.

private let previewSpace = Space(
  id: "preview-space", name: "Family", description: "Preview space",
  createdAt: .now, updatedAt: .now)

#Preview("Library") {
  MacPreviewFixture { state in
    MacLibraryBrowser(state: state).frame(width: 1400, height: 900)
  }
}

#Preview("Connect") {
  MacPreviewFixture { state in
    MacConnectView(state: state).frame(width: 700, height: 520)
  }
}

#Preview("All Albums") {
  MacPreviewFixture { state in
    MacAllAlbumsView(state: state, openAlbum: { _ in }).frame(width: 1100, height: 760)
  }
}

#Preview("Search") {
  MacPreviewFixture { state in
    MacSearchView(state: state, onOpenViewer: { _ in }).frame(width: 1100, height: 760)
  }
}

#Preview("Memories") {
  MacPreviewFixture { state in
    MacMemoriesView(state: state).frame(width: 1000, height: 700)
  }
}

#Preview("Map") {
  MacPreviewFixture { state in
    MacMapPlacesView(state: state, openViewer: { _ in }).frame(width: 1100, height: 760)
  }
}

#Preview("Storage") {
  MacPreviewFixture { state in
    MacStorageView(state: state).frame(width: 900, height: 650)
  }
}

#Preview("Settings") {
  MacPreviewFixture { state in
    MacSettingsView(state: state).frame(width: 800, height: 700)
  }
}

#Preview("Duplicates") {
  MacPreviewFixture { state in
    MacDuplicatesView(state: state, openViewer: { _ in }).frame(width: 900, height: 650)
  }
}

#Preview("Viewer") {
  MacPreviewFixture { state in
    MacViewerView(state: state, assetId: "asset-personal-1")
      .frame(width: 1000, height: 700)
  }
}

#Preview("New Shared Library") {
  MacPreviewFixture { state in
    MacNewSpaceSheet(state: state, onDone: {}).frame(width: 480, height: 360)
  }
}

#Preview("Manage Shared Library") {
  MacPreviewFixture { state in
    MacSpaceManageSheet(state: state, space: previewSpace, role: .owner, onDone: {})
      .frame(width: 620, height: 520)
  }
}

#Preview("New Album") {
  MacPreviewFixture { state in
    MacNewAlbumSheet(state: state, seedAssetIds: ["asset-personal-1"], onDone: {})
      .frame(width: 480, height: 360)
  }
}

#Preview("Add to Album") {
  MacPreviewFixture { state in
    MacAddToAlbumSheet(state: state, assetIds: ["asset-personal-1"], onDone: {})
      .frame(width: 560, height: 460)
  }
}

#Preview("Move Assets") {
  MacPreviewFixture { state in
    MacMoveSheet(state: state, assetIds: ["asset-personal-1"], onDone: { _ in })
      .frame(width: 560, height: 460)
  }
}

#Preview("Import Destination") {
  MacPreviewFixture { state in
    MacImportChooserSheet(state: state, urls: [URL(fileURLWithPath: "/tmp/preview-photo.jpg")], onDone: {})
      .frame(width: 560, height: 420)
  }
}

#Preview("Camera Import") {
  MacPreviewFixture { state in
    MacCameraImportView(state: state).frame(width: 900, height: 620)
  }
}
