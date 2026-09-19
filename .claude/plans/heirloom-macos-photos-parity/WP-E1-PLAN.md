# WP-E1 — Recipe v2 + rendition-on-same-asset (plan, Final for Phase 1)

Source brief: `heirloom-on-device-ai/PLAN.md` §13.4 (lines 489–507), §13.6 (E1 row: "Opus designs
server contract; implementer", depends E0 + WP1). Scout: E1 territory report (2026-09-18).

## Why phases

Full §13.4 is server storage + clients + Photos import/write-back + render jobs. Only the first
two unblock real Done-save. Split:

- **Phase 1 (this plan):** KV v2 + dual-read migration, rendition endpoint + storage/serving,
  all five Done-save call sites switched, contract tests. Done becomes real.
- **Phase 2 (later):** `asset_edit_resource` files (patches/PKDrawing/scripts), Apple Photos
  import (`recipe.source = "apple-photos"`) + write-back (`PHAdjustmentData`), batch render jobs.
- **Out:** E0 iOS canvas P0s (separate package; iOS call-site switch below does not fix canvas).

## Phase 1 contract design (normative)

1. `PUT /assets/:id/rendition` — multipart file upload, stores as the asset's `edited` file.
   Response: the asset DTO (thumb URLs now derive from the rendition). Auth: same as asset
   owner-write. Rejects non-image/video MIME as the asset upload path does.
2. `DELETE /assets/:id/rendition` — Revert: deletes the `edited` file; thumbs fall back to the
   original. Idempotent (204 when absent).
3. Serving rule: when a rendition exists, thumbnail/preview/original-URLs derive from it;
   `asset_edit` (server crop/rotate/mirror) applies **on top of** the rendition at serve time.
   Timeline shows one item (no separate asset is ever created — this falls out of the design).
4. Metadata KV unchanged in shape (JSON objects only): recipe key bumps
   `fork.editRecipe.v1` → `fork.editRecipe.v2`, versions `fork.editVersions.v1` → `.v2`
   (constants `EditRecipeKey`, `EditVersionKey`; payload `format` tags move in lockstep).
5. No `asset_edit` table change in Phase 1.

## Phase 1 client design (normative)

1. Dual-read migration: read tries `.v2` first, falls back to `.v1` (decode-with-identity for
   missing keys, as today); any save writes `.v2` only and deletes the `.v1` key after a
   successful write. No standalone migration job (user has no Heirloom edits yet; fleet rule:
   lazy migration on touch).
2. All five Done-save call sites switch atomically from "upload render as new asset + saveRecipe"
   to "PUT rendition + saveRecipe(.v2) + append-version": `MacEditModeView.savePhoto/saveVideo`,
   legacy `MacEditView`, `MacViewer` + `MacMainWindow` paste paths, iOS `EditView`.
   Order per save: upstream edits → rendition PUT → recipe save → version append (same order as
   today, rendition replacing the new-asset upload).
3. `EditHistory` copy/paste format tag moves to `.v2`; foreign/legacy payloads still rejected.
4. Golden JSON fixtures + base-`9b9bb7f2e` back-compat tests (TEST-PLAN E5) extended: v1 payloads
   decode identically under the v2 reader.
5. E7 Done-gating unchanged: fixture (no server original) keeps Done disabled; UI tests stay
   fixture-only, never Done on a real asset.

## Phase 1 tests (acceptance bar)

- Server: red-first specs for PUT/DELETE rendition (auth, MIME reject, idempotent revert,
  thumbs derive from rendition, `asset_edit`-on-top ordering) — new spec files beside
  `asset.service.spec.ts` / `asset-media.service.spec.ts`; run the server suite subset.
- Client: unit (dual-read v1→v2, save-writes-v2 + deletes-v1, copy/paste tag move, v1 golden
  back-compat) via `swift test --filter EditingTests`; UI tests untouched (still fixture-gated).
- No full-res perf budget is set in Phase 1 (scout risk 9) — rendition upload reuses the existing
  background export path; record timings in the report, do not gate on them.

## Phase 1 work split (two implementers, disjoint files)

- **Server worker:** `server/src/controllers/asset-media.controller.ts` (+ route), new
  `rendition.dto.ts` (or extend `editing.dto.ts`), storage + serving rule, Revert delete,
  red-first specs. Must not touch `native-apple/`.
- **Client worker:** PhotosCore persistence + keys + payloads + `EditHistory` tag + fixtures,
  all five call sites, unit tests. Must not touch `server/`.
- Shared vocabulary (do not rename unilaterally): `rendition`, `edited` file, `.v2` keys,
  "applies on top of the rendition".
- Both: clone to `/tmp`, commit there without push, report commit hash + test evidence.
  VM UI tests stay owner-run; main session merges.
