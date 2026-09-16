# Heirloom deployment — new LXC, Docker Compose, cloned DB, reorganized libraries

Supersedes `deploy-heirloom-prod.md` (in-place native upgrade). That plan assumed keeping 401 and
its DB. This one stands up a parallel instance and leaves 401 running untouched.

## Status as of 2026-09-16

**Done:** Phase 0 (gates green), Phase 2 (LXC 403 up, GPU verified), Phase 3 (clones + mounts —
layout changed from what's below, see Phase 3), Phase 4 (image built, stack running), Phase 5 (DB
cloned/restored/verified). **Not started:** Phase 1 (curation export — do this before Phase 6, not
optional), Phase 6-10.

Execution diverged from the plan below in several material ways — each is called out inline where
it happened, but the two biggest:
- **External mounts (`/mnt/family`, `/mnt/pictures`, `/mnt/videos`) are now writable, not
  read-only.** The plan's original stance ("the new instance must never write to `/mnt/*`") turned
  out to be incompatible with the shared-libraries feature itself — "move asset to shared library"
  physically relocates the file and deletes the original, which requires write access. See Phase 3.
- **Media paths are `/mnt/heirloom/{library,thumbs,encoded-video,upload,profile,backups}`**, mirroring
  the LXC's own paths 1:1 inside the container, not the plan's original `/data/*` scheme. See Phase 4c/4d.

The dump cleanup step in Phase 5 has **not** been done yet — both copies (`heirloom-seed.sql.gz` on
the Proxmox host and inside 403) are still present.

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

Mount into 403. **As executed 2026-09-16, actual mount layout differs from the original plan** —
the cache dataset got split into two direct mounts (so thumbs/encoded-video land at
`/mnt/heirloom/thumbs` and `/mnt/heirloom/encoded-video`, not nested under a `cache/` dir), and
external media ended up **writable**, not read-only:

```bash
pct set 403 \
 -mp1 /seagate_hdd/apps/heirloom/library,mp=/mnt/heirloom/library,replicate=0 \
 -mp3 /seagate_hdd/media/family,mp=/mnt/family,replicate=0 \
 -mp4 /seagate_hdd/media/pictures,mp=/mnt/pictures,replicate=0 \
 -mp5 /seagate_hdd/media/videos,mp=/mnt/videos,replicate=0 \
 -mp6 /zfs_proxmox/403/heirloom_cache/thumbs,mp=/mnt/heirloom/thumbs,replicate=0 \
 -mp7 /zfs_proxmox/403/heirloom_cache/encoded-video,mp=/mnt/heirloom/encoded-video,replicate=0
```

Keep `/mnt/family`, `/mnt/pictures`, `/mnt/videos` at **identical paths to 401** — external asset
rows store absolute `originalPath`, and a path change marks every one of them offline.

> A clone pins its origin snapshot: `seagate_hdd/apps/immich/library` cannot be destroyed until you
> `zfs promote seagate_hdd/apps/heirloom/library`. Promote during Phase 10, not before.

### Read-only vs. writable external mounts — why the plan changed

The original plan mounted `/mnt/family`, `/mnt/pictures`, `/mnt/videos` `ro=1` on the theory that
the new instance should never be able to touch the real NAS files. That held until testing the
fork's actual headline feature: **"move asset to shared library"** copies the file into managed
storage (`/mnt/heirloom/library/shared/{spaceId}/...`) and then deletes the original — by design,
so you don't end up with permanent duplicates. With `ro=1`, the delete step throws `EROFS`, the job
retries and fails repeatedly, and each retry leaves behind another orphaned copy at the destination
(observed: 3 duplicate copies of the same file before the DB was even updated to point at any of
them).

Decision made 2026-09-16: drop `ro=1`. The blast radius is narrower than "arbitrary write access" —
the relocation job only ever deletes a source file *immediately after* successfully copying that
exact file elsewhere, as part of an explicit move a user triggers. If you want the read-only
guarantee back, "move to shared library" cannot be used on external-library assets; every such move
will need the same manual cleanup done for the one test asset (copy file by hand, delete duplicates,
patch `originalPath`, all while the app is down or the asset is otherwise untouched).

### UID-mapping gotcha — read this before touching any file under `/mnt/heirloom` or `/mnt/{family,pictures,videos}` at the host level

403 is an **unprivileged LXC** (`unprivileged: 1`, no custom `lxc.idmap`), using Proxmox's default
subuid/subgid range `root:100000:65536` (`/etc/subuid`, `/etc/subgid` on the host). That means
container-internal UID 0 (root) maps to host UID 100000, and container-internal UID 999 (the UID
the Immich Docker image runs as, matching 401's own native `immich` system user — confirmed via
`pct exec 401 -- id immich` → `uid=999(immich) gid=991(immich)`) maps to **host UID 100999, GID
100991**.

Consequence: anything you `chown`/`cp`/`mkdir` **from the Proxmox host** (as real root) into a
path that 403's containers need to read or write must be owned at the host level by **`100999:100991`**,
not `999:991` — the latter is a coincidental, unrelated host account (`dnsmasq:crontab` on this
host) and produces silent, confusing "Permission denied" errors from inside the container that look
like a completely different problem. Hit this twice on 2026-09-16:

1. The ZFS-cloned library dataset (`seagate_hdd/apps/heirloom/library`) had a mix of ownership —
   some subdirs correctly `100999:100991` already, others (notably the top-level `.immich` marker
   and one user's personal folder) owned by real `root:zfs_users`, left over from a root-run
   maintenance operation on 401 at some point. Fixed with a single recursive
   `chown -R 100999:100991 /seagate_hdd/apps/heirloom/library` (takes seconds — it's metadata-only).
2. After dropping `ro=1` on family/pictures/videos (see above), deleting a relocated file's original
   still failed — those datasets carry ownership from however they were originally populated on
   401 (not uniformly `immich`'s own UID). Fixed the same way:
   `chown -R 100999:100991 /seagate_hdd/media/family /seagate_hdd/media/pictures /seagate_hdd/media/videos`
   (~5TB, still fast — chown doesn't touch file content). **Verified this doesn't break 401's own
   access**: 401 maps through the identical default subuid range, so files owned at host
   `100999:100991` resolve inside 401 as `immich:immich`, exactly as before — checked directly
   (`pct exec 401 -- ls -la /mnt/family/...` still shows `immich immich`) and confirmed 401 can
   still write there post-chown.

If you ever need to manually place or fix a file under any of these mounts again, chown it to
`100999:100991` from the host — not `999:991`, not by "running as root" inside the container (which
is real root inside 403, not privileged root on the host — subject to the exact same UID mapping).

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

> **Confirmed 2026-09-16: the plugins-stage warning above was exactly right, but the actual failure
> was DNS, not mise/toolchain availability.** `mise install` (fetching the Java toolchain) failed
> with `dns error: failed to lookup address information: Temporary failure in name resolution` —
> BuildKit runs each `RUN` step in its own isolated network namespace, which under nested
> virtualization (Docker inside an unprivileged LXC) can't reliably resolve DNS even though the
> LXC's own network (used by `git clone`, `apt-get`, `docker pull`, all of which worked fine) is
> completely healthy. Other `RUN` steps (npm registry fetches) hit the same `EAI_AGAIN` errors but
> survived via npm's own retry-with-backoff; `mise install` has no such retry and just fails outright
> on the first hiccup. **Fix: add `--network=host` to the `docker build` command** — this makes every
> `RUN` step share the LXC's own (working) network namespace instead of BuildKit's isolated one:
> ```bash
> docker build --network=host -f server/Dockerfile -t heirloom-server:local \
>   --build-arg BUILD_ID=local \
>   --build-arg BUILD_SOURCE_REF=feat/shared-libraries \
>   --build-arg BUILD_SOURCE_COMMIT=$(git rev-parse HEAD) \
>   .
> ```
> This got past the plugins stage on the first retry with no other changes.

### 4c. Compose — as actually deployed (2026-09-16), not the original draft

The compose file below is what's actually running. It differs from the earlier draft in three
ways: no "immich" anywhere in service names, container names, or image tags (per explicit
preference); paths mirror the LXC exactly (`/mnt/heirloom/...`) instead of a `/data` remap; and
`upload/`, `profile/`, `backups/` are mounted too (see 4d — the earlier draft missed these, and the
server won't boot without them).

Upstream images get retagged locally so no "immich" string appears in `docker images`:
```bash
docker tag ghcr.io/immich-app/immich-machine-learning:v3.2.0-cuda heirloom-ml:v3.2.0-cuda
docker tag ghcr.io/immich-app/postgres:16-vectorchord0.4.3-pgvectors0.2.0@sha256:<digest> \
  heirloom-postgres-base:16-vectorchord0.4.3-pgvectors0.2.0
```

`docker-compose.yml` (`/opt/heirloom/docker-compose.yml`):
```yaml
name: heirloom

services:
  server:
    container_name: server
    image: heirloom-server:local
    extends:
      file: hwaccel.transcoding.yml
      service: nvenc          # capabilities: [gpu, compute, video] — `video` is what NVENC needs
    volumes:
      - /mnt/heirloom:/mnt/heirloom
      - /mnt/family:/mnt/family
      - /mnt/pictures:/mnt/pictures
      - /mnt/videos:/mnt/videos
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    ports:
      - '2283:2283'
    depends_on:
      - redis
      - database
    restart: always
    healthcheck:
      disable: false

  machine-learning:
    container_name: machine-learning
    image: heirloom-ml:v3.2.0-cuda
    extends:
      file: hwaccel.ml.yml
      service: cuda
    volumes:
      - model-cache:/cache
    env_file:
      - .env
    restart: always
    healthcheck:
      disable: false

  redis:
    container_name: redis
    image: docker.io/valkey/valkey:9@sha256:c123e3715db63d06d4ad6964884037aa0d5d4d703939b9929954112889708e1d
    healthcheck:
      test: redis-cli ping | grep -q PONG || exit 1
    restart: always

  database:
    container_name: database
    image: heirloom-postgres-base:16-vectorchord0.4.3-pgvectors0.2.0
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data
    shm_size: 128mb
    restart: always
    healthcheck:
      disable: false

volumes:
  model-cache:
```

Prefer these `extends` fragments over `runtime: nvidia`. Both work, but the fragments request the
`video` capability explicitly, are maintained upstream, and match how 405 already runs GPU
workloads.

> **Single bind mount, not three.** `/mnt/heirloom:/mnt/heirloom` covers `library/`, `thumbs/`,
> `encoded-video/`, `upload/`, `profile/`, `backups/` in one line since they're all real children of
> that path on the LXC (see Phase 3's mount layout). Immich only ever addresses these as fixed-name
> subdirectories of `IMMICH_MEDIA_LOCATION`, so this works as long as all six are actually present
> under the mount — derivatives silently fail to resolve if any are missing.

Redis: keep the repo's pinned `docker.io/valkey/valkey:9@sha256:c123…`. Don't downgrade it.

> **nvidia-container-cli cgroup/BPF failure — hit this bringing the stack up, not in Phase 2's plain
> `docker run` GPU test.** The ML container failed to start with:
> `nvidia-container-cli: mount error: ... bpf_prog_query(BPF_CGROUP_DEVICE) failed: operation not permitted`.
> Phase 2's `docker run --rm --runtime=nvidia --gpus all ...` smoke test had already passed — the
> failure only appeared once compose's `deploy.resources.reservations.devices` GPU declaration was
> used instead of a bare `--gpus all` flag, which apparently routes through a code path that tries
> to manage cgroup device rules via eBPF — something an unprivileged LXC can't grant, regardless of
> `nesting=1`/`keyctl=1`. Fix: disable cgroup management in the toolkit, since the LXC's own
> `dev0`-`dev5` passthrough already grants device access and further cgroup restriction inside is
> both redundant and broken here:
> ```bash
> sed -i '/\[nvidia-container-cli\]/a no-cgroups = true' /etc/nvidia-container-runtime/config.toml
> systemctl restart docker
> ```
> Confirmed this doesn't need repeating per-container — it's a one-time daemon config change.

### 4d. `.env`

From `docker/example.env`, adapted. **`IMMICH_MEDIA_LOCATION` must match the mount above**, or
existing `asset_file` rows won't resolve and the timeline renders blank. `DB_DATABASE_NAME` is
`heirloom`, not `immich` — the restored database gets renamed as part of the "no immich anywhere"
naming pass (see Phase 5).

```
DB_DATA_LOCATION=/opt/heirloom/pgdata
DB_PASSWORD=<generate>
DB_USERNAME=postgres
DB_DATABASE_NAME=heirloom
DB_HOSTNAME=database
REDIS_HOSTNAME=redis
IMMICH_MEDIA_LOCATION=/mnt/heirloom
TZ=America/Chicago
```

> **`upload/`, `profile/`, `backups/` are not on any ZFS dataset cloned in Phase 3** — on 401 they
> live directly on the LXC's own rootfs under `/opt/immich/upload/{upload,profile,backups}`, not on
> `seagate_hdd/apps/immich/library` or `zfs_proxmox/401/immich_cache`. The server won't pass its own
> boot-time mount check without them (`Failed to read .../upload/.immich: ENOENT`, then the same for
> `profile`, then `backups`, one at a time as each gets added). `profile/` (avatars, ~1KB) and
> `upload/` (staging, ~34MB) are worth carrying over — `tar` them off 401 and extract into
> `/mnt/heirloom/{upload,profile}`. **Skip `backups/`** — on 401 it's 22GB of Immich's own
> automatic Postgres dump backups, not source data; just create an empty
> `/mnt/heirloom/backups/.immich` marker file and let the new instance generate its own going
> forward. Whatever you copy in from 401 needs the UID-mapping fix from Phase 3 applied too
> (`chown 999:991` from *inside* the container, since these came via `tar`/`pct exec` and already
> carry the right container-relative UID — no host-level `100999` offset needed for this specific
> path since nothing crossed the container boundary as a raw file, only as a tar stream extracted
> from inside 403's own namespace).

The fork renames nothing at the **application** level — env vars stay `IMMICH_*`, cookies stay
`immich_access_token`, routes are unchanged. Existing mobile clients authenticate against this
instance as-is. The "no immich anywhere" naming only touches things under our own control:
container/service names, image tags, the Postgres database name, and file names we chose ourselves.

### 4e. Gate before Phase 5

```bash
docker compose up -d database redis && sleep 20
docker compose up -d
docker compose exec machine-learning nvidia-smi        # confirmed: prints RTX A4500
docker compose logs machine-learning | grep -i cuda
```
Both must be green before you restore the database. **Not yet independently re-confirmed on the
`server` container specifically** (i.e. an explicit NVENC transcode test) — worth doing before
relying on hardware transcoding in anger.

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
# on 403 — the target DB inside the container is created as "immich" by default (matches
# DB_DATABASE_NAME at container-create time); rename it to "heirloom" before restoring so the
# rest of the naming pass is consistent, then restore into the renamed DB
docker compose up -d database && sleep 20
docker exec -i database psql -U postgres -c "ALTER DATABASE immich RENAME TO heirloom;"
gunzip -c heirloom-seed.sql.gz | docker exec -i database psql -U postgres -d heirloom
docker compose up -d      # server applies the fork migrations on boot
docker compose logs -f server
```

Expect `SharedLibraries` then `SpacePeople` to apply — **unless pre-existing data violates the new
`asset_container_not_locked` constraint, see below.** Both are additive with working `down()`, and
`npm run migrations:revert` exists if you need to back one out.

> **Migration blocker hit 2026-09-16: pre-existing PIN-locked assets inside an external library.**
> `SharedLibraries` adds `CHECK (visibility != 'locked' OR (spaceId IS NULL AND libraryId IS NULL))`
> — a locked (PIN-hidden) asset can no longer belong to a library or space, since either one implies
> other people can reach the underlying file, defeating the lock. Real data can violate this: we had
> 148 rows where a user had PIN-locked specific photos that also happened to sit inside an external
> library (`visibility='locked'` AND `libraryId` set). The migration transaction fails outright and
> rolls back completely — the server won't boot until this is resolved, and there is no backfill in
> the fork's own migrations for it (checked; none exists).
>
> **Do not just unlock them** — that's real, deliberately-hidden personal data. The fix that
> actually preserves the lock: detach each affected asset from its library (mirroring what
> `AssetRelocationService`/`SharedSpaceRepository.deleteSpace` already do for the analogous
> space-deletion case) while keeping `visibility='locked'` untouched:
> 1. Find them: `SELECT id, "originalPath" FROM asset WHERE visibility='locked' AND "libraryId" IS NOT NULL;`
> 2. Copy each file from its external (library) path into the owner's personal storage —
>    `/mnt/heirloom/library/<storageLabel>/<year>/<month>/<original filename>`, matching the path
>    convention already used by that user's existing personal assets. **Do this from the Proxmox
>    host** (real root), not `pct exec` — the destination directories are owned by mapped UIDs the
>    unprivileged container's root can't write into cleanly, then `chown 100999:100991` the new
>    files (see the UID-mapping note in Phase 3).
> 3. `UPDATE asset SET "libraryId" = NULL, "originalPath" = '<new path>' WHERE id = '<id>';` — leave
>    `visibility` alone.
> 4. Re-verify `SELECT count(*) FROM asset WHERE visibility='locked' AND "libraryId" IS NOT NULL;` is
>    `0`, then restart the server so the migration can complete.
>
> This is exactly the kind of case-by-case data fix Phase 6's "delete via API, not SQL" rule is
> meant to avoid — but the migration can't get far enough to expose the API for these specific rows,
> so it's a deliberate, narrow exception. Verified afterward: locked-asset count unchanged (202
> before and after, just 148 of them now personal instead of library-owned), files byte-identical to
> the originals (checksum match), and the assets remain invisible to non-owners exactly as before.

**Automatic path rewrite on every `IMMICH_MEDIA_LOCATION` change.** Once migrations succeed, the
server detects "media location changed" and runs a one-time `UPDATE asset SET "originalPath" =
REGEXP_REPLACE(...)` across every asset whose path starts with the *previous* location — this is
normal Immich behavior, not fork-specific, and ran twice in this deployment (once when we first set
`IMMICH_MEDIA_LOCATION=/data`, again when we switched to `/mnt/heirloom` per Phase 4c/4d). It's a
real bulk UPDATE across all ~219k rows and took a couple of minutes each time; watch
`pg_stat_activity` for a query matching `originalPath.*REGEXP_REPLACE` if the server seems to hang
on boot — it isn't hung, it's rewriting paths. External-library assets (`/mnt/family/...` etc.)
correctly don't match the old-location prefix and are left alone.

**Checkpoint before touching anything:** log in with an existing password, confirm the timeline
renders with thumbnails (proves cloned derivatives resolve), and play a video (proves NVENC).
Asset count should read 218,823 (not 218,824 as originally estimated — confirmed exact row-count
match against the live 401 baseline captured immediately before quiescing it). If thumbnails are
missing, `IMMICH_MEDIA_LOCATION` is wrong — fix it here, before the reorg.

**Clean up the dump once the checkpoint is green.** The gzip'd dump is a full copy of every user's
personal photo metadata (paths, faces, people names) sitting in plaintext outside the DB — don't
leave it lying around longer than needed. Two copies exist by this point, host and 403:

```bash
rm -f /tmp/heirloom-seed.sql.gz                              # on the Proxmox host
pct exec 403 -- rm -f /opt/heirloom/heirloom-seed.sql.gz     # inside the container
```

Do this only after the checkpoint above passes — it's your only pre-migration restore point until
you trust the running instance. If you want a fallback a little longer (e.g. through Phase 6's
reorg), keep the host copy until then and delete it before Phase 10 decommission at the latest.

**Still outstanding as of 2026-09-16: this cleanup hasn't been run yet.** Both copies are still present.

### A second, unrelated migration bug found and fixed the same day

Schema-drift check on boot flagged: `The index "shared_space"."shared_space_clusterGroupId_idx" is
missing and needs to be created`. Root cause: `1789426700280-SpacePeople.ts` adds
`shared_space.clusterGroupId` and its FK, and — two lines above — adds `person.spaceId` with a
matching `CREATE INDEX`, but never added the equivalent index for `clusterGroupId`. Genuine
oversight, not intentional.

Since that migration had already been applied to this DB, the fix is a new follow-up migration
(`server/src/schema/migrations/1789426700281-SharedSpaceClusterGroupIdIndex.ts`, registered in the
`ORDER` file) rather than editing the already-applied one — standard practice, and it means the fix
also lands correctly on 401's eventual in-place upgrade. Rebuild the image and restart the server to
apply it; confirmed clean (`No schema drift detected`) afterward.

### Log noise to expect right after changing external-mount ownership, not a real problem

If you do the Phase 3 UID-mapping `chown` across `/mnt/family`/`/mnt/pictures`/`/mnt/videos` while
the stack is running (or restart shortly after), expect a burst of
`LibrarySyncFiles: duplicate key value violates unique constraint "asset_ownerId_libraryId_checksum_idx"`
errors — potentially thousands, for files that are already correctly tracked. Root cause: `chown -R`
touches every file's ctime, and Immich's live file-watcher (unlike its scheduled scan, which
correctly checks the DB by path first) queues straight to insert on any change event, without
checking whether the path is already tracked. This is pure wasted work and log noise — a failed
INSERT can't touch the pre-existing row (the unique constraint is exactly what's protecting it) —
and it stops on its own once ctimes settle; the scheduled scan path won't repeat it. Confirmed
empirically: zero further errors within 2 minutes of the chown completing.

---

## Phase 6 — subtractive reorg

**Not started as of 2026-09-16 — do Phase 1 first.** Only once Phase 5's checkpoint is green.

> **Re-verify the library list before running this.** The restored DB currently shows only **4
> libraries total** (`SELECT count(*) FROM library`), not the 6 this phase assumes (Pictures,
> Videos, Family, Arpan Marriage, Bhargavi, Sachin) — re-enumerate what actually exists
> (`SELECT id, name, "importPaths" FROM library`) and adjust the delete list below before acting on
> it. Also note: one test move (a single asset, since cleaned up and fully verified working) already
> happened via "move to shared library" during Phase 4/5 testing — harmless to Phase 6, but the
> asset in question is no longer in any external library, so don't expect it in a fresh library
> asset-count check.

Delete via the **admin UI or API**, not SQL — the API cascades audit rows, cleans derivatives, and
queues the right jobs. SQL deletes will leave orphans. (The one exception made so far — the 148
locked-asset relocation in Phase 5 — was a narrow, deliberate exception forced by the migration
blocker, not a precedent for this phase.)

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
