# Personal fixtures (optional, never committed)

Drop your own real-world files here. Tests tagged `@personal` use them when
present and skip with a visible notice when absent, so a fresh checkout works
without this folder.

Expected file names (TESTING.md §2.3):

| File | What it is |
|---|---|
| `live.heic` + `live.mov` | iPhone Live Photo still + motion part |
| `portrait.heic` | Portrait mode with depth data |
| `proraw.dng` | ProRAW capture |
| `hdr.heic` | HDR still |
| `pano.jpg` | Panorama |
| `cinematic.mov` | Cinematic-mode video |
| `video-hevc.mov` | HEVC video |
| `screenshot.png` | Screenshot (usually no EXIF date) |
| `burst-1.heic` … `burst-3.heic` | Burst sequence |

Run `scripts/fork-test/index-personal.ts` to (re)build the gitignored
`manifest.local.json` (checksums + EXIF expectations) that tests read
(no tsx in the repo — stage under server/, compile + node):

```sh
mkdir -p server/.fork-ts-manual && cp scripts/fork-test/index-personal.ts server/.fork-ts-manual/ \
&& cd server && pnpm exec tsc --ignoreConfig --module commonjs --target es2022 \
  --moduleResolution bundler --esModuleInterop --skipLibCheck --types node \
  --outDir /tmp/fork-personal .fork-ts-manual/index-personal.ts \
&& NODE_PATH="$PWD/node_modules" node /tmp/fork-personal/index-personal.js; rm -rf .fork-ts-manual
```
