import { DateTime } from 'luxon';
import type { ContainerScope } from 'src/utils/container-scope.js';
import { CalendarHeatmapDto } from 'src/dtos/calendar-heatmap.dto.js';
import { CalendarHeatmapType } from 'src/enum.js';
import { AssetRepository } from 'src/repositories/asset.repository.js';
import { asDateString } from 'src/utils/date.js';

export const getCalendarHeatmap = async (
  userId: string,
  dto: CalendarHeatmapDto,
  repos: { asset: AssetRepository },
  scope?: ContainerScope,
) => {
  const toDate = DateTime.fromJSDate(dto.to ?? new Date(), { zone: 'utc' }).startOf('day');
  const fromDate = (
    dto.from ? DateTime.fromJSDate(dto.from, { zone: 'utc' }) : toDate.minus({ weeks: 52 }).plus({ days: 1 })
  ).startOf('day');

  const options = {
    from: fromDate.toJSDate(),
    to: toDate.plus({ days: 1 }).toJSDate(),
    type: dto.type ?? CalendarHeatmapType.Upload,
  };
  const counts = scope
    ? await repos.asset.getCalendarHeatmap(userId, options, scope)
    : await repos.asset.getCalendarHeatmap(userId, options);
  const countsMap = new Map(counts.map((item) => [asDateString(item.date)!, item.count]));

  const series: Array<{ date: string; count: number }> = [];
  for (let date = fromDate; date <= toDate; date = date.plus({ days: 1 })) {
    const key = date.toISODate()!;
    series.push({ date: key, count: countsMap.get(key) ?? 0 });
  }

  return {
    from: fromDate.toISODate()!,
    to: toDate.toISODate()!,
    series,
    totalCount: series.reduce((totalCount, item) => totalCount + item.count, 0),
  };
};
