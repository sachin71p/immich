# S8c — Web: full metadata panel & search filters

Depends on: S8a · Parallel-safe with S8b · Reads: DECISIONS §2 (R12, R13) · CODEMAP §H · handoff S7.

## Tasks
1. `DetailPanel.svelte`: "All metadata" expandable section → lazy `GET /assets/:id/exif/full`; groups collapsible,
   search box filtering keys, copy-value on click, binary entries shown as "binary (N bytes)".
2. Search filters: new sections `SearchExposureSection.svelte` (ISO, aperture, shutter, focal length ranges) and
   `SearchFileSection.svelte` (extensions, mime type, size range, min dimensions, 360°, has location, fps); add a
   "Library" selector (All / Personal / space / library) to the filters; extend `search-bar-utils.ts` mapping and the
   URL query serialization so searches are shareable/reloadable.
3. i18n keys in `i18n/en.json`.

## Tests
`search-bar-utils` round-trip tests for new params; component test for range inputs.

## Self-check / Verify
`cd web && pnpm run check:typescript && pnpm run check:svelte && pnpm run lint && pnpm run test --run`
