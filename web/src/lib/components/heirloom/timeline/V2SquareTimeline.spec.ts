// WP11 fix-batch spec (A1/A2/A3/A8): grid list roles, per-tile labels,
// selection state, and roving tabindex.
import { fireEvent, render } from '@testing-library/svelte';
import { getResizeObserverMock } from '$lib/__mocks__/resize-observer.mock';
import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
import { AssetVisibility } from '@immich/sdk';
import V2SquareTimeline from './V2SquareTimeline.svelte';

vi.stubGlobal('ResizeObserver', getResizeObserverMock());

const asset = (id: string, day: number, city: string | null = null): TimelineAsset => ({
  id,
  ownerId: 'owner-1',
  ratio: 1,
  thumbhash: null,
  localDateTime: { year: 2024, month: 6, day, hour: 1, minute: 2, second: 3, millisecond: 0 },
  createdAt: { year: 2024, month: 6, day, hour: 1, minute: 2, second: 3, millisecond: 0 },
  fileCreatedAt: { year: 2024, month: 6, day, hour: 1, minute: 2, second: 3, millisecond: 0 },
  visibility: AssetVisibility.Timeline,
  isFavorite: false,
  isTrashed: false,
  isVideo: false,
  isImage: true,
  stack: null,
  duration: null,
  projectionType: null,
  livePhotoVideoId: null,
  city,
  country: city ? 'Portugal' : null,
  people: null,
});

const assets = [asset('a', 3), asset('b', 12, 'Lisbon'), asset('c', 21)];

const tiles = (container: HTMLElement): HTMLButtonElement[] =>
  [...container.querySelectorAll<HTMLButtonElement>('[data-asset-id]')].sort((x, y) =>
    x.dataset.assetId!.localeCompare(y.dataset.assetId!),
  );

describe('V2SquareTimeline accessibility', () => {
  it('uses list/listitem roles with no grid rowcount (A1)', () => {
    const { container, getByRole } = render(V2SquareTimeline, { assets, group: 'all' });
    expect(getByRole('list', { name: 'Photo library grid' })).toBeTruthy();
    expect(container.querySelector('[role="grid"]')).toBeNull();
    expect(container.querySelector('[aria-rowcount]')).toBeNull();
    expect(container.querySelectorAll('[role="listitem"]').length).toBe(3);
  });

  it('names every tile with its date and position (A2)', () => {
    const { container } = render(V2SquareTimeline, { assets, group: 'all' });
    const labels = tiles(container).map((tile) => tile.getAttribute('aria-label') ?? '');
    expect(labels).toEqual([
      'Photo 1 of 3, 2024-06-03',
      'Photo 2 of 3, 2024-06-12, Lisbon, Portugal',
      'Photo 3 of 3, 2024-06-21',
    ]);
    expect(new Set(labels).size).toBe(3);
  });

  it('exposes selection as aria-selected (A3)', () => {
    const { container } = render(V2SquareTimeline, { assets, group: 'all', selectedIds: new Set(['b']) });
    const byId = new Map(tiles(container).map((tile) => [tile.dataset.assetId, tile]));
    expect(byId.get('b')?.getAttribute('aria-selected')).toBe('true');
    expect(byId.get('a')?.getAttribute('aria-selected')).toBe('false');
    expect(byId.get('c')?.getAttribute('aria-selected')).toBe('false');
    for (const tile of byId.values()) {
      expect(tile.hasAttribute('aria-pressed')).toBe(false);
    }
  });

  it('keeps a single tab stop that follows focus (A8)', async () => {
    const { container } = render(V2SquareTimeline, { assets, group: 'all' });
    const tabbables = () =>
      tiles(container)
        .filter((tile) => tile.tabIndex === 0)
        .map((tile) => tile.dataset.assetId);
    // Untouched grid: exactly one stop, on the first tile.
    expect(tabbables()).toEqual(['a']);
    // Focusing (click) moves the stop to the focused tile.
    const byId = new Map(tiles(container).map((tile) => [tile.dataset.assetId, tile]));
    await fireEvent.click(byId.get('c')!);
    expect(tabbables()).toEqual(['c']);
  });
});
