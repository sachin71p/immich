# Heirloom fork — production deployment runbook

Target: existing native (community-script) Immich in a Proxmox LXC, NVIDIA CUDA/NVENC,
media on the `seagate_hdd` zpool. Strategy: in-place upgrade, protected by snapshots.

Base facts established from the repo (verified, not assumed):

| Fact | Value | Why it matters |
|---|---|---|
| Fork base | upstream `v3.2.0` + 98 unreleased commits (`e55ac299a`, 2026-09-14) | You are deploying unreleased upstream code, not a tagged release |
| Upstream `v3.2.1` | NOT an ancestor of this branch | Don't assume parity with the latest release |
| New migrations | 2, fork-only: `1789426700279-SharedLibraries`, `1789426700280-SpacePeople` | The only schema delta |
| Migration shape | Purely additive — 9 new tables, nullable cols (`asset.spaceId`, `library.uploadPath`, `person.spaceId`), 1 new enum | No upstream table dropped or renamed |
| Reversibility | Both have complete `down()`; `npm run migrations:revert` exists | Real DB rollback, not just snapshot rollback |
| Migrations from the 98 upstream commits | **zero** | No hidden upstream schema work rides along |
| Thumbnail/preview version constants | unchanged since v3.2.0 | **No derivative regeneration** |
| Env vars / cookies / API routes | unchanged (`IMMICH_*`, `immich_access_token`, all existing routes) | Existing mobile + web clients keep their sessions |
| ML service | untouched by the fork (only upstream rknn/pyproject churn) | **Do not rebuild it — CUDA stays solved** |
| Personal asset storage paths | unchanged; shared spaces use a new `shared/{spaceId}/` namespace | Existing files stay exactly where they are |

---

## 0. STOP — two gates before any of this runs

**Gate 1 — S2 access control is failing.** `.claude/plans/shared-libraries/STATUS.md` reports 5
failing e2e album-access tests (viewer add/remove wrongly denied, owner wrongly denied, role-change
error message). The working tree still has uncommitted edits in `server/src/services/album.service.ts`
and `server/src/utils/access.ts` — the fix is mid-flight. A permissions bug in a system that is
about to gain shared spaces is the single worst class of bug to ship to real data.

**Gate 2 — S10 (upgrade gate) is NOT STARTED.** S10 is specifically the OpenAPI diff check,
upgrade test script, and merge rehearsal. That phase exists to answer the exact question this
runbook is asking. Deploying before it is skipping the check that was designed for this moment.

Minimum bar to proceed:
```
git status --porcelain          # must be empty
npm --prefix server run test    # green
# full e2e green, especially e2e/src/specs/server/api/fork/*
```

---

## 1. Native vs Docker — stay native

Given your setup, native is the lower-risk option, and it is not close:

- **Your CUDA/NVENC stack sits entirely outside the fork's diff.** NVENC transcoding is the server
  process shelling out to the existing ffmpeg binary; ML is a separate HTTP service the fork does
  not touch. Native means you never touch either one. Docker means re-solving GPU passthrough
  through LXC → docker → container, plus `nvidia-container-toolkit` inside an unprivileged LXC.
  That is a second hard problem bolted onto an already-risky upgrade.
- **Postgres + VectorChord already works.** Docker would push you toward the `immich-postgres`
  image or a hybrid host-postgres setup. More moving parts, no benefit.
- **Docker's real advantage is fast rollback — and the snapshot already gives you that**, plus the
  app-directory swap in §5 gives you docker-speed rollback natively.
- Docker-in-unprivileged-LXC also needs `nesting=1`, `keyctl=1`, and overlay2-on-ZFS workarounds.

There is no published image for your fork anyway — you build from source either way. Native just
means you build into a tree instead of a layer.

**Do not rebuild `machine-learning/`.** Leave `immich-ml.service` running untouched throughout.

---

## 2. Pre-flight (run against the RUNNING old instance, before anything stops)

Record the baseline so you can prove nothing was lost:

```bash
sudo -u postgres psql -d immich -c "
SELECT 'assets', count(*) FROM asset
UNION ALL SELECT 'not-deleted', count(*) FROM asset WHERE \"deletedAt\" IS NULL
UNION ALL SELECT 'albums', count(*) FROM album
UNION ALL SELECT 'libraries', count(*) FROM library
UNION ALL SELECT 'people', count(*) FROM person
UNION ALL SELECT 'asset_files', count(*) FROM asset_file;"
```

**Blocking check — the migration hard-fails on this:**
```bash
sudo -u postgres psql -d immich -c "SELECT id, name, \"storageLabel\" FROM \"user\" WHERE \"storageLabel\" = 'shared';"
# MUST return 0 rows. If not, rename that user's storage label first — 'shared' is now a
# reserved namespace (SharedLibraries.ts:4-13).
```

Record the running version and layout:
```bash
curl -s localhost:2283/api/server/version          # what you are upgrading FROM
systemctl list-units 'immich*'   # immich-web, immich-ml, immich-dedup (v3.2.0, Debian 13)
grep -vE '^\s*#' /opt/immich/.env                    # UPLOAD_LOCATION, DB_URL — note exact values
sudo -u postgres psql -d immich -c "SELECT id, name, \"importPaths\", \"exclusionPatterns\" FROM library;"
```

**In the old instance's admin UI, before upgrading, turn these OFF:**
- Administration → Settings → **Library** → disable periodic scan **and** the file watcher.
- Administration → Settings → **Storage Template** → confirm template migration is off.
- Administration → Settings → **Trash** → enable it, raise retention to 90 days.

These live in the `system_config` table and are read by the new binary at boot — this is how you get
"start with nothing scanning" without touching a single library path. See §7.

---

## 3. Snapshots (both layers, app stopped, DB quiesced)

**Verified topology (LXC 401, `homelab`, 2026-09-15).** Immich data spans THREE storage locations
across TWO pools. A seagate_hdd-only snapshot misses the 1.30T derivative cache.

| Data | Dataset | Size | Covered by |
|---|---|---:|---|
| Postgres 16 (`/var/lib/postgresql/16/main`) | `zfs_proxmox/vmdata/subvol-401-disk-0` (rootfs) | 58G used | `pct snapshot` |
| Uploaded originals → `/opt/immich/upload/library` | `seagate_hdd/apps/immich/library` | 1.35T | `zfs snapshot` |
| **thumbs + encoded-video** → `/opt/immich/upload/{thumbs,encoded-video}` | **`zfs_proxmox/401/immich_cache`** | **1.30T** | `zfs snapshot` |
| External media → `/mnt/{family,pictures,videos}` | `seagate_hdd/media/*` | 5.84T | `zfs snapshot` |

`/opt/immich/upload` itself (staging, `profile/`, `backups/`) is on the rootfs — covered by `pct snapshot`.
Bind mounts are NOT included in `pct snapshot`, which is why every row above needs its own `zfs snapshot`.

> `zfs_proxmox` has ~1.37T free against a 1.30T cache. Snapshots start near-zero and grow with
> divergence — fine for a short deploy window, but don't leave this one sitting for months.

Order matters — quiesce first so the snapshot is crash-consistent *and* logically consistent.

```bash
# --- inside LXC 401 ---
systemctl stop immich-web immich-ml immich-dedup
sudo -u postgres pg_dumpall --clean --if-exists | gzip > /root/immich-pre-heirloom-$(date +%F).sql.gz
ls -lh /root/immich-pre-heirloom-*.sql.gz      # sanity: not a 20-byte file
systemctl stop postgresql
```
> Use `pg_dumpall` (plain SQL), not `pg_dump -Fc` — custom-format dumps interact badly with the
> VectorChord vector columns on restore.
>
> Note `immich-dedup.service` + the `immich_dedup` database are a second consumer of this DB.
> Stop it too, and re-verify it after cutover — it is not covered by the fork's own tests.

```bash
# --- on the Proxmox host (homelab) ---
STAMP=pre-heirloom-$(date +%Y%m%d)

# Layer 1: LXC rootfs + config. This IS your Postgres backup. Bind mounts NOT included.
pct snapshot 401 $STAMP --description "pre Heirloom fork deploy"

# Layer 2: every bind-mounted dataset, BOTH pools.
zfs snapshot -r seagate_hdd/apps/immich/library@$STAMP    # uploaded originals  1.35T
zfs snapshot -r zfs_proxmox/401/immich_cache@$STAMP       # thumbs + encoded    1.30T  <-- easy to forget
zfs snapshot -r seagate_hdd/media/family@$STAMP           # external sources
zfs snapshot -r seagate_hdd/media/pictures@$STAMP
zfs snapshot -r seagate_hdd/media/videos@$STAMP

# Verify all six exist before proceeding:
pct listsnapshot 401
zfs list -t snapshot | grep $STAMP     # expect 5 rows
```

The `seagate_hdd/media/*` snapshots are belt-and-braces: Immich never writes to external library
sources, so a bad scan corrupts DB rows, not files. They are ~free on ZFS, so take them anyway.

There is also a `zfs_hdd_28tb_backup` replica of both pools as a third line of defence — confirm its
last sync timestamp before you start, but do not treat it as a substitute for the snapshots above.

Restart Postgres; leave the app services stopped.

---

## 4. Build and cut over

Build **beside** the running install, not over it. This is what makes rollback cheap.

```bash
cd /opt/immich
mv app app.prod-$(curl -s localhost:2283/api/server/version | jq -r .major.minor 2>/dev/null || echo prev)
# ^ keep the old built tree. This directory IS your fast rollback.

git clone --branch feat/shared-libraries <your-fork-url> /opt/immich/src-heirloom
cd /opt/immich/src-heirloom
```

Build in dependency order (this is the order the upstream Dockerfile uses — the SDK must exist
before web compiles):
```bash
npm --prefix open-api/typescript-sdk ci && npm --prefix open-api/typescript-sdk run build
npm --prefix web ci  && npm --prefix web  run build
npm --prefix server ci && npm --prefix server run build
```

Assemble the new `app/` to match the layout your old `app.prod-*` has — compare the two trees before
starting anything. Leave `machine-learning/` and its venv pointing at the **existing untouched**
install; do not copy a new one in.

```bash
diff <(find /opt/immich/app.prod-* -maxdepth 2 -type d | sed 's|.*app.prod-[^/]*||' | sort) \
     <(find /opt/immich/app        -maxdepth 2 -type d | sed 's|.*app||' | sort)
```

Then run migrations **explicitly, before starting the service**, so a migration failure is a clean
stop rather than a half-started server:
```bash
cd /opt/immich/app/server   # or wherever DB_URL resolves
DB_URL="<from .env>" npm run migrations:run
```
Expect exactly two to apply: `SharedLibraries`, then `SpacePeople`.

Start it:
```bash
systemctl start immich-ml immich-web
journalctl -u immich-web -f
```

---

## 5. Rollback tiers (know these before you need them)

| Tier | Action | Time | Cost |
|---|---|---|---|
| **1 — app only** | `mv app app.heirloom; mv app.prod-* app; systemctl restart immich-web` | ~1 min | none |
| **2 — app + schema** | `npm run migrations:revert` ×2, then tier 1 | ~5 min | loses only fork tables (all empty on day 1) |
| **3 — full restore** | `pct rollback $CTID $STAMP` + `zfs rollback seagate_hdd/<ds>@$STAMP` | ~15 min | **loses every upload and edit made since the snapshot** |

Tier 1 is likely sufficient on its own because the migrations are additive — old code ignores new
nullable columns and unknown tables. *Likely* is not *verified*: Immich 3.x has a schema-drift check
that may log warnings. **Test tier 1 deliberately** right after cutover, while the system is still
empty of new writes, so you know which tier you actually have.

Tier 3 is one-way. Once real uploads land post-cutover, tier 3 stops being a rollback and starts
being data loss — at that point you are committed to fixing forward.

---

## 6. Verification, before opening it up

```bash
# Counts must match §2 exactly:
sudo -u postgres psql -d immich -c "SELECT count(*) FROM asset WHERE \"deletedAt\" IS NULL;"

# Fork tables must exist and be EMPTY:
sudo -u postgres psql -d immich -c "
SELECT 'spaces', count(*) FROM shared_space
UNION ALL SELECT 'relocations', count(*) FROM asset_relocation;"
# ^ asset_relocation MUST be 0. The fork runs AssetRelocateQueueAll on bootstrap and nightly;
#   a non-empty table here means files are about to be moved on disk.

# Nothing went offline:
sudo -u postgres psql -d immich -c "SELECT \"isOffline\", count(*) FROM asset GROUP BY 1;"
```

In the UI: existing timeline loads with thumbnails (proves derivatives were reused), an existing
album opens, a video plays (proves NVENC path intact), face/person groupings still present, mobile
app still logged in (proves cookies unchanged), and an existing external library's assets are
browsable. Confirm the Jobs page shows no unexpected queue draining.

---

## 7. Your two questions, answered directly

### "Start with no library paths, then add them back one by one?"

**No — that is actively dangerous, and it's not what you want.** You are reusing the same database,
so your libraries already exist as rows with their `importPaths` intact. If you blank those paths
(or the mount is missing) and a scan runs, Immich marks every asset it can't find at its
`originalPath` as **offline**, and offline external assets get trashed. You'd be manufacturing the
exact data-loss event you're trying to snapshot against.

The safe version of the same instinct is **freeze the scanner, not the paths** — which is why §2 has
you disable the periodic library scan and the file watcher *in the old instance* before upgrading.
The new binary boots with them off. Then:

1. Boot, verify §6 with nothing scanning.
2. Re-enable scanning, and manually trigger a scan on **one** library — pick the smallest.
3. Confirm zero new `isOffline` rows and no unexpected asset count change.
4. Repeat one library at a time. Re-enable the periodic cron only after the last one is clean.

Optional hardening: mount the library sources read-only on the LXC `mp` entries for the first boot.
That makes an accidental write physically impossible rather than merely disabled.

### "Does it reprocess every media file, or can we keep existing thumbs and encodes?"

**Nothing is reprocessed. Everything is reused.** Verified, not assumed:

- Thumbnails, previews, and encoded video live under `UPLOAD_LOCATION` in `thumbs/` and
  `encoded-video/`, keyed by asset UUID, with `asset_file` rows pointing at them. Same DB + same
  `UPLOAD_LOCATION` = every derivative is found and served.
- No thumbnail/preview version constant changed between v3.2.0 and this branch, so nothing
  invalidates existing derivatives.
- The fork's storage change is **additive**: shared spaces get a new `shared/{spaceId}/` namespace.
  Personal asset paths are untouched (`server/src/cores/storage.core.ts:115-142`).
- ML embeddings survive too, because the ML model is unchanged and you aren't rebuilding that
  service. Smart search keeps working without re-indexing.

Two things that *would* cause mass reprocessing — avoid both:
- **Never run "Regenerate Thumbnails (ALL)"** or "Encode Video (ALL)" out of curiosity post-upgrade.
  Use the MISSING variants only.
- **Never change the storage template** during this deployment. Template migration rewrites paths
  for every asset on disk; combined with a fresh fork that's a bad week.

---

## 8. Suggested sequencing

1. Close Gate 1 and Gate 2. *(This is the long pole, and it is not a deployment task.)*
2. §2 pre-flight + settings freeze — can be done days ahead, on the live system, zero downtime.
3. Pick a window with no phone auto-backup running. §3 snapshots.
4. §4 build + cutover. §6 verify.
5. Deliberately exercise tier-1 rollback, then roll forward again.
6. §7 libraries, one at a time, over the following days.
7. Keep both snapshots for at least two weeks. Delete the ZFS one last.

> **Superseded** by `deploy-heirloom-docker.md` — the plan changed to a parallel Docker instance in a new LXC with a cloned DB. Kept for the in-place-upgrade analysis.
