# S8c handoff — Web: full metadata panel & search filters

## Summary
- DetailPanel: lazy "All metadata" panel (`DetailPanelFullMetadata.svelte`) calling `GET /assets/:id/exif/full`;
  collapsible groups, key search box, click-to-copy value, binary shown via `search_filter_full_metadata_binary`.
- Search filters: new `SearchExposureSection` (ISO/aperture/focal-length ranges), `SearchFileSection`
  (extensions, mime type, size range, min dimensions, 360°, has-location, fps), `SearchLibrarySection`
  (All/Personal/space/library, reusing S8a's `sharedSpaces` store). Wired into `SearchFilters.svelte`, round-tripped
  through the URL via `search-manager.svelte.ts` + new pure mappers in `search-bar-utils.ts`. i18n keys added.

## Files changed
New: `.../search-bar/{SearchExposureSection,SearchFileSection,SearchLibrarySection}.svelte`,
`SearchExposureSection.spec.ts`, `.../asset-viewer/DetailPanelFullMetadata.svelte`.
Modified (additive, `// fork: shared-libraries`): `SearchFilters.svelte`, `search-bar-utils.ts` (+spec),
`search-manager.svelte.ts`, `web/src/lib/types.ts`, `DetailPanel.svelte`, `i18n/en.json`, `packages/sdk/src/fetch-client.ts`.

## FORK.md patch-list lines
`web/src/lib/components/asset-viewer/{DetailPanel.svelte,DetailPanelFullMetadata.svelte} | full metadata viewer | R12 | S8c`
`web/src/lib/components/shared-components/search-bar/{SearchExposureSection,SearchFileSection,SearchLibrarySection}.svelte | extended metadata filters + library scope | R13 | S8c`
`web/src/lib/{components/shared-components/search-bar/search-bar-utils.ts,managers/search-manager.svelte.ts,types.ts} | filter<->URL query mapping | R13 | S8c`
`packages/sdk/src/fetch-client.ts | hand-added AssetFullExifResponseDto/getAssetFullExif + rich search fields (mise unavailable) | R12/R13 | S8c`

## Deviations
- Shutter/exposure-time range NOT implemented: S7 deliberately omitted `exposureTimeMin/Max` (no approved
  numeric normalization for free-form text) — see handoff/S7.md. Exposure covers ISO/aperture/focal length only.
- `mise` unavailable (same gap as S7): hand-added DTO fields/endpoint/enum to `fetch-client.ts` mirroring
  server's zod schemas, then ran `pnpm --filter @immich/sdk build`. S10 should re-run a real regen to confirm.
- CODEMAP-FIX: §H lists only `Search*Section.svelte`/`search-bar-utils.ts`, but filter↔URL round-trip actually
  lives in `search-manager.svelte.ts`; extended both — pure mappers (unit-tested) + wiring, respectively.
- Extensions/MIME type inputs are comma-separated text fields, not suggestion-backed multi-select (SDK's new
  `SearchSuggestionType.FileExtension` is available for a future combobox upgrade).
- S8b (+ a native-apple agent) edited files concurrently in this tree incl. `DetailPanel.svelte`; stayed inside
  declared scope, did not touch `TimelineAssetViewer.svelte`/`move-targets.ts`/timeline actions.

## Open issues
- `check:typescript`/`lint`: pass for all S8c files (2 pre-existing errors remain in S8b's out-of-scope files).
- `check:svelte`: hits documented TS 6.0.3 compiler crash (env gap, see S8a-verify.md); reported 1 error in
  S8b's `LibrarySourceSwitcher.svelte` before crashing, none in S8c files.
- `test --run`: hits documented `localStorage`/`ThemeManager` setup crash (env gap) across 41 suites incl.
  pre-existing ones; my new specs couldn't execute for the same reason. All 356 tests that ran passed.
