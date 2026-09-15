// fork: shared-libraries
// Parses the /photos library-switcher selection into the TimelineManager options fragment
// that selects the matching timeline source (DECISIONS §9 — spaceId/libraryId/personalOnly
// are mutually exclusive filters).

export const ALL_LIBRARY_SOURCE = 'all';
export const PERSONAL_LIBRARY_SOURCE = 'personal';
const SPACE_PREFIX = 'space:';
const LIBRARY_PREFIX = 'library:';

export const spaceLibrarySource = (spaceId: string) => `${SPACE_PREFIX}${spaceId}`;
export const librarySource = (libraryId: string) => `${LIBRARY_PREFIX}${libraryId}`;

export type LibrarySourceFilter = { personalOnly?: boolean; spaceId?: string; libraryId?: string };

export const parseLibrarySource = (value: string): LibrarySourceFilter => {
  if (value === PERSONAL_LIBRARY_SOURCE) {
    return { personalOnly: true };
  }
  if (value.startsWith(SPACE_PREFIX)) {
    return { spaceId: value.slice(SPACE_PREFIX.length) };
  }
  if (value.startsWith(LIBRARY_PREFIX)) {
    return { libraryId: value.slice(LIBRARY_PREFIX.length) };
  }
  return {};
};
