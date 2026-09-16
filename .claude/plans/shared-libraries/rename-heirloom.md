# Rename PhotosFork → Heirloom (full sweep)

## Goal
Zero case-insensitive occurrences of `photosfork` in tracked repo files.
Nothing is deployed, so bundle IDs, scheme/target names, file names, and
defaults keys may all change.

## Scope
All files listed by `git grep -il photosfork` at repo root
(`/Users/spatel/workspace/github/projects/immich`). This covers
`native-apple/` (code, `project.yml`, `scripts/verify.sh`, README) plus any
server/e2e/docs hits and the `.claude/plans/shared-libraries/` working docs
(living branch docs — safe to sed; only the `photosfork` token changes).

## Mapping rules (apply in this order)
1. Content replace, case-preserving: `PhotosFork` → `Heirloom`,
   `photosfork` → `heirloom`. This mechanically covers bundle IDs
   (`com.immich.photosfork.*` → `com.immich.heirloom.*`), BGTask identifier,
   entitlements path, extension principal-class strings, `UserDefaults` keys,
   notification names, file-path components (`PhotosFork/Media`,
   `PhotosForkStaging`, `PhotosForkExport-`), struct/class names, widget kind
   strings, `XCUIApplication` bundle-id strings, and `verify.sh`
   (`PhotosFork.xcodeproj` → `Heirloom.xcodeproj`, scheme names follow target
   renames). If any other case variant appears (e.g. `PHOTOSFORK`), mirror it
   the same way and report it.
2. File/dir renames via `git mv` for every tracked path containing the token
   (e.g. `PhotosFork.entitlements`, `PhotosForkIOSApp.swift`,
   `PhotosForkMacOSApp.swift`, agent/extension sources if matched). Do the
   `git mv`s first, then the content seds.
3. `CFBundleDisplayName`/`CFBundleName: Heirloom` keys already present on both
   app targets in `project.yml` — leave them.

## Safety valve
If a match looks like an external URL, an Apple-owned identifier, or anything
you cannot verify is ours, do NOT edit that line — finish everything else and
report it as an exception.

## Exclusions (do not touch)
`.git/`, `*/node_modules/*`, `DerivedData`, `.build`, generated
`*.xcodeproj` (regenerates from `project.yml`), untracked files
(`git status --short ??` — e.g. `e2e/test-assets/temp/` output), and git
history itself (past commit messages keep the old name).

## Verification gates (all must pass, report output)
1. `git grep -i photosfork -- .` → empty.
2. `cd native-apple && /opt/homebrew/bin/xcodegen generate` → exit 0.
3. Purity: every `+` diff line contains `heirloom` (any case) and every `-`
   diff line contains `photosfork` (any case) — i.e. no unrelated edits.
   Report `git status --short` and `git diff --stat`.
4. Do NOT run builds/tests (simulator + Docker need the host).

## Definition of done
Gates 1–4 pass, exceptions (if any) listed, work left uncommitted.
