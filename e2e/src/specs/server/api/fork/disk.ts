// Fork disk oracle (shared-libraries, T0). See TESTING.md §4.
//
// This is an INDEPENDENT re-implementation of DECISIONS.md §7 — it must not
// import server code, so a server regression shows up as a mismatch here.
// Scope is deliberately the fork's invariant (which container tree a file
// lives in), not upstream's template rendering: with the template ON the
// exact date-prefix rendering is upstream's business, so the original is
// located with a filename search under the container prefix; with the
// template OFF upstream nested paths are deterministic
// (upload/<key>/xx/yy/<file>) and asserted exactly.
//
// Container path <-> host mapping: the fork compose override bind-mounts the
// server media root to e2e/.fork-data, so a container path under /fork-data
// maps 1:1; /test-assets import paths map to e2e/test-assets on the host.

import { existsSync, readdirSync, statSync } from 'node:fs';
import { basename, join } from 'node:path';
import { expect } from 'vitest';

const e2eDir = join(import.meta.dirname, '..', '..', '..', '..', '..');
export const forkDataDir = join(e2eDir, '.fork-data');
export const hostTestAssetDir = join(e2eDir, 'test-assets');

/** Container media root on the fork stack (IMMICH_MEDIA_LOCATION in docker-compose.fork.yml). */
export const containerMediaRoot = '/fork-data';
/** Container mount of the upstream test-assets tree (read-write on the fork stack). */
export const containerTestAssetRoot = '/test-assets';

/** Storage key K(asset): `shared/<spaceId>` for space assets, else ownerId. */
export const storageKey = (asset: { ownerId: string; spaceId?: string | null }): string =>
  asset.spaceId ? `shared/${asset.spaceId}` : asset.ownerId;

const nested = (base: string, key: string, filename: string): string =>
  join(base, key, filename.slice(0, 2), filename.slice(2, 4), filename);

/**
 * Exact template-OFF original location (host path).
 *
 * `storedFilename` is the on-disk basename — `basename()` of the
 * API-reported `originalPath` — which the server derives from the upload
 * uuid (`<uuid>.<ext>`), NOT the client `originalFileName`. Passing the
 * client filename computes nesting the server never wrote.
 */
export const expectedUploadPath = (key: string, storedFilename: string): string =>
  nested(join(forkDataDir, 'upload'), key, storedFilename);

/** Host prefix of a personal library tree (template ON): library/<label>. */
export const personalLibraryPrefix = (storageLabelOrId: string): string =>
  join(forkDataDir, 'library', storageLabelOrId);

/** Host prefix of the shared space tree (template ON): library/shared. */
export const sharedLibraryPrefix = (): string => join(forkDataDir, 'library', 'shared');

export const findUnder = (dir: string, filename: string): string[] => {
  const found: string[] = [];
  if (!existsSync(dir)) {
    return found;
  }
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      found.push(...findUnder(path, filename));
    } else if (entry === filename) {
      found.push(path);
    }
  }
  return found;
};

/** Recursive basename-prefix search (nesting-agnostic; the server nests by filename hash). */
export const findByPrefix = (dir: string, prefix: string): string[] => {
  const found: string[] = [];
  if (!existsSync(dir)) {
    return found;
  }
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      found.push(...findByPrefix(path, prefix));
    } else if (entry.startsWith(prefix)) {
      found.push(path);
    }
  }
  return found;
};

export interface DiskAsset {
  id: string;
  ownerId: string;
  spaceId?: string | null;
  libraryId?: string | null;
  originalFileName: string;
  originalPath: string;
  sidecarPath?: string | null;
}

export interface ExpectFilesAtOptions {
  template: 'on' | 'off';
  /** Container prefix to search for template-ON originals (personal or shared tree). */
  hostPrefix?: string;
  /** Prefixes the original must have vanished from (proves old paths are gone). */
  absentFrom?: string[];
}

/** Assert original, sidecar, and derived files are at their expected host paths. */
export const expectFilesAt = (asset: DiskAsset, opts: ExpectFilesAtOptions): void => {
  if (opts.template === 'off' && !asset.libraryId) {
    const exact = expectedUploadPath(storageKey(asset), basename(asset.originalPath));
    expect(existsSync(exact), `original missing at ${exact} (container: ${asset.originalPath})`).toBe(true);
  } else if (opts.hostPrefix && !asset.libraryId) {
    const found = findUnder(opts.hostPrefix, asset.originalFileName);
    expect(found.length, `original ${asset.originalFileName} missing under ${opts.hostPrefix}`).toBeGreaterThan(0);
  }
  if (asset.sidecarPath) {
    const host = toHostPath(asset.sidecarPath);
    expect(host, `sidecar container path not mappable: ${asset.sidecarPath}`).not.toBe(null);
    expect(existsSync(host as string), `sidecar missing at ${host}`).toBe(true);
  }
  for (const prefix of opts.absentFrom ?? []) {
    const stale = findUnder(prefix, asset.originalFileName);
    expect(stale, `stale file still present: ${stale.join(', ')}`).toEqual([]);
  }
  // Thumbnails are `<id>_<fileType>.<format>` under thumbs/<key> and the
  // R17-01 caller settles thumbnailGeneration first, so every asset must have
  // at least one. Encoded video (`<id>.mp4`) only exists for transcoded
  // videos, so it is asserted by placement (any copy must live under the
  // current key) rather than by existence.
  const key = storageKey(asset);
  const thumbs = findByPrefix(join(forkDataDir, 'thumbs', key), `${asset.id}_`);
  expect(thumbs.length, `no thumbnails for asset ${asset.id} under thumbs/${key}`).toBeGreaterThan(0);
  const encodedDir = join(forkDataDir, 'encoded-video', key);
  for (const copy of findUnder(join(forkDataDir, 'encoded-video'), `${asset.id}.mp4`)) {
    expect(copy.startsWith(`${encodedDir}/`), `encoded video misplaced: ${copy} (expected under ${encodedDir})`).toBe(true);
  }
};

/** Map a container path reported by the API to its host mirror path. */
export const toHostPath = (containerPath: string): string | null => {
  if (containerPath.startsWith(`${containerMediaRoot}/`)) {
    return join(forkDataDir, containerPath.slice(containerMediaRoot.length + 1));
  }
  if (containerPath.startsWith(`${containerTestAssetRoot}/`)) {
    return join(hostTestAssetDir, containerPath.slice(containerTestAssetRoot.length + 1));
  }
  return null;
};

export interface DbFileEntry {
  id: string;
  originalPath: string;
  sidecarPath?: string | null;
}

const walkFiles = (dir: string): string[] => {
  const out: string[] = [];
  if (!existsSync(dir)) {
    return out;
  }
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    out.push(...(statSync(path).isDirectory() ? walkFiles(path) : [path]));
  }
  return out;
};

/**
 * Walk the host mirror and the DB (via the caller's listDbFiles, usually
 * world assets resolved through getAssetInfo) and report orphans (files on
 * disk nothing references) and missing files (DB rows with no file).
 */
export const auditDisk = async (listDbFiles: () => Promise<DbFileEntry[]>): Promise<{ orphans: string[]; missing: string[] }> => {
  const entries = await listDbFiles();
  const ids = new Set(entries.map((e) => e.id));
  const referenced = new Set<string>();
  const missing: string[] = [];
  const collectPath = (containerPath: string | null | undefined) => {
    if (!containerPath) {
      return;
    }
    const host = toHostPath(containerPath);
    if (!host) {
      return;
    }
    referenced.add(host);
    if (!existsSync(host)) {
      missing.push(host);
    }
  };
  for (const entry of entries) {
    collectPath(entry.originalPath);
    collectPath(entry.sidecarPath);
  }
  const orphans: string[] = [];
  // Derived filenames embed the asset id (<id>_<type>.<ext>); sidecars
  // sit next to their original.
  const isOrphan = (file: string): boolean => {
    if (referenced.has(file)) {
      return false;
    }
    const base = basename(file);
    return !ids.has(base.split('_', 1)[0]) && [...ids].every((id) => !base.includes(id));
  };
  for (const folder of ['library', 'upload', 'thumbs', 'encoded-video']) {
    for (const file of walkFiles(join(forkDataDir, folder))) {
      if (isOrphan(file)) {
        orphans.push(file);
      }
    }
  }
  return { orphans, missing };
};
