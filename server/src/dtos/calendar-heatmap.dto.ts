import { createZodDto } from 'nestjs-zod';
import z from 'zod';
import { CalendarHeatmapType } from 'src/enum.js';
import { isoDateToDate, stringToBool } from 'src/validation.js';

const CalendarHeatmapTypeSchema = z
  .enum(CalendarHeatmapType)
  .describe('Type of calendar heatmap')
  .meta({ id: 'CalendarHeatmapType' });

const CalendarHeatmapSchema = z
  .object({
    from: isoDateToDate.optional().describe('Start date in UTC'),
    to: isoDateToDate.optional().describe('End date in UTC'),
    type: CalendarHeatmapTypeSchema.optional().default(CalendarHeatmapType.Upload),
    // fork: shared-libraries
    spaceId: z.uuidv4().optional().describe('Filter heatmap by a shared space'),
    libraryId: z.uuidv4().optional().describe('Filter heatmap by a library'),
    personalOnly: stringToBool.optional().describe('Only include personal assets'),
  })
  .refine((dto) => !dto.from || !dto.to || dto.from <= dto.to, { message: 'from must be before to', path: ['from'] })
  .refine((dto) => [dto.spaceId, dto.libraryId, dto.personalOnly].filter((value) => value !== undefined).length <= 1, {
    message: 'spaceId, libraryId, and personalOnly are mutually exclusive',
  })
  .meta({ id: 'CalendarHeatmapDto' });

export class CalendarHeatmapDto extends createZodDto(CalendarHeatmapSchema) {}

const CalendarHeatmapResponseSchema = z
  .object({
    from: z.string().describe('Start date in UTC').meta({ example: '2024-01-01' }),
    to: z.string().describe('End date in UTC').meta({ example: '2024-12-31' }),
    series: z.array(
      z.object({
        date: z.string().describe('Date in UTC').meta({ example: '2024-01-01' }),
        count: z.int().nonnegative().describe('Activity count'),
      }),
    ),
    totalCount: z.int().nonnegative().describe('Total activity count over the period'),
  })
  .meta({ id: 'CalendarHeatmapResponseDto' });

export class CalendarHeatmapResponseDto extends createZodDto(CalendarHeatmapResponseSchema) {}
