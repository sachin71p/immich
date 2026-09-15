import {
  fromExposureQuery,
  fromFileQuery,
  fromLibraryQuery,
  isPopoverContent,
  toExposureQuery,
  toFileQuery,
  toLibraryQuery,
} from '$lib/components/shared-components/search-bar/search-bar-utils';
import { ProjectionType } from '$lib/constants';

describe('isPopoverContent', () => {
  const focusOutEventTo = (relatedTarget: EventTarget | null) => new FocusEvent('focusout', { relatedTarget });

  const createCalendarPopup = () => {
    const popup = document.createElement('div');
    popup.dataset.popoverContent = '';
    return popup;
  };

  it('returns true when focus moves to an element inside a calendar popup', () => {
    const popup = createCalendarPopup();
    const dayButton = document.createElement('button');
    popup.append(dayButton);

    expect(isPopoverContent(focusOutEventTo(dayButton))).toBe(true);
  });

  it('returns true when focus moves to the calendar popup itself', () => {
    const popup = createCalendarPopup();

    expect(isPopoverContent(focusOutEventTo(popup))).toBe(true);
  });

  it('returns false when focus moves to an element outside a calendar popup', () => {
    const button = document.createElement('button');

    expect(isPopoverContent(focusOutEventTo(button))).toBe(false);
  });

  it('returns false when focus does not move to another element', () => {
    expect(isPopoverContent(focusOutEventTo(null))).toBe(false);
  });
});

// fork: shared-libraries
describe('exposure query round-trip', () => {
  it('round-trips exposure range params', () => {
    const filter = fromExposureQuery({
      isoMin: 100,
      isoMax: 3200,
      fNumberMin: 1.4,
      fNumberMax: 8,
      focalLengthMin: 24,
      focalLengthMax: 70,
    });

    expect(filter).toEqual({
      isoMin: 100,
      isoMax: 3200,
      fNumberMin: 1.4,
      fNumberMax: 8,
      focalLengthMin: 24,
      focalLengthMax: 70,
    });
    expect(toExposureQuery(filter)).toEqual({
      isoMin: 100,
      isoMax: 3200,
      fNumberMin: 1.4,
      fNumberMax: 8,
      focalLengthMin: 24,
      focalLengthMax: 70,
    });
  });

  it('defaults to an empty filter when no exposure params are present', () => {
    const filter = fromExposureQuery({});

    expect(filter).toEqual({
      isoMin: undefined,
      isoMax: undefined,
      fNumberMin: undefined,
      fNumberMax: undefined,
      focalLengthMin: undefined,
      focalLengthMax: undefined,
    });
  });
});

// fork: shared-libraries
describe('file query round-trip', () => {
  it('round-trips file filter params, including the 360 toggle', () => {
    const filter = fromFileQuery({
      fileExtensions: ['jpg', 'png'],
      mimeTypes: ['image/jpeg'],
      fileSizeMin: 1024,
      fileSizeMax: 10_485_760,
      widthMin: 1920,
      heightMin: 1080,
      projectionType: ProjectionType.EQUIRECTANGULAR,
      hasLocation: true,
      fpsMin: 24,
      fpsMax: 60,
    });

    expect(filter).toEqual({
      fileExtensions: ['jpg', 'png'],
      mimeTypes: ['image/jpeg'],
      fileSizeMin: 1024,
      fileSizeMax: 10_485_760,
      widthMin: 1920,
      heightMin: 1080,
      is360: true,
      hasLocation: true,
      fpsMin: 24,
      fpsMax: 60,
    });
    expect(toFileQuery(filter)).toEqual({
      fileExtensions: ['jpg', 'png'],
      mimeTypes: ['image/jpeg'],
      fileSizeMin: 1024,
      fileSizeMax: 10_485_760,
      widthMin: 1920,
      heightMin: 1080,
      projectionType: ProjectionType.EQUIRECTANGULAR,
      hasLocation: true,
      fpsMin: 24,
      fpsMax: 60,
    });
  });

  it('omits empty extension/mime lists and unset flags when serializing', () => {
    const filter = fromFileQuery({});

    expect(filter.fileExtensions).toEqual([]);
    expect(filter.mimeTypes).toEqual([]);
    expect(filter.is360).toBe(false);

    const query = toFileQuery(filter);
    expect(query.fileExtensions).toBeUndefined();
    expect(query.mimeTypes).toBeUndefined();
    expect(query.projectionType).toBeUndefined();
    expect(query.hasLocation).toBeUndefined();
  });
});

// fork: shared-libraries
describe('library query round-trip', () => {
  it('round-trips a shared space selection', () => {
    const filter = fromLibraryQuery({ spaceId: 'space-1' });

    expect(filter).toEqual({ scope: 'space', spaceId: 'space-1' });
    expect(toLibraryQuery(filter)).toEqual({ spaceId: 'space-1', libraryId: undefined, personalOnly: undefined });
  });

  it('round-trips an external library selection', () => {
    const filter = fromLibraryQuery({ libraryId: 'library-1' });

    expect(filter).toEqual({ scope: 'library', libraryId: 'library-1' });
    expect(toLibraryQuery(filter)).toEqual({ spaceId: undefined, libraryId: 'library-1', personalOnly: undefined });
  });

  it('round-trips the personal-only scope', () => {
    const filter = fromLibraryQuery({ personalOnly: true });

    expect(filter).toEqual({ scope: 'personal' });
    expect(toLibraryQuery(filter)).toEqual({ spaceId: undefined, libraryId: undefined, personalOnly: true });
  });

  it('defaults to the "all" scope when nothing is set', () => {
    const filter = fromLibraryQuery({});

    expect(filter).toEqual({ scope: 'all' });
    expect(toLibraryQuery(filter)).toEqual({ spaceId: undefined, libraryId: undefined, personalOnly: undefined });
  });
});
