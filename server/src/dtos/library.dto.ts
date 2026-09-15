import { createZodDto } from 'nestjs-zod';
import z from 'zod';
import { Library } from 'src/database.js';
import { isoDatetimeToDate } from 'src/validation.js';

const stringArrayMax128 = z
  .array(z.string())
  .max(128)
  .refine((arr) => arr.every((s) => s.trim() !== ''), 'Array items must not be empty')
  .refine((arr) => new Set(arr).size === arr.length, 'Array must have unique items');

const CreateLibrarySchema = z
  .object({
    ownerId: z.uuidv4().describe('Owner user ID'),
    name: z.string().min(1).optional().describe('Library name'),
    importPaths: stringArrayMax128.optional().describe('Import paths (max 128)'),
    exclusionPatterns: stringArrayMax128.optional().describe('Exclusion patterns (max 128)'),
  })
  .meta({ id: 'CreateLibraryDto' });

const UpdateLibrarySchema = z
  .object({
    name: z.string().min(1).optional().describe('Library name'),
    importPaths: stringArrayMax128.optional().describe('Import paths (max 128)'),
    exclusionPatterns: stringArrayMax128.optional().describe('Exclusion patterns (max 128)'),
    // fork: shared-libraries
    uploadPath: z.string().nullable().optional().describe('Writable upload path inside an import path'),
  })
  .meta({ id: 'UpdateLibraryDto' });

// fork: shared-libraries
const LibraryMembersSchema = z
  .object({
    userIds: z
      .array(z.uuidv4())
      .min(1)
      .max(100)
      .refine((ids) => new Set(ids).size === ids.length),
  })
  .meta({ id: 'LibraryMembersDto' });

const LibraryTimelineSchema = z.object({ showInTimeline: z.boolean() }).meta({ id: 'LibraryTimelineDto' });

const LibraryMemberResponseSchema = z
  .object({ userId: z.uuidv4(), showInTimeline: z.boolean(), createdAt: isoDatetimeToDate })
  .meta({ id: 'LibraryMemberResponseDto' });

const SharedLibraryResponseSchema = z
  .object({
    id: z.uuidv4(),
    name: z.string(),
    ownerId: z.uuidv4(),
    isOwner: z.boolean(),
    showInTimeline: z.boolean(),
    assetCount: z.int(),
    hasUploadPath: z.boolean(),
  })
  .meta({ id: 'SharedLibraryResponseDto' });

export interface CrawlOptionsDto {
  pathsToCrawl: string[];
  includeHidden?: boolean;
  exclusionPatterns?: string[];
}

export interface WalkOptionsDto extends CrawlOptionsDto {
  take: number;
}

const ValidateLibrarySchema = z
  .object({
    importPaths: stringArrayMax128.optional().describe('Import paths to validate (max 128)'),
    exclusionPatterns: stringArrayMax128.optional().describe('Exclusion patterns (max 128)'),
  })
  .meta({ id: 'ValidateLibraryDto' });

const ValidateLibraryImportPathResponseSchema = z
  .object({
    importPath: z.string().describe('Import path'),
    isValid: z.boolean().describe('Is valid'),
    message: z.string().optional().describe('Validation message'),
  })
  .meta({ id: 'ValidateLibraryImportPathResponseDto' });

const ValidateLibraryResponseSchema = z
  .object({
    importPaths: z
      .array(ValidateLibraryImportPathResponseSchema)
      .optional()
      .describe('Validation results for import paths'),
  })
  .meta({ id: 'ValidateLibraryResponseDto' });

const LibraryResponseSchema = z
  .object({
    id: z.uuidv4().describe('Library ID'),
    ownerId: z.uuidv4().describe('Owner user ID'),
    name: z.string().describe('Library name'),
    assetCount: z.int().describe('Number of assets'),
    importPaths: z.array(z.string()).describe('Import paths'),
    exclusionPatterns: z.array(z.string()).describe('Exclusion patterns'),
    createdAt: isoDatetimeToDate.describe('Creation date'),
    updatedAt: isoDatetimeToDate.describe('Last update date'),
    refreshedAt: isoDatetimeToDate.nullable().describe('Last refresh date'),
  })
  .meta({ id: 'LibraryResponseDto' });

const LibraryStatsResponseSchema = z
  .object({
    photos: z.int().describe('Number of photos'),
    videos: z.int().describe('Number of videos'),
    total: z.int().describe('Total number of assets'),
    usage: z.int().describe('Storage usage in bytes'),
  })
  .meta({ id: 'LibraryStatsResponseDto' });

export class CreateLibraryDto extends createZodDto(CreateLibrarySchema) {}
export class UpdateLibraryDto extends createZodDto(UpdateLibrarySchema) {}
export class LibraryMembersDto extends createZodDto(LibraryMembersSchema) {}
export class LibraryTimelineDto extends createZodDto(LibraryTimelineSchema) {}
export class LibraryMemberResponseDto extends createZodDto(LibraryMemberResponseSchema) {}
export class SharedLibraryResponseDto extends createZodDto(SharedLibraryResponseSchema) {}
export class ValidateLibraryDto extends createZodDto(ValidateLibrarySchema) {}
export class ValidateLibraryResponseDto extends createZodDto(ValidateLibraryResponseSchema) {}
export class ValidateLibraryImportPathResponseDto extends createZodDto(ValidateLibraryImportPathResponseSchema) {}
export class LibraryResponseDto extends createZodDto(LibraryResponseSchema) {}
export class LibraryStatsResponseDto extends createZodDto(LibraryStatsResponseSchema) {}

export function mapLibrary(entity: Library): LibraryResponseDto {
  const assetCount = entity.assets ? entity.assets.length : 0;
  return {
    id: entity.id,
    ownerId: entity.ownerId,
    name: entity.name,
    createdAt: entity.createdAt,
    updatedAt: entity.updatedAt,
    refreshedAt: entity.refreshedAt,
    assetCount,
    importPaths: entity.importPaths,
    exclusionPatterns: entity.exclusionPatterns,
  };
}
