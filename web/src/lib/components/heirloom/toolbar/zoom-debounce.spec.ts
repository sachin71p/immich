// WP11 fix-batch spec (P2): zoom slider coalescing.
import { describe, expect, it, vi } from 'vitest';
import { createZoomDebouncer, V2_ZOOM_DEBOUNCE_MS } from './zoom-debounce';

describe('createZoomDebouncer', () => {
  it('collapses a drag burst into one trailing apply of the latest value', () => {
    vi.useFakeTimers();
    try {
      const apply = vi.fn();
      const debouncer = createZoomDebouncer(apply);
      debouncer.push(130);
      debouncer.push(150);
      debouncer.push(200);
      expect(apply).not.toHaveBeenCalled();
      vi.advanceTimersByTime(V2_ZOOM_DEBOUNCE_MS);
      expect(apply).toHaveBeenCalledTimes(1);
      expect(apply).toHaveBeenCalledWith(200);
    } finally {
      vi.useRealTimers();
    }
  });

  it('flush applies the pending value immediately (drag end)', () => {
    vi.useFakeTimers();
    try {
      const apply = vi.fn();
      const debouncer = createZoomDebouncer(apply);
      debouncer.push(180);
      debouncer.flush();
      expect(apply).toHaveBeenCalledTimes(1);
      expect(apply).toHaveBeenCalledWith(180);
      // The window is consumed — no second apply when it elapses.
      vi.advanceTimersByTime(V2_ZOOM_DEBOUNCE_MS * 2);
      expect(apply).toHaveBeenCalledTimes(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('flush with nothing pending is a no-op', () => {
    const apply = vi.fn();
    createZoomDebouncer(apply).flush();
    expect(apply).not.toHaveBeenCalled();
  });

  it('cancel drops the pending value', () => {
    vi.useFakeTimers();
    try {
      const apply = vi.fn();
      const debouncer = createZoomDebouncer(apply);
      debouncer.push(250);
      expect(debouncer.pending).toBe(true);
      debouncer.cancel();
      expect(debouncer.pending).toBe(false);
      vi.advanceTimersByTime(V2_ZOOM_DEBOUNCE_MS * 2);
      expect(apply).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });
});
