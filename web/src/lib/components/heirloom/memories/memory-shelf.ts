// Heirloom Web V2 — memories shelf composition (WP9 slice 2).
//
// Pure model behind `/v2/memories`. Native (`MacMemoriesView`) is a
// two-section list — a Stories shelf (120×150 covers + caption title) and
// an On This Day shelf (44×44 thumbs + long date) — plus an auto-advance
// player (700×520, black, title, Music toggle default-off, 5 s advance,
// dismiss at end). Data is composed from `memoryManager.memories`
// (`searchMemories`); On This Day rows derive from `OnThisDay`-typed
// memories, matching the web `memoryLaneTitle` treatment.

import { MemoryType } from '@immich/sdk';

export const V2_STORY_ADVANCE_MS = 5000;
export const V2_STORY_COVER_WIDTH = 120;
export const V2_STORY_COVER_HEIGHT = 150;
export const V2_OTD_THUMB_SIZE = 44;

export type V2MemoryInput = {
  id: string;
  type: string;
  memoryAt: string;
  isSaved: boolean;
  assets: { id: string }[];
};

export type V2StoryCover = {
  memoryId: string;
  title: string;
  coverAssetId: string;
  assetCount: number;
  isSaved: boolean;
};

/** Stories shelf: every memory with at least one asset gets a cover. */
export const toV2StoryCovers = <T extends V2MemoryInput>(
  memories: T[],
  titleFor: (memory: T) => string,
): V2StoryCover[] =>
  memories
    .filter((memory) => memory.assets.length > 0)
    .map((memory) => ({
      memoryId: memory.id,
      title: titleFor(memory),
      coverAssetId: memory.assets[0].id,
      assetCount: memory.assets.length,
      isSaved: memory.isSaved,
    }));

export type V2OnThisDayRow = {
  memoryId: string;
  assetId: string;
  memoryAt: string;
};

/** On This Day shelf: flat asset rows from `OnThisDay`-typed memories. */
export const toV2OnThisDayRows = (memories: V2MemoryInput[]): V2OnThisDayRow[] =>
  memories
    .filter((memory) => memory.type === MemoryType.OnThisDay && memory.assets.length > 0)
    .flatMap((memory) =>
      memory.assets.map((asset) => ({ memoryId: memory.id, assetId: asset.id, memoryAt: memory.memoryAt })),
    );

export type V2PlayerStep = { next: number } | { dismiss: true };

/** 5 s auto-advance: step within the story, dismiss past the last asset. */
export const advanceV2StoryPlayer = (index: number, total: number): V2PlayerStep => {
  if (total <= 0 || index < 0 || index >= total - 1) {
    return { dismiss: true };
  }
  return { next: index + 1 };
};
