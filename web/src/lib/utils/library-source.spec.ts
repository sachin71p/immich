import { librarySource, parseLibrarySource, spaceLibrarySource } from '$lib/utils/library-source';

describe('parseLibrarySource', () => {
  it('returns no filter for "all"', () => {
    expect(parseLibrarySource('all')).toEqual({});
  });

  it('returns personalOnly for "personal"', () => {
    expect(parseLibrarySource('personal')).toEqual({ personalOnly: true });
  });

  it('returns spaceId for a space source', () => {
    expect(parseLibrarySource(spaceLibrarySource('space-1'))).toEqual({ spaceId: 'space-1' });
  });

  it('returns libraryId for a library source', () => {
    expect(parseLibrarySource(librarySource('library-1'))).toEqual({ libraryId: 'library-1' });
  });

  it('falls back to no filter for an unknown value', () => {
    expect(parseLibrarySource('bogus')).toEqual({});
  });
});
