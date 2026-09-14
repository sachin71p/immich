# A6 — Storage optimization (iOS "Free up space" R14, macOS cache budget)

Depends on: A5 · Reads: A0 Architecture+Rules · DECISIONS §2 (R14).
Pre-step: scout upstream Flutter "Free Up Space" (Immich 2.5) settings + verification logic in `mobile/lib` —
report the exact options, defaults and server checks ≤30 lines to `handoff/A6-scout.md`.

## iOS
1. Free up space (parity with upstream): cutoff date, keep favorites (default on), keep selected albums, plus
   "keep last N days". Candidate = device asset whose checksum exists on the server as a non-trashed asset the user
   can access (verify via server call at deletion time, not just local DB). Preview screen with counts + bytes,
   then `PHAssetChangeRequest.deleteAssets` in batches (system confirmation). Afterwards explain that iOS keeps
   them in Recently Deleted for 30 days and offer a deep link to Photos.
2. Optional automatic mode: run the check after each backup batch and prompt (never delete silently).
3. Cache: "Optimize storage" toggle → originals tier budget small, thumbnails kept; "Download originals" mode for
   pinned containers; usage screen per tier.

## macOS
4. Cache budget settings (like "Optimize Mac Storage"): budget slider, per-library/album "Keep originals on this Mac",
   usage breakdown, purge.

## Tests
Candidate selection matrix (cutoff, favorites, albums, N days, server-missing, server-trashed); batch sizing; budgets.

Verify: `native-apple/scripts/verify.sh all`.
