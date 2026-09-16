// Heirloom Web V2 — management-sheet logic (WP7).
//
// Pure, UI-free helpers behind the V2 dialog components in this directory.
// PLAN §13 binding: V2 composes existing services/managers and never forks
// them, so every decision here is presentation-shaped (geometry, validation,
// role-gating, summaries) while the SDK calls live in the components.
//
// Geometry/contract source: WP1-MEASUREMENTS §6 (all sheets are
// `VStack(leading, 12)`, headline title, inline red-caption error,
// `Spacer()` + Cancel/primary button order, primary is the default action).

import { SharedSpaceRole, Status } from '@immich/sdk';

/** Native sheet widths in px (WP1 §6). Components bind these, never literals. */
export const SHEET_WIDTHS = {
  newAlbum: 300,
  addToAlbum: 300,
  move: 320,
  newSpace: 320,
  manageSpace: 360,
  importChooser: 360,
} as const;

export type SheetKind = keyof typeof SHEET_WIDTHS;

/** Minimum list height in px for the Add-to-Album and Move sheets (WP1 §6). */
export const SHEET_LIST_MIN_HEIGHT = 160;

/** Maximum file names shown before the "…and K more" row (WP1 §6). */
export const IMPORT_CHOOSER_PREVIEW_COUNT = 5;

/**
 * WP1-verbatim confirmation copy shown before moving into an external
 * library target.
 */
export const MOVE_LIBRARY_CONFIRM_BODY =
  'Files leave the import path once moved. This cannot be undone automatically.';

/**
 * G2 (WP2 §5): `AssetMediaCreateDto` carries `spaceId` ("Shared space upload
 * target") but NO `libraryId`, so direct upload-into-library is unsupported
 * server-side. The import chooser offers Personal + spaces as direct
 * destinations; external-library destinations are served upload-then-move
 * (upload to Personal, then the Move sheet). Do not invent a `libraryId`
 * upload parameter.
 */
export const LIBRARY_DESTINATION_VIA_MOVE = true;

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/** Validation failure codes for sheet name fields. Components map codes to `$t`. */
export type SheetNameError = 'required';

/**
 * Blank (empty or whitespace-only) names invalidate the primary action.
 * Components keep the primary disabled while this returns non-null and show
 * the mapped message as the inline red-caption error once the user has
 * attempted to submit (pristine fields show no error).
 */
export const validateSheetName = (name: string): SheetNameError | null =>
  name.trim().length === 0 ? 'required' : null;

export const isSheetNameValid = (name: string): boolean => validateSheetName(name) === null;

// ---------------------------------------------------------------------------
// Role gating (shared spaces)
// ---------------------------------------------------------------------------

/**
 * Manage-sheet capability matrix. Mirrors the classic space page
 * (`shared-libraries/[spaceId]/+page.svelte`): owner-only Delete, Leave for
 * non-owners, unrestricted edit/add for members. Server role model has only
 * Owner/Contributor (`SharedSpaceRole`); there is no role-update endpoint —
 * roles render read-only and change only via ownership transfer, which WP1 §6
 * does not put in this sheet.
 */
export interface SpaceSheetPermissions {
  /** Rename + description editing (Save). */
  canEditDetails: boolean;
  /** Add-member field. Any member may invite (matches classic members modal). */
  canAddMembers: boolean;
  /** Delete Library destructive action. Owner only. */
  canDelete: boolean;
  /** Leave action. Contributors only (owners must transfer/delete instead). */
  canLeave: boolean;
}

export const describeSpacePermissions = (role: SharedSpaceRole | undefined): SpaceSheetPermissions => {
  const isMember = role === SharedSpaceRole.Owner || role === SharedSpaceRole.Contributor;
  const isOwner = role === SharedSpaceRole.Owner;
  return {
    canEditDetails: isMember,
    canAddMembers: isMember,
    canDelete: isOwner,
    canLeave: role === SharedSpaceRole.Contributor,
  };
};

/**
 * Per-row Remove decision for the members list. Self-removal is never offered
 * as Remove (WP1 §6: "link-style Remove except self") — leaving is the
 * contributor Leave flow, and owners cannot self-remove at all. Returns a
 * reason code so the component can explain a disabled/absent control; no
 * inert buttons (PLAN §2).
 */
export type RemoveMemberDecision = { allowed: true } | { allowed: false; reason: 'self' | 'forbidden' };

export const decideRemoveMember = (
  role: SharedSpaceRole | undefined,
  memberUserId: string,
  myUserId: string,
): RemoveMemberDecision => {
  if (memberUserId === myUserId) {
    return { allowed: false, reason: 'self' };
  }
  const { canAddMembers } = describeSpacePermissions(role);
  return canAddMembers ? { allowed: true } : { allowed: false, reason: 'forbidden' };
};

// ---------------------------------------------------------------------------
// Move results
// ---------------------------------------------------------------------------

export interface MoveSummary {
  moved: number;
  unchanged: number;
  failed: number;
}

/** Tally per-asset move statuses (mirrors `MoveToLibraryModal` counting). */
export const summarizeMoveResults = (statuses: Status[]): MoveSummary => ({
  moved: statuses.filter((status) => status === Status.Moved).length,
  unchanged: statuses.filter((status) => status === Status.Noop).length,
  failed: statuses.filter((status) => status === Status.Error).length,
});

/** WP1 toast contract: `Moved M items (K already there).` / `Moved M; K failed (reasons).` */
export const formatMoveToast = (summary: MoveSummary): string => {
  const { moved, unchanged, failed } = summary;
  if (failed > 0) {
    return `Moved ${moved}; ${failed} failed (${unchanged} already there).`;
  }
  return `Moved ${moved} items (${unchanged} already there).`;
};

// ---------------------------------------------------------------------------
// Import chooser
// ---------------------------------------------------------------------------

export interface ImportPreview {
  shown: string[];
  extra: number;
}

/** First N names plus the overflow count (WP1 §6: "first 5 names + …and K more"). */
export const summarizeImportFiles = (fileNames: string[]): ImportPreview => ({
  shown: fileNames.slice(0, IMPORT_CHOOSER_PREVIEW_COUNT),
  extra: Math.max(0, fileNames.length - IMPORT_CHOOSER_PREVIEW_COUNT),
});

export const formatImportOverflow = (extra: number): string => `…and ${extra} more`;

// ---------------------------------------------------------------------------
// Row sorting
// ---------------------------------------------------------------------------

/** Move-sheet rows render sorted by title (WP1 §6). Pure; components map targets to titled rows first. */
export const sortRowsByTitle = <T extends { title: string }>(rows: T[]): T[] =>
  [...rows].sort((a, b) => a.title.localeCompare(b.title));

// ---------------------------------------------------------------------------
// Focus restoration
// ---------------------------------------------------------------------------

/**
 * Capture the currently focused element for later restoration. The V2 sheet
 * shell calls this on mount and invokes the returned closure on destroy, so
 * dialogs restore focus on close (PLAN §14/WP7 acceptance). Guards make it
 * safe when the element left the document or nothing was focused.
 */
export const captureFocusRestore = (doc: Document = globalThis.document): (() => void) => {
  const active = doc.activeElement;
  const restorable =
    active instanceof HTMLElement && doc.contains(active) ? (active as HTMLElement) : null;
  return () => {
    if (restorable && doc.contains(restorable) && typeof restorable.focus === 'function') {
      restorable.focus();
    }
  };
};
