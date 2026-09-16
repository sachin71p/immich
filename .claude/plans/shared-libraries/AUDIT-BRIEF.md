# Audit brief — shared-libraries fork vs. its own plan

You are auditing a fork of Immich (self-hosted photo server) on branch `feat/shared-libraries`.
Your job is to find **gaps between what the plan says and what the code does**. You are not
implementing, not refactoring, and not re-running CI.

Repo root: the directory you were started in. ~470 files diverge from upstream base `e55ac299a`
(upstream v3.2.0 + 98 commits). Stack: TypeScript (NestJS server, SvelteKit web), Swift
(`native-apple/` — iOS + macOS apps and a shared `PhotosCore` package), Postgres via Kysely.

---

## 1. Source-of-truth hierarchy

Read in this order. Later items never override earlier ones.

1. **`.claude/plans/shared-libraries/DECISIONS.md`** — the contract. Numbered requirements
   (`R*`), invariants (`I1`–`I7`), the role/permission matrix (§4), move rules (§6), directory
   layout (§7), lifecycle (§8), visibility scope (§10), and explicit out-of-scope (§11).
   **Anything in §11 is not a gap. Do not report it.**
2. **`.claude/plans/shared-libraries/phases/<ID>.md`** — per-phase specs (S0–S10, T0–T1, A0–A9).
3. **`.claude/plans/shared-libraries/CODEMAP.md`** — pre-verified file/symbol facts at the upstream
   base. **Treat as true. Do not re-derive anything it already states.** If you find it wrong,
   record a `CODEMAP-FIX:` line and move on.
4. **`.claude/plans/shared-libraries/TESTING.md`** — test case IDs and coverage gate rules.
5. **`.claude/plans/shared-libraries/handoff/<ID>.md` and `<ID>-verify.md`** — what the implementer
   and verifier each claimed. **These are claims, not evidence.** Your job includes checking whether
   a ✅ is real.
6. **`STATUS.md`** — the running scoreboard. Same caveat: a claim to test, not a fact.

The code is the final authority on what exists. `DECISIONS.md` is the final authority on what
*should* exist.

---

## 2. Known-open items — DO NOT re-report these as findings

These are already tracked. Reporting them wastes budget. Only report them if you find the
*documented* status is materially wrong (e.g. something marked ✅ is not).

- **S2**: 5 failing upstream e2e album-access specs (viewer add/remove wrongly denied, owner wrongly
  denied, role-change error message). Bug-hunt in flight.
- **T0**: 13 integrity + 4 world path-mapping failures; coverage gate missing IDs R13-04, W-01,
  W-02, W-09.
- **T1**: regression backfill in progress.
- **S8b / S8c**: marked PARTIAL — Docker and coverage not run; pre-existing TS 6.0.3 vitest crash.
- **S10**: in progress — `run.sh all upgrade` (Docker) and SQL/OpenAPI regen still pending.
- Full unit suite blocked by sandbox socket policy in several phases; host runs are the oracle.

---

## 3. What to look for, in priority order

**Rank findings by blast radius, not by how easy they were to spot.** This is a
sharing/permissions feature on a family photo server; the worst outcome is one user seeing
another's private photos, and the second-worst is data loss.

### P0 — Visibility & authorization leaks (highest value, audit hardest)
- Every query path that lists or counts assets must be scoped per `DECISIONS.md §10`. Hunt for
  read paths that filter by `ownerId` but forget `spaceId` / library membership: timeline, search,
  smart search, map, memories, people/faces, albums, sync stream, shared links, metadata endpoints,
  download/archive, statistics.
- The permission matrix in §4 vs. the actual branch table in `server/src/utils/access.ts` and
  `server/src/repositories/access.repository.ts`. Any role granted more than §4 allows is P0.
- New `Permission` enum values (§5) — are they enforced at every controller that needs them, and
  are they correctly usable as API-key scopes?
- Sync (S6): does a user who is removed from a space or library stop receiving its assets, and do
  they receive the correct deletes? Check `library_member` / `shared_space_member` removal paths.

### P1 — Invariant enforcement
- Each of `I1`–`I7` in §3. For each: is it enforced in the database (constraint/trigger), in the
  service layer, in both, or nowhere? A DB-only invariant with no service-layer guard produces
  500s; a service-only invariant is bypassable by another code path. Report which.
- Specifically confirm `asset_space_library_exclusive` (spaceId and libraryId never both set) is
  honored by every write path, not just the constraint.

### P2 — Move / relocation correctness (S3, §6, §7)
- `asset_relocation` lifecycle: rows created, processed, cleaned up. What happens on crash
  mid-move? Is `move_history` written before the file operation?
- EXDEV / cross-filesystem copy+verify path, and the recovery path on partial failure.
- Directory layout §7 (R17) vs. what `StorageCore.getStorageKey()` actually produces.
- Does anything delete originals? Trace every unlink/rm in fork-authored code and confirm a guard.

### P3 — Contract & consistency
- OpenAPI/SDK drift: do new endpoints appear in the generated SDK, and is the Dart SDK regenerated?
- DB migrations vs. table definitions in `server/src/schema/tables/` — do they agree?
- Web (S8a–S8c) and Apple (A3–A9) clients: do they call the endpoints the server actually exposes,
  with the shapes it expects?

### P4 — Remaining work
- Requirements in `DECISIONS.md §2` with no implementing code and no test.
- Phases marked ✅ whose `-verify.md` shows the verification did not actually run.
- TODO/FIXME/`@ts-expect-error`/`any` casts introduced by the fork in security-relevant paths.

---

## 4. Method — three waves, hard budget caps

You may delegate to subagents. **You are the only orchestrator; subagents do not spawn subagents.**

**Wave 0 (you, alone, no subagents).** Read `DECISIONS.md`, `STATUS.md`, `CODEMAP.md` and
`TESTING.md` in full. Write `.claude/plans/shared-libraries/audit/00-contract.md`: a flat checklist
of every `R*` requirement, every `I1`–`I7` invariant, and every §4 permission-matrix cell, each with
a stable ID. This file is the spine every subagent is measured against. Nothing else is read yet.

**Wave 1 — parallel, max 6 subagents, each capped at ~25k tokens.** One per axis, not per file:

| # | Axis | Scope |
|---|---|---|
| 1 | Visibility scope | `server/src/repositories/*.repository.ts`, `server/src/services/{timeline,search,memory,person,map,asset}.service.ts` |
| 2 | Authorization matrix | `server/src/utils/access.ts`, `access.repository.ts`, `server/src/controllers/`, `enum.ts` |
| 3 | Invariants + schema | `server/src/schema/`, both fork migrations, write paths that set `spaceId`/`libraryId` |
| 4 | Move / relocation / storage | `server/src/cores/storage.core.ts`, `services/{storage-template,asset-relocation,library}.service.ts` |
| 5 | Sync & membership | `services/sync.service.ts`, `repositories/sync.repository.ts`, membership add/remove paths |
| 6 | Clients vs. contract | `open-api/`, `web/src/lib/`, `native-apple/PhotosCore/Sources/SyncEngine/` |

Give each subagent: the axis, its file scope, the path to `00-contract.md`, the P-level definitions
above, the return schema in §5, and this instruction — *"CODEMAP.md is already verified; do not
re-survey anything it states. Do not read files outside your scope. Do not run tests."*

Each writes `.claude/plans/shared-libraries/audit/w1-<n>-<axis>.md` and returns **only** a one-line
count per severity plus the file path. Do not let them return prose.

**Wave 2 — you, alone.** Read the six files. Deduplicate, resolve contradictions, and **verify every
P0 yourself** by opening the specific `file:line` — a subagent's P0 claim is a lead, not a finding.
Downgrade anything you cannot confirm.

**Wave 3 — conditional, at most 2 subagents.** Only if Wave 2 leaves a specific question that a
targeted read answers. Skip it if there is none.

---

## 5. Return schema (every subagent, every wave)

One finding per line. No prose, no code blocks, no file dumps.

```
P<0-4> | <contract-id or "-"> | <path>:<line> | <one-line claim> | <CONFIRMED|SUSPECTED>
```

`CONFIRMED` means the agent opened the line and the claim is visible there. `SUSPECTED` means
inferred. Anything not opened is `SUSPECTED` — say so honestly; an inflated CONFIRMED is worse than
an honest SUSPECTED because I will trust it.

End each file with `GAPS: <what you could not check and why>`.

---

## 6. Token discipline (this is a hard requirement)

- **Never** run `rg`/`grep` without a path filter. No repo-root searches. `node_modules`,
  `dist/`, `build/`, `*.lock`, `e2e/fork-assets/generated/` are always excluded.
- **Never** read a file to "get oriented". Read it to answer a specific question you can state.
- **Never** paste code into a report or into another agent's prompt. Chain through file paths.
- **Do not run the test suite, builds, linters, or Docker.** Results already live in `STATUS.md`
  and `handoff/*-verify.md`. Re-running them is the single most expensive mistake available here.
- Prefer `sed -n 'X,Yp'` over reading whole files.
- `native-apple/` is ~100 files of Swift. Audit it **only** against §4/§10 contract items
  (does the client request the right scope) — do not review Swift UI code for quality.
- If a subagent returns confused output twice, do the task yourself or drop the axis. Do not
  re-prompt a third time.

---

## 7. Deliverable

`.claude/plans/shared-libraries/AUDIT-FINDINGS.md`:

1. **Verdict** — one paragraph: is this deployable to a live family photo server with real data?
2. **P0 table** — every confirmed leak or authorization gap, with `file:line` and the contract ID
   it violates. Empty table is a fine answer if it's true.
3. **P1–P2 table** — same shape.
4. **Coverage gaps** — `R*` requirements with no implementing code, and ✅ phases whose
   verification did not actually run.
5. **Remaining work** — ordered by what blocks deployment first.
6. **Contradictions found in the plan docs themselves** — e.g. `STATUS.md` S0 records base
   `v3.1.0` while `server/package.json` says `3.2.0`. Flag these; do not fix them.

Deployment context: this fork is going onto a live server with ~219k real family photos and 4 real
users. Write the verdict for someone deciding whether to put their family's photo library behind
this code. Be blunt about what you did not check.
