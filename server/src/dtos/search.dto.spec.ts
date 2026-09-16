import { MetadataSearchDto } from 'src/dtos/search.dto.js';
import { newUuid } from 'test/small.factory.js';

describe('[R8-04] container filter exclusivity', () => {
  const spaceId = newUuid();
  const libraryId = newUuid();

  it('rejects two container filters at once', () => {
    for (const dto of [
      { spaceId, libraryId },
      { spaceId, personalOnly: true },
      { libraryId, personalOnly: false },
    ]) {
      const result = MetadataSearchDto.schema.safeParse(dto);
      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.issues.map((issue) => issue.message)).toContain(
          'spaceId, libraryId, and personalOnly are mutually exclusive',
        );
      }
    }
  });

  it('accepts a single container filter', () => {
    expect(MetadataSearchDto.schema.safeParse({ spaceId }).success).toBe(true);
    expect(MetadataSearchDto.schema.safeParse({ libraryId }).success).toBe(true);
    expect(MetadataSearchDto.schema.safeParse({ personalOnly: true }).success).toBe(true);
  });
});
