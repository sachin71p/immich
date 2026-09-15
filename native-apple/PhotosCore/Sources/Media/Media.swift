/// Progressive media loading and cache budgeting (phase A2).
///
/// - `MediaTier`: still-image quality tiers and their fallback order.
/// - `MediaEndpoint`: authenticated media URLs (thumbnail/preview/fullsize/original, video
///   playback, live-photo motion, edited variants).
/// - `ThumbHash`: instant local placeholder decoded from `Asset.thumbhash`.
/// - `TieredMediaCache`: per-tier disk budgets with LRU eviction and offline pins.
/// - `MediaPipeline`: Nuke-backed progressive loader (placeholder → thumbnail → preview →
///   original), grid prefetcher, offline serving, pinning, and the A6 budget-policy surface.
/// - `MediaFormatInfo`: HEIC/RAW/video classification and the viewer HDR flag.
public enum PhotosMedia {}
