// Heirloom Web V2 — grid selection model (WP6).
//
// Mirrors native `MacSelection` semantics per WP1 §4: single select, toggle
// (Cmd/Ctrl-click), range extension from an anchor, select-all, clear. Arrow
// movement is expressed as flat-index deltas so the component owning the grid
// geometry (columns for up/down) translates keys without this model knowing
// about layout. Order is the flattened grid order (newest-first).

/**
 * WP11 P1: O(1)-size membership key for the flattened grid order. Grid lists
 * only ever change by add/remove (never in-place reorder), so length + first
 * + last id detects every membership change without the ~100 KB joined
 * string the caller used to build per interaction. A pure interior reorder
 * with identical ends would not trip it — accepted: `setOrder` only prunes
 * ids that left the grid, and membership is unchanged in that case.
 */
export const orderChecksum = (ids: string[]): string =>
  `${ids.length}:${ids[0] ?? ''}:${ids[ids.length - 1] ?? ''}`;

export class HeirloomSelectionModel {
  private order: string[] = [];
  private selected = new Set<string>();
  private anchorIndex: number | null = null;
  private focusedIndex: number | null = null;

  /** Replace the grid order; prunes selected ids that no longer exist. Returns pruned ids. */
  setOrder(ids: string[]): string[] {
    this.order = [...ids];
    const live = new Set(ids);
    const pruned: string[] = [];
    for (const id of this.selected) {
      if (live.has(id)) {
        continue;
      }
      this.selected.delete(id);
      pruned.push(id);
    }
    if (this.anchorIndex !== null && (this.anchorIndex < 0 || this.anchorIndex >= this.order.length)) {
      this.anchorIndex = null;
    }
    if (this.focusedIndex !== null && (this.focusedIndex < 0 || this.focusedIndex >= this.order.length)) {
      this.focusedIndex = null;
    }
    return pruned;
  }

  get count(): number {
    return this.selected.size;
  }

  get anchorId(): string | null {
    return this.anchorIndex === null ? null : (this.order[this.anchorIndex] ?? null);
  }

  get focusedId(): string | null {
    return this.focusedIndex === null ? null : (this.order[this.focusedIndex] ?? null);
  }

  isSelected(id: string): boolean {
    return this.selected.has(id);
  }

  /** Selected ids in grid order. */
  selectedIds(): string[] {
    return this.order.filter((id) => this.selected.has(id));
  }

  selectedSet(): Set<string> {
    return new Set(this.selected);
  }

  private indexOf(id: string): number {
    return this.order.indexOf(id);
  }

  /** Plain click: single selection, anchor + focus move to the clicked tile. */
  click(id: string): void {
    const index = this.indexOf(id);
    if (index === -1) {
      return;
    }
    this.selected = new Set([id]);
    this.anchorIndex = index;
    this.focusedIndex = index;
  }

  /** Cmd/Ctrl-click: toggle one tile, anchor + focus move to it. */
  toggle(id: string): void {
    const index = this.indexOf(id);
    if (index === -1) {
      return;
    }
    if (this.selected.has(id)) {
      this.selected.delete(id);
    } else {
      this.selected.add(id);
    }
    this.anchorIndex = index;
    this.focusedIndex = index;
  }

  /**
   * Shift-click: extend the range from the anchor (or focus when no anchor yet)
   * to the clicked tile, replacing the current selection.
   */
  extend(id: string): void {
    const index = this.indexOf(id);
    if (index === -1) {
      return;
    }
    const from = this.anchorIndex ?? this.focusedIndex ?? index;
    const [start, end] = from <= index ? [from, index] : [index, from];
    this.selected = new Set(this.order.slice(start, end + 1));
    this.focusedIndex = index;
  }

  selectAll(): void {
    this.selected = new Set(this.order);
    if (this.order.length > 0) {
      this.anchorIndex = 0;
      this.focusedIndex = this.order.length - 1;
    }
  }

  clear(): void {
    this.selected.clear();
    this.anchorIndex = null;
    this.focusedIndex = null;
  }

  /**
   * Arrow-key focus move by flat delta. Without extend, the focused tile becomes
   * the single selection (native arrow behavior). With shift, the range extends
   * from the anchor. Returns the focused id, or null when the grid is empty.
   */
  moveFocusBy(delta: number, options: { extend?: boolean } = {}): string | null {
    if (this.order.length === 0) {
      return null;
    }
    const base = this.focusedIndex ?? this.anchorIndex ?? (delta < 0 ? this.order.length - 1 : 0);
    const next = Math.min(this.order.length - 1, Math.max(0, base + delta));
    const id = this.order[next];
    if (options.extend) {
      const from = this.anchorIndex ?? base;
      const [start, end] = from <= next ? [from, next] : [next, from];
      this.selected = new Set(this.order.slice(start, end + 1));
    } else {
      this.selected = new Set([id]);
      this.anchorIndex = next;
    }
    this.focusedIndex = next;
    return id;
  }

  focus(id: string): void {
    const index = this.indexOf(id);
    if (index !== -1) {
      this.focusedIndex = index;
    }
  }
}
