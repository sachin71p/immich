// Fork fixture generator (shared-libraries, T0).
//
// Reads e2e/fork-assets/manifest.json (source of truth), writes
// e2e/fork-assets/generated/* (+ .xmp sidecars), then verifies every file
// against the manifest by reading it back with exiftool.
//
// Run from the server workspace so the server's own sharp +
// exiftool-vendored are used (no new dependencies):
//   cd server && pnpm exec tsc --ignoreConfig --module es2022 --target es2022 \
//     --moduleResolution bundler --esModuleInterop --skipLibCheck --types node \
//     --outDir /tmp/fork-gen test/fork-fixtures/generate.ts \
//   && NODE_PATH="$PWD/node_modules" node /tmp/fork-gen/generate.js
//
// Regenerate only when the manifest spec changes. Deterministic: pixels come
// from a seeded PRNG, so re-runs produce byte-identical files.

import { ExifTool } from 'exiftool-vendored';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import sharp from 'sharp';

interface SidecarSpec {
  date?: string;
  keywords?: string[];
  customNs?: boolean;
}

interface FixtureSpec {
  id: string;
  file: string;
  width: number;
  height: number;
  format: 'jpg' | 'png' | 'webp';
  seed: number;
  date?: string;
  offset?: string;
  noDate?: boolean;
  make?: string;
  model?: string;
  lens?: string;
  iso?: number;
  fNumber?: number;
  focal?: number;
  exposure?: string;
  rating?: number;
  orientation?: number;
  description?: string;
  gps?: [number, number];
  projection?: string;
  sidecar?: SidecarSpec;
  duplicateOf?: string;
  embedThumb?: boolean;
}

const findRepoRoot = (): string => {
  // Works both as generate.ts (server workspace) and compiled to /tmp.
  for (const start of [import.meta.dirname, process.cwd()]) {
    let dir = start;
    for (let i = 0; i < 6; i++) {
      if (existsSync(join(dir, 'e2e', 'fork-assets', 'manifest.json'))) {
        return dir;
      }
      dir = dirname(dir);
    }
  }
  throw new Error('repo root (e2e/fork-assets/manifest.json) not found');
};

const repoRoot = findRepoRoot();
const manifestPath = join(repoRoot, 'e2e', 'fork-assets', 'manifest.json');
const outDir = join(repoRoot, 'e2e', 'fork-assets', 'generated');
const MAX_BYTES = 150 * 1024;

// Seeded PRNG (mulberry32) — deterministic pixels, unique checksums.
const mulberry32 = (seed: number) => {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d_2b_79_f5) >>> 0;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 2 ** 32;
  };
};

const renderPixels = (spec: FixtureSpec): Buffer => {
  const random = mulberry32(spec.seed);
  const { width, height } = spec;
  const pixels = Buffer.alloc(width * height * 3);
  const baseR = Math.floor(random() * 256);
  const baseG = Math.floor(random() * 256);
  const baseB = Math.floor(random() * 256);
  // Flat field + seeded full-noise patch: compresses to KBs at any size
  // (all fixtures must stay < 150 KB) while keeping unique checksums.
  const patch = Math.min(96, width, height);
  const px = Math.floor(random() * (width - patch));
  const py = Math.floor(random() * (height - patch));
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 3;
      if (x >= px && x < px + patch && y >= py && y < py + patch) {
        pixels[i] = Math.floor(random() * 256);
        pixels[i + 1] = Math.floor(random() * 256);
        pixels[i + 2] = Math.floor(random() * 256);
      } else {
        pixels[i] = baseR;
        pixels[i + 1] = baseG;
        pixels[i + 2] = baseB;
      }
    }
  }
  return pixels;
};

const sidecarXml = (spec: FixtureSpec): string => {
  const date = spec.sidecar?.date ?? spec.date ?? '2022:01:01 00:00:00';
  const keywords = (spec.sidecar?.keywords ?? []).map((k) => `      <rdf:li>${k}</rdf:li>`).join('\n');
  const custom = spec.sidecar?.customNs
    ? `    <rdf:Description rdf:about="" xmlns:fork="https://fork.example/ns/1.0" fork:makerNote="simulated-makernote-payload"/>\n`
    : '';
  return `<?xml version="1.0" encoding="UTF-8"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about="" xmlns:exif="http://ns.adobe.com/exif/1.0/" exif:DateTimeOriginal="${date.replaceAll(':', '-').replace(' ', 'T')}"/>
${custom}    <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <dc:subject>
        <rdf:Seq>
${keywords}
        </rdf:Seq>
      </dc:subject>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
`;
};

const sha256 = (path: string): string => createHash('sha256').update(readFileSync(path)).digest('hex');

const num = (value: unknown): number | undefined =>
  typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : undefined;

async function main(): Promise<void> {
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8')) as { generated: FixtureSpec[] };
  mkdirSync(outDir, { recursive: true });
  const exiftool = new ExifTool({ taskTimeoutMillis: 30_000 });
  const byId = new Map(manifest.generated.map((s) => [s.id, s]));
  let failures = 0;
  const fail = (message: string) => {
    failures++;
    console.error(`FAIL ${message}`);
  };

  try {
    for (const spec of manifest.generated) {
      const file = join(outDir, spec.file);
      if (spec.duplicateOf) {
        const source = byId.get(spec.duplicateOf);
        if (!source) {
          fail(`${spec.id}: unknown duplicateOf ${spec.duplicateOf}`);
          continue;
        }
        copyFileSync(join(outDir, source.file), file);
      } else {
        const image = sharp(renderPixels(spec), { raw: { width: spec.width, height: spec.height, channels: 3 } });
        if (spec.format === 'jpg') {
          await image.jpeg({ quality: 70 }).toFile(file);
        } else if (spec.format === 'png') {
          await image.png().toFile(file);
        } else {
          await image.webp({ quality: 70 }).toFile(file);
        }
        const tags: Record<string, string | number> = {};
        if (spec.date && !spec.noDate) {
          tags.DateTimeOriginal = spec.offset ? `${spec.date}${spec.offset}` : spec.date;
          if (spec.offset) {
            tags.OffsetTimeOriginal = spec.offset;
          }
        }
        if (spec.make) {
          tags.Make = spec.make;
        }
        if (spec.model) {
          tags.Model = spec.model;
        }
        if (spec.lens) {
          tags.LensModel = spec.lens;
        }
        if (spec.iso !== undefined) {
          tags.ISO = spec.iso;
        }
        if (spec.fNumber !== undefined) {
          tags.FNumber = spec.fNumber;
        }
        if (spec.focal !== undefined) {
          tags.FocalLength = spec.focal;
        }
        if (spec.exposure !== undefined) {
          tags.ExposureTime = spec.exposure;
        }
        if (spec.rating !== undefined) {
          tags.Rating = spec.rating;
        }
        // NOTE: Orientation must go through a raw numeric arg — the
        // tags-object path writes a value exiftool reads back as 3.
        const extraArgs = ['-overwrite_original'];
        if (spec.orientation !== undefined) {
          extraArgs.push(`-Orientation#=${spec.orientation}`);
        }
        if (spec.description !== undefined) {
          tags.ImageDescription = spec.description;
        }
        if (spec.gps) {
          tags.GPSLatitude = spec.gps[0];
          tags.GPSLongitude = spec.gps[1];
        }
        if (spec.projection) {
          tags['XMP-gpano:ProjectionType'] = spec.projection;
        }
        if (Object.keys(tags).length > 0 || extraArgs.length > 1) {
          await exiftool.write(file, tags, extraArgs);
        }
      }
      if (spec.sidecar) {
        writeFileSync(`${file}.xmp`, sidecarXml(spec));
      }
      if (spec.embedThumb) {
        const thumb = join(tmpdir(), `fork-${spec.id}-thumb.jpg`);
        await sharp(renderPixels({ ...spec, seed: spec.seed + 1, width: 64, height: 48, format: 'jpg' }), {
          raw: { width: 64, height: 48, channels: 3 },
        })
          .jpeg({ quality: 60 })
          .toFile(thumb);
        await exiftool.write(file, {}, ['-overwrite_original', `-ThumbnailImage<=${thumb}`]);
        rmSync(thumb, { force: true });
      }
    }

    // Verify: read everything back and compare against the manifest.
    for (const spec of manifest.generated) {
      const file = join(outDir, spec.file);
      if (!existsSync(file)) {
        fail(`${spec.id}: missing ${spec.file}`);
        continue;
      }
      const bytes = readFileSync(file).length;
      if (bytes > MAX_BYTES) {
        fail(`${spec.id}: ${bytes} bytes exceeds 150 KB`);
      }
      if (spec.duplicateOf) {
        const source = byId.get(spec.duplicateOf);
        if (source && sha256(file) !== sha256(join(outDir, source.file))) {
          fail(`${spec.id}: bytes differ from ${spec.duplicateOf}`);
        }
        continue;
      }
      const meta = (await exiftool.read(file)) as Record<string, unknown>;
      // exiftool-vendored returns dates as ExifDateTime objects whose
      // toString() is ISO; rawValue keeps the original EXIF spelling.
      const dto =
        meta.DateTimeOriginal === null || meta.DateTimeOriginal === undefined
          ? ''
          : String((meta.DateTimeOriginal as { rawValue?: unknown }).rawValue ?? meta.DateTimeOriginal);
      if (spec.date && !spec.noDate && !dto.startsWith(spec.date)) {
        fail(`${spec.id}: DateTimeOriginal=${dto}, expected ${spec.date}`);
      } else if (spec.noDate && meta.DateTimeOriginal) {
        fail(`${spec.id}: expected no EXIF date, found ${dto}`);
      }
      if (spec.make && meta.Make !== spec.make) {
        fail(`${spec.id}: Make=${meta.Make}, expected ${spec.make}`);
      }
      if (spec.model && meta.Model !== spec.model) {
        fail(`${spec.id}: Model=${meta.Model}, expected ${spec.model}`);
      }
      if (spec.iso !== undefined && num(meta.ISO) !== spec.iso) {
        fail(`${spec.id}: ISO=${meta.ISO}, expected ${spec.iso}`);
      }
      if (spec.rating !== undefined && num(meta.Rating) !== spec.rating) {
        fail(`${spec.id}: Rating=${meta.Rating}, expected ${spec.rating}`);
      }
      if (spec.orientation !== undefined && num(meta.Orientation) !== spec.orientation) {
        fail(`${spec.id}: Orientation=${meta.Orientation}, expected ${spec.orientation}`);
      }
      if (spec.gps) {
        const lat = num(meta.GPSLatitude);
        const lon = num(meta.GPSLongitude);
        if (
          lat === undefined ||
          lon === undefined ||
          Math.abs(lat - spec.gps[0]) > 1e-4 ||
          Math.abs(lon - spec.gps[1]) > 1e-4
        ) {
          fail(`${spec.id}: GPS=${lat},${lon}, expected ${spec.gps}`);
        }
      }
      if (spec.projection && meta.ProjectionType !== spec.projection) {
        fail(`${spec.id}: ProjectionType=${meta.ProjectionType}, expected ${spec.projection}`);
      }
      if (num(meta.ImageWidth) !== spec.width || num(meta.ImageHeight) !== spec.height) {
        fail(`${spec.id}: dimensions=${meta.ImageWidth}x${meta.ImageHeight}, expected ${spec.width}x${spec.height}`);
      }
      if (spec.sidecar && !existsSync(`${file}.xmp`)) {
        fail(`${spec.id}: sidecar missing`);
      }
      if (spec.embedThumb && !meta.ThumbnailImage) {
        fail(`${spec.id}: embedded thumbnail missing`);
      }
    }
  } finally {
    await exiftool.end();
  }

  if (failures > 0) {
    throw new Error(`fixture verification failed with ${failures} error(s)`);
  }
  console.log(`generated + verified ${manifest.generated.length} fixtures in ${outDir}`);
}

void main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
