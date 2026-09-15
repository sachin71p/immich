import { createZodDto } from 'nestjs-zod';
import z from 'zod';
import { SharedSpaceRole } from 'src/enum.js';
import { isoDatetimeToDate } from 'src/validation.js';

const SharedSpaceRoleSchema = z.enum(SharedSpaceRole).meta({ id: 'SharedSpaceRole' });

const SharedSpaceCreateSchema = z
  .object({ name: z.string().trim().min(1), description: z.string().optional() })
  .meta({ id: 'SharedSpaceCreateDto' });

const SharedSpaceUpdateSchema = z
  .object({
    name: z.string().trim().min(1).optional(),
    description: z.string().optional(),
    thumbnailAssetId: z.uuidv4().nullable().optional(),
  })
  .meta({ id: 'SharedSpaceUpdateDto' });

const SharedSpaceMembersSchema = z
  .object({
    userIds: z
      .array(z.uuidv4())
      .min(1)
      .max(100)
      .refine((ids) => new Set(ids).size === ids.length),
  })
  .meta({ id: 'SharedSpaceMembersDto' });

const SharedSpaceOwnerSchema = z.object({ userId: z.uuidv4() }).meta({ id: 'SharedSpaceOwnerDto' });

const SharedSpaceTimelineSchema = z.object({ showInTimeline: z.boolean() }).meta({ id: 'SharedSpaceTimelineDto' });

const SharedSpaceMemberResponseSchema = z
  .object({
    userId: z.uuidv4(),
    role: SharedSpaceRoleSchema,
    showInTimeline: z.boolean(),
    createdAt: isoDatetimeToDate,
  })
  .meta({ id: 'SharedSpaceMemberResponseDto' });

const SharedSpaceResponseSchema = z
  .object({
    id: z.uuidv4(),
    name: z.string(),
    description: z.string(),
    role: SharedSpaceRoleSchema,
    memberCount: z.int(),
    assetCount: z.int(),
    showInTimeline: z.boolean(),
    thumbnailAssetId: z.uuidv4().nullable(),
    createdAt: isoDatetimeToDate,
    updatedAt: isoDatetimeToDate,
  })
  .meta({ id: 'SharedSpaceResponseDto' });

export class SharedSpaceCreateDto extends createZodDto(SharedSpaceCreateSchema) {}
export class SharedSpaceUpdateDto extends createZodDto(SharedSpaceUpdateSchema) {}
export class SharedSpaceMembersDto extends createZodDto(SharedSpaceMembersSchema) {}
export class SharedSpaceOwnerDto extends createZodDto(SharedSpaceOwnerSchema) {}
export class SharedSpaceTimelineDto extends createZodDto(SharedSpaceTimelineSchema) {}
export class SharedSpaceMemberResponseDto extends createZodDto(SharedSpaceMemberResponseSchema) {}
export class SharedSpaceResponseDto extends createZodDto(SharedSpaceResponseSchema) {}
