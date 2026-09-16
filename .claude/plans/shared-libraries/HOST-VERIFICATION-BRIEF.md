# Host verification — the last gate before deploy

All sandbox-runnable work is done: `v3.2.0` is merged, the §3a library face gate, §3b lint and §3c
cluster-group interaction spec have landed, and sandbox tiers are green (unit 2199/0, medium 645
passing across 72/74 files, all type/lint gates clean).

**Nothing below has run on a host since the fixes landed.** That is the only thing between this fork
and a deployment decision. The verdict is **do not deploy** until these tiers say otherwise.

Context: `AUDIT-FINDINGS.md`, `TESTING.md` (§7 gate, §8 host rules), `UPSTREAM-RECONCILE-BRIEF.md`.

---

## 0. Pre-step — split the mixed commit if it hasn't been done

`f6bd80b62` bundled a docs update with a real `R4-01` fix and its test (`metadata.service.ts`,
`metadata.service.spec.ts`, `moves.e2e-spec.ts` — an unregistered sidecar is invisible to relocation,
so a move strands it and re-extraction wipes user tags).

If `git log --oneline -3` still shows them together: keep `AUDIT-FINDINGS.md` in the docs commit and
move the three files into
`fix(shared-libraries): R4-01 register written sidecars so relocation carries them`.

**Verify nothing is pushed first** (`git rev-parse @{u}` — there was no upstream branch as of the last
check). If a remote branch now exists and contains this commit, **do not rewrite it** — add a
follow-up commit instead and say so.

---

## 1. Host prerequisites — get these right or the results are garbage

`TESTING.md §8` is explicit, and the two "known environmental" failures seen in the sandbox
(ffmpeg golden drift, missing workflow wasm) **are exactly these prerequisites unmet.** On a correctly
configured host they must **pass**, not be waived. Treat either one still failing as a host setup
problem to fix, not a result to record.

1. **Use mise, never bare `pnpm`**, for upstream server medium specs — bare `pnpm` silently picks the
   wrong toolchain.
2. **`mise run //:plugins`** must have built `packages/plugin-core/dist/plugin.wasm` before any medium
   run. Without it the workflow core-plugin spec fails with cryptic `Plugin method not found` errors
   (the import WARN swallows the underlying ENOENT).
3. **`ffprobe` must be the pinned `github:jellyfin/jellyfin-ffmpeg 7.1.3-6`** from the root
   `mise.toml` / `mise.lock`. It is a bare-PATH lookup in `media.repository.ts`, so a Homebrew ffmpeg
   9.x shifts keyframe packet timings and breaks the `audio-video` goldens in
   `server/test/fixtures/media.stub.ts`. **Never edit those goldens to match local drift.**
4. Docker Desktop running; sandbox disabled.
5. **Never run upstream path-planting specs on the fork stack.** `integrity.e2e-spec` `docker exec`s
   files into `/data/upload/…`; the fork stack serves `/fork-data`, so every detection reads zero.
   Fork-oracle specs run on the fork stack; upstream specs on the default stack.

Confirm 1–3 explicitly before starting and record the resolved `ffprobe` path and wasm timestamp in
your report. Most wasted host runs start here.

---

## 2. Execution order

`TESTING.md §7` prescribes the post-merge gate: **`run.sh all upgrade`**, and states the merge *is not
accepted* with any failing fork case or an INV-02/INV-03 failure. Do not jump straight to it — run the
canary first so a permissions regression surfaces in two minutes rather than ninety.

### 2a. Canary — upstream album specs, alone, first

The 5 upstream `album.e2e-spec.ts` (R11 / S2) specs are the over-restriction canary. This work
tightened authorization (§3a gate, Task 1), changed album access (R11) and re-scoped partner access
(C2) — this is the suite that catches having gone too far.

**If these regress, STOP.** Do not continue to the full suite; diagnose and fix first. A regression
here means the fork now denies something `DECISIONS.md §4` grants.

### 2b. Full gate

```bash
scripts/fork-test/run.sh all upgrade --template both
```

`all` = unit, medium, e2e-api, e2e-web, apple, upstream, coverage. Adding `upgrade` gives the §7
post-merge gate. `--template both` covers storage-template on and off, which matters because §3a and
the relocation work touch template paths.

If the Apple tier's Xcode toolchain is unhealthy, run the other tiers and report `apple` as NOT RUN —
do not let it block the server result.

### 2c. Targeted re-runs that the gate does not imply

Prior host greens for these are **invalidated** by this work and must be re-run explicitly even if the
aggregate passes:

- **S9 person suites** — `STATUS.md` records person.service 21/21, person unit 10/10, person e2e 16/16.
  The §3a face gate changes exactly this code. Re-run all three; do not assume.
- **S3 / S4 / S6** — relocation, spaces API and sync were all modified after their last host run.

### 2d. Coverage gate

`R13-04`, `W-01`, `W-02`, `W-09` remain missing and T1-owned. Separately, the new test tags
(`[C3]`, `[R16]`, `[I6]`, `[I7]`, unbracketed `PERM-11`) are deliberately invisible to the gate because
the matrix has no matching sub-cases. **Decide and record** whether the matrix should gain them — a
test that the gate cannot see is a test that silently disappears later.

### 2e. S10 regen

Must carry the `updateMyTimeline` → `updateMySpaceTimeline` rename (DEFERRED in Task 4 — renaming
before regen would break three clients). Note `access.repository.sql` is **stale** after the §3a gate
and needs regenerating too. Verify INV-02 (OpenAPI diff) passes after.

### 2f. ESM surface check — NEW, nothing has ever tested this

The fork carries `2a6262204 feat: NestJS 12 and ESM (#31237)` (2026-09-10, **626 files**), which
converted the server to ESM (`"type": "module"`). **Production's v3.2.0 does NOT have this commit** —
its `server/package.json` has no `"type"` field and is still CommonJS. Deploying therefore ships an
unreleased framework-major + module-system change underneath the fork's features.

This is not theoretical. The migration left two `require()` calls in ESM modules, which crash every
transactional email at render:

```
ERROR [Microservices] Unable to run job handler (NotifyAlbumInvite):
ReferenceError: require is not defined
    at ImmichLayout (.../dist/emails/components/immich.layout.js:6:22)
```

Fixed in this pass (`immich.layout.tsx`, `futo.layout.tsx` → static default import; the package is
CommonJS, so Node's interop supplies `module.exports` as the default). **Upstream has not fixed it** —
`server/src/emails/` has no commits since the ESM migration. Worth sending upstream.

Both audit passes scoped to fork-vs-plan and never exercised the upstream ESM migration, so:

- **Verify the fix end to end**: trigger `NotifyAlbumInvite` (add a member to an album) and confirm the
  email renders instead of throwing. The world seed does this automatically.
- **Sweep for siblings**: `require(` and `__dirname`/`__filename` in `server/src` were clean as of this
  pass (the `shared-space.service.ts` hits are a *method* named `require`, not CJS). Re-check after the
  merge, and extend to dynamic `import()` paths, runtime config loading, and any job handler that was
  never exercised by a test.
- Treat any new `ReferenceError: require is not defined` or `ERR_MODULE_NOT_FOUND` at runtime as an
  ESM-migration finding, not a fork defect — and record it in `AUDIT-FINDINGS.md` either way.

### 2g. C7 two-filesystem exercise

Unit mocks do not prove EXDEV behavior. On a host with two filesystems, exercise: cross-device move,
partial-copy crash resumption, and unlink-failure propagation. This is the one remaining item with no
automated coverage at all, and it guards against silently detaching files from their rows across a
219k-asset library.

---

## 3. Reporting

Append to `AUDIT-FINDINGS.md` under `## Re-verification (host)`:

- resolved `ffprobe` path and plugin wasm build time (proof §1 was satisfied)
- per tier: PASS / FAIL / NOT RUN with counts — **never PASS for a tier that did not run**
- the canary result, called out separately
- any finding whose `FIXED` status does not survive a host run — downgrade it in place
- the coverage-matrix decision from 2d

Then state the verdict. **Only you can change it from *do not deploy*.** Required to flip it: the
canary green, no failing fork case, INV-02/INV-03 green, and S9's three suites re-run green. Anything
short of that is still red, and saying so is the correct outcome — this goes in front of a live family
photo library with ~219k photos and four real users.

> The branch is shared and moving — new edits to `job.service.ts` and `e2e/test-assets` appeared during
> the last session. Run `git log --oneline -5` and `git status` before you start, and report what HEAD
> was when you ran, so the results can be attributed to a known tree.
