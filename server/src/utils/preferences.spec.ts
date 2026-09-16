import { UserMetadataKey } from 'src/enum.js';
import { getPreferences, getPreferencesPartial } from 'src/utils/preferences.js';

describe('shared library upload target preference (R3-01)', () => {
  it('persists a selected space id through a save/load round-trip', () => {
    const preferences = getPreferences([]);
    preferences.sharedLibraries.defaultUploadTarget = { type: 'space', spaceId: 'space-1' };

    const partial = getPreferencesPartial(preferences);
    expect(partial).toMatchObject({
      sharedLibraries: { defaultUploadTarget: { type: 'space', spaceId: 'space-1' } },
    });

    const restored = getPreferences([{ key: UserMetadataKey.Preferences, value: partial }]);
    expect(restored.sharedLibraries.defaultUploadTarget).toEqual({ type: 'space', spaceId: 'space-1' });
  });

  it('stores nothing for the default personal target', () => {
    expect(getPreferencesPartial(getPreferences([]))).toEqual({});
  });
});
