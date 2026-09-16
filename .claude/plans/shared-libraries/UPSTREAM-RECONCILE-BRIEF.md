# Upstream reconciliation + host verification

The remediation pass is complete: every audit finding carries an outcome, 15 commits landed, sandbox
tiers are green. See `AUDIT-FINDINGS.md`. **The verdict is still do not deploy**, for two reasons —
one newly discovered (§1), one known (§2).

Read `AUDIT-FINDINGS.md` (especially its two `## Re-verification` sections and `## NEEDS-DECISION`)
before starting. `DECISIONS.md` remains the contract.

**Order of operations — the sections below are NOT in execution order:**

1. §1 — merge `v3.2.0`, resolve collisions, re-run sandbox tiers
2. §3a — contract amendment, then the library face gate
3. §3b — lint cleanup (after the merge, own commit)
4. §3c — cluster-group interaction test
5. §2 — host verification tiers, canary first

Do not start §2 until §1 and §3 have landed; host runs on a tree you are about to change are wasted.

---

## 1. The fork is missing 40 upstream commits — fix this FIRST

Established by direct git inspection, and **not** caught by the audit or the remediation pass
(both were scoped to fork-vs-plan, never fork-vs-upstream):

```
merge-base(v3.2.0, feat/shared-libraries) = e61312084  "chore: version v3.2.0-rc.0"
git merge-base --is-ancestor v3.2.0 feat/shared-libraries  →  NO
```

The fork branched at **v3.2.0-rc.0**, not v3.2.0. Production runs **v3.2.0 final**, which contains
**40 commits this branch does not have.** Earlier plan documents describing the base as "v3.2.0 + 98
commits" are wrong; `git describe` reports `v3.1.0-460-g…` because v3.2.0 is on a different line.

**Schema is fine** — verified: the migration sets are identical apart from the two fork migrations, so
there is no upstream migration gap and no reprocessing implication. The problem is application code.

### Why this blocks deployment

Deploying would be a partial **downgrade** of upstream code in exactly the areas the fork rewrote:

| Missing upstream commit | Collides with |
|---|---|
| `d66756fca` fix(server): never unlink an untracked-file path that an asset now references | **C7 rewrote `storage.core.ts` move/unlink** — highest risk |
| `8139af6e0` fix: do not move faces of users other than the current owner | **Task 1 person/face owner access** |
| `bf75aaa81` fix(web): partner sharing timeline | **C2 partner scoping** |
| `583243901` fix(server): live photo transcode visibility | **C4 live-photo container propagation** |
| `f29691d2a` fix: face detection of edited assets | face pipeline |
| `2466ba5e6` fix(web): face editor coordinates on a not-yet-loaded video | face editor |
| `163d3c71f` fix(deps): update maplibre-gl to v6 **[security]** | dependency |

### How

**Merge `v3.2.0` into the branch. Do not rebase.** (Owner-confirmed 16-Sep.) 178 fork commits across ~470 files, on a branch
that is shared and actively moving — a rebase would be a long conflict slog with no audit trail, and
would invalidate the commit SHAs recorded in `AUDIT-FINDINGS.md`.

For each of the four **bolded** rows above (`d66756fca`, `8139af6e0`, `bf75aaa81`, `583243901`),
**the resolution is a judgment call — do not blind-take
either side.** Read the upstream fix's intent, then decide whether the fork's rewrite already covers
it, needs it layered on, or conflicts with it. `d66756fca` in particular may supersede or contradict
C7's unlink-error-propagation change; compare them explicitly and write the reasoning into the merge
commit.

Record in `AUDIT-FINDINGS.md` under a new `## Upstream reconciliation` section: what merged cleanly,
what conflicted, and how each of the four bolded collisions was resolved.

Then **re-run the full sandbox tier set** (server tsc, e2e tsc+lint, web tsc + svelte-check, full
non-controller unit) and confirm it is no worse than the session-close baseline: 80 files / 2197
passed / 0 failed, 226 controller `listen EPERM` failures, 22 pre-existing server lint errors.

---

## 2. Host verification backlog — nothing below has run since the fixes landed

Sandbox has no Docker, so every medium and e2e tier is unexecuted. **The security fixes therefore have
tests but no evidence.** Run these on the host, in this order.

1. **The 5 S2 album e2e specs — first, before anything else.** These are the over-restriction canary,
   and this work tightened authorization (Task 1), changed album access (R11) and re-scoped partner
   access (C2). If they regress, stop and fix before continuing; do not proceed to a full suite.
2. Controller unit (fails in sandbox only on `listen EPERM`).
3. `run.sh medium` — the new `PERM-11` / `[C3]` / `[R16]` / `[I6]` / `[I7]` tests, **plus re-runs for
   S3/S4/S6/S9**, whose prior host greens are invalidated by these fixes.
4. `run.sh e2e-api` — full fork suite.
5. Coverage gate. `R13-04`, `W-01`, `W-02`, `W-09` remain T1-owned and still missing. Note that the
   new test tags above are deliberately invisible to the gate (no matching matrix sub-cases) — decide
   whether the matrix should gain them.
6. `run.sh upgrade` / S10 — must carry the `updateMyTimeline` → `updateMySpaceTimeline` rename
   (DEFERRED in Task 4; renaming before regen would break three clients).
7. Real crash and filesystem-failure exercise for C7. Unit mocks do not prove EXDEV recovery, partial
   copy resumption, or unlink failure propagation. Do this on a host with two filesystems.

---

## 3. Owner decisions — now made, implement them

### 3a. Library face/person scope → **gate only; do NOT grant**

Owner decision 16-Sep, revised after inspecting upstream's cluster-group model. Read this section
fully before touching person/face code — the first version of this decision said "gate and grant",
and that was wrong.

**Build the gate.** A removed library member must lose face/person access to library assets they own.
Apply the existing shared predicate's library branch at the two sites Task 1 left at upstream
owner-only: `access.repository.ts` → `PersonAccess.checkOwnerAccess` and `checkFaceOwnerAccess`.
Do not write a second predicate. Add medium coverage for the removed-owner-denied case on the library
leg (the existing `PERM-11` medium test covers spaces only).

**Do NOT build the grant.** Face/person rights must not flow from library membership. Rationale, which
belongs in the contract:

- Faces are partitioned by `cluster_group`, one per user (`user.clusterGroupId`). An external
  library's assets sit inside the *owner's personal* cluster group, alongside their private photos.
  Granting face access via library membership would expose the owner's **entire personal face graph**
  as a side effect of sharing one folder — a far larger leak than the one being closed.
- `library` has no `clusterGroupId` (only `shared_space` does), so there is no container-scoped face
  graph to grant access *to* without new schema, a migration, and re-clustering.
- **Upstream already solves this properly.** `feat: cluster groups` (#30739, present in this branch's
  base) ships `cluster_group_request` — unique `(clusterGroupId, userId)` — with a full request/accept
  flow in `server/src/services/cluster-group.service.ts`, its own `ClusterGroupRequestCreate`
  permission, and a notification event. A user who wants their own people to appear on assets shared
  with them joins the relevant cluster group. That is explicit, mutual, and scoped to the people graph
  rather than to a container.

**Contract amendment (do this before the code).** `DECISIONS.md` currently has `§4` silent on
face/person rights and `§11` saying person graphs stay per-owner. Amend `§4` to state that
**face/person access follows cluster-group membership, not container membership**, and reconcile `§11`
to reference the cluster-group-request flow as the supported mechanism. This is a smaller amendment
than defining new library face rights, and it records why the grant was refused so it is not
re-litigated.

Then resolve the `NEEDS-DECISION` entry in `AUDIT-FINDINGS.md` — gate `FIXED` with the test name,
grant `NOT-A-DEFECT` citing the cluster-group flow.

**Re-run S9.** `STATUS.md` records it host-verified at person.service 21/21, person unit 10/10, person
e2e 16/16. The gate change invalidates all three; they must be re-run on the host, not assumed.

### 3b. The 22 pre-existing server lint errors → **fix them in this pass**

Owner decision 16-Sep. They are byte-identical to HEAD and not caused by the fork, but they are being
cleared now rather than carried. Do this **after** the `v3.2.0` merge, not before — the merge touches
many of the same files and fixing first guarantees rework. Keep it in its own commit, separate from
every functional change, so the host run can attribute a regression cleanly.

### 3c. Still genuinely open

- **Cluster-group interaction — unverified by anyone.** The fork added `shared_space.clusterGroupId`,
  creating space-scoped face graphs *alongside* upstream's user-level `user.clusterGroupId`. Nobody has
  checked how the two compose. Establish, with a test: what does a user who is both a shared-space
  member **and** has joined another user's cluster group (via `cluster_group_request`) see in their
  people list — one coherent set, or overlapping duplicates? Does naming a person in one surface
  affect the other? If the fork's S9 work breaks or bypasses upstream's cluster-group sharing, that is
  a new finding; record it in `AUDIT-FINDINGS.md` rather than fixing it silently.

- **5 unattributed new unit tests** (2197 vs 2190 baseline, +2 accounted). Identify them; a test
  appearing from nowhere on a shared moving branch is worth ten minutes.
- The branch is shared and moving. `git log` before every host run.

## 4. Definition of done

- `v3.2.0` is an ancestor of the branch, with the four bolded collisions individually reasoned
- Sandbox tiers no worse than the session-close baseline
- Host tiers 1–4 green, or their failures recorded honestly
- `AUDIT-FINDINGS.md` has an `## Upstream reconciliation` section and an updated `## Re-verification`
- `DECISIONS.md §4`/`§11` amended to route face/person access through cluster-group membership; `NEEDS-DECISION` closed (gate FIXED, grant NOT-A-DEFECT)
- Cluster-group / shared-space interaction established by test, and recorded
- S9's three host suites re-run (they are invalidated by 3a), not assumed
- Lint clean, in its own commit, landed after the merge

**Only you can change the verdict from *do not deploy*, and only if the host tiers support it.** This
goes in front of a live family photo library — ~219k photos, four real users, on a running server. An
over-optimistic green is worse than an honest red.
