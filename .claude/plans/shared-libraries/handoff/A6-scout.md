# A6 scout — upstream Flutter "Free Up Space" (v2.5, PR #24999)
- 4-step wizard (`CleanupStep`): selectDate → filterOptions → scan → delete; entry via profile panel or Settings.
- Options: cutoff date REQUIRED (scan no-ops when null); filter all/photos-only/videos-only (`AssetFilterType`, default all); keepFavorites default true.
- Server check: local⨝remote on checksum + remote.owner == user + remote.deletedAt IS NULL (backed-up, not trashed) — via the synced local mirror, no live call.
- Excludes iCloud Shared Albums from the scan; delete = device trash; hint to empty the system gallery trash to reclaim space.
- Fork deltas (decided): verify-at-deletion via live batched bulk-check (never local-DB-only; drop server-missing/trashed); + keep-albums, keep-last-N-days, cutoff optional-but-bounded (unbounded = no candidates); post-backup prompt is explicit UI, never silent.
- Pins/budgets: upstream has no cache-budget UI — fork adds `StoragePrefs` (per-library pins, shared slider steps, iOS 256MB / mac 2GB defaults).
- Deep link: iOS exposes no public Recently-Deleted URL — `FreeUpSpaceLinks.recentlyDeletedAlbum` is a fixed best-effort constant; callers fall back to text.
