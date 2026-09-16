# Heirloom Web V2 — management sheets (WP7)

V2-owned dialog components under `web/src/lib/components/heirloom/dialogs/`.
Presentation only (PLAN §13): every SDK call, store update, toast, and event
below reuses the exact contract of the classic modal/page named beside it. No
classic modal, service, store, or util was modified.

## Files

| File | Native sheet (WP1 §6) | Width | Service reuse |
| --- | --- | --- | --- |
| `sheet-logic.ts` | — (pure helpers) | — | `SharedSpaceRole`, `Status` types only |
| `V2Sheet.svelte` | all sheets (shell) | prop | focus-restore helper from `sheet-logic` |
| `V2NewAlbumSheet.svelte` | New Album (Name, Create disabled on blank) | 300 | `sdk.createAlbum` + `eventManager.emit('AlbumCreate')` (cf. `album-utils.createAlbum`) |
| `V2AddToAlbumSheet.svelte` | Add to Album (rows, list ≥160, added toast) | 300 | `sdk.getAllAlbums` + `addAssetsToAlbums` from `album.service` (cf. `AlbumPickerModal`) |
| `V2MoveSheet.svelte` | Move to… (count title, title-sorted rows, library confirm, empty state, result toast) | 320 | `computeMoveTargets` + `moveAssets`/`Type5-7` (cf. `MoveToLibraryModal`) |
| `V2NewSpaceSheet.svelte` | New Shared Library (Name + optional Description, Create disabled on blank) | 320 | `sdk.create` + `sharedSpaces.upsert` (cf. `SharedSpaceCreateModal`) |
| `V2ManageSpaceSheet.svelte` | Manage space (details + Save, member rows, add, Leave/Delete, Done) | 360 | `sdk.update/getMembers2/addMembers2/removeMember2/getMyUser/deleteSharedSpacesById` + `sharedSpaces` (cf. space page + `SharedSpaceMembersModal`) |
| `V2ImportChooserSheet.svelte` | Import chooser (names + overflow, Personal/space picker, queue toast, Done≈Upload+close) | 360 | `sharedSpaces` + `fileUploadHandler` (cf. `openFileUploadDialog` minus its picker) |
| `V2ConfirmSheet.svelte` | drop-confirm alert + delete/empty-trash confirms | 320 | caller-owned; trash callers use `sdk.emptyTrash/restoreTrash` (cf. `trash.service`) |

## Contract notes

- **Button order:** Cancel first, primary action last; destructive confirms
  render Cancel (autofocused) + red destructive action.
- **Validation:** blank names disable the primary; the inline red-caption error
  (`name_required`) appears after a submit attempt, never on pristine fields.
- **Role gating:** owner = edit/add/remove-others/Delete; contributor =
  edit/add/remove-others/Leave; non-members get no management controls.
  Self rows never offer Remove (Leave owns that flow). Space roles are
  read-only — the server exposes no role-update endpoint (only ownership
  transfer, which WP1 §6 does not place in this sheet).
- **Cancel/Escape/overlay:** no side effects. Overlay clicks never dismiss;
  Cancel and Escape close without mutating. Focus returns to the opener.
- **Minimal refresh:** `sharedSpaces.upsert/remove/refresh` per mutation;
  album flows emit the standard `AlbumCreate` event; move/add callers receive
  ids via `onMoved`/`onAdded` and own their timeline invalidation.
- **G2 upload-then-move (verified):** `AssetMediaCreateDto` carries `spaceId`
  but no `libraryId`, so the chooser offers Personal + spaces directly.
  External-library arrivals go upload-then-move through `V2MoveSheet`. No
  `libraryId` upload parameter was invented.

## Locale gaps (lead-owned, out of dialogs/** scope)

No locale keys exist for: the import queue toast (WP1-verbatim English
literal in `V2ImportChooserSheet`), the `Destination` label, and the
upload-then-move hint. Everything else reuses keys already consumed by
classic code.

## Specs

`sheet-logic.spec.ts` (23 tests): geometry constants, name validation,
owner/contributor/non-member gating, self-removal exclusion, move-result
tally + WP1 toast strings, import preview/overflow, title sorting, and
focus-restore capture/restore/no-op/detached-element behavior.
