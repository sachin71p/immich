#!/usr/bin/env bash
# UP-01 (S10): upgrade gate — upstream base tag with seeded data -> fork image.
# Steps: build+up the base-tag stack (isolated compose project), seed an admin,
# a user, an upload and an album, snapshot DB state, swap the server to the fork
# image (same volumes), wait for migrations, then verify data intact + the
# reserved storage-label guard. Cleans up unless --keep-stack is given.
# Usage: bash scripts/fork-test/upgrade.sh [--base-ref <sha>] [--keep-stack]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE_REF="e55ac299a4ec7cb372e35dbf2c6c05ee9ce77f6c"
KEEP_STACK=0
PROJECT="immich-upgrade"
PORT="2295"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --base-ref) BASE_REF="$2"; shift 2 ;;
    --base-ref=*) BASE_REF="${1#--base-ref=}"; shift ;;
    --keep-stack) KEEP_STACK=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

BASE_TREE="$(mktemp -d)/immich-upgrade-base"
MEDIA_DIR="$(mktemp -d)/upgrade-media"
API="http://127.0.0.1:$PORT/api"

cleanup() {
  if [[ "$KEEP_STACK" == 0 ]]; then
    (cd "$ROOT" && docker compose -p "$PROJECT" -f "$BASE_TREE/e2e/docker-compose.yml" down -v >/dev/null 2>&1 || true)
    git -C "$ROOT" worktree remove --force "$BASE_TREE" >/dev/null 2>&1 || true
    rm -rf "$(dirname "$BASE_TREE")" "$MEDIA_DIR"
  else
    echo "keeping upgrade stack (project $PROJECT); worktree at $BASE_TREE"
  fi
}
trap cleanup EXIT INT TERM

compose() { (cd "$ROOT" && docker compose -p "$PROJECT" "$@"); }

wait_for_ping() {
  for _ in $(seq 1 120); do
    if curl -fsS --max-time 2 "$API/server/ping" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "server did not become ready at $API" >&2
  return 1
}

echo "=== UP-01: checking out base $BASE_REF ==="
git -C "$ROOT" worktree add --detach "$BASE_TREE" "$BASE_REF" 1>&2

# Isolated project + host port so a live e2e stack is never disturbed. Volume
# paths are absolute: the base worktree has no test-assets submodule, and the
# media bind stays separate from e2e/.fork-data for the same reason. The fork
# overlay is intentionally NOT included: its relative mounts would resolve
# against the base worktree.
cat > "$BASE_TREE/e2e/docker-compose.upgrade.yml" <<EOF
services:
  immich-server:
    environment:
      IMMICH_MEDIA_LOCATION: /fork-data
    ports:
      - $PORT:2285
    volumes:
      - $ROOT/e2e/test-assets:/test-assets:rw
      - $MEDIA_DIR:/fork-data
EOF

echo "=== UP-01: starting upstream base stack ==="
compose -f "$BASE_TREE/e2e/docker-compose.yml" -f "$BASE_TREE/e2e/docker-compose.upgrade.yml" up -d --build 1>&2
wait_for_ping

echo "=== UP-01: seeding base data ==="
curl -fsS -X POST "$API/auth/admin-sign-up" \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@upgrade.test","password":"password","name":"Upgrade Admin"}' 1>&2
ADMIN_TOKEN="$(curl -fsS -X POST "$API/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@upgrade.test","password":"password"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')"
USER_ID="$(curl -fsS -X POST "$API/admin/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"email":"user@upgrade.test","password":"password","name":"Upgrade User"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
USER_TOKEN="$(curl -fsS -X POST "$API/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"user@upgrade.test","password":"password"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')"
ASSET_ID="$(curl -fsS -X POST "$API/assets" \
  -H "Authorization: Bearer $USER_TOKEN" \
  -F "assetData=@$ROOT/e2e/test-assets/formats/jpg/el_torcal_rocks.jpg;type=image/jpeg" \
  -F 'deviceAssetId=upgrade-1' -F 'deviceId=upgrade' \
  -F 'fileCreatedAt=2024-01-01T00:00:00.000Z' -F 'fileModifiedAt=2024-01-01T00:00:00.000Z' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
curl -fsS -X POST "$API/albums" \
  -H "Authorization: Bearer $USER_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"albumName\":\"Upgrade Album\",\"assetIds\":[\"$ASSET_ID\"]}" 1>&2
BEFORE_PATH="$(curl -fsS "$API/assets/$ASSET_ID" -H "Authorization: Bearer $USER_TOKEN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["originalPath"])')"
BEFORE_MIGRATIONS="$(compose -f "$BASE_TREE/e2e/docker-compose.yml" exec -T database psql -U postgres -d immich -tAc 'select count(*) from kysely_migrations')"
BEFORE_ASSETS="$(compose -f "$BASE_TREE/e2e/docker-compose.yml" exec -T database psql -U postgres -d immich -tAc "select count(*) from asset where \"deletedAt\" is null")"
echo "base: assets=$BEFORE_ASSETS migrations=$BEFORE_MIGRATIONS path=$BEFORE_PATH"

echo "=== UP-01: swapping to the fork image (built from the working tree) ==="
(cd "$ROOT" && docker build -f server/Dockerfile -t immich-server:latest . 1>&2)
compose -f "$BASE_TREE/e2e/docker-compose.yml" -f "$BASE_TREE/e2e/docker-compose.upgrade.yml" up -d immich-server 1>&2
wait_for_ping

echo "=== UP-01: verifying ==="
AFTER_MIGRATIONS="$(compose -f "$BASE_TREE/e2e/docker-compose.yml" exec -T database psql -U postgres -d immich -tAc 'select count(*) from kysely_migrations')"
AFTER_ASSETS="$(compose -f "$BASE_TREE/e2e/docker-compose.yml" exec -T database psql -U postgres -d immich -tAc "select count(*) from asset where \"deletedAt\" is null")"
AFTER_PATH="$(curl -fsS "$API/assets/$ASSET_ID" -H "Authorization: Bearer $USER_TOKEN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["originalPath"])')"
[[ "$AFTER_ASSETS" == "$BEFORE_ASSETS" ]] || { echo "UP-01 FAIL: asset count $BEFORE_ASSETS -> $AFTER_ASSETS" >&2; exit 1; }
[[ "$AFTER_MIGRATIONS" -ge "$BEFORE_MIGRATIONS" ]] || { echo "UP-01 FAIL: migrations went backwards" >&2; exit 1; }
curl -fsS "$API/assets/$ASSET_ID/original" -H "Authorization: Bearer $USER_TOKEN" -o /dev/null
echo "data intact: assets=$AFTER_ASSETS migrations=$AFTER_MIGRATIONS path=$AFTER_PATH"

echo "=== UP-01: reserved-label guard ==="
RESERVED_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$API/admin/users/$USER_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"storageLabel":"shared"}')"
[[ "$RESERVED_STATUS" == "400" ]] || { echo "UP-01 FAIL: reserved label accepted ($RESERVED_STATUS)" >&2; exit 1; }
curl -fsS -X PUT "$API/admin/users/$USER_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"storageLabel":"upgraded-personal"}' 1>&2
echo "UP-01 PASS: upgrade clean, data intact, reserved-label guard works"
