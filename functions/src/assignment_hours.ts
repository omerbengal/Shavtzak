// Custom hours on assignments: their shape, and the rule that one member has
// one set of hours per event.
//
// An assignment may carry `customStartAt` and `customEndAt`, two Israel
// wall-clock strings 'yyyy-MM-ddTHH:mm' (event_stretch.ts reads them). Every
// assignment of one member in one event must carry the same pair, null
// included, unless the member has allowMultipleAssignments (a placeholder
// whose slots are different people). Pure: index.ts reads Firestore and
// throws.

import {Timestamp} from 'firebase-admin/firestore';

import {customHoursInterval, parseWallMoment} from './event_stretch';
import {eventLocalDays} from './stages';

/** One assignment, reduced to what the shared-hours rule looks at. */
export interface HoursRow {
  id: string;
  eventId: string;
  teamMemberId: string;
  customStartAt: string | null;
  customEndAt: string | null;
}

/**
 * - 'none': both values are null or undefined;
 * - 'incomplete': exactly one value is there, or either one is unreadable;
 * - 'order': the end is not after the start;
 * - 'ok': both parse and the end is after the start.
 */
export function validateCustomHoursPair(
  start: unknown,
  end: unknown,
): 'none' | 'ok' | 'incomplete' | 'order' {
  if (start == null && end == null) return 'none';
  const startMinutes = parseWallMoment(start);
  const endMinutes = parseWallMoment(end);
  if (startMinutes == null || endMinutes == null) return 'incomplete';
  return endMinutes > startMinutes ? 'ok' : 'order';
}

/**
 * The (event, member) groups whose rows carry more than one distinct
 * (customStartAt, customEndAt) pair; null is a value like any other. Exempt
 * members are skipped. With `touchedIds`, only groups holding a touched row
 * count: a write is not blamed for a group it never touched.
 */
export function findSharedHoursViolations(
  rows: HoursRow[],
  exemptMemberIds: ReadonlySet<string>,
  touchedIds?: ReadonlySet<string>,
): Array<{eventId: string; teamMemberId: string}> {
  const groups = new Map<
    string,
    {eventId: string; teamMemberId: string; pairs: Set<string>; touched: boolean}
  >();
  for (const row of rows) {
    if (exemptMemberIds.has(row.teamMemberId)) continue;
    // NUL never occurs inside a Firestore id, so the key is unambiguous.
    const key = `${row.eventId}\u0000${row.teamMemberId}`;
    let group = groups.get(key);
    if (group == null) {
      group = {eventId: row.eventId, teamMemberId: row.teamMemberId, pairs: new Set(), touched: false};
      groups.set(key, group);
    }
    // JSON keeps null apart from the string 'null'.
    group.pairs.add(JSON.stringify([row.customStartAt, row.customEndAt]));
    if (touchedIds?.has(row.id)) group.touched = true;
  }
  return Array.from(groups.values())
    .filter((group) => group.pairs.size > 1 && (touchedIds == null || group.touched))
    .map(({eventId, teamMemberId}) => ({eventId, teamMemberId}));
}

/**
 * The hours of the member's first assignment in the event whose hours are
 * usable (customHoursInterval), or null when none has any.
 */
export function inheritedHours(
  rows: HoursRow[],
  eventId: string,
  teamMemberId: string,
): {customStartAt: string; customEndAt: string} | null {
  for (const row of rows) {
    if (row.eventId !== eventId || row.teamMemberId !== teamMemberId) continue;
    if (customHoursInterval(row.customStartAt, row.customEndAt) == null) continue;
    return {customStartAt: row.customStartAt as string, customEndAt: row.customEndAt as string};
  }
  return null;
}

/** A stored hours value as the rule sees it: the string, else null. */
function hoursValue(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

/**
 * A stored assignment as a row, or null when it names no event or member
 * (bad data is skipped, never thrown on). Absent or non-string hours are null.
 */
export function hoursRowFromDoc(id: string, data: Record<string, unknown>): HoursRow | null {
  const eventId = data['eventId'];
  const teamMemberId = data['teamMemberId'];
  if (typeof eventId !== 'string' || typeof teamMemberId !== 'string') return null;
  return {
    id,
    eventId,
    teamMemberId,
    customStartAt: hoursValue(data['customStartAt']),
    customEndAt: hoursValue(data['customEndAt']),
  };
}

/**
 * The rows once a set of writes applies: deletes first, then updates, then
 * creates. An update takes its event and member from its doc, and its hours
 * from the keys its doc carries, the stored row's hours where a key is
 * absent. A create's absent key is null. `live` must hold every stored row
 * an update rewrites.
 */
export function hoursAfterWrites(args: {
  live: HoursRow[];
  creates?: Array<{id: string; doc: Record<string, unknown>}>;
  updates?: Array<{id: string; doc: Record<string, unknown>}>;
  deletes?: string[];
}): HoursRow[] {
  const rows = new Map<string, HoursRow>(args.live.map((row) => [row.id, row]));
  for (const id of args.deletes ?? []) {
    rows.delete(id);
  }
  for (const {id, doc} of args.updates ?? []) {
    const stored = rows.get(id);
    rows.set(id, {
      id,
      eventId: String(doc['eventId']),
      teamMemberId: String(doc['teamMemberId']),
      customStartAt: 'customStartAt' in doc ? hoursValue(doc['customStartAt']) : stored?.customStartAt ?? null,
      customEndAt: 'customEndAt' in doc ? hoursValue(doc['customEndAt']) : stored?.customEndAt ?? null,
    });
  }
  for (const {id, doc} of args.creates ?? []) {
    rows.set(id, {
      id,
      eventId: String(doc['eventId']),
      teamMemberId: String(doc['teamMemberId']),
      customStartAt: hoursValue(doc['customStartAt']),
      customEndAt: hoursValue(doc['customEndAt']),
    });
  }
  return Array.from(rows.values());
}

/** The five times of an event; with its two dates they place it in time. */
const EVENT_TIME_FIELDS = ['assemblyTime', 'startTime', 'actualShowStartTime', 'endTime', 'teamEndTime'];

/**
 * Whether a save moves the event in time: its first or last day, or any of
 * its five times, differs. Days compare as Israel calendar days (an event
 * stores a day as the Timestamp of Israel midnight); times as trimmed strings,
 * an absent one being ''. The name, location and every other field never count.
 */
export function eventTimesChanged(before: Record<string, unknown>, after: Record<string, unknown>): boolean {
  if (israelDayKey(before['startDate']) !== israelDayKey(after['startDate'])) return true;
  if (israelDayKey(before['endDate']) !== israelDayKey(after['endDate'])) return true;
  return EVENT_TIME_FIELDS.some((field) => trimmedText(before[field]) !== trimmedText(after[field]));
}

/** A stored day as its Israel 'yyyy-MM-dd', or '' when it is not a Timestamp. */
function israelDayKey(value: unknown): string {
  return value instanceof Timestamp ? eventLocalDays(value.toMillis(), null)[0] : '';
}

function trimmedText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/** The hours an event save gives one assignment; null clears them. */
export interface HoursResolution {
  assignmentId: string;
  customStartAt: string | null;
  customEndAt: string | null;
}

/** Whether a row stores hours, readable or not. */
export function rowHasHours(row: HoursRow): boolean {
  return row.customStartAt != null || row.customEndAt != null;
}

/**
 * The assignment hours an event.update writes along with the event. `live` is
 * every assignment of the event, read in the same transaction.
 * - Times unchanged: nothing, and the resolutions are ignored.
 * - Times changed: every row that stores hours needs a resolution, else
 *   'uncovered' (hours were added after the client opened the event).
 *   Resolutions for rows no longer in the event are dropped; of two for one
 *   row, the later wins. Each pair must be 'none' or 'ok', else 'invalid', and
 *   the rows after them must pass findSharedHoursViolations, else 'shared'.
 */
export function planEventHoursResolution(args: {
  timesChanged: boolean;
  live: HoursRow[];
  resolutions: HoursResolution[];
  exemptMemberIds: ReadonlySet<string>;
}): {ok: true; updates: HoursResolution[]} | {ok: false; reason: 'uncovered' | 'invalid' | 'shared'} {
  if (!args.timesChanged) return {ok: true, updates: []};
  const liveIds = new Set(args.live.map((row) => row.id));
  const resolved = new Map<string, HoursResolution>();
  for (const resolution of args.resolutions) {
    if (liveIds.has(resolution.assignmentId)) resolved.set(resolution.assignmentId, resolution);
  }
  if (args.live.some((row) => rowHasHours(row) && !resolved.has(row.id))) {
    return {ok: false, reason: 'uncovered'};
  }
  const updates = Array.from(resolved.values());
  const invalid = updates.some((resolution) => {
    const verdict = validateCustomHoursPair(resolution.customStartAt, resolution.customEndAt);
    return verdict !== 'none' && verdict !== 'ok';
  });
  if (invalid) return {ok: false, reason: 'invalid'};
  const after = args.live.map((row) => {
    const resolution = resolved.get(row.id);
    return resolution == null
      ? row
      : {...row, customStartAt: resolution.customStartAt, customEndAt: resolution.customEndAt};
  });
  if (findSharedHoursViolations(after, args.exemptMemberIds).length > 0) {
    return {ok: false, reason: 'shared'};
  }
  return {ok: true, updates};
}
