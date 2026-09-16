// WP11 fix-batch spec (A10): memory player focus trap + restoration.
import { fireEvent, render } from '@testing-library/svelte';
import V2MemoryPlayer from './V2MemoryPlayer.svelte';

const props = {
  title: 'Summer trip',
  assetIds: ['a', 'b'],
  onClose: vi.fn(),
};

const focusables = (container: HTMLElement): HTMLElement[] =>
  [...container.querySelectorAll<HTMLElement>('button:not([disabled]), input:not([disabled])')].filter(
    (node) => node.offsetParent !== null || node === document.activeElement,
  );

describe('V2MemoryPlayer focus contract', () => {
  it('moves focus inside the dialog on open', () => {
    const { container } = render(V2MemoryPlayer, { ...props });
    const dialog = container.querySelector('[data-testid="v2-memory-player"]');
    expect(dialog).not.toBeNull();
    expect(dialog?.contains(document.activeElement)).toBe(true);
  });

  it('restores focus to the opener on close', () => {
    const opener = document.createElement('button');
    opener.textContent = 'Open memories';
    document.body.append(opener);
    opener.focus();
    expect(document.activeElement).toBe(opener);
    try {
      const { unmount } = render(V2MemoryPlayer, { ...props });
      expect(document.activeElement).not.toBe(opener);
      unmount();
      expect(document.activeElement).toBe(opener);
    } finally {
      opener.remove();
    }
  });

  it('traps Tab inside the dialog', async () => {
    const { container } = render(V2MemoryPlayer, { ...props });
    const items = focusables(container);
    expect(items.length).toBeGreaterThan(1);
    const first = items[0];
    const last = items[items.length - 1];
    last.focus();
    await fireEvent.keyDown(document, { key: 'Tab' });
    expect(document.activeElement).toBe(first);
    first.focus();
    await fireEvent.keyDown(document, { key: 'Tab', shiftKey: true });
    expect(document.activeElement).toBe(last);
  });
});
