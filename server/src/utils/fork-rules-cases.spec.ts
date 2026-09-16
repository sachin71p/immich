// T0 task 6 ( brief § "tasks" item 6 ): every row of e2e/fork-assets/rules-cases.json run
// against the REAL access/move/scope functions with repository answers programmed from the
// TESTING.md §3 canonical world (in-memory fakes).
//
// Boundary (see handoff/T0.md): DB-level narrowing (e.g. R6-07/RC-21 owner-access after a
// member is removed) is enforced inside repository SQL and proven by T1 host e2e. The fakes
// below transcribe DECISIONS §4/§10 as world facts; this spec pins the checkAccess branch
// table, the move/member service rules, and scope resolution — not SQL.
//
// Matrix-ID map (T1 U-layer backfill): [R2-02] add-member RC-13/RC-14 (duplicate-400 is in
// shared-space.service.spec); [R2-03] leave RC-15/RC-16, transfer RC-17/RC-18, delete-space
// RC-19/RC-20; [R6-06] carol-deny RC-03/RC-05/RC-14/RC-23; [R6-07] RC-21; [R5-02] RC-33;
// [R10-07] locked move RC-41; [R11-02] own-role-change RC-30; [R16-02] RC-26/RC-27.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { AuthDto } from 'src/dtos/auth.dto.js';
import { AlbumUserRole, AssetVisibility, Permission, UserMetadataKey } from 'src/enum.js';
import { AlbumService } from 'src/services/album.service.js';
import { AssetService } from 'src/services/asset.service.js';
import { SharedSpaceService } from 'src/services/shared-space.service.js';
import { checkAccess } from 'src/utils/access.js';
import { ContainerScopeService } from 'src/utils/container-scope.js';
import { newTestService } from 'test/utils.js';

const casesPath = join(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  '..',
  'e2e',
  'fork-assets',
  'rules-cases.json',
);
const { cases } = JSON.parse(readFileSync(casesPath, 'utf8')) as {
  cases: Array<Record<string, string>>;
};

const U = {
  admin: 'user-admin',
  alice: 'user-alice',
  bob: 'user-bob',
  carol: 'user-carol',
  dave: 'user-dave',
};
const S = { family: 'space-family', camera: 'space-camera', carolSolo: 'space-carol-solo' };
const L = { archive: 'lib-archive', nasro: 'lib-nasro' };
const TRIP = 'album-trip';
const DUP = Buffer.from('checksum-dup');

type WorldAsset = {
  id: string;
  ownerId: string;
  spaceId: string | null;
  libraryId: string | null;
  visibility: AssetVisibility;
  checksum: Buffer;
  stackId?: string;
  livePhotoVideoId?: string | null;
};

type World = ReturnType<typeof makeWorld>;

const roleRank = (role?: string) => ({ viewer: 0, contributor: 1, editor: 1, owner: 2 })[role ?? ''] ?? -1;
const subset = (ids: Set<string> | string[], keep: (id: string) => boolean) =>
  new Set([...ids].filter((id) => keep(id)));

// TESTING.md §3 canonical world, fresh per row so move mutations stay independent.
function makeWorld(opts?: { removeBobFromFamily?: boolean; hideCameraFromBob?: boolean }) {
  const hideCameraFromBob = opts?.hideCameraFromBob ?? false;
  const spaces: Record<string, { members: Record<string, string>; showInTimeline: Record<string, boolean> }> = {
    [S.family]: {
      members: opts?.removeBobFromFamily ? { [U.alice]: 'owner' } : { [U.alice]: 'owner', [U.bob]: 'contributor' },
      showInTimeline: { [U.alice]: true, [U.bob]: true },
    },
    [S.camera]: {
      members: { [U.bob]: 'owner', [U.alice]: 'contributor' },
      // RC-46 variant: camera hidden from bob's timeline; visible by default (RC-45/47).
      showInTimeline: { [U.bob]: !hideCameraFromBob, [U.alice]: true },
    },
    [S.carolSolo]: { members: { [U.carol]: 'owner' }, showInTimeline: { [U.carol]: true } },
  };
  const libraries: Record<string, { ownerId: string; members: string[]; uploadPath: string | null }> = {
    [L.archive]: { ownerId: U.alice, members: [U.bob], uploadPath: '/import/archive' },
    [L.nasro]: { ownerId: U.admin, members: [U.carol], uploadPath: null },
  };
  const album = {
    id: TRIP,
    ownerId: U.alice,
    roles: { [U.bob]: 'viewer' } as Record<string, string>,
    assetIds: ['asset-alice-personal', 'asset-fam-alice'],
  };
  const assets: Record<string, WorldAsset> = {
    'asset-alice-personal': {
      id: 'asset-alice-personal',
      ownerId: U.alice,
      spaceId: null,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: Buffer.from('c-alice-personal'),
    },
    'asset-alice-locked': {
      id: 'asset-alice-locked',
      ownerId: U.alice,
      spaceId: null,
      libraryId: null,
      visibility: AssetVisibility.Locked,
      checksum: Buffer.from('c-alice-locked'),
    },
    'asset-alice-dup': {
      id: 'asset-alice-dup',
      ownerId: U.alice,
      spaceId: null,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: DUP,
    },
    'asset-alice-live-still': {
      id: 'asset-alice-live-still',
      ownerId: U.alice,
      spaceId: null,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: Buffer.from('c-live-still'),
      livePhotoVideoId: 'asset-alice-live-motion',
    },
    'asset-alice-live-motion': {
      id: 'asset-alice-live-motion',
      ownerId: U.alice,
      spaceId: null,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: Buffer.from('c-live-motion'),
    },
    'asset-bob-personal': {
      id: 'asset-bob-personal',
      ownerId: U.bob,
      spaceId: null,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: Buffer.from('c-bob-personal'),
    },
    'asset-bob-stack-a': {
      id: 'asset-bob-stack-a',
      ownerId: U.bob,
      spaceId: null,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: Buffer.from('c-stack-a'),
      stackId: 'stack-1',
    },
    'asset-bob-stack-b': {
      id: 'asset-bob-stack-b',
      ownerId: U.bob,
      spaceId: null,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: Buffer.from('c-stack-b'),
      stackId: 'stack-1',
    },
    'asset-bob-family': {
      id: 'asset-bob-family',
      ownerId: U.bob,
      spaceId: S.family,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: Buffer.from('c-bob-family'),
    },
    'asset-fam-alice': {
      id: 'asset-fam-alice',
      ownerId: U.alice,
      spaceId: S.family,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: Buffer.from('c-fam-alice'),
    },
    'asset-fam-dup': {
      id: 'asset-fam-dup',
      ownerId: U.alice,
      spaceId: S.family,
      libraryId: null,
      visibility: AssetVisibility.Timeline,
      checksum: DUP,
    },
    'asset-arch-alice': {
      id: 'asset-arch-alice',
      ownerId: U.alice,
      spaceId: null,
      libraryId: L.archive,
      visibility: AssetVisibility.Timeline,
      checksum: Buffer.from('c-arch-alice'),
    },
  };
  const partners = [
    { sharedById: U.alice, sharedWithId: U.dave, sharedBy: { id: 1 }, sharedWith: { id: 2 }, inTimeline: true },
  ];
  const calls = { moveWithRelocation: [] as Array<{ ids: string[] }>, removeMember: [] as string[] };
  return { roleRank, spaces, libraries, album, assets, partners, calls };
}

const authFor = (actor: string) =>
  ({ user: { id: U[actor as keyof typeof U], isAdmin: actor === 'admin' } }) as unknown as AuthDto;

// In-memory access answers transcribing DECISIONS §4/§10 (see header boundary note).
function fakeAccess(world: World) {
  const { spaces, libraries, album, assets, roleRank } = world;
  const isSpaceMember = (userId: string, spaceId: string) => !!spaces[spaceId]?.members[userId];
  const assetById = (id: string) => assets[id];
  // DECISIONS §4 R6-07: the owner check is narrowed — the owner must also belong to the
  // asset's space (library assets keep the upstream owner rule).
  const narrowedOwner = (userId: string, asset: WorldAsset) =>
    asset.ownerId === userId && (!asset.spaceId || isSpaceMember(userId, asset.spaceId));
  const inTrip = (id: string) => album.assetIds.includes(id);
  const albumRole = (userId: string) => (userId === album.ownerId ? 'owner' : album.roles[userId]);
  return {
    asset: {
      checkOwnerAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(subset(ids, (id) => narrowedOwner(userId, assetById(id)))),
      // DECISIONS §4 R6-07 as transcribed for RC-21: album access to a SPACE asset additionally
      // requires space membership (leaving the space revokes the album view of its assets).
      checkAlbumAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(
          subset(
            ids,
            (id) =>
              inTrip(id) &&
              !!albumRole(userId) &&
              (!assetById(id).spaceId || isSpaceMember(userId, assetById(id).spaceId!)),
          ),
        ),
      checkPartnerAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(
          subset(ids, (id) => userId === U.dave && assetById(id).ownerId === U.alice && assetById(id).spaceId === null),
        ),
      checkSpaceAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(subset(ids, (id) => !!assetById(id).spaceId && isSpaceMember(userId, assetById(id).spaceId!))),
      checkLibraryMemberAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(
          subset(ids, (id) => {
            const asset = assetById(id);
            const lib = asset.libraryId ? libraries[asset.libraryId] : undefined;
            return !!lib && (lib.ownerId === userId || lib.members.includes(userId));
          }),
        ),
      checkAlbumMemberAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(subset(ids, (id) => inTrip(id) && !!albumRole(userId))),
    },
    album: {
      checkOwnerAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(subset(ids, (id) => id === TRIP && album.ownerId === userId)),
      checkSharedAlbumAccess: (userId: string, ids: Set<string>, minRole: string) =>
        Promise.resolve(
          subset(ids, (id) => id === TRIP && roleRank(albumRole(userId)) >= roleRank(minRole.toLowerCase())),
        ),
    },
    space: {
      checkMemberAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(subset(ids, (id) => isSpaceMember(userId, id))),
      checkOwnerAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(subset(ids, (id) => spaces[id]?.members[userId] === 'owner')),
    },
    library: {
      checkMemberAccess: (userId: string, ids: Set<string>) =>
        Promise.resolve(
          subset(ids, (id) => {
            const lib = libraries[id];
            return !!lib && (lib.ownerId === userId || lib.members.includes(userId));
          }),
        ),
    },
  };
}

function assetForContainer(container: string): string {
  if (container === 'space:family') {
    return 'asset-fam-alice';
  }
  if (container === 'library:archive') {
    return 'asset-arch-alice';
  }
  if (container === 'personal:alice') {
    return 'asset-alice-personal';
  }
  if (container === 'album:trip') {
    return 'asset-alice-personal';
  }
  throw new Error(`no representative asset for ${container}`);
}

function permissionForAction(action: string, row: Record<string, string>): { permission: Permission; ids: string[] } {
  const source = row.source ?? row.container;
  switch (action) {
    case 'read': {
      return { permission: Permission.AssetRead, ids: [assetForContainer(source)] };
    }
    case 'upload': {
      // Upload targets are gated by space membership (asset-media upload flow).
      const spaceId = source === 'space:family' ? S.family : source === 'space:camera' ? S.camera : S.carolSolo;
      return { permission: Permission.SharedSpaceRead, ids: [spaceId] };
    }
    case 'edit-metadata':
    case 'archive':
    case 'mixed-update': {
      return { permission: Permission.AssetUpdate, ids: [assetForContainer(source)] };
    }
    case 'favorite':
    case 'favorite-only': {
      return { permission: Permission.AssetFavorite, ids: [assetForContainer(source)] };
    }
    case 'trash':
    case 'delete': {
      return { permission: Permission.AssetDelete, ids: [assetForContainer(source)] };
    }
    case 'album-add': {
      return { permission: Permission.AlbumAssetCreate, ids: [TRIP] };
    }
    case 'album-remove': {
      return { permission: Permission.AlbumAssetDelete, ids: [TRIP] };
    }
    case 'rename-space': {
      return { permission: Permission.SharedSpaceUpdate, ids: [S.family] };
    }
    case 'add-member': {
      return source.startsWith('library:')
        ? { permission: Permission.LibraryMemberCreate, ids: [L.archive] }
        : { permission: Permission.SharedSpaceMemberCreate, ids: [S.family] };
    }
    case 'delete-space': {
      return { permission: Permission.SharedSpaceDelete, ids: [S.family] };
    }
    default: {
      throw new Error(`no permission mapping for ${action}`);
    }
  }
}

function sourceAssetForMove(source: string): string {
  switch (source) {
    case 'personal:alice': {
      return 'asset-alice-personal';
    }
    case 'personal:alice:locked': {
      return 'asset-alice-locked';
    }
    case 'personal:alice:dup': {
      return 'asset-alice-dup';
    }
    case 'personal:alice:live-still': {
      return 'asset-alice-live-still';
    }
    case 'personal:bob:stack-member': {
      return 'asset-bob-stack-a';
    }
    case 'space:family':
    case 'space:family:alice': {
      return 'asset-fam-alice';
    }
    case 'space:family:bob': {
      return 'asset-bob-family';
    }
    case 'library:archive': {
      return 'asset-arch-alice';
    }
    default: {
      throw new Error(`no move source for ${source}`);
    }
  }
}

function targetForMove(target: string) {
  if (target === 'personal' || target.startsWith('personal:')) {
    return { type: 'personal' } as const;
  }
  const [kind, id] = target.split(':', 2);
  if (kind === 'space') {
    return { type: 'space', id: id === 'family' ? S.family : id === 'camera' ? S.camera : S.carolSolo } as const;
  }
  return { type: 'library', id: id === 'archive' ? L.archive : L.nasro } as const;
}

// AssetService.move with container mutations applied to a fresh world per row. The
// uniqueness simulation mirrors the real partial unique index
// (ownerId, checksum) WHERE "libraryId" IS NULL plus (ownerId, libraryId, checksum).
function moveFakes(world: World) {
  return {
    getByIds: (ids: string[]) => Promise.resolve(ids.map((id) => ({ ...world.assets[id] }))),
    getMoveGroup: ([id]: string[]) => {
      const asset = world.assets[id];
      if (asset.stackId) {
        return Promise.resolve(Object.values(world.assets).filter((candidate) => candidate.stackId === asset.stackId));
      }
      if (asset.livePhotoVideoId) {
        return Promise.resolve([asset, world.assets[asset.livePhotoVideoId]].filter(Boolean));
      }
      return Promise.resolve([asset]);
    },
    // Mirrors AssetRepository.getByChecksumInContainer (B3): personal targets stay
    // owner-scoped; spaces and external libraries span owners. The move group is
    // excluded so live pairs and stacks never self-collide.
    getByChecksumInContainer: ({
      ownerId,
      checksum,
      spaceId,
      libraryId,
      excludeIds,
    }: {
      ownerId?: string;
      checksum: Buffer;
      spaceId?: string | null;
      libraryId?: string | null;
      excludeIds?: string[];
    }) =>
      Promise.resolve(
        Object.values(world.assets).find(
          (candidate) =>
            candidate.checksum.equals(checksum) &&
            (!ownerId || candidate.ownerId === ownerId) &&
            (libraryId
              ? candidate.libraryId === libraryId
              : (candidate.libraryId ?? null) === null &&
                (spaceId ? candidate.spaceId === spaceId : (candidate.spaceId ?? null) === null)) &&
            !(excludeIds ?? []).includes(candidate.id),
        ),
      ),
    moveWithRelocation: (ids: string[], options: { spaceId: string | null; libraryId: string | null }) => {
      for (const id of ids) {
        const asset = world.assets[id];
        const collision = Object.values(world.assets).some(
          (candidate) =>
            candidate.id !== id &&
            candidate.ownerId === asset.ownerId &&
            candidate.checksum.equals(asset.checksum) &&
            (options.libraryId ? candidate.libraryId === options.libraryId : candidate.libraryId === null),
        );
        if (collision) {
          throw new Error('duplicate key value violates unique checksum constraint');
        }
        asset.spaceId = options.spaceId;
        asset.libraryId = options.libraryId;
      }
      world.calls.moveWithRelocation.push({ ids });
      return Promise.resolve();
    },
  };
}

function memberFakes(world: World) {
  return {
    getMembers: (spaceId: string) =>
      Promise.resolve(
        Object.entries(world.spaces[spaceId]?.members ?? {}).map(([userId, role]) => ({
          userId,
          role,
          showInTimeline: true,
          createdAt: new Date(0),
        })),
      ),
    isMember: (spaceId: string, userId: string) => Promise.resolve(!!world.spaces[spaceId]?.members[userId]),
    removeMember: (spaceId: string, userId: string) => {
      world.calls.removeMember.push(`${spaceId}:${userId}`);
      return Promise.resolve();
    },
    transferOwner: () => Promise.resolve(),
  };
}

function scopeFakes(world: World, prefs?: Record<string, unknown>) {
  return {
    userRepository: {
      getMetadata: () => Promise.resolve(prefs ? [{ key: UserMetadataKey.Preferences, value: prefs }] : []),
    },
    partnerRepository: {
      getAll: (userId: string) =>
        Promise.resolve(
          world.partners.filter((partner) => partner.sharedWithId === userId || partner.sharedById === userId),
        ),
    },
    sharedSpaceRepository: {
      getAll: (userId: string) =>
        Promise.resolve(
          Object.entries(world.spaces)
            .filter(([, space]) => space.members[userId])
            .map(([id, space]) => ({ id, showInTimeline: space.showInTimeline[userId] ?? true })),
        ),
      isMember: (spaceId: string, userId: string) => Promise.resolve(!!world.spaces[spaceId]?.members[userId]),
    },
    libraryRepository: {
      getShared: (userId: string) =>
        Promise.resolve(
          Object.entries(world.libraries)
            .filter(([, lib]) => lib.ownerId === userId || lib.members.includes(userId))
            .map(([id, lib]) => ({ id, ownerId: lib.ownerId, showInTimeline: true })),
        ),
    },
  };
}

describe.each(cases)('rules-cases.json [$id]', (row) => {
  // Permission rows name the container `container`; move rows use `source`/`target`.
  const where = row.source ?? row.container;
  it(`[${row.id}] ${row.action} by ${row.actor} on ${where} → ${row.expected}`, async () => {
    const world = makeWorld(
      row.id === 'RC-21' ? { removeBobFromFamily: true } : row.id === 'RC-46' ? { hideCameraFromBob: true } : undefined,
    );
    const auth = authFor(row.actor);
    const access = fakeAccess(world) as never;

    switch (row.action) {
      case 'leave': {
        // SharedSpaceService has a custom constructor — build it directly with the fakes.
        const sut = new SharedSpaceService(access as never, memberFakes(world) as never, {} as never);
        if (row.expected === 'allow') {
          await sut.removeMember(auth, S.family, U[row.actor as keyof typeof U]);
          expect(world.calls.removeMember).toEqual([`${S.family}:${U[row.actor as keyof typeof U]}`]);
        } else {
          await expect(sut.removeMember(auth, S.family, U[row.actor as keyof typeof U])).rejects.toThrow();
        }
        return;
      }
      case 'transfer': {
        const sut = new SharedSpaceService(access as never, memberFakes(world) as never, {} as never);
        if (row.expected === 'allow') {
          await sut.transferOwner(auth, S.family, { userId: U.bob } as never);
        } else {
          await expect(sut.transferOwner(auth, S.family, { userId: U.bob } as never)).rejects.toThrow();
        }
        return;
      }
      case 'own-role-change': {
        // A viewer self-change is denied at the AlbumShare gate, which runs before the
        // own-role guard (upstream :788 pins the share message for this shape).
        const { sut } = newTestService(AlbumService);
        await expect(
          sut.updateUser(auth, TRIP, U[row.actor as keyof typeof U], { role: AlbumUserRole.Editor } as never),
        ).rejects.toThrow('Not found or no album.share access');
        return;
      }
      case 'move': {
        const { sut } = newTestService(AssetService, {
          asset: moveFakes(world),
          access,
          library: { get: (id: string) => Promise.resolve(world.libraries[id]) },
        } as never);
        const result = await sut.move(auth, {
          assetIds: [sourceAssetForMove(row.source)],
          target: targetForMove(row.target),
        } as never);
        const [outcome] = result.results;
        if (row.expected === 'moved' || row.expected === 'noop') {
          expect(outcome.status).toBe(row.expected);
        } else {
          expect(outcome.status).toBe('error');
          if (row.targetError === 'duplicate' || row.targetError === 'locked') {
            expect(outcome).toMatchObject({ reason: row.targetError });
          }
        }
        return;
      }
      default: {
        if (row.action.startsWith('scope-')) {
          const fakes = scopeFakes(
            world,
            row.id === 'RC-47' ? { sharedLibraries: { showPersonalInTimeline: false } } : undefined,
          );
          const service = new ContainerScopeService(
            fakes.userRepository as never,
            fakes.partnerRepository as never,
            fakes.sharedSpaceRepository as never,
            fakes.libraryRepository as never,
          );
          if (row.id === 'RC-48') {
            await expect(
              service.resolve(auth, { purpose: 'timeline', filter: { spaceId: S.family, libraryId: L.archive } }),
            ).rejects.toThrow();
            return;
          }
          const scope = await service.resolve(auth, {
            purpose: row.id === 'RC-50' ? 'locked' : 'timeline',
            withPartners: true,
          });
          switch (row.id) {
            case 'RC-45': {
              expect(scope).toEqual({
                personalUserIds: [U.bob],
                spaceIds: [S.family, S.camera],
                libraryIds: [L.archive],
              });

              break;
            }
            case 'RC-46': {
              expect(scope.spaceIds).toEqual([S.family]);

              break;
            }
            case 'RC-47': {
              expect(scope.personalUserIds).toEqual([]);
              expect(scope.spaceIds).toEqual([S.family, S.camera]);

              break;
            }
            case 'RC-49': {
              expect(scope.personalUserIds).toContain(U.alice);
              expect(scope.spaceIds).toEqual([]);
              expect(scope.libraryIds).toEqual([]);

              break;
            }
            case 'RC-50': {
              expect(scope).toEqual({ personalUserIds: [U.alice], spaceIds: [], libraryIds: [] });

              break;
            }
            // No default
          }
          return;
        }
        const { permission, ids } = permissionForAction(row.action, row);
        const allowed = await checkAccess(access, {
          auth,
          permission,
          ids: new Set(ids),
        } as never);
        if (row.expected === 'allow') {
          expect([...allowed].sort()).toEqual([...ids].sort());
        } else {
          expect(allowed.size).toBe(0);
        }
      }
    }
  });
});
