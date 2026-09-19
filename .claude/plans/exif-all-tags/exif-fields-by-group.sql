-- exif-fields-by-group.sql
--
-- Inventory every raw EXIF/metadata tag stored in `asset_exif_raw`, by exiftool family-1 group.
-- Read-only (only creates session-scoped TEMP tables). Run it against the Heirloom DB:
--
--   ssh homelab 'pct exec 403 -- docker exec -i database psql -U postgres -d heirloom' \
--     < .claude/plans/exif-all-tags/exif-fields-by-group.sql
--
-- Add `-A -F,` (and drop the \echo lines) if you want CSV out of section 3.
--
-- `asset_exif_raw` layout (see PLAN.md):
--   tags        jsonb  { "<group>": { "<tag>": <value>, ... }, ... }   from the original file
--   sidecarTags jsonb  same shape, from the .xmp sidecar (NULL when there is none)
--
-- The `kind` column is a HEURISTIC classification of the group name:
--   standard-exif       camera/TIFF/Exif/GPS/JFIF/ICC blocks defined by public specs
--   standard-xmp-iptc   XMP/IPTC namespaces defined by public specs (Dublin Core, xmp, tiff, exif, ...)
--   derived             computed by exiftool or the filesystem, NOT stored in the file (File, System, Composite, ExifTool)
--   container           media container structure (QuickTime atoms, PNG chunks, MPF, ...)
--   vendor-custom       everything else: MakerNotes, Apple/Google/DJI/Canon/... blocks and app-specific
--                       XMP namespaces (crs, lr, digiKam, apple-fi, GCamera, ...)

\set ON_ERROR_STOP on
\timing off

-- One pass over every tag of every asset. Aggregated immediately so we never materialise
-- the ~50M-row unnested set.
CREATE TEMP TABLE _exif_tag_stats AS
SELECT src.source,
       g.key                       AS grp,
       t.tag,
       count(*)                    AS assets,
       mode() WITHIN GROUP (ORDER BY jsonb_typeof(t.val)) AS value_type,
       min(left(t.val::text, 60))  AS sample_value
FROM (
  SELECT "assetId", 'file'::text AS source, tags AS doc
  FROM asset_exif_raw
  UNION ALL
  SELECT "assetId", 'sidecar'::text, "sidecarTags"
  FROM asset_exif_raw
  WHERE "sidecarTags" IS NOT NULL
) src
CROSS JOIN LATERAL jsonb_each(src.doc)     AS g(key, value)
CROSS JOIN LATERAL jsonb_each(g.value)     AS t(tag, val)
WHERE jsonb_typeof(g.value) = 'object'
GROUP BY src.source, g.key, t.tag;

CREATE TEMP TABLE _exif_group_kind AS
SELECT DISTINCT grp,
  CASE
    WHEN grp IN ('File', 'System', 'Composite', 'ExifTool')                      THEN 'derived'
    WHEN grp IN ('IFD0', 'IFD1', 'ExifIFD', 'GPS', 'InteropIFD', 'SubIFD', 'EXIF',
                 'JFIF', 'IPTC', 'Photoshop')
      OR grp LIKE 'ICC%' OR grp LIKE 'SubIFD%' OR grp LIKE 'IFD%'                THEN 'standard-exif'
    WHEN grp IN ('XMP-dc', 'XMP-xmp', 'XMP-xmpRights', 'XMP-xmpMM', 'XMP-xmpBJ',
                 'XMP-tiff', 'XMP-exif', 'XMP-exifEX', 'XMP-photoshop',
                 'XMP-iptcCore', 'XMP-iptcExt', 'XMP-plus', 'XMP-mwg-rs', 'XMP-mwg-kw',
                 'XMP-MP', 'XMP-dwc', 'XMP-acdsee', 'XMP-x')                     THEN 'standard-xmp-iptc'
    WHEN grp IN ('QuickTime', 'MPF', 'MPImage', 'PNG', 'PNG-pHYs', 'RIFF', 'Meta',
                 'Track', 'Keys', 'ItemList', 'UserData', 'Trailer', 'Extra')
      OR grp ~ '^(Track|Media|Handler|Meta)[0-9]*$'
      OR grp LIKE 'PNG-%'                                                        THEN 'container'
    ELSE                                                                            'vendor-custom'
  END AS kind
FROM _exif_tag_stats;

-- Tags Immich promotes into a real `asset_exif` column (approximate, by tag name).
CREATE TEMP TABLE _immich_promoted (tag text PRIMARY KEY, asset_exif_column text) ;
INSERT INTO _immich_promoted VALUES
  ('Make','make'), ('Model','model'), ('LensModel','lensModel'), ('LensID','lensModel'),
  ('FNumber','fNumber'), ('Aperture','fNumber'), ('FocalLength','focalLength'), ('ISO','iso'),
  ('ExposureTime','exposureTime'), ('ShutterSpeed','exposureTime'),
  ('ExifImageWidth','exifImageWidth'), ('ExifImageHeight','exifImageHeight'),
  ('ImageWidth','exifImageWidth'), ('ImageHeight','exifImageHeight'),
  ('Orientation','orientation'), ('DateTimeOriginal','dateTimeOriginal'), ('CreateDate','dateTimeOriginal'),
  ('ModifyDate','modifyDate'), ('GPSLatitude','latitude'), ('GPSLongitude','longitude'),
  ('ImageDescription','description'), ('Description','description'), ('Caption-Abstract','description'),
  ('Rating','rating'), ('Subject','tags'), ('Keywords','tags'), ('TagsList','tags'), ('HierarchicalSubject','tags'),
  ('OffsetTimeOriginal','timeZone'), ('OffsetTime','timeZone'), ('TimeZone','timeZone'),
  ('ProfileDescription','profileDescription'), ('ColorSpace','colorspace'), ('BitsPerSample','bitsPerSample'),
  ('ProjectionType','projectionType'), ('VideoFrameRate','fps'), ('ContentIdentifier','livePhotoCID'),
  ('MediaGroupUUID','livePhotoCID'), ('ImageUniqueID','autoStackId'), ('BurstUUID','autoStackId');

\echo
\echo '== 1. Coverage =========================================================='
SELECT (SELECT count(*) FROM asset WHERE "deletedAt" IS NULL)                 AS live_assets,
       (SELECT count(*) FROM asset_exif)                                      AS asset_exif_rows,
       (SELECT count(*) FROM asset_exif_raw)                                  AS raw_rows,
       (SELECT count(*) FROM asset_exif_raw WHERE "sidecarTags" IS NOT NULL)  AS raw_rows_with_sidecar,
       (SELECT count(*) FROM _exif_tag_stats)                                 AS distinct_group_tag_pairs,
       (SELECT count(DISTINCT grp) FROM _exif_tag_stats)                      AS distinct_groups;

\echo
\echo '== 2. Groups (kind, tag count, coverage) ==================================='
SELECT k.kind,
       s.grp                                     AS "group",
       count(DISTINCT s.tag)                     AS distinct_tags,
       sum(s.assets)                             AS tag_occurrences,
       max(s.assets)                             AS max_assets_with_a_tag,
       round(100.0 * max(s.assets) / NULLIF((SELECT count(*) FROM asset_exif_raw), 0), 1) AS max_pct_of_raw_rows,
       count(DISTINCT s.tag) FILTER (WHERE p.tag IS NOT NULL) AS tags_promoted_to_asset_exif
FROM _exif_tag_stats s
JOIN _exif_group_kind k USING (grp)
LEFT JOIN _immich_promoted p ON p.tag = s.tag
GROUP BY k.kind, s.grp
ORDER BY k.kind, distinct_tags DESC, s.grp;

\echo
\echo '== 2b. Rollup by kind ===================================================='
SELECT k.kind,
       count(DISTINCT s.grp)                                AS groups,
       count(*)                                             AS distinct_group_tag_pairs
FROM _exif_tag_stats s JOIN _exif_group_kind k USING (grp)
GROUP BY k.kind ORDER BY 3 DESC;

\echo
\echo '== 3. Every tag by group (coverage, type, sample, promoted column) ======='
SELECT k.kind,
       s.grp                                     AS "group",
       s.tag,
       s.source,
       s.assets,
       round(100.0 * s.assets / NULLIF((SELECT count(*) FROM asset_exif_raw), 0), 2) AS pct_of_raw_rows,
       s.value_type,
       p.asset_exif_column                       AS stored_in_asset_exif_as,
       s.sample_value
FROM _exif_tag_stats s
JOIN _exif_group_kind k USING (grp)
LEFT JOIN _immich_promoted p ON p.tag = s.tag
ORDER BY k.kind, s.grp, s.assets DESC, s.tag;

\echo
\echo '== 4. Tags found in files but NOT stored in any asset_exif column (the gain) =='
SELECT k.kind, s.grp AS "group", count(*) AS unpromoted_tags, sum(s.assets) AS occurrences
FROM _exif_tag_stats s
JOIN _exif_group_kind k USING (grp)
LEFT JOIN _immich_promoted p ON p.tag = s.tag
WHERE p.tag IS NULL AND k.kind <> 'derived'
GROUP BY k.kind, s.grp
ORDER BY occurrences DESC
LIMIT 40;
