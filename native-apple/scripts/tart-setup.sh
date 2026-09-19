#!/bin/sh
# One-time Tart setup for isolated macOS UI tests.
# Idempotent: safe to re-run; steps already done are skipped.
#
# What it does:
#   1. Ensures `tart` is installed (Homebrew, with a direct-download fallback --
#      the cirruslabs tap is currently broken, see troubleshooting in README).
#   2. Pulls IMAGE (macOS Tahoe + Xcode; large one-time download).
#   3. Clones IMAGE -> GOLDEN and sizes CPU/RAM/disk/display.
#   4. Boots GOLDEN, installs this host's SSH key, runs tart-guest-prep.sh
#      inside it (power settings, Xcode license, _developer group, work dir),
#      then stops it. Clones of GOLDEN inherit all of this incl. TCC grants.
#
# Usage:
#   native-apple/scripts/tart-setup.sh [--image URL] [--golden NAME] [--check-only]
#
# Env overrides: TART_IMAGE, TART_GOLDEN, TART_CPUS, TART_MEM_MB, TART_DISK_GB,
#   TART_DISPLAY, TART_SSH_KEY, TART_VERSION (fallback download pin).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Default tracks the macOS 27 beta (no GA image published yet; flip back to
# :latest once Cirrus ships a macOS 27 GA tag). Override with --image.
IMAGE="${TART_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-xcode:27-beta-6}"
GOLDEN="${TART_GOLDEN:-heirloom-ui-golden}"
GUEST_USER="${TART_GUEST_USER:-admin}"
SSH_KEY="${TART_SSH_KEY:-$HOME/.ssh/heirloom-tart}"
CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --golden) GOLDEN="$2"; shift 2 ;;
    --check-only) CHECK_ONLY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "error: unknown flag $1 (see --help)" >&2; exit 2 ;;
  esac
done

# Resolve a working tart binary: PATH first, then the manual install location.
# (The binary must run from inside tart.app to pick up its provisioning profile.)
resolve_tart() {
  if command -v tart >/dev/null 2>&1 && tart --version >/dev/null 2>&1; then
    command -v tart
  elif [ -x /Applications/tart.app/Contents/MacOS/tart ]; then
    echo /Applications/tart.app/Contents/MacOS/tart
  else
    return 1
  fi
}

install_tart() {
  if resolve_tart >/dev/null 2>&1; then
    echo "tart already installed: $(resolve_tart) ($($(resolve_tart) --version))"
    return 0
  fi
  echo "tart not found; trying Homebrew..."
  if brew install cirruslabs/cli/tart 2>/dev/null && resolve_tart >/dev/null 2>&1; then
    echo "installed via Homebrew."
    return 0
  fi
  echo "Homebrew install failed (the cirruslabs tap is known-broken); falling back to the release archive."
  ver="${TART_VERSION:-2.37.0}"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "downloading tart $ver (~22 MB)..."
  curl -sSL -o "$tmp/tart.tar.gz" "https://github.com/cirruslabs/tart/releases/download/$ver/tart.tar.gz"
  tar xzf "$tmp/tart.tar.gz" -C "$tmp"
  if [ -w /Applications ]; then
    rm -rf /Applications/tart.app
    cp -R "$tmp/tart.app" /Applications/tart.app
  else
    echo "need sudo to install tart.app into /Applications"
    sudo rm -rf /Applications/tart.app
    sudo cp -R "$tmp/tart.app" /Applications/tart.app
  fi
  rm -rf "$tmp"
  trap - EXIT
  resolve_tart >/dev/null 2>&1 || { echo "error: manual install did not yield a working tart" >&2; exit 2; }
  echo "installed: $(resolve_tart) ($(resolve_tart --version))"
}

vm_exists() { # $1=name -> 0 if a local VM with that exact name exists
  resolve_tart >/dev/null 2>&1 || return 1
  "$(resolve_tart)" list --quiet 2>/dev/null | grep -qx "$1"
}

install_tart

TART_BIN="$(resolve_tart)"
if [ "$CHECK_ONLY" = "1" ]; then
  echo "tart: $TART_BIN ($("$TART_BIN" --version))"
  if vm_exists "$GOLDEN"; then echo "golden VM '$GOLDEN' exists."; else echo "golden VM '$GOLDEN' MISSING (run without --check-only to create)."; fi
  exit 0
fi

if ! vm_exists "$GOLDEN"; then
  echo "pulling $IMAGE (tens of GB, one-time download; needs ~60 GB free)..."
  "$(resolve_tart)" pull "$IMAGE"

  # Size the VM from host resources, leaving headroom for the developer.
  ncpu=$(sysctl -n hw.ncpu)
  mem_mb=$(( $(sysctl -n hw.memsize) / 1048576 ))
  cpus="${TART_CPUS:-$(( ncpu / 2 ))}"
  [ "$cpus" -lt 4 ] && cpus=4
  mem="${TART_MEM_MB:-$(( mem_mb / 2 ))}"
  [ "$mem" -lt 8192 ] && mem=8192
  echo "cloning $IMAGE -> $GOLDEN (cpu=$cpus mem=${mem}MB disk=${TART_DISK_GB:-80}GB display=${TART_DISPLAY:-1920x1080})..."
  "$(resolve_tart)" clone "$IMAGE" "$GOLDEN"
  # Disk can only ever grow: images already larger than the target keep theirs.
  disk_want="${TART_DISK_GB:-80}"
  disk_have=$("$(resolve_tart)" list --format json 2>/dev/null | TART_GOLDEN_LOOKUP="$GOLDEN" python3 -c \
    'import json,os,sys; print(next((v.get("Disk",0) for v in json.load(sys.stdin) if v.get("Name")==os.environ["TART_GOLDEN_LOOKUP"]), 0))')
  # shellcheck disable=SC2086
  set -- --cpu "$cpus" --memory "$mem" --display "${TART_DISPLAY:-1920x1080}"
  if [ "${disk_have:-0}" -ge "$disk_want" ]; then
    echo "disk already ${disk_have}GB (>= ${disk_want}GB); skipping resize."
  else
    set -- "$@" --disk-size "$disk_want"
  fi
  "$(resolve_tart)" set "$GOLDEN" "$@"
else
  echo "golden VM '$GOLDEN' already exists; skipping pull/clone/resize."
fi

# SSH key for all later host<->guest traffic (setup installs it once; clones inherit it).
if [ ! -f "$SSH_KEY" ]; then
  echo "generating $SSH_KEY ..."
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "heirloom-tart"
fi

echo "booting $GOLDEN ..."
"$(resolve_tart)" run "$GOLDEN" >/tmp/heirloom-tart-setup-run.log 2>&1 &
run_pid=$!

guest_ip=""
for i in $(seq 1 60); do
  guest_ip=$("$(resolve_tart)" ip "$GOLDEN" 2>/dev/null || true)
  [ -n "$guest_ip" ] && break
  sleep 5
done
[ -n "$guest_ip" ] || { echo "error: VM booted but got no IP (see /tmp/heirloom-tart-setup-run.log)" >&2; kill "$run_pid" 2>/dev/null || true; exit 2; }
echo "guest IP: $guest_ip"

SSH="ssh -i $SSH_KEY -o BatchMode=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o LogLevel=ERROR"
echo "waiting for SSH..."
ok=0
for i in $(seq 1 60); do
  # shellcheck disable=SC2086
  if $SSH "$GUEST_USER@$guest_ip" true 2>/dev/null; then ok=1; break; fi
  sleep 5
done
[ "$ok" = "1" ] || { echo "error: SSH never came up on $guest_ip" >&2; exit 2; }

echo "installing SSH key (you will be asked for the guest password once; it is 'admin' on stock Cirrus images)..."
ssh-copy-id -i "$SSH_KEY" "$GUEST_USER@$guest_ip" 2>/dev/null || \
  cat "$SSH_KEY.pub" | ssh "$GUEST_USER@$guest_ip" \
    "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys"

echo "running guest prep..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$SCRIPT_DIR/tart-guest-prep.sh" "$GUEST_USER@$guest_ip:/tmp/" >/dev/null
# The work dir must be the native-apple dir (absolute) so the guest's staged
# DerivedData path matches the host's 1:1 and .xctestrun paths resolve.
NATIVE_ABS=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
# shellcheck disable=SC2086
$SSH "$GUEST_USER@$guest_ip" "bash /tmp/tart-guest-prep.sh '$NATIVE_ABS'"

echo "stopping $GOLDEN ..."
"$(resolve_tart)" stop "$GOLDEN" >/dev/null 2>&1 || true
wait "$run_pid" 2>/dev/null || true
echo ""
echo "setup complete. Run macOS UI tests isolated with:"
echo "  make test-macos-ui"
echo "On-host escape hatch:  make test-macos-ui RUN_ON_HOST=1"
