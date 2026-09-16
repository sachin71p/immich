// V2 HeirloomViewer component spec (WP8). Mirrors the mock posture of the
// classic `AssetViewer.spec.ts`: SDK + OCR + feature-flag mocks, animate and
// resize-observer stubs. Asserts V2 contract structure (black canvas, native
// toolbar order, wrap-around paging, rotation, close) — media/infra behavior
// itself is covered by the reused classic components' own specs.
import { AssetTypeEnum, AssetVisibility } from '@immich/sdk';
import { fireEvent } from '@testing-library/svelte';
import { getAnimateMock } from '$lib/__mocks__/animate.mock';
import { getResizeObserverMock } from '$lib/__mocks__/resize-observer.mock';
import { authManager } from '$lib/managers/auth-manager.svelte';
import { renderWithTooltips } from '$tests/helpers';
import { assetFactory } from '@test-data/factories/asset-factory';
import { preferencesFactory } from '@test-data/factories/preferences-factory';
import { userAdminFactory } from '@test-data/factories/user-factory';
import HeirloomViewer from './HeirloomViewer.svelte';
import { HEIRLOOM_LIVE_TEXT_NOTE } from './viewer-variant';

vi.mock('$lib/managers/feature-flags-manager.svelte', () => ({
  featureFlagsManager: {
    init: vi.fn(),
    loadFeatureFlags: vi.fn(),
    value: { smartSearch: true, trash: true },
  } as never,
}));

vi.mock('$lib/stores/ocr.svelte', () => ({
  ocrManager: {
    clear: vi.fn(),
    getAssetOcr: vi.fn(),
    hasOcrData: false,
    showOverlay: false,
  },
}));

describe('HeirloomViewer', () => {
  beforeAll(() => {
    Element.prototype.animate = getAnimateMock();
    vi.stubGlobal('ResizeObserver', getResizeObserverMock());
  });

  afterEach(() => {
    authManager.reset();
    vi.clearAllMocks();
  });

  afterAll(() => {
    vi.restoreAllMocks();
  });

  const setup = (ids = ['a', 'b', 'c'], current = 'b', options: { authenticated?: boolean } = {}, props = {}) => {
    if (options.authenticated) {
      authManager.setUser(userAdminFactory.build({ id: 'owner-id' }));
      authManager.setPreferences(preferencesFactory.build());
    }
    // Pin still images: the video/live-photo branches need media-chrome custom
    // elements, which happy-dom cannot construct (covered by reuse, not here).
    const assets = ids.map((id, index) =>
      assetFactory.build({
        id,
        ownerId: 'owner-id',
        type: AssetTypeEnum.Image,
        livePhotoVideoId: null,
        isFavorite: false,
        isTrashed: false,
        visibility: AssetVisibility.Timeline,
        hasMetadata: true,
        originalFileName: `photo-${index}.jpg`,
        originalPath: `/photos/photo-${index}.jpg`,
      }),
    );
    const onNavigate = vi.fn();
    const onClose = vi.fn();
    const rendered = renderWithTooltips(HeirloomViewer, {
      assetId: current,
      assets,
      onNavigate,
      onClose,
      ...props,
    });
    return { ...rendered, assets, onNavigate, onClose };
  };

  it('renders the black canvas variant root', () => {
    const { getByTestId } = setup();
    const root = getByTestId('heirloom-viewer');
    expect(root).toBeInTheDocument();
    expect(root.classList.contains('bg-black')).toBe(true);
    expect(getByTestId('heirloom-viewer-canvas')).toBeInTheDocument();
  });

  it('orders toolbar controls natively (favorite, rotate, delete, move, add-to-album, edit, info)', () => {
    // Test env renders raw i18n keys (`to_favorite`, `delete`, …); the rotate
    // and live-text labels are plain literals (no locale keys exist for them).
    const { getByTestId } = setup(['a', 'b', 'c'], 'b', { authenticated: true });
    const toolbar = getByTestId('heirloom-viewer-toolbar');
    const sequence = [...toolbar.querySelectorAll('button, [role="button"], [role="menuitem"]')]
      .map((element) => element.getAttribute('aria-label') ?? element.textContent?.trim() ?? '')
      .filter((label) => label.length > 0);
    const orderOf = (label: string) => sequence.indexOf(label);
    const rotateLabel = 'Rotate — Rotation is display-only and is not saved.';
    const expected = [
      'go_back',
      'to_favorite',
      rotateLabel,
      'delete',
      'move_to_library',
      'add_to_album',
      'editor',
      'info',
    ];
    for (const label of expected) {
      expect(orderOf(label), label).toBeGreaterThanOrEqual(0);
    }
    const positions = expected.map(orderOf);
    expect([...positions].sort((a, b) => a - b)).toEqual(positions);
    // VisionKit Live Text is a labeled, disabled macOS-only exception.
    const allLabels = [...toolbar.querySelectorAll('*')]
      .map((element) => element.getAttribute('aria-label') ?? '')
      .join('\n');
    expect(allLabels).toContain(HEIRLOOM_LIVE_TEXT_NOTE.slice(0, 40));
  });

  it('omits Edit without an authenticated editor (Decision A: no inert replicas)', () => {
    const { queryByLabelText } = setup();
    expect(queryByLabelText('Editor')).toBeNull();
  });

  it('pages next with wrap-around and previous without wrapping mid-list', async () => {
    const { getByLabelText, onNavigate } = setup(['a', 'b', 'c'], 'c');
    await fireEvent.click(getByLabelText('next'));
    expect(onNavigate).toHaveBeenCalledWith('a');

    onNavigate.mockClear();
    await fireEvent.click(getByLabelText('previous'));
    // Still on `c` (props are shell-owned): previous of `c` is `b`.
    expect(onNavigate).toHaveBeenCalledWith('b');
  });

  it('supports keyboard paging and Escape-to-close', async () => {
    const { onNavigate, onClose } = setup(['a', 'b', 'c'], 'a');
    await fireEvent.keyDown(document, { key: 'ArrowRight' });
    expect(onNavigate).toHaveBeenCalledWith('b');
    await fireEvent.keyDown(document, { key: 'Escape' });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('rotates display-only via toolbar and keyboard without navigating', async () => {
    const { getByTestId, getByLabelText, onNavigate } = setup();
    const canvas = getByTestId('heirloom-viewer-canvas');
    expect(canvas.style.transform).toBe('');
    await fireEvent.click(getByLabelText('Rotate — Rotation is display-only and is not saved.'));
    expect(canvas.style.transform).toBe('rotate(90deg)');
    await fireEvent.keyDown(document, { key: 'r' });
    expect(canvas.style.transform).toBe('rotate(180deg)');
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it('toggles the inspector with EXIF-capable detail content', async () => {
    const { getByTestId, getByLabelText, queryByTestId } = setup();
    expect(queryByTestId('heirloom-viewer-inspector')).toBeNull();
    await fireEvent.click(getByLabelText('info'));
    expect(getByTestId('heirloom-viewer-inspector')).toBeInTheDocument();
  });

  it('renders an error state for an unknown asset id', () => {
    const { getByText, queryByTestId } = setup(['a', 'b'], 'zzz');
    expect(getByText('Asset not found in this view.')).toBeInTheDocument();
    expect(queryByTestId('heirloom-viewer-canvas')).toBeNull();
  });
});
