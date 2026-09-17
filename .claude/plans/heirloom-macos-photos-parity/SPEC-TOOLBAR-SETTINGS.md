# Spec: window toolbar and Settings (owner-reviewed 2026-09-17)

This is binding for WP-C. The owner compared the two toolbars and wants Heirloom's to match Photos, with
one deliberate difference: the library-scope picker. Settings follows the owner's decisions below.

Visual references:
- `evidence/design/pairs/T1-toolbar-library-strip.png`: Photos on top, Heirloom below (Library).
- `evidence/design/pairs/T2-toolbar-viewer-strip.png`: Photos on top, Heirloom below (viewer).
- `evidence/design/pairs/S1…S4-settings-*.png`.
- Originals in `evidence/design/settings/`.

## 1. Library toolbar: current differences

The Photos toolbar (T1, top) differs from Heirloom's (T1, bottom) as follows.

| # | Area | Photos (target) | Heirloom today | Required change |
|---|---|---|---|---|
| T-1 | Window layout | Sidebar is a full-height floating panel. Its sidebar-toggle button sits **inside the sidebar column** next to the traffic lights. The content toolbar starts at the sidebar's edge, and photos scroll **under** the translucent toolbar (blurred) | Toggle sits at the left of the *content* area. The toolbar band is opaque white; the sidebar column top is grey | `NavigationSplitView` / `NSSplitViewController` with a full-height sidebar (`.fullSizeContentView`, sidebar toolbar item placed in the sidebar section). Content extends under a glass toolbar |
| T-2 | Title | Leading, stacked: **"Library"** (bold ~15 pt) over the date subtitle ("Apr 16, 2026", or a range, secondary ~11 pt) | Date range at far left in small grey text; "Library" as a separate centred-ish title | One leading title block: `navigationTitle` + `navigationSubtitle` (range or selection count). Nothing centred |
| T-3 | Scope picker | Glass capsule: photo-stack icon + **up/down chevron** (⌃⌄ pop-up indicator); no text | Capsule with icon + "All Libraries" + **down** chevron | **Owner exception:** keep the icon **and the full library name** ("All Libraries", "Personal Library", "Family", …), but use Photos' capsule style: same height, glass, **up/down chevron**. The name truncates with a middle ellipsis past ~180 pt. Menu styled like Photos: checkmark, SF symbol per row |
| T-4 | Zoom | Capsule with − and +, both enabled in normal state | Same shape, but − appears disabled (grey) at the current level | Match Photos: enable/disable only at the true min/max level. Same glyph weight and spacing |
| T-5 | Grouping | Glass segmented Years · Months · All Photos, selected pill | Visually close | Keep; match exact height, padding and selected-pill tint |
| T-6 | View-options group | One capsule: **aspect-ratio toggle** (rectangle with ↕ arrows), **Filter** (three decreasing lines → the filter menu: All Items, Favorites, Edited, Photos, Videos, Screenshots, Captured by Me, Not in an Album, Manage Keywords…), **"…"** (Show: Screenshots, Shared with You) | Capsule: **4-square grid** icon (square toggle), **three lines → Sort menu**, **"…" → the filter menu** | Same icons and semantics as Photos. Aspect toggle uses Photos' glyph. Three lines = **Filter**. "…" = **Show** options (Screenshots; Shared-library items, "Shared with You" equivalent). **Sort moves to View › Sort** |
| T-7 | Item-actions group | One capsule: Info · Share · Favorite · Rotate. Enabled by selection; Favorite is a filled heart when favourited | Separate capsule with the same four, all disabled/grey | Same grouping and glyphs. Enable with the selection; filled heart state |
| T-8 | Select | None (click selects) | "Select" text button in its own capsule | **Remove** (WP-G's selection model) |
| T-9 | Sync | None | Circular-arrows button in its own capsule | **Remove from the toolbar.** Sync Now goes in the "…" menu and File › Sync Now. Status shows in the sidebar footer ("Synced 2 min ago" / progress) |
| T-10 | Search | Wide rounded search field at the trailing edge (~420 pt at 1728 pt window width), "Search" placeholder with a magnifier | Not in the toolbar (sidebar page) | `NSSearchToolbarItem`, trailing, flexible width (min 180, ideal 420) |
| T-11 | Shared Library banner | A floating glass notice below the toolbar at the trailing edge ("Shared Library Suggestion: 23 photos, 20 videos", Review / Not Now) | None | Optional (P2). Use the same component if Heirloom adds suggestions |
| T-12 | Spacing | Capsule groups separated by ~8 pt. Leading title block, flexible space, then the groups; search takes the remaining space | Groups spread across the width, with extra gaps | Toolbar item order with one flexible space after the title. Group spacing per Photos |

Target order at 1728 pt (leading → trailing):
1. [traffic lights · sidebar toggle] (inside the sidebar)
2. **Title block** · *flexible space*
3. **Scope** (icon + name + ⌃⌄)
4. **Zoom** (− | +)
5. **Years · Months · All Photos**
6. **[aspect · filter · …]**
7. **[info · share · favorite · rotate]**
8. **Search**

At narrower widths the overflow order (first to collapse into the » menu) is: search shrinks to its
minimum, then [info … rotate], then [aspect · filter · …]. Match what Photos does when the window
narrows; verify it with a live resize.

## 2. Viewer toolbar: current differences (T2)

| # | Photos | Heirloom today | Required |
|---|---|---|---|
| TV-1 | Back chevron capsule, then a **zoom slider** capsule | Back chevron only | Add the zoom slider (WP-V V8/V9) |
| TV-2 | **Centred** two-line title: place name (bold) over "April 16, 2026 at 8:00:58 PM · 6,398 of 12,108" | Leading two-line title: date over time; **no position counter** | Centred place + subtitle with the **"N of M" counter** (§2a, V9/V19) |
| TV-3 | Trailing capsule: Info · Share · Favorite (filled) · Rotate · Auto-Enhance, then a separate **Edit** text capsule | Capsule: Favorite · Trash · Move (folder) · Add to Album · Adjust · Rotate · Info, plus a blue **Live Text** pill | Photos set and order. Trash/Move/Add-to-Album live in menus and the context menu. Adjust becomes the **Edit** text button. Live Text pill removed (V1) |

### 2a. Viewer header: exact content (owner request, 2026-09-17)

The owner wants every element of Photos' viewer header, laid out the same way.

**Leading**
- A circular back-chevron button in its own glass capsule.
- A second capsule with a **zoom slider**: "−" glyph · track · "+" glyph, about 140 pt. It is bound
  live to the page magnification. Fit is the left end, 8× the right end.

**Centre** (truly centred in the window's content area, independent of the leading/trailing widths)
- **Line 1 (bold 13 pt):** place name, e.g. "Miami Beach - Flamingo/Lummus".
  - Source: the reverse-geocoded neighbourhood/landmark, falling back to `exifInfo.city` or
    "City, State".
  - With no location: the **date** in bold ("April 16, 2026"), and line 2 omits the date.
- **Line 2 (secondary 11 pt):** "April 16, 2026 at 7:59:51 PM · 6,388 of 12,108".
  - **Date/time** in the asset's local time zone.
  - A middle-dot separator with spaces.
  - A **position counter**: 1-based index of the current asset **in the current viewer context**
    (the display-order snapshot: Library with its active filter, an album, a search result, a
    person…) "of" the context's total count. Both numbers use locale grouping separators.
  - The counter updates on every page change, including during rapid key paging, and when the
    context changes underneath (deletions, sync).
  - It's hidden for a single-item context (a standalone window, a deep link).
- Both lines truncate in the middle when narrow.

**Trailing**
- One glass capsule: **Info** (ⓘ, pressed state while the sidebar is open), **Share**, **Favorite**
  (outline or filled heart), **Rotate** (rotate-left glyph), **Auto Enhance** (magic wand; toggles,
  filled when applied).
- Then a separate capsule with the **Edit** text button.

**Image overlay badges**
- A **LIVE** capsule at the top-left of the image (translucent material, live glyph + "LIVE"). It's a
  menu: Live / Loop / Bounce / Long Exposure / Off, limited to what's supported.
- **HDR** when the asset is HDR.
- Hovering the LIVE badge plays the motion (Photos behaviour).
- Badges sit 8 pt inside the image's top-left corner and follow the fitted image rect, not the
  window.

**Tests (TV-4)**
- **U:** header formatter:
  - "Month d, yyyy at h:mm:ss a · N of M" with grouping ("6,388 of 12,108"), in en_US, de_DE
    ("6.388 von 12.108", localized) and one RTL locale;
  - with no place → the date becomes the title;
  - a single-item context omits the counter.
- **UI (fixture):**
  - open item k of the Library → the subtitle ends "k of <total>";
  - → → updates it to k+2;
  - open the same asset from an album → the counter reflects the album's position and count;
  - apply the Favorites filter → the total equals the favourites count.
- **S:** viewer header light/dark with the LIVE badge.
- **U:** the zoom slider ↔ magnification binding works both ways.

## 3. Settings (owner decisions)

The Photos Settings window is a compact window with icon tabs General · iCloud · Shared Library, using a
label-column form layout (right-aligned labels, checkboxes with explanatory text). Heirloom's is one long
grouped scrolling form. **Owner decision: Photos-style tabs plus one extra tab.**

### Tab: General (Photos General + Heirloom extras)
Same label-column layout as `photos-01-general.png`.
- **Library Location →** "Server:" showing the server URL (read-only), and "Local cache:" as a path with
  Show in Finder.
- **Privacy:** "Use Touch ID or password", which requires authentication for Hidden, Recently Deleted
  and Locked. Implement only if the app has those destinations; otherwise omit.
- **Photos:** "Autoplay Videos and Live Photos"; "Show Rating Controls" only if Immich ratings are
  supported (it has EXIF rating; ask the owner at the gate if unsure).
- **HDR:** "View Full HDR" (EDR display of HDR assets).
- **Memories:** "Show Featured Content", "Show Memories Notification" (only if memories notifications
  exist), "Reset Suggested Memories" (only if the server API allows it).
- **Importing:** (owner: **keep both**)
  - ☑ "Copy items to the Heirloom library". On: upload a copy. Off: reference in place; only if
    supported, otherwise show it checked and disabled with an explanation.
  - "Import into:" picker (Follow default upload target / Personal Library / each shared library). This
    is the existing `Heirloom.importDestination`.
- **Sharing:** "Include location information" (strip GPS on share/export when off).
- **Search:** "Smart Search" (Immich CLIP search). When off, search uses metadata only.

### Tab: Server (the iCloud tab's role)
- **Account:** server URL; **user name**; email; **user ID** (all shown together: name as the primary line, then email, then the ID in secondary monospaced text with a copy button); **Log Out**. (Owner request 2026-09-17: show the user name *along with* the user ID, not instead of it.)
- ☑ **Sync in the background** (existing Background Agent toggle, plus its inline note).
- **Originals on this Mac** (owner decision: *merge, but never offer "Download Originals"*):
  - Photos-style copy: "Heirloom keeps full-resolution originals on your server. This Mac stores
    smaller versions and downloads originals when you need them."
  - **No** "Download Originals to this Mac" option anywhere. Don't add a keep-everything mode.
  - Under it: "Keep up to [slider 0–8 GB] of originals", then the existing budget text. The detailed
    per-album list is in the Storage tab.

### Tab: Shared Libraries (owner: merge both)
- A library picker at top (Family, Friends, …).
- For the selected library:
  - **Participants** list (avatar, name, role Owner/Member) with **Add Participants…**, if the server
    supports it;
  - ☑ **Deletion Notifications**;
  - ☑ **Show in Library timeline** (existing per-space toggle);
  - **Manage / Leave / Delete Shared Library…** buttons as the role allows. Destructive actions are
    confirmed.
  - **Shared Library Suggestions** and **Suggest Moments That Include** only if the server supports
    suggestions; otherwise omit (don't show dead controls).
- Below the per-library section:
  - "Default upload target:" picker (existing);
  - ☑ "Show Personal Library in timeline" (existing);
  - "External libraries" with a show/hide toggle per owned external library (existing
    `hiddenOwnedLibraryIds`).

### Tab: Storage (the extra tab)
- **Keep originals on this Mac:** the existing per-album/per-library toggles (existing
  `MacStorageView` list).
- **Usage:** Thumbnails / Preview / Fullsize / Original / Total, with **Refresh Usage** and
  **Purge Unpinned…** (confirm).
- **Uploads in progress:** "Pending uploads: N", **Upload Now**.

### General rules for Settings
- The window has fixed width (~600 pt) and its height adapts per tab (like Photos). Toolbar-style tabs
  with SF Symbols: gearshape, server.rack, person.2, internaldrive.
- Every existing Heirloom preference key keeps working. No data migration beyond moving UI.
- ⌘, opens the window on the last-used tab.

## 4. Gap rows (added to PLAN §1, owned by WP-C)

| ID | Pri | Gap |
|---|---|---|
| C7 | P1 | Toolbar layout per §1 T-1…T-12 (window/sidebar structure, title block, scope capsule with the owner exception, view-options and item-actions groups, remove Select and Sync, search field) |
| C8 | P1 | Settings restructure per §3 (tabs, label-column layout, merged items, no Download-Originals option) |
| C9 | P2 | Photos-only General settings (Autoplay, HDR, Memories, Sharing location, Smart Search, Privacy lock). Implement only those the app/server supports; list the omitted ones in the report |

## 5. Tests (added to TEST-PLAN §2, WP-C)

| ID | Tests |
|---|---|
| C7 | S: toolbar snapshot at 1728 / 1280 / 900 pt widths, light and dark, for Library, an album, and the viewer (T2).<br>U: toolbar item identifiers equal the spec order, and no `toolbar.select` / `toolbar.sync` exist.<br>U: the filter button opens a menu with the filter titles; "…" opens the Show menu; View › Sort exists.<br>UI: the scope capsule's label equals the selected library's full name after choosing "Family"; the name is middle-truncated for a 60-character fixture name.<br>UI: the title block's `navigationTitle` is "Library" and the subtitle is the visible range; the frame's x is left of the scope capsule |
| C8 | S: each Settings tab, light and dark.<br>UI: the Server tab shows the fixture user's name, email and user ID together. U: every pre-existing preference key (`defaultUploadTarget`, `Heirloom.importDestination`, `showPersonalInTimeline`, `hiddenOwnedLibraryIds`, originals budget, per-library keep flags, agent toggle) is bound and round-trips through the new UI models.<br>U: **no control or string offers downloading all originals** (search the view tree for "Download Originals").<br>UI: ⌘, opens the last-used tab; Purge Unpinned… shows a confirmation, and Cancel changes nothing |
| C9 | U: a hidden-when-unsupported rule for each optional General item (capability flags injected) |
