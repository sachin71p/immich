// Fork personal-fixture indexer (shared-libraries, T0).
//
// Scans e2e/fork-assets/personal/ for the expected real-world files listed in
// README.md, reads EXIF + checksums, and writes the gitignored
// e2e/fork-assets/personal/manifest.local.json that @personal tests read for
// expectations (nothing personal is ever committed).
//
// Run via scripts/fork-test/run.sh, or manually (no tsx in the repo — stage
// under server/ so exiftool-vendored resolves, then compile + node):
//   mkdir -p server/.fork-ts-manual && cp scripts/fork-test/index-personal.ts server/.fork-ts-manual/ \
//   && cd server && pnpm exec tsc --ignoreConfig --module commonjs --target es2022 \
//     --moduleResolution bundler --esModuleInterop --skipLibCheck --types node \
//     --outDir /tmp/fork-personal .fork-ts-manual/index-personal.ts \
//   && NODE_PATH="$PWD/node_modules" node /tmp/fork-personal/index-personal.js; rm -rf .fork-ts-manual

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { ExifTool } from 'exiftool-vendored';

const findPersonalDir = (): string => {
  let dir = process.cwd();
  for (let i = 0; i < 6; i++) {
    const candidate = join(dir, 'e2e', 'fork-assets', 'personal');
    if (existsSync(candidate)) {
      return candidate;
    }
    dir = dirname(dir);
  }
  throw new Error('e2e/fork-assets/personal not found above cwd');
};

const sha256 = (path: string): string => createHash('sha256').update(readFileSync(path)).digest('hex');

const main = async (): Promise<void> => {
  const personalDir = findPersonalDir();
  const outFile = join(personalDir, 'manifest.local.json');
  const files = readdirSync(personalDir).filter(
    (file) => file !== 'README.md' && file !== 'manifest.local.json' && !file.startsWith('.'),
  );
  const exiftool = new ExifTool({ taskTimeoutMillis: 30_000 });
  try {
    const entries = [];
    for (const file of files.sort()) {
      const path = join(personalDir, file);
      const meta = (await exiftool.read(path)) as Record<string, unknown>;
      entries.push({
        file,
        sha256: sha256(path),
        dateTimeOriginal:
          meta.DateTimeOriginal == null
            ? null
            : String((meta.DateTimeOriginal as { rawValue?: unknown }).rawValue ?? meta.DateTimeOriginal),
        make: meta.Make ?? null,
        model: meta.Model ?? null,
        width: meta.ImageWidth ?? null,
        height: meta.ImageHeight ?? null,
      });
    }
    writeFileSync(outFile, `${JSON.stringify({ version: 1, files: entries }, null, 2)}\n`);
    console.log(`indexed ${entries.length} personal file(s) -> ${outFile}`);
  } finally {
    await exiftool.end();
  }
};

void main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
