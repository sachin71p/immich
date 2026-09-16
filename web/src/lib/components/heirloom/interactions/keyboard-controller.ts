// Heirloom Web V2 — type-to-date buffer + keyboard map (WP6).
//
// Native behavior (WP1 §4): typing digits/`-` jumps to the first matching row;
// the buffer resets after 1s of inactivity.
import type { TimelineDateTime } from '$lib/utils/timeline-util';

export const TYPE_AHEAD_TIMEOUT_MS = 1000;

export type TypeAheadKey = { key: string };

/** True for keys that feed the date buffer: digits and `-` (native type-to-date charset). */
export const isTypeAheadKey = (key: string): boolean => key.length === 1 && /[0-9-]/.test(key);

/** Accumulates type-to-date characters; stale unless `now - lastAt <= TYPE_AHEAD_TIMEOUT_MS`. */
export class TypeAheadBuffer {
  private buffer = '';
  private lastAt = 0;

  push(key: string, now: number): string {
    if (now - this.lastAt > TYPE_AHEAD_TIMEOUT_MS) {
      this.buffer = '';
    }
    this.buffer += key;
    this.lastAt = now;
    return this.buffer;
  }

  value(now: number): string {
    if (now - this.lastAt > TYPE_AHEAD_TIMEOUT_MS) {
      return '';
    }
    return this.buffer;
  }

  reset(): void {
    this.buffer = '';
    this.lastAt = 0;
  }
}

const pad2 = (value: number): string => String(value).padStart(2, '0');

/**
 * Find the first asset id (grid order) whose local date starts with the typed
 * prefix, e.g. `2024` → year, `2024-05` → month, `2024-05-03` → day. Returns
 * null when nothing matches.
 */
export const findDateMatch = (
  assets: { id: string; localDateTime: Pick<TimelineDateTime, 'year' | 'month' | 'day'> }[],
  prefix: string,
): string | null => {
  if (!prefix) {
    return null;
  }
  for (const asset of assets) {
    const { year, month, day } = asset.localDateTime;
    const iso = `${year}-${pad2(month)}-${pad2(day)}`;
    if (iso.startsWith(prefix)) {
      return asset.id;
    }
  }
  return null;
};

export type GridKeyEvent = {
  key: string;
  metaKey?: boolean;
  ctrlKey?: boolean;
  shiftKey?: boolean;
};

export type GridKeyAction =
  | { type: 'select-all' }
  | { type: 'clear' }
  | { type: 'open' }
  | { type: 'preview' }
  | { type: 'ignore' };

const isModifier = (event: GridKeyEvent): boolean => !!(event.metaKey || event.ctrlKey);

/**
 * Map a key event to its grid-level action. Arrow keys and toggle/extend clicks
 * are handled by the caller through HeirloomSelectionModel; this covers the
 * command layer: Cmd/Ctrl+A (select all), Escape (clear/close), Return (open
 * viewer), Space (preview equivalent — caller must preventDefault to hold
 * scroll). Everything else is `ignore` (type-ahead keys are routed to the
 * TypeAheadBuffer by the caller via isTypeAheadKey).
 */
export const describeGridKey = (event: GridKeyEvent): GridKeyAction => {
  if (event.key === 'Escape') {
    return { type: 'clear' };
  }
  if (isModifier(event) && (event.key === 'a' || event.key === 'A')) {
    return { type: 'select-all' };
  }
  if (!isModifier(event) && !event.shiftKey) {
    if (event.key === 'Enter') {
      return { type: 'open' };
    }
    if (event.key === ' ') {
      return { type: 'preview' };
    }
  }
  return { type: 'ignore' };
};
