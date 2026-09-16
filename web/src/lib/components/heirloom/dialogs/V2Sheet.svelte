<!-- Heirloom Web V2 — sheet shell (WP7, WP1 §6).
  Base dialog for every V2 management sheet: headline title, default slot,
  inline red-caption error, Cancel/primary footer (Cancel first).

  Keyboard contract (WP7 acceptance): Escape cancels, Tab is trapped inside
  the dialog, initial focus lands on [data-autofocus] (or the first focusable
  control), and focus returns to the opener on destroy via
  `captureFocusRestore`. Overlay clicks never dismiss (cancel must be explicit
  so it provably has no side effects).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import { captureFocusRestore } from './sheet-logic';

  interface Props {
    title: string;
    /** Native sheet width in px — always a SHEET_WIDTHS value, never a literal. */
    width: number;
    /** Inline red-caption error; null hides the row. */
    error?: string | null;
    onClose: () => void;
    children?: Snippet;
    footer?: Snippet;
  }

  let { title, width, error = null, onClose, children, footer }: Props = $props();

  let dialog = $state<HTMLElement | null>(null);
  let restoreFocus: (() => void) | null = null;

  const focusables = (): HTMLElement[] => {
    if (!dialog) {
      return [];
    }
    const nodes = dialog.querySelectorAll<HTMLElement>(
      'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
    );
    return [...nodes].filter((node) => node.offsetParent !== null || node === document.activeElement);
  };

  $effect(() => {
    restoreFocus = captureFocusRestore(document);
    const initial =
      dialog?.querySelector<HTMLElement>('[data-autofocus]') ?? focusables()[0] ?? dialog;
    initial?.focus();

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key !== 'Tab' || !dialog) {
        return;
      }
      const items = focusables();
      if (items.length === 0) {
        return;
      }
      const first = items[0];
      const last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown, true);
    return () => {
      document.removeEventListener('keydown', onKeyDown, true);
      restoreFocus?.();
    };
  });
</script>

<div data-heirloom-v2 data-testid="v2-sheet-overlay" class="v2-sheet-overlay">
  <div
    bind:this={dialog}
    role="dialog"
    aria-modal="true"
    aria-label={title}
    tabindex="-1"
    data-testid="v2-sheet"
    class="v2-sheet"
    style={`width: ${width}px`}
  >
    <h2 class="v2-sheet-title">{title}</h2>
    {@render children?.()}
    {#if error}
      <p class="v2-sheet-error" role="alert">{error}</p>
    {/if}
    {#if footer}
      <div class="v2-sheet-footer">{@render footer()}</div>
    {/if}
  </div>
</div>

<style>
  .v2-sheet-overlay {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding-top: 12vh;
    background-color: rgb(0 0 0 / 0.25);
  }

  .v2-sheet {
    max-width: calc(100vw - 32px);
    max-height: calc(100dvh - 32px);
    overflow-y: auto;
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 16px;
    border-radius: 12px;
    background-color: var(--v2-sheet-background, #fff);
    color: var(--v2-foreground, #1d1d1f);
    box-shadow: 0 12px 40px rgb(0 0 0 / 0.25);
    font-family:
      -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, 'Segoe UI', sans-serif;
  }

  .v2-sheet-title {
    margin: 0;
    font-size: 17px;
    line-height: 1.3;
    font-weight: 700;
  }

  .v2-sheet-error {
    margin: 0;
    font-size: 12px;
    line-height: 1.4;
    color: #d70015;
  }

  .v2-sheet-footer {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 4px;
  }

  /* Shared control styles consumed by every sheet in this directory. */
  :global([data-heirloom-v2] .v2-field-label) {
    display: block;
    font-size: 13px;
    font-weight: 600;
    margin: 0 0 4px;
  }

  :global([data-heirloom-v2] .v2-input),
  :global([data-heirloom-v2] .v2-textarea),
  :global([data-heirloom-v2] .v2-select) {
    width: 100%;
    box-sizing: border-box;
    font: inherit;
    font-size: 13px;
    padding: 6px 8px;
    border: 1px solid var(--v2-border, #d2d2d7);
    border-radius: 8px;
    background-color: var(--v2-input-background, #fff);
    color: inherit;
  }

  :global([data-heirloom-v2] .v2-input:focus-visible),
  :global([data-heirloom-v2] .v2-textarea:focus-visible),
  :global([data-heirloom-v2] .v2-select:focus-visible),
  :global([data-heirloom-v2] .v2-btn:focus-visible),
  :global([data-heirloom-v2] .v2-row-btn:focus-visible) {
    outline: 2px solid var(--v2-focus, #0a84ff);
    outline-offset: 1px;
  }

  :global([data-heirloom-v2] .v2-btn) {
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    padding: 6px 14px;
    border-radius: 8px;
    border: 1px solid var(--v2-border, #d2d2d7);
    background-color: var(--v2-btn-background, #f5f5f7);
    color: inherit;
    cursor: pointer;
  }

  :global([data-heirloom-v2] .v2-btn:disabled) {
    opacity: 0.45;
    cursor: default;
  }

  /* WP11 A18: #0071e3 (was #0a84ff ≈ 3.7:1) — white-on-fill ≈ 4.7:1 on
    both themes since the fill is solid. */
  :global([data-heirloom-v2] .v2-btn-primary) {
    background-color: #0071e3;
    border-color: #0071e3;
    color: #fff;
  }

  :global([data-heirloom-v2] .v2-btn-danger) {
    background-color: #d70015;
    border-color: #d70015;
    color: #fff;
  }

  :global([data-heirloom-v2] .v2-btn-ghost-danger) {
    background-color: transparent;
    border-color: transparent;
    color: #d70015;
  }

  :global([data-heirloom-v2] .v2-row-btn) {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
    box-sizing: border-box;
    font: inherit;
    text-align: start;
    padding: 8px;
    border: 0;
    border-radius: 8px;
    background: transparent;
    color: inherit;
    cursor: pointer;
  }

  :global([data-heirloom-v2] .v2-row-btn:hover:not(:disabled)) {
    background-color: var(--v2-hover, rgb(0 0 0 / 0.05));
  }

  :global([data-heirloom-v2] .v2-row-btn:disabled) {
    opacity: 0.45;
    cursor: default;
  }

  :global([data-heirloom-v2] .v2-row-title) {
    font-size: 13px;
    font-weight: 500;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  :global([data-heirloom-v2] .v2-row-sub) {
    font-size: 12px;
    color: var(--v2-secondary-foreground, #6e6e73);
  }

  :global([data-heirloom-v2] .v2-sheet-list) {
    overflow-y: auto;
    border: 1px solid var(--v2-border, #d2d2d7);
    border-radius: 8px;
  }

  :global([data-heirloom-v2] .v2-sheet-empty) {
    margin: 0;
    padding: 24px 12px;
    text-align: center;
    font-size: 13px;
    color: var(--v2-secondary-foreground, #6e6e73);
  }

  /* WP11 A18: #0071e3 ≈ 4.7:1 on white (was #0a84ff ≈ 3.7:1). */
  :global([data-heirloom-v2] .v2-link-btn) {
    font: inherit;
    font-size: 12px;
    padding: 0;
    border: 0;
    background: transparent;
    color: #0071e3;
    cursor: pointer;
  }

  :global([data-heirloom-v2] .v2-helper) {
    margin: 0;
    font-size: 12px;
    color: var(--v2-secondary-foreground, #6e6e73);
  }

  @media (prefers-color-scheme: dark) {
    .v2-sheet {
      --v2-sheet-background: #2c2c2e;
      --v2-foreground: #f5f5f7;
      --v2-border: #48484a;
      --v2-input-background: #1c1c1e;
      --v2-btn-background: #48484a;
      --v2-hover: rgb(255 255 255 / 0.08);
      --v2-secondary-foreground: #a1a1a6;
    }
    /* WP11 A18: #0071e3 fails on the dark sheet (≈ 3.0:1) — #2997ff ≈ 4.6:1
      on #2c2c2e keeps the link readable. Primary stays solid-fill, fine. */
    :global([data-heirloom-v2] .v2-link-btn) {
      color: #2997ff;
    }
  }
</style>
