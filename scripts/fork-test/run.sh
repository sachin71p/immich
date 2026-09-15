#!/usr/bin/env bash
# Fork test runner (shared-libraries, T0). See TESTING.md §6.
# Usage: scripts/fork-test/run.sh <tier...> [--keep-stack] [--template on|off|both] [--personal]
# Tiers: unit | medium | e2e-api | e2e-web | apple | upstream | upgrade | coverage | all
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="$ROOT/e2e/.fork-report"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/$STAMP.md"
KEEP_STACK=0
TEMPLATE=both
PERSONAL=0
TIERS=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --keep-stack) KEEP_STACK=1; shift ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --template=*) TEMPLATE="${1#--template=}"; shift ;;
    --personal) PERSONAL=1; shift ;;
    unit|medium|e2e-api|e2e-web|apple|upstream|upgrade|coverage|all) TIERS+=("$1"); shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "${#TIERS[@]}" == 0 ]]; then
  echo "usage: run.sh <tier...> [--keep-stack] [--template on|off|both] [--personal]" >&2
  exit 2
fi

mkdir -p "$REPORT_DIR"
{
  echo "# fork-test report $STAMP"
  echo ""
  echo "tiers: ${TIERS[*]} | template: $TEMPLATE | personal: $PERSONAL"
  echo ""
} > "$REPORT"

pass=0; fail=0
record() { # record <tier> <status> <detail>
  echo "- [$2] $1 $3" >> "$REPORT"
  if [[ "$2" == "PASS" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); fi
}

stack_up() {
  (cd "$ROOT" && docker compose -f e2e/docker-compose.yml -f e2e/docker-compose.fork.yml up -d --build)
}

stack_down() {
  if [[ "$KEEP_STACK" == 0 ]]; then
    (cd "$ROOT" && docker compose -f e2e/docker-compose.yml -f e2e/docker-compose.fork.yml down)
  fi
}

run_unit() {
  (cd "$ROOT/server" && pnpm run test) && record unit PASS "" || record unit FAIL "server suite"
  (cd "$ROOT/web" && pnpm run test --run) && record unit-web PASS "" || record unit-web FAIL "web suite"
}

run_medium() {
  (cd "$ROOT/server" && pnpm run test:medium -- test/medium/specs/fork) \
    && record medium PASS "" || record medium FAIL "see output"
}

run_e2e_api() {
  git -C "$ROOT" submodule update --init e2e/test-assets
  stack_up
  # shellcheck disable=SC2164
  (cd "$ROOT/e2e" && VITEST_DISABLE_DOCKER_SETUP=true pnpm test -- src/specs/server/api/fork) \
    && record e2e-api PASS "template=$TEMPLATE" || record e2e-api FAIL "template=$TEMPLATE"
  stack_down
}

run_e2e_web() {
  stack_up
  (cd "$ROOT/e2e" && pnpm test:web -- src/specs/web/fork) \
    && record e2e-web PASS "" || record e2e-web FAIL "see output"
  stack_down
}

run_apple() {
  if [[ -d "$ROOT/native-apple" ]]; then
    ("$ROOT/native-apple/scripts/verify.sh" core) && record apple PASS "" || record apple FAIL "see output"
  else
    record apple SKIP "no native-apple checkout"
  fi
}

run_upstream() {
  (cd "$ROOT/server" && pnpm run test:medium) && record upstream-medium PASS "" || record upstream-medium FAIL ""
  (cd "$ROOT/e2e" && VITEST_DISABLE_DOCKER_SETUP=true pnpm test -- src/specs/server/api) \
    && record upstream-e2e PASS "" || record upstream-e2e FAIL ""
}

run_upgrade() {
  echo "upgrade tier: implemented by S10 (UP-01 + INV-02 scripts)" | tee -a "$REPORT"
  record upgrade SKIP "owned by S10"
}

# No tsx in the repo: compile fork TS scripts with the server tsc, then node.
# The source is staged under server/ first so bare imports (exiftool-vendored)
# resolve from the server workspace, per TESTING.md §2.
run_ts() { # run_ts <repo-abs-ts-file> [args...]
  local src="$1"; shift
  local base; base="$(basename "$src")"
  local stage; stage="$(mktemp -d "$ROOT/server/.fork-ts-XXXXXX")"
  local out; out="$(mktemp -d)/fork-ts"
  cp "$src" "$stage/"
  (cd "$ROOT/server" && pnpm exec tsc --ignoreConfig --module commonjs --target es2022 \
    --moduleResolution bundler --esModuleInterop --skipLibCheck --types node \
    --outDir "$out" "$stage/$base") \
    && NODE_PATH="$ROOT/server/node_modules:$ROOT/e2e/node_modules" \
      node "$out/${base%.ts}.js" "$@"
  local status=$?
  rm -rf "$stage"
  return $status
}

run_coverage() {
  if [[ "$PERSONAL" == 1 ]]; then
    run_ts "$ROOT/scripts/fork-test/coverage.ts" --personal \
      && record coverage PASS "" || record coverage FAIL "see output"
  else
    run_ts "$ROOT/scripts/fork-test/coverage.ts" \
      && record coverage PASS "" || record coverage FAIL "see output"
  fi
}

for tier in "${TIERS[@]}"; do
  case "$tier" in
    unit) run_unit ;;
    medium) run_medium ;;
    e2e-api) run_e2e_api ;;
    e2e-web) run_e2e_web ;;
    apple) run_apple ;;
    upstream) run_upstream ;;
    upgrade) run_upgrade ;;
    coverage) run_coverage ;;
    all) run_unit; run_medium; run_e2e_api; run_e2e_web; run_apple; run_upstream; run_coverage ;;
  esac
done

{
  echo ""
  echo "result: $pass passed, $fail failed"
} >> "$REPORT"
cat "$REPORT"
[[ "$fail" == 0 ]]
