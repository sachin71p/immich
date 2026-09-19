#!/bin/sh
# WP-T T8: frame-change statistics for a gesture clip (PLAN §3 recipe).
# Usage: framestats.sh <clip> [crop=W:H:X:Y]
# Prints changed-frames/s p50 and p10 plus the longest static run during
# motion, using mpdecimate (hi=64*4:lo=64:frac=0.1) on a 325px-wide proxy —
# the same recipe for REF and AFTER clips so the numbers compare directly.
set -eu

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <clip> [crop=W:H:X:Y]" >&2
  exit 64
fi
clip=$1
crop=${2:-""}

if [ -n "$crop" ]; then
  vf="crop=$crop,scale=325:-2,mpdecimate=hi=64*4:lo=64:frac=0.1,showinfo"
else
  vf="scale=325:-2,mpdecimate=hi=64*4:lo=64:frac=0.1,showinfo"
fi

# One pts_time per changed frame (mpdecimate drops the static ones).
times=$(ffmpeg -hide_banner -i "$clip" -vf "$vf" -f null - 2>&1 \
  | grep -o 'pts_time:[0-9.]*' | cut -d: -f2)

n=$(printf '%s\n' "$times" | grep -c . || true)
if [ "$n" -lt 2 ]; then
  echo "changed_frames=0 (fewer than 2 changed frames; clip may be static)"
  exit 0
fi

printf '%s\n' "$times" | awk '
  { t[NR] = $1 }
  END {
    n = NR
    # Per-1s buckets of changed frames.
    for (i = 1; i <= n; i++) { b[int(t[i])]++ }
    m = 0
    for (k in b) { rates[++m] = b[k] }
    # Insertion sort is fine (clips are seconds long).
    for (i = 2; i <= m; i++) { v = rates[i]; j = i - 1; while (j >= 1 && rates[j] > v) { rates[j+1] = rates[j]; j-- } rates[j+1] = v }
    p50 = rates[int((m + 1) / 2)]
    p10idx = int(m * 0.1) + 1
    if (p10idx < 1) p10idx = 1
    if (p10idx > m) p10idx = m
    p10 = rates[p10idx]
    # Longest static run between the first and last changed frame.
    longest = 0
    for (i = 2; i <= n; i++) { gap = t[i] - t[i-1]; if (gap > longest) longest = gap }
    printf "changed_frames=%d\nchanged_fps_p50=%.1f\nchanged_fps_p10=%.1f\nlongest_static_run_s=%.3f\n", n, p50, p10, longest
  }'
