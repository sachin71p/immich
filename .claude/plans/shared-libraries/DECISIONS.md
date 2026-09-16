# Shared Libraries Fork — Product & Design Decisions

Source of truth for *what* we build and the rules. Agents: read only the sections your phase
file points to. Do not re-derive or re-litigate anything here. If a rule is ambiguous or
contradicts the code, STOP and write `BLOCKED:` in your handoff — do not improvise.

## §1 Vocabulary
| UI term | Code term | Meaning |
|---|---|---|
| Personal library | (implicit) | Assets with `spaceId IS NULL AND libraryId IS NULL`, owned by a user |
| Shared library | `SharedSpace`, table `shared_space` | Named, group-owned container. Immich already uses "library" for external libraries, so code says **space**. |
| External library | `Library`, table `library` (upstream) | Existing import-path library, extended with members + `uploadPath` |
| Container | — | Exactly one of: personal(ownerId) · space(spaceId) · external(libraryId) |
| Contributor | `asset.ownerId` | User who uploaded / first added the asset. Never changes on move. |

## §2 Requirements (keep numbering in commits and test names)
- R1 Each user has a personal library.
- R2 Any user can create shared libraries and add other users. Creator = `owner`; others = `contributor`.
- R3 A user picks personal OR one shared library as default upload target.
- R4 Move assets personal → shared.
- R5 Move *own* assets (ownerId = me) shared → personal.
- R6 In a shared library every member can edit, favorite, archive, trash/restore/permanently delete, add to albums, and move assets.
- R7 Multiple, freely named shared libraries per user.
- R8 Each user chooses which containers appear on their timeline.
- R9 External libraries can be shared with users and are selectable timeline sources.
- R10 Move media to any container the user has access to (move rules §6).
- R11 Shared albums: every album member can add AND remove assets.
- R12 View all image metadata (full exiftool dump, not only the DB subset).
- R13 Filter & search by metadata (extended filters) across visible containers.
- R14 iOS app keeps Immich mobile "Free up space" retention settings (cutoff date, keep favorites, keep albums).
- R15 Native iOS app implements as many Apple Photos features as possible.
- R16 Favorites are global per asset: anyone who can see the asset via a space, shared external library or shared album sees the same flag and may toggle it.
- R17 Each container has its own directory tree on disk; moving an asset between containers physically moves its files.

## §3 Invariants (enforce in code + tests)
- I1 `asset.spaceId` and `asset.libraryId` are never both non-null (DB CHECK constraint).
- I2 `asset.ownerId` is always a real user. Moves never change it; only the lifecycle reassignments in §8 do.
- I3 A live-photo still + its motion asset, and every asset of a stack, share one container. Moving one moves all.
- I4 Every file of an asset lives under the path computed for its current container (§7). Only the relocation
  engine moves files, always via upstream `StorageCore.moveFile` (move_history, crash-safe).
- I5 Backward compatible for the upstream Flutter app: existing endpoints keep their shapes; new behaviour is
  additive (new endpoints, new optional fields, new sync types).
- I6 DB container columns are the source of truth immediately after a move; files follow asynchronously.
  Every pending relocation has a row in `asset_relocation` until its files are in place.
- I7 `visibility = Locked` assets are always personal: they cannot be moved into a space/library, and a
  space/library asset cannot be set to Locked.

## §4 Roles & permissions
Space roles: `owner` (exactly one per space), `contributor`.

| Action | owner | contributor | non-member |
|---|---|---|---|
| View / download space assets | ✓ | ✓ | ✗ (unless via shared album / shared link) |
| Upload into space; move in/out (§6) | ✓ | ✓ | ✗ |
| Edit metadata, edit image, favorite, archive, trash, restore, permanently delete space assets | ✓ | ✓ | ✗ |
| Add space assets to albums / shared links (AssetShare) | ✓ | ✓ | ✗ |
| Rename space, description, cover | ✓ | ✓ | ✗ |
| Add members; remove a contributor | ✓ | ✓ | ✗ |
| Leave space | ✗ (delete or transfer first) | ✓ | — |
| Transfer ownership to a contributor | ✓ | ✗ | — |
| Delete space | ✓ | ✗ | — |

- External library sharing (R9): `library.ownerId` acts as owner; `library_member` rows give contributor rights on
  the library's *assets* per the table. Library settings (import paths, exclusions, uploadPath, scan, delete,
  members) stay admin-only as upstream.
- A contributor removed from a space loses access to the assets they contributed that remain in the space
  (upstream owner-access is narrowed: `ownerId = me AND (spaceId IS NULL OR I am a member of spaceId)`).
- Albums (R11): every album member of any role may add and remove any asset in the album. The role enum is kept
  for compatibility; role only gates album-level settings (rename, share, delete). A user can never change their
  own role, and nobody can set a role to `owner` via the album-user update endpoint.
- Favorites (R16): `asset.isFavorite` stays one column. New internal permission `AssetFavorite` is granted to:
  owner-access, space members, library members, members of any album containing the asset. Partners: no.
  An update request whose only field is `isFavorite` requires `AssetFavorite`; anything else requires `AssetUpdate`.
- Sync shows the real `isFavorite` to album/space/library viewers (upstream forces false for non-owners).
  Partner streams keep upstream behaviour.
- Faces/people follow cluster-group membership, not container membership. Space table rights confer
  no face/person rights beyond S9 space-scoped rows; library membership confers none. A removed
  library member loses face access to owned library assets (the owner leg additionally requires
  current library owner-or-membership); a current non-owner library member gains nothing.

## §5 New permissions (enum `Permission`, usable as API-key scopes)
`sharedSpace.create`, `sharedSpace.read`, `sharedSpace.update`, `sharedSpace.delete`,
`sharedSpaceMember.create`, `sharedSpaceMember.update`, `sharedSpaceMember.delete`,
`libraryMember.create`, `libraryMember.delete` (admin), `asset.move`, `asset.favorite`.
Access branches for them live in `server/src/utils/access.ts` like all others.

## §6 Move rules (R4, R5, R10)
Source container S, target container T, acting user U. Endpoint `POST /assets/move`.
1. U needs container access to S (owner-access, space member, library member). Album/partner/shared-link access is not enough.
2. T = personal → only if `asset.ownerId = U`.
3. T = space → U is a member of T.
4. T = external library → U is library owner or member AND `library.uploadPath` is set.
5. Selection is expanded to whole live-photo pairs and stacks (I3). If any expanded asset fails a rule, that
   whole group fails; other groups proceed. Response is per requested asset: `moved | noop | error(reason)`.
6. Moving never changes ownerId, albums, favorites, tags, faces, edits, or asset ids.
7. Moving to the current container is `noop`.
8. Duplicate-checksum collision in the target (upstream unique indexes) → `error(duplicate)` for that group.
9. Locked assets cannot move (I7).

## §7 Directory layout (R17)
`L(user)` = `user.storageLabel ?? user.id` (upstream). `space.storageLabel` = unique slug, derived from name at
creation (de-duplicated with `-2`, `-3`…), immutable afterwards except by an admin. Storage key
`K(asset)` = `shared/<spaceId>` if `spaceId` else `ownerId`.

| Files | Personal (upstream) | Space (new) | External library |
|---|---|---|---|
| Original, storage template ON | `library/<L(owner)>/<template>` | `library/shared/<space.storageLabel>/<template>` | moved-in: `<library.uploadPath>/<template>`; scanned files stay where found |
| Original, storage template OFF | `upload/<ownerId>/xx/yy/<file>` | `upload/shared/<spaceId>/xx/yy/<file>` | moved-in: `<library.uploadPath>/<originalFileName>` (de-dup suffix) |
| thumbnail / preview / fullsize / edited variants | `thumbs/<ownerId>/xx/yy/…` | `thumbs/shared/<spaceId>/xx/yy/…` | upstream (`ownerId`) |
| encoded video, android motion | `encoded-video/<ownerId>/xx/yy/…` | `encoded-video/shared/<spaceId>/xx/yy/…` | upstream (`ownerId`) |
| sidecar | `<original>.xmp` | same rule | same rule |

- User storage label `shared` is reserved: validation rejects it; the S1 migration fails with a clear message if a
  user already has it.
- Upload staging stays upstream (`upload/<ownerId>/…`); relocation then moves files into the container's tree.
- `library.uploadPath` must be absolute, inside one of the library's `importPaths`, and writable (checked on save).
- HLS session folders (transient) stay upstream.

## §8 Lifecycle
- Space deletion (owner only): all its assets → `spaceId = NULL` (back to each contributor's personal), relocation
  rows inserted and jobs queued, then the space row is deleted. Albums untouched.
- Member removed / leaves: their contributions stay in the space.
- Ownership transfer: owner ↔ contributor role swap in one transaction.
- User deletion (upstream cascades delete every asset the user owns): a pre-step in the user-delete job runs
  BEFORE any upstream deletion:
  1. For each space the user owns: transfer ownership to the earliest-joined contributor; if none, delete the space
     (assets return to personal and will be deleted with the user).
  2. Reassign `ownerId` of the user's assets that are in a space → that space's owner; in an external library they
     don't own → the library owner.
  3. Relocate reassigned assets inline (derived files keyed by ownerId must leave the user's folders), re-queue face
     detection for them. If any relocation fails, throw → the job retries later; never proceed to folder deletion.
- Trash: trashing a space asset puts it in the Trash of every member. "Empty trash" by a user empties only assets
  in containers the user can manage (own personal + member spaces + member libraries).
- Archive flag is global per asset (archiving a space asset archives it for all members).

## §9 Preferences & container filters (R3, R8)
- User preference `sharedLibraries.defaultUploadTarget`: `{ type: 'personal' } | { type: 'space', spaceId }`.
  Upload accepts optional `spaceId`; if absent the server applies the preference; a stale spaceId falls back to personal.
- User preference `sharedLibraries.showPersonalInTimeline` (default true).
- `shared_space_member.showInTimeline` and `library_member.showInTimeline` (default true). The library owner's own
  toggle lives in user preference `sharedLibraries.hiddenOwnedLibraryIds` (default empty).
- Partners keep upstream `partner.inTimeline`.
- Timeline and search DTOs get optional, mutually exclusive filters `spaceId`, `libraryId`, `personalOnly`
  (the Apple-style library switcher). Explicit filter overrides preferences (access-checked).

## §10 Visibility scope
`ContainerScope = { personalUserIds, spaceIds, libraryIds }`. An asset is in scope iff
`(spaceId IS NULL AND libraryId IS NULL AND ownerId = ANY(personalUserIds))
 OR spaceId = ANY(spaceIds) OR libraryId = ANY(libraryIds)`.
Scope purposes:
- `timeline` (timeline, favorites view, search, map, explore, memories, stats, calendar): personal = [me if
  showPersonal] + partners (only when the request allows partners, as upstream); spaces/libraries = member ones with
  showInTimeline (owned libraries minus hiddenOwnedLibraryIds).
- `manage` (trash, archive, locked): personal = [me]; all member spaces + member/owned libraries regardless of toggles;
  no partners. Locked view: personal = [me] only.
- Explicit filter → exactly that container.
Known behaviour change: partners no longer see a partner's external-library assets through partner sharing (share
the library instead).

## §11 Out of scope / known limitations
- People/faces are partitioned by cluster group (`user.clusterGroupId`, one per user). S9 space-scoped
  rows live in each space's universe (`shared_space.clusterGroupId`, lazily via `createSpaceGroup`).
  External libraries have no `clusterGroupId`, so their faces stay in the owner's personal cluster
  group. The supported cross-user mechanism is the upstream cluster-group-request flow
  (`cluster_group_request` unique `(clusterGroupId, userId)`; request/accept in
  `cluster-group.service.ts`, `ClusterGroupRequestCreate` permission, notification event). The
  library-membership face grant was considered and refused: it would expose the owner's entire
  personal face graph, and no container-scoped graph exists without new schema, a migration, and
  re-clustering.
- Duplicate detection (ML) stays per-owner.
- Upstream Flutter app gains no new UI (must keep working).
- Per-user favorites.
