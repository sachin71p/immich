# Heirloom deployment — new LXC, Docker Compose, cloned DB, reorganized libraries

Supersedes `deploy-heirloom-prod.md` (in-place native upgrade). That plan assumed keeping 401 and
its DB. This one stands up a parallel instance and leaves 401 running untouched.

## Approach: subtractive, not fresh

You asked for a fresh DB, then asked to carry over users with password hashes, personal assets,
their DB rows, faces, embeddings and thumbs. That list *is* most of the database. Building it into
an empty schema means an ETL across ~20 foreign-keyed tables — the highest-risk operation available
here, and it buys nothing.

Same end state, no ETL: **clone the database, then delete what you're reorganizing.**

| | Fresh DB + ETL | Clone + delete |
|---|---|---|
| Users, password hashes, API keys | hand-migrate | survive untouched |
| 125,932 personal assets + rows | hand-migrate | survive untouched |
| 330,593 faces, CLIP embeddings | regenerate (GPU-days) | survive untouched |
| 96G thumbs / 1.3T transcodes | regenerate | survive untouched |
| 6 external libraries | don't create | delete (2 min) |
| 8 junk albums | don't create | delete (2 min) |

Deleting an external library removes its DB rows, **never the source files** under `/mnt/*`.

---

## Verified environment (homelab, 2026-09-15)

- **GPU**: NVIDIA RTX A4500, 20470 MiB, driver 580.159.03
- **Proven Docker+GPU template — LXC 405**: unprivileged, `features: fuse=1,keyctl=1,nesting=1`,
  `dev0`–`dev5` NVIDIA passthrough, Docker 29.7.2, nvidia-container-toolkit 1.20.0, `nvidia`
  runtime registered, `overlayfs` storage driver, `nvidia-smi` working inside. 401 uses identical
  `dev0`–`dev5` lines. **Copy 405's config verbatim.**
- **Free LXC IDs**: 403 (used below), 408+
- **Pools**: `seagate_hdd` 18.5T free (36% cap) · `zfs_proxmox` 1.47T free (56% cap)
- **Datasets to clone**: `seagate_hdd/apps/immich/library` (1.35T, laid out by *storageLabel*:
  `bhargavi` 1.4T, `spateladmin` 99M) · `zfs_proxmox/401/immich_cache` (1.30T = 96G thumbs +
  1.3T encoded-video)
- Autosnapshots already run on `seagate_hdd/apps/immich` — use a distinct manual snapshot name
  so the autosnap pruner never tries to destroy a clone origin.

### Runtime divergence from production — read before deploying

| | Production (LXC 401) | This fork |
|---|---|---|
| Immich version | `v3.2.0` (tagged release) | branched at `v3.2.0-rc.0`; `v3.2.0` merged 16-Sep |
| Module system | **CommonJS** (`server/package.json` has no `"type"`) | **ESM** (`"type": "module"`) |
| Framework | NestJS 11 | **NestJS 12** |

The fork carries `2a6262204 feat: NestJS 12 and ESM (#31237)` (2026-09-10, **626 files changed**),
which production does not have. **This is the largest fork↔production gap — larger than any feature
in the fork.** Earlier revisions of this plan described the base as "v3.2.0 + 98 commits" and judged
risk from the migration set alone; the schema conclusion still holds (identical apart from the two
fork migrations, so no reprocessing), but the *runtime* is a framework-major and module-system change.

It is not theoretical. The migration left `require()` calls in ESM modules, crashing every
transactional email (`NotifyAlbumInvite` → `ReferenceError: require is not defined`). Found and fixed
in-fork on 16-Sep; **upstream has not fixed it.** Assume other ESM paths that no test covers exist —
see `HOST-VERIFICATION-BRIEF.md` §2f.

Practical consequences for this plan:
- Tier-1 rollback (swap back to 401) still works — the schema is compatible in both directions.
- But a fork↔prod A/B comparison is not comparing one feature set; it is comparing two runtimes.
- Exercise notification paths explicitly after cutover. They are not covered by the fork's own tests.

> **ZFS clones make this nearly free.** Both are real datasets, so `zfs clone` yields an instant
> writable copy at ~0 bytes, growing only as it diverges. The earlier "zfs_proxmox can't hold a
> second cache" constraint does not apply.

---

## Phase 0 — gates (unchanged, still blocking)

1. **S2 access control** — 5 failing e2e album-access tests; fix mid-flight in `album.service.ts` /
   `access.ts`. Working tree must be clean.
2. **S10 upgrade gate** — NOT STARTED.

```bash
git status --porcelain     # empty
npm --prefix server run test
```

Also confirm the migration guard passes — no user may have `storageLabel = 'shared'`. Current
labels are `spateladmin`, `bhargavi`, `arpan`, `sachin`. ✅ clear today; re-check before running.

---

## Phase 1 — export the curation that the reorg would destroy

**This is the step that is easy to skip and impossible to redo.** Verified: your one genuinely
curated album is 100% external, so deleting libraries empties it.

| Item | Personal | External | Survives library delete? |
|---|---:|---:|---|
| Nov 2016 Wedding – Haldi & Garba | 0 | 686 | ❌ export it |
| Archived | 408 | 688 | ❌ partially |
| Recents | 66 | 0 | ✅ |
| Arpan Marriage / Portrait / tmp / restore* / mobile_* | — | — | intentionally dropped |

Run against **401** and keep the CSVs off-container:

```bash
pct exec 401 -- su - postgres -c "psql -d immich -Atc \"
COPY (SELECT a.\\\"albumName\\\", ast.\\\"originalPath\\\"
      FROM album a JOIN album_asset aa ON aa.\\\"albumId\\\"=a.id
      JOIN asset ast ON ast.id=aa.\\\"assetId\\\"
      WHERE a.\\\"albumName\\\" NOT IN ('mobile_photos','mobile_videos','restore2','restore3','tmp'))
TO '/tmp/keep_albums.csv' CSV HEADER;\""

pct exec 401 -- su - postgres -c "psql -d immich -Atc \"
COPY (SELECT \\\"originalPath\\\" FROM asset WHERE visibility='archive')
TO '/tmp/keep_archived.csv' CSV HEADER;\""

pct exec 401 -- su - postgres -c "psql -d immich -Atc \"
COPY (SELECT p.name, ast.\\\"originalPath\\\"
      FROM person p JOIN asset_face af ON af.\\\"personId\\\"=p.id
      JOIN asset ast ON ast.id=af.\\\"assetId\\\" WHERE p.name <> '')
TO '/tmp/keep_people.csv' CSV HEADER;\""
# ^ if asset_face's person column is named differently in 3.2.0, check with:
#   \d asset_face   — adjust the column name, don't skip the export.

pct pull 401 /tmp/keep_albums.csv   ./keep_albums.csv
pct pull 401 /tmp/keep_archived.csv ./keep_archived.csv
pct pull 401 /tmp/keep_people.csv   ./keep_people.csv
```

`originalPath` is the join key for restoring all three after the reorg.

---

## Phase 2 — create LXC 403

Clone 405's proven shape. Do **not** hand-roll the GPU lines.

```bash
pct create 403 local:vztmpl/debian-13-standard_*_amd64.tar.zst \
  --hostname heirloom --cores 12 --memory 24576 --swap 4096 \
  --rootfs vmdata:120 --net0 name=eth0,bridge=vmbr0,ip=dhcp,type=veth \
  --features nesting=1,keyctl=1,fuse=1 --unprivileged 1 \
  --ostype debian --timezone America/Chicago --onboot 1 \
  --tags heirloom;photos

for i in 0 1 2 3 4 5; do :; done
cat >> /etc/pve/lxc/403.conf <<'EOF'
dev0: /dev/nvidia0
dev1: /dev/nvidiactl
dev2: /dev/nvidia-uvm
dev3: /dev/nvidia-uvm-tools
dev4: /dev/nvidia-caps/nvidia-cap1
dev5: /dev/nvidia-caps/nvidia-cap2
EOF

pct start 403
pct exec 403 -- nvidia-smi --query-gpu=name --format=csv,noheader   # must print RTX A4500
```

If `nvidia-smi` fails, install the **same driver version as the host (580.159.03)** inside the
container with `--no-kernel-module`. The kernel module is the host's; the container needs only
userspace libs. Do not proceed until this prints the GPU.

Then Docker + toolkit, mirroring 405:
```bash
pct exec 403 -- bash -c "curl -fsSL https://get.docker.com | sh"
pct exec 403 -- bash -c "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
# add the repo, then:
pct exec 403 -- bash -c "apt-get update && apt-get install -y nvidia-container-toolkit && nvidia-ctk runtime configure --runtime=docker && systemctl restart docker"
pct exec 403 -- docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
```
That last command is the gate for Phase 4. It must print the A4500.

---

## Phase 3 — ZFS clones (instant, ~0 bytes)

```bash
STAMP=heirloom-seed-$(date +%Y%m%d)   # distinct from autosnap_* so the pruner ignores it

zfs snapshot seagate_hdd/apps/immich/library@$STAMP
zfs clone    seagate_hdd/apps/immich/library@$STAMP seagate_hdd/apps/heirloom/library

zfs snapshot zfs_proxmox/401/immich_cache@$STAMP
zfs clone    zfs_proxmox/401/immich_cache@$STAMP    zfs_proxmox/403/heirloom_cache

zfs list -o name,used,avail,origin | grep heirloom
```

Mount into 403. **External media is read-only** — the new instance must never write to `/mnt/*`:
```bash
pct set 403 \
 -mp1 /seagate_hdd/apps/heirloom/library,mp=/mnt/heirloom/library,replicate=0 \
 -mp2 /zfs_proxmox/403/heirloom_cache,mp=/mnt/heirloom/cache,replicate=0 \
 -mp3 /seagate_hdd/media/family,mp=/mnt/family,ro=1,replicate=0 \
 -mp4 /seagate_hdd/media/pictures,mp=/mnt/pictures,ro=1,replicate=0 \
 -mp5 /seagate_hdd/media/videos,mp=/mnt/videos,ro=1,replicate=0
```

Keep `/mnt/family`, `/mnt/pictures`, `/mnt/videos` at **identical paths to 401** — external asset
rows store absolute `originalPath`, and a path change marks every one of them offline.

> A clone pins its origin snapshot: `seagate_hdd/apps/immich/library` cannot be destroyed until you
> `zfs promote seagate_hdd/apps/heirloom/library`. Promote during Phase 10, not before.

---

## Phase 4 — build the image and compose the stack

### 4a. What one build produces

`server/Dockerfile` is a 7-stage build (`builder → sdk → plugin-sdk → server | web | cli | plugins
→ prod`). The final stage assembles all of them:

```
COPY --from=server  /output/server-pruned          ./server          # server/Dockerfile:96
COPY --from=web     /usr/src/app/web/build         /build/www        # server/Dockerfile:97
COPY --from=cli     /output/cli-pruned             ./cli             # server/Dockerfile:98
COPY --from=plugins .../plugin-core/dist           /build/plugins/…  # server/Dockerfile:99
```

So **one image contains server + web + CLI + plugins**. There is no separate web build or web
container. You build exactly one image; everything else is pulled.

### 4b. Build it

Build **on 403**, after Docker is confirmed working. Needs the repo (~2GB), ~20GB scratch for
layers, and network to ghcr.io — the base images are digest-pinned
(`base-server-dev:202608300913@sha256:1886…`, `base-server-prod:…@sha256:e809…`).

```bash
git clone --branch feat/shared-libraries <fork-url> /opt/heirloom/src
cd /opt/heirloom/src

docker build -f server/Dockerfile -t heirloom-server:local \
  --build-arg BUILD_ID=local \
  --build-arg BUILD_SOURCE_REF=feat/shared-libraries \
  --build-arg BUILD_SOURCE_COMMIT=$(git rev-parse HEAD) \
  .
```
Context is the **repo root**, not `server/`. The build args only feed the version strings shown in
the UI's About dialog — omit them and those render blank, which is cosmetic but makes it impossible
to tell which build you are running. Set them.

> **Expect the `plugins` stage to be the fragile one.** It pulls `mise` and downloads toolchains
> (`server/Dockerfile:67–78`), and `TESTING.md §8` already documents mise prerequisites as a known
> friction point for plugin and ffmpeg work. If the build fails, it will almost certainly fail here
> and not in the TypeScript stages. Build once early — before the LXC is otherwise ready — so a
> toolchain problem surfaces while it is cheap to fix.

If 403 turns out to be a bad build host, build anywhere with Docker and move it:
`docker save heirloom-server:local | ssh … 'pct exec 403 -- docker load'`.

### 4c. Compose — start from the repo's file, don't hand-roll

Use `docker/docker-compose.yml` and `docker/example.env` as the base and apply four changes. The
repo also ships the GPU fragments (`docker/hwaccel.transcoding.yml`, `docker/hwaccel.ml.yml`) —
use them via `extends` rather than writing device config by hand.

| Change | From (repo default) | To | Why |
|---|---|---|---|
| server image | `ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}` | `heirloom-server:local` | your fork |
| ML image | `…/immich-machine-learning:${IMMICH_VERSION:-release}` | `…:v3.2.0-cuda` | GPU inference; fork doesn't change ML |
| postgres | `postgres:14-vectorchord0.4.3-pgvectors0.2.0` | `postgres:16-vectorchord0.4.3-pgvectors0.2.0` | **your dump is from PG16 — a 16→14 restore fails** |
| GPU | commented-out `extends:` blocks | uncomment both | see below |

Copy `hwaccel.transcoding.yml` and `hwaccel.ml.yml` next to your compose file, then:

```yaml
  immich-server:
    image: heirloom-server:local
    extends:
      file: hwaccel.transcoding.yml
      service: nvenc          # capabilities: [gpu, compute, video] — `video` is what NVENC needs
    volumes:
      - /mnt/heirloom/library:/data/library
      - /mnt/heirloom/cache/thumbs:/data/thumbs
      - /mnt/heirloom/cache/encoded-video:/data/encoded-video
      - /mnt/family:/mnt/family:ro
      - /mnt/pictures:/mnt/pictures:ro
      - /mnt/videos:/mnt/videos:ro
      - /etc/localtime:/etc/localtime:ro

  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:v3.2.0-cuda
    extends:
      file: hwaccel.ml.yml
      service: cuda
```

Prefer these `extends` fragments over `runtime: nvidia`. Both work, but the fragments request the
`video` capability explicitly, are maintained upstream, and match how 405 already runs GPU
workloads.

> **Deliberate deviation:** upstream mounts a single `${UPLOAD_LOCATION}:/data`. We split `/data`
> into three mounts because your thumbs and encoded-video live on `zfs_proxmox` while originals live
> on `seagate_hdd`. Immich only ever addresses these as subdirectories of `IMMICH_MEDIA_LOCATION`,
> so mounting them individually is safe — but all three must be present or derivatives won't resolve.

Redis: keep the repo's pinned `docker.io/valkey/valkey:9@sha256:c123…`. Don't downgrade it.

### 4d. `.env`

From `docker/example.env`. **`IMMICH_MEDIA_LOCATION=/data`** must match the mounts above, or
existing `asset_file` rows won't resolve and the timeline renders blank.

```
IMMICH_MEDIA_LOCATION=/data
DB_DATA_LOCATION=/opt/heirloom/pgdata
DB_HOSTNAME=database
DB_USERNAME=postgres
DB_PASSWORD=<generate>
DB_DATABASE_NAME=immich
REDIS_HOSTNAME=redis
```

The fork renames nothing — env vars stay `IMMICH_*`, cookies stay `immich_access_token`, routes are
unchanged. Existing mobile clients authenticate against this instance as-is.

### 4e. Gate before Phase 5

```bash
docker compose up -d database redis && sleep 20
docker compose up -d
docker compose exec immich-server nvidia-smi          # must print RTX A4500
docker compose logs immich-machine-learning | grep -i cuda
```
Both must be green before you restore the database.

---

## Phase 5 — clone the database

```bash
# on 401 — quiesce first for a consistent dump
pct exec 401 -- systemctl stop immich-web immich-ml immich-dedup
pct exec 401 -- su postgres -c "pg_dump --clean --if-exists -d immich" | gzip > /tmp/immich.sql.gz
pct exec 401 -- systemctl start immich-web immich-ml immich-dedup   # 401 goes straight back to service
```
> Plain SQL, not `-Fc` — custom-format dumps interact badly with VectorChord columns on restore.
>
> Use `su postgres -c`, **not** `su - postgres -c` — the dash makes it a login shell, which prints
> the community-scripts container's ANSI MOTD banner to stdout ahead of the real `pg_dump` output.
> That banner gets piped straight into the gzip'd dump and shows up as ~6 syntax errors at the very
> top of the restore log (harmless — psql skips them and continues — but avoidable). Confirmed on
> 2026-09-16: banner contamination was confined to the first 17 lines, all-table row counts on
> restore matched the 401 baseline exactly (assets 218823, users 4, libraries 4, albums 9,
> people 7133), so this is cosmetic, not a data-integrity risk — but the `su postgres -c` form
> avoids it outright.
>
> Also expect ~19 `role "dedup_ro" does not exist` errors on restore — harmless, that role only
> exists for 401's separate `immich_dedup` database. And budget more than the dump's own runtime for
> downtime: the 2026-09-16 run took ~9 minutes end-to-end on a 5.4GB DB (2.0GB gzip'd dump), not the
> ~1-2 min a bare `pg_dump` estimate suggests — plan the maintenance window accordingly.

```bash
# on 403
docker compose up -d database && sleep 20
gunzip -c /tmp/immich.sql.gz | docker compose exec -T database psql -U postgres -d immich
docker compose up -d      # server applies the 2 fork migrations on boot
docker compose logs -f heirloom-server
```

Expect exactly `SharedLibraries` then `SpacePeople` to apply. Both are additive with working
`down()`, and `npm run migrations:revert` exists if you need to back one out.

**Checkpoint before touching anything:** log in with an existing password, confirm the timeline
renders with thumbnails (proves cloned derivatives resolve), and play a video (proves NVENC).
Asset count should read 218,824. If thumbnails are missing, `IMMICH_MEDIA_LOCATION` is wrong —
fix it here, before the reorg.

**Clean up the dump once the checkpoint is green.** The gzip'd dump is a full copy of every user's
personal photo metadata (paths, faces, people names) sitting in plaintext outside the DB — don't
leave it lying around longer than needed. Two copies exist by this point, host and 403:

```bash
rm -f /tmp/immich.sql.gz                              # on the Proxmox host
pct exec 403 -- rm -f /opt/heirloom/immich.sql.gz     # inside the container
```

Do this only after the checkpoint above passes — it's your only pre-migration restore point until
you trust the running instance. If you want a fallback a little longer (e.g. through Phase 6's
reorg), keep the host copy until then and delete it before Phase 10 decommission at the latest.

---

## Phase 6 — subtractive reorg

Only once Phase 5's checkpoint is green.

Delete via the **admin UI or API**, not SQL — the API cascades audit rows, cleans derivatives, and
queues the right jobs. SQL deletes will leave orphans.

1. Delete all six external libraries: Pictures, Videos, Family, Arpan Marriage, Bhargavi, Sachin.
   Removes 92,836 asset rows. **Source files under `/mnt/*` are untouched** (and mounted `ro`).
2. Delete the junk albums: `mobile_photos`, `mobile_videos`, `restore3`, `restore2`, `tmp`,
   `Portrait`, `Arpan Marriage`. Keep `Recents` (66 personal assets, unaffected).

What remains: 4 users with working passwords, 125,988 personal assets with every thumb, transcode,
face and embedding intact, 3 API keys, 73 tags, 368 memories, 1 partner link.

---

## Phase 7 — rebuild libraries, properly this time

The old layout worked around Immich's one-file-one-library rule with nested paths and exclusions:
`Pictures` (`/mnt/pictures`) shadowed `Bhargavi` and `Sachin` at subpaths — both sat at 0 assets
since 2026-02-09 — while `Family` carried a hand-written exclusion for `/mnt/family/arpan_marriage`
so `Arpan Marriage` could own that subtree.

Shared libraries is the feature that replaces that hack. Decide the target shape before importing:
one library per physical tree (`/mnt/pictures`, `/mnt/videos`, `/mnt/family`) with `library_member`
rows granting access, rather than one library per person with overlapping paths.

Import **one library at a time**, smallest first, verifying `isOffline = 0` and the expected asset
count between each. Leave the periodic scan and the file watcher **off** until the last one is clean.

---

## Phase 8 — restore curation

Re-apply the Phase 1 CSVs by matching `originalPath`:
- recreate `Nov 2016 Wedding – Haldi & Garba (date-fixed)` from `keep_albums.csv` (686 assets)
- re-apply `visibility='archive'` from `keep_archived.csv` (1,096)
- re-apply the 10 person names from `keep_people.csv`

Straightforward via the API once the new libraries have imported and paths resolve again.

---

## Phase 9 — transcode policy

Set target codec **HEVC** before any bulk video work. On the A4500 that is roughly half the storage
of the current h264 output and encodes faster.

Existing personal-asset transcodes were made under the old h264 policy and stay valid — Immich will
not re-encode them unless you explicitly run *Transcode Video (ALL)*. **Don't.** Let HEVC apply to
newly imported external video only; the mixed codecs cost nothing.

Then let the backfill run over days, watching `nvidia-smi` and the Jobs page. Thumbnails for newly
imported external assets regenerate too (~96G scale); personal thumbs are already there.

---

## Phase 10 — cutover and decommission

Run both instances in parallel until you trust 403.

1. Point phone backup at 403 and confirm new uploads land in the clone. **Until you do this, 401 is
   still receiving uploads that 403 will not have** — the clone diverges from that moment.
2. Move the DNS name / reverse-proxy entry to 403's IP.
3. Re-verify `immich-dedup` if you still want it — it reads the Immich schema directly and is not
   covered by any fork test.
4. Let 401 sit stopped but intact for two weeks.
5. Only then: `zfs promote seagate_hdd/apps/heirloom/library`, same for the cache clone, then
   destroy 401 and its datasets. Promotion must come first or you cannot free the origin.

## Rollback

Production is never modified, so rollback is: **stop 403, start 401.** That's the whole procedure.
401 keeps its dataset, its DB, and its GPU config throughout. Worst case you destroy 403 and its
two clones and start over having lost nothing.
