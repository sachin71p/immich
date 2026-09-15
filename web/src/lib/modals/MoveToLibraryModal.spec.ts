import { Status } from '@immich/sdk';
import { fireEvent } from '@testing-library/svelte';
import { authManager } from '$lib/managers/auth-manager.svelte';
import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
import { renderWithTooltips } from '$tests/helpers';
import { preferencesFactory } from '@test-data/factories/preferences-factory';
import { userAdminFactory } from '@test-data/factories/user-factory';
import MoveToLibraryModal from './MoveToLibraryModal.svelte';

const { moveAssetsMock } = vi.hoisted(() => ({ moveAssetsMock: vi.fn() }));

vi.mock('@immich/sdk', async () => {
  const sdk = await vi.importActual<typeof import('@immich/sdk')>('@immich/sdk');
  return {
    ...sdk,
    moveAssets: moveAssetsMock,
  };
});

describe('MoveToLibraryModal component', () => {
  const userId = 'me';

  beforeEach(() => {
    authManager.setUser(userAdminFactory.build({ id: userId }));
    authManager.setPreferences(preferencesFactory.build());
    sharedSpaces.spaces = [];
    sharedSpaces.libraries = [];
    moveAssetsMock.mockReset();
  });

  afterEach(() => {
    authManager.reset();
    sharedSpaces.spaces = [];
    sharedSpaces.libraries = [];
  });

  it('lists personal, space and library destinations for an owned asset', () => {
    sharedSpaces.spaces = [
      {
        id: 'space-1',
        name: 'Family',
        description: '',
        assetCount: 0,
        memberCount: 1,
        role: 'owner',
        showInTimeline: true,
        thumbnailAssetId: null,
        createdAt: '',
        updatedAt: '',
      } as never,
    ];
    sharedSpaces.libraries = [
      {
        id: 'library-1',
        name: 'Archive',
        hasUploadPath: true,
        isOwner: true,
        ownerId: userId,
        assetCount: 0,
        showInTimeline: true,
      },
    ];

    const { getByText } = renderWithTooltips(MoveToLibraryModal, {
      assetIds: ['asset-1'],
      assetOwnerIds: [userId],
      onClose: vi.fn(),
    });

    expect(getByText('move_to_personal')).toBeInTheDocument();
    expect(getByText('Family')).toBeInTheDocument();
    expect(getByText('Archive')).toBeInTheDocument();
  });

  it('excludes personal and libraries without an upload path for a not-fully-owned selection', () => {
    sharedSpaces.spaces = [];
    sharedSpaces.libraries = [
      {
        id: 'library-1',
        name: 'Archive',
        hasUploadPath: false,
        isOwner: true,
        ownerId: 'someone-else',
        assetCount: 0,
        showInTimeline: true,
      },
    ];

    const { queryByText, getByText } = renderWithTooltips(MoveToLibraryModal, {
      assetIds: ['asset-1'],
      assetOwnerIds: ['someone-else'],
      onClose: vi.fn(),
    });

    expect(queryByText('move_to_personal')).not.toBeInTheDocument();
    expect(queryByText('Archive')).not.toBeInTheDocument();
    expect(getByText('move_target_empty')).toBeInTheDocument();
  });

  it('moves the selection and closes with the moved ids', async () => {
    moveAssetsMock.mockResolvedValue({ results: [{ id: 'asset-1', status: Status.Moved }] });
    const onClose = vi.fn();

    const { getByText } = renderWithTooltips(MoveToLibraryModal, {
      assetIds: ['asset-1'],
      assetOwnerIds: [userId],
      onClose,
    });

    await fireEvent.click(getByText('move_to_personal'));

    expect(moveAssetsMock).toHaveBeenCalledWith({
      assetMoveDto: { assetIds: ['asset-1'], target: { type: 'personal' } },
    });
    await vi.waitFor(() => expect(onClose).toHaveBeenCalledWith(['asset-1']));
  });
});
