# A2 — Core: image pipeline & cache tiers

Depends on: A1 · Reads: A0 Architecture+Rules · DECISIONS §2 (R14, R15).

## Tasks
1. Media URLs via ImmichAPI: thumbnail (`size=thumbnail`), preview, fullsize/original, video playback, live-photo
   motion (livePhotoVideoId), edited vs original variants.
2. Nuke pipeline: thumbhash decode (instant placeholder) → thumbnail → preview → original (on zoom or explicit),
   decode off-main with downsampling to target pixel size, memory cache sized to device, request prioritization +
   cancellation for fast scroll, prefetcher API for grid (`prefetch(ids, tier)`).
3. Disk cache tiers with separate budgets and LRU: thumbnails (large budget, kept preferentially — "all thumbnails
   on device" option), previews, originals. Pinning API: keep originals for an album/space/library/favorites offline.
   Budget policy API used by A6: `setBudget(tier, bytes)`, `evict(toFree:)`, `usage()`.
4. Offline behaviour: serve best cached tier; surface "original unavailable offline" state to UI.
5. HEIC/RAW/ProRAW/HDR: keep original bytes; expose HDR-capable image for viewers (dynamic range flag).

## Tests
Tier fallback order, LRU eviction respects pins, budget accounting, cancellation, thumbhash decoding correctness.

Verify: `native-apple/scripts/verify.sh core`.
