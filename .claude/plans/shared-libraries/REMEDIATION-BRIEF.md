# Remediation brief — close the audit findings

You produced `.claude/plans/shared-libraries/AUDIT-FINDINGS.md` (verdict: do not deploy). Now fix it.

Read first, in full: `AUDIT-FINDINGS.md`, `audit/00-contract.md`, and every `audit/w1-*.md` and
`audit/w3-*.md` — **including their `GAPS:` lines**, which tell you what the audit could not see.
`DECISIONS.md` remains the contract; §11 is out of scope and stays out.

---

## 0. What changes from the audit brief

| | Audit | Remediation |
|---|---|---|
| Tests / builds / linters | forbidden | **required** — a fix without a failing-then-passing test is not a fix |
| Docker / host tiers | forbidden | required for the phases you touch, per `TESTING.md §8` |
| Editing code | forbidden | that is the job |
| Subagents | 6 in wave 1 | see §4; still the only orchestrator, still no nested subagents |

---

## 1. Non-negotiables

**Fix root causes, not lines.** The 30 findings are ~8 defects. If you patch `access.repository.ts:246`
without also fixing `:351`, `:699` and `:727`, you have fixed one symptom of one bug. Every cluster in
§3 gets **one** centralized fix applied at every site.

**Centralize, do not sprinkle.** The reason this leaked is that the fork broadened the data model
(assets can now live in a container) while leaving upstream's `ownerId = userId` shortcut scattered
across repositories. Adding a membership check at each call site reproduces the original failure mode:
the next query someone writes will leak again. Introduce a shared, named predicate/helper and route
every site through it. A reviewer must be able to grep for one symbol and see all users.

**You must move in BOTH directions — this is the trap.** The P0s are *under*-restriction (people see
what they shouldn't). But S2's 5 failing upstream album specs and the P3 findings
(`access.ts:146`, `access.ts:197`) are *over*-restriction (people denied what §4 promises them).
A blunt "add membership checks everywhere" pass will fix the P0s and make the over-restriction worse.
**`DECISIONS.md §4` is the arbiter for every cell.** When code and §4 disagree, §4 wins; if §4 is
genuinely ambiguous, write the question into `AUDIT-FINDINGS.md` under a `NEEDS-DECISION` heading and
leave that cell alone rather than guessing.

**Never weaken an upstream permission to make a fork test pass.** If a fix requires changing upstream
behavior, stop and flag it.

**Resolve SUSPECTED before fixing it.** Three findings are inferred, not confirmed. Confirm or dismiss
each *before* writing code — do not "fix" something that was never broken.

---

## 2. Reproduce before you fix

For every P0 and P1, in this order:

1. Write a test that **fails** for the reason the audit states, named for its contract ID
   (`PERM-11`, `I3`, `I6`, `R17`, `I4`…). For access leaks the shape is: set up membership → remove
   membership → assert the removed user is denied.
2. Confirm it fails for the right reason, not a setup error.
3. Fix.
4. Confirm it passes, and that nothing else regressed.

A leak with no regression test is not closed — it is dormant. The audit found these precisely because
tests did not.

---

## 3. The eight clusters — fix in this order

### C1 (P0) — "owner" is no longer sufficient for access
`access.repository.ts:246, :351, :699, :727` · `memory.repository.ts:73, :192`

Root cause: an asset's owner is **not** automatically entitled to it once it sits in a container they
have been removed from. Every `ownerId = userId` shortcut inherited from upstream is now wrong for
container assets.

Define one predicate — *"personal and owned"* **OR** *"in a container where the caller is a current
member"* — and route asset, asset-file, person and face access through it. `spaceId IS NULL` alone
does not mean personal; `libraryId` must be excluded too (that is exactly the `:246` bug).

### C2 (P0) — partner access is unscoped
`access.ts:119, :135` · `access.repository.ts:274`

Partner sharing must only ever expose **personal** assets: `spaceId IS NULL AND libraryId IS NULL`.
Fix the partner query itself, not each caller. Check the branch ordering at `access.ts:119` — partner
is tried before container membership, so the unscoped query wins before the correct check runs.

### C3 (P0) — removed members never receive removal events
`sync.repository.ts:977, :1032, :1172` (+ SUSPECTED `:923`)

The delete streams join `shared_space_member` / `library_member`, so the moment a membership row is
deleted the user becomes unreachable and **never learns to drop the assets from their local store**.
A client that already synced keeps showing them. Treat this as equal in severity to the read leaks —
it is the same exposure, offline.

This one needs design, not a patch. The audit notes a possibly-correct precedent: library removal may
already compensate via `library_member_audit` filtered by removed user
(`sync.repository.ts:1152-1156`, emitted `sync.service.ts:769-772`). **Investigate that path first** —
if it works, mirror it for spaces; if it does not, both need the audit-table-driven design. Close the
w3 GAP: confirm whether `shared_space_audit` is populated on member deletion, and what the client does
with `SharedSpaceDeleteV1` / `SharedLibraryDeleteV1`. Verify end-to-end, not by reading SQL.

### C4 (P1) — live-photo halves can split across containers (I3)
`asset.repository.ts:818` · `metadata.service.ts:726-728`

Matching lacks container predicates; motion-asset creation copies `libraryId` but drops `spaceId`.
Fix both — either alone leaves the invariant breakable. The audit notes I3 is enforced **neither** in
the DB nor fully in the service layer; decide whether it should also become a DB constraint and say why.

### C5 (P1) — relocation-row bypass (I6)
`asset-media.service.ts:179` · migration `1789426700279-SharedLibraries.ts:112` · `asset.table.ts:102`

Two paths change an asset's container without creating an `asset_relocation` row: direct upload into a
space, and the FK's `ON DELETE SET NULL`. The migration has not been deployed anywhere but dev, so you
may amend it in place — but say so loudly in the handoff, because anyone who already applied it must
re-run. Also decide whether I7 (Locked visibility on container assets) should gain a DB CHECK rather
than staying service-only.

### C6 (P1) — path containment is prefix-only (R17)
`library.service.ts:346` · `storage-template.service.ts:363`

`/allowed/../outside` passes, and `shared/family-2` escapes the `shared/family` root. Both need
resolve-then-boundary-check (`p === root || p.startsWith(root + path.sep)`), with the path normalized
first. **One shared helper, used by both**, plus unit tests for `..` traversal, the sibling-prefix
case, symlinks, and trailing separators.

### C7 (P1/P2) — move failures are swallowed (I4, I6)
`storage.core.ts:255, :274, :290` · `storage-template.service.ts:275`

Four variations on one defect: a file operation fails, the error is logged, and the caller proceeds to
mark the relocation complete. On a 219k-asset library this silently detaches files from their rows.
Errors must propagate; a relocation row may only complete when the move is verified. `:290` is a
distinct bug — crash recovery stats the already-missing old path before using known asset data, so a
completed copy can never be resumed. Exercise crash and filesystem-failure cases on a host, not in
unit mocks.

### C8 (P1/P3) — client and contract
`AssetViewerNavBar.svelte:203` · `open-api/immich-openapi-specs.json:14930` · `access.ts:146, :197` ·
`asset.repository.ts:960`

Web offers Locked visibility to container members (I7). The `updateMyTimeline` operationId collides
with the external-library operation at `:7922` despite differing DTOs — rename one **before** the S10
SDK regeneration, or every generated client inherits the ambiguity. The two `access.ts` P3s and the
favorites P3 are the over-restriction side of §1: contributors are denied rights §4 grants them.
For the Svelte fix, verify the server also rejects it — a client-only fix is a UI tidy, not a
security fix.

---

## 4. Execution

Work in batches. **Do not parallelize agents across files another agent is editing** — C1, C2 and the
`access.ts` P3s all touch the same two files and must be one sequential unit.

| Batch | Clusters | Parallel? |
|---|---|---|
| 1 | C1 + C2 + C8's `access.ts` P3s | **No** — one agent, shared files |
| 2 | C3 | No — design first, then implement |
| 3 | C4, C5 | Yes — 2 agents, disjoint files |
| 4 | C6, C7 | Yes — 2 agents, disjoint files |
| 5 | C8 remainder (web, OpenAPI) | Yes — 2 agents |

After each batch: run the affected unit suites plus the full server suite, and **re-run the 5 failing
S2 album specs every time**. They are your canary for over-restriction. Commit per cluster with the
contract IDs in the message.

Delegate implementation freely, but **you review every diff against §4 and the invariants yourself**.
A subagent reporting "fixed" is a claim. Keep prompts file-referenced, not pasted; cap each agent;
forbid unfiltered repo-root searches.

---

## 5. Definition of done, per finding

- Contract ID named in the test name and the commit message
- A test that failed before and passes after
- The whole cluster fixed, not just the cited line
- No upstream permission weakened; S2's album specs no worse than before
- `STATUS.md` updated with what **actually ran**

---

## 6. Documentation and process

The audit found `STATUS.md` marking S1, S3–S7, A0, A2, A3 complete while their verifier records show
required tiers were blocked or never ran, and A4–A9 have no `-verify.md` at all. That is how a leak
this size stayed invisible. Fix the records, not just the code:

- Correct the S0 base version (`STATUS.md` says v3.1.0; `server/package.json` says 3.2.0 and the base
  is v3.2.0 + 98 commits).
- Reconcile every ✅ against `TESTING.md §8`. A phase whose host tier never ran is not ✅ — downgrade it.
- Either produce the missing A4–A9 verifier records or mark those phases unverified.
- Close the OpenAPI/SQL regeneration contradiction called out in the audit.

Do not quietly re-mark things green. If a tier cannot run, say so and say why.

---

## 7. Deliverable

Update `AUDIT-FINDINGS.md` in place: add an `Outcome` column to every table — `FIXED` (with the test
name), `NOT-A-DEFECT` (with evidence), `DEFERRED` (with reason and owner), or `NEEDS-DECISION`.

Then append a **Re-verification** section stating plainly: which suites ran, on host or in sandbox,
what still fails, and whether the verdict has changed from *do not deploy*.

You are the only one who can say that verdict has changed. Do not say it unless the tests support it —
this code is going in front of a real family photo library with ~219k photos and four real users, and
an over-optimistic green is worse than an honest red.
