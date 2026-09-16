#!/bin/sh
# profile.sh — record an Instruments trace of the installed Heirloom macOS app.
#
# Usage: profile.sh [name] [seconds]
#   name    trace label, written to /tmp/heirloom-perf/<name>-<timestamp>.trace
#   seconds recording length (default 120)
#
# Why attach instead of launch: an app launched by `xctrace --launch` is not
# registered with LaunchServices, so accessibility/computer-use cannot see its
# windows and the WP7 scripted scenario cannot drive it. We open the installed
# app normally, then attach to its pid.
set -eu

name="${1:-manual}"
seconds="${2:-120}"
app="/Applications/Heirloom-macOS.app"
outdir="/tmp/heirloom-perf"

if [ ! -d "$app" ]; then
  echo "error: $app not found; run 'make install-macos' first" >&2
  exit 1
fi

mkdir -p "$outdir"
ts=$(date +%Y%m%d-%H%M%S)
out="$outdir/${name}-${ts}.trace"

echo "Quitting any running Heirloom instance for a cold-launch recording..."
osascript -e 'tell application id "com.immich.heirloom.macos" to quit' 2>/dev/null || true
sleep 2

echo "Launching $app ..."
open -a "$app"

# Wait up to 60 s for the app to register a pid.
pid=""
i=0
while [ "$i" -lt 60 ]; do
  pid=$(pgrep -x Heirloom-macOS | head -1 || true)
  if [ -n "$pid" ]; then break; fi
  sleep 1
  i=$((i + 1))
done
if [ -z "$pid" ]; then
  echo "error: Heirloom-macOS did not start within 60 s" >&2
  exit 1
fi

echo "Recording ${seconds}s Time Profiler + Hangs + os_signpost on pid $pid ..."
echo "Perform the WP7 scenario (scripts/heirloom-perf/README.md) now."
xcrun xctrace record \
  --template 'Time Profiler' \
  --instrument Hangs \
  --instrument os_signpost \
  --time-limit "${seconds}s" \
  --attach "$pid" \
  --output "$out"
echo "Trace written to $out"
