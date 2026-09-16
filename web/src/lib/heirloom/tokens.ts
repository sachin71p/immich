// Heirloom Web V2 — visual tokens (PLAN §6 findings, WP1 measurements).
//
// Values mirror the native macOS main window: ~240px sidebar, 120px default
// square tiles, 2px gaps, 8px content inset, 64–300 zoom range. The CSS file
// (`heirloom-v2.css`) is the rendering source of truth; these constants keep
// component logic (e.g. zoom clamping) consistent with it.

export const V2_SIDEBAR_WIDTH_PX = 240;
export const V2_GRID_GAP_PX = 2;
export const V2_GRID_INSET_PX = 8;
export const V2_DEFAULT_TILE_PX = 120;
export const V2_MIN_TILE_PX = 64;
export const V2_MAX_TILE_PX = 300;

/** V2 root marker attribute. All V2 CSS is scoped beneath it — never global. */
export const V2_ROOT_ATTRIBUTE = 'data-heirloom-v2';
