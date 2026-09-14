# A7 — Metadata panel, search & filters (iOS + macOS)

Depends on: A3, A4, S7 · Reads: A0 Architecture+Rules · DECISIONS §2 (R12, R13), §10 · handoff S7.

## Tasks
1. Info panel "All metadata": `GET /assets/:id/exif/full`, grouped, searchable, copyable; cached per asset.
2. Search: smart search (CLIP) + metadata search (S7 filters) with suggestion chips (people, places, camera, lens,
   file type), library scope selector, results grid reusing A3/A4 grids. Recent searches.
3. Local instant filters on LocalStore exif mirror (camera, lens, ISO/aperture/shutter/focal ranges, file type,
   dimensions, has location, favorites, media type, date range) for offline filtering; server search for the rest.
4. Filter DSL shared by both apps (Core `Search` module) with URL-like serialization for saved searches (smart albums later).

## Tests
Filter DSL round-trip, local query correctness on fixture DB, API param mapping.

Verify: `native-apple/scripts/verify.sh all`.
