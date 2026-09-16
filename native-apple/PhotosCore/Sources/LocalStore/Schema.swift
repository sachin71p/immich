import GRDB

/// Schema v1 — CODEMAP §F / A1 brief task 1. One migration per brief-listed table group; GRDB replays
/// these against a fresh database and no-ops on an up-to-date one, so schema growth in later phases is
/// always a *new* `registerMigration` call, never an edit to these.
enum Schema {
  static func makeMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()

    migrator.registerMigration("v1_users_partners") { db in
      try db.create(table: "user") { t in
        t.primaryKey("id", .text)
        t.column("name", .text).notNull()
        t.column("email", .text).notNull()
        t.column("avatarColor", .text)
        t.column("deletedAt", .datetime)
        t.column("hasProfileImage", .boolean).notNull().defaults(to: false)
        t.column("profileChangedAt", .datetime)
        t.column("isAdmin", .boolean)
        t.column("storageLabel", .text)
        t.column("quotaSizeInBytes", .integer)
        t.column("quotaUsageInBytes", .integer)
      }
      try db.create(table: "partner") { t in
        t.column("sharedById", .text).notNull()
        t.column("sharedWithId", .text).notNull()
        t.column("inTimeline", .boolean).notNull().defaults(to: true)
        t.primaryKey(["sharedById", "sharedWithId"])
      }
    }

    migrator.registerMigration("v1_assets_exif") { db in
      try db.create(table: "asset") { t in
        t.primaryKey("id", .text)
        t.column("ownerId", .text).notNull()
        t.column("originalFileName", .text).notNull()
        t.column("thumbhash", .text)
        t.column("checksum", .text).notNull()
        t.column("fileCreatedAt", .datetime)
        t.column("fileModifiedAt", .datetime)
        t.column("createdAt", .datetime)
        t.column("localDateTime", .datetime)
        t.column("durationSeconds", .integer)
        t.column("type", .text).notNull()
        t.column("deletedAt", .datetime)
        t.column("isFavorite", .boolean).notNull().defaults(to: false)
        t.column("visibility", .text).notNull().defaults(to: "timeline")
        t.column("livePhotoVideoId", .text)
        t.column("stackId", .text)
        t.column("libraryId", .text)
        // fork: shared-libraries — DECISIONS §10.
        t.column("spaceId", .text)
        t.column("width", .integer)
        t.column("height", .integer)
        t.column("isEdited", .boolean).notNull().defaults(to: false)
        // Apple-only: which local Photos asset an unsynced upload came from (Upload module, A2).
        t.column("localIdentifier", .text)
      }
      try db.create(index: "asset_on_localDateTime", on: "asset", columns: ["localDateTime"])
      try db.create(index: "asset_on_spaceId", on: "asset", columns: ["spaceId"])
      try db.create(index: "asset_on_libraryId", on: "asset", columns: ["libraryId"])
      try db.create(index: "asset_on_ownerId", on: "asset", columns: ["ownerId"])

      try db.create(table: "assetExif") { t in
        t.primaryKey("assetId", .text)
        t.column("description", .text)
        t.column("exifImageWidth", .integer)
        t.column("exifImageHeight", .integer)
        t.column("fileSizeInByte", .integer)
        t.column("orientation", .text)
        t.column("dateTimeOriginal", .datetime)
        t.column("modifyDate", .datetime)
        t.column("timeZone", .text)
        t.column("latitude", .double)
        t.column("longitude", .double)
        t.column("projectionType", .text)
        t.column("city", .text)
        t.column("state", .text)
        t.column("country", .text)
        t.column("make", .text)
        t.column("model", .text)
        t.column("lensModel", .text)
        t.column("fNumber", .double)
        t.column("focalLength", .double)
        t.column("iso", .integer)
        t.column("exposureTime", .text)
        t.column("profileDescription", .text)
        t.column("rating", .integer)
        t.column("fps", .double)
      }
    }

    migrator.registerMigration("v1_albums") { db in
      try db.create(table: "album") { t in
        t.primaryKey("id", .text)
        t.column("name", .text).notNull()
        t.column("description", .text).notNull().defaults(to: "")
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("thumbnailAssetId", .text)
        t.column("isActivityEnabled", .boolean).notNull().defaults(to: false)
        t.column("order", .text).notNull().defaults(to: "desc")
      }
      try db.create(table: "albumUser") { t in
        t.column("albumId", .text).notNull()
        t.column("userId", .text).notNull()
        t.column("role", .text).notNull()
        t.primaryKey(["albumId", "userId"])
      }
      try db.create(table: "albumAsset") { t in
        t.column("albumId", .text).notNull()
        t.column("assetId", .text).notNull()
        t.primaryKey(["albumId", "assetId"])
      }
      try db.create(index: "albumAsset_on_assetId", on: "albumAsset", columns: ["assetId"])
    }

    migrator.registerMigration("v1_stacks") { db in
      try db.create(table: "stack") { t in
        t.primaryKey("id", .text)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("primaryAssetId", .text).notNull()
        t.column("ownerId", .text).notNull()
      }
    }

    migrator.registerMigration("v1_spaces_libraries") { db in
      try db.create(table: "space") { t in
        t.primaryKey("id", .text)
        t.column("name", .text).notNull()
        t.column("description", .text).notNull().defaults(to: "")
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
      }
      try db.create(table: "spaceMember") { t in
        t.column("spaceId", .text).notNull()
        t.column("userId", .text).notNull()
        t.column("role", .text).notNull()
        t.column("showInTimeline", .boolean).notNull().defaults(to: true)
        t.primaryKey(["spaceId", "userId"])
      }
      try db.create(table: "library") { t in
        t.primaryKey("id", .text)
        t.column("name", .text).notNull()
        t.column("ownerId", .text).notNull()
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
        // Not carried by SyncSharedLibraryV1; hydrated via a `getLibrary` REST fallback — see A1 handoff.
        // `uploadPathHydrated` distinguishes "not yet fetched" from "fetched, genuinely unset".
        t.column("uploadPath", .text)
        t.column("uploadPathHydrated", .boolean).notNull().defaults(to: false)
      }
      // No SharedLibraryMemberV1 sync entity exists (A1 handoff CODEMAP-FIX); this table exists for
      // schema completeness and future REST hydration, but A1's Rules only relies on `library.ownerId`
      // and the fact that a `SharedLibraryV1` row exists at all (sync is membership-scoped).
      try db.create(table: "libraryMember") { t in
        t.column("libraryId", .text).notNull()
        t.column("userId", .text).notNull()
        t.column("role", .text).notNull()
        t.column("showInTimeline", .boolean).notNull().defaults(to: true)
        t.primaryKey(["libraryId", "userId"])
      }
    }

    migrator.registerMigration("v1_people_faces") { db in
      try db.create(table: "person") { t in
        t.primaryKey("id", .text)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("ownerId", .text).notNull()
        t.column("name", .text).notNull()
        t.column("birthDate", .datetime)
        t.column("isHidden", .boolean).notNull().defaults(to: false)
        t.column("isFavorite", .boolean).notNull().defaults(to: false)
        t.column("color", .text)
        t.column("faceAssetId", .text)
      }
      try db.create(table: "face") { t in
        t.primaryKey("id", .text)
        t.column("assetId", .text).notNull()
        t.column("personId", .text)
        t.column("imageWidth", .integer).notNull()
        t.column("imageHeight", .integer).notNull()
        t.column("boundingBoxX1", .integer).notNull()
        t.column("boundingBoxY1", .integer).notNull()
        t.column("boundingBoxX2", .integer).notNull()
        t.column("boundingBoxY2", .integer).notNull()
        t.column("sourceType", .text).notNull()
        t.column("deletedAt", .datetime)
        t.column("isVisible", .boolean).notNull().defaults(to: true)
      }
      try db.create(index: "face_on_assetId", on: "face", columns: ["assetId"])
    }

    migrator.registerMigration("v1_memories") { db in
      try db.create(table: "memory") { t in
        t.primaryKey("id", .text)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("deletedAt", .datetime)
        t.column("ownerId", .text).notNull()
        t.column("type", .text).notNull()
        t.column("dataJSON", .text).notNull()
        t.column("isSaved", .boolean).notNull().defaults(to: false)
        t.column("memoryAt", .datetime).notNull()
        t.column("seenAt", .datetime)
        t.column("showAt", .datetime)
        t.column("hideAt", .datetime)
      }
      try db.create(table: "memoryAsset") { t in
        t.column("memoryId", .text).notNull()
        t.column("assetId", .text).notNull()
        t.primaryKey(["memoryId", "assetId"])
      }
    }

    migrator.registerMigration("v1_prefs_sync_cache") { db in
      try db.create(table: "userMetadata") { t in
        t.column("userId", .text).notNull()
        t.column("key", .text).notNull()
        t.column("valueJSON", .text).notNull()
        t.primaryKey(["userId", "key"])
      }
      // One checkpoint row per SyncEntityType — the last acked "type|updateId|extraId" string
      // (server/src/utils/sync.ts `toAck`); resumed sync starts here. CODEMAP §F.
      try db.create(table: "syncAck") { t in
        t.primaryKey("type", .text)
        t.column("ack", .text).notNull()
      }
      // Media module (later phase) cache index; A1 only owns the schema.
      try db.create(table: "mediaCache") { t in
        t.column("assetId", .text).notNull()
        t.column("variant", .text).notNull()
        t.column("localPath", .text).notNull()
        t.column("sizeBytes", .integer).notNull()
        t.column("lastAccessedAt", .datetime).notNull()
        t.primaryKey(["assetId", "variant"])
      }
    }

    // Album sharing is relational upstream (albumUser rows), but the app sidebar needs a durable
    // local classification that updates immediately after a share/unshare sync batch.
    migrator.registerMigration("v2_album_sharing_type") { db in
      try db.alter(table: "album") { t in
        t.add(column: "sharingType", .text).notNull().defaults(to: "personal")
      }
      try db.execute(sql: """
        UPDATE album SET sharingType = CASE
          WHEN (SELECT COUNT(*) FROM albumUser WHERE albumUser.albumId = album.id) > 1 THEN 'shared'
          ELSE 'personal' END
        """)
    }

    // A5: durable upload queue. One row per file part to send (live-photo still+motion and
    // original+edit pairs enqueue as separate rows linked by `pairId`, uploaded motion-first).
    migrator.registerMigration("v2_upload_queue") { db in
      try db.create(table: "uploadQueue") { t in
        t.primaryKey("id", .text)
        t.column("pairId", .text)
        t.column("kind", .text).notNull()
        t.column("state", .text).notNull().defaults(to: "pending")
        t.column("localIdentifier", .text)
        t.column("filePath", .text).notNull()
        t.column("checksum", .text).notNull()
        t.column("fileName", .text).notNull()
        t.column("fileCreatedAt", .datetime)
        t.column("fileModifiedAt", .datetime)
        t.column("isFavorite", .boolean).notNull().defaults(to: false)
        t.column("durationMs", .integer)
        t.column("isVideo", .boolean).notNull().defaults(to: false)
        t.column("spaceId", .text)
        t.column("livePhotoVideoId", .text)
        t.column("serverAssetId", .text)
        t.column("attempts", .integer).notNull().defaults(to: 0)
        t.column("nextRetryAt", .datetime)
        t.column("lastError", .text)
        t.column("createdAt", .datetime).notNull()
      }
      try db.create(index: "uploadQueue_on_state", on: "uploadQueue", columns: ["state"])
      try db.create(index: "uploadQueue_on_checksum", on: "uploadQueue", columns: ["checksum"])
      try db.create(table: "backupChangeToken") { t in
        t.primaryKey("scope", .text)
        t.column("tokenData", .blob)
        t.column("updatedAt", .datetime).notNull()
      }
    }

    // Every timeline/browse query excludes Live Photo motion-video components via
    // `id NOT IN (SELECT livePhotoVideoId FROM asset WHERE livePhotoVideoId IS NOT NULL)`
    // (rowSelectSQL in LocalStore+Timeline). Without an index that inner SELECT is a full table
    // scan, and `MacGridLoader.bucketed()` runs it once per month bucket — a library spanning
    // decades can mean hundreds of scans per grid load, turning into minutes of "0 photos".
    migrator.registerMigration("v2_livephoto_video_index") { db in
      try db.create(index: "asset_on_livePhotoVideoId", on: "asset", columns: ["livePhotoVideoId"])
    }

    // WP1: the timeline hot path filters `deletedAt IS NULL AND visibility != 'locked'` and
    // orders by `localDateTime` on every grid query — a composite index keeps the planner off
    // full scans at 100k+ rows. New migration, never an edit to an old one.
    migrator.registerMigration("v3_timeline_cover_index") { db in
      try db.create(
        index: "asset_on_deleted_visibility_localDateTime", on: "asset",
        columns: ["deletedAt", "visibility", "localDateTime"])
    }

    return migrator
  }
}
