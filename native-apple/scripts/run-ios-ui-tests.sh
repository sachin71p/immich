#!/bin/sh
# Run the iOS UI tests (Heirloom-iOS-UITests) in the bridged Tart guest VM so
# sim runs stop competing with the host's desktop, device installs, and the
# macOS suite (see native-apple/scripts/run-macos-ui-tests.sh for the macOS
# twin; the data-plane below mirrors its --guest flow step for step).
#
# Default flow:
#   1. Host builds: xcodegen + `xcodebuild build-for-testing` for the
#      Heirloom-iOS scheme (simulator builds need no signing overrides).
#   2. Copy host DerivedData Build/Products to the SAME absolute path in the
#      guest (rsync deltas; the .xctestrun embeds absolute paths, so 1:1
#      placement keeps it valid).
#   3. `xcodebuild test-without-building` in the guest on the named simulator
#      (the guest auto-boots it), streamed to this terminal.
#   4. Copy the .xcresult back to .build/tart-results/<run>/ on the host.
#
# iOS UI tests launch with -useFixtureStore (no network server), so nothing
# on the host needs to be reachable from the guest.
#
# Usage:
#   run-ios-ui-tests.sh [--only-testing A/B/c]... [--only-testing-file F]
#     [--configuration Debug|Release] [--simulator NAME] [--guest [user@]ip]
#     [--full-derived-data] [--no-build] [--host]
#
# Perf-budget tests (GridPerf/CollectionsPerf, F3b timing) stay gated on host
# hardware or a real device: guest sim graphics are software-rendered, so the
# VM is a correctness gate, not a stopwatch.
#
# Env: RUN_ON_HOST=1 (or --host) -> local `xcodebuild test` run.
#   ONLY_TESTING (space-separated), CONFIGURATION (default Debug),
#   SIMULATOR_NAME (default iPhone 17e), TART_SSH_KEY, TART_GUEST.
# Exit codes: 0 pass, 1 tests failed, 2 infrastructure/setup error.
set -eu
set -o pipefail 2>/dev/null || true

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
NATIVE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$NATIVE_DIR/.." && pwd)

GUEST_USER="admin"
SSH_KEY="${TART_SSH_KEY:-$HOME/.ssh/heirloom-tart}"
CONFIGURATION="${CONFIGURATION:-Debug}"
SIMULATOR="${SIMULATOR_NAME:-iPhone 17e}"
ONLY_TESTING="${ONLY_TESTING:-}"
ONLY_FILE=""
# Default: direct-guest runs on the reserved-IP bridged VM (no local tart
# needed). Single `-` (not `:-`) so an explicitly empty TART_GUEST opts out:
# `TART_GUEST= ...` with no other route is an error (see below).
GUEST="${TART_GUEST-admin@192.168.4.58}"
RUN_ON_HOST="${RUN_ON_HOST:-0}"
NO_BUILD=0; HOST_MODE=0
: "${FULL_DERIVED_DATA:=0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --only-testing) ONLY_TESTING="$ONLY_TESTING $2"; shift 2 ;;
    --only-testing-file) ONLY_FILE="$2"; shift 2 ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    --simulator) SIMULATOR="$2"; shift 2 ;;
    --guest) GUEST="$2"; shift 2 ;;
    --full-derived-data) FULL_DERIVED_DATA=1; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    --host) HOST_MODE=1; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "error: unknown flag $1 (see --help)" >&2; exit 2 ;;
  esac
done

if [ -n "$ONLY_FILE" ]; then
  [ -f "$ONLY_FILE" ] || { echo "error: --only-testing-file not found: $ONLY_FILE" >&2; exit 2; }
  ONLY_TESTING="$ONLY_TESTING $(grep -v '^[[:space:]]*#' "$ONLY_FILE" | grep -v '^[[:space:]]*$' || true)"
fi
# Default scope: the whole iOS UI test target.
[ -n "$ONLY_TESTING" ] || ONLY_TESTING="Heirloom-iOS-UITests"

ONLY_ARGS=""
# shellcheck disable=SC2086
for spec in $ONLY_TESTING; do ONLY_ARGS="$ONLY_ARGS -only-testing:$spec"; done

DESTINATION="platform=iOS Simulator,name=$SIMULATOR"

# Escape hatch: local run (mirrors the pre-remote `make test-ios-ui` shape).
if [ "$HOST_MODE" = "1" ] || [ "$RUN_ON_HOST" = "1" ]; then
  command -v xcodegen >/dev/null 2>&1 || { echo "error: xcodegen missing (brew install xcodegen)" >&2; exit 2; }
  mkdir -p "$NATIVE_DIR/.build/clang-module-cache"
  # shellcheck disable=SC2086
  ( cd "$NATIVE_DIR" && xcodegen generate >/dev/null && \
    CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" xcodebuild test \
      -project Heirloom.xcodeproj \
      -scheme Heirloom-iOS \
      -configuration "$CONFIGURATION" \
      -destination "$DESTINATION" \
      -derivedDataPath .build/DerivedData \
      -skipPackagePluginValidation \
      -allowProvisioningUpdates \
      $ONLY_ARGS )
  exit "$?"
fi

[ -n "$GUEST" ] || { echo "error: no guest route (unset TART_GUEST to opt out; --guest to pick a VM)" >&2; exit 2; }
[ -f "$SSH_KEY" ] || { echo "error: SSH key $SSH_KEY missing. Install this host's key in the guest first:" >&2; echo "  cat $SSH_KEY.pub | ssh '$GUEST' 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'" >&2; exit 2; }
case "$GUEST" in
  *@*) GUEST_SSH_USER="${GUEST%%@*}"; GUEST_IP="${GUEST#*@}" ;;
  *) GUEST_SSH_USER="$GUEST_USER"; GUEST_IP="$GUEST" ;;
esac

SSH="ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
# shellcheck disable=SC2086
$SSH "$GUEST_SSH_USER@$GUEST_IP" true 2>/dev/null \
  || { echo "error: SSH to $GUEST_SSH_USER@$GUEST_IP failed (VM booted bridged with reserved IP? key installed? see README)" >&2; exit 2; }

HOST_DD="$NATIVE_DIR/.build/DerivedData"
# Default ships just Build/Products: verified sufficient because the
# .xctestrun addresses everything via __TESTROOT__ under Products (app,
# -Runner.app, .xctest plugin). --full-derived-data restores the whole tree.
SYNC_SRC="$HOST_DD/Build/Products"
[ "${FULL_DERIVED_DATA:-0}" = "1" ] && SYNC_SRC="$HOST_DD"

if [ "$NO_BUILD" = "0" ]; then
  # The OpenAPI doc is gitignored and generated; a fresh checkout needs it.
  if [ ! -f "$NATIVE_DIR/PhotosCore/Sources/ImmichAPI/openapi.yaml" ] && [ -x "$NATIVE_DIR/scripts/gen-api.sh" ]; then
    echo "generating OpenAPI client input (gen-api.sh)..."
    ( cd "$NATIVE_DIR" && ./scripts/gen-api.sh )
  fi
  command -v xcodegen >/dev/null 2>&1 || { echo "error: xcodegen missing on host (brew install xcodegen)" >&2; exit 2; }
  mkdir -p "$NATIVE_DIR/.build/clang-module-cache"
  echo "host build-for-testing (configuration=$CONFIGURATION, simulator=$SIMULATOR)..."
  ( cd "$NATIVE_DIR" && xcodegen generate >/dev/null && \
    CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" xcodebuild \
      -project Heirloom.xcodeproj \
      -scheme Heirloom-iOS \
      -configuration "$CONFIGURATION" \
      -destination "$DESTINATION" \
      -derivedDataPath .build/DerivedData \
      -skipPackagePluginValidation \
      build-for-testing )
fi

XCTESTRUN=$(ls -t "$HOST_DD"/Build/Products/Heirloom-iOS_*.xctestrun 2>/dev/null | head -1 || true)
[ -n "$XCTESTRUN" ] || { echo "error: no Heirloom-iOS .xctestrun under $HOST_DD/Build/Products (run without --no-build first)" >&2; exit 2; }
echo "xctestrun: $XCTESTRUN"

# Stage DerivedData at the same absolute path (sudo only to create/chown the
# root-owned prefix once; the sync itself runs as the guest user).
# shellcheck disable=SC2086
$SSH "$GUEST_SSH_USER@$GUEST_IP" "sudo -n mkdir -p '$HOST_DD' && sudo -n chown -R '$GUEST_SSH_USER' '$NATIVE_DIR/.build'" 2>/dev/null \
  || { echo "error: cannot stage guest dir (passwordless sudo missing?). Re-run native-apple/scripts/tart-setup.sh" >&2; exit 2; }

_rel="${SYNC_SRC#/}"
if command -v rsync >/dev/null 2>&1 && $SSH "$GUEST" "rsync --version >/dev/null 2>&1"; then
  echo "syncing DerivedData (incremental rsync)..."
  # shellcheck disable=SC2086
  rsync -a --delete --partial -e "$SSH" "$SYNC_SRC/" "$GUEST:/$_rel/"
else
  echo "syncing DerivedData (full tar; rsync missing on one end)..."
  tar -cf - -C / "$_rel" | $SSH "$GUEST" "tar -xf - -C /"
fi

RUN_TS=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR="$NATIVE_DIR/.build/tart-results/$RUN_TS"
mkdir -p "$RESULTS_DIR"
GUEST_OUT="/Users/$GUEST_SSH_USER/heirloom-ios-runs/$RUN_TS.xcresult"

echo "running iOS UI tests in guest ($SIMULATOR)..."
rc=0
# shellcheck disable=SC2086
$SSH "$GUEST" \
  "xcodebuild test-without-building -xctestrun '$XCTESTRUN' -destination '$DESTINATION' $ONLY_ARGS -resultBundlePath '$GUEST_OUT'" \
  2>&1 | tee "$RESULTS_DIR/guest-xcodebuild.log" || rc=$?

echo "fetching results..."
# shellcheck disable=SC2086
$SSH "$GUEST" "tar -cf - -C / '${GUEST_OUT#/}'" | tar -xf - -C "$RESULTS_DIR" 2>/dev/null || \
  echo "warning: could not fetch .xcresult (guest path may be missing after a hard failure)"
XCRESULT_HOST="$RESULTS_DIR$GUEST_OUT"
[ -d "$XCRESULT_HOST" ] || XCRESULT_HOST="(missing)"

echo ""
if [ "$rc" = "0" ]; then
  echo "PASS: iOS UI tests passed in guest ($GUEST)."
else
  echo "FAIL: iOS UI tests failed (exit $rc)."
fi
echo "guest xcodebuild log: $RESULTS_DIR/guest-xcodebuild.log"
echo ".xcresult: $XCRESULT_HOST"
exit "$rc"
