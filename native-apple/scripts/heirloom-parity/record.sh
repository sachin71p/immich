#!/bin/sh
# WP-T T8: 60 fps screen recording for REF-vs-AFTER gesture comparisons.
# Usage: record.sh <name> <seconds> [av-device-index]
# Writes <name>.mp4 into the current directory. The device index varies per
# Mac — run `ffmpeg -f avfoundation -list_devices true -i ""` to find the
# main display (the owner prompts per app; see HANDOFF-PROMPT.md).
set -eu

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <name> <seconds> [av-device-index]" >&2
  exit 64
fi
name=$1
seconds=$2
device=${3:-3}

exec ffmpeg -f avfoundation -framerate 60 -capture_cursor 1 \
  -i "$device:none" -t "$seconds" \
  -vf scale=1728:-2 -c:v h264_videotoolbox -b:v 14M "$name.mp4"
