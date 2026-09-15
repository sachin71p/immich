# S2 e2e fix — album access-control parity restore

## Root cause
S2 (f34f92116) intentionally dropped the Editor-only restriction on album
asset paths, contradicting 5 upstream specs in
`e2e/src/specs/server/api/album.e2e-spec.ts`. Failure (3) (`:654`
not_found) is a cascade of (2): fixtures are built once in `beforeAll`,
so (2)'s wrongful delete of `user1Asset1` from `user1Albums[0]` starves (3).

## Files changed
- `server/src/utils/access.ts`: `AlbumAssetCreate`/`AlbumAssetDelete`
  shared-album role back to `Editor` (fixes `:549`, `:673`).
- `server/src/services/album.service.ts`: `removeAssets`
  `canAlwaysRemove` back to `AlbumDelete` (fixes `:638` + cascade `:654`);
  `updateUser` runs `AlbumShare` check before fork role guards (fixes `:788`).
- `server/src/services/album.service.spec.ts`: viewer-remove test now
  asserts `NO_PERMISSION` (upstream parity).

## Self-check (in-sandbox)
- `tsc --noEmit`: clean. `eslint` on 3 touched files: clean.
- `vitest` album/access/asset specs: 144 passed.
- e2e: NOT RUN (needs Docker).

## Host verification needed
Run upstream album e2e on host: the 5 specs at `:549 :638 :654
:673 :788` plus full `album.e2e-spec.ts` for regressions.
