import { basename, dirname, join, resolve, sep } from 'node:path';

type Realpath = (path: string) => Promise<string>;

/**
 * Returns true only when candidate is root itself or is below root at a path
 * boundary. Both inputs are normalized before comparison.
 */
export const isPathInside = (candidate: string, root: string) => {
  const resolvedRoot = resolve(root);
  const resolvedCandidate = resolve(candidate);
  return resolvedCandidate === resolvedRoot || resolvedCandidate.startsWith(`${resolvedRoot}${sep}`);
};

/**
 * Resolves the existing portion of a path and appends any missing suffix.
 * This detects symlinks in an existing destination parent while still working
 * for a destination file that has not been created yet.
 */
const realpathWithMissingSuffix = async (input: string, realpath: Realpath): Promise<string> => {
  let current = resolve(input);
  const missing: string[] = [];

  while (true) {
    try {
      return join(await realpath(current), ...missing);
    } catch (error: any) {
      if (error?.code !== 'ENOENT') throw error;

      const parent = dirname(current);
      if (parent === current) throw error;
      missing.unshift(basename(current));
      current = parent;
    }
  }
};

/**
 * Resolves lexical traversal and filesystem symlinks before enforcing a root
 * boundary. Use this for paths whose allowed root is security-sensitive.
 */
export const isResolvedPathInside = async (candidate: string, root: string, realpath: Realpath) => {
  if (!isPathInside(candidate, root)) return false;

  const [resolvedCandidate, resolvedRoot] = await Promise.all([
    realpathWithMissingSuffix(candidate, realpath),
    realpathWithMissingSuffix(root, realpath),
  ]);
  return isPathInside(resolvedCandidate, resolvedRoot);
};
