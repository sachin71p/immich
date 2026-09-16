/**
 * Deterministic V2 test fixtures (WP3 harness).
 * No product imports: plain data + a seeded PRNG so every consumer
 * (vitest, Playwright, screenshots) builds the identical corpus.
 */

export const FIXTURE_NOW_ISO = '2026-01-15T12:00:00.000Z';
export const FIXTURE_SEED = 20260115;

export type FixtureMediaType = 'photo' | 'video' | 'screenshot';
export type FixtureVisibility = 'visible' | 'hidden' | 'archived' | 'locked' | 'trashed';
export type FixtureSourceKind = 'personal' | 'space' | 'library';

export interface FixtureAsset {
  id: string;
  checksum: string;
  fileName: string;
  mediaType: FixtureMediaType;
  visibility: FixtureVisibility;
  favorite: boolean;
  capturedAt: string;
  durationMs: number | null;
  width: number;
  height: number;
  sourceKind: FixtureSourceKind;
  sourceId: string | null;
  personIds: string[];
  gps: { lat: number; lon: number } | null;
}

/**
 * xorshift32 — deterministic across runs for a fixed seed.
 * Uses only shifts/xor (no Math.imul) to stay lint-clean under tscompat.
 */
export function seededRandom(seed: number): () => number {
  let a = (seed || 1) >>> 0;
  return () => {
    a ^= a << 13;
    a >>>= 0;
    a ^= a >>> 17;
    a ^= a << 5;
    a >>>= 0;
    return a / 4294967296;
  };
}

export function fixtureId(n: number): string {
  return `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
}

const DAY_MS = 86_400_000;

export interface BatchOptions {
  count: number;
  seed?: number;
  sourceKind?: FixtureSourceKind;
  sourceId?: string | null;
  /** Days before FIXTURE_NOW_ISO the newest asset is captured. */
  newestDaysAgo?: number;
}

/** Build `count` assets, newest-first, with stable ids/timestamps for the seed. */
export function makeAssetBatch({
  count,
  seed = 1,
  sourceKind = 'personal',
  sourceId = null,
  newestDaysAgo = 0,
}: BatchOptions): FixtureAsset[] {
  const rand = seededRandom(seed);
  const now = Date.parse(FIXTURE_NOW_ISO);
  const assets: FixtureAsset[] = [];
  for (let i = 0; i < count; i += 1) {
    const n = seed * 100_000 + i;
    const mediaType: FixtureMediaType = rand() < 0.7 ? 'photo' : rand() < 0.6 ? 'video' : 'screenshot';
    const capturedAt = new Date(now - (newestDaysAgo * DAY_MS + i * DAY_MS)).toISOString();
    assets.push({
      id: fixtureId(n),
      checksum: `fixture-checksum-${n}`,
      fileName: `fixture-${mediaType}-${i}.${mediaType === 'video' ? 'mp4' : mediaType === 'screenshot' ? 'png' : 'jpg'}`,
      mediaType,
      visibility: 'visible',
      favorite: i % 7 === 0,
      capturedAt,
      durationMs: mediaType === 'video' ? 5_000 + Math.floor(rand() * 60_000) : null,
      width: 4000,
      height: 3000,
      sourceKind,
      sourceId,
      personIds: i % 5 === 0 ? [fixtureId(900_000 + (i % 3))] : [],
      gps: i % 4 === 0 ? { lat: 37.7749 + rand() * 0.1, lon: -122.4194 + rand() * 0.1 } : null,
    });
  }
  return assets;
}

/** Minimal per-visibility corpus: one asset per visibility state. */
export function makeVisibilityCorpus(seed = 2): FixtureAsset[] {
  const visibilities: FixtureVisibility[] = ['visible', 'hidden', 'archived', 'locked', 'trashed'];
  return visibilities.map((visibility, i) => ({
    ...makeAssetBatch({ count: 1, seed: seed + i })[0],
    visibility,
    favorite: visibility === 'visible' && i === 0,
  }));
}
