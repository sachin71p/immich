import { mkdir, mkdtemp, realpath, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { isPathInside, isResolvedPathInside } from 'src/utils/path.js';

describe('path containment', () => {
  const temporaryDirectories: string[] = [];

  afterEach(async () => {
    const directories = [...temporaryDirectories];
    temporaryDirectories.length = 0;
    await Promise.all(directories.map((directory) => rm(directory, { force: true, recursive: true })));
  });

  it('[R17] rejects traversal and a sibling prefix while accepting the root and trailing separators', () => {
    expect(isPathInside('/allowed/../outside', '/allowed')).toBe(false);
    expect(isPathInside('/shared/family-2/photo.jpg', '/shared/family')).toBe(false);
    expect(isPathInside('/shared/family/', '/shared/family')).toBe(true);
    expect(isPathInside('/shared/family/photo.jpg/', '/shared/family/')).toBe(true);
  });

  it('[R17] rejects an existing symlink that escapes the allowed root', async () => {
    const temporaryDirectory = await mkdtemp(join(tmpdir(), 'immich-path-'));
    temporaryDirectories.push(temporaryDirectory);
    const root = join(temporaryDirectory, 'allowed');
    const outside = join(temporaryDirectory, 'outside');
    await Promise.all([mkdir(root), mkdir(outside)]);
    await symlink(outside, join(root, 'escape'));

    await expect(isResolvedPathInside(join(root, 'escape', 'photo.jpg'), root, realpath)).resolves.toBe(false);
  });
});
