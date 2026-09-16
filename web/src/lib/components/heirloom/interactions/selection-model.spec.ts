// WP6 — selection model (single/toggle/range/anchor/arrows) specs.
import { describe, expect, it } from 'vitest';
import { HeirloomSelectionModel, orderChecksum } from './selection-model';

const ids = ['a', 'b', 'c', 'd', 'e'];

const modelWith = () => {
  const model = new HeirloomSelectionModel();
  model.setOrder(ids);
  return model;
};

describe('heirloom selection model', () => {
  it('single click selects exactly one tile and sets the anchor', () => {
    const model = modelWith();
    model.click('c');
    expect(model.selectedIds()).toEqual(['c']);
    expect(model.anchorId).toBe('c');
    expect(model.focusedId).toBe('c');
  });

  it('toggle adds and removes without disturbing the rest', () => {
    const model = modelWith();
    model.click('b');
    model.toggle('d');
    expect(model.selectedIds()).toEqual(['b', 'd']);
    model.toggle('b');
    expect(model.selectedIds()).toEqual(['d']);
    expect(model.anchorId).toBe('b');
  });

  it('shift-click extends the range from the anchor in both directions', () => {
    const model = modelWith();
    model.click('c');
    model.extend('e');
    expect(model.selectedIds()).toEqual(['c', 'd', 'e']);
    model.extend('a');
    expect(model.selectedIds()).toEqual(['a', 'b', 'c']);
    expect(model.anchorId).toBe('c');
  });

  it('shift-click with no anchor extends from focus', () => {
    const model = modelWith();
    model.focus('d');
    model.extend('b');
    expect(model.selectedIds()).toEqual(['b', 'c', 'd']);
  });

  it('select-all then clear resets selection and anchor', () => {
    const model = modelWith();
    model.selectAll();
    expect(model.selectedIds()).toEqual(ids);
    expect(model.count).toBe(5);
    model.clear();
    expect(model.selectedIds()).toEqual([]);
    expect(model.anchorId).toBeNull();
  });

  it('plain arrow move collapses to the newly focused tile', () => {
    const model = modelWith();
    model.click('b');
    expect(model.moveFocusBy(2)).toBe('d');
    expect(model.selectedIds()).toEqual(['d']);
  });

  it('shift+arrow extends from the anchor and clamps at the edges', () => {
    const model = modelWith();
    model.click('b');
    model.moveFocusBy(2, { extend: true });
    expect(model.selectedIds()).toEqual(['b', 'c', 'd']);
    model.moveFocusBy(10, { extend: true });
    expect(model.selectedIds()).toEqual(['b', 'c', 'd', 'e']);
    expect(model.focusedId).toBe('e');
    model.moveFocusBy(-100);
    expect(model.selectedIds()).toEqual(['a']);
  });

  it('ignores unknown ids and prunes order changes', () => {
    const model = modelWith();
    model.click('zzz');
    expect(model.selectedIds()).toEqual([]);
    model.click('a');
    model.toggle('b');
    expect(model.setOrder(['a', 'c'])).toEqual(['b']);
    expect(model.selectedIds()).toEqual(['a']);
  });
});

describe('orderChecksum (WP11 P1)', () => {
  const joinKey = (list: string[]): string => list.join(',');

  it('is stable for identical input and distinct for different ends', () => {
    expect(orderChecksum([])).toBe(orderChecksum([]));
    expect(orderChecksum(ids)).toBe(orderChecksum([...ids]));
    expect(orderChecksum(['a'])).not.toBe(orderChecksum(['b']));
    expect(orderChecksum(ids)).not.toBe(orderChecksum([...ids, 'f']));
    expect(orderChecksum(ids)).not.toBe(orderChecksum(ids.slice(1)));
    expect(orderChecksum(ids)).not.toBe(orderChecksum(ids.slice(0, -1)));
  });

  it('agrees with the joined key on every membership-changing mutation', () => {
    // The mutations syncOrder must react to: append, drop head/tail/middle,
    // replace, clear. Both keys must change exactly when membership changes.
    const mutations: string[][] = [
      [...ids, 'f'],
      ['z', ...ids],
      ids.slice(1),
      ids.slice(0, -1),
      ids.filter((id) => id !== 'c'),
      ['x', 'y'],
      [],
    ];
    for (const next of mutations) {
      const membershipChanged = new Set(next).size !== new Set(ids).size || next.some((id) => !ids.includes(id));
      expect(orderChecksum(next) !== orderChecksum(ids)).toBe(membershipChanged);
      expect((joinKey(next) !== joinKey(ids)) === membershipChanged).toBe(true);
    }
  });

  it('is O(1)-sized regardless of list length', () => {
    const big = Array.from({ length: 10_000 }, (_, index) => `asset-${index}`);
    expect(orderChecksum(big).length).toBeLessThan(40);
    expect(joinKey(big).length).toBeGreaterThan(50_000);
  });
});
