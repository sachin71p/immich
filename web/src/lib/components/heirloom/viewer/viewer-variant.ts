// Heirloom Web V2 — viewer variant logic (WP8, PLAN §13).
//
// Pure, UI-free helpers behind the explicit V2 viewer variant. Lead decision D3
// is binding: the V2 viewer is an opt-in variant composed with
// `asset-viewer-manager` (never a fork), branching on the `/v2` route id so the
// classic viewer stays byte-identical. Composed in `HeirloomViewer.svelte`.
import type { AssetResponseDto } from '@immich/sdk';

/**
 * D3 branching predicate. The shell agent's `[[assetId]]` route wrappers use
 * this to decide between the classic viewer and the V2 variant. Matches any
 * SvelteKit route id inside the `/v2` tree (e.g. `/(user)/v2/library/[[assetId=id]]`).
 */
export const isV2ViewerRoute = (routeId: string | null | undefined): boolean =>
  !!routeId && /(^|\/)v2(\/|$)/.test(routeId);

/** Wrap-around paging index across a viewer context of `count` siblings. */
export const pageViewerIndex = (index: number, delta: number, count: number): number => {
  if (count <= 0) {
    return -1;
  }
  return (((index + delta) % count) + count) % count;
};

export interface ViewerCursor<T> {
  current: T;
  previous: T;
  next: T;
  index: number;
}

/**
 * Resolve the wrapped prev/current/next cursor for `assetId` within the
 * viewer context (`viewerContext` sibling id list in native terms). Returns
 * `undefined` when the asset is not in the context — the component renders
 * its error state instead of crashing.
 */
export const pageViewerCursor = <T extends { id: string }>(
  assets: T[],
  assetId: string,
): ViewerCursor<T> | undefined => {
  if (assets.length === 0) {
    return undefined;
  }
  const index = assets.findIndex((asset) => asset.id === assetId);
  if (index === -1) {
    return undefined;
  }
  return {
    current: assets[index],
    previous: assets[pageViewerIndex(index, -1, assets.length)],
    next: assets[pageViewerIndex(index, 1, assets.length)],
    index,
  };
};

/** Client-side display rotation only (Rotate reconciliation, WP0/WP2). Degrees clockwise. */
export type DisplayRotation = 0 | 90 | 180 | 270;

/** Cycle 0 → 90 → 180 → 270 → 0. Never touches the server: no rotation field exists on `UpdateAssetDto`. */
export const nextDisplayRotation = (rotation: DisplayRotation): DisplayRotation =>
  ((rotation + 90) % 360) as DisplayRotation;

/** CSS transform for the canvas wrapper. Empty string at 0° so no transform is applied. */
export const displayRotationStyle = (rotation: DisplayRotation): string =>
  rotation === 0 ? '' : `rotate(${rotation}deg)`;

/**
 * Native toolbar order (WP1 §5, `MacViewer.swift:73-88`): Favorite, Rotate,
 * Delete, Move to…, Add to Album, [Edit iff `canEdit`], Info, Live Text toggle.
 */
export const HEIRLOOM_VIEWER_TOOLBAR_ORDER = [
  'favorite',
  'rotate',
  'delete',
  'move',
  'addToAlbum',
  'edit',
  'info',
  'liveText',
] as const;

export type HeirloomViewerTool = (typeof HEIRLOOM_VIEWER_TOOLBAR_ORDER)[number];

/**
 * Compose the toolbar model for an asset. `Edit` renders if and only if the
 * caller passes the working browser editor gate (`Edit.$if` from
 * `getAssetActions`); every other slot is always present. The server-backed
 * OCR control and the macOS-only Live Text exception share the `liveText` slot.
 */
export const composeHeirloomToolbar = (canEdit: boolean): HeirloomViewerTool[] =>
  HEIRLOOM_VIEWER_TOOLBAR_ORDER.filter((tool) => tool !== 'edit' || canEdit);

/** VisionKit/Live Text is a documented macOS-only exception (WP1 §8); server-backed OCR is retained. */
export const HEIRLOOM_LIVE_TEXT_NOTE =
  'Live Text is available only in the macOS app. Text in photos stays searchable through server-backed text recognition where available.';

/** Rotation persistence is a documented exception: display-only, never saved. */
export const HEIRLOOM_ROTATE_NOTE = 'Rotation is display-only and is not saved.';

/** Minimal asset shape the variant needs (full `AssetResponseDto` in practice). */
export type HeirloomViewerAsset = AssetResponseDto;
