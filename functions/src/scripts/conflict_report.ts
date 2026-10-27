// Read-only before/after report of the conflict check on pulled data.
//
// For every assignment on an event that hasn't ended, asks two builds of the
// backend whether the member is free for the event: the old rule (a build of
// main) and the new one (this build). Writes a CSV of every assignment whose
// answer changes, with the constraint responsible and a reason category.
//
// Pure local computation over JSON files pulled from Firestore (each
// `{"documents": [...]}`, Timestamps as `{"__type__": "Timestamp", "value"}`).
// It never touches Firebase: the builds' index.js files are only loaded for
// their exported pure functions.
//
// Usage (from functions/):
//   npx tsx src/scripts/conflict_report.ts --old <old>/lib/index.js \
//     --new lib/index.js --events <f> --assignments <f> --members <f> \
//     --today 2026-10-26 --out <csv>

import {readFileSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {homedir} from 'node:os';
import * as path from 'node:path';

type Doc = Record<string, unknown>;
type Outcome = 'free' | 'blocked' | 'error';
type MemberAvailableForEvent = (member: Doc, event: Doc) => boolean;

interface WallInterval {
  start: number;
  end: number;
}

interface StretchConstraintInput {
  firstDay: Date;
  lastDay: Date;
  startTime: string | null;
  endTime: string | null;
  repeatType: 'daily' | 'weekly' | 'monthly' | null;
  repeatDay: number | null;
  repeatEndDay: Date | null;
}

interface Build {
  memberAvailableForEvent: MemberAvailableForEvent;
  makeTimestamp: (date: Date) => unknown;
}

interface NewBuildExtras {
  eventStretchFromData: (event: Doc) => WallInterval;
  normalizeDayInIsrael: (date: Date) => Date;
  formatWallMinutes: (minutes: number) => string;
  wallTimeMinutes: (value: string | null | undefined) => number | null;
  constraintIntervalsNear: (constraint: StretchConstraintInput, stretch: WallInterval) => WallInterval[];
}

const MINUTES_PER_DAY = 24 * 60;
const OUTCOME_LABEL: Record<Outcome, string> = {
  free: 'פנוי',
  blocked: 'חסום',
  error: 'שגיאה',
};
const CATEGORIES = [
  'pending now counts',
  'recurring',
  'missing time',
  'past midnight',
  'team end',
  'night',
  'now free',
  'other',
] as const;
type Category = (typeof CATEGORIES)[number];

function parseArgs(argv: string[]): Record<string, string> {
  const args: Record<string, string> = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    const value = argv[i + 1];
    if (!key.startsWith('--') || value == null) {
      throw new Error(`Bad argument near "${key}"`);
    }
    args[key.slice(2)] = value;
  }
  for (const required of ['old', 'new', 'events', 'assignments', 'members', 'today', 'out']) {
    if (args[required] == null) {
      throw new Error(`Missing --${required}`);
    }
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(args['today'])) {
    throw new Error('--today must be yyyy-MM-dd');
  }
  return args;
}

function expandHome(filePath: string): string {
  return filePath.startsWith('~/') ? path.join(homedir(), filePath.slice(2)) : path.resolve(filePath);
}

// Each build loads its own firebase-admin, so a Timestamp must come from the
// build that reads it (asDate checks `instanceof Timestamp`).
function loadBuild(indexPath: string): {
  build: Build;
  exported: Record<string, unknown>;
  load: ReturnType<typeof createRequire>;
} {
  const load = createRequire(indexPath);
  const exported = load(indexPath) as Record<string, unknown>;
  const memberAvailableForEvent = exported['__testMemberAvailableForEvent'];
  if (typeof memberAvailableForEvent !== 'function') {
    throw new Error(`${indexPath} does not export __testMemberAvailableForEvent`);
  }
  const firestore = load('firebase-admin/firestore') as {Timestamp: {fromDate(date: Date): unknown}};
  return {
    build: {
      memberAvailableForEvent: memberAvailableForEvent as MemberAvailableForEvent,
      makeTimestamp: (date) => firestore.Timestamp.fromDate(date),
    },
    exported,
    load,
  };
}

function readDocuments(filePath: string): Doc[] {
  const parsed = JSON.parse(readFileSync(filePath, 'utf8')) as {documents?: Doc[]};
  if (!Array.isArray(parsed.documents)) {
    throw new Error(`${filePath} has no "documents" array`);
  }
  return parsed.documents;
}

function documentId(doc: Doc): string {
  const docPath = doc['__path__'];
  if (typeof docPath === 'string') {
    return docPath.split('/').pop() as string;
  }
  return String(doc['id']);
}

/** The stored fields as Firestore would hand them over, minus `__path__`. */
function revive(value: unknown, makeTimestamp: (date: Date) => unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => revive(item, makeTimestamp));
  }
  if (value !== null && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    if (record['__type__'] === 'Timestamp' && typeof record['value'] === 'string') {
      return makeTimestamp(new Date(record['value']));
    }
    const result: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(record)) {
      if (key === '__path__') continue;
      result[key] = revive(item, makeTimestamp);
    }
    return result;
  }
  return value;
}

function rawDate(value: unknown): Date | null {
  if (value == null) return null;
  if (typeof value === 'string') return new Date(value);
  if (typeof value === 'object' && (value as Doc)['__type__'] === 'Timestamp') {
    return new Date((value as Doc)['value'] as string);
  }
  return null;
}

function ask(build: Build, member: Doc, event: Doc): {outcome: Outcome; error?: string} {
  try {
    return {outcome: build.memberAvailableForEvent(member, event) ? 'free' : 'blocked'};
  } catch (error) {
    return {outcome: 'error', error: error instanceof Error ? error.message : String(error)};
  }
}

function main(): void {
  // The deployed functions run in UTC, and constraint dates are stored as
  // strings without an offset ('2026-02-19T00:00:00.000'), which Date parses
  // in local time. Pin UTC so both builds read them as production does.
  process.env.TZ = 'UTC';
  if (new Date('2026-01-01T00:00:00.000').getTime() !== Date.UTC(2026, 0, 1)) {
    throw new Error('Could not pin TZ=UTC; run with TZ=UTC');
  }
  const args = parseArgs(process.argv.slice(2));
  const today = args['today'];

  const oldSide = loadBuild(path.resolve(args['old']));
  const newSide = loadBuild(path.resolve(args['new']));
  const stretchModule = newSide.load(path.join(path.dirname(path.resolve(args['new'])), 'event_stretch.js')) as Record<
    string,
    unknown
  >;
  const extras: NewBuildExtras = {
    eventStretchFromData: newSide.exported['__testEventStretchFromData'] as NewBuildExtras['eventStretchFromData'],
    normalizeDayInIsrael: newSide.exported['__testNormalizeDayInIsrael'] as NewBuildExtras['normalizeDayInIsrael'],
    formatWallMinutes: stretchModule['formatWallMinutes'] as NewBuildExtras['formatWallMinutes'],
    wallTimeMinutes: stretchModule['wallTimeMinutes'] as NewBuildExtras['wallTimeMinutes'],
    constraintIntervalsNear: stretchModule['constraintIntervalsNear'] as NewBuildExtras['constraintIntervalsNear'],
  };
  for (const [name, fn] of Object.entries(extras)) {
    if (typeof fn !== 'function') {
      throw new Error(`The new build does not export ${name}`);
    }
  }

  const israelDay = (date: Date): string => extras.normalizeDayInIsrael(date).toISOString().slice(0, 10);

  const events = new Map(readDocuments(args['events']).map((doc) => [documentId(doc), doc]));
  const members = new Map(readDocuments(args['members']).map((doc) => [documentId(doc), doc]));
  const assignments = readDocuments(args['assignments']);

  const skipped = {
    eventMissingOrUndated: 0,
    eventEnded: 0,
    deactivated: 0,
    memberMissing: 0,
    multipleAssignmentsMember: 0,
  };
  const transitions = new Map<string, number>();
  const categoryCounts = new Map<Category, number>(CATEGORIES.map((category) => [category, 0]));
  const changedRows: {sortKey: string; cells: string[]}[] = [];
  let checked = 0;

  for (const assignment of assignments) {
    const event = events.get(String(assignment['eventId']));
    if (event == null) {
      skipped.eventMissingOrUndated++;
      continue;
    }
    const firstDayDate = rawDate(event['startDate']);
    const lastDayDate = rawDate(event['endDate']);
    if (firstDayDate == null || lastDayDate == null) {
      skipped.eventMissingOrUndated++;
      continue;
    }
    const firstDay = israelDay(firstDayDate);
    // A last day before the first (bad data) is the first day, as in the stretch.
    const lastDay = [firstDay, israelDay(lastDayDate)].sort()[1];
    if (lastDay < today) {
      skipped.eventEnded++;
      continue;
    }
    if (event['isDeactivated'] === true || assignment['isDeactivated'] === true) {
      skipped.deactivated++;
      continue;
    }
    const member = members.get(String(assignment['teamMemberId']));
    if (member == null) {
      skipped.memberMissing++;
      continue;
    }
    if (member['allowMultipleAssignments'] === true) {
      skipped.multipleAssignmentsMember++;
      continue;
    }
    checked++;

    const oldEvent = revive(event, oldSide.build.makeTimestamp) as Doc;
    const newEvent = revive(event, newSide.build.makeTimestamp) as Doc;
    const oldMember = revive(member, oldSide.build.makeTimestamp) as Doc;
    const newMember = revive(member, newSide.build.makeTimestamp) as Doc;
    const before = ask(oldSide.build, oldMember, oldEvent);
    const after = ask(newSide.build, newMember, newEvent);
    const transition = `${OUTCOME_LABEL[before.outcome]} → ${OUTCOME_LABEL[after.outcome]}`;
    transitions.set(transition, (transitions.get(transition) ?? 0) + 1);
    if (after.outcome === 'error') {
      // The new rule must never throw; surface it loudly.
      console.error(`NEW RULE THREW for assignment ${documentId(assignment)}: ${after.error}`);
    }
    if (before.outcome === after.outcome) {
      continue;
    }

    // One constraint at a time: the responsible ones answer differently alone.
    const constraints = Array.isArray(member['constraints']) ? (member['constraints'] as Doc[]) : [];
    const responsible = constraints.filter((constraint) => {
      const alone = {...member, constraints: [constraint]};
      return (
        ask(oldSide.build, revive(alone, oldSide.build.makeTimestamp) as Doc, oldEvent).outcome !==
        ask(newSide.build, revive(alone, newSide.build.makeTimestamp) as Doc, newEvent).outcome
      );
    });

    const stretch = extras.eventStretchFromData(newEvent);
    const category = categorize({event, stretch, responsible, before: before.outcome, after: after.outcome, extras});
    categoryCounts.set(category, (categoryCounts.get(category) ?? 0) + 1);

    const dates = firstDay === lastDay ? firstDay : `${firstDay} → ${lastDay}`;
    changedRows.push({
      sortKey: `${firstDay} ${String(event['name'])} ${String(member['name'])} ${String(assignment['roleType'])}`,
      cells: [
        String(event['name'] ?? ''),
        dates,
        `${extras.formatWallMinutes(stretch.start)} → ${extras.formatWallMinutes(stretch.end)}`,
        String(member['name'] ?? ''),
        String(assignment['roleType'] ?? ''),
        OUTCOME_LABEL[before.outcome] + (before.error != null ? ` (${before.error})` : ''),
        OUTCOME_LABEL[after.outcome] + (after.error != null ? ` (${after.error})` : ''),
        responsible.length > 0
          ? responsible.map((constraint) => describeConstraint(constraint, israelDay)).join(' | ')
          : '(no single constraint; combination)',
        category,
      ],
    });
  }

  changedRows.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
  const lines: string[][] = [
    [
      'event',
      'Israel dates',
      'stretch',
      'member',
      'role',
      'old',
      'new',
      'responsible constraint(s)',
      'category',
    ],
    ...changedRows.map((row) => row.cells),
    [],
    ['rows checked', String(checked)],
    ['changed', String(changedRows.length)],
    ['unchanged', String(checked - changedRows.length)],
    ...CATEGORIES.map((category) => [category, String(categoryCounts.get(category) ?? 0)]),
    [],
    ['old → new', 'rows'],
    ...[...transitions.entries()].sort().map(([transition, count]) => [transition, String(count)]),
  ];
  const byteOrderMark = String.fromCharCode(0xfeff);
  const csv = byteOrderMark + lines.map((cells) => cells.map(csvCell).join(',')).join('\r\n') + '\r\n';
  const outPath = expandHome(args['out']);
  writeFileSync(outPath, csv, 'utf8');

  console.log(`Wrote ${outPath}`);
  console.log(`Assignments read: ${assignments.length}; skipped: ${JSON.stringify(skipped)}`);
  console.log(`Rows checked: ${checked}; changed: ${changedRows.length}; unchanged: ${checked - changedRows.length}`);
  console.log(`Old → new: ${JSON.stringify(Object.fromEntries(transitions))}`);
  console.log(`Per category: ${JSON.stringify(Object.fromEntries(categoryCounts))}`);
}

function csvCell(value: string): string {
  return /[",\r\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
}

function describeConstraint(constraint: Doc, israelDay: (date: Date) => string): string {
  const first = rawDate(constraint['startDate']);
  const last = rawDate(constraint['endDate']) ?? first;
  const firstDay = first == null ? '?' : israelDay(first);
  const lastDay = last == null ? '?' : israelDay(last);
  const start = typeof constraint['startTime'] === 'string' ? constraint['startTime'] : null;
  const end = typeof constraint['endTime'] === 'string' ? constraint['endTime'] : null;
  const hours = start == null && end == null ? 'all day' : `${start ?? '(none)'}–${end ?? '(none)'}`;
  const repeatType = typeof constraint['repeatType'] === 'string' ? constraint['repeatType'] : null;
  let dates = firstDay === lastDay ? firstDay : `${firstDay} → ${lastDay}`;
  if (repeatType != null) {
    const repeatEnd = rawDate(constraint['repeatEndDate']);
    dates =
      `${repeatType}` +
      (typeof constraint['repeatDay'] === 'number' ? ` (day ${constraint['repeatDay']})` : '') +
      ` from ${firstDay} until ${repeatEnd == null ? '(no end)' : israelDay(repeatEnd)}`;
  }
  return `${String(constraint['status'])} ${String(constraint['constraintType'])} ${dates} ${hours}`;
}

// The first category that fits. The overlap-based ones look at where a
// responsible constraint meets the new stretch.
function categorize(input: {
  event: Doc;
  stretch: WallInterval;
  responsible: Doc[];
  before: Outcome;
  after: Outcome;
  extras: NewBuildExtras;
}): Category {
  const {event, stretch, responsible, before, after, extras} = input;
  if (responsible.some((constraint) => constraint['status'] === 'pending')) {
    return 'pending now counts';
  }
  if (responsible.some((constraint) => typeof constraint['repeatType'] === 'string')) {
    return 'recurring';
  }
  const time = (field: string): number | null =>
    extras.wallTimeMinutes(typeof event[field] === 'string' ? (event[field] as string) : null);
  const showEnd = time('endTime');
  if (showEnd == null || (time('assemblyTime') == null && time('startTime') == null)) {
    return 'missing time';
  }

  const overlaps = responsible.flatMap((constraint) =>
    extras
      .constraintIntervalsNear(toStretchConstraint(constraint, extras), stretch)
      .filter((interval) => interval.start < stretch.end && stretch.start < interval.end)
      .map((interval) => ({start: Math.max(interval.start, stretch.start), end: Math.min(interval.end, stretch.end)})),
  );
  // Days in wall-clock minutes; a last day before the first (bad data) is the
  // first day, as in the stretch.
  const dayMinutes = (value: unknown): number =>
    extras.normalizeDayInIsrael(rawDate(value) as Date).getTime() / 60000;
  const firstDay = dayMinutes(event['startDate']);
  const lastDay = Math.max(firstDay, dayMinutes(event['endDate']));
  const isOneDay = lastDay === firstDay;

  // A one-day event that runs past midnight, met after midnight.
  if (isOneDay && overlaps.some((overlap) => overlap.end > firstDay + MINUTES_PER_DAY)) {
    return 'past midnight';
  }
  // Met between show end and team end on the last day.
  let showEndMoment = lastDay + showEnd;
  if (isOneDay && showEndMoment <= stretch.start) {
    showEndMoment += MINUTES_PER_DAY;
  }
  if (showEndMoment < stretch.end && overlaps.some((overlap) => overlap.end > showEndMoment)) {
    return 'team end';
  }
  if (!isOneDay && overlaps.length > 0) {
    return 'night';
  }
  if (before === 'blocked' && after === 'free') {
    return 'now free';
  }
  return 'other';
}

function toStretchConstraint(constraint: Doc, extras: NewBuildExtras): StretchConstraintInput {
  const firstDay = extras.normalizeDayInIsrael(rawDate(constraint['startDate']) as Date);
  const lastDayDate = rawDate(constraint['endDate']);
  const repeatEndDate = rawDate(constraint['repeatEndDate']);
  const repeatType = typeof constraint['repeatType'] === 'string' ? constraint['repeatType'] : null;
  return {
    firstDay,
    lastDay: lastDayDate == null ? firstDay : extras.normalizeDayInIsrael(lastDayDate),
    startTime: typeof constraint['startTime'] === 'string' ? constraint['startTime'] : null,
    endTime: typeof constraint['endTime'] === 'string' ? constraint['endTime'] : null,
    repeatType: repeatType as StretchConstraintInput['repeatType'],
    repeatDay: typeof constraint['repeatDay'] === 'number' ? constraint['repeatDay'] : null,
    repeatEndDay: repeatEndDate == null ? null : extras.normalizeDayInIsrael(repeatEndDate),
  };
}

if (require.main === module) {
  main();
}
