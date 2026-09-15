// Fork coverage checker (shared-libraries, T0). See TESTING.md §6.
//
// Greps all fork specs for `[ID]` tags and diffs against the TESTING.md §5
// case matrix. Fails if a case owned by a completed phase (STATUS.md ✅)
// has no test. Cases from incomplete phases are reported, not failed.
// Personal (@personal) cases are skipped unless --personal is passed AND
// e2e/fork-assets/personal/manifest.local.json exists.
//
// Run via scripts/fork-test/run.sh coverage, or manually (no tsx in the repo):
//   mkdir -p server/.fork-ts-manual && cp scripts/fork-test/coverage.ts server/.fork-ts-manual/ \
//   && cd server && pnpm exec tsc --ignoreConfig --module commonjs --target es2022 \
//     --moduleResolution bundler --esModuleInterop --skipLibCheck --types node \
//     --outDir /tmp/fork-coverage .fork-ts-manual/coverage.ts \
//   && node /tmp/fork-coverage/coverage.js [--personal]; rm -rf .fork-ts-manual

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';

const findRoot = (): string => {
  let dir = process.cwd();
  for (let i = 0; i < 6; i++) {
    if (existsSync(join(dir, '.claude', 'plans', 'shared-libraries', 'TESTING.md'))) {
      return dir;
    }
    dir = dirname(dir);
  }
  throw new Error('repo root not found above cwd');
};

const skipDirs = new Set(['node_modules', '.build', '.git', 'dist', 'build']);

const walk = (dir: string, exts: string[]): string[] => {
  const out: string[] = [];
  if (!existsSync(dir)) {
    return out;
  }
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    // Never follow symlinks (native-apple/.build has symlink loops).
    if (entry.isSymbolicLink() || skipDirs.has(entry.name)) {
      continue;
    }
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...walk(path, exts));
    } else if (entry.isFile() && exts.some((ext) => entry.name.endsWith(ext))) {
      out.push(path);
    }
  }
  return out;
};

interface MatrixRow {
  id: string;
  phase: string;
}

const parseMatrix = (testing: string): MatrixRow[] => {
  const rows: MatrixRow[] = [];
  for (const line of testing.split('\n')) {
    const cells = line.split('|').map((c) => c.trim());
    // Matrix rows: | ID | Req | Layer | Phase | Scenario |
    if (cells.length >= 6 && /^(R[0-9]*|INV|MV|LC|SY|UP|W|AP)-[0-9A-Z-]+$/.test(cells[1] ?? '') && cells[0] === '') {
      rows.push({ id: cells[1], phase: cells[4] });
    }
  }
  return rows;
};

const parseDonePhases = (status: string): Set<string> => {
  const done = new Set<string>();
  for (const line of status.split('\n')) {
    const cells = line.split('|').map((c) => c.trim());
    if (cells.length >= 7 && cells[0] === '' && cells[5].includes('✅')) {
      done.add(cells[1]);
    }
  }
  return done;
};

const main = (): void => {
  const root = findRoot();
  const requirePersonal = process.argv.includes('--personal');
  const testing = readFileSync(join(root, '.claude', 'plans', 'shared-libraries', 'TESTING.md'), 'utf8');
  const status = readFileSync(join(root, '.claude', 'plans', 'shared-libraries', 'STATUS.md'), 'utf8');
  const matrix = parseMatrix(testing);
  const donePhases = parseDonePhases(status);

  const specRoots = [
    join(root, 'server', 'src'),
    // fork: shared-libraries - fork-tagged tests also live in the existing medium suites (S6),
    // not only the future T1 fork dir.
    join(root, 'server', 'test', 'medium', 'specs'),
    join(root, 'e2e', 'src', 'specs'),
    join(root, 'web', 'src'),
    join(root, 'native-apple'),
  ];
  const tagged = new Set<string>();
  for (const specRootDir of specRoots) {
    for (const file of walk(specRootDir, ['.ts', '.tsx', '.swift'])) {
      const content = readFileSync(file, 'utf8');
      for (const match of content.matchAll(/\[((?:R[0-9]*|INV|MV|LC|SY|UP|W|AP)-[0-9A-Z-]+)\]/g)) {
        tagged.add(match[1]);
      }
    }
  }

  const personalOk = existsSync(join(root, 'e2e', 'fork-assets', 'personal', 'manifest.local.json'));
  const missing: MatrixRow[] = [];
  const pending: MatrixRow[] = [];
  for (const row of matrix) {
    if (tagged.has(row.id)) {
      continue;
    }
    if (donePhases.has(row.phase)) {
      missing.push(row);
    } else {
      pending.push(row);
    }
  }

  console.log(`matrix cases: ${matrix.length}, tagged: ${tagged.size}`);
  console.log(`done phases: ${[...donePhases].join(', ')}`);
  if (!requirePersonal || !personalOk) {
    console.log('personal fixtures: skipped (pass --personal with manifest.local.json to require them)');
  }
  if (pending.length > 0) {
    console.log(`pending (phase not done): ${pending.map((r) => r.id).join(', ')}`);
  }
  if (missing.length > 0) {
    console.error(`MISSING tests for done-phase cases: ${missing.map((r) => `${r.id}(${r.phase})`).join(', ')}`);
    process.exit(1);
  }
  console.log('coverage OK: every done-phase case has a test');
};

main();
