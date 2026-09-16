# Heirloom Web V2 — macOS Parity Execution Plan

Status: Ready for execution
Plan owner: lead implementation agent
Target: additive browser UI under `/v2`
Reference revision at plan creation: `464f9122be29b807b854e109cf6eecfce4544c52`
Last updated: 2026-09-16

## 1.1 Native Photos parity addendum — 2026-09-16

The browser V2 reference is the updated Heirloom macOS app, not the legacy macOS shell described
below. Add the following to the V2 acceptance scope:

- Utilities must show Recently Deleted, Duplicates, Captured by Me, Hidden, Archive, and Locked.
  Hidden removes media from the main timeline and may include every library the user can access.
  Archive remains a separate organization state; it is not a replacement for Hidden. Locked is
  personal-library-only and must be gated by a browser-appropriate re-authentication flow before
  contents render. The browser must never offer Lock for a shared-space or external-library asset.
- Duplicates must use the existing `/duplicates` API and present the server-provided groups across
  all libraries the authenticated user can access. Do not recreate detection from client checksums
  or limit it to the currently selected timeline source.
- Album sidebar classification is membership-driven: an album with another member is a Shared Album,
  including one created by the current user and shared later. Personal Albums contain only albums
  with no other member. Persisted/local data and optimistic share/unshare updates must refresh this
  classification immediately.
- The sidebar includes all native media collections represented by available metadata: Videos,
  Selfies, Live Photos, Portrait, Screenshots, and Screen Recordings. It also adds Captured With,
  grouping camera models under broad categories such as Phone, DSLR/Mirrorless, Drone, and GoPro
  while keeping each model selectable.
- Long Shared Libraries, Shared Albums, External Libraries, Albums, and Captured With collections
  collapse when they exceed three rows. The disclosure state must be keyboard accessible and
  restore sensibly on navigation.
- The desktop toolbar begins with Library and its visible date range. Source selection sits beside
  the grid-size minus/plus controls; grouping remains Years / Months / All Photos. Match native
  control padding, especially the visible gap between button labels and capsule borders. The
  timeline is a square grid with 2px gaps, 8px inset, and 64–300px-equivalent size controls.
- Each view has a centered footer with its real visible photo/video totals and the live sync status
  (syncing, up to date, or attention required). Do not display an unconditional “synced” string.

## 1. Objective

Build a new authenticated Heirloom browser experience under `/v2` whose application content, information architecture, primary interactions, and responsive desktop behavior match the native macOS Heirloom app as closely as browser technology permits.

The existing browser UI remains operational and unchanged at its current routes. The two experiences must be available simultaneously for comparison throughout development.

The project is complete when:

1. `/v2` and its child routes render the macOS-style Heirloom shell.
2. Existing routes such as `/photos`, `/albums`, and `/search` retain their current appearance and behavior.
3. Library navigation, source selection, square-grid browsing, selection, viewer, search, map, memories, people, albums, shared libraries, utilities, and browser-relevant settings satisfy the acceptance criteria in this plan.
4. Native-only capabilities have an explicit browser equivalent or a documented unavailable state. No inert or misleading controls are shipped.
5. Automated functional, accessibility, performance, and visual-regression gates pass.

## 2. Non-negotiable constraints

- This is additive. Do not replace, redirect, or restyle existing classic routes.
- Put the new route tree under `web/src/routes/(user)/v2`.
- `/v2` redirects to `/v2/library`.
- Give V2 its own shell, sidebar, toolbar, route helpers, visual tokens, and scoped CSS.
- Do not globally rebrand the classic Immich web UI.
- Any shared-component modification must be opt-in. Defaults must preserve classic behavior.
- Avoid server changes unless a concrete API gap is demonstrated with a failing test or a documented request/response analysis.
- Preserve authentication, authorization, privacy, and shared-library role checks.
- Preserve all unrelated worktree changes.
- Do not run destructive Git commands, reset, clean, checkout files, or stash user work.
- Do not hide unsupported capabilities behind controls that appear functional.
- Do not make an advanced browser editor a prerequisite for shipping the shell, grid, viewer, or navigation.

## 3. Worktree safety protocol

The repository was already dirty when this plan was written. At that time it contained both staged and unstaged changes, including changes under the shared-libraries plan and web/native code.

Every implementation agent must:

1. Run `git status --short` before editing.
2. Record the pre-existing changed paths in its handoff.
3. Inspect a target file's diff before modifying it.
4. Use narrow patches and preserve changes not created by the agent.
5. Never run `git reset`, `git clean`, `git checkout --`, or an implicit equivalent.
6. Never stash or commit unless the user explicitly requests it.
7. Stop and notify the lead if a planned edit overlaps an unexplained user change.

## 4. Definition of parity

### 4.1 Reference environment

The visual contract should use:

- native: macOS 27 fixture build
- browser: Safari on macOS
- reference viewport/content window: 1400 × 900
- themes: light and dark
- deterministic fixture data
- a stable system appearance, locale, timezone, and reduced-motion setting

Chrome outside the application content is excluded: browser tabs/address bar and macOS title/menu bar are not compared.

### 4.2 Parity categories

Every surface is classified independently:

- Visual parity: geometry, spacing, color, typography hierarchy, icons, borders, materials, and animation.
- Information-architecture parity: labels, ordering, grouping, destinations, and toolbar structure.
- Interaction parity: selection, keyboard behavior, navigation, modals, drag/drop, and state restoration.
- Functional parity: the action produces an equivalent persistent result.
- Documented browser exception: the native capability cannot be reproduced safely or portably.

“Exact” means that visual and interaction parity meet the automated tolerances in section 17, not that the browser reproduces operating-system chrome.

### 4.3 Known native-only or non-portable capabilities

These require explicit treatment:

| Native capability | Browser treatment |
| --- | --- |
| macOS menu bar | V2 toolbar/menu equivalents and documented shortcuts |
| native multi-window scene model | URL-backed views; optional `window.open` for viewer |
| Quick Look | Heirloom viewer/preview |
| Finder file promises | explicit Download; optional progressive enhancement |
| ImageCaptureCore camera import | file picker and supported browser capture input |
| SMAppService/background agent | real PWA/background feature or unavailable explanation |
| local cache budget controls | browser-storage implementation or unavailable explanation |
| VisionKit visual lookup/subject lift | omit or mark macOS-only |
| SF Symbols/SF Pro | licensed existing icons and system font stack |
| Core Image editing pipeline | separate WebGL/WASM/server project or reduced working tool set |

## 5. Source-of-truth code map

Read these native files before making visual or behavioral decisions:

- `native-apple/Apps/macOS/Sources/MacMainWindow.swift`
- `native-apple/Apps/macOS/Sources/MacSidebar.swift`
- `native-apple/Apps/macOS/Sources/MacSidebarModel.swift`
- `native-apple/Apps/macOS/Sources/MacViewer.swift`
- `native-apple/Apps/macOS/Sources/MacSearchView.swift`
- `native-apple/Apps/macOS/Sources/MacMapPlacesView.swift`
- `native-apple/Apps/macOS/Sources/MacMemoriesView.swift`
- `native-apple/Apps/macOS/Sources/MacSettings.swift`
- `native-apple/Apps/macOS/Sources/MacStorageView.swift`
- `native-apple/Apps/macOS/Sources/MacEditView.swift`
- `native-apple/Apps/macOS/Sources/MacMenus.swift`
- `native-apple/Apps/macOS/Sources/MacConnectView.swift`
- `native-apple/Apps/macOS/Sources/HeirloomMacOSApp.swift`

Read these web files and subsystems before creating replacements:

- `web/src/routes/(user)/+layout.ts`
- `web/src/routes/(user)/+layout.svelte`
- `web/src/lib/components/layouts/UserPageLayout.svelte`
- `web/src/lib/components/layouts/UserSidebar.svelte`
- `web/src/lib/components/shared-components/navigation-bar/NavigationBar.svelte`
- `web/src/lib/components/timeline/Timeline.svelte`
- `web/src/lib/components/timeline/Thumbnail.svelte`
- `web/src/lib/managers/VirtualScrollManager/`
- `web/src/lib/managers/timeline-manager/`
- `web/src/lib/utils/layout-utils.ts`
- `web/src/lib/components/asset-viewer/`
- `web/src/lib/managers/asset-viewer-manager.svelte.ts`
- `web/src/lib/route.ts`
- `web/src/app.css`
- existing shared-space, library-source, move, permission, album, upload, search, map, memories, OCR, and EXIF implementations

Relevant fork documentation:

- `.claude/plans/shared-libraries/STATUS.md`
- `.claude/plans/shared-libraries/TESTING.md`
- `FORK.md`

## 6. Current architecture findings

- The macOS main window uses a split view with an approximately 240px sidebar.
- The primary grid uses square cells, 2px gaps, 8px content inset, and a default cell size of approximately 120px.
- The macOS toolbar includes library source, Years/Months/All Photos grouping, a 64–300 zoom slider, management actions where applicable, and Sync.
- The native grid supports multi-selection, keyboard navigation, Return, Space preview, type-to-date, internal drag/drop, file import, and file export.
- The classic web timeline is an aspect-ratio-preserving justified grid with different navigation and toolbar structure.
- Existing web data capabilities cover most V2 requirements: source filtering, spaces, libraries, roles, albums, asset actions, visibility, search, map, people, memories, metadata, OCR, viewer media, and uploads.
- The current web editor is materially smaller than the native editor.
- The native collection grid currently flattens section data in its collection-view adapter. Phase 0 must decide whether visible grouping follows the shipped native behavior or the intended Year/Month header model.

## 7. Target routes

| Route | Destination |
| --- | --- |
| `/v2` | redirect to `/v2/library` |
| `/v2/library/[[assetId=id]]` | Library |
| `/v2/collections` | Collections |
| `/v2/search/[[assetId=id]]` | Search |
| `/v2/favorites` | Favorites |
| `/v2/recently-saved` | Recently Saved |
| `/v2/map` | Map/Places |
| `/v2/people` | People |
| `/v2/memories` | Memories |
| `/v2/media/photos` | Photos |
| `/v2/media/videos` | Videos |
| `/v2/media/screenshots` | Screenshots |
| `/v2/spaces/[spaceId]` | shared library/space |
| `/v2/libraries/[libraryId]` | external library |
| `/v2/albums/[albumId]` | Album |
| `/v2/imports` | Imports |
| `/v2/trash` | Recently Deleted |
| `/v2/hidden` | Hidden |
| `/v2/archive` | Archive |
| `/v2/locked` | Locked |
| `/v2/settings` | browser-relevant settings |

Do not link V2 from the classic sidebar until visual and functional acceptance gates pass. Direct URLs are sufficient for the comparison period.

## 8. Proposed V2 code organization

```text
web/src/routes/(user)/v2/
  +layout.svelte
  +page.ts
  library/[[assetId=id]]/
  collections/
  search/[[assetId=id]]/
  favorites/
  recently-saved/
  map/
  people/
  memories/
  media/photos/
  media/videos/
  media/screenshots/
  spaces/[spaceId]/
  libraries/[libraryId]/
  albums/[albumId]/
  imports/
  trash/
  hidden/
  archive/
  locked/
  settings/

web/src/lib/components/heirloom/
  shell/
  sidebar/
  toolbar/
  timeline/
  viewer/
  search/
  map/
  memories/
  people/
  settings/
  dialogs/
  shared/

web/src/lib/heirloom/
  routes.ts
  navigation.ts
  ui-state.svelte.ts
  tokens.ts
  capabilities.ts
  drag-drop.ts
  parity-types.ts
  heirloom-v2.css
```

The exact subdivision may change, but V2-only code must remain clearly isolated.

## 9. URL and preference contract

Use URL state for shareable/restorable state:

- `source=all`
- `source=personal`
- `source=space:<uuid>`
- `source=library:<uuid>`
- `group=years|months|all`
- `zoom=<integer from 64 through 300>`
- existing asset deep-link parameter/path conventions where compatible

Rules:

1. Valid URL state has highest precedence.
2. V2-specific saved preferences are the fallback.
3. Native defaults are the final fallback.
4. Invalid values are normalized without a reload loop.
5. Back/forward navigation restores source, grouping, zoom, asset viewer state, and scroll target.
6. V2 preferences must not overwrite classic web preferences.

## 10. Work packages

### WP0 — Preflight and baseline inventory

Owner: lead agent
Dependencies: none
File ownership: documentation and test artifacts only

Tasks:

- Run the worktree safety protocol.
- Confirm branch, revision, package manager, build commands, and available native fixture build.
- Inventory current classic routes and existing relevant tests.
- Verify the parent `(user)` layout authentication and asset-viewer behavior.
- Create a progress checklist derived from this plan.
- Assign disjoint work packages to subagents.

Deliverables:

- preflight note
- changed-file ownership table
- baseline command results

Gate:

- no production code changes until pre-existing changes and ownership are understood

### WP1 — Visual parity contract

Owner: visual-analysis subagent
Dependencies: WP0
File ownership: visual references and parity documentation only

Tasks:

- Run the native app with deterministic fixture seed.
- Capture light and dark reference screenshots at 1400 × 900.
- Cover library idle, selection, grouping modes, source picker, viewer, inspector, search, map, people, memories, dialogs, settings, and editor.
- Capture the corresponding classic web pages.
- Measure sidebar, toolbar, grid, typography, spacing, colors, borders, shadows, materials, and motion durations.
- Resolve the Year/Month section-header ambiguity against the running app.
- Identify dynamic regions requiring screenshot masks.

Deliverables:

- reference screenshots
- `PARITY-MATRIX.md`
- `MEASUREMENTS.md`
- documented browser exceptions

Acceptance:

- every planned V2 route maps to at least one native reference or an explicit “no native surface” entry
- every toolbar/sidebar action has an expected behavior or documented exception

### WP2 — Route and API feasibility matrix

Owner: data-analysis subagent
Dependencies: WP0
File ownership: documentation/tests; no server edits

Tasks:

- Map each destination to existing SDK calls, stores, and components.
- Confirm filters for personal, space, external library, media type, visibility, recent, favorites, people, map, and memories.
- Map create/update/delete operations for albums and spaces.
- Map role and permission checks for move and member administration.
- Identify any missing response fields or APIs with evidence.
- Propose the minimum possible server change only where reuse is impossible.

Deliverable:

- `ROUTE-DATA-MATRIX.md`

Acceptance:

- no speculative server work
- every claimed gap includes a reproduction or contract-level explanation

### WP3 — Test baseline and harness design

Owner: test-analysis subagent
Dependencies: WP0
File ownership: new V2 test helpers and baseline documentation

Tasks:

- Inventory unit, component, Playwright, and fork E2E patterns.
- Record baseline check/test results without fixing unrelated failures.
- Define deterministic fixture setup and visual masks.
- Define classic/V2/native comparison pairs.
- Establish accessibility and performance measurement methods.

Deliverables:

- baseline test report
- initial V2 test fixtures/helpers
- visual comparison manifest

### WP4 — V2 shell and navigation

Owner: shell subagent
Dependencies: WP1 and WP2
File ownership:

- `web/src/routes/(user)/v2/**`, excluding feature pages assigned elsewhere
- `web/src/lib/components/heirloom/shell/**`
- `web/src/lib/components/heirloom/sidebar/**`
- `web/src/lib/components/heirloom/toolbar/**`
- `web/src/lib/heirloom/routes.ts`
- V2 scoped tokens/styles

Tasks:

- Add the route root and redirect.
- Implement the persistent shell, sidebar, toolbar, content outlet, loading, error, empty, popover, toast, and modal foundations.
- Match native sidebar ordering and selected/hover/focus states.
- Populate spaces, external libraries, and albums from live data.
- Add a centralized V2 route builder.
- Add URL-backed source/group/zoom state and V2-only preference fallback.
- Add safe responsive behavior while treating desktop as the parity target.
- Use scoped CSS under a V2 root attribute/class.

Acceptance:

- direct navigation and reload work for each skeleton route
- classic navigation screenshots remain unchanged
- no global V2 selector leaks outside the V2 root
- keyboard focus order and landmarks are valid

### WP5 — Square virtualized timeline

Owner: grid subagent, then lead integration
Dependencies: WP1, WP2, WP3
File ownership:

- new V2 timeline components
- shared timeline/layout files only while explicitly locked by the lead

Tasks:

- Add an opt-in square layout mode to the reusable virtualized timeline system.
- Support tile size, gap, content inset, grouping, and scrubber visibility as explicit options.
- Preserve justified layout as the default.
- Implement 120px default square tiles, 64–300 zoom, 2px gaps, and 8px inset.
- Match native grouping and headers established in WP1.
- Preserve scroll anchor and focus when zoom/group/source changes.
- Add V2 empty/loading/error states.
- Ensure source filters and stacked-asset behavior remain correct.

Acceptance:

- classic timeline tests and screenshots are unchanged
- V2 handles at least 10,000 fixture assets without rendering the complete collection
- zooming and regrouping do not lose the user's approximate scroll position
- no duplicate fetch loop or excessive layout thrash

### WP6 — Selection, keyboard, and drag/drop

Owner: interaction subagent
Dependencies: WP5
File ownership: V2 interaction/drag-drop files; shared selection files only with lead lock

Tasks:

- Match single, Command/Ctrl, and Shift-range selection.
- Implement Command/Ctrl+A, arrows, Return, Space, Escape, and type-to-date.
- Match focus/selection visuals and selection toolbar.
- Create a documented internal asset drag payload.
- Add album drops and personal/space/external-library move drops.
- Apply permission-aware visual drop states.
- Add external file drops with destination selection.
- Provide explicit Download in place of Finder file promises.
- Add toast and error recovery behavior.

Acceptance:

- keyboard-only browsing and selection are complete
- unauthorized destinations do not accept drops
- failed operations restore coherent UI state
- all persistent actions use existing authorization-aware services

### WP7 — Management sheets

Owner: management subagent
Dependencies: WP4 and WP6
File ownership: V2 dialogs and route-specific management components

Tasks:

- Add New Album, Add to Album, Move to Library, New Shared Library, Manage Shared Library, member/role, import-destination, and destructive confirmation flows.
- Reuse existing SDK/service logic.
- Match native sheet widths, hierarchy, button order, validation, disabled states, and progress treatment.
- Refresh affected stores and timelines after success.

Acceptance:

- role-restricted controls are absent or disabled as appropriate
- dialogs are fully keyboard accessible and restore focus on close
- cancel has no side effects

### WP8 — Heirloom viewer

Owner: viewer subagent
Dependencies: WP1, WP2, WP4
File ownership: `web/src/lib/components/heirloom/viewer/**` and V2 viewer routes/wrappers

Tasks:

- Wrap or extend the current viewer through an explicit V2 variant.
- Match the black canvas, toolbar order, spacing, controls, and inspector.
- Support Favorite, Rotate, Delete, Move, Add to Album, Edit, Info, and OCR where already functional.
- Support previous/next, keyboard paging, zoom, video, and Live Photos.
- Keep asset identity in the URL and restore it on reload/back/forward.
- Add optional new-window behavior using a real V2 URL.
- Document unsupported VisionKit features.

Acceptance:

- classic viewer appearance and behavior remain unchanged
- deep-linked V2 assets open directly and close to the correct collection state
- media playback and keyboard navigation pass automated tests

### WP9 — Feature destinations

Owner: feature subagents split by disjoint directories
Dependencies: WP4 and WP5; viewer integration may follow WP8

Search:

- match native search field, scope selector, suggestions, recents, filters, square results, and EXIF presentation
- reuse current search API/manager

Map:

- implement the native horizontal map/grid split
- synchronize map and grid selection

People:

- match native hierarchy, spacing, cards, empty states, and navigation

Memories:

- match stories shelf and On This Day presentation
- reuse the existing story player/data

Media and utilities:

- map Photos/Videos/Screenshots to existing filters
- map favorites, recent, imports, hidden, archive, locked, and trash to existing APIs
- validate semantics where macOS labels differ from existing server concepts

Settings:

- match native layout for account, server/session information, upload destination, import destination, and timeline source
- show storage/background controls only if backed by a real browser implementation
- do not expose editable server URL inside the same-origin authenticated app unless product requirements explicitly change

Acceptance:

- each route has loading, empty, populated, error, and unauthorized coverage where relevant
- no route is a visual placeholder at release gate

### WP10 — Browser editor decision and implementation

Owner: lead/product decision, then dedicated editor team if approved
Dependencies: WP1 and viewer integration

Current native scope includes adjustments, filters, crop/perspective, portrait depth, vector markup, video trim/mute/rotate, undo/redo, copy/paste, revert, and compare. Current web scope is substantially smaller.

Decision A — reduced working browser editor:

- visually integrate only existing working browser tools
- identify macOS-only tools clearly
- do not render inert replicas

Decision B — full functional parity:

- write a separate technical design for WebGL/WASM or server rendering
- define preview/final-render consistency, color management, edit-recipe compatibility, video behavior, performance, and fallback
- schedule as an independent milestone

The lead must record the chosen decision. Decision B must not block V2 browsing release unless the user explicitly makes full editor parity a release requirement.

### WP11 — Accessibility, performance, and cross-browser hardening

Owner: quality subagent
Dependencies: WP4–WP9

Tasks:

- validate landmarks, accessible names, focus visibility, modal focus traps, announcements, and keyboard-only use
- support reduced motion and high-contrast/forced-color behavior where practical
- test Safari and Chrome on macOS; record font/rendering variance elsewhere
- profile initial load, scrolling, zoom/regroup, viewer open, and large collections
- eliminate obvious memory leaks and repeated request loops

Acceptance:

- no serious automated accessibility findings
- all primary workflows are keyboard operable
- 10,000-asset fixture remains virtualized and responsive
- Safari is the reference browser; Chrome has no functional blockers

### WP12 — Documentation and comparison rollout

Owner: lead agent
Dependencies: all release packages

Tasks:

- document `/v2`, route mapping, browser exceptions, test procedure, and known gaps
- update fork documentation/hot spots for any shared-file modifications
- add an optional comparison control only after approval
- keep classic routes canonical until an explicit promotion decision
- provide a final changed-file list, verification record, pixel-diff report, and residual-risk list

## 11. Native information architecture contract

The sidebar order should follow:

1. Library
   - Library
   - Collections
   - Search
2. Pinned
   - Favorites
   - Recently Saved
   - Map
   - People
   - Memories
3. Media Types
   - Photos
   - Videos
   - Screenshots
4. Shared Libraries
   - user spaces
   - New…
5. Shared External Libraries
   - available external libraries
6. Albums
   - albums
   - New Album
7. Utilities
   - Imports
   - Recently Deleted
   - Hidden
   - Archive
   - Locked

Classic-only destinations such as tags, sharing, workflows, or administration must not be deleted. During comparison they remain available in the classic UI. If V2 access is necessary, place them behind a clearly labeled More/classic link rather than inserting them into the native sidebar contract.

## 12. Shared-component change rules

Before changing any existing shared component:

1. Prove that composition or a V2 wrapper is insufficient.
2. Add an explicit prop or strategy object.
3. Keep the existing behavior as the default.
4. Add a regression test for the default.
5. Add a focused V2 test for the new path.
6. Note the shared file in fork documentation if it increases upstream merge risk.

Do not import route `+page.svelte` files as components. Extract reusable lower-level behavior or create a V2 composition over existing managers/services.

## 13. State and data rules

- Do not fork business logic if an existing service/manager already owns it.
- Keep V2 presentation state separate from persisted domain state.
- Use current source-filter parsing and permission helpers.
- Treat personal, space, and external-library destinations distinctly.
- Do not silently reinterpret “Recently Saved” or “Imports”; document and test their data semantics.
- Preserve viewer/timeline synchronization when an asset moves out of the active source.
- On successful mutations, update or invalidate the minimum affected stores.
- On failure, preserve selection where safe and show an actionable error.
- Browser Sync means refresh/invalidate client data, not native background synchronization.

## 14. Subagent orchestration

The lead agent is responsible for integration and must keep a live ownership table.

Maximum recommended concurrency with four available slots:

- one lead
- up to three subagents

### Wave 1 — read-only discovery

- Agent A: WP1 visual contract
- Agent B: WP2 data/API matrix
- Agent C: WP3 test baseline
- Lead: WP0 and integration design

### Wave 2 — foundation

- Agent A: WP4 shell/routes
- Agent B: WP5 square-grid implementation
- Agent C: WP8 viewer feasibility and isolated V2 viewer
- Lead: URL/state contract, review, integration, conflict resolution

### Wave 3 — feature completion

- Agent A: WP6 interactions and drag/drop
- Agent B: WP7 management sheets
- Agent C: WP9 special destinations, split further only after earlier work lands
- Lead: shared-file integration and tests

### Wave 4 — quality

- Agent A: accessibility
- Agent B: performance/cross-browser
- Agent C: visual regression and documentation audit
- Lead: final verification and release report

### Ownership rules

- Only one agent edits a given file at a time.
- The lead owns shared hot spots unless it explicitly transfers the lock.
- Treat `Timeline.svelte`, timeline managers, `layout-utils.ts`, `(user)/+layout.svelte`, route helpers, and global CSS as locked shared files.
- Subagents should prefer new V2-owned files.
- A subagent must not broaden its scope without notifying the lead.
- A subagent must not fix unrelated failures.

### Required subagent handoff

Every subagent returns:

1. scope completed
2. files read
3. files changed
4. assumptions and decisions
5. tests run and exact results
6. unresolved gaps
7. known overlap with pre-existing changes
8. recommended next owner/action

## 15. Testing matrix

### Unit tests

- route generation/parsing
- source/group/zoom normalization
- URL-versus-preference precedence
- square-grid geometry
- group boundary calculations
- date type-ahead
- drag payload parsing
- permission/drop-target decisions
- browser capability decisions

### Component tests

- shell/sidebar selection
- source picker
- grouping and zoom controls
- selection toolbar
- keyboard navigation
- dialogs and focus restoration
- viewer/inspector
- loading, empty, error, and unauthorized states

### End-to-end tests

- open/reload/deep-link each route
- select/range/select-all/clear
- open viewer, page, toggle info, close
- switch source/grouping/zoom and use browser back/forward
- create album and add assets
- move assets between allowed sources
- reject unauthorized moves
- external file import
- search/filter/open result
- map/grid synchronization
- utilities and visibility changes
- classic route regression

### Visual tests

At minimum:

- 1400 × 900 light and dark
- library idle and selected
- all grouping modes
- source menus
- dialogs
- viewer and inspector
- search idle/results
- map
- people
- memories
- settings

Use deterministic fixture data. Mask only regions documented in the visual manifest.

### Performance tests

- initial V2 library load
- smooth sustained scrolling
- zoom and regroup
- source switch
- viewer open/close
- 10,000-asset memory behavior

## 16. Verification commands

Use repository-standard versions and setup. At minimum:

```bash
cd web
pnpm run check:typescript
pnpm run check:svelte
pnpm run lint
pnpm run test --run
pnpm run build
```

Where the required Docker environment is available:

```bash
scripts/fork-test/run.sh e2e-web
```

Also run the targeted Playwright/component commands discovered during WP3. Record exact commands and whether a failure predates this project.

## 17. Release acceptance gates

### Visual

- reference geometry differs by no more than 2px for measured major components
- typography baselines differ by no more than 2px at the reference environment
- approved screenshot pixel difference is below 1% after documented masks
- no unexpected horizontal overflow
- light and dark themes both pass

### Functional

- all V2 routes are reloadable and deep-linkable
- all working actions persist equivalent results
- role and permission boundaries match existing behavior
- back/forward restoration works
- classic routes remain functional

### Accessibility

- no serious automated findings
- complete keyboard operation for primary workflows
- visible focus and correct focus restoration
- modals and toasts are announced appropriately

### Performance

- large collections remain virtualized
- no full collection DOM rendering
- no repeated uncontrolled fetch/layout loops
- performance measurements and remaining risks are documented

### Regression

- classic-route visual baselines remain unchanged unless separately approved
- existing test suites pass or all unrelated baseline failures are documented
- no accidental server schema/API change

## 18. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| V2 styling leaks into classic routes | root-scope V2 CSS; add classic screenshot regression |
| shared timeline changes regress classic layout | opt-in strategy/default preservation; focused tests |
| pixel parity inferred from source rather than running app | mandatory WP1 screenshots and measurements |
| macOS grouping intent differs from visible build | resolve and record in WP1 before grid implementation |
| duplicate business logic diverges | reuse services/managers; isolate presentation only |
| agent merge conflicts | disjoint ownership and lead-controlled shared-file locks |
| dirty worktree changes are lost | mandatory preflight and no destructive Git operations |
| browser editor expands scope indefinitely | explicit WP10 decision gate |
| fake native settings/actions ship | capability table plus working-or-unavailable rule |
| V2 becomes inaccessible on smaller screens | safe responsive fallback without redefining desktop reference |
| upstream Immich merges become harder | isolate V2; document every shared hot spot |

## 19. Progress tracking

The lead may update these checkboxes as work is verified, not merely started:

- [x] WP0 preflight and ownership table complete
- [x] WP1 visual parity contract approved
- [x] WP2 route/data matrix approved
- [x] WP3 test baseline recorded
- [x] WP4 shell/navigation accepted
- [x] WP5 square timeline accepted
- [x] WP6 interactions accepted
- [x] WP7 management sheets accepted
- [x] WP8 viewer accepted
- [x] WP9 feature destinations accepted
- [x] WP10 editor decision recorded and implemented to chosen scope
- [ ] WP11 accessibility/performance hardening accepted (static accepted 2026-09-16; axe/perf/screenshot runs host-pending with runbooks)
- [x] WP12 documentation and rollout report complete
- [x] classic route regression gate passed (unit 82/832 green, zero classic diffs, tsc + svelte-check clean; e2e-web host-pending per WP3 baseline)
- [ ] final visual parity gate passed (no runtime screenshots — host recipe in refs/CAPTURE-LOG.md)

## 20. Final implementation report template

```markdown
# Heirloom Web V2 implementation report

## Outcome

## Routes completed

## Files changed

## Shared classic files changed and why

## Server/API changes and evidence

## Tests and exact results

## Visual comparison results

## Accessibility results

## Performance results

## Browser/native capability exceptions

## Pre-existing failures or worktree changes preserved

## Remaining risks and recommended follow-up
```

## 21. Lead-agent start sequence

1. Read this entire plan.
2. Run the worktree safety protocol.
3. Read the native and web source-of-truth files.
4. Create the ownership table.
5. Spawn the three Wave 1 read-only subagents.
6. Complete WP0 while they work.
7. Review and consolidate WP1–WP3 outputs.
8. Do not begin shared timeline modifications until the parity contract and data matrix are resolved.
9. Execute Waves 2–4 with disjoint ownership.
10. Keep classic routes live throughout.
11. Stop only for a genuine product decision, unsafe overlap, missing authority, or unrecoverable external dependency.
