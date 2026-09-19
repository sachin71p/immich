Repo: /Users/spatel/workspace/github/projects/immich — Immich fork (branch feat/shared-libraries), server code in ./server, package manager pnpm.

Implement the plan in `.claude/plans/exif-all-tags/PLAN.md` exactly. Read it first — it is the single source of truth and its design decisions are final (separate `asset_exif_raw` table with jsonb `tags` / `sidecarTags`, helper move to `server/src/utils/exif.ts`, NUL-safe sanitizer, one extra task in `handleMetadataExtraction`, additive migration `1789426700282-AssetExifRaw.ts`, tests). Supporting facts with file:line references and templates are in `.claude/plans/exif-all-tags/scout-report.md`; line numbers may have drifted slightly, so verify before editing.

Hard constraints:
- Do NOT git commit or push. Leave the working tree uncommitted for me to review.
- Do NOT modify `docker-compose.yml` (it has unrelated uncommitted edits of mine).
- Do NOT touch web/, mobile/, e2e/, or any OpenAPI/DTO/controller code.
- Do NOT change the arguments of `readFullTags`, and do not change the behaviour of `GET /assets/:id/exif/full` (only move its two helper functions).
- Do NOT touch the running homelab servers (no ssh, no database access). This is a code-only task.
- Match surrounding style: ESM `.js` import suffixes, `// fork: exif-all-tags` comment marker, comment density of neighbouring code.

Start state: `git status --short` should show only ` M docker-compose.yml` and `?? .claude/plans/exif-all-tags/`. If anything else is present, stop and tell me before proceeding.

Definition of done: every item under "Definition of done" in PLAN.md passes, run from `/Users/spatel/workspace/github/projects/immich/server` — tsc, the three vitest files, eslint + prettier on changed files, and `git status` limited to the expected files. If a command cannot run here (e.g. it needs a database or docker), say so explicitly rather than claiming it passed.

Report back (<=25 lines): files changed, each command run with PASS/FAIL, anything not run and why, and any deviation from the plan with the reason. No file dumps.
