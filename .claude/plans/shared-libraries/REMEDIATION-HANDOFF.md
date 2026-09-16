# Remediation handoff — finish the partially-completed fix pass

A previous agent worked `REMEDIATION-BRIEF.md` and ran out of budget mid-pass. It did **not** record
what it finished. This brief is the verified state: what is done, what is left, what is unproven.

Read `AUDIT-FINDINGS.md`, `audit/00-contract.md` and `REMEDIATION-BRIEF.md` (its §1 non-negotiables
and §5 definition-of-done still apply in full). Everything below supersedes the brief's work order.

> **All work is in the uncommitted working tree.** ~55 files are staged/modified. Do not reset,
> stash or rebase. Commit per cluster as you go.

---

## 1. Already done — do NOT redo

A centralized predicate now exists and is the mechanism for the whole C1/C2 class:

**`withPersonalOwnershipOrCurrentContainerMembership`** — `server/src/utils/container-scope.ts:59`

Verified fixed against current code:

| Cluster | Findings | Mechanism |
|---|---|---|
| C1 (part) | asset owner access, asset-file owner access, memory search, single-memory | the predicate above |
| C2 (all) | partner AssetRead/Share, `checkPartnerAccess` | partner query now requires `spaceId IS NULL AND libraryId IS NULL` |
| C4 (all) | live-photo match, motion-asset creation | container predicates added; `spaceId: asset.spaceId ?? null` propagated |
| C5 (all) | upload relocation row, FK, I7 CHECK | `createRelocations` on spaced upload; FK → `ON DELETE RESTRICT`; `asset_container_not_locked` CHECK |
| C6 (all) | both containment sites | new `server/src/utils/path.ts` → `isResolvedPathInside` (realpath-based), used by both call sites |
| C7 (all) | 4 move/EXDEV sites | errors now propagate; recovery reordered to use `assetInfo` before stat |

New tests already written: `server/src/utils/path.spec.ts`,
`server/test/medium/specs/repositories/access.repository.spec.ts`,
`server/test/medium/specs/repositories/shared-container-integrity.spec.ts`.

---

## 2. THE CRITICAL CAVEAT

**Not one test, build, or linter has been run against any of this.** The previous agent exhausted its
budget before verification. Every row in the table above is "the code looks correct", not "it works".

You are inheriting ~55 modified files of unverified security-sensitive changes, including a schema
CHECK constraint and an FK semantics change. **Task 0 below is therefore not optional and not last.**

---

## 3. Work order

### Task 0 — Establish a baseline (do this FIRST, before writing any new code)

Run the server unit suite, the new medium specs, and the linter/typecheck. Then run the 5 S2 album
e2e specs that were failing before this pass — they are the over-restriction canary.

Record the result verbatim in `AUDIT-FINDINGS.md` under a new `## Re-verification` section. If the
existing fixes are broken, **fixing them comes before any new work below.** Do not build on top of an
unverified pile.

### Task 1 (P0) — Finish C1: person and face owner access

`server/src/repositories/access.repository.ts:689` (person) and `:717` (face) still use unconditional
`ownerId = userId` with no membership gate. These are the same defect the predicate already solves, so
this should be a small change, not a redesign — route both through
`withPersonalOwnershipOrCurrentContainerMembership`.

**One judgment call first:** the audit noted these sites carry `S9` comments suggesting the
owner-scoping may be *intentional* for space-scoped People. Read `phases/S9-space-people.md` and
`DECISIONS.md §4` before changing them. If §4 genuinely intends owner-only person access inside a
space, mark both `NOT-A-DEFECT` with the citation and move on. If §4 is ambiguous, mark
`NEEDS-DECISION` and leave them. **Do not guess** — over-tightening People access breaks S9, which
`STATUS.md` records as host-verified passing (person.service 21/21, person e2e 16/16).

### Task 2 (P0) — C3: removed members never receive removal events

`sync.repository.ts:974` (member delete), `:1029` (space asset remove), `:1169` (library asset remove)
all still require a **live** membership row for the recipient. A removed member therefore never learns
to drop the assets, and an already-synced client keeps showing them. Same exposure as a read leak,
offline.

The audit found a probable compensating path — the member-delete trigger writes `shared_space_audit`
and `library_member_audit` keyed by the removed `userId` (`sync.repository.ts:923`, `:1152`) — but
flagged it as **pre-existing trigger behavior that was never verified by running SQL**.

So: **verify before you design.** Write a medium/e2e test that adds a member, syncs, removes the
member, and asserts the client receives an event that causes it to drop the container's assets. If the
audit path already works, that test passes and you mark 10/11/12 `NOT-A-DEFECT` with the test as
evidence. If it fails, implement the audit-table-driven delivery and make it pass.

This is the largest remaining item and the one most likely to need real design. Budget for it.

### Task 3 (P1) — C8 web: Locked visibility offered to container members

`web/src/lib/components/asset-viewer/AssetViewerNavBar.svelte:204` — `SetVisibilityAction` is gated on
`isOwner`, which now includes space/library members, contradicting I7.

**Check the server first.** I7 just gained a DB CHECK (`asset_container_not_locked`), so the server may
already reject this — in which case the current behavior is a confusing UI that produces a 500 rather
than a security hole, and the fix is to hide the action *and* confirm the server returns a clean error.
A client-only fix is a UI tidy, not a security fix.

### Task 4 (P3) — Contract and the over-restriction side

- `open-api/immich-openapi-specs.json` — `updateMyTimeline` operationId collides between the
  shared-space operation (`:14930`) and the external-library one (`:7922`) despite differing DTOs.
  Rename one **before** S10's SDK regeneration, or every generated client inherits the ambiguity.
- The three over-restriction P3s from the audit, which the previous pass did not address:
  `access.ts` AssetFileDownload (contributors denied downloads §4 grants), `access.ts` AssetEditGet
  (owner-only while EditCreate/Delete admit members), and the favorites field omitting `libraryId` for
  external-library members. Each is measured against `DECISIONS.md §4`.
- Resolve the two SUSPECTED authorization findings the audit could not confirm:
  `SharedSpaceMemberUpdate` and `SharedSpaceMemberDelete` are granted to every member, with
  owner-transfer and self-removal protection depending on an uninspected service-layer guard. Read the
  service, then either confirm the guard exists (mark `NOT-A-DEFECT` with `file:line`) or fix it.

### Task 5 — Review two questionable fixes from the previous pass

- `storage-template.service.ts` batch job: the new error handling still converts a **per-asset failure
  into an overall Success job status**. Confirm that is intended; a relocation batch that silently
  reports success after losing an asset is the same class of defect C7 was meant to close.
- The migration was amended in place (FK → `ON DELETE RESTRICT`, plus the new CHECK). Anyone who
  already applied the old version must re-run it. Make that explicit in `FORK.md` and the handoff.

### Task 6 — Documentation and process

`STATUS.md` was modified but only its S10 row; **no remediation or audit progress was recorded at
all.** Still outstanding from `REMEDIATION-BRIEF.md §6`:

- Add an `Outcome` column to every table in `AUDIT-FINDINGS.md`: `FIXED` (with test name),
  `NOT-A-DEFECT` (with evidence), `DEFERRED` (reason + owner), `NEEDS-DECISION`. **Nothing is recorded
  yet — this is why this handoff was necessary.** Do it incrementally as you work, not at the end.
- Correct the S0 base version (`STATUS.md` says v3.1.0; `package.json` says 3.2.0, base is v3.2.0+98).
- Reconcile every ✅ against `TESTING.md §8`. S1, S3–S7, A0, A2, A3 are marked complete while their
  verifier records show required tiers blocked or never run; A4–A9 have no `-verify.md` at all.
  Downgrade what is not evidenced.

---

## 4. Definition of done

- Every finding in `AUDIT-FINDINGS.md` carries an `Outcome`
- Every `FIXED` names a test that failed before and passes after
- The 5 S2 album specs are no worse than the Task 0 baseline
- Host tiers run per `TESTING.md §8` for every phase touched — sandbox-only is not release evidence
- `## Re-verification` section states: which suites ran, host or sandbox, what still fails, and
  whether the verdict has changed from **do not deploy**

Only you can change that verdict, and only if the tests support it. This fork is going in front of a
real family photo library — ~219k photos, 4 real users, on a live server. An over-optimistic green is
worse than an honest red.
