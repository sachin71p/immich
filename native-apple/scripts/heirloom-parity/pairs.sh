#!/bin/sh
# WP-T T8: rebuild the DESIGN-REFERENCE side-by-side pairs from fresh captures.
# Usage: pairs.sh <captures-dir> <pairs-out-dir>
#
# <captures-dir> holds fresh stills named REF-<base>.png (Apple Photos target)
# and CUR-<base>.png (current Heirloom), extracted from recordings with e.g.
#   ffmpeg -ss <t> -i <clip>.mp4 -frames:v 1 REF-<base>.png
# <base> is the pair stem from DESIGN-REFERENCE.md (e.g. V1-viewer-photo).
# Each pair is composed as Photos-left / Heirloom-right with labels, matching
# the layout described in DESIGN-REFERENCE.md. Missing sides are skipped with
# a warning (not fatal) so partial capture sessions still produce output.
set -eu

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <captures-dir> <pairs-out-dir>" >&2
  exit 64
fi
capdir=$1
outdir=$2
mkdir -p "$outdir"

# Pair stems from DESIGN-REFERENCE.md / evidence/design/pairs/.
pairs="E1-edit-adjust E2-edit-light-options E3-edit-styles-vs-filters E4-edit-crop
  E5-edit-tools-vs-portrait F1-launch-early F2-launch-grid-vs-zero I1-info-panel
  I2-info-placement L1-library-allphotos L2-library-months L3-library-years
  L4-toolbar-scope-menu L5-toolbar-filter-menu L6-toolbar-more-vs-sort
  L7-grid-context-menu M1-menubar-file M2-menubar-view M3-menubar-image
  M4-menubar-view-duplicate P1-collections P2-search P3-map P4-people
  P5-videos P6-all-albums P7-album S1-settings-general-vs-account
  S2-settings-icloud-vs-storage S3-settings-sharedlib-vs-timeline
  S4-settings-icloud-vs-usage-agent T1-toolbar-library-strip
  T2-toolbar-viewer-strip V1-viewer-photo V2-viewer-context-menu
  V3-viewer-info V4-viewer-video V5-viewer-chevron-vs-nav-bug"

made=0
skipped=0
for base in $pairs; do
  # shellcheck disable=SC2086
  ref="$capdir/REF-$base.png"
  cur="$capdir/CUR-$base.png"
  if [ ! -f "$ref" ] || [ ! -f "$cur" ]; then
    echo "skip $base (missing side)" >&2
    skipped=$((skipped + 1))
    continue
  fi
  ffmpeg -hide_banner -loglevel error -y -i "$ref" -i "$cur" -filter_complex "
    [0:v]scale=1200:-2,drawtext=text='Apple Photos (REF)':x=24:y=24:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.6[l];
    [1:v]scale=1200:-2,drawtext=text='Heirloom (AFTER)':x=24:y=24:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.6[r];
    [l][r]hstack=inputs=2" "$outdir/$base.png"
  made=$((made + 1))
done
echo "pairs made=$made skipped=$skipped -> $outdir"
