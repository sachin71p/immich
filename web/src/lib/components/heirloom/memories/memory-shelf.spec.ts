import { MemoryType } from '@immich/sdk';
import { describe, expect, it } from 'vitest';
import {
  advanceV2StoryPlayer,
  toV2OnThisDayRows,
  toV2StoryCovers,
  V2_STORY_ADVANCE_MS,
  type V2MemoryInput,
} from './memory-shelf';

const memory = (overrides: Partial<V2MemoryInput> = {}): V2MemoryInput => ({
  id: 'm1',
  type: MemoryType.OnThisDay,
  memoryAt: '2020-09-16T00:00:00Z',
  isSaved: false,
  assets: [{ id: 'a1' }, { id: 'a2' }],
  ...overrides,
});

describe('toV2StoryCovers', () => {
  it('covers every memory that has assets', () => {
    const covers = toV2StoryCovers([memory({ id: 'm1' }), memory({ id: 'm2', assets: [] })], (m) => `title-${m.id}`);
    expect(covers).toEqual([
      { memoryId: 'm1', title: 'title-m1', coverAssetId: 'a1', assetCount: 2, isSaved: false },
    ]);
  });
});

describe('toV2OnThisDayRows', () => {
  it('flattens assets of OnThisDay memories only', () => {
    const rows = toV2OnThisDayRows([
      memory({ id: 'm1', assets: [{ id: 'a1' }, { id: 'a2' }] }),
      memory({ id: 'm2', type: 'other', assets: [{ id: 'b1' }] }),
    ]);
    expect(rows).toEqual([
      { memoryId: 'm1', assetId: 'a1', memoryAt: '2020-09-16T00:00:00Z' },
      { memoryId: 'm1', assetId: 'a2', memoryAt: '2020-09-16T00:00:00Z' },
    ]);
  });

  it('is empty when nothing is OnThisDay', () => {
    expect(toV2OnThisDayRows([memory({ type: 'other' })])).toEqual([]);
  });
});

describe('advanceV2StoryPlayer', () => {
  it('advances every 5 s within the story', () => {
    expect(V2_STORY_ADVANCE_MS).toBe(5000);
    expect(advanceV2StoryPlayer(0, 3)).toEqual({ next: 1 });
    expect(advanceV2StoryPlayer(1, 3)).toEqual({ next: 2 });
  });

  it('dismisses past the last asset', () => {
    expect(advanceV2StoryPlayer(2, 3)).toEqual({ dismiss: true });
  });

  it('dismisses on degenerate input', () => {
    expect(advanceV2StoryPlayer(0, 0)).toEqual({ dismiss: true });
    expect(advanceV2StoryPlayer(-1, 3)).toEqual({ dismiss: true });
  });
});
