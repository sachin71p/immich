// Fork world builder (shared-libraries, T0). See TESTING.md §3.
//
// buildWorld() seeds a deterministic multi-user world after resetting the
// database (upstream tables + fork tables — utils.resetDatabase does not know
// the fork tables, so the full list is passed explicitly without editing
// utils.ts). Idempotent: call once per spec file after resetDatabase().

import {
  AlbumUserRole,
  AssetVisibility,
  Type4,
  addAssetsToAlbum,
  addMembers as addLibraryMembers,
  addMembers2 as addSpaceMembers,
  create as createSharedSpace,
  createLibrary,
  login,
  setupPinCode,
  unlockAuthSession,
  updateAssets,
  updateConfig,
  updatePartner,
  type AssetResponseDto,
  type LoginResponseDto,
  type SharedSpaceResponseDto,
} from '@immich/sdk';
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { join, parse } from 'node:path';
import { testAssetDir, testAssetDirInternal, utils } from 'src/utils.js';
import { settle } from './jobs.js';

export const forkAssetDir = join(testAssetDir, '..', 'fork-assets');
export const generatedDir = join(forkAssetDir, 'generated');
export const personalDir = join(forkAssetDir, 'personal');
const forkDataDir = join(testAssetDir, '..', '.fork-data');

export interface WorldUser {
  login: LoginResponseDto;
  email: string;
}

export interface WorldAsset {
  id: string;
  manifestId: string;
  owner: string;
}

export interface World {
  users: Record<'admin' | 'alice' | 'bob' | 'carol' | 'dave', WorldUser>;
  spaces: Record<'family' | 'camera' | 'carolSolo', SharedSpaceResponseDto>;
  libraries: { archive: { id: string }; nasro: { id: string } };
  albumTrip: { id: string };
  assets: WorldAsset[];
  template: 'on' | 'off';
}

// PIN for alice's audit elevation (4-6 digits per the API contract) and the
// unlock TTL guard: server unlocks last 15 minutes, so audit sessions refresh
// well before that.
const worldPin = '123456';
const auditSessionTtlMs = 10 * 60_000;
const auditSessions = new Map<World, { accessToken: string; unlockedAt: number }>();

/**
 * Read token for the R17 placement audits. Locked assets (fork-10) are
 * unreadable without an elevated session, so alice reads through a dedicated
 * PIN-unlocked session that is re-created once the unlock window nears
 * expiry; everyone else reads through their login token and the interactive
 * sessions stay non-elevated.
 */
export const auditToken = async (world: World, owner: string): Promise<string> => {
  const user = (world.users as Record<string, WorldUser>)[owner];
  if (!user) {
    throw new Error(`unknown world owner ${owner}`);
  }
  if (owner !== 'alice') {
    return user.login.accessToken;
  }
  const cached = auditSessions.get(world);
  if (cached && Date.now() - cached.unlockedAt < auditSessionTtlMs) {
    return cached.accessToken;
  }
  const fresh = await login({ loginCredentialDto: { email: user.email, password: 'Password123' } });
  await unlockAuthSession({ sessionUnlockDto: { pinCode: worldPin } }, { headers: asBearerAuth(fresh.accessToken) });
  auditSessions.set(world, { accessToken: fresh.accessToken, unlockedAt: Date.now() });
  return fresh.accessToken;
};

const forkTables = [
  'shared_space',
  'shared_space_member',
  'shared_space_audit',
  'shared_space_member_audit',
  'shared_space_asset_audit',
  'library_member',
  'library_member_audit',
  'asset_relocation',
  'move_history',
];

const upstreamTables = [
  'stack',
  'library',
  'shared_link',
  'person',
  'person_group',
  'cluster_group',
  'album',
  'asset',
  'asset_face',
  'activity',
  'api_key',
  'session',
  'user',
  'system_metadata',
  'tag',
  'integrity_report',
];

export const resetForkDatabase = () => utils.resetDatabase([...upstreamTables, ...forkTables]);

const asBearerAuth = (accessToken: string) => ({ Authorization: `Bearer ${accessToken}` });

export const setStorageTemplate = async (adminToken: string, enabled: boolean): Promise<void> => {
  const config = await utils.getSystemConfig(adminToken);
  (config as { storageTemplate: { enabled: boolean } }).storageTemplate.enabled = enabled;
  await updateConfig({ adminConfigDto: config }, { headers: asBearerAuth(adminToken) });
};

const manifestFile = (manifestId: string): string => {
  const manifest = JSON.parse(readFileSync(join(forkAssetDir, 'manifest.json'), 'utf8')) as {
    generated: { id: string; file: string }[];
  };
  const entry = manifest.generated.find((e) => e.id === manifestId);
  if (!entry) {
    throw new Error(`unknown fixture ${manifestId}`);
  }
  return entry.file;
};

export const requireAssetId = (asset: { id?: string; statusCode?: number }, label: string): string => {
  if (!asset?.id) {
    // fork: surface Nest's statusCode as .status so denial assertions (e.g. R3-02's 403)
    // can match it; the message alone cannot distinguish 400/403/500.
    const error = new Error(`upload failed for ${label}: ${JSON.stringify(asset)}`) as Error & { status?: number };
    if (typeof asset?.statusCode === 'number') {
      error.status = asset.statusCode;
    }
    throw error;
  }
  return asset.id;
};

export const uploadFixture = async (token: string, manifestId: string, extra?: { spaceId?: string }) => {
  const file = manifestFile(manifestId);
  const bytes = readFileSync(join(generatedDir, file));
  // Fixtures with a `<file>.xmp` next to them (fork-06/07/08/10) must upload
  // it as sidecarData, otherwise the server never writes `<original>.xmp`
  // and the disk oracle's sidecar assertion cannot pass.
  const sidecarFile = join(generatedDir, `${file}.xmp`);
  const sidecarData = existsSync(sidecarFile)
    ? { bytes: readFileSync(sidecarFile), filename: `${file}.xmp` }
    : undefined;
  const asset = await utils.createAsset(token, {
    assetData: { bytes, filename: file },
    ...(sidecarData && { sidecarData }),
    ...extra,
  });
  requireAssetId(asset, `fixture ${manifestId}`);
  return asset;
};

export interface BuildWorldOptions {
  storageTemplate: 'on' | 'off';
}

export const buildWorld = async ({ storageTemplate }: BuildWorldOptions): Promise<World> => {
  // The regular e2e database reset only cleans the upstream /data mount. The
  // fork stack uses /fork-data, so stale files from an earlier world otherwise
  // survive and make StorageCore treat a checksum-mismatched destination as an
  // interrupted move. Reset both fork-owned media roots before seeding.
  mkdirSync(forkDataDir, { recursive: true });
  // Keep the bind-mount root itself alive. Replacing it while Docker has it
  // mounted can leave the server attached to the old host inode.
  for (const entry of ['library', 'upload', 'thumbs', 'encoded-video', 'profile', 'backups']) {
    rmSync(join(forkDataDir, entry), { recursive: true, force: true });
  }
  utils.resetTempFolder();
  await resetForkDatabase();
  const admin = await utils.adminSetup();
  await utils.resetAdminConfig(admin.accessToken);
  await setStorageTemplate(admin.accessToken, storageTemplate === 'on');

  const signup = async (email: string, name: string): Promise<WorldUser> => {
    const login = await utils.userSetup(admin.accessToken, { email, password: 'Password123', name });
    return { login, email };
  };

  const alice = await signup('alice@test.com', 'alice');
  const bob = await signup('bob@test.com', 'bob');
  const carol = await signup('carol@test.com', 'carol');
  const dave = await signup('dave@test.com', 'dave');
  // dave is alice's partner with timeline access (upstream partner flow).
  // New partnerships default inTimeline=false, so dave opts in the way the
  // app does; without this his partner buckets are empty (R8-05 saw 0).
  await utils.createPartner(alice.login.accessToken, dave.login.userId);
  await updatePartner(
    { id: alice.login.userId, partnerUpdateDto: { inTimeline: true } },
    { headers: asBearerAuth(dave.login.accessToken) },
  );

  // Spaces: Family Mobile (alice owner, bob contributor), Camera
  // (bob owner, alice contributor), Carol Solo (carol owner).
  const family = await createSharedSpace({ sharedSpaceCreateDto: { name: 'Family Mobile' } }, { headers: { Authorization: `Bearer ${alice.login.accessToken}` } });
  await addSpaceMembers(
    { id: family.id, sharedSpaceMembersDto: { userIds: [bob.login.userId] } },
    { headers: { Authorization: `Bearer ${alice.login.accessToken}` } },
  );
  const camera = await createSharedSpace({ sharedSpaceCreateDto: { name: 'Camera' } }, { headers: { Authorization: `Bearer ${bob.login.accessToken}` } });
  await addSpaceMembers(
    { id: camera.id, sharedSpaceMembersDto: { userIds: [alice.login.userId] } },
    { headers: { Authorization: `Bearer ${bob.login.accessToken}` } },
  );
  const carolSolo = await createSharedSpace({ sharedSpaceCreateDto: { name: 'Carol Solo' } }, { headers: { Authorization: `Bearer ${carol.login.accessToken}` } });

  // External libraries under /test-assets/temp/fork/... (host e2e/test-assets/temp/fork/...).
  const archiveImport = `${testAssetDirInternal}/temp/fork/archive`;
  mkdirSync(join(testAssetDir, 'temp', 'fork', 'archive', 'incoming'), { recursive: true });
  const archive = await createLibrary(
    { createLibraryDto: { ownerId: alice.login.userId, importPaths: [archiveImport] } },
    { headers: { Authorization: `Bearer ${admin.accessToken}` } },
  );
  await utils.updateLibrary(admin.accessToken, archive.id, { uploadPath: `${archiveImport}/incoming` });
  await addLibraryMembers(
    { id: archive.id, libraryMembersDto: { userIds: [bob.login.userId] } },
    { headers: { Authorization: `Bearer ${admin.accessToken}` } },
  );
  const nasImport = `${testAssetDirInternal}/temp/fork/nasro`;
  mkdirSync(join(testAssetDir, 'temp', 'fork', 'nasro'), { recursive: true });
  const nasro = await createLibrary(
    { createLibraryDto: { ownerId: admin.userId, importPaths: [nasImport] } },
    { headers: { Authorization: `Bearer ${admin.accessToken}` } },
  );

  // Seed the Archive import path on the host, then scan.
  cpSync(join(generatedDir, manifestFile('fork-11')), join(testAssetDir, 'temp', 'fork', 'archive', 'fork-11.jpg'));
  cpSync(join(generatedDir, manifestFile('fork-12')), join(testAssetDir, 'temp', 'fork', 'archive', 'fork-12.jpg'));
  cpSync(join(generatedDir, manifestFile('fork-13')), join(testAssetDir, 'temp', 'fork', 'archive', 'fork-13.webp'));
  await utils.scan(admin.accessToken, archive.id, 120_000);
  cpSync(join(generatedDir, manifestFile('fork-14')), join(testAssetDir, 'temp', 'fork', 'nasro', 'fork-14.png'));
  await utils.scan(admin.accessToken, nasro.id, 120_000);

  const assets: WorldAsset[] = [];
  const track = (id: string, manifestId: string, owner: string) => {
    assets.push({ id, manifestId, owner });
  };

  // External-library scans are not uploads: record the scanned assets so the
  // R8/R17 oracles account for every file the world owns (originals and their
  // derived thumbs). Manifest ids are scan-prefixed so `.find('fork-12')`
  // keeps resolving the space upload, not the same-named archive scan
  // (LC-01 regressed on that collision). Owners read their own library:
  // alice owns Archive, admin owns NAS-RO.
  const archived = await utils.searchAssets(alice.login.accessToken, { libraryId: archive.id });
  for (const item of archived.assets.items) {
    track(item.id, `scan-${parse(item.originalFileName).name}`, 'alice');
  }
  const nasroScanned = await utils.searchAssets(admin.accessToken, { libraryId: nasro.id });
  for (const item of nasroScanned.assets.items) {
    track(item.id, `scan-${parse(item.originalFileName).name}`, 'admin');
  }

  // Per-container assets: >=3 synthetic fixtures each, incl. a sidecar one and a GPS one.
  for (const manifestId of ['fork-01', 'fork-06', 'fork-07']) {
    const asset = await uploadFixture(alice.login.accessToken, manifestId);
    track(asset.id, manifestId, 'alice');
  }
  for (const manifestId of ['fork-02', 'fork-08', 'fork-12']) {
    const asset = await uploadFixture(alice.login.accessToken, manifestId, { spaceId: family.id });
    track(asset.id, manifestId, 'alice');
  }
  for (const manifestId of ['fork-03', 'fork-16', 'fork-19']) {
    const asset = await uploadFixture(bob.login.accessToken, manifestId, { spaceId: camera.id });
    track(asset.id, manifestId, 'bob');
  }
  for (const manifestId of ['fork-04', 'fork-17', 'fork-27']) {
    const asset = await uploadFixture(carol.login.accessToken, manifestId, { spaceId: carolSolo.id });
    track(asset.id, manifestId, 'carol');
  }
  for (const manifestId of ['fork-15', 'fork-23', 'fork-24']) {
    const asset = await uploadFixture(bob.login.accessToken, manifestId);
    track(asset.id, manifestId, 'bob');
  }

  // Live-photo pair in alice personal: personal files when present,
  // otherwise the upstream Pixel motion photo as stand-in.
  const liveStill = join(personalDir, 'live.heic');
  const liveMotion = join(personalDir, 'live.mov');
  if (existsSync(liveStill) && existsSync(liveMotion)) {
    const video = await utils.createAsset(alice.login.accessToken, {
      assetData: { bytes: readFileSync(liveMotion), filename: 'live.mov' },
    });
    requireAssetId(video, 'personal live.mov');
    const still = await utils.createAsset(alice.login.accessToken, {
      assetData: { bytes: readFileSync(liveStill), filename: 'live.heic' },
      livePhotoVideoId: video.id,
    });
    requireAssetId(still, 'personal live.heic');
    track(still.id, 'personal-live', 'alice');
  } else {
    const bytes = readFileSync(join(testAssetDir, 'formats', 'motionphoto', 'pixel-8a.jpg'));
    const motion = await utils.createAsset(alice.login.accessToken, {
      assetData: { bytes, filename: 'pixel-8a.jpg' },
    });
    requireAssetId(motion, 'upstream pixel-8a.jpg');
    track(motion.id, 'up-motion-jpg', 'alice');
  }

  // 2-asset stack in bob personal.
  const stackA = await uploadFixture(bob.login.accessToken, 'fork-20');
  const stackB = await uploadFixture(bob.login.accessToken, 'fork-21');
  await utils.createStack(bob.login.accessToken, [stackA.id, stackB.id]);
  track(stackA.id, 'fork-20', 'bob');
  track(stackB.id, 'fork-21', 'bob');

  // Locked asset in alice personal.
  const locked = await uploadFixture(alice.login.accessToken, 'fork-10');
  await updateAssets(
    { assetBulkUpdateDto: { ids: [locked.id], visibility: AssetVisibility.Locked } },
    { headers: asBearerAuth(alice.login.accessToken) },
  );
  track(locked.id, 'fork-10', 'alice');

  // Duplicate pair split between bob personal and Camera. dupB must be a DISTINCT
  // asset with identical bytes (R10-06's duplicate premise, R8's counts): same-owner
  // same-checksum uploads collapse into the existing asset at upload time, so alice
  // (a Camera member) contributes it instead.
  const dupA = await uploadFixture(bob.login.accessToken, 'fork-09a');
  track(dupA.id, 'fork-09a', 'bob');
  const dupB = await uploadFixture(alice.login.accessToken, 'fork-09b', { spaceId: camera.id });
  track(dupB.id, 'fork-09b', 'alice');

  // Album Trip (alice owner, bob viewer) with alice-personal + Family Mobile assets.
  // updateAlbumUser only re-roles existing members (server no-ops for non-members),
  // so bob must join at creation for the R11/R16 viewer-membership tests to hold.
  const trip = await utils.createAlbum(alice.login.accessToken, {
    albumName: 'Trip',
    albumUsers: [{ userId: bob.login.userId, role: AlbumUserRole.Viewer }],
  });
  const tripAssets = assets.filter((a) => ['fork-01', 'fork-02'].includes(a.manifestId)).map((a) => a.id);
  await addAssetsToAlbum(
    { id: trip.id, bulkIdsDto: { ids: tripAssets } },
    { headers: { Authorization: `Bearer ${alice.login.accessToken}` } },
  );

  // Preferences: bob uploads to Family Mobile by default; alice stays personal.
  await utils.updateMyPreferences(bob.login.accessToken, {
    sharedLibraries: { defaultUploadTarget: { type: Type4.Space, spaceId: family.id } },
  });

  await settle(admin.accessToken);

  // fork-10 is Locked: even the owner cannot read it without an elevated
  // session, which the R17 placement audits need for its original/sidecar
  // paths. Set the PIN here (credential only, no elevation side effect);
  // auditToken() elevates a dedicated alice session lazily so a slow file
  // never outruns the 15-minute server unlock window. Interactive sessions
  // stay non-elevated so timeline-visibility tests keep observing locked
  // assets as hidden.
  await setupPinCode({ pinCodeSetupDto: { pinCode: worldPin } }, { headers: asBearerAuth(alice.login.accessToken) });

  return {
    users: { admin: { login: admin, email: 'admin@test.com' }, alice, bob, carol, dave },
    spaces: { family, camera, carolSolo },
    libraries: { archive: { id: archive.id }, nasro: { id: nasro.id } },
    albumTrip: { id: trip.id },
    assets,
    template: storageTemplate,
  };
};

export const getAsset = (token: string, id: string): Promise<AssetResponseDto> => utils.getAssetInfo(token, id);
