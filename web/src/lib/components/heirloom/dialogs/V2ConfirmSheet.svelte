<!-- Heirloom Web V2 — destructive confirmation sheet (WP7).
  Presentation-only wrapper over an explicit caller decision: the caller
  passes copy + tone and receives `onClose(confirmed)`. Used for delete,
  empty/restore trash, permanent delete, and the external-library drop
  confirm (`Move into external library?` + Move(destructive)/Cancel, WP1 §6).
  Trash callers reuse the sdk calls + toast keys from trash.service
  (emptyTrash/restoreTrash); this sheet only replaces the classic
  `modalManager.showDialog` presentation with the V2 sheet treatment.
-->
<script lang="ts">
  import { t } from 'svelte-i18n';
  import V2Sheet from './V2Sheet.svelte';
  import { SHEET_WIDTHS } from './sheet-logic';

  interface Props {
    title: string;
    body: string;
    confirmLabel: string;
    cancelLabel?: string;
    /** 'danger' renders the confirm action destructive red. */
    tone?: 'default' | 'danger';
    onClose: (confirmed: boolean) => void;
  }

  let { title, body, confirmLabel, cancelLabel, tone = 'default', onClose }: Props = $props();
</script>

<V2Sheet title={title} width={SHEET_WIDTHS.move} onClose={() => onClose(false)}>
  <p class="v2-helper">{body}</p>
  {#snippet footer()}
    <button type="button" class="v2-btn" data-autofocus onclick={() => onClose(false)}>
      {cancelLabel ?? $t('cancel')}
    </button>
    <button
      type="button"
      class={tone === 'danger' ? 'v2-btn v2-btn-danger' : 'v2-btn v2-btn-primary'}
      onclick={() => onClose(true)}
    >
      {confirmLabel}
    </button>
  {/snippet}
</V2Sheet>
