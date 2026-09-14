# Status

Legend: ⬜ todo · 🟨 in progress · ✅ done · ⛔ blocked · ➖ skipped

| Phase | Title | Depends on | Risk | Status | Commit | Note |
|---|---|---|---|---|---|---|
| S0 | Fork baseline, FORK.md, branch | — | low | ✅ | 3e0c08539 | base v3.1.0; server+web check/lint/test PASS after plugin-sdk bootstrap |
| S1 | Schema & migrations | S0 | med | ⬜ | | |
| S2 | Access control, favorites & album permissions | S1 (parallel-safe with S3) | **high** | ⬜ | | |
| S3 | Storage keys & relocation engine | S1 (parallel-safe with S2) | **high** | ⬜ | | |
| S4 | Spaces/library-member API, move API, upload target, lifecycle | S2, S3 | **high** | ⬜ | | |
| S5 | Visibility scope across queries | S4 | **high** | ⬜ | | |
| S6 | Sync stream for spaces & shared libraries | S5 | **high** | ⬜ | | |
| S7 | Full metadata endpoint & extended search filters | S5 | med | ⬜ | | |
| S8a | Web: spaces management, settings, admin library members | S6, S7 | med | ⬜ | | |
| S8b | Web: timeline switcher, move action, favorites/album UI, upload target | S8a | med | ⬜ | | |
| S8c | Web: full metadata panel, search filters | S8a (parallel-safe with S8b) | low | ⬜ | | |
| S9 | (optional) Space-scoped People | S6 | high | ⬜ | | |
| S10 | Hardening: e2e, FORK.md, upstream-merge rehearsal | S8b, S8c | med | ⬜ | | |
| A0 | Apple: workspace, shared core package skeleton, codegen | S0 | low | ⬜ | | |
| A1 | Apple core: auth, sync engine, local DB | A0, S6 | high | ⬜ | | |
| A2 | Apple core: image pipeline + cache tiers | A1 | med | ⬜ | | |
| A3 | iOS app: grid, viewer, libraries, albums, favorites, move | A2 | med | ⬜ | | |
| A4 | macOS app: sidebar, grid, viewer, libraries, albums, move, import | A2 (parallel-safe with A3) | med | ⬜ | | |
| A5 | Backup/upload (iOS extension + macOS watcher/import) | A3, A4 | high | ⬜ | | |
| A6 | Storage optimization (iOS free-up-space R14, macOS cache budget) | A5 | high | ⬜ | | |
| A7 | Metadata panel, search & filters (both) | A3, A4, S7 | low | ⬜ | | |
| A8 | Editor engine (Core Image) + UIs | A3, A4 | high | ⬜ | | |
| A9 | Photos-like extras: Live Photos, video, Live Text, memories, map, extensions | A8 | med | ⬜ | | |
