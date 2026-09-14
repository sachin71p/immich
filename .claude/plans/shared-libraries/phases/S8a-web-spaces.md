# S8a — Web: shared libraries management, settings, admin library members

Depends on: S6, S7 (SDK regenerated) · Reads: DECISIONS §4, §9 · CODEMAP §H · handoffs S4, S5.

## Goal
Users can create/manage shared libraries and members, set default upload target and timeline sources; admins
manage external-library members and uploadPath.

## Tasks
1. Sidebar (`Sidebar.svelte`): "Shared libraries" group listing my spaces (+ "New shared library"), below Albums/Sharing.
2. Routes: `web/src/routes/(user)/shared-libraries/+page.svelte` (grid of spaces: cover, name, member avatars, count,
   role badge; create button) and `…/shared-libraries/[spaceId=id]/[[photos=photos]]/+page.svelte`: header (name,
   description inline edit, members, "Show in my timeline" toggle, menu: rename, add members, leave (contributor),
   transfer ownership / delete (owner) with confirm dialogs stating §8 consequences), and a timeline scoped with
   `spaceId` (reuse the album-page timeline composition pattern, options `{ spaceId }`).
3. Modals: `SharedSpaceCreateModal.svelte`, `SharedSpaceMembersModal.svelte` (copy `AlbumAddUsersModal` for the user picker).
4. User settings: new "Libraries" section (register in `UserSettingsList.svelte`): default upload target select
   (Personal + my spaces), timeline sources toggles: Personal, each space (member showInTimeline), each shared/owned
   external library (library `/me` endpoint), link to Partner settings for partners.
5. Admin library management: per-library "Members" editor (add/remove users) and "Upload path" field with server
   validation error display.
6. i18n keys in `i18n/en.json` only (other locales fall back).
7. Keep a small `web/src/lib/stores/shared-spaces` (or manager) that caches my spaces + shared libraries for other
   components (S8b uses it).

## Tests
Component tests (vitest, pattern from `SharedLinkFormFields.spec.ts`) for create modal validation and settings toggles.

## Self-check / Verify
`cd web && pnpm run check:typescript && pnpm run check:svelte && pnpm run lint && pnpm run test --run`
