// Whether a constraint touches an event, judged on the Israel wall clock.
//
// An event is one continuous stretch, from its start on the first day to its
// end on the last day, nights included. A constraint blocks when any of its
// intervals overlaps that stretch. Pure: index.ts turns Firestore documents
// into the inputs below. The Flutter app implements the same rule, and both
// run shared/test-fixtures/event_conflict_cases.json.
//
// A moment is minutes since 1970-01-01 00:00 of the Israel wall clock: an
// Israel calendar day (as UTC midnight, normalizeDayInIsrael's output) plus
// minutes since that midnight. DST therefore never shifts a comparison.
//
// An assignment can carry hours of its own (custom hours, stored as two
// 'yyyy-MM-ddTHH:mm' strings). Its window is those hours when they are usable
// (customHoursInterval) and the event's stretch otherwise; the same overlap
// rule then judges the member against that window.

export const MINUTES_PER_DAY = 24 * 60;
const MS_PER_MINUTE = 60 * 1000;

/** Minutes on the Israel wall clock, half-open: [start, end). */
export interface WallInterval {
  start: number;
  end: number;
}

/** Days are UTC midnight of the Israel calendar day. */
export interface StretchEventInput {
  firstDay: Date;
  lastDay: Date;
  assemblyTime?: string | null;
  startTime?: string | null;
  endTime?: string | null;
  teamEndTime?: string | null;
}

/**
 * Days are UTC midnight of the Israel calendar day. For a weekly repeat,
 * repeatDay is 1 = Monday … 7 = Sunday; for a monthly one, the day of month.
 */
export interface StretchConstraintInput {
  firstDay: Date;
  lastDay: Date;
  startTime: string | null;
  endTime: string | null;
  repeatType: 'daily' | 'weekly' | 'monthly' | null;
  repeatDay: number | null;
  repeatEndDay: Date | null;
}

/**
 * Minutes since midnight of an `HH:mm` time, hours 0–23 and minutes 0–59.
 * Anything else ('', '24:00', '9:00 ', null) is missing: null, never a throw.
 */
export function wallTimeMinutes(value: string | null | undefined): number | null {
  if (typeof value !== 'string') return null;
  const match = /^(\d{2}):(\d{2})$/.exec(value);
  if (match == null) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours > 23 || minutes > 59) return null;
  return hours * 60 + minutes;
}

function dayMinutes(day: Date): number {
  return Math.round(day.getTime() / MS_PER_MINUTE);
}

/**
 * The event's stretch:
 * - start: the first day at assemblyTime, else startTime, else 00:00;
 * - end: the last day at teamEndTime, else endTime, else 24:00;
 * - a one-day event whose end is not after its start ends the next day;
 * - a multi-day event is read literally;
 * - a last day before the first day (bad data) is taken as the first day.
 */
export function eventStretch(event: StretchEventInput): WallInterval {
  const firstDay = dayMinutes(event.firstDay);
  const lastDay = Math.max(firstDay, dayMinutes(event.lastDay));
  const start =
    firstDay +
    (wallTimeMinutes(event.assemblyTime) ?? wallTimeMinutes(event.startTime) ?? 0);
  let end =
    lastDay +
    (wallTimeMinutes(event.teamEndTime) ?? wallTimeMinutes(event.endTime) ?? MINUTES_PER_DAY);
  if (lastDay === firstDay && end <= start) {
    end += MINUTES_PER_DAY;
  }
  return {start, end};
}

/**
 * From `startTime` on `firstDay` to `endTime` on `lastDay`; a missing start is
 * 00:00 and a missing end is 24:00. An end not after its start rolls to the
 * next day.
 */
function timeWindow(firstDay: number, lastDay: number, startTime: string | null, endTime: string | null): WallInterval {
  const start = firstDay + (wallTimeMinutes(startTime) ?? 0);
  let end = lastDay + (wallTimeMinutes(endTime) ?? MINUTES_PER_DAY);
  if (end <= start) {
    end += MINUTES_PER_DAY;
  }
  return {start, end};
}

/** 1 = Monday … 7 = Sunday, like the client's DateTime.weekday. */
function isoWeekday(dayStart: number): number {
  const weekday = new Date(dayStart * MS_PER_MINUTE).getUTCDay();
  return weekday === 0 ? 7 : weekday;
}

function recurrenceMatches(constraint: StretchConstraintInput, dayStart: number): boolean {
  switch (constraint.repeatType) {
    case 'daily':
      return true;
    case 'weekly':
      return constraint.repeatDay === isoWeekday(dayStart);
    case 'monthly':
      return constraint.repeatDay === new Date(dayStart * MS_PER_MINUTE).getUTCDate();
    default:
      return false;
  }
}

/**
 * The constraint's intervals that can reach `stretch`:
 * - one-time: one interval, from startTime on its first day to endTime on its
 *   last day (the whole days without hours). A last day before the first day
 *   (bad data) is taken as the first day, as on the event side;
 * - recurring: one interval on each matching day between its first day and
 *   repeatEndDay, the whole day or startTime→endTime. A null repeatEndDay
 *   matches nothing.
 */
export function constraintIntervalsNear(
  constraint: StretchConstraintInput,
  stretch: WallInterval,
): WallInterval[] {
  const firstDay = dayMinutes(constraint.firstDay);
  if (constraint.repeatType == null) {
    const lastDay = Math.max(firstDay, dayMinutes(constraint.lastDay));
    return [timeWindow(firstDay, lastDay, constraint.startTime, constraint.endTime)];
  }
  if (constraint.repeatEndDay == null) {
    return [];
  }
  const repeatEndDay = dayMinutes(constraint.repeatEndDay);
  // An occurrence can roll into the next day, so start one day before the
  // stretch's first day.
  const from = Math.max(firstDay, Math.floor(stretch.start / MINUTES_PER_DAY) * MINUTES_PER_DAY - MINUTES_PER_DAY);
  const to = Math.min(repeatEndDay, Math.floor(stretch.end / MINUTES_PER_DAY) * MINUTES_PER_DAY);
  const intervals: WallInterval[] = [];
  for (let day = from; day <= to; day += MINUTES_PER_DAY) {
    if (recurrenceMatches(constraint, day)) {
      intervals.push(timeWindow(day, day, constraint.startTime, constraint.endTime));
    }
  }
  return intervals;
}

/** Half-open overlap: touching is not a conflict. */
export function constraintOverlapsStretch(
  constraint: StretchConstraintInput,
  stretch: WallInterval,
): boolean {
  return constraintIntervalsNear(constraint, stretch).some(
    (interval) => interval.start < stretch.end && stretch.start < interval.end,
  );
}

/** A wall-clock moment as 'yyyy-MM-ddTHH:mm'. */
export function formatWallMinutes(minutes: number): string {
  return new Date(minutes * MS_PER_MINUTE).toISOString().slice(0, 16);
}

/**
 * A stored 'yyyy-MM-ddTHH:mm' as minutes on the wall clock (the same scale as
 * WallInterval). Strict: a real calendar date, hours 0–23, minutes 0–59.
 * Anything else ('2026-02-30T10:00', '…T24:00', '…T9:00', a space for the T, a
 * non-string) is null, never a throw. The Flutter app's parseWallMoment reads
 * the same way.
 */
export function parseWallMoment(value: unknown): number | null {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(value);
  if (match == null) return null;
  const [year, month, day, hours, minutes] = match.slice(1).map(Number);
  if (hours > 23 || minutes > 59) return null;
  // setUTCFullYear, not Date.UTC: Date.UTC maps years 0–99 to 1900–1999.
  const moment = new Date(0);
  moment.setUTCFullYear(year, month - 1, day);
  moment.setUTCHours(hours, minutes, 0, 0);
  // Date rolls 30 February into March; a real date round-trips.
  if (moment.getUTCFullYear() !== year || moment.getUTCMonth() !== month - 1 || moment.getUTCDate() !== day) {
    return null;
  }
  return Math.round(moment.getTime() / MS_PER_MINUTE);
}

/**
 * An assignment's own hours as an interval: non-null only when both values
 * parse (parseWallMoment) and the end is after the start.
 */
export function customHoursInterval(start: unknown, end: unknown): WallInterval | null {
  const startMinutes = parseWallMoment(start);
  const endMinutes = parseWallMoment(end);
  if (startMinutes == null || endMinutes == null || endMinutes <= startMinutes) return null;
  return {start: startMinutes, end: endMinutes};
}

/**
 * `value` moved by `days` whole calendar days, the clock unchanged (the wall
 * clock has no DST here), or null when `value` is unreadable.
 */
export function shiftWallMoment(value: string, days: number): string | null {
  const minutes = parseWallMoment(value);
  if (minutes == null) return null;
  return formatWallMinutes(minutes + days * MINUTES_PER_DAY);
}

/**
 * The 'yyyy-MM-dd' keys of the days an interval touches: its start's day and
 * the day of its last minute (end - 1 minute), so an interval ending exactly
 * at midnight does not touch the next day.
 */
export function wallDayKeysTouched(interval: WallInterval): [string, string] {
  return [formatWallMinutes(interval.start).slice(0, 10), formatWallMinutes(interval.end - 1).slice(0, 10)];
}
