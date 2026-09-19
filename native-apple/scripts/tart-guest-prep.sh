#!/bin/bash
# Guest-side prep for the heirloom-ui golden image. Runs INSIDE the macOS VM
# as the admin user (invoked by tart-setup.sh over SSH; $1 = host work dir whose
# absolute path must also exist here so .xctestrun paths resolve 1:1).
# Idempotent: safe to re-run.
set -eu

WORK_DIR="${1:?usage: tart-guest-prep.sh <host-work-dir-absolute-path>}"
echo "== guest prep (user: $(whoami), console: $(stat -f %Su /dev/console)) =="

SUDO="sudo -n"
$SUDO true 2>/dev/null || { echo "note: passwordless sudo unavailable; some steps below may fail (re-run setup with NOPASSWD sudo)"; SUDO="sudo"; }

# Keep the VM awake for UI tests: no computer/display/disk sleep.
$SUDO systemsetup -setcomputersleep Never >/dev/null 2>&1 || true
$SUDO systemsetup -setdisplaysleep Never >/dev/null 2>&1 || true
$SUDO systemsetup -setharddisksleep Never >/dev/null 2>&1 || true
echo "sleep: computer=$($SUDO systemsetup -getcomputersleep 2>/dev/null | tail -1)"

# No screensaver / no password-on-wake inside the disposable VM.
defaults -currentHost write com.apple.screensaver idleTime -int 0 2>/dev/null || true
defaults write com.apple.screensaver askForPassword -int 0 2>/dev/null || true
defaults write com.apple.screensaver askForPasswordDelay -int 0 2>/dev/null || true

# Xcode usable non-interactively.
$SUDO xcodebuild -license accept >/dev/null 2>&1 || true
echo "xcode: $(xcode-select -p)"
xcodebuild -version | head -2

# Debugging/testing group membership for the test runner.
$SUDO dseditgroup -o edit -a "$(whoami)" -t user _developer 2>/dev/null || true
$SUDO DevToolsSecurity -enable 2>/dev/null || true

# Work dir mirroring the host path (owned by the guest user, no sudo needed later).
$SUDO mkdir -p "$WORK_DIR"
$SUDO chown "$(whoami)" "$WORK_DIR"

echo "== guest prep OK =="
