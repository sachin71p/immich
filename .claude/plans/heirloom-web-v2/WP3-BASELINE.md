# WP3 — Test baseline report (pre-V2)

Date: 2026-09-16. Worktree: `/Users/spatel/workspace/github/projects/immich`, branch state per `git log` (`f77bebddc` HEAD).
V2 routes do not exist yet (`web/src/routes/(user)/v2/` absent, `web/src/lib/heirloom*/` absent) — this is a true pre-change baseline.

## 0. Worktree safety record

`git status --short` at session start:

```text
M .claude/plans/deploy-heirloom-docker.md
M native-apple/Apps/macOS/Sources/MacAppState.swift
M native-apple/PhotosCore/Sources/ImmichAPI/ImmichConnection.swift
?? .claude/plans/heirloom-web-v2/
```

The three modified files are pre-existing user modifications — never touched, per constraints.
No destructive git operations performed. Only additions under `.claude/plans/heirloom-web-v2/` and
`web/src/lib/heirloom-test/` were made by this agent.

## 1. Test-pattern inventory (web/)

### 1a. Unit / component — vitest (`web:unit`)

- Config: `web/vite.config.ts` lines 58–70 — `include: src/**/*.{test,spec}.{js,ts}`, `globals: true`,
  `environment: happy-dom`, `setupFiles: ./src/test-data/setup.ts`, `env.TZ = UTC`.
- Setup (`web/src/test-data/setup.ts`): svelte-i18n `init({fallbackLocale:'dev'})`, `Element.prototype.animate`
  stub, `matchMedia` mock. Timezone pinned to UTC.
- Count: **65 spec files** under `web/src`.
- Patterns observed:
  - **Pure util specs** (no rendering): `utils/timeline-util.spec.ts` (fake timers + fixed system time
    `2024-07-27T12:00:00Z`, locale switching), `utils/library-source.spec.ts` (V2-relevant: source parsing),
    `utils/byte-units`, `date-time`, `cancellable-task`, `executor-queue`, `layout-utils`, `container-utils`,
    `move-targets`, `asset-permissions`, `people-utils`, `ocr-utils`. Deterministic style: fixed clocks,
    no network.
  - **Service specs with mocks**: `services/asset.service.spec.ts`, `services/shared-link.service.spec.ts`.
  - **Component specs** via `@testing-library/svelte`: `components/sidebar/Sidebar.spec.ts`
    (stores mocked with `vi.mock`, `vi.hoisted` fixture objects, `beforeEach` reset),
    `components/asset-viewer/*`, `components/album-page/__tests__/*`, `components/shared-components/*`,
    `modals/*`. Render helper: `web/tests/helpers.ts` → `renderWithTooltips` wraps components in
    `TestWrapper.svelte`.
  - **Route-builder specs**: `lib/route.spec.ts` — asserts exact URL strings from the `Route.*` builders
    (login/search/shared-link). This is the closest existing analogue to the V2 URL-state contract
    (PLAN §9); V2 will need an equivalent spec for source/group/zoom normalization.
  - **Manager/store specs**: `managers/timeline-manager/*.svelte.spec.ts`,
    `managers/asset-multi-select-manager.svelte.spec.ts`, `stores/folders.svelte.spec.ts`,
    `stores/ocr.svelte.spec.ts`.
  - **Route co-located specs**: `routes/(user)/albums/.../AlbumDescription.spec.ts`,
    `routes/(user)/people/manage/ManagePeopleVisibility.spec.ts`,
    `routes/(user)/shared-links/(list)/ShareCover.spec.ts`.
- Scripts (`web/package.json`): `test` = `vitest` (watch), `test:cov` = `vitest --coverage`,
  `check:typescript` = `tsc --noEmit`, `check:svelte` = `svelte-check …`,
  `lint` = `eslint . --max-warnings 0 --concurrency 6`.

### 1b. Playwright — `e2e/` (three projects in `e2e/playwright.config.ts`)

| Project | testDir | Launch |
|---|---|---|
| `web` | `src/specs/web` | `pnpm test:web` (`playwright test --project=web`) |
| `ui` | `src/ui/specs` | `pnpm test:web:ui` |
| `maintenance` | `src/specs/maintenance/web` | `pnpm test:web:maintenance` |

- `src/specs/web/`: `album`, `asset-viewer/`, `auth`, `duplicates`, `integrity`, `photo-viewer`,
  `shared-link`, `user-admin`, `websocket`, plus **`fork/` (9 files — the fork-E2E web surface)**:
  `album-viewer`, `asset-metadata`, `library-members`, `library-switcher`, `move-to-library`,
  `search-filters`, `settings`, `space-upload`, `spaces`.
- `src/ui/specs/`: `asset-viewer/` (asset-viewer, broken-asset, face-editor, ocr, stack + `utils.ts`),
  `memory/` (memory-viewer + `utils.ts`), `search/` (search-gallery), `timeline/` (timeline + `utils.ts`).
  These are the closest existing visual/functional analogues for V2 timeline, viewer, search, memories.
- Timeline/viewer/sidebar-adjacent coverage today: `timeline.e2e-spec`, `photo-viewer.e2e-spec`,
  `asset-viewer/*`, `Sidebar.spec.ts` (unit), `RecentAlbums.spec.ts`. No dedicated sidebar e2e found.

### 1c. Fork-E2E web entry point — `scripts/fork-test/run.sh`

- `run_e2e_web()`: `stack_up` (Docker compose) → `(cd $ROOT/e2e && pnpm test:web -- src/specs/web/fork)` →
  `stack_down`. Requires Docker daemon + image stack; **not runnable from this sandbox** (no Docker
  authority). Recorded as not-run with command documented (§3).

### 1d. Accessibility / performance today

- `axe-core` (or `@axe-core/playwright`): **not present** in `web/`, `e2e/`, or root `package.json`.
  No existing automated-a11y pattern; V2 must introduce the method (see WP3-VISUAL-MANIFEST.md §5).
- No checked-in perf-timing harness found (no `performance.now` measurement helpers, no LHCI config
  observed). Perf method is therefore new (manifest §6).

## 2. Baseline command results

| # | Command (cwd) | Exit | Result | Pre-existing? |
|---|---|---|---|---|
| B1 | `cd web && pnpm exec vitest run src/lib/route.spec.ts` | 0 | 18/18 passed (1.89 s) | n/a (green) |
| B2 | `cd web && pnpm exec vitest run src/lib/utils/library-source.spec.ts src/lib/utils/timeline-util.spec.ts` | 0 | 15/15 passed (10.64 s) | n/a (green) |
| B3 | `cd web && pnpm run check:typescript` | not run | Full-project `tsc` exceeds bounded-run budget; deferred to WP4+ verification gate | — |
| B4 | `cd web && pnpm run test --run` (full 65-file unit suite) | not run | Exceeds ~5 min bounded budget from here; command documented for quality agent | — |
| B5 | `scripts/fork-test/run.sh e2e-web` | not run | **No Docker authority from this sandbox**; command documented, needs host/CI | — |
| B6 | `cd e2e && pnpm test:web:ui -- src/ui/specs/timeline` | not run | Requires live web+server stack (webServer/docker); documented for later agent | — |

No failures were observed. Nothing was fixed (constraint: record only).

## 3. Pre-existing-failure flags

- **P0 (tooling, pre-existing): `pnpm run lint` is broken on the pristine tree.** The `tscompat/tscompat`
  eslint rule throws `TypeError: Cannot read properties of undefined (reading 'Class')` (fatal rule crash,
  not a lint finding) on committed, unmodified files — verified `src/lib/utils/date-time.ts:21`
  (`new Intl.DateTimeFormat … .formatRange`) and `src/lib/utils.ts:80`, both with empty `git status`.
  The same crash fires on the new WP3 helper files (any file using everyday globals such as
  `URLSearchParams`/`Date.parse` can trigger it; an existing `URLSearchParams` user,
  `utils/navigation.ts`, lints clean, so the trigger is data-dependent inside the rule). Full `lint`
  therefore cannot pass with or without V2 work. Owner: lead (rule upgrade/pin or disable for affected
  files). WP3 did not touch it.
- Otherwise: the executed unit probes (B1, B2) passed, and broader suites were deliberately not run
  (bounded-run constraint). Full-suite unit failures, if any, remain uncharacterized and must be
  recorded — not fixed — by the agent that first runs those suites (see recommended next action).
- Known environmental non-runners (not failures): Docker-gated `e2e-web`, stack-gated Playwright `ui`
  specs. These must run on host/CI before WP4+ claims verification.

## 4. Gaps for later agents

1. Full `vitest --run` (65 files) baseline with per-file results — first runner records failures as
   pre-existing, does not fix.
2. `check:typescript` / `check:svelte` / `lint` baseline on the untouched tree.
3. Playwright `ui` timeline/viewer/search/memory specs against host stack — captures current classic
   behavior that V2 must not regress (release gate §17-regression).
4. `e2e-web` fork specs on host Docker — baseline for spaces/library/album/member flows V2 reuses.
5. `@axe-core/playwright` (or chosen a11y dep) is not installed — install decision + `package.json`
   change belongs to the Wave-4 a11y agent, not WP3.
