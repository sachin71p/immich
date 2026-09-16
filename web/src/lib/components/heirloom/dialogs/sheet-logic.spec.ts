// V2 management-sheet logic spec (WP7). Pure functions — no component mocks.
import { describe, expect, it } from 'vitest';
import { SharedSpaceRole, Status } from '@immich/sdk';
import {
  captureFocusRestore,
  decideRemoveMember,
  describeSpacePermissions,
  formatImportOverflow,
  formatMoveToast,
  IMPORT_CHOOSER_PREVIEW_COUNT,
  isSheetNameValid,
  SHEET_LIST_MIN_HEIGHT,
  SHEET_WIDTHS,
  sortRowsByTitle,
  summarizeImportFiles,
  summarizeMoveResults,
  validateSheetName,
} from './sheet-logic';

describe('sheet geometry (WP1 §6)', () => {
  it('pins every sheet to its native width', () => {
    expect(SHEET_WIDTHS).toEqual({
      newAlbum: 300,
      addToAlbum: 300,
      move: 320,
      newSpace: 320,
      manageSpace: 360,
      importChooser: 360,
    });
  });

  it('gives the album/move lists a 160px minimum height', () => {
    expect(SHEET_LIST_MIN_HEIGHT).toBe(160);
  });

  it('previews the first 5 import names', () => {
    expect(IMPORT_CHOOSER_PREVIEW_COUNT).toBe(5);
  });
});

describe('validateSheetName', () => {
  it('accepts a non-blank name', () => {
    expect(validateSheetName('Family')).toBeNull();
    expect(isSheetNameValid('Family')).toBe(true);
  });

  it('rejects empty and whitespace-only names (primary stays disabled)', () => {
    for (const name of ['', '   ', '\n\t ']) {
      expect(validateSheetName(name)).toBe('required');
      expect(isSheetNameValid(name)).toBe(false);
    }
  });

  it('accepts names with surrounding whitespace (components trim on submit)', () => {
    expect(validateSheetName('  Trips  ')).toBeNull();
  });
});

describe('describeSpacePermissions', () => {
  it('grants the owner edit, add, and delete but no leave', () => {
    expect(describeSpacePermissions(SharedSpaceRole.Owner)).toEqual({
      canEditDetails: true,
      canAddMembers: true,
      canDelete: true,
      canLeave: false,
    });
  });

  it('grants the contributor edit, add, and leave but no delete', () => {
    expect(describeSpacePermissions(SharedSpaceRole.Contributor)).toEqual({
      canEditDetails: true,
      canAddMembers: true,
      canDelete: false,
      canLeave: true,
    });
  });

  it('grants nothing to non-members or unknown roles (controls absent-or-disabled)', () => {
    for (const role of [undefined, 'admin' as unknown as SharedSpaceRole]) {
      expect(describeSpacePermissions(role)).toEqual({
        canEditDetails: false,
        canAddMembers: false,
        canDelete: false,
        canLeave: false,
      });
    }
  });
});

describe('decideRemoveMember', () => {
  it('never offers Remove on the self row (leave flow owns that)', () => {
    expect(decideRemoveMember(SharedSpaceRole.Owner, 'me', 'me')).toEqual({
      allowed: false,
      reason: 'self',
    });
    expect(decideRemoveMember(SharedSpaceRole.Contributor, 'me', 'me')).toEqual({
      allowed: false,
      reason: 'self',
    });
  });

  it('allows members to remove other members', () => {
    expect(decideRemoveMember(SharedSpaceRole.Owner, 'other', 'me')).toEqual({ allowed: true });
    expect(decideRemoveMember(SharedSpaceRole.Contributor, 'other', 'me')).toEqual({ allowed: true });
  });

  it('forbids removal for non-members with a reason (no inert buttons)', () => {
    expect(decideRemoveMember(undefined, 'other', 'me')).toEqual({
      allowed: false,
      reason: 'forbidden',
    });
  });
});

describe('summarizeMoveResults / formatMoveToast', () => {
  it('tallies moved / already-there / failed like the classic move modal', () => {
    expect(summarizeMoveResults([Status.Moved, Status.Moved, Status.Noop, Status.Error])).toEqual({
      moved: 2,
      unchanged: 1,
      failed: 1,
    });
  });

  it('reports an empty selection as all zeros', () => {
    expect(summarizeMoveResults([])).toEqual({ moved: 0, unchanged: 0, failed: 0 });
  });

  it('formats the WP1 success toast', () => {
    expect(formatMoveToast({ moved: 3, unchanged: 1, failed: 0 })).toBe('Moved 3 items (1 already there).');
  });

  it('formats the WP1 partial-failure toast', () => {
    expect(formatMoveToast({ moved: 2, unchanged: 1, failed: 1 })).toBe('Moved 2; 1 failed (1 already there).');
  });
});

describe('summarizeImportFiles', () => {
  it('shows the first 5 names plus the overflow count', () => {
    const names = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
    expect(summarizeImportFiles(names)).toEqual({ shown: ['a', 'b', 'c', 'd', 'e'], extra: 2 });
  });

  it('reports no overflow for 5 or fewer files', () => {
    expect(summarizeImportFiles(['a', 'b'])).toEqual({ shown: ['a', 'b'], extra: 0 });
    expect(summarizeImportFiles([])).toEqual({ shown: [], extra: 0 });
  });

  it('formats the overflow row', () => {
    expect(formatImportOverflow(3)).toBe('…and 3 more');
  });
});

describe('sortRowsByTitle', () => {
  it('sorts move/album rows by title without mutating the input', () => {
    const rows = [{ title: 'Zebra' }, { title: 'apple' }, { title: 'Mango' }];
    const sorted = sortRowsByTitle(rows);
    expect(sorted.map(({ title }) => title)).toEqual(['apple', 'Mango', 'Zebra']);
    expect(rows[0].title).toBe('Zebra');
  });
});

describe('captureFocusRestore', () => {
  it('restores focus to the element that was focused before the sheet opened', () => {
    const button = document.createElement('button');
    document.body.append(button);
    button.focus();
    expect(document.activeElement).toBe(button);

    const restore = captureFocusRestore(document);
    button.blur();
    expect(document.activeElement).not.toBe(button);

    restore();
    expect(document.activeElement).toBe(button);
    button.remove();
  });

  it('is a safe no-op when nothing restorable was focused', () => {
    (document.activeElement as HTMLElement | null)?.blur?.();
    const restore = captureFocusRestore(document);
    expect(() => restore()).not.toThrow();
  });

  it('does not throw when the previously focused element left the document', () => {
    const button = document.createElement('button');
    document.body.append(button);
    button.focus();
    const restore = captureFocusRestore(document);
    button.remove();
    expect(() => restore()).not.toThrow();
  });
});
