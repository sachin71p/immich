#!/bin/sh
# Run the macOS UI tests (Heirloom-macOS-UITests) inside a disposable Tart VM
# so the host desktop is never interrupted (no focus/cursor/Spaces steal, no
# host Accessibility/Screen Recording needed for the app under test).
#
# Default flow:
#   1. Clone GOLDEN -> throwaway VM (or reuse --vm), boot it (VM window stays
#      isolated; --headless is experimental for UI tests).
#   2. Host builds: xcodegen + `xcodebuild build-for-testing` (mirrors the
#      `make test-macos-ui` flags, including project signing).
#   3. Copy host DerivedData to the SAME absolute path in the guest (tar pipe;
#      the .xctestrun embeds absolute paths, so 1:1 placement keeps it valid).
#   4. `xcodebuild test-without-building` in the guest, streamed to this terminal.
#   5. Copy the .xcresult back to .build/tart-results/<run>/ on the host.
#   6. Stop + delete the throwaway VM (golden stays intact).
#
# One-time prerequisite: native-apple/scripts/tart-setup.sh
#
# Usage:
#   run-macos-ui-tests.sh [--only-testing A/B/c]... [--only-testing-file F]
#     [--configuration Debug|Release] [--vm NAME] [--keep] [--no-build]
#     [--headless] [--golden NAME] [--remote user@host] [--guest [user@]ip]
#     [--full-derived-data] [--team-signing] [--host]
#
# Syncs just Build/Products by default (~0.65 GB vs ~6 GB; verified sufficient
# for test-without-building). --full-derived-data restores the whole tree.
# Host builds sign ad-hoc for VMs (fresh guests Gatekeeper-reject team
# signatures); --team-signing restores automatic signing instead.
#
# --remote builds HERE, ships DerivedData to the REMOTE Mac at the same
# absolute path (both checkouts must live at identical paths: the .xctestrun
# embeds them), runs this same script there with --no-build against its Tart
# VM, streams the output back, and fetches the .xcresult. Built for agent
# workflows that live on this machine while the VM lives elsewhere.
#
# --guest talks DIRECTLY to an already-booted bridged VM at a stable LAN IP
# (reserved DHCP), with no tart involvement here: build here, stage + test +
# fetch straight into the guest over SSH. Boot the VM once on its host, e.g.
# `tart run --net-bridged=en0 <vm>`. The persistent instance keeps state
# between runs (unlike disposable clones): good for iteration, while --remote
# (fresh clone per run) stays the clean gate. Guest needs this host's SSH key:
# cat $SSH_KEY.pub | ssh <guest> 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
#
# Env: RUN_ON_HOST=1 (or --host) -> legacy on-host `make test-macos-ui` path.
#   ONLY_TESTING (space-separated), CONFIGURATION (default Debug),
#   TART_VM, TART_GOLDEN, TART_SSH_KEY, TART_GUEST_USER, TART_REMOTE, TART_GUEST.
# Exit codes: 0 pass, 1 tests failed, 2 infrastructure/setup error.
set -eu
set -o pipefail 2>/dev/null || true

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
NATIVE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$NATIVE_DIR/.." && pwd)

GOLDEN="${TART_GOLDEN:-heirloom-ui-golden}"
GUEST_USER="${TART_GUEST_USER:-admin}"
SSH_KEY="${TART_SSH_KEY:-$HOME/.ssh/heirloom-tart}"
CONFIGURATION="${CONFIGURATION:-Debug}"
ONLY_TESTING="${ONLY_TESTING:-}"
ONLY_FILE=""
VM_OVERRIDE="${TART_VM:-}"
REMOTE="${TART_REMOTE:-}"
# Default: direct-guest runs on the reserved-IP bridged VM (no local tart
# needed). Single `-` (not `:-`) so an explicitly empty TART_GUEST opts out
# back to the disposable-clone flow: `TART_GUEST= make test-macos-ui`.
GUEST="${TART_GUEST-admin@192.168.4.58}"
# Guards below must only fire for an explicitly chosen guest, never for the
# default above (or RUN_ON_HOST / --remote would break).
GUEST_EXPLICIT=0
if [ -n "${TART_GUEST+set}" ] && [ -n "$TART_GUEST" ]; then GUEST_EXPLICIT=1; fi
RUN_ON_HOST="${RUN_ON_HOST:-0}"
KEEP=0; NO_BUILD=0; HEADLESS=0; HOST_MODE=0
: "${TEAM_SIGNING:=0}"
: "${FULL_DERIVED_DATA:=0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --only-testing) ONLY_TESTING="$ONLY_TESTING $2"; shift 2 ;;
    --only-testing-file) ONLY_FILE="$2"; shift 2 ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    --vm) VM_OVERRIDE="$2"; shift 2 ;;
    --golden) GOLDEN="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    --guest) GUEST="$2"; GUEST_EXPLICIT=1; shift 2 ;;
    --products-only) :; shift ;; # accepted for back-compat; Products is now the default
    --full-derived-data) FULL_DERIVED_DATA=1; shift ;;
    --team-signing) TEAM_SIGNING=1; shift ;;
    --keep) KEEP=1; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    --headless) HEADLESS=1; shift ;;
    --host) HOST_MODE=1; shift ;;
    -h|--help) sed -n '2,44p' "$0"; exit 0 ;;
    *) echo "error: unknown flag $1 (see --help)" >&2; exit 2 ;;
  esac
done

if [ -n "$REMOTE" ] && { [ "$HOST_MODE" = "1" ] || [ "$RUN_ON_HOST" = "1" ]; }; then
  echo "error: --remote cannot combine with --host/RUN_ON_HOST" >&2; exit 2
fi
if [ -n "$REMOTE" ] && [ "$GUEST_EXPLICIT" = "1" ]; then
  echo "error: --remote cannot combine with an explicit --guest (pick one route)" >&2; exit 2
fi
if [ "$GUEST_EXPLICIT" = "1" ] && { [ "$HOST_MODE" = "1" ] || [ "$RUN_ON_HOST" = "1" ] || [ -n "$VM_OVERRIDE" ] || [ "$HEADLESS" = "1" ]; }; then
  echo "error: --guest cannot combine with --host/--vm/--headless (it addresses a booted VM directly)" >&2; exit 2
fi

# Escape hatch: legacy on-host run (re-exec via make so flags stay single-sourced).
if [ "$HOST_MODE" = "1" ] || [ "$RUN_ON_HOST" = "1" ]; then
  # shellcheck disable=SC2086
  exec make -C "$REPO_ROOT" test-macos-ui RUN_ON_HOST=1 CONFIGURATION="$CONFIGURATION" ONLY_TESTING="$ONLY_TESTING"
fi

if [ -n "$ONLY_FILE" ]; then
  [ -f "$ONLY_FILE" ] || { echo "error: --only-testing-file not found: $ONLY_FILE" >&2; exit 2; }
  ONLY_TESTING="$ONLY_TESTING $(grep -v '^[[:space:]]*#' "$ONLY_FILE" | grep -v '^[[:space:]]*$' || true)"
fi
# Default scope: the whole macOS UI test target ("run all macOS UI tests").
[ -n "$ONLY_TESTING" ] || ONLY_TESTING="Heirloom-macOS-UITests"

# VM-bound test builds sign ad-hoc by default: fresh VMs Gatekeeper-reject
# team/developer signatures (ENOPOLICY) with no CLI-workable override, while
# ad-hoc launches fine and needs no provisioning. Same convention as
# verify.sh's Apple-tier build. --team-signing restores Makefile-style
# automatic signing (keeps App Group/keychain entitlements; needs profiles
# and a VM that trusts the developer).
build_host() {
  command -v xcodegen >/dev/null 2>&1 || { echo "error: xcodegen missing on host (brew install xcodegen)" >&2; exit 2; }
  mkdir -p "$NATIVE_DIR/.build/clang-module-cache"
  if [ "${TEAM_SIGNING:-0}" = "1" ]; then
    # Must be exported BEFORE xcodegen so the generated project bakes in a
    # real team (not the literal ${DEVELOPMENT_TEAM}).
    : "${DEVELOPMENT_TEAM:=599Z443923}"
    export DEVELOPMENT_TEAM
    echo "host build-for-testing (configuration=$CONFIGURATION, team signing)..."
    ( cd "$NATIVE_DIR" && xcodegen generate >/dev/null && \
      CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" xcodebuild \
        -project Heirloom.xcodeproj \
        -scheme Heirloom-macOS \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -derivedDataPath .build/DerivedData \
        -skipPackagePluginValidation \
        -allowProvisioningUpdates \
        build-for-testing )
  else
    echo "host build-for-testing (configuration=$CONFIGURATION, ad-hoc for VM)..."
    ( cd "$NATIVE_DIR" && DEVELOPMENT_TEAM="" xcodegen generate >/dev/null && \
      CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" xcodebuild \
        -project Heirloom.xcodeproj \
        -scheme Heirloom-macOS \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -derivedDataPath .build/DerivedData \
        -skipPackagePluginValidation \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_ENTITLEMENTS="" DEVELOPMENT_TEAM="" \
        build-for-testing )
  fi
}

HOST_DD="$NATIVE_DIR/.build/DerivedData"
# Default ships just Build/Products (~0.65 GB vs ~6 GB): verified sufficient
# because the .xctestrun addresses everything via __TESTROOT__ under Products
# (app, -Runner.app, .xctest plugin, PackageFrameworks). --full-derived-data
# restores the whole tree if a future Xcode layout ever needs more.
SYNC_SRC="$HOST_DD/Build/Products"
[ "${FULL_DERIVED_DATA:-0}" = "1" ] && SYNC_SRC="$HOST_DD"

locate_xctestrun() {
  XCTESTRUN=$(ls -t "$HOST_DD"/Build/Products/*.xctestrun 2>/dev/null | head -1 || true)
  [ -n "$XCTESTRUN" ] || { echo "error: no .xctestrun under $HOST_DD/Build/Products (run without --no-build first)" >&2; exit 2; }
}

# Incremental tree sync to the same absolute path on the far end.
# $1 = absolute source dir, $2 = ssh destination, $3 = ssh command (unexpanded),
# $4 = human label. Uses rsync (deltas after the first full sync) when both
# ends have it, else falls back to a full tar pipe.
sync_dir() {
  _src="$1"; _dst="$2"; _ssh="$3"; _label="$4"
  _rel="${_src#/}"
  if command -v rsync >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    if $_ssh "$_dst" "rsync --version >/dev/null 2>&1"; then
      # Live progress only on a terminal (keeps agent logs clean); prefer the
      # overall progress2 bar, fall back to per-file --progress.
      # --partial resumes interrupted files; -z compresses (slow-link win,
      # negligible CPU cost for delta sizes). Both probed, not assumed.
      _prog=""; _zflag=""
      if [ -t 1 ]; then
        if rsync --help 2>/dev/null | grep -q progress2; then _prog="--info=progress2"; else _prog="--progress"; fi
      fi
      if rsync --help 2>/dev/null | grep -q -- '--compress'; then _zflag="-z"; fi
      echo "syncing $_label (incremental rsync; ~$(du -sh "$_src" 2>/dev/null | cut -f1) total)..."
      # shellcheck disable=SC2086
      rsync -a --delete --partial ${_zflag} ${_prog} -e "$_ssh" "$_src/" "$_dst:/$_rel/"
      return 0
    fi
  fi
  echo "syncing $_label (full tar, no live progress; rsync missing on one end)..."
  tar -cf - -C / "$_rel" | $_ssh "$_dst" "tar -xf - -C /"
}

# Shared guest data-plane: stage DerivedData at the same absolute path,
# run test-without-building, fetch the .xcresult.
# Requires: SSH, GUEST_SSH_USER, GUEST_IP, GUEST_LABEL, XCTESTRUN,
#   ONLY_TESTING, RESULTS_DIR, RUN_TS, HOST_DD, NATIVE_DIR.
run_in_guest() {
  # shellcheck disable=SC2086
  $SSH "$GUEST_SSH_USER@$GUEST_IP" "sudo -n mkdir -p '$HOST_DD' && sudo -n chown -R '$GUEST_SSH_USER' '$NATIVE_DIR/.build'" 2>/dev/null \
    || { echo "error: cannot stage guest dir (passwordless sudo missing?). Re-run native-apple/scripts/tart-setup.sh" >&2; return 2; }
  # shellcheck disable=SC2086
  sync_dir "$SYNC_SRC" "$GUEST_SSH_USER@$GUEST_IP" "$SSH" "DerivedData"

  GUEST_OUT="/Users/$GUEST_SSH_USER/heirloom-ui-runs/$RUN_TS.xcresult"
  ONLY_ARGS=""
  # shellcheck disable=SC2086
  for spec in $ONLY_TESTING; do ONLY_ARGS="$ONLY_ARGS -only-testing:$spec"; done

  echo "running UI tests in guest..."
  rc=0
  # shellcheck disable=SC2086
  $SSH "$GUEST_SSH_USER@$GUEST_IP" \
    "xcodebuild test-without-building -xctestrun '$XCTESTRUN' -destination 'platform=macOS' $ONLY_ARGS -resultBundlePath '$GUEST_OUT'" \
    2>&1 | tee "$RESULTS_DIR/guest-xcodebuild.log" || rc=$?

  echo "fetching results..."
  # shellcheck disable=SC2086
  $SSH "$GUEST_SSH_USER@$GUEST_IP" "tar -cf - -C / '${GUEST_OUT#/}'" | tar -xf - -C "$RESULTS_DIR" 2>/dev/null || \
    echo "warning: could not fetch .xcresult (guest path may be missing after a hard failure)"
  XCRESULT_HOST="$RESULTS_DIR$GUEST_OUT"
  [ -d "$XCRESULT_HOST" ] || XCRESULT_HOST="(missing)"

  echo ""
  if [ "$rc" = "0" ]; then
    echo "PASS: macOS UI tests passed in guest ($GUEST_LABEL)."
  else
    echo "FAIL: UI tests failed (exit $rc)."
  fi
  echo "guest xcodebuild log: $RESULTS_DIR/guest-xcodebuild.log"
  echo ".xcresult: $XCRESULT_HOST"
  return "$rc"
}

# Remote mode: build HERE, ship the bits to the remote Mac at the same
# absolute path, run this same script THERE with --no-build against its Tart
# VM, stream the output back, and fetch the .xcresult.
if [ -n "$REMOTE" ]; then
  [ "$NO_BUILD" = "0" ] && build_host
  locate_xctestrun
  echo "xctestrun: $XCTESTRUN"
  RSSH="ssh -o ConnectTimeout=10 -o LogLevel=ERROR"
  # shellcheck disable=SC2086
  $RSSH "$REMOTE" "test -d '$NATIVE_DIR'" 2>/dev/null \
    || { echo "error: $NATIVE_DIR missing on $REMOTE (check out the repo at the SAME absolute path on both Macs)" >&2; exit 2; }
  sync_dir "$SYNC_SRC" "$REMOTE" "$RSSH" "DerivedData to $REMOTE (same absolute path)"
  REMOTE_ARGS="--no-build --golden $GOLDEN"
  [ -n "$VM_OVERRIDE" ] && REMOTE_ARGS="$REMOTE_ARGS --vm $VM_OVERRIDE"
  [ "$KEEP" = "1" ] && REMOTE_ARGS="$REMOTE_ARGS --keep"
  [ "$HEADLESS" = "1" ] && REMOTE_ARGS="$REMOTE_ARGS --headless"
  echo "running UI tests on $REMOTE ..."
  rc=0
  # shellcheck disable=SC2086
  $RSSH "$REMOTE" "cd '$NATIVE_DIR' && ONLY_TESTING='$ONLY_TESTING' CONFIGURATION='$CONFIGURATION' ./scripts/run-macos-ui-tests.sh $REMOTE_ARGS" || rc=$?
  echo "fetching results..."
  mkdir -p "$NATIVE_DIR/.build/tart-results"
  RLATEST=$($RSSH "$REMOTE" "ls -t '$NATIVE_DIR/.build/tart-results' 2>/dev/null | head -1" || true)
  if [ -n "$RLATEST" ]; then
    if scp -r -o LogLevel=ERROR "$REMOTE:$NATIVE_DIR/.build/tart-results/$RLATEST" "$NATIVE_DIR/.build/tart-results/" >/dev/null 2>&1; then
      echo ".xcresult fetched: $NATIVE_DIR/.build/tart-results/$RLATEST"
    else
      echo "warning: result fetch failed; results remain on $REMOTE under .build/tart-results/$RLATEST"
    fi
  fi
  exit "$rc"
fi

# Direct-guest mode: an already-booted bridged VM at a stable LAN IP.
if [ -n "$GUEST" ]; then
  [ -f "$SSH_KEY" ] || { echo "error: SSH key $SSH_KEY missing. Install this host's key in the guest first:" >&2; echo "  cat $SSH_KEY.pub | ssh '$GUEST' 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'" >&2; exit 2; }
  case "$GUEST" in
    *@*) GUEST_SSH_USER="${GUEST%%@*}"; GUEST_IP="${GUEST#*@}" ;;
    *) GUEST_SSH_USER="$GUEST_USER"; GUEST_IP="$GUEST" ;;
  esac
  [ "$NO_BUILD" = "0" ] && build_host
  locate_xctestrun
  echo "xctestrun: $XCTESTRUN"
  SSH="ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
  # shellcheck disable=SC2086
  $SSH "$GUEST_SSH_USER@$GUEST_IP" true 2>/dev/null \
    || { echo "error: SSH to $GUEST_SSH_USER@$GUEST_IP failed (VM booted bridged with reserved IP? key installed? see README)" >&2; exit 2; }
  RUN_TS=$(date +%Y%m%d-%H%M%S)
  RESULTS_DIR="$NATIVE_DIR/.build/tart-results/$RUN_TS"
  mkdir -p "$RESULTS_DIR"
  GUEST_LABEL="guest $GUEST_SSH_USER@$GUEST_IP"
  rc=0
  run_in_guest || rc=$?
  exit "$rc"
fi

resolve_tart() {
  if command -v tart >/dev/null 2>&1 && tart --version >/dev/null 2>&1; then
    command -v tart
  elif [ -x /Applications/tart.app/Contents/MacOS/tart ]; then
    echo /Applications/tart.app/Contents/MacOS/tart
  else
    return 1
  fi
}

TART=$(resolve_tart 2>/dev/null || true)
[ -n "$TART" ] || { echo "error: tart not installed. Run: native-apple/scripts/tart-setup.sh" >&2; exit 2; }
[ -f "$SSH_KEY" ] || { echo "error: SSH key $SSH_KEY missing. Run: native-apple/scripts/tart-setup.sh" >&2; exit 2; }

vm_exists() { "$TART" list --quiet 2>/dev/null | grep -qx "$1"; }
vm_ip() { "$TART" ip "$1" 2>/dev/null || true; }

RUN_TS=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR="$NATIVE_DIR/.build/tart-results/$RUN_TS"
mkdir -p "$RESULTS_DIR"

EPHEMERAL="heirloom-ui-$RUN_TS"
if [ -n "$VM_OVERRIDE" ]; then
  VM="$VM_OVERRIDE"
  vm_exists "$VM" || { echo "error: VM '$VM' not found (tart list). Omit --vm for a disposable clone." >&2; exit 2; }
  MANAGED=0
else
  VM="$EPHEMERAL"
  vm_exists "$GOLDEN" || { echo "error: golden VM '$GOLDEN' missing. Run: native-apple/scripts/tart-setup.sh" >&2; exit 2; }
  echo "cloning $GOLDEN -> $VM ..."
  "$TART" clone "$GOLDEN" "$VM"
  MANAGED=1
fi

cleanup() {
  if [ "$MANAGED" = "1" ]; then
    if [ "$KEEP" = "1" ]; then
      echo "keeping VM '$VM' (--keep). ssh: ssh -i $SSH_KEY $GUEST_USER@$(vm_ip "$VM")"
    else
      echo "tearing down $VM ..."
      "$TART" stop "$VM" >/dev/null 2>&1 || true
      "$TART" delete "$VM" >/dev/null 2>&1 || true
    fi
  fi
  if [ -n "${RUN_PID:-}" ]; then kill "$RUN_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

if [ -n "$(vm_ip "$VM")" ]; then
  echo "VM '$VM' already running."
else
  echo "booting $VM ... (VM window stays isolated; your desktop is untouched)"
  if [ "$HEADLESS" = "1" ]; then
    echo "note: --headless is experimental for UI tests; use the VM window if tests misbehave."
    "$TART" run --no-graphics "$VM" >/tmp/heirloom-ui-run.log 2>&1 &
  else
    "$TART" run "$VM" >/tmp/heirloom-ui-run.log 2>&1 &
  fi
  RUN_PID=$!
fi

echo "waiting for guest IP..."
GUEST_IP=""
for i in $(seq 1 24); do
  GUEST_IP=$(vm_ip "$VM")
  [ -n "$GUEST_IP" ] && break
  sleep 5
done
[ -n "$GUEST_IP" ] || { echo "error: VM booted but got no IP (see /tmp/heirloom-ui-run.log)" >&2; exit 2; }

SSH="ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
echo "waiting for SSH on $GUEST_IP ..."
ok=0
for i in $(seq 1 36); do
  # shellcheck disable=SC2086
  if $SSH "$GUEST_USER@$GUEST_IP" true 2>/dev/null; then ok=1; break; fi
  sleep 5
done
[ "$ok" = "1" ] || { echo "error: SSH never came up on $GUEST_IP (guest agent/SSHD issue; see README troubleshooting)" >&2; exit 2; }

if [ "$NO_BUILD" = "0" ]; then build_host; fi
locate_xctestrun
echo "xctestrun: $XCTESTRUN"

GUEST_SSH_USER="$GUEST_USER"
GUEST_LABEL="Tart VM '$VM'"
rc=0
run_in_guest || rc=$?
exit "$rc"
