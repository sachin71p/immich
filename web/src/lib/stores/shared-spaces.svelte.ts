import * as sdk from '@immich/sdk';

/**
 * Small client cache shared by the sidebar, settings and shared-library pages.
 * The API is intentionally fetched on the client: membership can change while a
 * user stays on a page and the next phase consumes this same cache.
 */
class SharedSpacesStore {
  spaces = $state<sdk.SharedSpaceResponseDto[]>([]);
  libraries = $state<sdk.SharedLibraryResponseDto[]>([]);
  loading = $state(false);
  loaded = $state(false);

  async refresh() {
    this.loading = true;
    try {
      const [spaces, libraries] = await Promise.all([sdk.getAll(), sdk.getSharedLibraries()]);
      this.spaces = spaces;
      this.libraries = libraries;
      this.loaded = true;
    } finally {
      this.loading = false;
    }
  }

  async ensureLoaded() {
    if (!this.loaded && !this.loading) {
      await this.refresh();
    }
  }

  upsert(space: sdk.SharedSpaceResponseDto) {
    const index = this.spaces.findIndex(({ id }) => id === space.id);
    this.spaces = index === -1 ? [...this.spaces, space] : this.spaces.map((item) => (item.id === space.id ? space : item));
  }

  remove(id: string) {
    this.spaces = this.spaces.filter((space) => space.id !== id);
  }
}

export const sharedSpaces = new SharedSpacesStore();
