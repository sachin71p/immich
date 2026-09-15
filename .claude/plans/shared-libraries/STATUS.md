# Status

Legend: ⬜ todo · 🟨 in progress · ✅ done · ⛔ blocked · ➖ skipped

| Phase | Title | Depends on | Risk | Status | Commit | Note |
|---|---|---|---|---|---|---|
| S0 | Fork baseline, FORK.md, branch | — | low | ✅ | 3e0c08539 | base v3.1.0; server+web check/lint/test PASS after plugin-sdk bootstrap |
| S1 | Schema & migrations | S0 | med | ✅ | 06ec13fac | targeted medium schema tests PASS; full unit suite blocked by sandbox socket policy |
| S2 | Access control, favorites & album permissions | S1 (parallel-safe with S3) | **high** | ✅ | f34f92116 | check/lint and focused suites PASS; full unit suite blocked by sandbox socket policy |
| S3 | Storage keys & relocation engine | S1 (parallel-safe with S2) | **high** | ✅ | 83f80f33f | check/lint and focused suites PASS; full unit suite blocked by sandbox socket policy |
| S4 | Spaces/library-member API, move API, upload target, lifecycle | S2, S3 | **high** | ✅ | 19cce54f5 | typecheck/lint and focused suites PASS; full unit suite blocked by sandbox socket policy; Dart SDK regen needs Java |
| S5 | Visibility scope across queries | S4 | **high** | 🟨 | 98f0179d9 | host medium 15-Sep caught a real regression: S5 dropped the own-timeline TimelineRead gate, shared-link sessions enumerated buckets instead of 400; restored without touching scope behavior (tsc/eslint clean, unit 46 incl. timeline/search/sync), host medium re-run pending |
| T0 | Test harness: fixtures, world, disk oracle, runner, coverage | S0 (parallel-safe with S6/S7) | med | 🟨 | 83f7fc363 | HOST unit PASS 15-Sep (111 files, 2388 + 1 pre-existing it.fails); watch-mode fixed 727b68e38; HOST medium #1 57 failed → fixed (18bc6e27e scope wire-up, c8ce0f52a SY ambiguity/id-split, spaceId); HOST medium #2 26 failed — search/memory/asset/sync-asset/album-asset/SY-03-04/schema PASS, SY-01/05 split unsatisfiable + timeline shared-link gate both fixed this turn (unit 46 clean), re-run pending; plugin/ffmpeg → mise prereqs in TESTING.md §8 + wasm fail-fast in spec; e2e-api raced boot (empty DB, all skipped) → ping wait added to stack_up; coverage FAIL is the missing-IDs gate (R13-04/W-01/W-02/W-09 → T1 backfill) |
| T1 | Regression backfill for S1–S5 (host run with Docker) | T0 | **high** | ⬜ | | S1–S5 were ✅ without medium/e2e runs |
| S6 | Sync stream for spaces & shared libraries | S5 | **high** | 🟨 | 41822db64 | host medium 15-Sep exposed 2 real bugs: ambiguous space-upsert selects (SY-03/04) + create/update split keyed on asset.id not updateId (SY-01/02/05); fixed c8ce0f52a, but host medium #2 showed updateId<=createAck unsatisfiable (both checkpoints share the nowId clock, a modified row always exceeds it); re-keyed the split on createdAt<=checkpoint-time(+1ms) (tsc/eslint clean, unit 46), host medium re-run pending |
| S7 | Full metadata endpoint & extended search filters | S5 | med | ✅ | 231211358 | check/lint and 241 configured focused tests pass; bare plan Vitest command lacks alias config; full/medium suites constrained by sandbox/container |
| S8a | Web: spaces management, settings, admin library members | S6, S7 | med | ✅ | 0d317e4ee | check:typescript/lint clean (fixed 5 lint errors + 2 tailwind warnings); check:svelte and vitest blocked by host toolchain (pre-existing TS 6.0.3 crash, localStorage-in-vitest gap), not phase defects |
| S8b | Web: timeline switcher, move action, favorites/album UI, upload target | S8a | med | 🟨 | c688cca6e | verifier PARTIAL: ts/lint + 356 tests PASS (KNOWN crashes only); coverage harness broken (T0), Docker NOT RUN |
| S8c | Web: full metadata panel, search filters | S8a (parallel-safe with S8b) | low | 🟨 | 1c552f852 | verifier PARTIAL: ts/lint + 356 tests PASS (KNOWN crashes only); coverage harness broken (T0), Docker NOT RUN |
| S9 | (optional) Space-scoped People | S6 | high | 🟨 | 1e5d39f46 | code checks PASS (tsc/eslint, 333 tests); HOST unit PASS 15-Sep incl. person-space 10/10; coverage FAIL was T0 harness gap (fixed 727b68e38), medium/e2e-api/coverage still need host run |
| S10 | Hardening: upgrade gate, FORK.md, upstream-merge rehearsal | S8b, S8c, T1 | med | ⬜ | | |
| A0 | Apple: workspace, shared core package skeleton, codegen | S0 | low | ✅ | 9d686e0b8 | host now has a full Xcode toolchain; `swift build && swift test` verified clean (1 fixed `Operations.Login`→`Operations.login` naming bug, applied in A1) |
| A1 | Apple core: auth, sync engine, local DB | A0, S6 | high | ✅ | 2756651c4 | `swift build && swift test` clean on independently reverified from-scratch build: 29/29 pass; AP-02 vs rules-cases.json deferred to T0 |
| A2 | Apple core: image pipeline + cache tiers | A1 | med | ✅ | 6618a19c5 | swift build + swift test 55/55 PASS (29 A0/A1 intact); verify.sh sandbox-exec + xcodegen NOT RUN (toolchain gaps) |
| A3 | iOS app: grid, viewer, libraries, albums, favorites, move | A2 | med | 🟨 | | implementer DONE 15-Sep; verifier PARTIAL 15-Sep (handoff/A3-verify.md): verify.sh ios NOT RUN, xcodegen missing in sandbox — needs host `native-apple/scripts/verify.sh ios` |
| A4 | macOS app: sidebar, grid, viewer, libraries, albums, move, import | A2 (parallel-safe with A3) | med | ⬜ | | |
| A5 | Backup/upload (iOS extension + macOS watcher/import) | A3, A4 | high | ⬜ | | |
| A6 | Storage optimization (iOS free-up-space R14, macOS cache budget) | A5 | high | ⬜ | | |
| A7 | Metadata panel, search & filters (both) | A3, A4, S7 | low | ⬜ | | |
| A8 | Editor engine (Core Image) + UIs | A3, A4 | high | ⬜ | | |
| A9 | Photos-like extras: Live Photos, video, Live Text, memories, map, extensions | A8 | med | ⬜ | | |
