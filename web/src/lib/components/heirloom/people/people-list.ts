// Heirloom Web V2 — people list composition (WP9 slice 2).
//
// Pure model behind `/v2/people`. Native (`MacPeopleView`) is a minimal
// per-owner list — plain rows with an `Unnamed` fallback, no cards or
// stories — so V2 matches the list and navigates to a detail page for
// rename/merge/hide. Data comes from `getAllPeople({ withHidden })`
// (the classic people-page composition); this module only shapes rows.

import type { PersonResponseDto } from '@immich/sdk';

export type V2PersonRow = {
  id: string;
  displayName: string;
  isUnnamed: boolean;
  isHidden: boolean;
  isFavorite: boolean;
  updatedAt: string;
};

/** Shape people into minimal list rows with the native `Unnamed` fallback. */
export const toV2PersonRows = (people: PersonResponseDto[]): V2PersonRow[] =>
  people.map((person) => ({
    id: person.id,
    displayName: person.name === '' ? 'Unnamed' : person.name,
    isUnnamed: person.name === '',
    isHidden: person.isHidden,
    isFavorite: person.isFavorite ?? false,
    updatedAt: person.updatedAt ?? '',
  }));

/** Visible (non-hidden) people count for the list headline. */
export const countV2VisiblePeople = (people: Pick<PersonResponseDto, 'isHidden'>[]): number =>
  people.filter((person) => !person.isHidden).length;

/**
 * Client-side name filter for the list search field. Hidden people stay
 * hidden here — unhiding lives on the detail page, mirroring the classic
 * list which only renders non-hidden rows.
 */
export const filterV2PersonRows = (rows: V2PersonRow[], query: string): V2PersonRow[] => {
  const needle = query.trim().toLocaleLowerCase();
  if (!needle) {
    return rows;
  }
  return rows.filter((row) => row.displayName.toLocaleLowerCase().includes(needle));
};

/** Grid options for a person's assets: buckets `personId` filter (WP2 row). */
export const buildV2PersonAssetsOptions = (personId: string) => ({
  personId,
  withStacked: true,
});
