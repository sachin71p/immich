// Fork coverage checker (shared-libraries, T0). See TESTING.md §6.
//
// Greps all fork specs for `[ID]` tags and diffs against the TESTING.md §5
// case matrix. Fails if a case owned by a completed phase (STATUS.md ✅)
// has no test. Cases from incomplete phases are reported, not failed.
// Personal (@personal) cases are skipped unless --personal is passed AND
// e2e/fork-assets/personal/manifest.local.json exists.
//
// Gate-tier rows (S10, Layer G) are implemented as scripts/tiers, not specs:
// INV-02 by the `openapi-diff` tier, UP-01 by the `upgrade` tier, INV-03 by
// the `upstream` tier (upstream-medium + upstream-e2e). They count as covered
// only with host-tier execution evidence: a PASS record in e2e/.fork-report/
// (written by run.sh). Script existence alone never covers them.
//
// Cross-cutting tags [C3]/[R16]/[I6]/[I7]/PERM-11 are NOT matrix rows and
// never fail the gate for being unlisted; they are reported, and the gate
// fails if a tag recorded in scripts/fork-test/coverage.advisory.json has
// vanished from the tree (no silent loss, no invented phase ownership).
// COVERAGE_ADVISORY_BASELINE overrides the baseline path (self-checks).
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

// Gate-tier rows count as covered only with host-tier execution evidence:
// the newest e2e/.fork-report/*.md record for each required tier must be
// PASS (run.sh writes one `- [PASS|FAIL] <tier>` line per tier run).
interface GateTier {
  id: string;
  tiers: string[];
  owed: string;
}

const gateTiers: GateTier[] = [
  { id: 'INV-02', tiers: ['openapi-diff'], owed: 'scripts/fork-test/run.sh upgrade' },
  { id: 'UP-01', tiers: ['upgrade'], owed: 'scripts/fork-test/run.sh upgrade' },
  { id: 'INV-03', tiers: ['upstream-medium', 'upstream-e2e'], owed: 'scripts/fork-test/run.sh upstream' },
];

interface TierRecord {
  status: string;
  file: string;
}

const readTierEvidence = (reportDir: string): Map<string, TierRecord> => {
  const latest = new Map<string, TierRecord>();
  if (!existsSync(reportDir)) {
    return latest;
  }
  for (const file of readdirSync(reportDir).filter((f) => f.endsWith('.md')).sort()) {
    for (const line of readFileSync(join(reportDir, file), 'utf8').split('\n')) {
      const match = /^-\s*\[(PASS|FAIL|SKIP)\]\s+(\S+)/.exec(line.trim());
      if (match) {
        latest.set(match[2], { status: match[1], file });
      }
    }
  }
  return latest;
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

  const evidence = readTierEvidence(join(root, 'e2e', '.fork-report'));
  const gateEvidence: string[] = [];
  const gateOwed: string[] = [];
  for (const gate of gateTiers) {
    const passing = gate.tiers.filter((tier) => evidence.get(tier)?.status === 'PASS');
    if (passing.length === gate.tiers.length) {
      tagged.add(gate.id);
      gateEvidence.push(`${gate.id} covered by ${gate.tiers.map((t) => `${t} PASS (${evidence.get(t)?.file})`).join(' + ')}`);
    } else {
      const detail = gate.tiers
        .map((t) => {
          const rec = evidence.get(t);
          return rec ? `${t} ${rec.status} (${rec.file})` : `${t} never ran`;
        })
        .join(' + ');
      gateOwed.push(`${gate.id} has no host-tier PASS evidence [${detail}] — owed: ${gate.owed}`);
    }
  }

  // Fork cross-cutting tags (HOST-VERIFICATION-BRIEF §2d decision): [C3], [R16],
  // [I6], [I7] and bare PERM-11 annotate tests whose case id already pins the
  // behavior, so they are NOT matrix rows and never fail the gate. Report them,
  // and fail if a tag recorded in the advisory baseline has vanished from the
  // tree; adding hard rows would invent phase ownership for bare-invariant
  // tags (a T0-contract change, out of S10 scope).
  const advisoryTags = ['C3', 'R16', 'I6', 'I7', 'PERM-11'];
  const advisorySeen = new Map<string, number>();
  for (const specRootDir of specRoots) {
    for (const file of walk(specRootDir, ['.ts', '.tsx', '.swift'])) {
      const content = readFileSync(file, 'utf8');
      for (const tag of advisoryTags) {
        const pattern = tag === 'PERM-11' ? /PERM-11/ : new RegExp(`\\[${tag}\\]`);
        if (pattern.test(content)) {
          advisorySeen.set(tag, (advisorySeen.get(tag) ?? 0) + 1);
        }
      }
    }
  }
  const baselinePath =
    process.env.COVERAGE_ADVISORY_BASELINE ?? join(root, 'scripts', 'fork-test', 'coverage.advisory.json');
  let baseline: Record<string, number> = {};
  if (existsSync(baselinePath)) {
    try {
      baseline = JSON.parse(readFileSync(baselinePath, 'utf8')) as Record<string, number>;
    } catch (error) {
      console.error(`cannot parse advisory baseline ${baselinePath}: ${error}`);
      process.exit(1);
    }
  } else {
    console.log(`advisory baseline: missing (${baselinePath}) — disappearance detection off until it is committed`);
  }
  const vanished = advisoryTags.filter((tag) => (baseline[tag] ?? 0) > 0 && (advisorySeen.get(tag) ?? 0) === 0);

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
  for (const line of gateEvidence) {
    console.log(`gate evidence: ${line}`);
  }
  for (const line of gateOwed) {
    console.log(`gate evidence: ${line}`);
  }
  console.log(
    `advisory tags (report-only, not matrix rows): ${advisoryTags.map((t) => `${t}=${advisorySeen.get(t) ?? 0} files`).join(', ')}`,
  );
  let failed = false;
  if (vanished.length > 0) {
    console.error(
      `VANISHED advisory tags (seen in ${baselinePath}, now at zero files): ${vanished.join(', ')} — restore the tests or deliberately update the baseline`,
    );
    failed = true;
  }
  if (missing.length > 0) {
    console.error(`MISSING tests for done-phase cases: ${missing.map((r) => `${r.id}(${r.phase})`).join(', ')}`);
    failed = true;
  }
  if (failed) {
    process.exit(1);
  }
  console.log('coverage OK: every done-phase case has a test');
};

main();
