import { isEqual } from 'lodash-es';
import { PersistedLocalStorage } from '$lib/utils/persisted';

export type MemoriesPreferences = {
  showUpcoming: boolean;
  onlyFavorites: boolean;
};

class UserPreferencesManager {
  #showDetailPanel = new PersistedLocalStorage<boolean>('asset-viewer-state', false);
  #showAssetPath = new PersistedLocalStorage<boolean>('asset-viewer-show-path', false);
  #showAssetOwners = new PersistedLocalStorage<boolean>('album-show-asset-owners', false);
  // fork: shared-libraries — remembers the /photos library switcher selection ('all' | 'personal' | `space:<id>` | `library:<id>`)
  #timelineLibrarySource = new PersistedLocalStorage<string>('timeline-library-source', 'all');
  #defaultMemories: MemoriesPreferences = { showUpcoming: false, onlyFavorites: false };
  #memories = new PersistedLocalStorage<MemoriesPreferences>(
    'memories-settings',
    { ...this.#defaultMemories },
    {
      upgrade: 'merge',
    },
  );

  get showDetailPanel() {
    return this.#showDetailPanel.current;
  }

  set showDetailPanel(value: boolean) {
    this.#showDetailPanel.current = value;
  }

  get showAssetPath() {
    return this.#showAssetPath.current;
  }

  set showAssetPath(value: boolean) {
    this.#showAssetPath.current = value;
  }

  get showAssetOwners() {
    return this.#showAssetOwners.current;
  }

  set showAssetOwners(value: boolean) {
    this.#showAssetOwners.current = value;
  }

  get timelineLibrarySource() {
    return this.#timelineLibrarySource.current;
  }

  set timelineLibrarySource(value: string) {
    this.#timelineLibrarySource.current = value;
  }

  get memories() {
    return this.#memories.current;
  }

  set memories(value: MemoriesPreferences) {
    this.#memories.current = value;
  }

  hasMemoryPreferences() {
    return !isEqual(this.memories, this.#defaultMemories);
  }
}

export const userPreferencesManager = new UserPreferencesManager();
