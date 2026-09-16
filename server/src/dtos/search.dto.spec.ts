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

describe('[S10] S7 numeric filter formats', () => {
  const doubleFields = ['fNumberMin', 'fNumberMax', 'focalLengthMin', 'focalLengthMax', 'fpsMin', 'fpsMax'] as const;

  it('declares format double so OpenAPI regen passes validation', () => {
    for (const field of doubleFields) {
      const meta = (
        MetadataSearchDto.schema.shape[field] as unknown as { meta(): { format?: string; deprecated?: boolean } }
      ).meta();
      expect(meta?.format).toBe('double');
      expect(meta?.deprecated).toBe(true);
    }
  });

  it('still accepts fractional values and rejects negatives', () => {
    for (const field of doubleFields) {
      expect(MetadataSearchDto.schema.safeParse({ [field]: 1.8 }).success).toBe(true);
      expect(MetadataSearchDto.schema.safeParse({ [field]: -1 }).success).toBe(false);
    }
  });
});
