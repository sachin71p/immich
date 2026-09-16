// Heirloom Web V2 — toolbar zoom coalescer (WP11 P2).
//
// The zoom slider fires `oninput` per tick; each tick used to push a
// `goto(replaceState)` that re-ran the O(n) grid re-layout. This trailing-edge
// debouncer collapses a drag burst into a single apply while the anchor-
// restore effects in `V2SquareTimeline` keep covering jump restoration, so
// behavior is unchanged apart from tick coalescing.

/** Coalescing window for zoom slider ticks. */
export const V2_ZOOM_DEBOUNCE_MS = 100;

export interface ZoomDebouncer {
  /** Offer a slider value; only the latest within the window is applied. */
  push: (value: number) => void;
  /** Apply the pending value immediately (e.g. drag end). No-op when empty. */
  flush: () => void;
  /** Drop the pending value and stop the timer (e.g. unmount). */
  cancel: () => void;
  /** True while a value is waiting for the window to elapse. */
  readonly pending: boolean;
}

export const createZoomDebouncer = (apply: (value: number) => void): ZoomDebouncer => {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let latest: number | undefined;

  const clearTimer = () => {
    if (timer !== undefined) {
      clearTimeout(timer);
      timer = undefined;
    }
  };

  return {
    push: (value: number) => {
      latest = value;
      clearTimer();
      timer = setTimeout(() => {
        timer = undefined;
        const next = latest;
        latest = undefined;
        if (next !== undefined) {
          apply(next);
        }
      }, V2_ZOOM_DEBOUNCE_MS);
    },
    flush: () => {
      clearTimer();
      const next = latest;
      latest = undefined;
      if (next !== undefined) {
        apply(next);
      }
    },
    cancel: () => {
      clearTimer();
      latest = undefined;
    },
    get pending(): boolean {
      return latest !== undefined;
    },
  };
};
