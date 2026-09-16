# Shared Libraries Audit Contract Checklist

R1 | Each user has a personal library.
R2 | Any user can create shared libraries and add other users; creator is owner and others are contributors.
R3 | A user chooses personal or one shared library as their default upload target.
R4 | Assets can move personal to shared.
R5 | A user can move only their own assets from shared to personal.
R6 | Every shared-library member can edit, favorite, archive, trash/restore/permanently delete, add to albums, and move assets.
R7 | Users can have multiple freely named shared libraries.
R8 | Each user can choose timeline containers.
R9 | External libraries can be shared with users and selected as timeline sources.
R10 | Media can move to any container the user can access, subject to §6.
R11 | Every shared-album member can add and remove assets.
R12 | View the complete exiftool metadata dump.
R13 | Filter and search metadata across visible containers.
R14 | Native iOS retains Immich mobile Free up space settings.
R15 | Native iOS implements as many Apple Photos features as possible.
R16 | Favorites are global per asset; eligible space/library/album viewers see and may toggle the same value.
R17 | Each container has its own on-disk tree; container moves physically relocate files.

I1 | spaceId and libraryId are never both non-null; DB CHECK plus code and tests.
I2 | ownerId always references a real user; moves preserve it except §8 lifecycle reassignment.
I3 | Live-photo still/motion pairs and all stack assets share a container; moves include the group.
I4 | Every asset file is under its current container path; only relocation moves files through StorageCore.moveFile with move history and crash safety.
I5 | Existing upstream Flutter API shapes remain compatible; additions are additive.
I6 | Database container columns change immediately; pending files have an asset_relocation row until in place.
I7 | Locked assets are personal only and cannot move into containers; container assets cannot become Locked.

PERM-01-owner | View/download space assets: allowed.
PERM-01-contributor | View/download space assets: allowed.
PERM-01-nonmember | View/download space assets: denied except shared album/link.
PERM-02-owner | Upload into a space and move in/out: allowed.
PERM-02-contributor | Upload into a space and move in/out: allowed.
PERM-02-nonmember | Upload into a space and move in/out: denied.
PERM-03-owner | Edit/favorite/archive/trash/restore/permanently delete space assets: allowed.
PERM-03-contributor | Edit/favorite/archive/trash/restore/permanently delete space assets: allowed.
PERM-03-nonmember | Edit/favorite/archive/trash/restore/permanently delete space assets: denied.
PERM-04-owner | Add space assets to albums/shared links: allowed.
PERM-04-contributor | Add space assets to albums/shared links: allowed.
PERM-04-nonmember | Add space assets to albums/shared links: denied.
PERM-05-owner | Rename space, description, and cover: allowed.
PERM-05-contributor | Rename space, description, and cover: allowed.
PERM-05-nonmember | Rename space, description, and cover: denied.
PERM-06-owner | Add members and remove a contributor: allowed.
PERM-06-contributor | Add members and remove a contributor: allowed.
PERM-06-nonmember | Add members and remove a contributor: denied.
PERM-07-owner | Leave space: denied; transfer or delete first.
PERM-07-contributor | Leave space: allowed.
PERM-07-nonmember | Leave space: not applicable.
PERM-08-owner | Transfer ownership to a contributor: allowed.
PERM-08-contributor | Transfer ownership to a contributor: denied.
PERM-08-nonmember | Transfer ownership to a contributor: not applicable.
PERM-09-owner | Delete space: allowed.
PERM-09-contributor | Delete space: denied.
PERM-09-nonmember | Delete space: not applicable.
PERM-10 | External-library members have contributor asset rights; settings, import paths, exclusions, uploadPath, scan, delete, and members remain admin-only.
PERM-11 | Removed space contributors lose access to their remaining contributions.
PERM-12 | Any album member may add/remove any album asset; roles only gate album settings.
PERM-13 | No album user may change their own role or set owner through album-user update.
PERM-14 | AssetFavorite applies to owner access, space members, library members, and members of any album containing the asset; partners are excluded.
PERM-15 | Favorite-only updates require AssetFavorite; other updates require AssetUpdate.
PERM-16 | Sync preserves real isFavorite for album/space/library viewers; partners retain upstream behavior.
