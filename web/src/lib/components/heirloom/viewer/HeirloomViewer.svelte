<!-- Heirloom Web V2 — viewer variant (WP8, lead decision D3).
  Explicit opt-in variant composed with `asset-viewer-manager` (never a fork):
  the shell agent's `/v2` `[[assetId]]` route wrappers render this component
  (branching via `isV2ViewerRoute`), classic routes keep the classic viewer.
  No file under `asset-viewer/` is modified or duplicated here — media,
  inspector, OCR, delete/move/edit flows are all reused.

  Contract (WP1 §5): black canvas; toolbar order Favorite, Rotate (display-only),
  Delete, Move to…, Add to Album, [Edit iff canEdit], Info, Live Text
  (macOS-only exception + server-backed OCR); wrap-around prev/next paging;
  keyboard paging; zoom/video/Live Photos via reused viewers; inspector with
  EXIF browser via reused `DetailPanel`; asset identity stays URL-backed
  (the shell owns `goto` — this component only emits `onNavigate`/`onClose`).
-->
<script lang="ts">
  import { focusTrap } from '$lib/actions/focus-trap';
  import type { OnAction, PreAction } from '$lib/components/asset-viewer/actions/action';
  import DeleteAction from '$lib/components/asset-viewer/actions/DeleteAction.svelte';
  import MoveToLibraryAction from '$lib/components/asset-viewer/actions/MoveToLibraryAction.svelte';
  import type { AssetCursor } from '$lib/components/asset-viewer/AssetViewer.svelte';
  import DetailPanel from '$lib/components/asset-viewer/DetailPanel.svelte';
  import EditorPanel from '$lib/components/asset-viewer/editor/EditorPanel.svelte';
  import ImagePanoramaViewer from '$lib/components/asset-viewer/ImagePanoramaViewer.svelte';
  import OcrButton from '$lib/components/asset-viewer/OcrButton.svelte';
  import PhotoViewer from '$lib/components/asset-viewer/PhotoViewer.svelte';
  import VideoViewer from '$lib/components/asset-viewer/VideoWrapperViewer.svelte';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import { AssetAction, ProjectionType } from '$lib/constants';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { getAssetActions } from '$lib/services/asset.service';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { ocrManager } from '$lib/stores/ocr.svelte';
  import { getSharedLink } from '$lib/utils';
  import { AssetTypeEnum, type AlbumResponseDto, type AssetResponseDto } from '@immich/sdk';
  import { ActionButton, Icon, IconButton, type ActionItem } from '@immich/ui';
  import {
    mdiChevronLeft,
    mdiChevronRight,
    mdiClose,
    mdiInformationOutline,
    mdiMotionPauseOutline,
    mdiMotionPlayOutline,
    mdiOpenInNew,
    mdiRotateRight,
    mdiTextBoxSearchOutline,
  } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { SwipeCustomEvent } from 'svelte-gestures';
  import {
    composeHeirloomToolbar,
    displayRotationStyle,
    HEIRLOOM_LIVE_TEXT_NOTE,
    HEIRLOOM_ROTATE_NOTE,
    nextDisplayRotation,
    pageViewerCursor,
    pageViewerIndex,
    type DisplayRotation,
  } from './viewer-variant';

  interface Props {
    /** Current asset id. URL-backed: owned by the shell route (`[[assetId]]`). */
    assetId: string;
    /** Viewer context (sibling list) for wrap-around paging. */
    assets: AssetResponseDto[];
    /** Album context for add/remove/cover scoping, when opened from an album. */
    album?: AlbumResponseDto | null;
    /**
     * Builds the real V2 asset URL for an id (shell-owned route helper).
     * When provided, an "open in new window" control renders (`window.open`
     * on a real V2 URL, PLAN §4.3 exception treatment); otherwise it is absent.
     */
    assetHref?: (assetId: string) => string;
    /** Shell navigates to the V2 asset URL (deep-link open, back/forward coherent). */
    onNavigate?: (assetId: string) => void;
    /** Shell restores the collection URL (close restores collection state). */
    onClose?: () => void;
    /** Shell refresh hint after mutations that may move the asset out of source. */
    onAssetChange?: (asset: AssetResponseDto) => void;
  }

  let { assetId, assets, album = null, assetHref, onNavigate, onClose, onAssetChange }: Props = $props();

  const sharedLink = getSharedLink();

  // Wrap-around cursor across the viewer context (native `viewerContext` paging).
  const cursor = $derived(pageViewerCursor(assets, assetId));
  const baseAsset = $derived(cursor?.current);

  // Server-confirmed updates (favorite toggle, metadata edits) refresh the
  // displayed asset without forking refresh logic.
  let assetPatch = $state<AssetResponseDto | undefined>();
  const asset = $derived(assetPatch && baseAsset && assetPatch.id === baseAsset.id ? assetPatch : baseAsset);

  // Display-only rotation (Rotate reconciliation: no server persistence call).
  let rotation = $state<DisplayRotation>(0);
  // Reset per asset so rotation never leaks across pages.
  let rotationForAsset = $state<string | undefined>();
  $effect.pre(() => {
    if (rotationForAsset !== assetId) {
      rotationForAsset = assetId;
      rotation = 0;
    }
  });

  // V2-local inspector state (independent of the classic detail-panel pref).
  let showInspector = $state(false);
  let mediaError = $state(false);
  let mediaErrorForAsset = $state<string | undefined>();
  $effect.pre(() => {
    if (mediaErrorForAsset !== assetId) {
      mediaErrorForAsset = assetId;
      mediaError = false;
    }
  });

  // fork: shared-libraries — album membership for the favorite permission (DECISIONS §4).
  const isAlbumMember = $derived(
    authManager.authenticated && !!album?.albumUsers.some(({ user }) => user.id === authManager.user.id),
  );
  const Actions = $derived(
    asset ? getAssetActions($t, { ...asset, stackPrimaryAssetId: undefined }, { isAlbumMember }) : undefined,
  );
  // `Edit` renders iff the existing working browser editor gate passes —
  // never an inert replica (WP10 Decision A posture).
  const canEdit = $derived(Actions?.Edit.$if?.() ?? false);
  const toolbar = $derived(composeHeirloomToolbar(canEdit));
  const showOcr = $derived(!!asset && asset.type === AssetTypeEnum.Image && ocrManager.hasOcrData);
  const isMotionPhoto = $derived(!!asset?.livePhotoVideoId);
  const isPlayingMotion = $derived(assetViewerManager.isPlayingMotionPhoto);
  const isVideo = $derived(asset?.type === AssetTypeEnum.Video);
  const isPanorama = $derived(
    !!asset &&
      (asset.exifInfo?.projectionType === ProjectionType.EQUIRECTANGULAR ||
        (asset.originalPath?.toLowerCase().endsWith('.insp') ?? false)),
  );
  const rotationStyle = $derived(displayRotationStyle(rotation));

  const goTo = (id: string) => {
    if (id !== assetId) {
      onNavigate?.(id);
    }
  };
  const goNext = () => {
    if (cursor) {
      goTo(cursor.next.id);
    }
  };
  const goPrevious = () => {
    if (cursor) {
      goTo(cursor.previous.id);
    }
  };

  const handleDeleteAction: OnAction = (action) => {
    if (!asset) {
      return;
    }
    if (action.type === AssetAction.TRASH || action.type === AssetAction.DELETE) {
      // The deleted asset is gone: advance to the sibling sliding into its
      // place (wrap-around), or close when the context is now empty.
      const remaining = assets.filter(({ id }) => id !== asset.id);
      if (remaining.length === 0) {
        onClose?.();
        return;
      }
      const target = remaining[pageViewerIndex(cursor?.index ?? 0, 0, remaining.length)];
      onAssetChange?.(asset);
      goTo(target.id);
    }
  };

  const handlePreAction: PreAction = (action) => {
    // Move may take the asset out of the active source (PLAN §13): hint the
    // shell to refresh/invalidate the minimum affected stores.
    if (action.type === AssetAction.MOVE && asset) {
      onAssetChange?.(asset);
    }
  };

  const handleAssetUpdate = (updated: AssetResponseDto) => {
    if (updated.id === assetId) {
      assetPatch = updated;
    }
    onAssetChange?.(updated);
  };

  const handleSwipe = (event: SwipeCustomEvent) => {
    if (assetViewerManager.zoom > 1 || ocrManager.showOverlay) {
      return;
    }
    if (event.detail.direction === 'left') {
      goNext();
    } else if (event.detail.direction === 'right') {
      goPrevious();
    }
  };

  const handleKeydown = (event: KeyboardEvent) => {
    if (event.defaultPrevented) {
      return;
    }
    // `target` can be `document` (e.g. synthetic events) — guard the DOM call.
    const target = event.target as Element | null;
    if (typeof target?.closest === 'function' && target.closest('input, textarea, select, [contenteditable="true"]')) {
      return;
    }
    switch (event.key) {
      case 'ArrowRight': {
        event.preventDefault();
        goNext();
        break;
      }
      case 'ArrowLeft': {
        event.preventDefault();
        goPrevious();
        break;
      }
      case 'Escape': {
        event.preventDefault();
        onClose?.();
        break;
      }
      case 'r':
      case 'R': {
        rotation = nextDisplayRotation(rotation);
        break;
      }
      case 'i':
      case 'I': {
        showInspector = !showInspector;
        break;
      }
    }
  };

  const viewerCursor = $derived<AssetCursor | undefined>(
    asset && cursor ? { current: asset, nextAsset: cursor.next, previousAsset: cursor.previous } : undefined,
  );

  const CloseAction: ActionItem = {
    title: $t('go_back'),
    icon: mdiClose,
    onAction: () => onClose?.(),
    shortcuts: [{ key: 'Escape' }],
  };

  // No `rotate` locale key exists (out of scope to add one): plain label.
  const RotateAction: ActionItem = {
    title: `Rotate — ${HEIRLOOM_ROTATE_NOTE}`,
    icon: mdiRotateRight,
    onAction: () => {
      rotation = nextDisplayRotation(rotation);
    },
    shortcuts: [{ key: 'r' }],
  };

  const InfoAction: ActionItem = {
    title: $t('info'),
    icon: mdiInformationOutline,
    onAction: () => {
      showInspector = !showInspector;
    },
    shortcuts: [{ key: 'i' }],
  };

  // Documented macOS-only exception (PLAN §2, WP1 §8). Rendered as a
  // disabled, labeled control — never an inert replica of VisionKit.
  // `ActionItem` carries no `disabled` flag, so this slot uses `IconButton`
  // directly instead of `ActionButton` (see template).
  const liveTextLabel = HEIRLOOM_LIVE_TEXT_NOTE;

  // No `open_in_new_window` locale key exists (out of scope to add one): plain label.
  const OpenInNewAction: ActionItem | undefined = $derived(
    asset && assetHref
      ? {
          title: 'Open in new window',
          icon: mdiOpenInNew,
          onAction: () => {
            const href = assetHref(asset.id);
            if (typeof window !== 'undefined') {
              window.open(href, '_blank', 'noopener');
            }
          },
        }
      : undefined,
  );
</script>

<OnEvents onAssetUpdate={handleAssetUpdate} />
<svelte:document onkeydown={handleKeydown} />

<section
  data-heirloom-v2
  data-testid="heirloom-viewer"
  class="fixed inset-0 z-50 grid h-full w-full grid-rows-[64px_1fr] overflow-hidden bg-black text-white"
  use:focusTrap
  aria-label="Asset viewer"
>
  <!-- WP11 A12: single-key shortcut disclosure. The shortcuts below ignore
    text inputs (see handleKeydown), but WCAG 2.1.4 still asks for
    documentation — this note is where the viewer documents keyboard use. -->
  <p class="v2-visually-hidden" data-testid="heirloom-viewer-shortcuts">
    Single-key shortcuts: R rotates the display, I toggles the info panel. They are inactive while typing in a
    text field.
  </p>
  <!-- Native-order toolbar: Favorite, Rotate, Delete, Move to…, Add to Album,
    [Edit iff canEdit], Info, Live Text (exception) -->
  <header
    data-testid="heirloom-viewer-toolbar"
    class="row-start-1 flex h-16 items-center gap-1 overflow-x-auto bg-black/90 px-3"
  >
    <div class="dark shrink-0">
      <ActionButton action={CloseAction} />
    </div>
    {#if asset && Actions}
      {#each toolbar as tool (tool)}
        {#if tool === 'favorite'}
          <ActionButton action={Actions.Favorite} />
          <ActionButton action={Actions.Unfavorite} />
        {:else if tool === 'rotate'}
          <ActionButton action={RotateAction} />
        {:else if tool === 'delete'}
          <DeleteAction {asset} onAction={handleDeleteAction} preAction={handlePreAction} />
        {:else if tool === 'move'}
          <MoveToLibraryAction {asset} preAction={handlePreAction} />
        {:else if tool === 'addToAlbum'}
          <ActionButton action={Actions.AddToAlbum} />
        {:else if tool === 'edit' && canEdit}
          <ActionButton action={Actions.Edit} />
        {:else if tool === 'info'}
          <ActionButton action={InfoAction} />
        {:else if tool === 'liveText'}
          {#if showOcr}
            <OcrButton />
          {/if}
          <IconButton
            color="secondary"
            shape="round"
            variant="ghost"
            icon={mdiTextBoxSearchOutline}
            aria-label={liveTextLabel}
            title={liveTextLabel}
            disabled
            onclick={() => {}}
          />
        {/if}
      {/each}
      {#if isMotionPhoto}
        {#if isPlayingMotion && (Actions.StopMotionPhoto.$if?.() ?? false)}
          <ActionButton action={{ ...Actions.StopMotionPhoto, icon: mdiMotionPauseOutline }} />
        {:else if !isPlayingMotion && (Actions.PlayMotionPhoto.$if?.() ?? false)}
          <ActionButton action={{ ...Actions.PlayMotionPhoto, icon: mdiMotionPlayOutline }} />
        {/if}
      {/if}
    {/if}
    <div class="ms-auto flex shrink-0 items-center gap-1">
      {#if OpenInNewAction}
        <ActionButton action={OpenInNewAction} />
      {/if}
    </div>
  </header>

  {#if !asset}
    <!-- Unknown id for this context: error state, never a crash. -->
    <div class="flex flex-col items-center justify-center gap-4 bg-black p-8 text-center">
      <p class="text-lg">Asset not found in this view.</p>
      <div class="dark"><ActionButton action={CloseAction} /></div>
    </div>
  {:else}
    <div class="row-start-2 grid min-h-0 grid-cols-[1fr_auto]">
      <!-- Black canvas. Rotation is a CSS transform on this wrapper only. -->
      <div class="relative min-h-0 min-w-0 overflow-hidden bg-black">
        <div
          data-testid="heirloom-viewer-canvas"
          class="flex h-full w-full items-center justify-center transition-transform duration-200"
          style:transform={rotationStyle || undefined}
          role="img"
          aria-label={asset.originalFileName}
        >
          {#if mediaError}
            <p class="px-8 text-center text-sm text-gray-300">Could not load this asset.</p>
          {:else if isVideo}
            <VideoViewer
              {asset}
              cacheKey={asset.thumbhash}
              projectionType={asset.exifInfo?.projectionType}
              loopVideo={false}
              playOriginalVideo={false}
              extendedControls
              onPreviousAsset={goPrevious}
              onNextAsset={goNext}
              onClose={() => onClose?.()}
              onVideoEnded={goNext}
            />
          {:else if isMotionPhoto && isPlayingMotion}
            <VideoViewer
              {asset}
              assetId={asset.livePhotoVideoId!}
              cacheKey={asset.thumbhash}
              projectionType={asset.exifInfo?.projectionType}
              loopVideo={true}
              playOriginalVideo={false}
              extendedControls
              onPreviousAsset={goPrevious}
              onNextAsset={goNext}
              onClose={() => onClose?.()}
              onVideoEnded={() => (assetViewerManager.isPlayingMotionPhoto = false)}
            />
          {:else if isPanorama}
            <ImagePanoramaViewer {asset} />
          {:else if viewerCursor}
            <PhotoViewer cursor={viewerCursor} {sharedLink} onSwipe={handleSwipe} onError={() => (mediaError = true)} />
          {/if}
        </div>

        <!-- Wrap-around paging controls -->
        {#if assets.length > 1}
          <div class="absolute inset-y-0 start-0 my-auto h-fit">
            <button
              type="button"
              class="m-4 rounded-full bg-black/50 p-3 text-white transition hover:bg-black/80"
              aria-label={$t('previous')}
              onclick={goPrevious}
            >
              <span aria-hidden="true"><Icon icon={mdiChevronLeft} /></span>
            </button>
          </div>
          <div class="absolute inset-y-0 end-0 my-auto h-fit">
            <button
              type="button"
              class="m-4 rounded-full bg-black/50 p-3 text-white transition hover:bg-black/80"
              aria-label={$t('next')}
              onclick={goNext}
            >
              <span aria-hidden="true"><Icon icon={mdiChevronRight} /></span>
            </button>
          </div>
        {/if}
      </div>

      <!-- Inspector / editor column (reused working panels only). -->
      {#if assetViewerManager.isShowEditor}
        <aside
          data-testid="heirloom-viewer-editor"
          aria-label="Editor"
          class="h-full w-90 overflow-y-auto bg-black"
        >
          <EditorPanel {asset} onClose={() => assetViewerManager.closeEditor()} />
        </aside>
      {:else if showInspector}
        <aside
          data-testid="heirloom-viewer-inspector"
          aria-label="Info"
          class="h-full w-90 overflow-y-auto border-s border-white/10 bg-black"
        >
          <DetailPanel {asset} currentAlbum={album} />
        </aside>
      {/if}
    </div>
  {/if}
</section>
