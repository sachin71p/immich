# Shared Libraries Audit Findings

## Verdict

**Do not deploy this fork to a live family photo server.** Confirmed authorization paths can expose shared-space or external-library assets to a partner or to a contributor after their membership has been removed; a memory can also return linked container assets without checking present membership. Relocation has multiple confirmed paths that can mark work complete while files are missing or duplicated. This was a static audit only: no tests, build, linter, Docker, or migration was run, and the outstanding host coverage leaves several lifecycle and sync claims unproven.

## P0 — confirmed visibility and authorization gaps

| Contract | Location | Finding | Outcome |
|---|---|---|---|
| PERM-11 | `server/src/repositories/access.repository.ts:246` | `checkOwnerAccess` treats every `spaceId IS NULL` asset as personal; it does not exclude `libraryId`, so an owner removed from a shared external library still receives direct asset access. | pending (Task 6) |
| PERM-11 | `server/src/repositories/access.repository.ts:351` | Direct asset-file owner access has no space/library membership condition, leaving a removed contributor able to fetch files of assets they own. | pending (Task 6) |
| PERM-01-nonmember | `server/src/utils/access.ts:119` | `AssetRead` tries partner access before container membership; the partner query lacks the required personal-container restriction and can reveal a partner's space or external-library assets. | pending (Task 6) |
| PERM-04-nonmember | `server/src/utils/access.ts:135` | The same unscoped partner branch grants `AssetShare`, allowing a non-member partner to add a container asset to a shared link. | pending (Task 6) |
| PERM-11 | `server/src/repositories/memory.repository.ts:73` | Memory asset expansion filters only visibility/deletion, not current container membership; a user-owned memory can return previously linked space/library assets after removal. The single-memory path repeats this at line 192. | pending (Task 6) |
| PERM-11 | `server/src/repositories/access.repository.ts:689` (PersonAccess.checkOwnerAccess; audit w1-2:699) | A removed contributor who owns a space person passed the `ownerId = userId` OR branch with no membership gate, retaining person read/update (PersonDelete/Merge, get/update/thumbnail). | FIXED — owner branch gated to `spaceId IS NULL`; space persons require current membership (S9 member branch unchanged). Test: `PERM-11 denies a removed contributor person and face access` in `server/test/medium/specs/repositories/access.repository.spec.ts` (host run pending; SQL-shape probe in sandbox confirms the gate). S9 unit `person-space.spec` 10/10 still pass. |
| PERM-11 | `server/src/repositories/access.repository.ts:717` (PersonAccess.checkFaceOwnerAccess; audit w1-2:727) | A removed contributor who owns an asset passed the `asset.ownerId = userId` OR branch for its space asset's faces with no membership gate, retaining FaceDelete/PersonCreate/PersonReassign. | FIXED — asset leg is now personal-ownership (`ownerId` + `spaceId`/`libraryId` NULL) OR current space membership; library assets keep upstream owner-only scope (see NEEDS-DECISION). Same test as above; S9 `person-space` 10/10 + `person.service` unit 67/67 still pass. |
| PERM-11 | `server/src/repositories/sync.repository.ts:977` (SharedSpaceMemberSync.getDeletes; audit w1-5:977) | A removed space member cannot receive SharedSpaceMemberDeleteV1 because the stream requires a current membership row. | NOT-A-DEFECT — by design: direct member removal fires `shared_space_member_delete_audit`, which writes a user-keyed `shared_space_audit` row, so the removed member receives SharedSpaceDeleteV1 instead (verified trigger + user-keyed getDeletes). Evidence: medium `[SY-03] [SY-04]` (host PASS — leave emits the container delete) + Apple `membershipLoss` fixture test (client drops the space and its assets, keeps personal assets). |
| PERM-11 | `server/src/repositories/sync.repository.ts:1032` (SharedSpaceAssetSync.getRemoves; audit w1-5:1032) | A removed space member cannot receive SharedSpaceAssetRemoveV1 (same membership gate). | NOT-A-DEFECT — same compensation as above: per-asset removes correctly require current membership; the removed member gets the container delete instead. Same evidence. |
| — | `server/src/repositories/sync.repository.ts:1172` (LibraryAssetSync.getRemoves; audit w1-5:1172) | A removed library member cannot receive SharedLibraryAssetRemoveV1 (same membership gate). | NOT-A-DEFECT — `library_member_delete_audit` writes a user-keyed `library_member_audit` row; the removed member receives SharedLibraryDeleteV1. Evidence: medium `[SY-05]` (host PASS) + Apple `libraryDelete` apply (drops library, members, and `asset WHERE libraryId`). |
| PERM-11 | container deletion sync (new finding, Task 2) | Deleting a space or external library wrote NO user-keyed sync tombstones: member rows cascade (`ON DELETE CASCADE`), which skips the member-delete audit trigger via its `pg_trigger_depth()` guard, and no trigger exists on container delete. Members' clients kept showing the deleted container and its assets forever (no delete event; upserts join dead memberships). | FIXED — `SharedSpaceRepository.deleteSpace` and `LibraryRepository.delete` now insert user-keyed audit rows for current members inside the delete transaction (same shape the trigger writes). Tests: `[LC-01] [C3] space deletion emits SharedSpaceDeleteV1 to members` + `[C3] library deletion emits SharedLibraryDeleteV1 to members` in `server/test/medium/specs/sync/sync-container-delete.spec.ts` (host run pending; pre-fix failure mechanism: zero audit rows → user-keyed getDeletes returns empty → no DeleteV1). tsc + eslint clean; space/library/sync unit 90/90 pass. |

## Task 4 — contract outcomes

- **P3 AssetFileDownload / AssetEditGet (audit w1-2:146/197): FIXED.** Both now fall through
  owner → space → library membership (`server/src/utils/access.ts`). Evidence: `access.spec`
  `PERM-01-contributor` / `PERM-03-contributor` tests, 7/7 pass in sandbox.
- **P3 favorites `libraryId` (audit C8, `asset.repository.ts:966`): FIXED.** The time-bucket
  `isFavorite` projection forced `false` for every non-owned asset outside a space; library
  members never saw real favorites. Now `ownerId = me OR spaceId NOT NULL OR libraryId NOT NULL`
  (rows are already scope-filtered; partners never receive library assets per §10). Evidence:
  `[R16]` time-bucket test in `server/test/medium/specs/repositories/shared-container-favorites.spec.ts`
  (host run pending). Server `asset.service` favorite paths untouched.
- **R11 album add/remove (S2 canary support): FIXED at the access and service layers**
  (Viewer role admitted; remove bypasses per-asset share check). Evidence: access + album unit
  specs green in sandbox; upstream `album.e2e-spec` aligned to decided R11; the 5 e2e canary
  specs still need the host run (Task 0).
- **SUSPECTED SharedSpaceMemberUpdate (audit w1-2:306): NOT-A-DEFECT.** The broad entry
  permission fronts two routes, both guarded at the service layer: `transferOwner`
  re-requires owner-only `SharedSpaceDelete` (`shared-space.service.ts:143`, `access.ts:324-326`)
  and rejects non-contributor targets (`:144-146`); `updateMyTimeline` hardcodes `auth.user.id`
  (`:151-154`) and its DTO carries only `showInTimeline` (`shared-space.dto.ts:32`), so neither
  owner-transfer by contributors nor self role-change is reachable.
- **SUSPECTED SharedSpaceMemberDelete (audit w1-2:308): NOT-A-DEFECT.** `removeMember`
  (`shared-space.service.ts:129-140`) requires the target to be a member, blocks removing the
  owner (covers PERM-07-owner leave-denied and owner-removal), and requires the actor to be the
  target or a member. Library member admin stays admin-only (`access.ts:329-332`, PERM-10).
- **OpenAPI `updateMyTimeline` collision (`immich-openapi-specs.json:7922` vs `:14930`): DEFERRED
  to S10's SDK regeneration (owner: S10).** Both `PATCH /libraries/{id}/members/me` and
  `PATCH /shared-spaces/{id}/members/me` share the operationId, so generators emit ambiguous
  suffixed names with flipped meanings per client (TS SDK: `updateMyTimeline` = library,
  `updateMyTimeline2` = space; Apple filtered doc: `updateMyTimeline` = space). The spec JSON and
  `packages/sdk` are generated artifacts (spec from a running server, SDK via `mise //:open-api`;
  both need host DB/toolchain), and the SDK is consumed by web (2 call sites), e2e
  (`timeline-scope.e2e-spec`), and Apple (`SpaceMutations` + generator config) — renaming the
  source now without regenerating would break all three clients. Prescription: rename the
  **space** controller+service methods to `updateMySpaceTimeline` (keeps TS `updateMyTimeline` =
  library stable; the stale `updateMyTimeline2` callers then fail LOUDLY at compile time instead
  of silently flipping meaning), regenerate spec + all SDKs, update web (LibrarySettings,
  space photos page), e2e, and Apple callers + the generator-config comment. Sibling collisions
  (`getMembers`/`addMembers`/`removeMember` shared across spaces/libraries, per the Apple config
  comment) are pre-existing and out of this pass.

## NEEDS-DECISION

1. **Library face/person scope (Task 1 boundary).** The Task 1 fix gates the *space* leg of
   person/face owner access but deliberately leaves the *library* leg at upstream owner-only:
   a removed library member who owns a library asset retains face access to it, and a current
   library member (non-owner) has none. PERM-10 grants library members contributor *asset* rights,
   but face/person management is not in the §4 table; §11 keeps person graphs per-owner and S9
   scopes person sharing to spaces. Neither the member expansion (shared predicate's library
   branch) nor the removal gate was applied to the library leg — both directions would exceed the
   decided contract. Owner decision needed: mirror PERM-11 for libraries (gate + member rights),
   or keep upstream owner-only. The medium test above covers spaces only.

## P1–P2 — confirmed integrity and relocation gaps

| Severity | Contract | Location | Finding | Outcome |
|---|---|---|---|---|
| P1 | I3 | `server/src/services/metadata.service.ts:728` | Motion-asset creation copies `libraryId` but omits the source `spaceId`, so a live-photo pair can be split across containers. | pending (Task 6) |
| P1 | I3 | `server/src/repositories/asset.repository.ts:818` | Live-photo matching is keyed by owner/type/CID without container predicates, allowing halves from different containers to be linked. | pending (Task 6) |
| P1 | I6 | `server/src/services/asset-media.service.ts:179` | Uploading directly into a space writes the staged asset with `spaceId` but creates no relocation row, despite staging needing asynchronous container relocation. | pending (Task 6) |
| P1 | I6 | `server/src/schema/migrations/1789426700279-SharedLibraries.ts:112` | The space foreign key uses `ON DELETE SET NULL`, permitting a container change without the required relocation record. | pending (Task 6) |
| P1 | R17 | `server/src/services/library.service.ts:346` | Upload-path containment is prefix-only; a normalized path such as `/allowed/../outside` passes although it is outside the import path. | pending (Task 6) |
| P1 | R17 | `server/src/services/storage-template.service.ts:363` | Template root validation is prefix-only, so a sibling whose name starts with the root can escape its assigned container tree. | pending (Task 6) |
| P1 | I4 | `server/src/cores/storage.core.ts:255` | A non-EXDEV rename error is logged and returned rather than propagated, enabling callers to continue after the original file did not move. | pending (Task 6) |
| P1 | I6 | `server/src/services/storage-template.service.ts:275` | Template relocation suppresses `moveFile` failures, allowing the relocation workflow to finish its row after a failed move. | pending (Task 6) |
| P1 | I7 | `web/src/lib/components/asset-viewer/AssetViewerNavBar.svelte:203` | Space/library members are offered the Locked visibility action for container assets, contrary to the invariant (server rejection was not rechecked in this client-only review). | FIXED — server rejects with a clean 400 (`BadRequestException('Shared assets cannot be locked')` in both `update` and `updateAll`; DB CHECK `asset_container_not_locked` backstops), and the UI no longer offers the toggle on container assets (new `isPersonalAsset` gate). Tests: `[I7]` update/updateAll rejections in `asset.service.spec` (78/78 pass); `isPersonalAsset` in `asset-permissions.spec` (11/11 pass). Web tsc + svelte-check clean; web eslint environmentally crashed (pre-existing tscompat/TS6 issue, reproduces on untouched files). |
| P2 | I4 | `server/src/cores/storage.core.ts:274` | After copy-and-verify on EXDEV, failure to unlink the old file is only logged; the new path and move record are finalized, leaving an unmanaged original outside the container tree. | pending (Task 6) |
| P2 | I4 | `server/src/cores/storage.core.ts:290` | Destination-only crash recovery stats the missing old path before using known asset data, preventing recovery of a completed copy after a crash. | pending (Task 6) |

## Coverage gaps

- T1 is in progress and the coverage gate is still missing `R13-04`, `W-01`, `W-02`, and `W-09` (already tracked in `STATUS.md`); host Docker coverage has not closed these cases.
- `S1`, `S3`, `S4`, `S5`, `S6`, and `S7` are marked complete even though their corresponding verifier records show required full and/or Docker verification was stopped, blocked, or not run. `S3` additionally records unresolved suite failures.
- `A0`, `A2`, and `A3` verifier records each show a required verification entry point did not run; `A4`–`A9` have no `-verify.md` handoff despite being marked complete. Later `STATUS.md` host-run claims may be true, but they are not supported by matching verifier records.
- No additional R1–R17 requirement was established as having neither implementation nor test during this bounded audit. The unverified T1 matrix remains the substantive requirement-level gap.

## Remaining work — deployment order

1. Fix and regression-test every P0 access path, including read, file download, sharing, memory, partner, and post-removal cases.
2. Prove membership-removal sync behavior end to end. `shared_space_member` deletion is filtered by current membership in `server/src/repositories/sync.repository.ts:977`; the targeted review could not establish a reliable compensating `SharedSpaceDeleteV1`. Library removal may have a separate member-audit route and needs the same end-to-end proof.
3. Fix relocation error propagation, EXDEV cleanup/recovery, containment checks, live-photo container propagation, and every I6 relocation-row bypass; exercise crash and filesystem-failure cases on a host.
4. Complete T1 and the coverage gate, then run the required host Docker tiers and upgrade gate. Do not use sandbox-only checks as release evidence.
5. Regenerate and review OpenAPI/SDK/SQL artifacts after the pending S10 work; the client review also found duplicate OpenAPI operation identity for `updateMyTimeline` at `open-api/immich-openapi-specs.json:14930`.

## Re-verification (Task 0 baseline, 2026-09-15 sandbox run + host-deferred tiers)

Verdict: **unchanged — do not deploy.** The remediation pile is partially verified:
non-controller unit is green (including every touched suite), but controller unit,
medium, e2e, and the lint gate all need a host run or owner triage (details below).

### What ran (sandbox, this session)

| Suite | Command | Result |
|---|---|---|
| server typecheck | `cd server && pnpm run check` | PASS (`tsc --noEmit`, exit 0) |
| e2e typecheck | `cd e2e && pnpm run check` | PASS (covers the staged R11 spec renames) |
| e2e lint | `cd e2e && pnpm run lint` | PASS |
| server unit, all touched suites | vitest `--run` on `path`, `access`, `fork-rules-cases`, `preferences`, `container-scope` specs + `album`, `asset-media`, `asset-relocation`, `library`, `metadata`, `storage-template` service specs | 503/503 PASS (67 util + 436 service) |
| server unit, full minus controllers | vitest `--run --exclude '**/controllers/**'` | 80 files / 2190 tests PASS, 0 failures |
| server unit, full | vitest `--run` (115 files, 2422 tests) | 2195 pass / 226 fail / 1 expected-fail. Every failure is a `listen EPERM: operation not permitted 0.0.0.0` from supertest-based `src/controllers/**` specs — the sandbox forbids `listen(2)`. No `AssertionError` in 3 consecutive runs (one transient `TypeError: reading 'port'` seen once, an EPERM-adjacent supertest artifact, not reproduced since). |
| new medium specs (C1/C2/C5 evidence) | `access.repository.spec.ts`, `shared-container-integrity.spec.ts` (+ touched `shared-libraries-schema.spec.ts`) | NOT RUN (see below); `tsc` + `eslint --max-warnings 0` clean on all three |
| S2 album e2e canary (5 specs, STATUS.md S2 row) | host `scripts/fork-test/run.sh e2e-api` | NOT RUN (see below); `e2e` tsc+lint clean. Tree already aligns 3 of the 5 to decided R11 (`should be able to add assets to album as a viewer`, `should be able to remove foreign asset from shared album as a member`, `should be able to remove assets from album as a viewer`) plus the `access.ts` R11 + `AssetFileDownload`/`AssetEditGet` member-access changes; the other 2 (owner-denied, role-change message per the S2 row) ride the same host run. |

### One real baseline failure found and fixed

`server/src/dtos/search.dto.spec.ts` `[R8-04]` (2 tests) failed on genuine
assertions, not EPERM: it passed `personalOnly: 'true'`/`'false'` (strings) while
the committed contract (a573f1eed, "R8-04 personalOnly … use native booleans …
matches neighboring fields and the validation.ts contract for body params") requires
native booleans. The spec was stale, not the code. Fixed the spec to `true`/`false`
— 2/2 pass, spec+DTO eslint clean. Full-suite failures dropped 228 → 226, exactly
the 2 fixed tests; nothing else moved.

### Pre-existing lint gate state (not caused by the remediation pass)

Full `cd server && pnpm run lint`: 22 errors, **all on lines/files byte-identical to
HEAD** (verified via `git show HEAD:`) — the pass introduced zero lint errors, but the
gate is red. Breakdown: 8× `import-x/order` around `container-scope.js` imports in
unmodified files (`map.repository`, `trash.repository`, `services/index`,
`memory.service`, `shared/user-methods`, `trash.service`, `user.service`,
`container-scope.spec`); 2× `unicorn` in untouched `ContainerScopeService.resolve`
lines; 9× in T0-era `test/fork-fixtures/generate.ts`; 2× `no-useless-undefined` in
`test/medium/specs/fork/asset-relocation.spec.ts`; 1× `consistent-function-scoping`
in `server/src/services/library-upload-path.spec.ts`. Left untouched (autofix would
rewrite unrelated files, e.g. an `eqeqeq` in the fixture generator) — needs an owner
decision, not a drive-by fix.

### NOT RUN — host required (sandbox blocks: no `listen(2)`, no Docker daemon)

- `src/controllers/**` unit (226 tests): sandbox EPERM, needs any host.
- M medium incl. the 2 new specs: `docker info` fails in sandbox; needs host Docker.
- E e2e-api incl. the 5 S2 album canary specs: needs host Docker + `run.sh e2e-api`.
- No host tiers have run since the remediation pile landed, so C1/C2/C4–C7 stay
  "code looks correct", and the C3 audit path stays unverified, until the host runs.

## Contradictions in plan documentation

- `STATUS.md` describes the S0 base as v3.1.0, while this audit brief describes upstream base `e55ac299a` as v3.2.0 plus 98 commits.
- `TESTING.md` §8 says phases with server-behavior tiers not run must remain awaiting a host run, but `STATUS.md` marks several such phases complete while their verifier records say those tiers were blocked or not run.
- `STATUS.md` records S10 as pending OpenAPI/SQL regeneration, while the checked-in OpenAPI spec already has an operation-ID collision; the plan gives no single artifact-regeneration state that reconciles those facts.
