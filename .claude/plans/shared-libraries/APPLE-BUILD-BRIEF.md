# Apple app build — iOS + macOS

Runs **in parallel with** the host verification tiers (`HOST-VERIFICATION-BRIEF.md`). Read §1 before
touching anything: this must happen in an isolated worktree, not the main checkout.

## 0. Scope — what this is and is not

**Not part of the deployment plan.** `.claude/plans/deploy-heirloom-docker.md` covers the server stack
only (Docker Compose, Postgres, storage). The Apple apps are a separate artifact on a separate track.

**Not a deployment dependency.** The fork renames no env vars, cookies or routes, so stock Immich
mobile clients work against it unchanged. The Heirloom apps are additive — the server can deploy and
be used without them.

**What this is:** an early build-health check. `STATUS.md` records that A3 and A4 each surfaced 6–7
host-only Swift 6 build breaks (concurrency/Sendable, actor isolation, SDK API drift) that the sandbox
never caught. Finding the next batch now, while the server tiers run, is free parallelism.

**Do not treat the output as a shippable build** — see §4.

---

## 1. Isolate in a worktree — mandatory

`native-apple/scripts/verify.sh core` calls `gen-api.sh`, which copies
`open-api/immich-openapi-specs.json` over the **tracked** file
`native-apple/PhotosCore/Sources/ImmichAPI/openapi.yaml`. The host verification run triggers that same
path via `run.sh all` → `run_apple`. Two processes writing one tracked file while a Docker test suite
reads the tree is how you get results nobody can attribute.

```bash
git worktree add ../heirloom-apple feat/shared-libraries
cd ../heirloom-apple
git log --oneline -3          # record the HEAD you are building
```

Work only there. **Do not commit** from this worktree unless you are fixing a build break (§3), and if
you do, keep it to `native-apple/` files only. `Heirloom.xcodeproj/` is gitignored, so xcodegen output
will not create churn. Remove the worktree when done: `git worktree remove ../heirloom-apple`.

---

## 2. Build

Prerequisites: Xcode 27+ with **iOS 27.0 / macOS 27.0** SDKs (from `project.yml`), `xcodegen` ≥ 2.44.0 on
PATH. If either is missing, stop and report — do not work around it by lowering deployment targets.

```bash
cd native-apple
./scripts/verify.sh core    # PhotosCore: gen-api + swift build + swift test
./scripts/verify.sh ios     # xcodegen + xcodebuild build+test, iOS Simulator
./scripts/verify.sh mac     # xcodegen + xcodebuild build+test, ad-hoc signed
```

Run `core` first and stop if it fails — both app targets depend on it, and a core failure makes the
app errors noise.

`mac` uses `CODE_SIGN_IDENTITY="-"` (ad-hoc), which is correct for local verification.

Eight targets exist beyond the two apps — background-upload, photo-editing, share, widgets, intents,
agent. `xcodebuild ... build test` on each scheme covers what the schemes include; if an extension
target is not built by either scheme, say so rather than assuming it compiles.

---

## 3. When a build breaks

Expected, based on A3/A4 history. Fix them, with these limits:

- Fix **build breaks only** — Swift 6 concurrency/Sendable, actor isolation, SDK signature drift,
  missing `await`. Do not refactor, restyle or "improve" working code.
- Never lower a deployment target, disable a concurrency check, or add `@unchecked Sendable` to silence
  a real data race. If a fix needs one of those, stop and report it as a finding.
- Match existing patterns in the file — e.g. `nonisolated(unsafe)` for statics is already the
  established idiom here (`SyncEngine/WireTypes.swift`).
- One commit per logical fix, prefixed `fix(apple):`, `native-apple/` files only.

Run each mode **twice** after fixing. A4's history shows UI tests that pass once and fail on rerun —
one green run is not evidence.

---

## 4. The sequencing caveat — this build will need redoing

S10's regen (`HOST-VERIFICATION-BRIEF.md` §2e) renames `updateMyTimeline` → `updateMySpaceTimeline` in
`open-api/immich-openapi-specs.json`. The Swift client is generated from that spec by `gen-api.sh`, so
**every artifact you produce now becomes stale when S10 lands**, and any Swift call site referencing
the old operation will need updating.

That is fine — the value here is catching build breaks early, not producing a final binary. But:

- Do not distribute or install anything from this run as though it were final.
- After S10 regen, re-run `verify.sh all` and fix whatever the rename surfaces. Expect at least one
  call site.
- If you find Swift code calling `updateMyTimeline`, note the file:line now so the post-regen fix is a
  lookup rather than a search.

---

## 5. Device installation — not your task

Building and simulator-testing is in scope. Installing on a physical iPhone or Mac is **not**: it needs
the owner's Apple developer identity and provisioning. Do not configure signing identities, teams, or
credentials, and do not modify `CODE_SIGN_STYLE`/`DEVELOPMENT_TEAM` beyond what `verify.sh` already
passes. When builds are green, report that and let the owner handle device deployment in Xcode.

---

## 6. Report

- HEAD you built, and the Xcode / xcodegen / SDK versions
- Per mode (`core`, `ios`, `mac`): PASS / FAIL / NOT RUN, with test counts
- Every build break found and how it was fixed, one line each — flag any that needed a concurrency
  escape hatch, those are findings not fixes
- Which of the eight auxiliary targets were actually compiled, and which were not
- Any Swift call site referencing `updateMyTimeline` (for the post-S10 fix)
- Confirmation that each mode was run twice with the same result

Do not touch `server/`, `web/`, `e2e/`, or the deployment plans. The host verification run owns those.
