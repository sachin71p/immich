# Shared Libraries Audit Findings

## Verdict

**Do not deploy this fork to a live family photo server — unchanged after remediation.**
Every P0/P1/P2 finding now has a fix with a named regression test (see the Outcome columns),
and the sandbox-verifiable tiers are green (server + e2e typecheck, full non-controller unit
2190+ tests, all touched suites, web tsc + svelte-check). But the host-only tiers that prove
the fixes — controller unit (sandbox EPERM), medium (new PERM-11/C3/R16/I6/I7 tests), the 5
S2 album e2e canary specs, and the full e2e-api/medium suites over the touched engine code —
have not run since the fixes landed. One NEEDS-DECISION (library face/person scope) and one
DEFERRED item (OpenAPI rename → S10 regen) remain open. The verdict flips only on host runs.

## P0 — confirmed visibility and authorization gaps

| Contract | Location | Finding | Outcome |
|---|---|---|---|
| PERM-11 | `server/src/repositories/access.repository.ts:246` | `checkOwnerAccess` treats every `spaceId IS NULL` asset as personal; it does not exclude `libraryId`, so an owner removed from a shared external library still receives direct asset access. | FIXED — owner branch routed through `withPersonalOwnershipOrCurrentContainerMembership` (commit `4337fe52a`). Evidence: medium `PERM-11 denies a removed contributor direct asset, asset-file, and memory access` (host run pending); tsc + eslint clean. |
| PERM-11 | `server/src/repositories/access.repository.ts:351` | Direct asset-file owner access has no space/library membership condition, leaving a removed contributor able to fetch files of assets they own. | FIXED — same predicate (`4337fe52a`); covered by the same medium PERM-11 test (asserts file ids denied after removal). |
| PERM-01-nonmember | `server/src/utils/access.ts:119` | `AssetRead` tries partner access before container membership; the partner query lacks the required personal-container restriction and can reveal a partner's space or external-library assets. | FIXED — partner query requires `spaceId IS NULL AND libraryId IS NULL` (`4337fe52a`). Evidence: medium `PERM-01-nonmember denies partner access to space and library assets` (host run pending). |
| PERM-04-nonmember | `server/src/utils/access.ts:135` | The same unscoped partner branch grants `AssetShare`, allowing a non-member partner to add a container asset to a shared link. | FIXED — same partner-query gate as above (`4337fe52a`); same medium test asserts share-link denial. |
| PERM-11 | `server/src/repositories/memory.repository.ts:73` | Memory asset expansion filters only visibility/deletion, not current container membership; a user-owned memory can return previously linked space/library assets after removal. The single-memory path repeats this at line 192. | FIXED — both sites routed through the predicate (`4337fe52a`). Evidence: same medium PERM-11 test asserts `memory.get`/`memory.search` return empty assets after removal (host run pending). |
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

## Task 5 — review outcomes

- **Storage-template batch `Success` after per-asset failures: INTENDED, already tested.**
  `handleMigration` (batch) catches per-asset errors, logs them with asset id + stack
  (`storage-template.service.ts:214-216`), continues, and reports overall `Success` (`:225`).
  That is the upstream batch-resilience pattern (one bad asset must not abort a full-library
  migration), and the C7 fix changed what flows into it: move failures now THROW instead of
  completing rows silently. The per-asset job (`handleMigrationSingle`) still reports `Failed`.
  Evidence: `should not update the database if the move fails due to incorrect newPath
  filesize` asserts batch `Success` with no DB write on a failed move.
- **Migration amended in place: documented.** `1789426700279-SharedLibraries.ts` gained FK
  `RESTRICT` + both CHECKs after landing; the amended bytes never ran anywhere. Added a
  "Migration re-run" note to `FORK.md` (fresh database only, no repair path). E2e/medium
  always migrate from scratch, so host tiers are unaffected.

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

   **RESOLVED 16-Sep (owner decision §3a: gate only, grant refused).** Gate FIXED — the library
   owner leg of `checkFaceOwnerAccess` now additionally requires current library owner-or-membership
   (the shared predicate's library-branch EXISTS shape), so a removed member who owns a library asset
   loses face access to it; a current non-owner member still gets nothing. `checkOwnerAccess` is
   unchanged owner-only (person rows carry no `libraryId`, so a gate there is vacuous). Evidence:
   medium test `PERM-11 denies a removed library member face access to owned library assets`
   (`server/test/medium/specs/repositories/access.repository.spec.ts`; host run pending).
   Grant NOT-A-DEFECT — face/person rights follow cluster-group membership, not container membership
   (DECISIONS §4/§11): external libraries have no `clusterGroupId`, so a membership grant would expose
   the owner's entire personal face graph; the supported cross-user mechanism is the upstream
   cluster-group-request flow (`cluster-group.service.ts`). Interaction coverage:
   `server/test/medium/specs/repositories/cluster-group-interaction.spec.ts` (host run pending).

## P1–P2 — confirmed integrity and relocation gaps

| Severity | Contract | Location | Finding | Outcome |
|---|---|---|---|---|
| P1 | I3 | `server/src/services/metadata.service.ts:728` | Motion-asset creation copies `libraryId` but omits the source `spaceId`, so a live-photo pair can be split across containers. | FIXED — motion creation carries `spaceId` (commit `d2f0b7de6`). Evidence: metadata unit spec green in sandbox (117 tests); medium `[I3]` container-matching tests (host run pending). |
| P1 | I3 | `server/src/repositories/asset.repository.ts:818` | Live-photo matching is keyed by owner/type/CID without container predicates, allowing halves from different containers to be linked. | FIXED — match query container-scoped (`libraryId`/`spaceId` equality, commit `2951462e2`). Evidence: medium `[I3]` cross-container mismatch tests (host run pending). |
| P1 | I6 | `server/src/services/asset-media.service.ts:179` | Uploading directly into a space writes the staged asset with `spaceId` but creates no relocation row, despite staging needing asynchronous container relocation. | FIXED — space uploads and sidecar-carrying personal uploads create a relocation row before metadata extraction (commit `d2f0b7de6`). Evidence: `[I6]`/`[R17-01]` upload unit tests green in sandbox (asset-media 139 tests). |
| P1 | I6 | `server/src/schema/migrations/1789426700279-SharedLibraries.ts:112` | The space foreign key uses `ON DELETE SET NULL`, permitting a container change without the required relocation record. | FIXED — FK amended to `RESTRICT` (+ table mirror, commit `654e37c9f`; fresh-DB-only, see FORK.md). Evidence: medium `[I6] refuses to delete a space that still holds assets` (host run pending). |
| P1 | R17 | `server/src/services/library.service.ts:346` | Upload-path containment is prefix-only; a normalized path such as `/allowed/../outside` passes although it is outside the import path. | FIXED — containment via resolved realpath checks (`isResolvedPathInside`, commit `d2f0b7de6`). Evidence: library unit spec green in sandbox (73 tests); path/rules unit specs green. |
| P1 | R17 | `server/src/services/storage-template.service.ts:363` | Template root validation is prefix-only, so a sibling whose name starts with the root can escape its assigned container tree. | FIXED — boundary-checked containment (commit `c0e236b76`). Evidence: storage-template unit spec green in sandbox (33 tests). |
| P1 | I4 | `server/src/cores/storage.core.ts:255` | A non-EXDEV rename error is logged and returned rather than propagated, enabling callers to continue after the original file did not move. | FIXED — `moveFile` throws on rename/size/unlink failures (commit `c0e236b76`). Evidence: `[I4]` propagation test green in sandbox. |
| P1 | I6 | `server/src/services/storage-template.service.ts:275` | Template relocation suppresses `moveFile` failures, allowing the relocation workflow to finish its row after a failed move. | FIXED — failures propagate; the batch job logs-and-continues per asset by design (see Task 5 review; commit `c0e236b76`). Evidence: filesize-mismatch batch test asserts `Success` with no DB write. |
| P1 | I7 | `web/src/lib/components/asset-viewer/AssetViewerNavBar.svelte:203` | Space/library members are offered the Locked visibility action for container assets, contrary to the invariant (server rejection was not rechecked in this client-only review). | FIXED — server rejects with a clean 400 (`BadRequestException('Shared assets cannot be locked')` in both `update` and `updateAll`; DB CHECK `asset_container_not_locked` backstops), and the UI no longer offers the toggle on container assets (new `isPersonalAsset` gate). Tests: `[I7]` update/updateAll rejections in `asset.service.spec` (78/78 pass); `isPersonalAsset` in `asset-permissions.spec` (11/11 pass). Web tsc + svelte-check clean; web eslint environmentally crashed (pre-existing tscompat/TS6 issue, reproduces on untouched files). |
| P2 | I4 | `server/src/cores/storage.core.ts:274` | After copy-and-verify on EXDEV, failure to unlink the old file is only logged; the new path and move record are finalized, leaving an unmanaged original outside the container tree. | FIXED — unlink failure throws (commit `c0e236b76`). Evidence: storage-template crash-recovery unit tests green in sandbox. |
| P2 | I4 | `server/src/cores/storage.core.ts:290` | Destination-only crash recovery stats the missing old path before using known asset data, preventing recovery of a completed copy after a crash. | FIXED — recovery prefers known asset data (`oldStat` skipped when `assetInfo` present, commit `c0e236b76`). Evidence: recovery unit tests green in sandbox. |

## Coverage gaps

- T1 is in progress and the coverage gate is still missing `R13-04`, `W-01`, `W-02`, and `W-09` (already tracked in `STATUS.md`); host Docker coverage has not closed these cases.
- `S1`, `S3`, `S4`, `S5`, `S6`, and `S7` are marked complete even though their corresponding verifier records show required full and/or Docker verification was stopped, blocked, or not run. `S3` additionally records unresolved suite failures.
- `A0`, `A2`, and `A3` verifier records each show a required verification entry point did not run; `A4`–`A9` have no `-verify.md` handoff despite being marked complete. Later `STATUS.md` host-run claims may be true, but they are not supported by matching verifier records.
- No additional R1–R17 requirement was established as having neither implementation nor test during this bounded audit. The unverified T1 matrix remains the substantive requirement-level gap.

## Remaining work — deployment order

1. ~~Fix and regression-test every P0 access path~~ — DONE in remediation (P0 table Outcomes; commits `4337fe52a`, `7b77c2860`, `914d25258`, `2951462e2`). Host runs still pending.
2. ~~Prove membership-removal sync behavior end to end~~ — DONE (member-removal compensation verified via SY-03/04/05 + Apple fixture; container-deletion tombstones added with [LC-01]/[C3] tests, commit `d93fc777d`). Host medium run still pending.
3. ~~Fix relocation error propagation, EXDEV cleanup/recovery, containment checks, live-photo container propagation, and I6 relocation-row bypasses~~ — DONE (P1–P2 table Outcomes; commits `c0e236b76`, `d2f0b7de6`, `654e37c9f`). Crash/filesystem cases still need a host (brief C7 explicitly requires non-mock exercise).
4. Complete T1 and the coverage gate, then run the required host Docker tiers and upgrade gate. Do not use sandbox-only checks as release evidence. — STILL OPEN (host-owned).
5. Regenerate and review OpenAPI/SDK/SQL artifacts after the pending S10 work — STILL OPEN (S10-owned); the regen must carry the `updateMyTimeline`→`updateMySpaceTimeline` rename (remediation DEFERRED, see Task 4).

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

## Re-verification (session close, 16-Sep, sandbox + 13 commits)

Session commits (oldest first): `670202347` (Task 0 baseline), `4337fe52a` (pile C1/C2),
`7b77c2860` (Task 1 person/face), `d93fc777d` (Task 2 tombstones), `441294e6c` (Task 3
Locked UI), `914d25258` (P3+R11 access), `373859597` (R11 service+e2e), `2951462e2` (R16
favorites), `c0e236b76` (G1 engine), `d2f0b7de6` (G2 guards), `654e37c9f` (schema
amendment), `aa7923248` (e2e harness), `f3455c46a` (C5 integrity spec). The host also
committed `8c9a00a38` (e2e fixes) mid-session; the branch is shared and moving — verify
`git log` before host runs.

Final sandbox state: server `tsc` clean, e2e `tsc`+`lint` clean, web `tsc` + `svelte-check`
(0 errors) clean, full non-controller unit **80 files / 2197 passed / 0 failed** (Task-0
baseline was 2190; +2 are the new `[I7]` asset tests, +5 unattributed across untouched
suites — zero failures in both runs, all touched suites individually re-verified). The 226
controller failures remain pure sandbox `listen EPERM`. Server full lint still shows the 22
pre-existing errors (byte-identical to HEAD — owner decision needed); web lint crashes on the
pre-existing tscompat/TS6 incompatibility (reproduces on untouched files). `pnpm` wrapper
commands intermittently trip a no-TTY modules-purge self-check in this sandbox (host-side
`node_modules` drift suspected); direct `node_modules/.bin` binaries work and no collateral
was left (lockfiles untouched).

Host backlog (nothing below has run since the fixes landed): controller unit (any host),
`run.sh medium` (new PERM-11/C3/R16/I6/I7 tests + re-runs for S3/S4/S6/S9 engine areas),
`run.sh e2e-api` (5 S2 canary specs + full fork suite), coverage gate (R13-04/W-01/W-02/W-09
still T1-owned), S10 regen carrying the opId rename, real crash/filesystem exercise (C7
brief demand). New-test tags `[R16]`/`[C3]`/`[I6]`/`[I7]`/unbracketed `PERM-11` are
intentionally invisible to the coverage gate (matrix has no such sub-cases); `[LC-01]` and
`[R16-04]`-adjacent tags ride existing IDs.

## Upstream reconciliation (merge `a64fced5d`, 16-Sep)

`v3.2.0` is now an ancestor of the branch (merge-base was `e61312084`,
v3.2.0-rc.0). `git cherry HEAD v3.2.0 e61312084` showed **35 of the 40**
delta commits were already present via main-line originals the fork had
picked up after branching — the merge's only new content is the
release-line version bumps plus the resolutions below. No migration
changes on either side beyond the fork's own two; schema gap: none.

What merged cleanly: all 35 already-present commits (no-op), the four
version-bump commits (tree already at 3.2.0 everywhere), the maplibre-gl
v6 backport `163d3c71f` (main-line `68e340930` already in HEAD; identical
`setWorkerUrl` hunk auto-merged).

What conflicted (9 files) and how each bolded collision was resolved:
- `d66756fca` (untracked-file unlink race) — COVERS, no resolution
  needed. The fix is integrity-subsystem-only (`getTrackedPaths` + three
  `integrity.service.ts` guards); its original `c1f2756f6` is an
  ancestor. C7's `moveFile` rewrite is disjoint (move-registry paths);
  layering a tracked-path check onto `unlink(oldPath)` would block every
  EXDEV move. No conflict occurred in these files.
- `8139af6e0` (cross-user face move on merge) — COVERS. Fork
  `reassignFaces` already holds the fix verbatim + the S9 `spaceId` leg;
  the upstream regression tests are already in the fork medium spec,
  adapted to bulk `mergePeople` (first id wins per scope). One conflict
  hunk in `person.repository.ts` resolved by keeping the fork hunk whole
  (reasoning comment added); the spec's `mergePerson`-vs-`mergePeople`
  hunk resolved to `mergePeople` with an equivalence comment. No test
  port was needed — the scout's port prescription was voided on
  inspection (fork `7b51c50a9` already covers both upstream cases).
- `bf75aaa81` (partner timeline) — COVERS, zero-byte cherry-pick of
  `040ae6bc0` in HEAD. No conflict.
- `583243901` (live-photo transcode visibility) — COVERS, zero-byte
  cherry-pick of `58fb1ed4a` in HEAD. No conflict, no SQL regen.
- Mechanical, fork-side-kept throughout: ESM `.js`-suffix imports
  (`asset-job.repository.ts`, `mappers.ts`, medium spec);
  `people_picker.dart` kept `Store.people.all()` (fork `6874c07db`
  refactor) over the removed provider name; `pnpm-lock.yaml` kept the
  fork's svelte 5.56.10 peer variant (2 hunks); `search-bar-utils.ts`
  kept both fork filter helpers and upstream `isPopoverContent`;
  both-added spec files resolved to the fork supersets (verified to
  contain upstream's tests verbatim).
- Correction to the brief's table: `d66756fca` never touched
  `storage.core.ts`, so the "highest risk" C7 collision was a
  non-collision; the only functional upstream delta (`163d3c71f`) was
  already applied.

Sandbox re-verification of the merged tree: see `## Re-verification`
(session-merge entry to follow).

## Re-verification (reconcile + §§3a–3c, 16-Sep — sandbox unblocked)

Verdict: **unchanged — do not deploy.** But the evidence base moved
substantially: the sandbox's Docker daemon and loopback network now work
(both were hard-blocked at audit time), so the medium tier, the DB-backed
§3a/§3c evidence, and the full controller set ran for real. e2e-api,
coverage, upgrade/S10, and the C7 filesystem exercise still need a host.

Sandbox runs (measured at `a64fced5d` for the merge, `39199677c` after
§§3a–3c; three verifier passes, all read-only, lockfiles untouched):
- Merge tiers: server tsc PASS, e2e tsc+lint PASS, web tsc + svelte-check
  0/0 PASS, non-controller unit 80 files / 2199 passed / 0 failed —
  NO-WORSE-THAN-BASELINE at `a64fced5d`.
- Final tiers at `39199677c`: all of the above green plus server lint
  **0 errors / 0 warnings** (post-§3b gate green) and non-controller unit
  80 / 2199 / 0.
- Full medium tree (`test:medium`, testcontainers Postgres, real
  migrations incl. ClusterGroups/SharedLibraries/SpacePeople): **72/74
  files, 645 passed / 2 failed / 22 skipped**. Both failures are known
  ENV/harness, not product: `audio-video.spec.ts` ffmpeg golden drift
  (`keyframeAccDuration` off by tens) and `workflow-core-plugin.spec.ts`
  setup error (wasm missing, `mise` absent in sandbox) — both match the
  prior triage classification. Every fork, repository, service, and sync
  spec is green.
- Full controller unit: **35 files / 231 passed + 1 expected-fail, zero
  failures, zero `listen EPERM`** across two runs — the sandbox network
  block is lifted.
- §3a gate evidence (real DB runs, not pending): PERM-11 spaces + partner
  + **new library sibling
  `PERM-11 denies a removed library member face access to owned library
  assets`** 4/4 in `access.repository.spec.ts`; person merge tests
  (`should merge people of multiple users`,
  `should not merge into person another user does not have`) inside
  medium `person.service.spec.ts` 21/21 (S9 re-run 1 of 3 done);
  person-space 10/10 + person.service unit 67/67 in sandbox (S9 re-run
  2 of 3 done); `person.e2e-spec` 16/16 still host-owned (S9 re-run 3).
- §3c evidence: `cluster-group-interaction.spec.ts` 1/1 PASS (real run,
  re-confirmed) — no duplicates, no leaks, naming independent; no S9
  bypass found. S9-adjacent medium: `[LC-01]/[C3]` container-delete 2/2,
  `[I6]/[I7]` integrity 2/2, `[R16]` favorites 1/1.
- Sandbox caveat (do not over-read): the §3c PASS and medium greens ran
  against sandbox Postgres; the host medium re-run still owns release
  confirmation, and `searchFaces` in the §3c test needs vchord in the
  host template DB.

Still host-only (nothing below has run anywhere since the fixes landed):
controller verdict already closed in sandbox; remaining are the 5 S2
album canary specs (upstream `album.e2e-spec.ts`, R11-aligned — run
FIRST, stop on regression), full fork `run.sh e2e-api` (both templates),
`run.sh medium` re-run for S3/S4/S6/S9 engine areas, coverage gate
(R13-04/W-01/W-02/W-09 still T1-owned; new PERM-11/[C3]/[R16]/[I6]/[I7]
tags deliberately invisible to the matrix — matrix-gain decision open),
`run.sh upgrade`/S10 carrying the `updateMyTimeline`→
`updateMySpaceTimeline` rename + SQL/OpenAPI regen (incl. the now-stale
`access.repository.sql` from the §3a gate), and the C7 real crash /
two-filesystem exercise (EXDEV recovery, partial-copy resumption, unlink
propagation — unit mocks do not prove these).

Open non-blockers carried forward: the 5 unattributed unit tests (2197
vs 2190; scout could not reproduce a 2190 full-tree baseline — needs the
§3c scope/baseline-commit to close exactly); web eslint still crashes
environmentally (tscompat/TS6, untouched files).

## Contradictions in plan documentation

- ~~`STATUS.md` describes the S0 base as v3.1.0, while this audit brief describes upstream base `e55ac299a` as v3.2.0 plus 98 commits.~~ — RESOLVED 16-Sep: `git describe` gives `v3.1.0-379-ge55ac299a`; S0 row corrected to the describe output (package 3.2.0 is the dev version, not a tag).
- `TESTING.md` §8 says phases with server-behavior tiers not run must remain awaiting a host run, but `STATUS.md` marks several such phases complete while their verifier records say those tiers were blocked or not run. — ACKNOWLEDGED, not re-marked: remediation appended explicit host re-run notes to the S2/S3/S4/S5/S6/S9/T0 rows it touches (the fixes invalidate prior host greens for those areas) and leaves phase-status decisions to the host owner.
- ~~`STATUS.md` records S10 as pending OpenAPI/SQL regeneration, while the checked-in OpenAPI spec already has an operation-ID collision; the plan gives no single artifact-regeneration state that reconciles those facts.~~ — RESOLVED 16-Sep: collision recorded as DEFERRED with a rename prescription (see Task 4); S10 row now notes the regen must carry it.

## Re-verification (host, 16-Sep — `run.sh all upgrade --template both`, report 20260916-012553)

Ran at HEAD `e01b0c856` (`final`, feat/shared-libraries; log e01b0c856/a0d19cf01/6167df212/c7bca38c8/3229d34cd).
`git rev-parse @{u}` fails — no upstream branch, nothing pushed. Tree at run time was dirty
(`AM Makefile`, `M mise.lock`, `M native-apple/project.yml`, `? e2e/test-assets`); results are
attributed to `e01b0c856` plus that dirt. Full log: `/tmp/gate-full-20260916-012553.log` (5188 lines);
aggregate: `e2e/.fork-report/20260916-012553.md`.

§0 split NOT DONE: `f6bd80b62` still mixes `AUDIT-FINDINGS.md` docs with the R4-01 fix
(`metadata.service.ts`, `metadata.service.spec.ts`, `moves.e2e-spec.ts`) and sits 10 commits deep
with a later R4-01 follow-up (`4a3e65308`) built on it. No upstream exists so a rebase would be
locally safe, but the gate below is red, which dominates — splitting is deferred until the tree
is green and the history is being prepared for push.

§1 prerequisites (proof): `packages/plugin-core/dist/plugin.wasm` 2522844 bytes, mtime Sep 16 00:32;
`mise` present at `/opt/homebrew/bin/mise` (2026.9.9). `ffprobe` resolves to
`/opt/homebrew/bin/ffprobe` **9.0.1 Homebrew — NOT the pinned `jellyfin-ffmpeg 7.1.3-6`**.
Per the brief §1 this is a host-setup problem to fix, not a result to waive; the two
`upstream-medium` audio-video failures (`eiffel-tower.mp4`, `train.mov`) are suspect on exactly
this ground. Docker Desktop was up (fork-stack tiers ran).

Canary (§2a): upstream `album.e2e-spec.ts` 40/40 PASS including the 5 R11/S2 specs (prior
standalone result at an older HEAD `e3dd5532d`, not re-run on this tree — STOP not triggered,
but treat as stale, not as fresh canary evidence). Note: the gate's `upstream-e2e` album FAIL
is DB-infra (`ECONNREFUSED 5435`), not an authorization regression.

Per-tier (§2b/§2c; **never PASS for a tier that did not run**):

- unit: PASS — 115/115 files, 2437 passed + 1 xfail.
- unit-web: FAIL — 42/23 files fail at import (`localStorage` TypeError); 359 runnable passed.
  Root cause (env vs regression) needs owner triage.
- medium: PASS — 2/2 suites, 4/4.
- e2e-api: FAIL — 2 failed tests (`moves` R4-01 personal-move identity; `world` R17-03 auditDisk
  orphans) across 2 files; S9 person re-run inside this tier PASS 8/8 files, 75 passed/1 skipped.
- e2e-web: FAIL — 48 passed / 1 failed / 1 skipped of 50 (album map-view Map-marker `toBeVisible`,
  not retried standalone — possibly flaky, unconfirmed).
- apple: FAIL — 129 tests / 18 suites, 3 issues (Editing copy/paste `keyNotFound` adjust;
  UploadQueue SHA1 `abc`; SearchTests `localLocationFavoriteTypeAndSize`).
- upstream-medium: FAIL — 1/73 files, 2 failed / 667 passed (audio-video goldens, see ffprobe note).
- upstream-e2e: FAIL — 33/1 files, 9 failed / 2 passed / 469 skipped; collapse is DB-infra
  (connection refused/terminated), NOT a true upstream run on the correct `/data` stack — that run
  is still owed (needs stack swap + long serial run).
- coverage: FAIL — matrix 85 cases, 82 tagged; MISSING all S10: `INV-02`, `INV-03`, `UP-01`.
- upgrade + openapi-diff: NOT RUN — `run.sh:128 `keep[@]` unbound variable` crash under bash 3.2;
  INV-02/INV-03/UP-01 have zero evidence.

Downgrades: any `FIXED` claim touching R4-01 relocation identity, R17-03 audit orphans, unit-web
imports, or audio-video goldens does not survive this host run — all four fail here.

§2d coverage-matrix decision: matrix (85/82, S10 trio missing) cannot be accepted as-is; S10 tests
are owed. The invisible-tag question (`[C3]`, `[R16]`, `[I6]`, `[I7]`, unbracketed `PERM-11`) is
left OPEN for the owner — a test the gate cannot see can silently disappear, so either the matrix
gains them or the tests are retagged; no silent third option.

§2e S10 regen: NOT DONE. §2f C7 two-filesystem exercise: NOT RUN (no automated coverage; still owed).

Verdict: **do not deploy.** Conjunction status: canary-green YES (stale HEAD) / no-failing-fork NO
/ INV-02·INV-03-green NO (never ran) / S9-rerun-green YES (8/8). Anything short of all four is red,
and this is short by two plus a red fork tier. Runner fixes recommended before re-run: bash-3.2-safe
`keep` array at `run.sh:128`, `stack_up` before the upstream tier, `--maxWorkers=1` + `/data` stack
for the upstream tier, bracket tags for S10 shell gates.

## Re-verification (host, 16-Sep, second pass — HEAD `464f9122b`, no fresh tiers)

HEAD is now `464f9122b` (`final`, feat/shared-libraries; tree clean except untracked `e2e/test-assets`;
no upstream branch). The gate report 20260916-012553 ran at dangling `e01b0c856`+dirt, and `e01b0c856`
is not an ancestor of HEAD (merge-base `a0d19cf01`). Diff `e01..HEAD` is 4 files (this findings record,
103-line `Makefile`, `mise.lock`, `project.yml`); the functional code the tiers exercise — email layouts,
native-apple connection/tests — is identical between the two. So the red tier failures carry over by
inspection, but HEAD itself has zero fresh tier evidence: **no host tier ran this session**, and the
re-run the new HEAD requires is still owed. Canary remains the stale 40/40 PASS at `e3dd5532d`.

§2f ESM (verified inline, not just via sweep): the email fix is effective. The remaining `require(...)`
hits (`immich.layout.tsx:19`, `futo.layout.tsx:32`) go through `const require =
createRequire(import.meta.url)` (`node:module`), so `require` is defined and the
`ReferenceError: require is not defined` crash is gone — converting them to static default imports
would be cosmetic strictening, not a fix. `__dirname`/`__filename`: 0 hits in `server/src/emails`.
Email render was green at e01 (unit `renderEmail` asserts) and the layouts are byte-identical at HEAD,
so that evidence applies but is stale; an end-to-end `NotifyAlbumInvite` render on a live stack has
still never been observed.

§1 correction: the pinned `ffprobe` 7.1.3-6 **does exist on this host** at
`~/.local/share/mise/installs/github-jellyfin-jellyfin-ffmpeg/7.1.3-6/ffprobe` — only the bare-PATH
resolution is wrong (Homebrew 9.0.1 wins). Next gate must run under the mise toolchain (`mise exec` /
mise shims first on PATH) so the pinned binary resolves; that may clear the two audio-video golden
failures without touching goldens.

Verdict: **do not deploy** (unchanged). Conjunction: canary-green stale-YES / no-failing-fork NO /
INV-02·INV-03-green NO (never ran) / S9-rerun-green stale-YES. Prior downgrades (R4-01, R17-03,
unit-web imports, audio-video goldens) stand. Still owed for a flip: fresh full gate on this HEAD
with mise-PATH ffprobe, true upstream-e2e on `/data`, S10 regen + INV-02/INV-03, live-email render,
C7 exercise, and the f6bd80b62 split at push-prep time.

## Re-verification (host, 16-Sep, third pass — flip attempt; still NO-FLIP, blockers narrowed)

Program: 7 parallel fix tracks (runner, r4-01, r17-03, unit-web, apple, s10, c7) + a
conditional gate. HEAD still `464f9122b`; tree is dirty (~30 files, staged+unstaged agent
edits, unreviewed). `origin/feat/shared-libraries` now EXISTS — the §0 split must be a
follow-up commit at push-prep, **never a rebase**. (Decision recorded.)

Proven green, verified inline this session (logs + own runs, not agent word):

- Canary FRESH green: `/tmp/canary-2a.log` 02:14, 1 file / 40 tests passed. The auth-server
  `[ELIFECYCLE]` line is container-teardown noise after the pass, not a test failure.
- INV-02 PASS (`gate-openapi-diff.log`: no removals/renames/type changes, +12 paths/+23 schemas).
- UP-01 PASS (`gate-upgrade.log`: data intact, reserved-label guard works).
- `run.sh:128` fix reviewed (branch instead of empty-array expansion under bash-3.2 `set -u`)
  and proven by execution — upgrade + openapi-diff ran through it.
- exif audio-video 3/3 PASS under pinned ffprobe 7.1.3-6 (own run just now via
  `vitest.config.medium.mjs`) → the prior red was pure PATH drift, never a regression.
  `run.sh` hardened in this pass (mise shims first on PATH; `bash -n` clean, resolves the
  pinned ffprobe) to kill the whole footgun class.
- Fork lifecycle subset 43/43 on both templates — subset only, not the full fork gate.

Not proven / still owed (verdict stays red):

- INV-03: the upstream-e2e run is methodologically VOID — the log mixes fork-oracle
  `.fork-data` assertions with upstream specs failing in the zeros-pattern of a wrong-stack
  run (brief §1.5). Not product-red; the true `/data`-stack run is still owed.
- S9: person service/unit/e2e have no log evidence this session — unknown. (exif/trash are
  NOT the S9 suites; the trash failures belong to the same void run.)
- Full fork e2e-api gate on the final tree: not run.
- Email live render (2f), C7 status: no evidence produced.
- Coverage-matrix §2d DECIDED (owner, overriding the agent's marker-based version): gate-tier
  IDs (INV-02/UP-01/INV-03) count as covered by host-tier execution evidence, not by
  script-existence markers; invisible tags (`[C3]`/`[R16]`/`[I6]`/`[I7]`/`PERM-11`) stay
  advisory-but-reported, plus disappearance detection (fail if a previously-seen advisory tag
  vanishes — no invented phase ownership, no silent loss). Implementation of the refinement
  is owed.

Conjunction: canary-green YES (fresh) / no-failing-fork NOT PROVEN / INV-02 green + INV-03
void / S9 unknown. Narrowed path to flip: (1) review + per-phase commit of the dirty tree;
(2) full `run.sh all upgrade --template both` under the hardened runner; (3) true
upstream-e2e on `/data`; (4) S9 trio evidence; (5) email render + C7 evidence; (6) coverage
refinement; (7) split as follow-up commit.
