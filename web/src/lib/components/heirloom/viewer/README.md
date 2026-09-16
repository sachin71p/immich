# Heirloom Web V2 — viewer variant (WP8)

Owner: WP8 viewer agent. Shell agent: read **Component interface** below, do not
create route files here (PLAN §14 ownership).

## What this is

Explicit opt-in V2 viewer variant (lead decision D3): black canvas, native
toolbar order, wrap-around paging, display-only rotation, inspector with EXIF
browser. Composed with `asset-viewer-manager` and reused classic viewers —
never a fork. Classic viewer files are untouched (zero edits).

## Files

- `viewer-variant.ts` — pure logic: `isV2ViewerRoute` (D3 branching),
  `pageViewerIndex`/`pageViewerCursor` (wrap-around), `nextDisplayRotation` /
  `displayRotationStyle` (client-side rotation), `composeHeirloomToolbar` +
  `HEIRLOOM_VIEWER_TOOLBAR_ORDER` (native order, Edit iff canEdit),
  `HEIRLOOM_LIVE_TEXT_NOTE` / `HEIRLOOM_ROTATE_NOTE` (documented exceptions).
- `HeirloomViewer.svelte` — the variant component.
- `viewer-variant.spec.ts`, `HeirloomViewer.spec.ts` — vitest coverage.

## Reuse vs variant vs exception (feasibility verdict per WP8 action)

| Action | Verdict | Treatment |
| --- | --- | --- |
| Black canvas | reuse | `bg-black` root; media via `PhotoViewer` / `VideoWrapperViewer` / `ImagePanoramaViewer` |
| Favorite | reuse | `getAssetActions` Favorite/Unfavorite `ActionButton`s |
| Rotate | variant + exception | `rotation` state → CSS transform on canvas wrapper only; persistence unavailable and labeled (no `UpdateAssetDto` rotation field exists) |
| Delete | reuse | classic `DeleteAction`; after delete, advance to next sibling (wrap) or close |
| Move to… | reuse | classic `MoveToLibraryAction`; emits `onAssetChange` refresh hint (PLAN §13) |
| Add to Album | reuse | `getAssetActions` AddToAlbum (existing modal) |
| Edit | reuse gated | existing `Edit` action + `EditorPanel` **iff** `Edit.$if()` passes; otherwise absent (WP10 Decision A — no inert replicas) |
| Info / inspector | reuse | V2-local toggle + classic `DetailPanel` (fields + `DetailPanelFullMetadata` EXIF browser) |
| OCR | reuse | classic `OcrButton` when `ocrManager.hasOcrData` (server-backed) |
| Live Text | exception | disabled, labeled control (`HEIRLOOM_LIVE_TEXT_NOTE`); VisionKit is macOS-only (WP1 §8) |
| Prev/next paging | variant | `pageViewerCursor` wrap-around over shell-provided `assets`; overlay buttons |
| Keyboard paging | variant | ArrowLeft/Right, Escape, `r` rotate, `i` info (input-focus guarded) |
| Zoom | reuse | inside `PhotoViewer` (pinch/scroll/wheel via `assetViewerManager`) |
| Video + Live Photos | reuse | `VideoWrapperViewer` incl. motion-photo branch (`isPlayingMotionPhoto`) |
| Tiered loading | reuse | inside the media viewers (`imageLoaderStatus` / adaptive loading) |
| Open in new window | variant | `window.open` on a **real V2 URL** from shell `assetHref`; absent without it |

## Component interface (shell agent)

```svelte
<HeirloomViewer
  assetId={params.assetId}      <!-- URL-backed, shell-owned -->
  assets={viewerContextAssets}  <!-- sibling AssetResponseDto[] for wrap paging -->
  album={album ?? null}         <!-- optional album scoping -->
  assetHref={(id) => `/v2/library/${id}`}  <!-- optional; enables new-window -->
  onNavigate={(id) => goto(...)}  <!-- shell: goto V2 asset URL -->
  onClose={() => goto(...)}       <!-- shell: restore collection URL -->
  onAssetChange={(asset) => refreshStores(asset)}  <!-- mutation refresh hint -->
/>
```

- Branch on `isV2ViewerRoute(page.route.id)` so the classic viewer never
  renders inside `/v2` (parent `(user)/+layout` drives the classic manager
  from `page.data.asset` — the shell wrapper must own the asset URL param).
- `assets` should be the current viewer context in display order; unknown
  `assetId` renders the error state (no crash).
- Test ids: `heirloom-viewer`, `heirloom-viewer-toolbar`,
  `heirloom-viewer-canvas`, `heirloom-viewer-inspector`,
  `heirloom-viewer-editor`.
