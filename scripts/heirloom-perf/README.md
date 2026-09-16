# heirloom-perf — macOS performance harness (WP0/WP7)

Repeatable Instruments profiling for the Heirloom macOS app. Baseline for
comparison: `04-baseline-profile.md` (13 hangs, 12.93 s total, worst 2.00 s).

## Record a trace

```bash
make install-macos                      # Release build into /Applications
scripts/heirloom-perf/profile.sh gate2 150
```

`profile.sh [name] [seconds]` (default 120 s) quits any running instance for a
cold launch, opens the installed app normally, waits for its pid, and records
the **Time Profiler + Hangs + os_signpost** instruments attached to it:

```bash
xcrun xctrace record --template 'Time Profiler' --instrument Hangs \
  --instrument os_signpost --time-limit 150s --attach <pid> \
  --output /tmp/heirloom-perf/gate2-<timestamp>.trace
```

Why attach instead of `--launch`: an app launched by xctrace is not registered
with LaunchServices, so accessibility/computer-use cannot see its windows and
the scripted scenario below cannot drive it.

## Summarize a trace

```bash
python3 scripts/heirloom-perf/summarize.py /tmp/heirloom-perf/gate2-<ts>.trace
```

Prints a Markdown summary: hang count / total / worst with a per-hang table;
top 20 main-thread inclusive frames owned by Heirloom/PhotosCore (PhotosCore
links statically into the app binary, so one binary check covers both;
process-entry frames are skipped); and per-name count/p50/p95/max for the
`HeirloomSignpost` intervals (`GridLoad`, `SnapshotBuild`, `LayoutPrepare`,
`ThumbnailFetch`, `ThumbnailDecode`, `ViewerOpen`).

The parser resolves xctrace's id/ref string dedup (threads, states, frames,
binaries, backtraces) and streams the time-profile table, so a ~200 s trace
parses in under a minute. Interval names are read from the export's
`signpost-name` cell (`name` kept as fallback for older exports). Empty tables (e.g. no signposts fired) print a
placeholder row instead of crashing.

## Scripted scenario (WP7 §3)

Perform these steps during the recording; take a screenshot at each step into
`reports/shots/gate<N>/`:

- A. Cold launch. Time the window appearing and the first thumbnails appearing
  (screenshots every 0.5 s for 5 s).
- B. Library → Years → Months → All Photos → Months, pausing 2 s each. No
  error banner; headers correct.
- C. Drag the scroll bar top → bottom → top over ~5 s, then fling-scroll 20
  screens. After stopping, no blank cell stays longer than 0.5 s, no black
  borders.
- D. Single-click 3 items, ⌘-click 2 more, click empty space (deselects),
  − − + + zoom, and pinch if possible.
- E. Favorite one photo, then unfavorite it: heart badge updates instantly, no
  grid reload (scroll position unchanged).
- F. Double-click a photo → info → → → ← ← (lands on the original) →
  rotate ×4 → Esc.
- G. Sidebar: Favorites, Recently Saved, Map (pan/zoom), People, Memories,
  Photos, Videos, Live Photos, Portrait, Screenshots, the shared library, an
  album, Collections, Search (type a query + Return). Each renders content or
  a proper empty state within 1 s, with a correct title and no irrelevant
  toolbar items.
- H. Open Move… from a selection → Cancel; open again → Escape; open again →
  ⌘Q quits the app. **Never confirm a move, trash, lock, or album change on
  the real library.**

## Large synthetic fixture (no server needed)

Automated perf runs without the owner's server:

```bash
/Applications/Heirloom-macOS.app/Contents/MacOS/Heirloom-macOS \
  --fixture-seed --fixture-seed-count=100000
```

`--fixture-seed` boots the in-memory store through the public `apply()` path;
`--fixture-seed-count=<N>` (N up to 150000, clamped) adds N deterministic
synthetic assets — photos, videos with durations, live-photo still+motion
pairs, and screenshots — with `localDateTime` spread evenly over 15 years,
varied aspect ratios, and a reused real thumbhash. Live pairs emit one
companion motion row, so the store holds ~5% more rows than N. The media
pipeline runs offline in this mode, so cells show placeholders; there is no
network traffic and nothing touches the real library.

`--fixture-seed-count=100000` is the second baseline (cf. the 102k-row owner
library): record its launch-to-first-thumbnails time alongside the Instruments
trace. Before WP2/WP3 the grid is expected to be slow here — that slowness is
the thing being measured.
