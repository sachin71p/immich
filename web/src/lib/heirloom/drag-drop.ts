// Heirloom Web V2 — internal asset drag payload + drop-target permission decisions (WP6).
//
// Documented contract for V2 grid drag/drop:
//
// - Internal drags (asset tiles → album sidebar rows / library-space targets) carry a
//   JSON payload under HEIRLOOM_ASSET_MIME. The payload lists the dragged asset ids,
//   their owner ids (for permission decisions without extra fetches), and the source
//   container the drag started from (for same-container noop detection).
// - External file drags (OS → grid) carry the browser-native `Files` type and are NOT
//   claimed by V2 drop targets unless a destination handler is provided; the global
//   UploadCover (`routes/(user)/DragAndDropUploadOverlay.svelte`) remains the default
//   file-drop owner. V2 file drops delegate to the same `fileUploadHandler` it uses.
// - Permission decisions are pure: callers precompute `computeMoveTargets(...)` once
//   per selection and pass the resulting MoveTarget list in. This module only checks
//   membership, so the authorization rules stay owned by `utils/move-targets.ts`.
//
// All persistent effects (add-to-album, move, upload, download) go through the existing
// authorization-aware services; this module never touches the network.
import type { MoveTarget } from '$lib/utils/move-targets';

/** MIME type identifying an internal Heirloom asset drag. */
export const HEIRLOOM_ASSET_MIME = 'application/x-heirloom-assets';

export type HeirloomDragSource =
  | { type: 'personal' }
  | { type: 'space'; id: string }
  | { type: 'library'; id: string }
  | { type: 'album'; id: string }
  | { type: 'other'; id: string };

export type HeirloomDragPayload = {
  version: 1;
  assetIds: string[];
  ownerIds: string[];
  source: HeirloomDragSource;
};

/** Drop destinations V2 understands. `library.hasUploadPath` mirrors the move rule. */
export type HeirloomDropTarget =
  | { kind: 'album'; id: string; name: string }
  | { kind: 'space'; id: string; name: string }
  | { kind: 'library'; id: string; name: string; hasUploadPath: boolean }
  | { kind: 'personal' };

export type DropDecisionReason =
  | 'album-add'
  | 'move-allowed'
  | 'empty-selection'
  | 'same-container-noop'
  | 'library-missing-upload-path'
  | 'target-not-permitted';

export type DropDecision = { allowed: boolean; reason: DropDecisionReason };

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isValidSource = (value: unknown): value is HeirloomDragSource => {
  if (!isRecord(value) || typeof value.type !== 'string') {
    return false;
  }
  switch (value.type) {
    case 'personal': {
      return true;
    }
    case 'space':
    case 'library':
    case 'album':
    case 'other': {
      return typeof value.id === 'string' && value.id.length > 0;
    }
    default: {
      return false;
    }
  }
};

export const encodeHeirloomDragPayload = (payload: HeirloomDragPayload): string =>
  JSON.stringify({ version: 1, assetIds: payload.assetIds, ownerIds: payload.ownerIds, source: payload.source });

/**
 * Parse a raw `getData(HEIRLOOM_ASSET_MIME)` string. Returns null for missing,
 * malformed, version-mismatched, or empty payloads — callers treat null as
 * "not an internal Heirloom drag".
 */
export const decodeHeirloomDragPayload = (raw: string | null | undefined): HeirloomDragPayload | null => {
  if (!raw) {
    return null;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw) as unknown;
  } catch {
    return null;
  }
  if (!isRecord(parsed) || parsed.version !== 1) {
    return null;
  }
  if (!Array.isArray(parsed.assetIds) || parsed.assetIds.some((id) => typeof id !== 'string')) {
    return null;
  }
  if (!Array.isArray(parsed.ownerIds) || parsed.ownerIds.some((id) => typeof id !== 'string')) {
    return null;
  }
  if (parsed.assetIds.length === 0 || !isValidSource(parsed.source)) {
    return null;
  }
  return { version: 1, assetIds: parsed.assetIds, ownerIds: parsed.ownerIds, source: parsed.source };
};

/** True when the drag carries an internal Heirloom asset payload. */
export const hasHeirloomPayload = (types: readonly string[]): boolean => types.includes(HEIRLOOM_ASSET_MIME);

/** True when the drag carries OS files. Independent of internal payload detection. */
export const hasFilePayload = (types: readonly string[]): boolean => types.includes('Files');

const sameContainer = (source: HeirloomDragSource, target: HeirloomDropTarget): boolean => {
  switch (target.kind) {
    case 'personal': {
      return source.type === 'personal';
    }
    case 'space':
    case 'library':
    case 'album': {
      return source.type === target.kind && 'id' in source && source.id === target.id;
    }
  }
};

const moveTargetCovers = (allowedTargets: readonly MoveTarget[], target: HeirloomDropTarget): boolean => {
  switch (target.kind) {
    case 'personal': {
      return allowedTargets.some((candidate) => candidate.type === 'personal');
    }
    case 'space': {
      return allowedTargets.some((candidate) => candidate.type === 'space' && candidate.id === target.id);
    }
    case 'library': {
      return allowedTargets.some((candidate) => candidate.type === 'library' && candidate.id === target.id);
    }
    case 'album': {
      return false;
    }
  }
};

/**
 * Decide whether an internal asset drop is permitted on a target.
 *
 * - Album targets always accept (add-to-album; the service enforces album
 *   membership server-side and reports per-asset results).
 * - Personal/space/library targets accept only when the target is inside the
 *   precomputed `computeMoveTargets` allow-list. Drops back onto the source
 *   container are rejected as noops so the UI can show a neutral state instead
 *   of running a pointless move.
 * - Libraries without an upload path reject visibly (same rule as the move sheet).
 */
export const decideAssetDrop = (
  payload: HeirloomDragPayload | null,
  target: HeirloomDropTarget,
  allowedMoveTargets: readonly MoveTarget[],
): DropDecision => {
  if (!payload || payload.assetIds.length === 0) {
    return { allowed: false, reason: 'empty-selection' };
  }
  if (target.kind === 'album') {
    if (sameContainer(payload.source, target)) {
      return { allowed: false, reason: 'same-container-noop' };
    }
    return { allowed: true, reason: 'album-add' };
  }
  if (target.kind === 'library' && !target.hasUploadPath) {
    return { allowed: false, reason: 'library-missing-upload-path' };
  }
  if (sameContainer(payload.source, target)) {
    return { allowed: false, reason: 'same-container-noop' };
  }
  if (!moveTargetCovers(allowedMoveTargets, target)) {
    return { allowed: false, reason: 'target-not-permitted' };
  }
  return { allowed: true, reason: 'move-allowed' };
};
