import type { QueueResponseDto } from '@immich/sdk';
import type { ActionItem } from '@immich/ui';
import type { DateTime } from 'luxon';
import type { SvelteSet } from 'svelte/reactivity';
import { MediaType } from '$lib/constants';

export type LatLng = { lng: number; lat: number };

export type QueueSnapshot = { timestamp: number; snapshot?: QueueResponseDto[] };

export type HeaderButtonActionItem = ActionItem & { data?: { title?: string } };

export enum UploadState {
  PENDING,
  STARTED,
  DONE,
  ERROR,
  DUPLICATED,
}

export type UploadAsset = {
  id: string;
  file: File;
  assetId?: string;
  isTrashed?: boolean;
  albumId?: string;
  progress?: number;
  state?: UploadState;
  startDate?: number;
  eta?: number;
  speed?: number;
  error?: unknown;
  message?: string;
};

export enum OnboardingRole {
  SERVER = 'server',
  USER = 'user',
}

export type SearchCameraFilter = {
  make?: string;
  model?: string;
  lensModel?: string;
};

export type SearchDateFilter = {
  takenBefore?: DateTime;
  takenAfter?: DateTime;
};

export type SearchDisplayFilters = {
  isNotInAlbum: boolean;
  isArchive: boolean;
  isFavorite: boolean;
};

export type SearchLocationFilter = {
  country?: string;
  state?: string;
  city?: string;
};

// fork: shared-libraries
export type SearchExposureFilter = {
  isoMin?: number;
  isoMax?: number;
  fNumberMin?: number;
  fNumberMax?: number;
  focalLengthMin?: number;
  focalLengthMax?: number;
};

// fork: shared-libraries
export type SearchFileFilter = {
  fileExtensions: string[];
  mimeTypes: string[];
  fileSizeMin?: number;
  fileSizeMax?: number;
  widthMin?: number;
  heightMin?: number;
  is360?: boolean;
  hasLocation?: boolean;
  fpsMin?: number;
  fpsMax?: number;
};

// fork: shared-libraries
export type SearchLibraryScope = 'all' | 'personal' | 'space' | 'library';

// fork: shared-libraries
export type SearchLibraryFilter = {
  scope: SearchLibraryScope;
  spaceId?: string;
  libraryId?: string;
};

export type SearchFilter = {
  query: string;
  ocr?: string;
  queryType: 'smart' | 'metadata' | 'description' | 'fullPath' | 'ocr';
  personIds: SvelteSet<string>;
  tagIds: SvelteSet<string> | null;
  location: SearchLocationFilter;
  queryAssetId?: string;
  camera: SearchCameraFilter;
  date: SearchDateFilter;
  display: SearchDisplayFilters;
  mediaType: MediaType;
  rating?: number | null;
  // fork: shared-libraries
  exposure: SearchExposureFilter;
  // fork: shared-libraries
  file: SearchFileFilter;
  // fork: shared-libraries
  library: SearchLibraryFilter;
};

export type JSONSchemaType = 'string' | 'number' | 'integer' | 'boolean' | 'object';

export type JSONSchemaProperty = {
  type: JSONSchemaType;
  title?: string;
  description?: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  default?: any;
  enum?: string[];
  minimum?: number;
  maximum?: number;
  precision?: number;
  array?: boolean;
  properties?: Record<string, JSONSchemaProperty>;
  required?: string[];
  uiHint?: {
    type?: 'AlbumId' | 'AssetId' | 'PersonId' | 'TagId';
    order?: number;
  };
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type SchemaConfig = any;
