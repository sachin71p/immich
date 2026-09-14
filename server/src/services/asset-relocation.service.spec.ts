import { isPathInside } from 'src/services/asset-relocation.service.js';

describe('asset relocation import-path guard', () => {
  it('requires an actual import-path boundary', () => {
    expect(isPathInside('/imports/foo/asset.jpg', '/imports/foo')).toBe(true);
    expect(isPathInside('/imports/foo2/asset.jpg', '/imports/foo')).toBe(false);
  });
});
