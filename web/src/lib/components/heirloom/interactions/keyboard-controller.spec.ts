// WP6 — type-to-date buffer + keyboard map specs.
import { describe, expect, it } from 'vitest';
import {
  describeGridKey,
  findDateMatch,
  isTypeAheadKey,
  TypeAheadBuffer,
  TYPE_AHEAD_TIMEOUT_MS,
} from './keyboard-controller';

const asset = (id: string, year: number, month: number, day: number) => ({
  id,
  localDateTime: { year, month, day },
});

describe('type-to-date buffer', () => {
  it('accumulates within the 1s window and resets after it', () => {
    const buffer = new TypeAheadBuffer();
    expect(buffer.push('2', 0)).toBe('2');
    expect(buffer.push('0', 500)).toBe('20');
    expect(buffer.push('2', 500 + TYPE_AHEAD_TIMEOUT_MS + 1)).toBe('2');
    expect(buffer.value(500 + TYPE_AHEAD_TIMEOUT_MS + 2)).toBe('2');
    expect(buffer.value(500 + 2 * TYPE_AHEAD_TIMEOUT_MS + 10)).toBe('');
  });

  it('only accepts digits and dash as type-ahead keys', () => {
    expect(isTypeAheadKey('5')).toBe(true);
    expect(isTypeAheadKey('-')).toBe(true);
    expect(isTypeAheadKey('a')).toBe(false);
    expect(isTypeAheadKey('Enter')).toBe(false);
    expect(isTypeAheadKey(' ')).toBe(false);
  });

  it('jumps to the first asset matching year/month/day prefixes', () => {
    const assets = [asset('n1', 2024, 6, 1), asset('n2', 2023, 12, 25), asset('n3', 2023, 12, 31)];
    expect(findDateMatch(assets, '2024')).toBe('n1');
    expect(findDateMatch(assets, '2023-12-3')).toBe('n3');
    expect(findDateMatch(assets, '2022')).toBeNull();
    expect(findDateMatch(assets, '')).toBeNull();
  });
});

describe('grid keyboard map', () => {
  it('maps select-all, clear, open, and preview', () => {
    expect(describeGridKey({ key: 'a', metaKey: true })).toEqual({ type: 'select-all' });
    expect(describeGridKey({ key: 'A', ctrlKey: true })).toEqual({ type: 'select-all' });
    expect(describeGridKey({ key: 'Escape' })).toEqual({ type: 'clear' });
    expect(describeGridKey({ key: 'Enter' })).toEqual({ type: 'open' });
    expect(describeGridKey({ key: ' ' })).toEqual({ type: 'preview' });
  });

  it('ignores modified open/preview keys and plain characters', () => {
    expect(describeGridKey({ key: 'Enter', metaKey: true })).toEqual({ type: 'ignore' });
    expect(describeGridKey({ key: ' ', shiftKey: true })).toEqual({ type: 'ignore' });
    expect(describeGridKey({ key: 'a' })).toEqual({ type: 'ignore' });
    expect(describeGridKey({ key: 'ArrowRight' })).toEqual({ type: 'ignore' });
  });
});
