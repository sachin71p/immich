import {
  getAllPeople,
  type MetadataSearchDto,
  type PersonResponseDto,
  type SharedLibraryResponseDto,
  type SharedSpaceResponseDto,
  type SmartSearchDto,
  type TagResponseDto,
} from '@immich/sdk';
import { DateTime } from 'luxon';
import { t } from 'svelte-i18n';
import type { SvelteSet } from 'svelte/reactivity';
import { get } from 'svelte/store';
import { MediaType, ProjectionType } from '$lib/constants';
import type { SearchExposureFilter, SearchFileFilter, SearchLibraryFilter } from '$lib/types';
import { handleError } from '$lib/utils/handle-error';

export enum SearchDatePreset {
  ThisYear,
  LastYear,
  Last30Days,
  Custom,
}

export const getSearchDatePreset = (after: DateTime | undefined, before: DateTime | undefined) => {
  if (!after && !before) {
    return;
  }

  const start = after?.toMillis();
  const end = before?.endOf('day').toMillis();

  if (start === DateTime.utc().startOf('year').toMillis() && end === DateTime.utc().endOf('year').toMillis()) {
    return SearchDatePreset.ThisYear;
  }

  if (
    start === DateTime.utc().minus({ years: 1 }).startOf('year').toMillis() &&
    end === DateTime.utc().minus({ years: 1 }).endOf('year').toMillis()
  ) {
    return SearchDatePreset.LastYear;
  }

  if (
    start === DateTime.utc().minus({ days: 30 }).startOf('day').toMillis() &&
    end === DateTime.utc().endOf('day').toMillis()
  ) {
    return SearchDatePreset.Last30Days;
  }

  return SearchDatePreset.Custom;
};

export const getSearchDateRange = (after: DateTime | undefined, before: DateTime | undefined) => {
  const $t = get(t);
  const start = after?.toLocaleString(DateTime.DATE_MED);
  const end = before?.toLocaleString(DateTime.DATE_MED);
  return start && end ? $t('search_filter_date_interval', { values: { start, end } }) : (start ?? end);
};

export const getSearchDateTitle = (
  preset: SearchDatePreset | undefined,
  before: DateTime | undefined,
  after: DateTime | undefined,
): string | undefined => {
  const $t = get(t);
  switch (preset) {
    case SearchDatePreset.ThisYear: {
      return $t('search_filter_date_this_year');
    }
    case SearchDatePreset.LastYear: {
      return $t('search_filter_date_last_year');
    }
    case SearchDatePreset.Last30Days: {
      return $t('search_filter_date_last_30_days');
    }
    case SearchDatePreset.Custom: {
      return getSearchDateRange(before, after);
    }
    default: {
      return;
    }
  }
};

export const getSearchTypeTitle = (type: string) => {
  const $t = get(t);
  switch (type) {
    case 'metadata': {
      return $t('file_name_text');
    }
    case 'description': {
      return $t('description');
    }
    case 'fullPath': {
      return $t('full_path_or_folder');
    }
    case 'ocr': {
      return $t('ocr');
    }
    default: {
      return;
    }
  }
};

export const getSearchTypePlaceholder = (type: string) => {
  const $t = get(t);
  switch (type) {
    case 'metadata': {
      return $t('search_by_filename_example');
    }
    case 'description': {
      return $t('search_by_description_example');
    }
    case 'fullPath': {
      return $t('search_by_full_path_example');
    }
    case 'ocr': {
      return $t('search_by_ocr_example');
    }
    case 'smart': {
      return $t('search_by_context_example');
    }
    default: {
      return $t('search_your_photos');
    }
  }
};

export const getSearchPlacesTitle = (city?: string, state?: string, country?: string) =>
  [city, state, country].filter(Boolean).join(', ') || undefined;

export const getSearchMediaTitle = (mediaType: MediaType) => {
  const $t = get(t);
  switch (mediaType) {
    case MediaType.Image: {
      return $t('image');
    }
    case MediaType.Video: {
      return $t('video');
    }
    default: {
      return;
    }
  }
};

export const getPeople = async (selected: SvelteSet<string>): Promise<PersonResponseDto[]> => {
  const $t = get(t);
  try {
    const res = await getAllPeople({ withHidden: false });
    res.people.sort((a, b) => (selected.has(a.id) ? -1 : selected.has(b.id) ? 1 : 0));
    return res.people;
  } catch (error) {
    handleError(error, $t('errors.failed_to_get_people'));
  }
  return [];
};

export const getSearchPeopleTitle = (people: PersonResponseDto[], selected: SvelteSet<string>) => {
  if (selected.size === 0) {
    return;
  }

  const $t = get(t);

  const name = people.find(({ id, name }) => name && selected.has(id))?.name;
  if (name) {
    return selected.size === 1 ? name : $t('name_plus_more_people', { values: { name, count: selected.size - 1 } });
  }

  return $t('people_count', { values: { count: selected.size } });
};

export const getSearchTagsTitle = (tags: TagResponseDto[], selected: SvelteSet<string>) => {
  const $t = get(t);

  const id = selected.values().next().value;
  if (!id) {
    return undefined;
  }

  const tag = tags.find((t) => t.id === id)?.name;
  if (!tag) {
    return undefined;
  }

  return selected.size === 1 ? tag : $t('tag_plus_more_tags', { values: { tag, count: selected.size - 1 } });
};

// fork: shared-libraries
export const fromExposureQuery = (searchQuery: MetadataSearchDto | SmartSearchDto): SearchExposureFilter => ({
  isoMin: searchQuery.isoMin,
  isoMax: searchQuery.isoMax,
  fNumberMin: searchQuery.fNumberMin,
  fNumberMax: searchQuery.fNumberMax,
  focalLengthMin: searchQuery.focalLengthMin,
  focalLengthMax: searchQuery.focalLengthMax,
});

// fork: shared-libraries
export const toExposureQuery = (filter: SearchExposureFilter): Partial<MetadataSearchDto & SmartSearchDto> => ({
  isoMin: filter.isoMin,
  isoMax: filter.isoMax,
  fNumberMin: filter.fNumberMin,
  fNumberMax: filter.fNumberMax,
  focalLengthMin: filter.focalLengthMin,
  focalLengthMax: filter.focalLengthMax,
});

// fork: shared-libraries
export const getSearchExposureTitle = (filter: SearchExposureFilter): string | undefined => {
  const $t = get(t);
  const parts: string[] = [];
  if (filter.isoMin !== undefined || filter.isoMax !== undefined) {
    parts.push($t('iso'));
  }
  if (filter.fNumberMin !== undefined || filter.fNumberMax !== undefined) {
    parts.push($t('f_number'));
  }
  if (filter.focalLengthMin !== undefined || filter.focalLengthMax !== undefined) {
    parts.push($t('focal_length'));
  }
  return parts.length > 0 ? parts.join(', ') : undefined;
};

// fork: shared-libraries
export const fromFileQuery = (searchQuery: MetadataSearchDto | SmartSearchDto): SearchFileFilter => ({
  fileExtensions: searchQuery.fileExtensions ?? [],
  mimeTypes: searchQuery.mimeTypes ?? [],
  fileSizeMin: searchQuery.fileSizeMin,
  fileSizeMax: searchQuery.fileSizeMax,
  widthMin: searchQuery.widthMin,
  heightMin: searchQuery.heightMin,
  is360: searchQuery.projectionType === ProjectionType.EQUIRECTANGULAR,
  hasLocation: searchQuery.hasLocation,
  fpsMin: searchQuery.fpsMin,
  fpsMax: searchQuery.fpsMax,
});

// fork: shared-libraries
export const toFileQuery = (filter: SearchFileFilter): Partial<MetadataSearchDto & SmartSearchDto> => ({
  fileExtensions: filter.fileExtensions.length > 0 ? filter.fileExtensions : undefined,
  mimeTypes: filter.mimeTypes.length > 0 ? filter.mimeTypes : undefined,
  fileSizeMin: filter.fileSizeMin,
  fileSizeMax: filter.fileSizeMax,
  widthMin: filter.widthMin,
  heightMin: filter.heightMin,
  projectionType: filter.is360 ? ProjectionType.EQUIRECTANGULAR : undefined,
  hasLocation: filter.hasLocation || undefined,
  fpsMin: filter.fpsMin,
  fpsMax: filter.fpsMax,
});

// fork: shared-libraries
export const getSearchFileTitle = (filter: SearchFileFilter): string | undefined => {
  const $t = get(t);
  const active =
    filter.fileExtensions.length > 0 ||
    filter.mimeTypes.length > 0 ||
    filter.fileSizeMin !== undefined ||
    filter.fileSizeMax !== undefined ||
    filter.widthMin !== undefined ||
    filter.heightMin !== undefined ||
    filter.is360 ||
    filter.hasLocation ||
    filter.fpsMin !== undefined ||
    filter.fpsMax !== undefined;
  return active ? $t('search_filter_file') : undefined;
};

// fork: shared-libraries
export const fromLibraryQuery = (searchQuery: MetadataSearchDto | SmartSearchDto): SearchLibraryFilter => {
  if (searchQuery.spaceId) {
    return { scope: 'space', spaceId: searchQuery.spaceId };
  }
  if (searchQuery.libraryId) {
    return { scope: 'library', libraryId: searchQuery.libraryId };
  }
  if (searchQuery.personalOnly) {
    return { scope: 'personal' };
  }
  return { scope: 'all' };
};

// fork: shared-libraries
export const toLibraryQuery = (filter: SearchLibraryFilter): Partial<MetadataSearchDto & SmartSearchDto> => ({
  spaceId: filter.scope === 'space' ? filter.spaceId : undefined,
  libraryId: filter.scope === 'library' ? filter.libraryId : undefined,
  personalOnly: filter.scope === 'personal' ? true : undefined,
});

// fork: shared-libraries
export const getSearchLibraryTitle = (
  filter: SearchLibraryFilter,
  spaces: SharedSpaceResponseDto[],
  libraries: SharedLibraryResponseDto[],
): string | undefined => {
  const $t = get(t);
  switch (filter.scope) {
    case 'personal': {
      return $t('personal_library');
    }
    case 'space': {
      return spaces.find((space) => space.id === filter.spaceId)?.name;
    }
    case 'library': {
      return libraries.find((library) => library.id === filter.libraryId)?.name;
    }
    default: {
      return undefined;
    }
  }
};

export const isPopoverContent = (event: FocusEvent): boolean => {
  const element = event.relatedTarget;
  return element instanceof Element && element.closest('[data-popover-content]') !== null;
};
