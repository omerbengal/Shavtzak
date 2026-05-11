import cors from 'cors';
import express, {Request, Response} from 'express';
import {randomBytes, randomUUID, scryptSync, timingSafeEqual, createHash} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from 'firebase-admin/firestore';
import {onRequest} from 'firebase-functions/v2/https';
import {
  canExecuteDriveAction,
  DriveExportValidationError,
  executeDriveAction,
  exportProductionDataToSheets,
} from './drive_export';
import {
  createCalendarAuthUrl,
  disconnectCalendarAuth,
  exchangeCalendarAuthCode,
  executeCalendarAction,
  getCalendarConfigForClient,
  getCalendarStatusForClient,
} from './calendar_integration';
import {
  deleteAppEventCalendarArtifacts,
  syncAppEventCalendars,
  syncAssignedEventsBestEffort,
  syncAssignedFutureEventsForMemberEmailChange,
  syncEventsAndConstraints,
} from './calendar_sync_backend';

initializeApp();

const db = getFirestore();
const auth = getAuth();
const app = express();

app.use(cors({origin: true}));
app.use((request: Request, _response: Response, next) => {
  const routeOverride = request.query['route'];
  if (request.path === '/' && typeof routeOverride === 'string' && routeOverride.trim().length > 0) {
    request.url = routeOverride.startsWith('/') ? routeOverride : `/${routeOverride}`;
  }
  next();
});
app.use(express.json({limit: '2mb'}));

type EnvironmentMode = 'production' | 'test';

type ActorContext = {
  memberId: string;
  uniqueKey: string;
  isAdmin: boolean;
  sessionId: string;
  expiresAt: Timestamp;
  member: Record<string, unknown>;
};

type Collections = {
  teamMembers: string;
  events: string;
  assignments: string;
  assignmentLabels: string;
  checklistItems: string;
  presets: string;
  calendarSync: string;
  eventCalendarSync: string;
  logs: string;
  privateCredentials: string;
  privateSessions: string;
  privateGoogleCalendarAuth: string;
};

type AppEventCalendarSyncSummary = {
  scannedCount: number;
  changedCount: number;
  upToDateCount: number;
  failedEventIds: string[];
  removedOrphanedCount: number;
  cleanedSyncStateCount: number;
};

type ConstraintCalendarSyncSummary = {
  scannedCount: number;
  rejectedCount: number;
  retriedCount: number;
  successCount: number;
  skippedCount: number;
  failedConstraintIds: string[];
};

type DatabaseConstraintCalendarSyncSummary = {
  scannedCount: number;
  changedCount: number;
  upToDateCount: number;
  removedOrphanedCount: number;
  cleanedSyncStateCount: number;
  failedConstraintIds: string[];
};

type ManagedCalendarEventSummary = {
  id: string;
  status: string | null;
  summary: string | null;
  description: string | null;
  location: string | null;
  colorId: string | null;
  startDate: string | null;
  startDateTime: string | null;
  endDate: string | null;
  endDateTime: string | null;
  recurrence: string[];
  attendeeEmails: string[];
  attendeesKnown: boolean;
  eventId: string | null;
  eventType: string | null;
  constraintId: string | null;
  teamMemberId: string | null;
  constraintType: string | null;
  repeatType: string | null;
  repeatDay: string | null;
  repeatEndDate: string | null;
  isTestMode: string | null;
};

type DesiredAppEventCalendarState = {
  payload: Record<string, unknown>;
  useAllDay: boolean;
  assemblyTitle: string;
  mainTitle: string;
  location: string | null;
  colorId: string;
  assemblyStartPrefix: string | null;
  assemblyEndPrefix: string | null;
  mainStartPrefix: string | null;
  mainEndPrefix: string | null;
  allDayStartDate: string | null;
  allDayEndDate: string | null;
};

type DesiredConstraintCalendarState = {
  teamMemberPayload: Record<string, unknown>;
  constraintPayload: Record<string, unknown>;
  summary: string;
  description: string;
  colorId: string;
  attendeeEmails: string[];
  startDate: string | null;
  startDateTime: string | null;
  endDate: string | null;
  endDateTime: string | null;
  recurrence: string[];
  repeatType: string | null;
  repeatDay: string | null;
  repeatEndDate: string | null;
};

const DEFAULT_TEAM_MEMBER_PASSCODE = '071023';
const DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH = DEFAULT_TEAM_MEMBER_PASSCODE.length;

const CALENDAR_SYNC_MAX_RETRY_ATTEMPTS = 3;
const CALENDAR_SYNC_INITIAL_RETRY_DELAY_MS = 1000;
const CALENDAR_SYNC_BACKOFF_MULTIPLIER = 2;
const CALENDAR_SYNC_MAX_RETRY_DELAY_MS = 300000;
const CALENDAR_TEST_MODE_PREFIX = 'שבצק טסטינג: ';
const CALENDAR_APP_EVENT_COLOR_ID = '7';
const CALENDAR_TEST_MODE_COLOR_ID = '5';
const CALENDAR_UNAVAILABILITY_COLOR_ID = '8';

function getEnvironmentMode(value: unknown): EnvironmentMode {
  return value === 'test' ? 'test' : 'production';
}

function getCollections(environment: EnvironmentMode): Collections {
  const prefix = environment === 'test' ? 'test_' : '';
  return {
    teamMembers: `${prefix}teamMembers`,
    events: `${prefix}events`,
    assignments: `${prefix}assignments`,
    assignmentLabels: `${prefix}assignmentLabels`,
    checklistItems: `${prefix}checklist_items`,
    presets: `${prefix}checklist_presets`,
    calendarSync: `${prefix}calendar_sync`,
    eventCalendarSync: `${prefix}event_calendar_sync`,
    logs: `${prefix}logs`,
    privateCredentials: `${prefix}private_member_credentials`,
    privateSessions: `${prefix}private_sessions`,
    privateGoogleCalendarAuth: `${prefix}private_google_calendar_auth`,
  };
}

function requireString(value: unknown, fieldName: string): string {
  if (typeof value != 'string' || value.trim().length === 0) {
    throw new Error(`Missing or invalid ${fieldName}`);
  }
  return value;
}

function optionalString(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value != 'string') {
    throw new Error('Expected string value');
  }
  return value;
}

function asDate(value: unknown, fieldName: string): Date {
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value == 'string') {
    finalDateCheck(value, fieldName);
    return new Date(value);
  }
  throw new Error(`Missing or invalid ${fieldName}`);
}

function finalDateCheck(value: string, fieldName: string): void {
  if (Number.isNaN(Date.parse(value))) {
    throw new Error(`Missing or invalid ${fieldName}`);
  }
}

function toTimestamp(value: unknown, fieldName: string): Timestamp {
  return Timestamp.fromDate(asDate(value, fieldName));
}

const ISRAEL_TIME_ZONE = 'Asia/Jerusalem';

type CalendarDateParts = {
  year: number;
  month: number;
  day: number;
};

function getCalendarDatePartsInTimeZone(
  date: Date,
  timeZone: string,
): CalendarDateParts {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });

  const partMap: Record<string, string> = {};
  for (const part of formatter.formatToParts(date)) {
    if (part.type !== 'literal') {
      partMap[part.type] = part.value;
    }
  }

  return {
    year: Number(partMap['year']),
    month: Number(partMap['month']),
    day: Number(partMap['day']),
  };
}

function getTimeZoneOffsetMinutes(date: Date, timeZone: string): number {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    timeZoneName: 'shortOffset',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });

  const offsetPart = formatter
    .formatToParts(date)
    .find((part) => part.type === 'timeZoneName')
    ?.value;

  if (offsetPart == null) {
    throw new Error(`Missing timezone offset for ${timeZone}`);
  }

  const match = /^GMT([+-])(\d{1,2})(?::?(\d{2}))?$/.exec(offsetPart);
  if (match == null) {
    throw new Error(`Unsupported timezone offset format: ${offsetPart}`);
  }

  const sign = match[1] === '-' ? -1 : 1;
  const hours = Number(match[2]);
  const minutes = Number(match[3] ?? '0');
  return sign * ((hours * 60) + minutes);
}

function buildTimeZoneMidnight(
  year: number,
  month: number,
  day: number,
  timeZone: string,
): Date {
  let candidate = new Date(Date.UTC(year, month - 1, day, 0, 0, 0));

  for (let iteration = 0; iteration < 3; iteration += 1) {
    const offsetMinutes = getTimeZoneOffsetMinutes(candidate, timeZone);
    candidate = new Date(
      Date.UTC(year, month - 1, day, 0, 0, 0) - (offsetMinutes * 60 * 1000),
    );
  }

  return candidate;
}

function asCalendarDay(value: unknown, fieldName: string): Date {
  if (value instanceof Timestamp) {
    const parts = getCalendarDatePartsInTimeZone(value.toDate(), ISRAEL_TIME_ZONE);
    return buildTimeZoneMidnight(
      parts.year,
      parts.month,
      parts.day,
      ISRAEL_TIME_ZONE,
    );
  }

  if (typeof value == 'string') {
    const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
    if (match != null) {
      const year = Number(match[1]);
      const month = Number(match[2]);
      const day = Number(match[3]);
      return buildTimeZoneMidnight(year, month, day, ISRAEL_TIME_ZONE);
    }
  }

  const parts = getCalendarDatePartsInTimeZone(
    asDate(value, fieldName),
    ISRAEL_TIME_ZONE,
  );
  return buildTimeZoneMidnight(
    parts.year,
    parts.month,
    parts.day,
    ISRAEL_TIME_ZONE,
  );
}

function toDayTimestamp(value: unknown, fieldName: string): Timestamp {
  return Timestamp.fromDate(asCalendarDay(value, fieldName));
}

function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate()
  );
}

function normalizeDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

// Returns a Date at UTC midnight of the Israel calendar day of `date`.
// Event day-stamps are stored as Israel midnight (e.g. 21:00Z in summer), so
// using getUTCDate() on them would skid back into the previous calendar day.
function normalizeDayInIsrael(date: Date): Date {
  const parts = getCalendarDatePartsInTimeZone(date, ISRAEL_TIME_ZONE);
  return new Date(Date.UTC(parts.year, parts.month - 1, parts.day));
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}

function parseTimeToMinutes(value: unknown): number | null {
  if (typeof value != 'string' || value.length === 0) return null;
  const parts = value.split(':');
  if (parts.length !== 2) return null;
  const hours = Number(parts[0]);
  const minutes = Number(parts[1]);
  if (!Number.isInteger(hours) || !Number.isInteger(minutes)) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
  return hours * 60 + minutes;
}

function timesOverlap(
  firstStart: string | null,
  firstEnd: string | null,
  secondStart: string | null,
  secondEnd: string | null,
): boolean {
  const aStart = parseTimeToMinutes(firstStart);
  const aEnd = parseTimeToMinutes(firstEnd);
  const bStart = parseTimeToMinutes(secondStart);
  const bEnd = parseTimeToMinutes(secondEnd);
  if (aStart == null || aEnd == null || bStart == null || bEnd == null) {
    return true;
  }
  return aStart < bEnd && bStart < aEnd;
}

function hashPasscode(passcode: string): string {
  const salt = randomBytes(16);
  const hash = scryptSync(passcode, salt, 64);
  return `${salt.toString('hex')}:${hash.toString('hex')}`;
}

function verifyPasscode(passcode: string, encodedHash: string): boolean {
  const parts = encodedHash.split(':');
  if (parts.length !== 2) return false;
  const salt = Buffer.from(parts[0], 'hex');
  const expected = Buffer.from(parts[1], 'hex');
  const actual = scryptSync(passcode, salt, expected.length);
  return timingSafeEqual(expected, actual);
}

function getStoredPrivatePasscodeValue(
  credentialData: Record<string, unknown> | undefined,
): string | null {
  const value = credentialData?.['passcodeValue'];
  return typeof value === 'string' && value.length > 0 ? value : null;
}

async function upsertPrivatePasscodeCredential(
  collections: Collections,
  memberId: string,
  passcode: string,
  length: number,
  extraFields: Record<string, unknown> = {},
): Promise<void> {
  await db.collection(collections.privateCredentials).doc(memberId).set(
    stripUndefined({
      passcodeHash: hashPasscode(passcode),
      passcodeValue: passcode,
      passcodeLength: length,
      updatedAt: FieldValue.serverTimestamp(),
      ...extraFields,
    }),
    {merge: true},
  );
}

function hashSessionToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

function stripUndefined<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(
    Object.entries(value).filter(([, entryValue]) => entryValue !== undefined),
  ) as T;
}

async function readTeamMemberByUniqueKey(
  firestore: Firestore,
  collections: Collections,
  uniqueKey: string,
): Promise<{id: string; data: Record<string, unknown>} | null> {
  const snapshot = await firestore
    .collection(collections.teamMembers)
    .where('uniqueKey', '==', uniqueKey)
    .limit(1)
    .get();
  if (snapshot.empty) {
    const directDoc = await firestore.collection(collections.teamMembers).doc(uniqueKey).get();
    if (!directDoc.exists) {
      return null;
    }
    return {id: directDoc.id, data: directDoc.data() ?? {}};
  }
  const doc = snapshot.docs[0];
  return {id: doc.id, data: doc.data()};
}

async function readTeamMemberById(
  firestore: Firestore,
  collections: Collections,
  memberId: string,
): Promise<Record<string, unknown> | null> {
  const snapshot = await firestore.collection(collections.teamMembers).doc(memberId).get();
  return snapshot.exists ? snapshot.data() ?? null : null;
}

async function readEventById(
  firestore: Firestore,
  collections: Collections,
  eventId: string,
): Promise<Record<string, unknown> | null> {
  const snapshot = await firestore.collection(collections.events).doc(eventId).get();
  return snapshot.exists ? snapshot.data() ?? null : null;
}

function optionalStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => (typeof entry === 'string' ? entry : null))
    .filter((entry): entry is string => entry != null);
}

function normalizeOptionalText(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeEmailValue(value: string): string {
  return value.trim().toLowerCase();
}

function uniqueSortedStrings(values: Iterable<string>): string[] {
  return Array.from(new Set(
    Array.from(values)
      .map((value) => value.trim())
      .filter((value) => value.length > 0),
  )).sort((left, right) => left.localeCompare(right));
}

function toLocalDateTimePrefix(value: string | null): string | null {
  if (value == null || value.length < 16) {
    return value;
  }
  return value.slice(0, 16);
}

function formatCalendarDateTimePrefix(date: Date, time: string): string {
  return `${formatCalendarDateOnly(date)}T${time}`;
}

function calendarEventColorId(environment: EnvironmentMode): string {
  return environment === 'test'
    ? CALENDAR_TEST_MODE_COLOR_ID
    : CALENDAR_APP_EVENT_COLOR_ID;
}

function constraintColorIdForEnvironment(environment: EnvironmentMode): string {
  return environment === 'test'
    ? CALENDAR_TEST_MODE_COLOR_ID
    : CALENDAR_UNAVAILABILITY_COLOR_ID;
}

function createCalendarEventMainTitle(eventName: string, environment: EnvironmentMode): string {
  return environment === 'test'
    ? `${CALENDAR_TEST_MODE_PREFIX}${eventName}`
    : eventName;
}

function createCalendarEventAssemblyTitle(eventName: string, environment: EnvironmentMode): string {
  const title = `${eventName} - התייצבות והכנות`;
  return environment === 'test'
    ? `${CALENDAR_TEST_MODE_PREFIX}${title}`
    : title;
}

function cleanConstraintNote(note: string | null): string | null {
  if (note == null || note.trim().length === 0) {
    return null;
  }

  const autoRejectionMessage =
    '(מגבלה זו נדחתה באופן אוטומטי בגלל שאחד מהמנהלים מחק את המגבלה מגוגל קלנדר)';
  const cleaned = note
    .replace(`\n\n${autoRejectionMessage}`, '')
    .replace(autoRejectionMessage, '')
    .trim();
  return cleaned.length > 0 ? cleaned : null;
}

function createConstraintDescription(note: string | null): string {
  const cleaned = cleanConstraintNote(note);
  const lines = cleaned != null && cleaned.length > 0
    ? [cleaned, '', '--- נוצר אוטומטית על ידי שבצק ---']
    : ['--- נוצר אוטומטית על ידי שבצק ---'];
  return `${lines.join('\n')}\n`;
}

function createConstraintTitle(
  memberName: string,
  environment: EnvironmentMode,
): string {
  const base = `${memberName} - מגבלה`;
  return environment === 'test'
    ? `${CALENDAR_TEST_MODE_PREFIX}${base}`
    : base;
}

function weekdayToRRule(weekday: number | null): string | null {
  switch (weekday) {
    case 1:
      return 'MO';
    case 2:
      return 'TU';
    case 3:
      return 'WE';
    case 4:
      return 'TH';
    case 5:
      return 'FR';
    case 6:
      return 'SA';
    case 7:
      return 'SU';
    default:
      return null;
  }
}

function formatRRuleUntil(endDate: Date): string {
  const utc = new Date(
    Date.UTC(endDate.getUTCFullYear(), endDate.getUTCMonth(), endDate.getUTCDate(), 23, 59, 59),
  );
  const year = utc.getUTCFullYear().toString().padStart(4, '0');
  const month = String(utc.getUTCMonth() + 1).padStart(2, '0');
  const day = String(utc.getUTCDate()).padStart(2, '0');
  const hour = String(utc.getUTCHours()).padStart(2, '0');
  const minute = String(utc.getUTCMinutes()).padStart(2, '0');
  const second = String(utc.getUTCSeconds()).padStart(2, '0');
  return `${year}${month}${day}T${hour}${minute}${second}Z`;
}

function buildConstraintRecurrenceRule(constraint: Record<string, unknown>): string | null {
  const repeatType =
    typeof constraint['repeatType'] === 'string'
      ? constraint['repeatType']
      : null;
  if (repeatType == null || constraint['repeatEndDate'] == null) {
    return null;
  }

  const until = formatRRuleUntil(asDate(constraint['repeatEndDate'], 'constraint.repeatEndDate'));
  switch (repeatType) {
    case 'daily':
      return `RRULE:FREQ=DAILY;UNTIL=${until}`;
    case 'weekly': {
      const byDay = weekdayToRRule(readInt(constraint['repeatDay']));
      return byDay == null ? null : `RRULE:FREQ=WEEKLY;BYDAY=${byDay};UNTIL=${until}`;
    }
    case 'monthly': {
      const repeatDay = readInt(constraint['repeatDay']);
      if (repeatDay == null || repeatDay < 1 || repeatDay > 31) {
        return null;
      }
      return `RRULE:FREQ=MONTHLY;BYMONTHDAY=${repeatDay};UNTIL=${until}`;
    }
    default:
      return null;
  }
}

function nextMonthlyOccurrenceOnOrAfter(
  from: Date,
  day: number,
  maxDate: Date | null,
): Date | null {
  let cursor = new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), 1));

  for (let i = 0; i < 240; i += 1) {
    const daysInMonth = new Date(
      Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, 0),
    ).getUTCDate();
    if (day <= daysInMonth) {
      const candidate = new Date(
        Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth(), day),
      );
      if (candidate.getTime() >= from.getTime()) {
        if (maxDate != null && candidate.getTime() > maxDate.getTime()) {
          return null;
        }
        return candidate;
      }
    }

    const nextMonth = new Date(
      Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, 1),
    );
    if (maxDate != null && nextMonth.getTime() > maxDate.getTime()) {
      return null;
    }
    cursor = nextMonth;
  }

  return null;
}

function resolveConstraintEventStartDate(constraint: Record<string, unknown>): Date {
  const startDate = asDate(constraint['startDate'], 'constraint.startDate');
  const start = new Date(
    Date.UTC(
      startDate.getUTCFullYear(),
      startDate.getUTCMonth(),
      startDate.getUTCDate(),
    ),
  );
  const repeatType =
    typeof constraint['repeatType'] === 'string'
      ? constraint['repeatType']
      : null;
  if (repeatType == null || constraint['repeatEndDate'] == null) {
    return start;
  }

  const repeatEndDate = asDate(constraint['repeatEndDate'], 'constraint.repeatEndDate');
  const repeatEnd = new Date(
    Date.UTC(
      repeatEndDate.getUTCFullYear(),
      repeatEndDate.getUTCMonth(),
      repeatEndDate.getUTCDate(),
    ),
  );

  switch (repeatType) {
    case 'daily':
      return start;
    case 'weekly': {
      const repeatDay = readInt(constraint['repeatDay']);
      if (repeatDay == null || repeatDay < 1 || repeatDay > 7) {
        return start;
      }
      const jsWeekday = start.getUTCDay() === 0 ? 7 : start.getUTCDay();
      const offset = (repeatDay - jsWeekday + 7) % 7;
      const candidate = addDays(start, offset);
      return candidate.getTime() > repeatEnd.getTime() ? start : candidate;
    }
    case 'monthly': {
      const repeatDay = readInt(constraint['repeatDay']);
      if (repeatDay == null || repeatDay < 1 || repeatDay > 31) {
        return start;
      }
      return nextMonthlyOccurrenceOnOrAfter(start, repeatDay, repeatEnd) ?? start;
    }
    default:
      return start;
  }
}

function asManagedCalendarEventSummary(value: unknown): ManagedCalendarEventSummary | null {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }

  const record = value as Record<string, unknown>;
  const id = optionalString(record['id']);
  if (id == null || id.length === 0) {
    return null;
  }

  return {
    id,
    status: optionalString(record['status']),
    summary: optionalString(record['summary']),
    description: optionalString(record['description']),
    location: optionalString(record['location']),
    colorId: optionalString(record['colorId']),
    startDate: optionalString(record['startDate']),
    startDateTime: optionalString(record['startDateTime']),
    endDate: optionalString(record['endDate']),
    endDateTime: optionalString(record['endDateTime']),
    recurrence: optionalStringArray(record['recurrence']),
    attendeeEmails: optionalStringArray(record['attendeeEmails']),
    attendeesKnown: record['attendeesKnown'] === true,
    eventId: optionalString(record['eventId']),
    eventType: optionalString(record['eventType']),
    constraintId: optionalString(record['constraintId']),
    teamMemberId: optionalString(record['teamMemberId']),
    constraintType: optionalString(record['constraintType']),
    repeatType: optionalString(record['repeatType']),
    repeatDay: optionalString(record['repeatDay']),
    repeatEndDate: optionalString(record['repeatEndDate']),
    isTestMode: optionalString(record['isTestMode']),
  };
}

async function listManagedCalendarEventsForSync(
  actor: ActorContext,
  environment: EnvironmentMode,
  filters: {
    kind?: 'app' | 'constraint';
    eventId?: string | null;
    constraintId?: string | null;
  } = {},
): Promise<ManagedCalendarEventSummary[]> {
  const result = await executeCalendarAction(
    db,
    {
      memberId: actor.memberId,
      isAdmin: actor.isAdmin,
    },
    environment,
    'listManagedCalendarEvents',
    stripUndefined({
      kind: filters.kind,
      eventId: filters.eventId ?? undefined,
      constraintId: filters.constraintId ?? undefined,
    }),
  );

  const events = Array.isArray(result['events']) ? result['events'] : [];
  return events
    .map((entry) => asManagedCalendarEventSummary(entry))
    .filter((entry): entry is ManagedCalendarEventSummary => entry != null);
}

async function getManagedCalendarEventForSync(
  actor: ActorContext,
  environment: EnvironmentMode,
  calendarEventId: string,
): Promise<ManagedCalendarEventSummary | null> {
  const result = await executeCalendarAction(
    db,
    {
      memberId: actor.memberId,
      isAdmin: actor.isAdmin,
    },
    environment,
    'getManagedCalendarEvent',
    {
      calendarEventId,
    },
  );

  return asManagedCalendarEventSummary(result['event']);
}

function buildDesiredAppEventCalendarState(
  eventId: string,
  eventData: Record<string, unknown>,
  environment: EnvironmentMode,
): DesiredAppEventCalendarState {
  const eventName = requireString(eventData['name'], 'event.name');
  const startDate = asDate(eventData['startDate'], 'event.startDate');
  const endDate = asDate(eventData['endDate'], 'event.endDate');
  const assemblyTime = typeof eventData['assemblyTime'] === 'string'
    ? eventData['assemblyTime'].trim()
    : '';
  const startTime = typeof eventData['startTime'] === 'string'
    ? eventData['startTime'].trim()
    : '';
  const actualShowStartTime = typeof eventData['actualShowStartTime'] === 'string'
    ? eventData['actualShowStartTime'].trim()
    : '';
  const endTime = typeof eventData['endTime'] === 'string'
    ? eventData['endTime'].trim()
    : '';
  const separatorTime = actualShowStartTime.length > 0 ? actualShowStartTime : startTime;
  const useAllDay = assemblyTime.length === 0 || endTime.length === 0;
  const location = normalizeOptionalText(eventData['location']);
  const payload = stripUndefined({
    eventId,
    eventName,
    startDate: formatCalendarDateOnly(startDate),
    endDate: formatCalendarDateOnly(endDate),
    assemblyTime,
    separatorTime,
    endTime,
    location,
    isTestMode: environment === 'test',
  });

  return {
    payload,
    useAllDay,
    assemblyTitle: createCalendarEventAssemblyTitle(eventName, environment),
    mainTitle: createCalendarEventMainTitle(eventName, environment),
    location,
    colorId: calendarEventColorId(environment),
    assemblyStartPrefix:
      !useAllDay && assemblyTime.length > 0 && separatorTime.length > 0
        ? formatCalendarDateTimePrefix(startDate, assemblyTime)
        : null,
    assemblyEndPrefix:
      !useAllDay && assemblyTime.length > 0 && separatorTime.length > 0
        ? formatCalendarDateTimePrefix(startDate, separatorTime)
        : null,
    mainStartPrefix:
      !useAllDay && (separatorTime.length > 0 || assemblyTime.length > 0)
        ? formatCalendarDateTimePrefix(
          startDate,
          separatorTime.length > 0 ? separatorTime : assemblyTime,
        )
        : null,
    mainEndPrefix:
      !useAllDay && endTime.length > 0
        ? formatCalendarDateTimePrefix(endDate, endTime)
        : null,
    allDayStartDate: useAllDay ? formatCalendarDateOnly(startDate) : null,
    allDayEndDate: useAllDay ? formatCalendarDateOnly(addDays(endDate, 1)) : null,
  };
}

function managedAppEventMatchesDesired(
  managedEvent: ManagedCalendarEventSummary | null,
  desired: DesiredAppEventCalendarState,
  expectedType: 'assembly' | 'main' | 'allDay',
): boolean {
  if (managedEvent == null) {
    return false;
  }

  if (managedEvent.eventType !== expectedType) {
    return false;
  }

  if (managedEvent.colorId !== desired.colorId) {
    return false;
  }

  if (normalizeOptionalText(managedEvent.location) !== desired.location) {
    return false;
  }

  if (expectedType === 'assembly') {
    return managedEvent.summary === desired.assemblyTitle &&
      toLocalDateTimePrefix(managedEvent.startDateTime) === desired.assemblyStartPrefix &&
      toLocalDateTimePrefix(managedEvent.endDateTime) === desired.assemblyEndPrefix;
  }

  if (expectedType === 'main') {
    return managedEvent.summary === desired.mainTitle &&
      toLocalDateTimePrefix(managedEvent.startDateTime) === desired.mainStartPrefix &&
      toLocalDateTimePrefix(managedEvent.endDateTime) === desired.mainEndPrefix;
  }

  return managedEvent.summary === desired.mainTitle &&
    managedEvent.startDate === desired.allDayStartDate &&
    managedEvent.endDate === desired.allDayEndDate;
}

function managedEventAttendeesMatch(
  managedEvent: ManagedCalendarEventSummary | null,
  desiredEmails: string[],
): boolean {
  if (managedEvent == null) {
    return false;
  }

  if (!managedEvent.attendeesKnown) {
    return false;
  }

  const currentEmails = uniqueSortedStrings(
    managedEvent.attendeeEmails.map((email) => normalizeEmailValue(email)),
  );
  return currentEmails.length === desiredEmails.length &&
    currentEmails.every((email, index) => email === desiredEmails[index]);
}

async function readEventAttendeeEmails(
  collections: Collections,
  eventId: string,
  teamMemberCache: Map<string, Record<string, unknown> | null>,
): Promise<string[]> {
  const assignmentsSnapshot = await db
    .collection(collections.assignments)
    .where('eventId', '==', eventId)
    .get();

  const teamMemberIds = Array.from(new Set(
    assignmentsSnapshot.docs
      .map((doc) => {
        const data = doc.data() ?? {};
        return typeof data['teamMemberId'] === 'string'
          ? data['teamMemberId'] as string
          : null;
      })
      .filter((teamMemberId): teamMemberId is string => teamMemberId != null),
  ));

  const emails = new Set<string>();
  for (const teamMemberId of teamMemberIds) {
    if (!teamMemberCache.has(teamMemberId)) {
      teamMemberCache.set(teamMemberId, await readTeamMemberById(db, collections, teamMemberId));
    }
    const teamMemberData = teamMemberCache.get(teamMemberId) ?? null;
    const email = normalizeOptionalText(teamMemberData?.['email']);
    if (email != null) {
      emails.add(normalizeEmailValue(email));
    }
  }

  return uniqueSortedStrings(emails);
}

async function updateAppEventAttendees(
  actor: ActorContext,
  environment: EnvironmentMode,
  calendarEventIds: Iterable<string>,
  emails: string[],
): Promise<void> {
  const uniqueIds = uniqueSortedStrings(calendarEventIds);
  for (const calendarEventId of uniqueIds) {
    await executeCalendarAction(
      db,
      {
        memberId: actor.memberId,
        isAdmin: actor.isAdmin,
      },
      environment,
      'updateEventAttendees',
      {
        calendarEventId,
        emails,
      },
    );
  }
}

async function deleteManagedAppEvent(
  actor: ActorContext,
  environment: EnvironmentMode,
  managedEvent: ManagedCalendarEventSummary,
): Promise<void> {
  await executeCalendarAction(
    db,
    {
      memberId: actor.memberId,
      isAdmin: actor.isAdmin,
    },
    environment,
    'deleteAppEventCalendarEvents',
    managedEvent.eventType === 'assembly'
      ? {assemblyCalendarEventId: managedEvent.id}
      : {mainCalendarEventId: managedEvent.id},
  );
}

async function reconcileSingleAppEventCalendar(
  actor: ActorContext,
  environment: EnvironmentMode,
  collections: Collections,
  eventId: string,
  eventData: Record<string, unknown>,
  managedEvents: ManagedCalendarEventSummary[],
  eventSyncData: Record<string, unknown> | null,
  teamMemberCache: Map<string, Record<string, unknown> | null>,
): Promise<{changed: boolean}> {
  const desired = buildDesiredAppEventCalendarState(eventId, eventData, environment);
  const desiredEmails = await readEventAttendeeEmails(collections, eventId, teamMemberCache);
  const activeManagedEvents = managedEvents.filter((event) => event.status !== 'cancelled');
  const assemblyEvents = activeManagedEvents.filter((event) => event.eventType === 'assembly');
  const mainEvents = activeManagedEvents.filter((event) => event.eventType === 'main');
  const allDayEvents = activeManagedEvents.filter((event) => event.eventType === 'allDay');
  const currentAssembly = assemblyEvents[0] ?? null;
  const currentMain = mainEvents[0] ?? null;
  const currentAllDay = allDayEvents[0] ?? null;
  const currentStateAssemblyId = optionalString(eventSyncData?.['assemblyCalendarEventId']) ?? '';
  const currentStateMainId = optionalString(eventSyncData?.['mainCalendarEventId']) ?? '';
  const currentStateStatus = optionalString(eventSyncData?.['status']) ?? '';
  const currentAssemblyId = currentAssembly?.id ?? currentStateAssemblyId;
  const currentMainId = desired.useAllDay
    ? (currentAllDay?.id ?? currentMain?.id ?? currentStateMainId)
    : (currentMain?.id ?? currentAllDay?.id ?? currentStateMainId);
  const detailedCurrentAssembly =
    !desired.useAllDay && currentAssemblyId.length > 0
      ? await getManagedCalendarEventForSync(actor, environment, currentAssemblyId)
      : null;
  const detailedCurrentMain =
    currentMainId.length > 0
      ? await getManagedCalendarEventForSync(actor, environment, currentMainId)
      : null;

  const hasDuplicateEvents = assemblyEvents.length > 1 || mainEvents.length > 1 || allDayEvents.length > 1;
  const needsEventUpsert = desired.useAllDay
    ? !managedAppEventMatchesDesired(detailedCurrentMain, desired, 'allDay') ||
      currentAssembly != null ||
      assemblyEvents.length > 0 ||
      hasDuplicateEvents
    : !managedAppEventMatchesDesired(detailedCurrentAssembly, desired, 'assembly') ||
      !managedAppEventMatchesDesired(detailedCurrentMain, desired, 'main') ||
      currentAllDay != null ||
      hasDuplicateEvents;
  const needsAttendeeSync = desired.useAllDay
    ? !managedEventAttendeesMatch(detailedCurrentMain, desiredEmails)
    : !managedEventAttendeesMatch(detailedCurrentAssembly, desiredEmails) ||
      !managedEventAttendeesMatch(detailedCurrentMain, desiredEmails);

  let finalAssemblyId = desired.useAllDay
    ? ''
    : currentAssemblyId;
  let finalMainId = currentMainId;
  let changed = false;

  if (needsEventUpsert) {
    const result = await executeCalendarAction(
      db,
      {
        memberId: actor.memberId,
        isAdmin: actor.isAdmin,
      },
      environment,
      'updateAppEventCalendarEvents',
      {
        assemblyCalendarEventId: finalAssemblyId,
        mainCalendarEventId: finalMainId,
        event: desired.payload,
      },
    );
    const recreatedIds =
      result['result'] != null && typeof result['result'] === 'object' && !Array.isArray(result['result'])
        ? result['result'] as Record<string, unknown>
        : null;

    if (desired.useAllDay) {
      finalAssemblyId = '';
      if (recreatedIds != null && typeof recreatedIds['main'] === 'string') {
        finalMainId = recreatedIds['main'] as string;
      }
    } else {
      if (recreatedIds != null && typeof recreatedIds['assembly'] === 'string') {
        finalAssemblyId = recreatedIds['assembly'] as string;
      }
      if (recreatedIds != null && typeof recreatedIds['main'] === 'string') {
        finalMainId = recreatedIds['main'] as string;
      }
    }
    changed = true;
  }

  const finalIds = new Set(
    [finalAssemblyId, finalMainId].filter((calendarEventId) => calendarEventId.trim().length > 0),
  );
  for (const managedEvent of activeManagedEvents) {
    if (finalIds.has(managedEvent.id)) {
      continue;
    }
    await deleteManagedAppEvent(actor, environment, managedEvent);
    changed = true;
  }

  if (needsAttendeeSync || needsEventUpsert) {
    await updateAppEventAttendees(actor, environment, finalIds, desiredEmails);
    changed = true;
  }

  if (
    currentStateAssemblyId !== finalAssemblyId ||
    currentStateMainId !== finalMainId ||
    currentStateStatus !== 'synced'
  ) {
    await db.collection(collections.eventCalendarSync).doc(eventId).set({
      assemblyCalendarEventId: finalAssemblyId,
      mainCalendarEventId: finalMainId,
      status: 'synced',
      syncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    changed = true;
  }

  return {changed};
}

function buildDesiredConstraintCalendarState(
  teamMemberId: string,
  teamMemberData: Record<string, unknown>,
  constraint: Record<string, unknown>,
  environment: EnvironmentMode,
): DesiredConstraintCalendarState {
  const teamMemberPayload = serializeTeamMemberForCalendarAction(teamMemberId, teamMemberData);
  const constraintPayload = serializeConstraintForCalendarAction(constraint);
  const startDate = resolveConstraintEventStartDate(constraint);
  const repeatType =
    typeof constraint['repeatType'] === 'string'
      ? constraint['repeatType']
      : null;
  const recurrenceRule = buildConstraintRecurrenceRule(constraint);
  const hasTimeRange =
    normalizeOptionalText(constraint['startTime']) != null &&
    normalizeOptionalText(constraint['endTime']) != null;
  const rawEndBaseDate = repeatType != null
    ? startDate
    : (constraint['endDate'] == null
      ? asDate(constraint['startDate'], 'constraint.startDate')
      : asDate(constraint['endDate'], 'constraint.endDate'));
  const endBaseDate = normalizeDay(rawEndBaseDate);
  const attendeeEmail = normalizeOptionalText(teamMemberData['email']);

  return {
    teamMemberPayload,
    constraintPayload,
    summary: createConstraintTitle(
      requireString(teamMemberData['name'] ?? teamMemberId, 'teamMember.name'),
      environment,
    ),
    description: createConstraintDescription(normalizeOptionalText(constraint['note'])),
    colorId: constraintColorIdForEnvironment(environment),
    attendeeEmails:
      attendeeEmail == null ? [] : [normalizeEmailValue(attendeeEmail)],
    startDate: hasTimeRange ? null : formatCalendarDateOnly(startDate),
    startDateTime: hasTimeRange
      ? formatCalendarDateTimePrefix(
        startDate,
        requireString(constraint['startTime'], 'constraint.startTime'),
      )
      : null,
    endDate: hasTimeRange ? null : formatCalendarDateOnly(addDays(endBaseDate, 1)),
    endDateTime: hasTimeRange
      ? formatCalendarDateTimePrefix(
        endBaseDate,
        requireString(constraint['endTime'], 'constraint.endTime'),
      )
      : null,
    recurrence: recurrenceRule == null ? [] : [recurrenceRule],
    repeatType,
    repeatDay:
      constraintPayload['repeatDay'] == null ? null : String(constraintPayload['repeatDay']),
    repeatEndDate:
      constraintPayload['repeatEndDate'] == null
        ? null
        : String(constraintPayload['repeatEndDate']),
  };
}

function managedConstraintEventMatchesDesired(
  managedEvent: ManagedCalendarEventSummary | null,
  desired: DesiredConstraintCalendarState,
): boolean {
  if (managedEvent == null) {
    return false;
  }

  if (
    managedEvent.summary !== desired.summary ||
    managedEvent.description !== desired.description ||
    managedEvent.colorId !== desired.colorId ||
    managedEvent.constraintType !== 'unavailability' ||
    managedEvent.repeatType !== (desired.repeatType ?? '') ||
    managedEvent.repeatDay !== (desired.repeatDay ?? '') ||
    managedEvent.repeatEndDate !== (desired.repeatEndDate ?? '') ||
    managedEvent.teamMemberId !== String(desired.teamMemberPayload['id'])
  ) {
    return false;
  }

  const currentRecurrence = uniqueSortedStrings(managedEvent.recurrence);
  const desiredRecurrence = uniqueSortedStrings(desired.recurrence);
  if (
    currentRecurrence.length !== desiredRecurrence.length ||
    currentRecurrence.some((entry, index) => entry !== desiredRecurrence[index])
  ) {
    return false;
  }

  const currentEmails = uniqueSortedStrings(
    managedEvent.attendeeEmails.map((email) => normalizeEmailValue(email)),
  );
  if (
    currentEmails.length !== desired.attendeeEmails.length ||
    currentEmails.some((entry, index) => entry !== desired.attendeeEmails[index])
  ) {
    return false;
  }

  if (desired.startDateTime != null || desired.endDateTime != null) {
    return toLocalDateTimePrefix(managedEvent.startDateTime) === desired.startDateTime &&
      toLocalDateTimePrefix(managedEvent.endDateTime) === desired.endDateTime;
  }

  return managedEvent.startDate === desired.startDate &&
    managedEvent.endDate === desired.endDate;
}

async function deleteManagedConstraintEvent(
  actor: ActorContext,
  environment: EnvironmentMode,
  managedEvent: ManagedCalendarEventSummary,
): Promise<void> {
  await executeCalendarAction(
    db,
    {
      memberId: actor.memberId,
      isAdmin: actor.isAdmin,
    },
    environment,
    'deleteConstraintEvent',
    {
      calendarEventId: managedEvent.id,
      teamMemberId: managedEvent.teamMemberId ?? actor.memberId,
    },
  );
}

async function reconcileConstraintsFromDatabase(
  actor: ActorContext,
  environment: EnvironmentMode,
  collections: Collections,
  managedConstraintEvents?: ManagedCalendarEventSummary[],
): Promise<DatabaseConstraintCalendarSyncSummary> {
  const teamMembersSnapshot = await db.collection(collections.teamMembers).get();
  const syncSnapshot = await db.collection(collections.calendarSync).get();
  const managedEvents = managedConstraintEvents ??
    await listManagedCalendarEventsForSync(actor, environment, {kind: 'constraint'});

  const desiredConstraints = new Map<string, {
    teamMemberId: string;
    teamMemberData: Record<string, unknown>;
    constraint: Record<string, unknown>;
  }>();
  for (const memberDoc of teamMembersSnapshot.docs) {
    const teamMemberData = memberDoc.data() ?? {};
    const constraints = Array.isArray(teamMemberData['constraints'])
      ? teamMemberData['constraints'] as Array<Record<string, unknown>>
      : [];
    for (const constraint of constraints) {
      if (constraint['status'] !== 'approved' || constraint['constraintType'] !== 'unavailability') {
        continue;
      }
      const constraintId = requireString(constraint['id'], 'constraint.id');
      desiredConstraints.set(constraintId, {
        teamMemberId: memberDoc.id,
        teamMemberData,
        constraint,
      });
    }
  }

  const managedByConstraintId = new Map<string, ManagedCalendarEventSummary[]>();
  for (const managedEvent of managedEvents) {
    const constraintId = managedEvent.constraintId;
    if (constraintId == null || constraintId.length === 0) {
      continue;
    }
    const bucket = managedByConstraintId.get(constraintId) ?? [];
    bucket.push(managedEvent);
    managedByConstraintId.set(constraintId, bucket);
  }

  const syncByConstraintId = new Map<string, Record<string, unknown>>();
  for (const doc of syncSnapshot.docs) {
    syncByConstraintId.set(doc.id, doc.data() ?? {});
  }

  let changedCount = 0;
  let upToDateCount = 0;
  let removedOrphanedCount = 0;
  let cleanedSyncStateCount = 0;
  const failedConstraintIds: string[] = [];
  const deletedGoogleEventIds = new Set<string>();

  for (const [constraintId, desiredConstraint] of desiredConstraints.entries()) {
    try {
      const desired = buildDesiredConstraintCalendarState(
        desiredConstraint.teamMemberId,
        desiredConstraint.teamMemberData,
        desiredConstraint.constraint,
        environment,
      );
      const activeManagedEvents = (managedByConstraintId.get(constraintId) ?? [])
        .filter((event) => event.status !== 'cancelled');
      const currentManagedEvent = activeManagedEvents[0] ?? null;
      const syncData = syncByConstraintId.get(constraintId) ?? null;
      const currentStateCalendarEventId = optionalString(syncData?.['calendarEventId']) ?? '';
      const currentStateStatus = optionalString(syncData?.['status']) ?? '';
      const hasDuplicates = activeManagedEvents.length > 1;
      const needsUpsert = hasDuplicates ||
        !managedConstraintEventMatchesDesired(currentManagedEvent, desired);

      let finalCalendarEventId = currentManagedEvent?.id ?? currentStateCalendarEventId;
      let changed = false;

      if (needsUpsert) {
        const result = await executeCalendarAction(
          db,
          {
            memberId: actor.memberId,
            isAdmin: actor.isAdmin,
          },
          environment,
          'ensureConstraintEvent',
          {
            calendarEventId: finalCalendarEventId.length > 0 ? finalCalendarEventId : undefined,
            teamMember: desired.teamMemberPayload,
            constraint: desired.constraintPayload,
            isTestMode: environment === 'test',
          },
        );
        finalCalendarEventId = requireString(result['calendarEventId'], 'calendarEventId');
        changed = true;
      }

      for (const managedEvent of activeManagedEvents) {
        if (managedEvent.id === finalCalendarEventId || deletedGoogleEventIds.has(managedEvent.id)) {
          continue;
        }
        await deleteManagedConstraintEvent(actor, environment, managedEvent);
        deletedGoogleEventIds.add(managedEvent.id);
        changed = true;
      }

      if (
        currentStateCalendarEventId !== finalCalendarEventId ||
        currentStateStatus !== 'synced' ||
        optionalString(syncData?.['teamMemberId']) !== desiredConstraint.teamMemberId
      ) {
        await saveSyncedConstraintSyncState(
          collections,
          constraintId,
          desiredConstraint.teamMemberId,
          finalCalendarEventId,
        );
        changed = true;
      }

      if (changed) {
        changedCount += 1;
      } else {
        upToDateCount += 1;
      }
    } catch (error) {
      console.error(`Failed to reconcile constraint ${constraintId}:`, error);
      failedConstraintIds.push(constraintId);
    }
  }

  for (const doc of syncSnapshot.docs) {
    if (desiredConstraints.has(doc.id)) {
      continue;
    }

    const syncData = doc.data() ?? {};
    const calendarEventId = optionalString(syncData['calendarEventId']);
    const managedEvent = (managedByConstraintId.get(doc.id) ?? [])
      .find((event) => event.id === calendarEventId) ??
      (managedByConstraintId.get(doc.id) ?? [])[0] ??
      null;
    if (managedEvent != null && !deletedGoogleEventIds.has(managedEvent.id)) {
      try {
        await deleteManagedConstraintEvent(actor, environment, managedEvent);
        deletedGoogleEventIds.add(managedEvent.id);
        removedOrphanedCount += 1;
      } catch (error) {
        console.error(`Failed to remove orphaned constraint event ${managedEvent.id}:`, error);
      }
    }

    await doc.ref.delete();
    cleanedSyncStateCount += 1;
  }

  for (const managedEvent of managedEvents) {
    const constraintId = managedEvent.constraintId;
    if (
      constraintId == null ||
      desiredConstraints.has(constraintId) ||
      deletedGoogleEventIds.has(managedEvent.id)
    ) {
      continue;
    }

    try {
      await deleteManagedConstraintEvent(actor, environment, managedEvent);
      deletedGoogleEventIds.add(managedEvent.id);
      removedOrphanedCount += 1;
    } catch (error) {
      console.error(`Failed to remove orphaned constraint event ${managedEvent.id}:`, error);
    }
  }

  return {
    scannedCount: desiredConstraints.size,
    changedCount,
    upToDateCount,
    removedOrphanedCount,
    cleanedSyncStateCount,
    failedConstraintIds,
  };
}

async function syncCalendarAttendeesForEvent(
  actor: ActorContext,
  environment: EnvironmentMode,
  collections: Collections,
  eventId: string,
): Promise<{
  attempted: boolean;
  success: boolean;
}> {
  try {
    const eventDoc = await db.collection(collections.events).doc(eventId).get();
    if (!eventDoc.exists) {
      return {attempted: false, success: true};
    }

    const [syncDoc, managedEvents] = await Promise.all([
      db.collection(collections.eventCalendarSync).doc(eventId).get(),
      listManagedCalendarEventsForSync(actor, environment, {
        kind: 'app',
        eventId,
      }),
    ]);
    await reconcileSingleAppEventCalendar(
      actor,
      environment,
      collections,
      eventId,
      eventDoc.data() ?? {},
      managedEvents,
      syncDoc.exists ? syncDoc.data() ?? {} : null,
      new Map<string, Record<string, unknown> | null>(),
    );
    return {attempted: true, success: true};
  } catch (error) {
    console.error(
      `Failed to sync calendar attendees for event ${eventId}:`,
      error,
    );
    return {attempted: true, success: false};
  }
}

async function syncCalendarAttendeesForEvents(
  actor: ActorContext,
  environment: EnvironmentMode,
  collections: Collections,
  eventIds: Iterable<string>,
): Promise<void> {
  const uniqueEventIds = Array.from(new Set(
    Array.from(eventIds).filter((eventId) => eventId.trim().length > 0),
  ));

  for (const eventId of uniqueEventIds) {
    await syncCalendarAttendeesForEvent(actor, environment, collections, eventId);
  }
}

async function reconcileAppEventsFromDatabase(
  actor: ActorContext,
  environment: EnvironmentMode,
  collections: Collections,
  eventId?: string | null,
  managedAppEvents?: ManagedCalendarEventSummary[],
): Promise<AppEventCalendarSyncSummary> {
  const failedEventIds: string[] = [];
  let scannedCount = 0;
  let changedCount = 0;
  let upToDateCount = 0;
  let removedOrphanedCount = 0;
  let cleanedSyncStateCount = 0;
  const deletedGoogleEventIds = new Set<string>();
  const teamMemberCache = new Map<string, Record<string, unknown> | null>();

  if (eventId != null && eventId.trim().length > 0) {
    const normalizedEventId = eventId.trim();
    const eventDoc = await db.collection(collections.events).doc(normalizedEventId).get();
    if (!eventDoc.exists) {
      return {
        scannedCount: 0,
        changedCount: 0,
        upToDateCount: 0,
        failedEventIds,
        removedOrphanedCount: 0,
        cleanedSyncStateCount: 0,
      };
    }

    const [syncDoc, managedEvents] = await Promise.all([
      db.collection(collections.eventCalendarSync).doc(normalizedEventId).get(),
      listManagedCalendarEventsForSync(actor, environment, {
        kind: 'app',
        eventId: normalizedEventId,
      }),
    ]);
    scannedCount = 1;

    try {
      const result = await reconcileSingleAppEventCalendar(
        actor,
        environment,
        collections,
        normalizedEventId,
        eventDoc.data() ?? {},
        managedEvents,
        syncDoc.exists ? syncDoc.data() ?? {} : null,
        teamMemberCache,
      );
      if (result.changed) {
        changedCount = 1;
      } else {
        upToDateCount = 1;
      }
    } catch (error) {
      console.error(`Failed to reconcile app event ${normalizedEventId}:`, error);
      failedEventIds.push(normalizedEventId);
    }
  } else {
    const [eventsSnapshot, syncSnapshot, fetchedManagedEvents] = await Promise.all([
      db.collection(collections.events).get(),
      db.collection(collections.eventCalendarSync).get(),
      managedAppEvents != null
        ? Promise.resolve(managedAppEvents)
        : listManagedCalendarEventsForSync(actor, environment, {kind: 'app'}),
    ]);
    const managedEvents = fetchedManagedEvents;

    const managedByEventId = new Map<string, ManagedCalendarEventSummary[]>();
    for (const managedEvent of managedEvents) {
      const managedEventId = managedEvent.eventId;
      if (managedEventId == null || managedEventId.length === 0) {
        continue;
      }
      const bucket = managedByEventId.get(managedEventId) ?? [];
      bucket.push(managedEvent);
      managedByEventId.set(managedEventId, bucket);
    }

    const syncByEventId = new Map<string, Record<string, unknown>>();
    for (const doc of syncSnapshot.docs) {
      syncByEventId.set(doc.id, doc.data() ?? {});
    }

    scannedCount = eventsSnapshot.docs.length;
    const existingEventIds = new Set(eventsSnapshot.docs.map((doc) => doc.id));

    for (const doc of eventsSnapshot.docs) {
      const currentEventId = doc.id;
      try {
        const result = await reconcileSingleAppEventCalendar(
          actor,
          environment,
          collections,
          currentEventId,
          doc.data() ?? {},
          managedByEventId.get(currentEventId) ?? [],
          syncByEventId.get(currentEventId) ?? null,
          teamMemberCache,
        );
        if (result.changed) {
          changedCount += 1;
        } else {
          upToDateCount += 1;
        }
      } catch (error) {
        console.error(`Failed to reconcile app event ${currentEventId}:`, error);
        failedEventIds.push(currentEventId);
      }
    }

    for (const doc of syncSnapshot.docs) {
      if (existingEventIds.has(doc.id)) {
        continue;
      }

      const syncData = doc.data() ?? {};
      const storedCalendarIds = [
        optionalString(syncData['assemblyCalendarEventId']),
        optionalString(syncData['mainCalendarEventId']),
      ].filter((calendarEventId): calendarEventId is string =>
        calendarEventId != null && calendarEventId.length > 0,
      );
      for (const calendarEventId of storedCalendarIds) {
        if (deletedGoogleEventIds.has(calendarEventId)) {
          continue;
        }
        const managedEvent =
          (managedByEventId.get(doc.id) ?? []).find((event) => event.id === calendarEventId) ??
          (managedByEventId.get(doc.id) ?? []).find((event) => !deletedGoogleEventIds.has(event.id)) ??
          null;
        if (managedEvent == null) {
          continue;
        }
        try {
          await deleteManagedAppEvent(actor, environment, managedEvent);
          deletedGoogleEventIds.add(managedEvent.id);
          removedOrphanedCount += 1;
        } catch (error) {
          console.error(`Failed to remove orphaned app event ${managedEvent.id}:`, error);
        }
      }
      await doc.ref.delete();
      cleanedSyncStateCount += 1;
    }

    for (const managedEvent of managedEvents) {
      const managedEventId = managedEvent.eventId;
      if (
        managedEventId == null ||
        existingEventIds.has(managedEventId) ||
        deletedGoogleEventIds.has(managedEvent.id)
      ) {
        continue;
      }

      try {
        await deleteManagedAppEvent(actor, environment, managedEvent);
        deletedGoogleEventIds.add(managedEvent.id);
        removedOrphanedCount += 1;
      } catch (error) {
        console.error(`Failed to remove orphaned app event ${managedEvent.id}:`, error);
      }
    }
  }

  return {
    scannedCount,
    changedCount,
    upToDateCount,
    failedEventIds,
    removedOrphanedCount,
    cleanedSyncStateCount,
  };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function readInt(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

function formatCalendarDateOnly(date: Date): string {
  const normalized = normalizeDay(date);
  const year = normalized.getUTCFullYear().toString().padStart(4, '0');
  const month = String(normalized.getUTCMonth() + 1).padStart(2, '0');
  const day = String(normalized.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function getAvailableRoleKeys(teamMemberData: Record<string, unknown>): string[] {
  const roleCapabilities = teamMemberData['roleCapabilities'];
  if (roleCapabilities == null || typeof roleCapabilities !== 'object' || Array.isArray(roleCapabilities)) {
    return [];
  }

  return Object.entries(roleCapabilities as Record<string, unknown>)
    .filter(([, value]) => value === true)
    .map(([key]) => key);
}

function serializeTeamMemberForCalendarAction(
  teamMemberId: string,
  teamMemberData: Record<string, unknown>,
): Record<string, unknown> {
  return {
    id: teamMemberId,
    name: requireString(teamMemberData['name'] ?? teamMemberId, 'teamMember.name'),
    email: optionalString(teamMemberData['email']),
    availableRoleKeys: getAvailableRoleKeys(teamMemberData),
  };
}

function serializeConstraintForCalendarAction(
  constraint: Record<string, unknown>,
): Record<string, unknown> {
  const rawConstraintType =
    typeof constraint['constraintType'] === 'string'
      ? constraint['constraintType'].trim()
      : 'unavailability';
  const repeatTypeRaw =
    typeof constraint['repeatType'] === 'string'
      ? constraint['repeatType'].trim()
      : null;
  const repeatType =
    repeatTypeRaw === 'daily' || repeatTypeRaw === 'weekly' || repeatTypeRaw === 'monthly'
      ? repeatTypeRaw
      : null;
  const repeatDay = readInt(constraint['repeatDay']);

  return stripUndefined({
    id: requireString(constraint['id'], 'constraint.id'),
    startDate: formatCalendarDateOnly(asDate(constraint['startDate'], 'constraint.startDate')),
    endDate:
      constraint['endDate'] == null
        ? null
        : formatCalendarDateOnly(asDate(constraint['endDate'], 'constraint.endDate')),
    note: optionalString(constraint['note']),
    constraintType: rawConstraintType === 'availability' ? 'availability' : 'unavailability',
    startTime: optionalString(constraint['startTime']),
    endTime: optionalString(constraint['endTime']),
    repeatType,
    repeatDay: repeatDay ?? undefined,
    repeatEndDate:
      constraint['repeatEndDate'] == null
        ? null
        : formatCalendarDateOnly(asDate(constraint['repeatEndDate'], 'constraint.repeatEndDate')),
  });
}

async function updateConstraintStatusForTeamMember(
  collections: Collections,
  actor: ActorContext,
  teamMemberId: string,
  constraintId: string,
  newStatus: string,
  options: {
    note?: string | null;
    wasAutoRejectedFromCalendar?: boolean;
  } = {},
): Promise<boolean> {
  const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
  const memberDoc = await memberRef.get();
  if (!memberDoc.exists) {
    return false;
  }

  const memberData = memberDoc.data() ?? {};
  const teamMemberName =
    typeof memberData['name'] === 'string' ? memberData['name'] as string : null;
  const constraints = Array.isArray(memberData['constraints'])
    ? [...(memberData['constraints'] as Array<Record<string, unknown>>)]
    : [];
  const constraintIndex = constraints.findIndex((constraint) => constraint['id'] === constraintId);
  if (constraintIndex < 0) {
    return false;
  }

  const previousConstraint = constraints[constraintIndex];
  const wasAutoRejectedFromCalendar = options.wasAutoRejectedFromCalendar === true;
  const updatedConstraint = {
    ...constraints[constraintIndex],
    status: newStatus,
    ...(options.note != null ? {note: options.note} : {}),
    ...(options.wasAutoRejectedFromCalendar != null
      ? {wasAutoRejectedFromCalendar}
      : {}),
  };
  constraints[constraintIndex] = updatedConstraint;

  await memberRef.update({
    constraints,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await writeAuditLog(
    db,
    collections,
    actor,
    'constraint.updateStatus',
    getConstraintAuditEntityType(updatedConstraint),
    constraintId,
    buildConstraintAuditDetails(
      teamMemberId,
      teamMemberName,
      updatedConstraint,
      {
        newStatus,
        semanticAction: getConstraintStatusSemanticAction(
          newStatus,
          wasAutoRejectedFromCalendar,
        ) ?? undefined,
      },
    ),
    {
      before: previousConstraint,
      after: updatedConstraint,
    },
  );
  return true;
}

async function acquireConstraintSyncAction(
  collections: Collections,
  constraintId: string,
  teamMemberId: string,
): Promise<{
  action: 'create' | 'update';
  calendarEventId: string | null;
}> {
  return await db.runTransaction(async (transaction) => {
    const ref = db.collection(collections.calendarSync).doc(constraintId);
    const snapshot = await transaction.get(ref);
    if (snapshot.exists && snapshot.data()?.['status'] === 'synced') {
      return {
        action: 'update' as const,
        calendarEventId: optionalString(snapshot.data()?.['calendarEventId']),
      };
    }

    transaction.set(ref, {
      calendarEventId: '',
      teamMemberId,
      status: 'pending',
      syncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      retryCount: 0,
      errorMessage: null,
      reservedBy: Date.now(),
    });

    return {
      action: 'create' as const,
      calendarEventId: null,
    };
  });
}

async function saveFailedConstraintSyncState(
  collections: Collections,
  constraintId: string,
  teamMemberId: string,
  errorMessage: string,
  retryCount: number,
): Promise<void> {
  await db.collection(collections.calendarSync).doc(constraintId).set({
    calendarEventId: '',
    teamMemberId,
    status: 'failed',
    syncedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    retryCount,
    errorMessage,
  });
}

async function saveSyncedConstraintSyncState(
  collections: Collections,
  constraintId: string,
  teamMemberId: string,
  calendarEventId: string,
): Promise<void> {
  await db.collection(collections.calendarSync).doc(constraintId).set({
    calendarEventId,
    teamMemberId,
    status: 'synced',
    syncedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    retryCount: 0,
    errorMessage: null,
  });
}

async function retryConstraintCalendarSync(
  actor: ActorContext,
  environment: EnvironmentMode,
  collections: Collections,
  constraintId: string,
  teamMemberId: string,
  teamMemberData: Record<string, unknown>,
  constraint: Record<string, unknown>,
  currentRetryCount: number,
): Promise<boolean> {
  try {
    const syncAction = await acquireConstraintSyncAction(
      collections,
      constraintId,
      teamMemberId,
    );
    const teamMemberPayload = serializeTeamMemberForCalendarAction(
      teamMemberId,
      teamMemberData,
    );
    const constraintPayload = serializeConstraintForCalendarAction(constraint);

    if (syncAction.action === 'update') {
      if (syncAction.calendarEventId == null || syncAction.calendarEventId.length === 0) {
        throw new Error('Update action requested but no calendar event ID found');
      }

      await executeCalendarAction(
        db,
        {
          memberId: actor.memberId,
          isAdmin: actor.isAdmin,
        },
        environment,
        'updateConstraintEvent',
        {
          calendarEventId: syncAction.calendarEventId,
          teamMember: teamMemberPayload,
          constraint: constraintPayload,
          isTestMode: environment === 'test',
        },
      );
      return true;
    }

    const result = await executeCalendarAction(
      db,
      {
        memberId: actor.memberId,
        isAdmin: actor.isAdmin,
      },
      environment,
      'createConstraintEvent',
      {
        teamMember: teamMemberPayload,
        constraint: constraintPayload,
        isTestMode: environment === 'test',
      },
    );
    const calendarEventId = requireString(result['calendarEventId'], 'calendarEventId');
    await saveSyncedConstraintSyncState(
      collections,
      constraintId,
      teamMemberId,
      calendarEventId,
    );
    return true;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await saveFailedConstraintSyncState(
      collections,
      constraintId,
      teamMemberId,
      message,
      currentRetryCount + 1,
    );
    return false;
  }
}

async function syncConstraintCalendarStates(
  actor: ActorContext,
  environment: EnvironmentMode,
  collections: Collections,
): Promise<ConstraintCalendarSyncSummary> {
  const syncedSnapshot = await db
    .collection(collections.calendarSync)
    .where('status', '==', 'synced')
    .get();
  const failedSnapshot = await db
    .collection(collections.calendarSync)
    .where('status', '==', 'failed')
    .get();

  let rejectedCount = 0;
  let retriedCount = 0;
  let successCount = 0;
  let skippedCount = 0;
  const failedConstraintIds: string[] = [];
  const teamMemberCache = new Map<string, Record<string, unknown> | null>();

  const getTeamMember = async (teamMemberId: string): Promise<Record<string, unknown> | null> => {
    if (teamMemberCache.has(teamMemberId)) {
      return teamMemberCache.get(teamMemberId) ?? null;
    }

    const teamMemberData = await readTeamMemberById(db, collections, teamMemberId);
    teamMemberCache.set(teamMemberId, teamMemberData);
    return teamMemberData;
  };

  for (const doc of syncedSnapshot.docs) {
    const syncData = doc.data() ?? {};
    const calendarEventId = optionalString(syncData['calendarEventId']);
    const teamMemberId = optionalString(syncData['teamMemberId']);
    if (
      calendarEventId == null ||
      calendarEventId.length === 0 ||
      teamMemberId == null ||
      teamMemberId.length === 0
    ) {
      skippedCount += 1;
      continue;
    }

    const result = await executeCalendarAction(
      db,
      {
        memberId: actor.memberId,
        isAdmin: actor.isAdmin,
      },
      environment,
      'eventExists',
      {
        calendarEventId,
      },
    );
    const eventExists = result['exists'] === true;
    if (eventExists) {
      continue;
    }

    const updated = await updateConstraintStatusForTeamMember(
      collections,
      actor,
      teamMemberId,
      doc.id,
      'rejected',
      {
        wasAutoRejectedFromCalendar: true,
      },
    );
    await doc.ref.delete().catch(() => undefined);
    if (updated) {
      rejectedCount += 1;
    } else {
      skippedCount += 1;
    }
  }

  for (const doc of failedSnapshot.docs) {
    const syncData = doc.data() ?? {};
    const teamMemberId = optionalString(syncData['teamMemberId']);
    if (teamMemberId == null || teamMemberId.length === 0) {
      skippedCount += 1;
      continue;
    }

    const teamMemberData = await getTeamMember(teamMemberId);
    if (teamMemberData == null) {
      skippedCount += 1;
      continue;
    }

    const constraints = Array.isArray(teamMemberData['constraints'])
      ? teamMemberData['constraints'] as Array<Record<string, unknown>>
      : [];
    const constraint = constraints.find((entry) => entry['id'] === doc.id);
    if (constraint == null) {
      skippedCount += 1;
      continue;
    }

    retriedCount += 1;
    const currentRetryCount = readInt(syncData['retryCount']) ?? 0;
    if (currentRetryCount >= CALENDAR_SYNC_MAX_RETRY_ATTEMPTS) {
      failedConstraintIds.push(doc.id);
      continue;
    }

    const delayMs = Math.round(
      CALENDAR_SYNC_INITIAL_RETRY_DELAY_MS *
        (CALENDAR_SYNC_BACKOFF_MULTIPLIER * currentRetryCount),
    );
    const clampedDelayMs = Math.min(
      Math.max(delayMs, CALENDAR_SYNC_INITIAL_RETRY_DELAY_MS),
      CALENDAR_SYNC_MAX_RETRY_DELAY_MS,
    );
    await delay(clampedDelayMs);

    const success = await retryConstraintCalendarSync(
      actor,
      environment,
      collections,
      doc.id,
      teamMemberId,
      teamMemberData,
      constraint,
      currentRetryCount,
    );
    if (success) {
      successCount += 1;
    } else {
      failedConstraintIds.push(doc.id);
    }
  }

  return {
    scannedCount: syncedSnapshot.docs.length + failedSnapshot.docs.length,
    rejectedCount,
    retriedCount,
    successCount,
    skippedCount,
    failedConstraintIds,
  };
}

function buildEventsAndConstraintsSyncMessage(
  eventSummary: AppEventCalendarSyncSummary,
  constraintSummary: DatabaseConstraintCalendarSyncSummary,
): string {
  const parts = [
    `אירועים: בוצעו שינויים ב-${eventSummary.changedCount} מתוך ${eventSummary.scannedCount}, ${eventSummary.upToDateCount} כבר היו תקינים, נכשלו ${eventSummary.failedEventIds.length}.`,
    `מגבלות: בוצעו שינויים ב-${constraintSummary.changedCount} מתוך ${constraintSummary.scannedCount}, ${constraintSummary.upToDateCount} כבר היו תקינות, נכשלו ${constraintSummary.failedConstraintIds.length}.`,
  ];

  if (eventSummary.removedOrphanedCount > 0) {
    parts.push(`אירועים: נמחקו ${eventSummary.removedOrphanedCount} אירועים יתומים מיומן גוגל.`);
  }
  if (eventSummary.cleanedSyncStateCount > 0) {
    parts.push(`אירועים: נוקו ${eventSummary.cleanedSyncStateCount} רשומות סנכרון ישנות.`);
  }
  if (constraintSummary.removedOrphanedCount > 0) {
    parts.push(`מגבלות: נמחקו ${constraintSummary.removedOrphanedCount} אירועים יתומים מיומן גוגל.`);
  }
  if (constraintSummary.cleanedSyncStateCount > 0) {
    parts.push(`מגבלות: נוקו ${constraintSummary.cleanedSyncStateCount} רשומות סנכרון ישנות.`);
  }

  return `סנכרון אירועים ומגבלות הושלם. ${parts.join(' ')}`;
}

async function createSession(
  firestore: Firestore,
  collections: Collections,
  memberId: string,
  uniqueKey: string,
  isAdmin: boolean,
): Promise<{sessionToken: string; expiresAt: string}> {
  const sessionToken = randomBytes(48).toString('hex');
  const sessionHash = hashSessionToken(sessionToken);
  const now = Timestamp.now();
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000));

  await firestore.collection(collections.privateSessions).doc(sessionHash).set({
    memberId,
    uniqueKey,
    isAdmin,
    createdAt: now,
    updatedAt: now,
    lastUsedAt: now,
    expiresAt,
  });

  return {
    sessionToken,
    expiresAt: expiresAt.toDate().toISOString(),
  };
}

async function authenticateRequest(request: Request): Promise<{
  actor: ActorContext;
  environment: EnvironmentMode;
  collections: Collections;
}> {
  const header = request.header('authorization');
  if (!header || !header.startsWith('Bearer ')) {
    throw new HttpError(401, 'Missing session token');
  }

  const token = header.substring('Bearer '.length).trim();
  if (token.length === 0) {
    throw new HttpError(401, 'Missing session token');
  }

  let decodedToken;
  try {
    decodedToken = await auth.verifyIdToken(token);
  } catch (error) {
    throw new HttpError(401, 'Invalid session token');
  }

  const environment = getEnvironmentMode(request.body?.environment);
  const collections = getCollections(environment);
  const memberId = requireString(decodedToken.uid, 'token.uid');
  const memberDoc = await db.collection(collections.teamMembers).doc(memberId).get();
  if (!memberDoc.exists) {
    throw new HttpError(401, 'User no longer exists');
  }

  const memberData = memberDoc.data() ?? {};
  if (memberData['isActive'] !== true || memberData['isArchived'] === true) {
    throw new HttpError(403, 'User is no longer active');
  }

  return {
    environment,
    collections,
    actor: {
      memberId,
      uniqueKey: requireString(memberData['uniqueKey'] ?? memberId, 'member.uniqueKey'),
      isAdmin: memberData['isAdmin'] === true,
      sessionId: '',
      expiresAt: Timestamp.now(),
      member: memberData,
    },
  };
}

function getConstraintStatusSemanticAction(
  newStatus: unknown,
  wasAutoRejectedFromCalendar = false,
): string | null {
  if (wasAutoRejectedFromCalendar) {
    return 'autoreject';
  }

  if (typeof newStatus !== 'string' || newStatus.trim().length === 0) {
    return null;
  }

  switch (newStatus.trim().toLowerCase()) {
    case 'approved':
      return 'approve';
    case 'rejected':
      return 'reject';
    case 'pending':
      return 'returntopending';
    default:
      return null;
  }
}

function getChecklistUpdateSemanticAction(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): string | null {
  const diff = buildAuditDiff(before, after, ['createdAt', 'updatedAt', 'statusLastUpdatedAt']);
  const changedKeys = new Set([
    ...Object.keys(diff.oldValue ?? {}),
    ...Object.keys(diff.newValue ?? {}),
  ]);

  if (changedKeys.size !== 1 || !changedKeys.has('status')) {
    return null;
  }

  if (after['status'] === true) {
    return 'complete';
  }

  if (after['status'] === false) {
    return 'reopen';
  }

  return null;
}

function normalizeAuditActionType(
  operation: string,
  details: Record<string, unknown> = {},
): string {
  const raw = operation.trim().toLowerCase();
  const finalSegment = raw.split('.').at(-1) ?? raw;
  const explicitSemanticAction = optionalString(details['semanticAction']);

  if (explicitSemanticAction != null && explicitSemanticAction.trim().length > 0) {
    return explicitSemanticAction.trim().toLowerCase();
  }

  if (finalSegment === 'updatestatus') {
    const semanticAction = getConstraintStatusSemanticAction(
      details['newStatus'],
      details['wasAutoRejectedFromCalendar'] === true,
    );
    if (semanticAction != null) {
      return semanticAction;
    }
  }

  switch (finalSegment) {
    case 'insert':
      return 'create';
    case 'edit':
      return 'update';
    default:
      return finalSegment;
  }
}

function getAuditEntityName(details: Record<string, unknown>): string | null {
  const name = details['name'];
  if (typeof name === 'string' && name.trim().length > 0) {
    return name.trim();
  }

  const entityName = details['entityName'];
  if (typeof entityName === 'string' && entityName.trim().length > 0) {
    return entityName.trim();
  }

  return null;
}

function optionalDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'string' && value.trim().length > 0 && !Number.isNaN(Date.parse(value))) {
    return new Date(value);
  }
  return null;
}

function formatIsraelDateOnly(date: Date): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Jerusalem',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

function getConstraintRepeatTypeLabel(value: unknown): string | null {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return null;
  }

  switch (value.trim().toLowerCase()) {
    case 'daily':
      return 'יומי';
    case 'weekly':
      return 'שבועי';
    case 'monthly':
      return 'חודשי';
    default:
      return value;
  }
}

function getConstraintAuditEntityType(
  constraint: Record<string, unknown> | null | undefined,
): string {
  return constraint?.['constraintType'] === 'availability'
    ? 'availability'
    : 'constraint';
}

function buildConstraintSummary(
  constraint: Record<string, unknown> | null | undefined,
): string | null {
  if (constraint == null) {
    return null;
  }

  const startDate = optionalDate(constraint['startDate']);
  const endDate = optionalDate(constraint['endDate']);
  const startTime =
    typeof constraint['startTime'] === 'string' &&
      constraint['startTime'].trim().length > 0
      ? constraint['startTime'].trim()
      : null;
  const endTime =
    typeof constraint['endTime'] === 'string' &&
      constraint['endTime'].trim().length > 0
      ? constraint['endTime'].trim()
      : null;
  const note =
    typeof constraint['note'] === 'string' && constraint['note'].trim().length > 0
      ? constraint['note'].trim()
      : null;
  const repeatTypeLabel = getConstraintRepeatTypeLabel(constraint['repeatType']);

  const parts: string[] = [];

  if (repeatTypeLabel != null) {
    parts.push(repeatTypeLabel);
  }

  if (startDate != null) {
    const startText = formatIsraelDateOnly(startDate);
    const endText = endDate == null ? null : formatIsraelDateOnly(endDate);
    parts.push(endText == null || endText === startText
      ? startText
      : `${startText} - ${endText}`);
  }

  if (startTime != null || endTime != null) {
    parts.push(startTime != null && endTime != null
      ? `${startTime} - ${endTime}`
      : (startTime ?? endTime)!);
  }

  if (note != null) {
    parts.push(note);
  }

  return parts.length > 0 ? parts.join(' | ') : null;
}

function buildConstraintAuditDetails(
  teamMemberId: string,
  teamMemberName: string | null,
  constraint: Record<string, unknown> | null | undefined,
  extras: Record<string, unknown> = {},
): Record<string, unknown> {
  return stripUndefined({
    teamMemberId,
    teamMemberName: teamMemberName ?? undefined,
    constraintType:
      typeof constraint?.['constraintType'] === 'string'
        ? constraint['constraintType']
        : undefined,
    startDate: constraint?.['startDate'] ?? undefined,
    endDate: constraint?.['endDate'] ?? undefined,
    startTime:
      typeof constraint?.['startTime'] === 'string'
        ? constraint['startTime']
        : undefined,
    endTime:
      typeof constraint?.['endTime'] === 'string'
        ? constraint['endTime']
        : undefined,
    note:
      typeof constraint?.['note'] === 'string' &&
        constraint['note'].trim().length > 0
        ? constraint['note']
        : undefined,
    status:
      typeof constraint?.['status'] === 'string'
        ? constraint['status']
        : undefined,
    repeatType:
      typeof constraint?.['repeatType'] === 'string'
        ? constraint['repeatType']
        : undefined,
    repeatDay:
      typeof constraint?.['repeatDay'] === 'number'
        ? constraint['repeatDay']
        : undefined,
    repeatEndDate: constraint?.['repeatEndDate'] ?? undefined,
    wasAutoRejectedFromCalendar:
      constraint?.['wasAutoRejectedFromCalendar'] === true ? true : undefined,
    constraintSummary: buildConstraintSummary(constraint) ?? undefined,
    ...extras,
  });
}

function buildAssignmentAuditDetails(
  assignment: Record<string, unknown> | null | undefined,
  extras: Record<string, unknown> = {},
): Record<string, unknown> {
  return stripUndefined({
    eventId:
      typeof assignment?.['eventId'] === 'string'
        ? assignment['eventId']
        : undefined,
    eventName:
      typeof extras['eventName'] === 'string' && String(extras['eventName']).trim().length > 0
        ? extras['eventName']
        : undefined,
    teamMemberId:
      typeof assignment?.['teamMemberId'] === 'string'
        ? assignment['teamMemberId']
        : undefined,
    teamMemberName:
      typeof extras['teamMemberName'] === 'string' && String(extras['teamMemberName']).trim().length > 0
        ? extras['teamMemberName']
        : undefined,
    roleType:
      typeof assignment?.['roleType'] === 'string'
        ? assignment['roleType']
        : undefined,
    status:
      typeof assignment?.['status'] === 'string'
        ? assignment['status']
        : undefined,
    ...extras,
  });
}

function buildChecklistItemAuditDetails(
  checklistItem: Record<string, unknown> | null | undefined,
  extras: Record<string, unknown> = {},
): Record<string, unknown> {
  return stripUndefined({
    name:
      typeof checklistItem?.['name'] === 'string'
        ? checklistItem['name']
        : undefined,
    responsibleId:
      typeof checklistItem?.['responsibleId'] === 'string'
        ? checklistItem['responsibleId']
        : undefined,
    responsibleName:
      typeof extras['responsibleName'] === 'string' &&
        String(extras['responsibleName']).trim().length > 0
        ? extras['responsibleName']
        : undefined,
    status:
      typeof checklistItem?.['status'] === 'boolean'
        ? checklistItem['status']
        : undefined,
    createdByAdminId:
      typeof checklistItem?.['createdByAdminId'] === 'string'
        ? checklistItem['createdByAdminId']
        : undefined,
    ...extras,
  });
}

function formatIsraelTimestamp(date: Date): string {
  const formatter = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Jerusalem',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    fractionalSecondDigits: 3,
    hour12: false,
  });

  const partMap: Record<string, string> = {};
  for (const part of formatter.formatToParts(date)) {
    if (part.type !== 'literal') {
      partMap[part.type] = part.value;
    }
  }

  return `${partMap['year']}-${partMap['month']}-${partMap['day']}`
      + `T${partMap['hour']}:${partMap['minute']}:${partMap['second']}`
      + `.${partMap['fractionalSecond'] ?? '000'}`;
}

function normalizeAuditValue(value: unknown): unknown {
  if (value == null) {
    return null;
  }

  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (Array.isArray(value)) {
    return value.map((item) => normalizeAuditValue(item));
  }

  if (typeof value === 'object') {
    const normalized: Record<string, unknown> = {};
    for (const [key, entryValue] of Object.entries(
      value as Record<string, unknown>,
    ).sort(([left], [right]) => left.localeCompare(right))) {
      if (entryValue === undefined) {
        continue;
      }
      normalized[key] = normalizeAuditValue(entryValue);
    }
    return normalized;
  }

  if (typeof value === 'bigint') {
    return value.toString();
  }

  return value;
}

function normalizeAuditRecord(
  value: Record<string, unknown> | null | undefined,
): Record<string, unknown> | null {
  if (value == null) {
    return null;
  }

  return normalizeAuditValue(value) as Record<string, unknown>;
}

function auditValuesEqual(left: unknown, right: unknown): boolean {
  return JSON.stringify(normalizeAuditValue(left)) ===
    JSON.stringify(normalizeAuditValue(right));
}

function buildAuditDiff(
  before: Record<string, unknown> | null | undefined,
  after: Record<string, unknown> | null | undefined,
  ignoreKeys: string[] = [],
): {
  changes: Record<string, unknown> | null;
  oldValue: Record<string, unknown> | null;
  newValue: Record<string, unknown> | null;
} {
  const normalizedBefore = normalizeAuditRecord(before);
  const normalizedAfter = normalizeAuditRecord(after);

  if (normalizedBefore == null && normalizedAfter == null) {
    return {
      changes: null,
      oldValue: null,
      newValue: null,
    };
  }

  const ignored = new Set(ignoreKeys);
  const keys = Array.from(
    new Set([
      ...Object.keys(normalizedBefore ?? {}),
      ...Object.keys(normalizedAfter ?? {}),
    ]),
  )
    .filter((key) => !ignored.has(key))
    .sort((left, right) => left.localeCompare(right));

  const changes: Record<string, unknown> = {};
  const oldValue: Record<string, unknown> = {};
  const newValue: Record<string, unknown> = {};

  for (const key of keys) {
    const beforeValue = normalizedBefore?.[key] ?? null;
    const afterValue = normalizedAfter?.[key] ?? null;

    if (auditValuesEqual(beforeValue, afterValue)) {
      continue;
    }

    changes[key] = {
      oldValue: beforeValue,
      newValue: afterValue,
    };
    oldValue[key] = beforeValue;
    newValue[key] = afterValue;
  }

  return {
    changes: Object.keys(changes).length > 0 ? changes : null,
    oldValue: Object.keys(oldValue).length > 0 ? oldValue : null,
    newValue: Object.keys(newValue).length > 0 ? newValue : null,
  };
}

async function writeAuditLog(
  firestore: Firestore,
  collections: Collections,
  actor: ActorContext,
  operation: string,
  entityType: string,
  entityId: string,
  details: Record<string, unknown> = {},
  diffContext: {
    before?: Record<string, unknown> | null;
    after?: Record<string, unknown> | null;
    ignoreKeys?: string[];
  } = {},
  operationContext: {
    operationId?: string;
    parentOperationId?: string | null;
  } = {},
): Promise<string> {
  const performerName = typeof actor.member['name'] === 'string'
    ? (actor.member['name'] as string)
    : null;
  const diff = buildAuditDiff(
    diffContext.before,
    diffContext.after,
    diffContext.ignoreKeys ?? ['createdAt', 'updatedAt', 'statusLastUpdatedAt'],
  );
  const operationId = typeof operationContext.operationId === 'string' &&
      operationContext.operationId.trim().length > 0
    ? operationContext.operationId.trim()
    : randomUUID();
  const parentOperationId = typeof operationContext.parentOperationId === 'string' &&
      operationContext.parentOperationId.trim().length > 0
    ? operationContext.parentOperationId.trim()
    : null;

  await firestore.collection(collections.logs).add({
    timestampUtc: FieldValue.serverTimestamp(),
    timestampLocalIsrael: formatIsraelTimestamp(new Date()),
    actionType: normalizeAuditActionType(operation, details),
    operation,
    entityType,
    entityId,
    entityName: getAuditEntityName(details),
    performerId: actor.memberId,
    performerUniqueKey: actor.uniqueKey,
    performerName,
    status: 'success',
    source: 'cloud_function',
    changes: diff.changes,
    oldValue: diff.oldValue,
    newValue: diff.newValue,
    details,
    operationId,
    ...(parentOperationId == null ? {} : {parentOperationId}),
  });

  return operationId;
}

async function ensureFirebaseAuthUser(
  memberId: string,
  memberData: Record<string, unknown>,
): Promise<void> {
  const displayName = typeof memberData['name'] === 'string'
    ? (memberData['name'] as string)
    : undefined;
  const disabled = memberData['isActive'] !== true || memberData['isArchived'] === true;

  try {
    await auth.updateUser(memberId, stripUndefined({
      displayName,
      disabled,
    }));
  } catch (error) {
    const errorCode = error instanceof Error && 'code' in error
      ? String((error as {code?: unknown}).code)
      : '';
    if (errorCode !== 'auth/user-not-found') {
      throw error;
    }

    await auth.createUser(stripUndefined({
      uid: memberId,
      displayName,
      disabled,
    }));
  }
}

function requireAdmin(actor: ActorContext): void {
  if (!actor.isAdmin) {
    throw new HttpError(403, 'Admin access is required');
  }
}

function requireSelfOrAdmin(actor: ActorContext, memberId: string): void {
  if (!actor.isAdmin && actor.memberId !== memberId) {
    throw new HttpError(403, 'You do not have access to this resource');
  }
}

function teamMemberDocFromJson(member: Record<string, unknown>, existing?: Record<string, unknown>): Record<string, unknown> {
  const next = stripUndefined({
    id: member['id'],
    name: member['name'],
    isActive: member['isActive'],
    isPermanent: member['isPermanent'] ?? false,
    isArchived: member['isArchived'] ?? false,
    constraints: member['constraints'] ?? [],
    roleCapabilities: member['roleCapabilities'] ?? {},
    comments: member['comments'] ?? '',
    createdAt: toTimestamp(member['createdAt'], 'member.createdAt'),
    updatedAt: toTimestamp(member['updatedAt'], 'member.updatedAt'),
    uniqueKey: member['uniqueKey'] ?? existing?.['uniqueKey'],
    isAdmin: member['isAdmin'] ?? false,
    passcodeLength: member['passcodeLength'] ?? existing?.['passcodeLength'] ?? null,
    allowMultipleAssignments: member['allowMultipleAssignments'] ?? false,
    phoneNumber: member['phoneNumber'] ?? null,
    email: member['email'] ?? null,
    birthday: member['birthday'] == null ? null : toTimestamp(member['birthday'], 'member.birthday'),
    canAccessSummaryScreen: member['canAccessSummaryScreen'] ?? false,
    canAccessShamapExport: member['canAccessShamapExport'] ?? false,
    canAccessConstraintsExamining: member['canAccessConstraintsExamining'] ?? false,
    vehicleInfo: member['vehicleInfo'] ?? null,
    availableEventIds: member['availableEventIds'] ?? [],
  });

  return next;
}

function eventDocFromJson(event: Record<string, unknown>): Record<string, unknown> {
  return stripUndefined({
    id: event['id'],
    name: event['name'],
    startDate: toDayTimestamp(event['startDate'], 'event.startDate'),
    endDate: toDayTimestamp(event['endDate'], 'event.endDate'),
    startTime: event['startTime'] ?? '',
    endTime: event['endTime'] ?? '',
    assemblyTime: event['assemblyTime'] ?? '',
    actualShowStartTime: event['actualShowStartTime'] ?? '',
    location: event['location'] ?? '',
    parkingLocation: event['parkingLocation'] ?? null,
    parkingEditorIds: event['parkingEditorIds'] ?? [],
    requiresArmed: event['requiresArmed'] ?? false,
    comments: event['comments'] ?? '',
    categoryId: event['categoryId'] ?? null,
    roleRequirements: event['roleRequirements'] ?? {},
    createdAt: toTimestamp(event['createdAt'], 'event.createdAt'),
    updatedAt: toTimestamp(event['updatedAt'], 'event.updatedAt'),
    driveFolderId: event['driveFolderId'] ?? null,
    driveFolderLink: event['driveFolderLink'] ?? null,
    isArchived: event['isArchived'] ?? false,
    relevantForExtendedTeam: event['relevantForExtendedTeam'] ?? false,
  });
}

function assignmentDocFromJson(assignment: Record<string, unknown>): Record<string, unknown> {
  return stripUndefined({
    id: assignment['id'],
    eventId: assignment['eventId'],
    teamMemberId: assignment['teamMemberId'],
    roleType: assignment['roleType'],
    slotIndex: assignment['slotIndex'] ?? 0,
    status: assignment['status'] ?? 'pending',
    notes: assignment['notes'] ?? '',
    semanticLabelId: normalizeOptionalText(assignment['semanticLabelId']),
    alternativePhoneNumber: assignment['alternativePhoneNumber'] ?? null,
    createdAt: toTimestamp(assignment['createdAt'], 'assignment.createdAt'),
    updatedAt: toTimestamp(assignment['updatedAt'], 'assignment.updatedAt'),
  });
}

function assignmentLabelDocFromJson(
  label: Record<string, unknown>,
): Record<string, unknown> {
  return stripUndefined({
    id: label['id'],
    key: label['key'],
    hebrewName: label['hebrewName'],
    color: label['color'] ?? '#1565C0',
    sortOrder: label['sortOrder'] ?? 0,
    isActive: label['isActive'] ?? true,
    createdAt: toTimestamp(label['createdAt'], 'label.createdAt'),
    updatedAt: toTimestamp(label['updatedAt'], 'label.updatedAt'),
  });
}

function checklistNotesToFirestore(rawNotes: unknown): Array<Record<string, unknown>> {
  if (!Array.isArray(rawNotes)) return [];
  return rawNotes.map((note) => {
    const data = note as Record<string, unknown>;
    return stripUndefined({
      id: data['id'],
      content: data['content'],
      createdAt: toTimestamp(data['createdAt'], 'note.createdAt'),
      createdByTeamMemberId: data['createdByTeamMemberId'],
      createdByTeamMemberName: data['createdByTeamMemberName'] ?? null,
      authorRole: data['authorRole'] ?? null,
    });
  });
}

function checklistItemDocFromJson(item: Record<string, unknown>): Record<string, unknown> {
  return stripUndefined({
    eventId: item['eventId'],
    name: item['name'],
    responsibleId: item['responsibleId'],
    notes: checklistNotesToFirestore(item['notes']),
    ccIds: item['ccIds'] ?? [],
    status: item['status'] ?? false,
    createdAt: toTimestamp(item['createdAt'], 'checklistItem.createdAt'),
    updatedAt: toTimestamp(item['updatedAt'], 'checklistItem.updatedAt'),
    statusLastUpdatedAt: toTimestamp(
      item['statusLastUpdatedAt'],
      'checklistItem.statusLastUpdatedAt',
    ),
    createdByAdminId: item['createdByAdminId'] ?? null,
  });
}

function presetDocFromJson(preset: Record<string, unknown>): Record<string, unknown> {
  return stripUndefined({
    name: preset['name'],
    items: Array.isArray(preset['items']) ? preset['items'] : [],
    createdAt: toTimestamp(preset['createdAt'], 'preset.createdAt'),
    updatedAt: toTimestamp(preset['updatedAt'], 'preset.updatedAt'),
  });
}

function parseConstraint(constraint: Record<string, unknown>): Record<string, unknown> {
  return {
    ...constraint,
    startDate: asDate(constraint['startDate'], 'constraint.startDate'),
    endDate: constraint['endDate'] == null ? null : asDate(constraint['endDate'], 'constraint.endDate'),
    repeatEndDate:
      constraint['repeatEndDate'] == null
        ? null
        : asDate(constraint['repeatEndDate'], 'constraint.repeatEndDate'),
  };
}

function constraintMatchesDate(constraint: Record<string, unknown>, date: Date): boolean {
  const startDate = normalizeDayInIsrael(constraint['startDate'] as Date);
  const endDate = constraint['endDate'] == null
    ? startDate
    : normalizeDayInIsrael(constraint['endDate'] as Date);
  const repeatType = typeof constraint['repeatType'] === 'string' ? constraint['repeatType'] : null;
  const repeatDay = typeof constraint['repeatDay'] === 'number' ? constraint['repeatDay'] : null;
  const repeatEndDate = constraint['repeatEndDate'] == null
    ? null
    : normalizeDayInIsrael(constraint['repeatEndDate'] as Date);
  const target = normalizeDayInIsrael(date);

  if (repeatType == null) {
    return target >= startDate && target <= endDate;
  }

  if (repeatEndDate == null || target < startDate || target > repeatEndDate) {
    return false;
  }

  if (repeatType === 'daily') return true;
  if (repeatType === 'weekly') {
    const weekday = target.getUTCDay() === 0 ? 7 : target.getUTCDay();
    return repeatDay === weekday;
  }
  if (repeatType === 'monthly') {
    return repeatDay === target.getUTCDate();
  }
  return false;
}

function constraintBlocksEvent(
  constraint: Record<string, unknown>,
  eventData: Record<string, unknown>,
): boolean {
  const constraintStart = optionalString(constraint['startTime']);
  const constraintEnd = optionalString(constraint['endTime']);
  if (constraintStart == null && constraintEnd == null) {
    return true;
  }
  const eventStartRaw = requireString(
    typeof eventData['assemblyTime'] === 'string' &&
      (eventData['assemblyTime'] as string).length > 0
      ? eventData['assemblyTime']
      : eventData['startTime'],
    'event.startTime',
  );
  const eventEndRaw = requireString(eventData['endTime'], 'event.endTime');
  return timesOverlap(constraintStart, constraintEnd, eventStartRaw, eventEndRaw);
}

function memberAvailableForEvent(
  memberData: Record<string, unknown>,
  eventData: Record<string, unknown>,
): boolean {
  if (memberData['isArchived'] === true || memberData['isActive'] !== true) {
    return false;
  }

  const isPermanent = memberData['isPermanent'] === true;
  const constraints = Array.isArray(memberData['constraints'])
    ? memberData['constraints'].map((item) => parseConstraint(item as Record<string, unknown>))
    : [];
  const eventStart = asDate(eventData['startDate'], 'event.startDate');
  const eventEnd = asDate(eventData['endDate'], 'event.endDate');

  if (isPermanent) {
    for (let day = normalizeDayInIsrael(eventStart); day <= normalizeDayInIsrael(eventEnd); day = addDays(day, 1)) {
      for (const constraint of constraints) {
        if (constraint['status'] !== 'approved') continue;
        if (constraint['constraintType'] !== 'unavailability') continue;
        if (!constraintMatchesDate(constraint, day)) continue;
        if (constraintBlocksEvent(constraint, eventData)) {
          return false;
        }
      }
    }
    return true;
  }

  const availableEventIds = Array.isArray(memberData['availableEventIds'])
    ? memberData['availableEventIds'].map((value) => String(value))
    : [];
  if (availableEventIds.includes(requireString(eventData['id'], 'event.id'))) {
    return true;
  }

  for (let day = normalizeDayInIsrael(eventStart); day <= normalizeDayInIsrael(eventEnd); day = addDays(day, 1)) {
    let availableOnDay = false;
    for (const constraint of constraints) {
      if (constraint['status'] !== 'approved') continue;
      if (constraint['constraintType'] !== 'availability') continue;
      if (!constraintMatchesDate(constraint, day)) continue;
      if (constraintBlocksEvent(constraint, eventData)) {
        availableOnDay = true;
        break;
      }
    }
    if (!availableOnDay) {
      return false;
    }
  }
  return true;
}

async function validateAssignmentPayload(
  firestore: Firestore,
  collections: Collections,
  assignment: Record<string, unknown>,
  ignoreAssignmentId?: string,
  options?: {
    bypassAvailability?: boolean;
  },
): Promise<void> {
  const eventId = requireString(assignment['eventId'], 'assignment.eventId');
  const teamMemberId = requireString(assignment['teamMemberId'], 'assignment.teamMemberId');
  const roleType = requireString(assignment['roleType'], 'assignment.roleType');
  const semanticLabelId = normalizeOptionalText(assignment['semanticLabelId']);

  const reads = [
    firestore.collection(collections.events).doc(eventId).get(),
    firestore.collection(collections.teamMembers).doc(teamMemberId).get(),
  ];
  if (semanticLabelId != null) {
    reads.push(
      firestore.collection(collections.assignmentLabels).doc(semanticLabelId).get(),
    );
  }

  const [eventDoc, memberDoc, semanticLabelDoc] = await Promise.all(reads);

  if (!eventDoc.exists) {
    throw new HttpError(400, 'אירוע לא נמצא');
  }
  if (!memberDoc.exists) {
    throw new HttpError(400, 'חבר צוות לא נמצא');
  }
  if (semanticLabelId != null && !semanticLabelDoc?.exists) {
    throw new HttpError(400, 'סיווג השיבוץ לא נמצא');
  }

  const eventData = eventDoc.data() ?? {};
  const memberData = memberDoc.data() ?? {};

  const roleCapabilities =
    (memberData['roleCapabilities'] as Record<string, unknown> | undefined) ?? {};
  if (roleCapabilities[roleType] !== true) {
    throw new HttpError(400, 'חבר/ת הצוות אינו/ה מוסמך/ת לתפקיד זה');
  }

  if (memberData['isActive'] !== true) {
    throw new HttpError(400, 'לא ניתן לשבץ חבר/ת צוות לא פעיל/ה');
  }

  if (memberData['allowMultipleAssignments'] !== true) {
    const duplicates = await firestore
      .collection(collections.assignments)
      .where('eventId', '==', eventId)
      .get();
    const hasDuplicate = duplicates.docs.some((doc) => {
      if (doc.id === ignoreAssignmentId) {
        return false;
      }

      const data = doc.data();
      return (
        data['teamMemberId'] === teamMemberId &&
        data['roleType'] === roleType
      );
    });
    if (hasDuplicate) {
      throw new HttpError(400, 'חבר/ת הצוות כבר משובץ/ת לתפקיד זה באירוע');
    }
  }

  if (
    options?.bypassAvailability !== true &&
    memberData['allowMultipleAssignments'] !== true &&
    !memberAvailableForEvent(memberData, eventData)
  ) {
    throw new HttpError(400, 'חבר/ת הצוות לא זמין/ה לאירוע זה');
  }
}

async function validateAssignmentMetadataPayload(
  firestore: Firestore,
  collections: Collections,
  payload: Record<string, unknown>,
): Promise<{
  notes: string;
  semanticLabelId: string | null;
  alternativePhoneNumber: string | null;
}> {
  const notes = typeof payload['notes'] === 'string' ? payload['notes'] : '';
  const semanticLabelId = normalizeOptionalText(payload['semanticLabelId']);

  if (semanticLabelId != null) {
    const semanticLabelDoc = await firestore
      .collection(collections.assignmentLabels)
      .doc(semanticLabelId)
      .get();
    if (!semanticLabelDoc.exists) {
      throw new HttpError(400, 'סיווג השיבוץ לא נמצא');
    }
  }

  return {
    notes,
    semanticLabelId,
    alternativePhoneNumber: normalizeOptionalText(payload['alternativePhoneNumber']),
  };
}

async function getUtilitiesListsDoc(): Promise<Record<string, unknown>> {
  const doc = await db.collection('utilities').doc('Lists').get();
  return doc.exists ? (doc.data() ?? {}) : {};
}

function getRolesArray(listsData: Record<string, unknown>): Array<Record<string, unknown>> {
  return Array.isArray(listsData['Roles'])
    ? (listsData['Roles'] as Array<Record<string, unknown>>)
    : [];
}

function getCategoriesArray(listsData: Record<string, unknown>): Array<Record<string, unknown>> {
  return Array.isArray(listsData['Categories'])
    ? (listsData['Categories'] as Array<Record<string, unknown>>)
    : [];
}

async function executeMutation(
  actor: ActorContext,
  environment: EnvironmentMode,
  collections: Collections,
  operation: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  switch (operation) {
    case 'teamMember.insert': {
      requireAdmin(actor);
      const member = payload['member'] as Record<string, unknown>;
      const memberId = requireString(member['id'], 'member.id');
      const nextMember = {
        ...teamMemberDocFromJson(member),
        passcodeLength: DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH,
      };
      await db.collection(collections.teamMembers).doc(memberId).set(nextMember);
      await upsertPrivatePasscodeCredential(
        collections,
        memberId,
        DEFAULT_TEAM_MEMBER_PASSCODE,
        DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH,
      );
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
        name: member['name'],
      }, {
        after: nextMember,
      });
      return {ok: true};
    }

    case 'teamMember.update': {
      const member = payload['member'] as Record<string, unknown>;
      const memberId = requireString(member['id'], 'member.id');
      const docRef = db.collection(collections.teamMembers).doc(memberId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }
      const existing = existingDoc.data() ?? {};
      let next = teamMemberDocFromJson(member, existing);
      if (!actor.isAdmin) {
        requireSelfOrAdmin(actor, memberId);
        next = {
          ...existing,
          phoneNumber: next['phoneNumber'] ?? null,
          email: next['email'] ?? null,
          birthday: next['birthday'] ?? null,
          vehicleInfo: next['vehicleInfo'] ?? null,
          updatedAt: next['updatedAt'],
        };
      }
      delete next['passcode'];
      await docRef.update(next);
      const previousEmail = normalizeOptionalText(existing['email']);
      const nextEmail = normalizeOptionalText(next['email']);
      if (previousEmail !== nextEmail) {
        try {
          await syncAssignedFutureEventsForMemberEmailChange(
            {
              firestore: db,
              actor: {
                memberId: actor.memberId,
                isAdmin: actor.isAdmin,
              },
              environment,
              collections,
            },
            memberId,
          );
        } catch (error) {
          console.error(`Failed to sync future events for team member ${memberId}:`, error);
        }
      }
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
        name: typeof next['name'] === 'string'
          ? next['name']
          : existing['name'],
      }, {
        before: existing,
        after: next,
      });
      return {ok: true};
    }

    case 'teamMember.updatePasscode': {
      const memberId = requireString(payload['memberId'], 'memberId');
      const passcode = requireString(payload['passcode'], 'passcode');
      const length = Number(payload['length']);
      const currentPasscode = optionalString(payload['currentPasscode']);
      requireSelfOrAdmin(actor, memberId);

      const teamRef = db.collection(collections.teamMembers).doc(memberId);
      const credentialRef = db.collection(collections.privateCredentials).doc(memberId);
      const teamDoc = await teamRef.get();
      if (!teamDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }
      const teamBefore = teamDoc.data() ?? {};
      const credentialDoc = await credentialRef.get();

      if (!actor.isAdmin) {
        const existingHash = credentialDoc.data()?.['passcodeHash'];
        const legacyPasscode = typeof teamBefore['passcode'] === 'string'
          ? teamBefore['passcode']
          : null;
        const hasExistingPasscode = typeof existingHash === 'string' ||
          (typeof legacyPasscode === 'string' && legacyPasscode.length > 0) ||
          teamBefore['passcodeLength'] != null;

        if (hasExistingPasscode) {
          let isCurrentPasscodeValid = false;

          if (typeof existingHash === 'string') {
            isCurrentPasscodeValid = currentPasscode != null &&
              verifyPasscode(currentPasscode, existingHash);
          } else if (typeof legacyPasscode === 'string' &&
              legacyPasscode.length > 0) {
            isCurrentPasscodeValid = currentPasscode === legacyPasscode;
          } else {
            throw new HttpError(
              409,
              'לא ניתן לאמת את קוד הגישה הנוכחי. יש לפנות למנהל/ת',
            );
          }

          if (!isCurrentPasscodeValid) {
            throw new HttpError(403, 'קוד הגישה הנוכחי שגוי');
          }
        }
      }

      await upsertPrivatePasscodeCredential(collections, memberId, passcode, length);

      await teamRef.update({
        passcodeLength: length,
        passcode: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      const teamAfter: Record<string, unknown> = {
        ...teamBefore,
        passcodeLength: length,
      };
      delete teamAfter['passcode'];
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {length}, {
        before: teamBefore,
        after: teamAfter,
      });
      return {ok: true};
    }

    case 'teamMember.clearPasscode': {
      const memberId = requireString(payload['memberId'], 'memberId');
      requireSelfOrAdmin(actor, memberId);
      const teamRef = db.collection(collections.teamMembers).doc(memberId);
      const teamDoc = await teamRef.get();
      if (!teamDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }
      const teamBefore = teamDoc.data() ?? {};
      await db.collection(collections.privateCredentials).doc(memberId).delete();
      await teamRef.update({
        passcodeLength: FieldValue.delete(),
        passcode: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      const teamAfter: Record<string, unknown> = {
        ...teamBefore,
      };
      delete teamAfter['passcodeLength'];
      delete teamAfter['passcode'];
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {}, {
        before: teamBefore,
        after: teamAfter,
      });
      return {ok: true};
    }

    case 'teamMember.getPasscode': {
      requireAdmin(actor);
      const memberId = requireString(payload['memberId'], 'memberId');
      const teamRef = db.collection(collections.teamMembers).doc(memberId);
      const credentialRef = db.collection(collections.privateCredentials).doc(memberId);
      const [teamDoc, credentialDoc] = await Promise.all([
        teamRef.get(),
        credentialRef.get(),
      ]);

      if (!teamDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }

      const teamData = teamDoc.data() ?? {};
      const credentialData = credentialDoc.data();
      const storedPasscode = getStoredPrivatePasscodeValue(credentialData);
      const storedLength =
        typeof credentialData?.['passcodeLength'] === 'number'
          ? credentialData['passcodeLength']
          : typeof teamData['passcodeLength'] === 'number'
            ? teamData['passcodeLength']
            : storedPasscode?.length ?? 0;

      if (storedPasscode != null) {
        await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
          revealed: true,
          length: storedLength,
        });
        return {
          ok: true,
          passcode: storedPasscode,
          length: storedLength,
        };
      }

      const legacyPasscode = typeof teamData['passcode'] === 'string' &&
          (teamData['passcode'] as string).length > 0
        ? (teamData['passcode'] as string)
        : null;

      if (legacyPasscode != null) {
        const length = typeof teamData['passcodeLength'] === 'number'
          ? teamData['passcodeLength']
          : legacyPasscode.length;
        await upsertPrivatePasscodeCredential(
          collections,
          memberId,
          legacyPasscode,
          length,
          {
            migratedFromLegacyFieldAt: FieldValue.serverTimestamp(),
          },
        );
        await teamRef.update({
          passcode: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
          revealed: true,
          length,
        });
        return {
          ok: true,
          passcode: legacyPasscode,
          length,
        };
      }

      if (credentialDoc.exists || teamData['passcodeLength'] != null) {
        throw new HttpError(
          409,
          'לא ניתן להציג את קוד הגישה הקיים. יש להגדיר קוד חדש',
        );
      }

      throw new HttpError(404, 'לא הוגדר קוד גישה');
    }

    case 'teamMember.delete': {
      requireAdmin(actor);
      const memberId = requireString(payload['memberId'], 'memberId');
      const docRef = db.collection(collections.teamMembers).doc(memberId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }
      const existing = existingDoc.data() ?? {};
      await docRef.delete();
      await db.collection(collections.privateCredentials).doc(memberId).delete().catch(() => undefined);
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
        name: existing['name'],
      }, {
        before: existing,
      });
      return {ok: true};
    }

    case 'teamMember.insertBatch': {
      requireAdmin(actor);
      const members = Array.isArray(payload['members']) ? payload['members'] : [];
      const batch = db.batch();
      for (const rawMember of members) {
        const member = rawMember as Record<string, unknown>;
        const memberId = requireString(member['id'], 'member.id');
        const nextMember = {
          ...teamMemberDocFromJson(member),
          passcodeLength: DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH,
        };
        batch.set(
          db.collection(collections.teamMembers).doc(memberId),
          nextMember,
        );
        batch.set(
          db.collection(collections.privateCredentials).doc(memberId),
          {
            passcodeHash: hashPasscode(DEFAULT_TEAM_MEMBER_PASSCODE),
            passcodeValue: DEFAULT_TEAM_MEMBER_PASSCODE,
            passcodeLength: DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH,
            updatedAt: FieldValue.serverTimestamp(),
          },
        );
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'teamMemberBatch', actor.memberId, {
        count: members.length,
      });
      return {ok: true};
    }

    case 'constraint.updateStatus': {
      requireAdmin(actor);
      const constraintIdOrMemberId = requireString(payload['teamMemberIdOrConstraintId'], 'teamMemberIdOrConstraintId');
      const constraintIndexValue = payload['constraintIndex'];
      const newStatus = requireString(payload['newStatus'], 'newStatus');
      const note = optionalString(payload['note']);
      const wasAutoRejectedFromCalendar = payload['wasAutoRejectedFromCalendar'] === true;

      if (constraintIndexValue == null) {
        const teamMembers = await db.collection(collections.teamMembers).get();
        for (const doc of teamMembers.docs) {
          const data = doc.data();
          const teamMemberName =
            typeof data['name'] === 'string' ? (data['name'] as string) : null;
          const constraints = Array.isArray(data['constraints']) ? [...(data['constraints'] as Array<Record<string, unknown>>)] : [];
          const index = constraints.findIndex((constraint) => constraint['id'] === constraintIdOrMemberId);
          if (index < 0) continue;
          const previousConstraint = constraints[index];
          const updated = {
            ...constraints[index],
            status: newStatus,
            ...(note != null ? {note} : {}),
            ...(payload['wasAutoRejectedFromCalendar'] != null
              ? {wasAutoRejectedFromCalendar}
              : {}),
          };
          constraints[index] = updated;
          await doc.ref.update({
            constraints,
            updatedAt: FieldValue.serverTimestamp(),
          });
          await writeAuditLog(
            db,
            collections,
            actor,
            operation,
            getConstraintAuditEntityType(updated),
            constraintIdOrMemberId,
            buildConstraintAuditDetails(doc.id, teamMemberName, updated, {
              newStatus,
              semanticAction: getConstraintStatusSemanticAction(
                newStatus,
                wasAutoRejectedFromCalendar,
              ) ?? undefined,
            }),
            {
              before: previousConstraint,
              after: updated,
            },
          );
          return {ok: true};
        }
        throw new HttpError(404, 'Constraint not found');
      }

      const teamMemberId = constraintIdOrMemberId;
      const constraintIndex = Number(constraintIndexValue);
      const memberDoc = await db.collection(collections.teamMembers).doc(teamMemberId).get();
      if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
      const teamMemberName =
        typeof memberDoc.data()?.['name'] === 'string'
          ? (memberDoc.data()?.['name'] as string)
          : null;
      const constraints = Array.isArray(memberDoc.data()?.['constraints'])
        ? [...(memberDoc.data()?.['constraints'] as Array<Record<string, unknown>>)]
        : [];
      if (constraintIndex < 0 || constraintIndex >= constraints.length) {
        throw new HttpError(400, 'Invalid constraint index');
      }
      const previousConstraint = constraints[constraintIndex];
      constraints[constraintIndex] = {
        ...constraints[constraintIndex],
        status: newStatus,
        ...(note != null ? {note} : {}),
        ...(payload['wasAutoRejectedFromCalendar'] != null
          ? {wasAutoRejectedFromCalendar}
          : {}),
      };
      await memberDoc.ref.update({
        constraints,
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        getConstraintAuditEntityType(constraints[constraintIndex]),
        String(constraints[constraintIndex]['id']),
        buildConstraintAuditDetails(
          teamMemberId,
          teamMemberName,
          constraints[constraintIndex],
          {
            newStatus,
            semanticAction: getConstraintStatusSemanticAction(
              newStatus,
              wasAutoRejectedFromCalendar,
            ) ?? undefined,
          },
        ),
        {
          before: previousConstraint,
          after: constraints[constraintIndex],
        },
      );
      return {ok: true};
    }

    case 'constraint.add': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      const constraint = payload['constraint'] as Record<string, unknown>;
      const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
      const memberDoc = await memberRef.get();
      if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
      const teamMemberName =
        typeof memberDoc.data()?.['name'] === 'string'
          ? (memberDoc.data()?.['name'] as string)
          : null;
      await memberRef.update({
        constraints: FieldValue.arrayUnion(constraint),
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        getConstraintAuditEntityType(constraint),
        requireString(constraint['id'], 'constraint.id'),
        buildConstraintAuditDetails(teamMemberId, teamMemberName, constraint),
        {
          after: constraint,
        },
      );
      return {ok: true};
    }

    case 'constraint.edit': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      requireSelfOrAdmin(actor, teamMemberId);
      const updatedConstraint = payload['constraint'] as Record<string, unknown>;
      const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
      const memberDoc = await memberRef.get();
      if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
      const teamMemberName =
        typeof memberDoc.data()?.['name'] === 'string'
          ? (memberDoc.data()?.['name'] as string)
          : null;
      const constraints = Array.isArray(memberDoc.data()?.['constraints'])
        ? [...(memberDoc.data()?.['constraints'] as Array<Record<string, unknown>>)]
        : [];
      const index = constraints.findIndex((constraint) => constraint['id'] === constraintId);
      if (index < 0) throw new HttpError(404, 'Constraint not found');
      const previousConstraint = constraints[index];
      constraints[index] = updatedConstraint;
      await memberRef.update({constraints, updatedAt: FieldValue.serverTimestamp()});
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        getConstraintAuditEntityType(updatedConstraint),
        constraintId,
        buildConstraintAuditDetails(
          teamMemberId,
          teamMemberName,
          updatedConstraint,
        ),
        {
          before: previousConstraint,
          after: updatedConstraint,
        },
      );
      return {ok: true};
    }

    case 'constraint.remove': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      requireSelfOrAdmin(actor, teamMemberId);
      const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
      const memberDoc = await memberRef.get();
      if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
      const teamMemberName =
        typeof memberDoc.data()?.['name'] === 'string'
          ? (memberDoc.data()?.['name'] as string)
          : null;
      const constraints = Array.isArray(memberDoc.data()?.['constraints'])
        ? [...(memberDoc.data()?.['constraints'] as Array<Record<string, unknown>>)]
        : [];
      const removedConstraint =
        constraints.find((constraint) => constraint['id'] === constraintId) ?? null;
      const nextConstraints = constraints.filter((constraint) => constraint['id'] !== constraintId);
      await memberRef.update({constraints: nextConstraints, updatedAt: FieldValue.serverTimestamp()});
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        getConstraintAuditEntityType(removedConstraint),
        constraintId,
        buildConstraintAuditDetails(
          teamMemberId,
          teamMemberName,
          removedConstraint,
        ),
        {
          before: removedConstraint,
        },
      );
      return {ok: true};
    }

    case 'event.insert': {
      requireAdmin(actor);
      const event = payload['event'] as Record<string, unknown>;
      const eventId = requireString(event['id'], 'event.id');
      const name = requireString(event['name'], 'event.name');
      const startDate = asCalendarDay(event['startDate'], 'event.startDate');
      const startOfTargetDay = Timestamp.fromDate(startDate);
      const endOfTargetDay = Timestamp.fromDate(addDays(startDate, 1));
      const duplicates = await db
        .collection(collections.events)
        .where('startDate', '>=', startOfTargetDay)
        .where('startDate', '<', endOfTargetDay)
        .get();
      const hasDuplicate = duplicates.docs.some((doc) => {
        const data = doc.data();
        return data['name'] === name;
      });
      if (hasDuplicate) {
        throw new HttpError(400, 'כבר קיים אירוע בשם זה בתאריך זה');
      }
      const nextEvent = eventDocFromJson(event);
      await db.collection(collections.events).doc(eventId).set(nextEvent);
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {name}, {
        after: nextEvent,
      });
      return {ok: true};
    }

    case 'event.update': {
      const event = payload['event'] as Record<string, unknown>;
      const eventId = requireString(event['id'], 'event.id');
      const eventRef = db.collection(collections.events).doc(eventId);
      const existingDoc = await eventRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Event not found');
      }
      const existing = existingDoc.data() ?? {};
      const existingParkingEditorIds = Array.isArray(existing['parkingEditorIds'])
        ? existing['parkingEditorIds'].map((value) => String(value))
        : [];

      if (!actor.isAdmin) {
        if (!existingParkingEditorIds.includes(actor.memberId)) {
          throw new HttpError(403, 'אין הרשאה לעדכן את מיקום החנייה של האירוע');
        }

        const nextParkingLocation = typeof event['parkingLocation'] === 'string'
          ? event['parkingLocation']
          : null;
        const nextUpdatedAt = toTimestamp(event['updatedAt'], 'event.updatedAt');

        await eventRef.update({
          parkingLocation: nextParkingLocation,
          updatedAt: nextUpdatedAt,
        });
        await writeAuditLog(db, collections, actor, operation, 'event', eventId, {
          name: typeof existing['name'] === 'string' ? existing['name'] : undefined,
          parkingLocationUpdated: true,
        }, {
          before: {
            parkingLocation: existing['parkingLocation'] ?? null,
            updatedAt: existing['updatedAt'] ?? null,
          },
          after: {
            parkingLocation: nextParkingLocation,
            updatedAt: nextUpdatedAt,
          },
        });
        return {ok: true};
      }

      const name = requireString(event['name'], 'event.name');
      const startDate = asCalendarDay(event['startDate'], 'event.startDate');
      const startOfTargetDay = Timestamp.fromDate(startDate);
      const endOfTargetDay = Timestamp.fromDate(addDays(startDate, 1));
      const duplicates = await db
        .collection(collections.events)
        .where('startDate', '>=', startOfTargetDay)
        .where('startDate', '<', endOfTargetDay)
        .get();
      const hasDuplicate = duplicates.docs.some((doc) => {
        if (doc.id === eventId) {
          return false;
        }

        const data = doc.data();
        return data['name'] === name;
      });
      if (hasDuplicate) {
        throw new HttpError(400, 'כבר קיים אירוע בשם זה בתאריך זה');
      }
      const nextEvent = eventDocFromJson(event);
      await eventRef.update(nextEvent);
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {name}, {
        before: existing,
        after: nextEvent,
      });
      return {ok: true};
    }

    case 'event.delete': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      const eventRef = db.collection(collections.events).doc(eventId);
      const [eventDoc, assignmentSnapshot, checklistSnapshot] =
        await Promise.all([
          eventRef.get(),
          db.collection(collections.assignments).where('eventId', '==', eventId).get(),
          db.collection(collections.checklistItems).where('eventId', '==', eventId).get(),
        ]);
      if (!eventDoc.exists) {
        throw new HttpError(404, 'Event not found');
      }
      const existingEvent = eventDoc.data() ?? {};
      const existingAssignments = assignmentSnapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() ?? {},
      }));
      const existingChecklistItems = checklistSnapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() ?? {},
      }));

      const teamMemberNameCache = new Map<string, string | null>();
      const readTeamMemberName = async (memberId: string | null): Promise<string | null> => {
        if (memberId == null) {
          return null;
        }

        if (teamMemberNameCache.has(memberId)) {
          return teamMemberNameCache.get(memberId) ?? null;
        }

        const teamMemberData = await readTeamMemberById(db, collections, memberId);
        const teamMemberName = typeof teamMemberData?.['name'] === 'string'
          ? teamMemberData['name'] as string
          : null;
        teamMemberNameCache.set(memberId, teamMemberName);
        return teamMemberName;
      };

      const deletedAssignments = await Promise.all(existingAssignments.map(async (assignment) => {
        const teamMemberId = typeof assignment.data['teamMemberId'] === 'string'
          ? assignment.data['teamMemberId'] as string
          : null;
        const teamMemberName = await readTeamMemberName(teamMemberId);
        return buildAssignmentAuditDetails(assignment.data, {
          id: assignment.id,
          teamMemberName: teamMemberName ?? undefined,
        });
      }));

      const deletedChecklistItems = await Promise.all(existingChecklistItems.map(async (item) => {
        const responsibleId = typeof item.data['responsibleId'] === 'string'
          ? item.data['responsibleId'] as string
          : null;
        const responsibleName = await readTeamMemberName(responsibleId);
        return buildChecklistItemAuditDetails(item.data, {
          id: item.id,
          responsibleName: responsibleName ?? undefined,
        });
      }));
      await deleteAppEventCalendarArtifacts(
        {
          firestore: db,
          actor: {
            memberId: actor.memberId,
            isAdmin: actor.isAdmin,
          },
          environment,
          collections,
        },
        eventId,
      );

      const batch = db.batch();
      for (const doc of assignmentSnapshot.docs) {
        batch.delete(doc.ref);
      }
      for (const doc of checklistSnapshot.docs) {
        batch.delete(doc.ref);
      }
      batch.delete(eventRef);
      batch.delete(db.collection(collections.eventCalendarSync).doc(eventId));
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, stripUndefined({
        name: existingEvent['name'],
        deletedAssignments:
          deletedAssignments.length > 0 ? deletedAssignments : undefined,
        deletedChecklistItems:
          deletedChecklistItems.length > 0 ? deletedChecklistItems : undefined,
      }), {
        before: existingEvent,
      });
      return {ok: true};
    }

    case 'event.insertBatch': {
      requireAdmin(actor);
      const events = Array.isArray(payload['events']) ? payload['events'] : [];
      const batch = db.batch();
      for (const rawEvent of events) {
        const event = rawEvent as Record<string, unknown>;
        const eventId = requireString(event['id'], 'event.id');
        batch.set(db.collection(collections.events).doc(eventId), eventDocFromJson(event));
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'eventBatch', actor.memberId, {
        count: events.length,
      });
      return {ok: true};
    }

    case 'event.updateArchiveStatus': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      const eventRef = db.collection(collections.events).doc(eventId);
      const existingDoc = await eventRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Event not found');
      }
      const existing = existingDoc.data() ?? {};
      const nextEvent = {
        ...existing,
        isArchived: payload['isArchived'] === true,
      };
      await eventRef.update({
        isArchived: payload['isArchived'] === true,
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {
        name: existing['name'],
        isArchived: payload['isArchived'] === true,
      }, {
        before: existing,
        after: nextEvent,
      });
      return {ok: true};
    }

    case 'assignment.insert': {
      requireAdmin(actor);
      const assignment = payload['assignment'] as Record<string, unknown>;
      const assignmentId = requireString(assignment['id'], 'assignment.id');
      await validateAssignmentPayload(db, collections, assignment, undefined, {
        bypassAvailability: payload['bypassAvailability'] === true,
      });
      const nextAssignment = assignmentDocFromJson(assignment);
      await db.collection(collections.assignments).doc(assignmentId).set(nextAssignment);
      await syncAssignedEventsBestEffort(
        {
          firestore: db,
          actor: {
            memberId: actor.memberId,
            isAdmin: actor.isAdmin,
          },
          environment,
          collections,
        },
        [String(nextAssignment['eventId'])],
      );
      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId, {}, {
        after: nextAssignment,
      });
      return {ok: true};
    }

    case 'assignment.update': {
      requireAdmin(actor);
      const assignment = payload['assignment'] as Record<string, unknown>;
      const assignmentId = requireString(assignment['id'], 'assignment.id');
      const assignmentRef = db.collection(collections.assignments).doc(assignmentId);
      const existingDoc = await assignmentRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment not found');
      }
      const existing = existingDoc.data() ?? {};
      await validateAssignmentPayload(db, collections, assignment, assignmentId, {
        bypassAvailability: payload['bypassAvailability'] === true,
      });
      const nextAssignment = assignmentDocFromJson(assignment);
      await assignmentRef.update(nextAssignment);
      await syncAssignedEventsBestEffort(
        {
          firestore: db,
          actor: {
            memberId: actor.memberId,
            isAdmin: actor.isAdmin,
          },
          environment,
          collections,
        },
        [
          typeof existing['eventId'] === 'string' ? existing['eventId'] : '',
          String(nextAssignment['eventId']),
        ],
      );
      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId, {}, {
        before: existing,
        after: nextAssignment,
      });
      return {ok: true};
    }

    case 'assignment.updateMetadata': {
      requireAdmin(actor);
      const assignmentId = requireString(payload['assignmentId'], 'assignmentId');
      const assignmentRef = db.collection(collections.assignments).doc(assignmentId);
      const existingDoc = await assignmentRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment not found');
      }

      const existing = existingDoc.data() ?? {};
      const metadata = await validateAssignmentMetadataPayload(db, collections, payload);
      const updatedAt = Timestamp.now();

      await assignmentRef.update(stripUndefined({
        notes: metadata.notes,
        semanticLabelId: metadata.semanticLabelId,
        alternativePhoneNumber: metadata.alternativePhoneNumber ?? FieldValue.delete(),
        updatedAt,
      }));

      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId, {}, {
        before: existing,
        after: stripUndefined({
          ...existing,
          notes: metadata.notes,
          semanticLabelId: metadata.semanticLabelId,
          alternativePhoneNumber: metadata.alternativePhoneNumber,
          updatedAt,
        }),
      });
      return {ok: true};
    }

    case 'assignment.delete': {
      requireAdmin(actor);
      const assignmentId = requireString(payload['assignmentId'], 'assignmentId');
      const assignmentRef = db.collection(collections.assignments).doc(assignmentId);
      const existingDoc = await assignmentRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment not found');
      }
      const existing = existingDoc.data() ?? {};
      await assignmentRef.delete();
      if (typeof existing['eventId'] === 'string') {
        await syncAssignedEventsBestEffort(
          {
            firestore: db,
            actor: {
              memberId: actor.memberId,
              isAdmin: actor.isAdmin,
            },
            environment,
            collections,
          },
          [existing['eventId'] as string],
        );
      }
      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId, {}, {
        before: existing,
      });
      return {ok: true};
    }

    case 'assignment.deleteByEvent': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      const eventData = await readEventById(db, collections, eventId);
      const eventName = typeof eventData?.['name'] === 'string'
        ? eventData['name'] as string
        : null;
      const snapshot = await db.collection(collections.assignments).where('eventId', '==', eventId).get();
      const existingAssignments = snapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() ?? {},
      }));
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      await syncAssignedEventsBestEffort(
        {
          firestore: db,
          actor: {
            memberId: actor.memberId,
            isAdmin: actor.isAdmin,
          },
          environment,
          collections,
        },
        [eventId],
      );
      const batchOperationId = randomUUID();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', eventId, {
        name: eventName ?? undefined,
        deletedCount: snapshot.docs.length,
      }, {}, {
        operationId: batchOperationId,
      });

      const teamMemberNameCache = new Map<string, string | null>();
      for (const assignment of existingAssignments) {
        const teamMemberId = typeof assignment.data['teamMemberId'] === 'string'
          ? assignment.data['teamMemberId'] as string
          : null;
        let teamMemberName: string | null = null;
        if (teamMemberId != null) {
          teamMemberName = teamMemberNameCache.get(teamMemberId) ?? null;
          if (!teamMemberNameCache.has(teamMemberId)) {
            const teamMemberData = await readTeamMemberById(db, collections, teamMemberId);
            teamMemberName = typeof teamMemberData?.['name'] === 'string'
              ? teamMemberData['name'] as string
              : null;
            teamMemberNameCache.set(teamMemberId, teamMemberName);
          }
        }

        await writeAuditLog(
          db,
          collections,
          actor,
          'assignment.delete',
          'assignment',
          assignment.id,
          buildAssignmentAuditDetails(assignment.data, {
            eventName: eventName ?? undefined,
            teamMemberName: teamMemberName ?? undefined,
          }),
          {
            before: assignment.data,
          },
          {
            parentOperationId: batchOperationId,
          },
        );
      }
      return {ok: true};
    }

    case 'assignment.deleteByPerson': {
      requireAdmin(actor);
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      const teamMemberData = await readTeamMemberById(db, collections, teamMemberId);
      const teamMemberName = typeof teamMemberData?.['name'] === 'string'
        ? teamMemberData['name'] as string
        : null;
      const snapshot = await db
        .collection(collections.assignments)
        .where('teamMemberId', '==', teamMemberId)
        .get();
      const existingAssignments = snapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() ?? {},
      }));
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      await syncAssignedEventsBestEffort(
        {
          firestore: db,
          actor: {
            memberId: actor.memberId,
            isAdmin: actor.isAdmin,
          },
          environment,
          collections,
        },
        existingAssignments.map((assignment) => (
          typeof assignment.data['eventId'] === 'string'
            ? assignment.data['eventId'] as string
            : ''
        )),
      );
      const batchOperationId = randomUUID();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', teamMemberId, {
        name: teamMemberName ?? undefined,
        deletedCount: snapshot.docs.length,
      }, {}, {
        operationId: batchOperationId,
      });

      const eventNameCache = new Map<string, string | null>();
      for (const assignment of existingAssignments) {
        const assignmentEventId = typeof assignment.data['eventId'] === 'string'
          ? assignment.data['eventId'] as string
          : null;
        let eventName: string | null = null;
        if (assignmentEventId != null) {
          eventName = eventNameCache.get(assignmentEventId) ?? null;
          if (!eventNameCache.has(assignmentEventId)) {
            const eventDoc = await readEventById(db, collections, assignmentEventId);
            eventName = typeof eventDoc?.['name'] === 'string'
              ? eventDoc['name'] as string
              : null;
            eventNameCache.set(assignmentEventId, eventName);
          }
        }

        await writeAuditLog(
          db,
          collections,
          actor,
          'assignment.delete',
          'assignment',
          assignment.id,
          buildAssignmentAuditDetails(assignment.data, {
            eventName: eventName ?? undefined,
            teamMemberName: teamMemberName ?? undefined,
          }),
          {
            before: assignment.data,
          },
          {
            parentOperationId: batchOperationId,
          },
        );
      }
      return {ok: true};
    }

    case 'assignment.deleteBatch': {
      requireAdmin(actor);
      const assignmentIds = Array.isArray(payload['assignmentIds']) ? payload['assignmentIds'] : [];
      const assignmentRefs = assignmentIds.map((rawId) =>
        db.collection(collections.assignments).doc(String(rawId)),
      );
      const assignmentDocs = assignmentRefs.length > 0 ? await db.getAll(...assignmentRefs) : [];
      const existingAssignments = assignmentDocs
        .filter((doc) => doc.exists)
        .map((doc) => ({
          id: doc.id,
          data: doc.data() ?? {},
        }));
      const batch = db.batch();
      for (const rawId of assignmentIds) {
        batch.delete(db.collection(collections.assignments).doc(String(rawId)));
      }
      await batch.commit();
      await syncAssignedEventsBestEffort(
        {
          firestore: db,
          actor: {
            memberId: actor.memberId,
            isAdmin: actor.isAdmin,
          },
          environment,
          collections,
        },
        existingAssignments.map((assignment) => (
          typeof assignment.data['eventId'] === 'string'
            ? assignment.data['eventId'] as string
            : ''
        )),
      );
      const batchOperationId = randomUUID();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', actor.memberId, {
        deletedCount: existingAssignments.length,
      }, {}, {
        operationId: batchOperationId,
      });

      const teamMemberNameCache = new Map<string, string | null>();
      const eventNameCache = new Map<string, string | null>();
      for (const assignment of existingAssignments) {
        const assignmentEventId = typeof assignment.data['eventId'] === 'string'
          ? assignment.data['eventId'] as string
          : null;
        const assignmentTeamMemberId = typeof assignment.data['teamMemberId'] === 'string'
          ? assignment.data['teamMemberId'] as string
          : null;

        let eventName: string | null = null;
        if (assignmentEventId != null) {
          eventName = eventNameCache.get(assignmentEventId) ?? null;
          if (!eventNameCache.has(assignmentEventId)) {
            const eventDoc = await readEventById(db, collections, assignmentEventId);
            eventName = typeof eventDoc?.['name'] === 'string'
              ? eventDoc['name'] as string
              : null;
            eventNameCache.set(assignmentEventId, eventName);
          }
        }

        let teamMemberName: string | null = null;
        if (assignmentTeamMemberId != null) {
          teamMemberName = teamMemberNameCache.get(assignmentTeamMemberId) ?? null;
          if (!teamMemberNameCache.has(assignmentTeamMemberId)) {
            const teamMemberDoc = await readTeamMemberById(db, collections, assignmentTeamMemberId);
            teamMemberName = typeof teamMemberDoc?.['name'] === 'string'
              ? teamMemberDoc['name'] as string
              : null;
            teamMemberNameCache.set(assignmentTeamMemberId, teamMemberName);
          }
        }

        await writeAuditLog(
          db,
          collections,
          actor,
          'assignment.delete',
          'assignment',
          assignment.id,
          buildAssignmentAuditDetails(assignment.data, {
            eventName: eventName ?? undefined,
            teamMemberName: teamMemberName ?? undefined,
          }),
          {
            before: assignment.data,
          },
          {
            parentOperationId: batchOperationId,
          },
        );
      }
      return {ok: true};
    }

    case 'assignment.insertBatch': {
      requireAdmin(actor);
      const assignments = Array.isArray(payload['assignments']) ? payload['assignments'] : [];
      const batch = db.batch();
      for (const rawAssignment of assignments) {
        const assignment = rawAssignment as Record<string, unknown>;
        const assignmentId = requireString(assignment['id'], 'assignment.id');
        await validateAssignmentPayload(db, collections, assignment);
        batch.set(
          db.collection(collections.assignments).doc(assignmentId),
          assignmentDocFromJson(assignment),
        );
      }
      await batch.commit();
      await syncAssignedEventsBestEffort(
        {
          firestore: db,
          actor: {
            memberId: actor.memberId,
            isAdmin: actor.isAdmin,
          },
          environment,
          collections,
        },
        assignments.map((assignment) => {
          const value = assignment as Record<string, unknown>;
          return typeof value['eventId'] === 'string' ? value['eventId'] as string : '';
        }),
      );
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', actor.memberId, {
        count: assignments.length,
      });
      return {ok: true};
    }

    case 'utility.clearAllData': {
      requireAdmin(actor);
      if (collections.teamMembers.startsWith('test_') == false) {
        throw new HttpError(403, 'clearAllData is only allowed in test mode');
      }
      const collectionNames = [
        collections.teamMembers,
        collections.events,
        collections.assignments,
        collections.assignmentLabels,
        collections.checklistItems,
        collections.presets,
        collections.calendarSync,
        collections.eventCalendarSync,
        collections.privateCredentials,
        collections.privateSessions,
        collections.privateGoogleCalendarAuth,
      ];
      for (const collectionName of collectionNames) {
        const snapshot = await db.collection(collectionName).get();
        const batch = db.batch();
        for (const doc of snapshot.docs) {
          batch.delete(doc.ref);
        }
        await batch.commit();
      }
      await writeAuditLog(db, collections, actor, operation, 'utility', actor.memberId);
      return {ok: true};
    }

    case 'calendar.saveSyncState': {
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      await db.collection(collections.calendarSync).doc(constraintId).set({
        calendarEventId: requireString(payload['calendarEventId'], 'calendarEventId'),
        teamMemberId,
        status: requireString(payload['status'], 'status'),
        syncedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        retryCount: 0,
        errorMessage: null,
      });
      return {ok: true};
    }

    case 'calendar.updateSyncStatus': {
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      const existingDoc = await db.collection(collections.calendarSync).doc(constraintId).get();
      const teamMemberId = requireString(existingDoc.data()?.['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      await existingDoc.ref.update(stripUndefined({
        status: requireString(payload['status'], 'status'),
        updatedAt: FieldValue.serverTimestamp(),
        errorMessage: optionalString(payload['errorMessage']),
        retryCount: payload['retryCount'],
      }));
      return {ok: true};
    }

    case 'calendar.removeSyncState': {
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      const existingDoc = await db.collection(collections.calendarSync).doc(constraintId).get();
      const teamMemberId = requireString(existingDoc.data()?.['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      await existingDoc.ref.delete();
      return {ok: true};
    }

    case 'calendar.atomicCheckAndSetSyncState': {
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      const result = await db.runTransaction(async (transaction) => {
        const ref = db.collection(collections.calendarSync).doc(constraintId);
        const snapshot = await transaction.get(ref);
        if (snapshot.exists && snapshot.data()?.['status'] === 'synced') {
          return {
            action: 'update',
            calendarEventId: snapshot.data()?.['calendarEventId'] ?? null,
            teamMemberId: snapshot.data()?.['teamMemberId'] ?? null,
          };
        }
        transaction.set(ref, {
          calendarEventId: '',
          teamMemberId,
          status: 'pending',
          syncedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          retryCount: 0,
          errorMessage: null,
          reservedBy: Date.now(),
        });
        return {
          action: 'create',
          calendarEventId: null,
          teamMemberId,
        };
      });
      return result as Record<string, unknown>;
    }

    case 'calendar.saveEventSyncState': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      await db.collection(collections.eventCalendarSync).doc(eventId).set({
        assemblyCalendarEventId: optionalString(payload['assemblyCalendarEventId']) ?? '',
        mainCalendarEventId: optionalString(payload['mainCalendarEventId']) ?? '',
        status: requireString(payload['status'], 'status'),
        syncedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {ok: true};
    }

    case 'calendar.removeEventSyncState': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      await db.collection(collections.eventCalendarSync).doc(eventId).delete();
      return {ok: true};
    }

    case 'checklist.insert': {
      requireAdmin(actor);
      const item = payload['item'] as Record<string, unknown>;
      const itemId = requireString(item['id'], 'item.id');
      const nextItem = checklistItemDocFromJson(item);
      await db.collection(collections.checklistItems).doc(itemId).set(nextItem);
      await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId, {
        name: item['name'],
      }, {
        after: nextItem,
      });
      return {ok: true};
    }

    case 'checklist.update': {
      const item = payload['item'] as Record<string, unknown>;
      const itemId = requireString(item['id'], 'item.id');
      const docRef = db.collection(collections.checklistItems).doc(itemId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) throw new HttpError(404, 'Checklist item not found');
      const existing = existingDoc.data() ?? {};
      const isResponsible = existing['responsibleId'] === actor.memberId;
      const ccIds = Array.isArray(existing['ccIds']) ? existing['ccIds'].map(String) : [];
      if (!actor.isAdmin && !isResponsible && !ccIds.includes(actor.memberId)) {
        throw new HttpError(403, 'אין לך הרשאה לערוך את הפריט');
      }

      if (actor.isAdmin || isResponsible) {
        const nextItem = checklistItemDocFromJson(item);
        const semanticAction = getChecklistUpdateSemanticAction(existing, nextItem);
        await docRef.update(nextItem);
        await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId, stripUndefined({
          name: item['name'] ?? existing['name'],
          semanticAction,
        }), {
          before: existing,
          after: nextItem,
        });
      } else {
        const nextItem = {
          ...existing,
          status: item['status'] ?? existing['status'] ?? false,
          statusLastUpdatedAt: toTimestamp(
            item['statusLastUpdatedAt'] ?? new Date().toISOString(),
            'item.statusLastUpdatedAt',
          ),
          updatedAt: toTimestamp(item['updatedAt'] ?? new Date().toISOString(), 'item.updatedAt'),
        };
        const semanticAction = getChecklistUpdateSemanticAction(existing, nextItem);
        await docRef.update({
          status: item['status'] ?? existing['status'] ?? false,
          statusLastUpdatedAt: toTimestamp(
            item['statusLastUpdatedAt'] ?? new Date().toISOString(),
            'item.statusLastUpdatedAt',
          ),
          updatedAt: toTimestamp(item['updatedAt'] ?? new Date().toISOString(), 'item.updatedAt'),
        });
        await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId, stripUndefined({
          name: existing['name'],
          semanticAction,
        }), {
          before: existing,
          after: nextItem,
        });
      }
      return {ok: true};
    }

    case 'checklist.delete': {
      requireAdmin(actor);
      const itemId = requireString(payload['itemId'], 'itemId');
      const docRef = db.collection(collections.checklistItems).doc(itemId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Checklist item not found');
      }
      const existing = existingDoc.data() ?? {};
      await docRef.delete();
      await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId, {
        name: existing['name'],
      }, {
        before: existing,
      });
      return {ok: true};
    }

    case 'checklist.deleteByEvent': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      const snapshot = await db.collection(collections.checklistItems).where('eventId', '==', eventId).get();
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'checklistItemBatch', eventId, {
        deletedCount: snapshot.docs.length,
      });
      return {ok: true};
    }

    case 'checklist.addNote': {
      const checklistItemId = requireString(payload['checklistItemId'], 'checklistItemId');
      const noteData = payload['noteData'] as Record<string, unknown>;
      const docRef = db.collection(collections.checklistItems).doc(checklistItemId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) throw new HttpError(404, 'Checklist item not found');
      const existing = existingDoc.data() ?? {};
      const isResponsible = existing['responsibleId'] === actor.memberId;
      const ccIds = Array.isArray(existing['ccIds']) ? existing['ccIds'].map(String) : [];
      if (!actor.isAdmin && !isResponsible && !ccIds.includes(actor.memberId)) {
        throw new HttpError(403, 'אין לך הרשאה להוסיף הערה לפריט');
      }
      const firestoreNote = checklistNotesToFirestore([noteData])[0];
      await docRef.update({
        notes: FieldValue.arrayUnion(firestoreNote),
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        'checklistNote',
        String(firestoreNote['id'] ?? checklistItemId),
        {
          checklistItemId,
          checklistItemName: existing['name'],
        },
        {
          after: firestoreNote,
        },
      );
      return {ok: true};
    }

    case 'preset.insert': {
      requireAdmin(actor);
      const preset = payload['preset'] as Record<string, unknown>;
      const presetId = requireString(preset['id'], 'preset.id');
      const nextPreset = presetDocFromJson(preset);
      await db.collection(collections.presets).doc(presetId).set(nextPreset);
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId, {
        name: preset['name'],
      }, {
        after: nextPreset,
      });
      return {ok: true};
    }

    case 'preset.update': {
      requireAdmin(actor);
      const preset = payload['preset'] as Record<string, unknown>;
      const presetId = requireString(preset['id'], 'preset.id');
      const presetRef = db.collection(collections.presets).doc(presetId);
      const existingDoc = await presetRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Preset not found');
      }
      const existing = existingDoc.data() ?? {};
      const nextPreset = presetDocFromJson(preset);
      await presetRef.update(nextPreset);
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId, {
        name: preset['name'],
      }, {
        before: existing,
        after: nextPreset,
      });
      return {ok: true};
    }

    case 'preset.delete': {
      requireAdmin(actor);
      const presetId = requireString(payload['presetId'], 'presetId');
      const presetRef = db.collection(collections.presets).doc(presetId);
      const existingDoc = await presetRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Preset not found');
      }
      const existing = existingDoc.data() ?? {};
      await presetRef.delete();
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId, {
        name: existing['name'],
      }, {
        before: existing,
      });
      return {ok: true};
    }

    case 'preset.loadIntoEvent': {
      requireAdmin(actor);
      const presetId = requireString(payload['presetId'], 'presetId');
      const eventId = requireString(payload['eventId'], 'eventId');
      const creatorAdminId = requireString(payload['creatorAdminId'], 'creatorAdminId');
      const presetDoc = await db.collection(collections.presets).doc(presetId).get();
      if (!presetDoc.exists) throw new HttpError(404, 'Preset not found');
      const preset = presetDoc.data() ?? {};
      const items = Array.isArray(preset['items']) ? preset['items'] : [];
      const batch = db.batch();
      const now = new Date().toISOString();
      for (const rawItem of items) {
        const item = rawItem as Record<string, unknown>;
        const checklistItemId = randomUUID();
        const notes = typeof item['adminNote'] === 'string' && item['adminNote'].trim().length > 0
          ? [
              {
                id: randomUUID(),
                content: item['adminNote'],
                createdAt: Timestamp.fromDate(new Date(now)),
                createdByTeamMemberId: creatorAdminId,
                createdByTeamMemberName: null,
                authorRole: 'מנהל',
              },
            ]
          : [];
        batch.set(db.collection(collections.checklistItems).doc(checklistItemId), {
          eventId,
          name: item['name'],
          responsibleId: item['responsibleId'],
          ccIds: Array.isArray(item['ccIds']) ? item['ccIds'] : [],
          notes,
          status: false,
          createdAt: Timestamp.fromDate(new Date(now)),
          updatedAt: Timestamp.fromDate(new Date(now)),
          statusLastUpdatedAt: Timestamp.fromDate(new Date(now)),
          createdByAdminId: creatorAdminId,
        });
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId, {
        eventId,
        count: items.length,
      });
      return {ok: true};
    }

    case 'assignmentLabel.insert': {
      requireAdmin(actor);
      const label = payload['label'] as Record<string, unknown>;
      const labelId = requireString(label['id'], 'label.id');
      const nextLabel = assignmentLabelDocFromJson(label);
      await db.collection(collections.assignmentLabels).doc(labelId).set(nextLabel);
      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', labelId, {
        name: label['hebrewName'],
      }, {
        after: nextLabel,
      });
      return {ok: true};
    }

    case 'assignmentLabel.update': {
      requireAdmin(actor);
      const label = payload['label'] as Record<string, unknown>;
      const labelId = requireString(label['id'], 'label.id');
      const labelRef = db.collection(collections.assignmentLabels).doc(labelId);
      const existingDoc = await labelRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment label not found');
      }
      const existing = existingDoc.data() ?? {};
      const nextLabel = assignmentLabelDocFromJson(label);
      await labelRef.update(nextLabel);
      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', labelId, {
        name: label['hebrewName'],
      }, {
        before: existing,
        after: nextLabel,
      });
      return {ok: true};
    }

    case 'assignmentLabel.archive':
    case 'assignmentLabel.restore': {
      requireAdmin(actor);
      const labelId = requireString(payload['labelId'], 'labelId');
      const labelRef = db.collection(collections.assignmentLabels).doc(labelId);
      const existingDoc = await labelRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment label not found');
      }
      const existing = existingDoc.data() ?? {};
      const nextLabel = {
        ...existing,
        isActive: operation === 'assignmentLabel.restore',
        updatedAt: FieldValue.serverTimestamp(),
      };
      await labelRef.update({
        isActive: operation === 'assignmentLabel.restore',
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', labelId, {
        name: existing['hebrewName'],
      }, {
        before: existing,
        after: nextLabel,
      });
      return {ok: true};
    }

    case 'assignmentLabel.delete': {
      requireAdmin(actor);
      const labelId = requireString(payload['labelId'], 'labelId');
      const labelRef = db.collection(collections.assignmentLabels).doc(labelId);
      const existingDoc = await labelRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment label not found');
      }
      const existing = existingDoc.data() ?? {};

      const assignmentsSnapshot = await db
        .collection(collections.assignments)
        .where('semanticLabelId', '==', labelId)
        .get();

      const assignmentDocs = assignmentsSnapshot.docs;
      const chunkSize = 400;
      for (let index = 0; index < assignmentDocs.length; index += chunkSize) {
        const batch = db.batch();
        for (const assignmentDoc of assignmentDocs.slice(index, index + chunkSize)) {
          batch.update(assignmentDoc.ref, {
            semanticLabelId: null,
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      await labelRef.delete();

      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', labelId, {
        name: existing['hebrewName'],
        clearedAssignmentsCount: assignmentDocs.length,
      }, {
        before: existing,
      });
      return {ok: true};
    }

    case 'assignmentLabel.reorder': {
      requireAdmin(actor);
      const labelIdToSortOrder = payload['labelIdToSortOrder'] as Record<string, unknown>;
      const entries = Object.entries(labelIdToSortOrder);
      const batch = db.batch();
      for (const [labelId, sortOrder] of entries) {
        if (typeof sortOrder !== 'number' || !Number.isFinite(sortOrder)) {
          throw new Error(`Missing or invalid labelIdToSortOrder.${labelId}`);
        }
        batch.update(db.collection(collections.assignmentLabels).doc(labelId), {
          sortOrder,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', actor.memberId, {
        count: entries.length,
      });
      return {ok: true};
    }

    case 'role.insert':
    case 'role.update':
    case 'role.archive':
    case 'role.restore':
    case 'role.delete':
    case 'role.reorder':
    case 'role.seed': {
      requireAdmin(actor);
      const listsRef = db.collection('utilities').doc('Lists');
      const listsData = await getUtilitiesListsDoc();
      const previousRoles = getRolesArray(listsData);
      let roles = getRolesArray(listsData);
      let auditEntityId = actor.memberId;
      let auditEntityType = 'role';
      let auditDetails: Record<string, unknown> = {
        count: roles.length,
      };
      let auditBefore: Record<string, unknown> | null = null;
      let auditAfter: Record<string, unknown> | null = null;

      if (operation === 'role.insert') {
        const role = payload['role'] as Record<string, unknown>;
        const roleId = requireString(role['id'], 'role.id');
        auditEntityId = roleId;
        auditDetails = {
          count: roles.length + 1,
          name: role['hebrewName'],
        };
        auditAfter = role;
        roles = [...roles, role];
      } else if (operation === 'role.update') {
        const role = payload['role'] as Record<string, unknown>;
        const roleId = requireString(role['id'], 'role.id');
        auditEntityId = roleId;
        auditBefore = roles.find((item) => item['id'] === roleId) ?? null;
        auditAfter = role;
        auditDetails = {
          count: roles.length,
          name: role['hebrewName'],
        };
        roles = roles.map((item) => (item['id'] === roleId ? role : item));
      } else if (operation === 'role.archive' || operation === 'role.restore') {
        const roleId = requireString(payload['roleId'], 'roleId');
        auditEntityId = roleId;
        auditBefore = roles.find((item) => item['id'] === roleId) ?? null;
        roles = roles.map((item) => {
          if (item['id'] !== roleId) return item;
          return {
            ...item,
            isArchived: operation === 'role.archive',
            isVisible: operation === 'role.restore' ? true : item['isVisible'],
            updatedAt: new Date().toISOString(),
          };
        });
        auditAfter = roles.find((item) => item['id'] === roleId) ?? null;
        auditDetails = {
          count: roles.length,
          name: auditAfter?.['hebrewName'] ?? auditBefore?.['hebrewName'],
        };
      } else if (operation === 'role.delete') {
        const roleId = requireString(payload['roleId'], 'roleId');
        auditEntityId = roleId;
        auditBefore = roles.find((item) => item['id'] === roleId) ?? null;
        auditDetails = {
          count: Math.max(roles.length - 1, 0),
          name: auditBefore?.['hebrewName'],
        };
        roles = roles.filter((item) => item['id'] !== roleId);
      } else if (operation === 'role.reorder') {
        const sortOrderMap = payload['roleIdToSortOrder'] as Record<string, number>;
        auditEntityType = 'roleBatch';
        auditDetails = {
          count: roles.length,
        };
        roles = roles.map((item) => ({
          ...item,
          sortOrder: sortOrderMap[String(item['id'])] ?? item['sortOrder'],
          updatedAt: new Date().toISOString(),
        }));
        auditBefore = {roles: previousRoles};
        auditAfter = {roles};
      } else if (operation === 'role.seed') {
        if (roles.length > 0) return {ok: true};
        const seedRoles = Array.isArray(payload['roles']) ? payload['roles'] : [];
        auditEntityType = 'roleBatch';
        auditDetails = {
          count: seedRoles.length,
        };
        auditAfter = {roles: seedRoles};
        roles = seedRoles as Array<Record<string, unknown>>;
      }

      await listsRef.set({Roles: roles}, {merge: true});
      await writeAuditLog(db, collections, actor, operation, auditEntityType, auditEntityId, auditDetails, {
        before: auditBefore,
        after: auditAfter,
      });
      return {ok: true};
    }

    case 'category.insert':
    case 'category.update':
    case 'category.delete':
    case 'category.permanentlyDelete':
    case 'category.restore': {
      requireAdmin(actor);
      const listsRef = db.collection('utilities').doc('Lists');
      const listsData = await getUtilitiesListsDoc();
      let categories = getCategoriesArray(listsData);
      let auditEntityId = actor.memberId;
      let auditDetails: Record<string, unknown> = {
        count: categories.length,
      };
      let auditBefore: Record<string, unknown> | null = null;
      let auditAfter: Record<string, unknown> | null = null;

      if (operation === 'category.insert') {
        const category = payload['category'] as Record<string, unknown>;
        const categoryId = requireString(category['id'], 'category.id');
        auditEntityId = categoryId;
        auditDetails = {
          count: categories.length + 1,
          name: category['name'],
        };
        auditAfter = category;
        categories = [...categories, category];
      } else if (operation === 'category.update') {
        const category = payload['category'] as Record<string, unknown>;
        const categoryId = requireString(category['id'], 'category.id');
        auditEntityId = categoryId;
        auditBefore = categories.find((item) => item['id'] === categoryId) ?? null;
        auditAfter = category;
        auditDetails = {
          count: categories.length,
          name: category['name'],
        };
        categories = categories.map((item) => (item['id'] === categoryId ? category : item));
      } else {
        const categoryId = requireString(payload['categoryId'], 'categoryId');
        auditEntityId = categoryId;
        auditBefore = categories.find((item) => item['id'] === categoryId) ?? null;
        if (operation === 'category.permanentlyDelete') {
          auditDetails = {
            count: Math.max(categories.length - 1, 0),
            name: auditBefore?.['name'],
          };
          categories = categories.filter((item) => item['id'] !== categoryId);
        } else {
          categories = categories.map((item) => {
            if (item['id'] !== categoryId) return item;
            return {
              ...item,
              isArchived: operation === 'category.delete',
              updatedAt: new Date().toISOString(),
            };
          });
          auditAfter = categories.find((item) => item['id'] === categoryId) ?? null;
          auditDetails = {
            count: categories.length,
            name: auditAfter?.['name'] ?? auditBefore?.['name'],
          };
        }
      }

      await listsRef.set({Categories: categories}, {merge: true});
      await writeAuditLog(db, collections, actor, operation, 'category', auditEntityId, auditDetails, {
        before: auditBefore,
        after: auditAfter,
      });
      return {ok: true};
    }

    default:
      throw new HttpError(400, `Unsupported operation: ${operation}`);
  }
}

class HttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

app.post('/auth/list-members', async (request: Request, response: Response) => {
  try {
    const environment = getEnvironmentMode(request.body?.environment);
    const collections = getCollections(environment);
    const snapshot = await db.collection(collections.teamMembers).orderBy('name').get();
    const members = snapshot.docs
      .map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          uniqueKey: data['uniqueKey'] ?? '',
          name: data['name'] ?? '',
          isActive: data['isActive'] === true,
          hasPasscode: data['passcodeLength'] != null,
          passcodeLength: data['passcodeLength'] ?? null,
          allowMultipleAssignments: data['allowMultipleAssignments'] === true,
        };
      })
      .filter((member) => member.allowMultipleAssignments !== true);
    response.json({members});
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/auth/sign-in', async (request: Request, response: Response) => {
  try {
    const uniqueKey = requireString(request.body?.uniqueKey, 'uniqueKey');
    const passcode = requireString(request.body?.passcode, 'passcode');
    const environment = getEnvironmentMode(request.body?.environment);
    const collections = getCollections(environment);
    const memberResult = await readTeamMemberByUniqueKey(db, collections, uniqueKey);

    if (memberResult == null) {
      throw new HttpError(404, 'משתמש לא נמצא');
    }

    const memberData = memberResult.data;
    if (memberData['isActive'] !== true) {
      throw new HttpError(403, 'לא ניתן להתחבר עם משתמש לא פעיל');
    }

    const credentialRef = db.collection(collections.privateCredentials).doc(memberResult.id);
    const credentialDoc = await credentialRef.get();
    let isValid = false;
    let length: number | null =
      typeof memberData['passcodeLength'] === 'number'
        ? memberData['passcodeLength']
        : null;

    if (credentialDoc.exists) {
      const credentialData = credentialDoc.data();
      const hash = credentialData?.['passcodeHash'];
      if (typeof hash === 'string') {
        isValid = verifyPasscode(passcode, hash);
        length = typeof credentialData?.['passcodeLength'] === 'number'
          ? credentialData['passcodeLength']
          : length;
        if (isValid) {
          await credentialRef.set({
            passcodeValue: passcode,
            passcodeLength: length ?? passcode.length,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      }
    } else if (typeof memberData['passcode'] === 'string' && (memberData['passcode'] as string).length > 0) {
      isValid = memberData['passcode'] === passcode;
      if (isValid) {
        await upsertPrivatePasscodeCredential(
          collections,
          memberResult.id,
          passcode,
          length ?? passcode.length,
          {
            migratedFromLegacyFieldAt: FieldValue.serverTimestamp(),
          },
        );
        await db.collection(collections.teamMembers).doc(memberResult.id).update({
          passcode: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }

    if (!isValid) {
      throw new HttpError(403, 'קוד הגישה שגוי');
    }

    await ensureFirebaseAuthUser(memberResult.id, memberData);
    const customToken = await auth.createCustomToken(
      memberResult.id,
      stripUndefined({
        uniqueKey,
        isAdmin: memberData['isAdmin'] === true,
      }),
    );

    response.json({
      ok: true,
      customToken,
      memberId: memberResult.id,
      uniqueKey,
      passcodeLength: length ?? passcode.length,
      isAdmin: memberData['isAdmin'] === true,
    });
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/auth/validate-session', async (request: Request, response: Response) => {
  try {
    const auth = await authenticateRequest(request);
    response.json({
      ok: true,
      memberId: auth.actor.memberId,
      uniqueKey: auth.actor.uniqueKey,
      isAdmin: auth.actor.isAdmin,
    });
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/auth/sign-out', async (request: Request, response: Response) => {
  try {
    response.json({ok: true});
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/config', async (request: Request, response: Response) => {
  try {
    const environment = getEnvironmentMode(request.body?.environment);
    const result = await getCalendarConfigForClient(db, environment);
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/status', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    const result = await getCalendarStatusForClient(db, authContext.environment);
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/oauth/start', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);
    const redirectUri = requireString(request.body?.redirectUri, 'redirectUri');
    const result = await createCalendarAuthUrl(
      db,
      authContext.environment,
      redirectUri,
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/oauth/exchange', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);
    const code = requireString(request.body?.code, 'code');
    const redirectUri = requireString(request.body?.redirectUri, 'redirectUri');
    const result = await exchangeCalendarAuthCode(
      db,
      authContext.environment,
      code,
      redirectUri,
      {
        memberId: authContext.actor.memberId,
        isAdmin: authContext.actor.isAdmin,
      },
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/oauth/sign-out', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);
    const result = await disconnectCalendarAuth(db, authContext.environment);
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/action', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    const action = requireString(request.body?.action, 'action');
    const payload =
      (request.body?.payload as Record<string, unknown> | undefined) ?? {};
    const result = await executeCalendarAction(
      db,
      {
        memberId: authContext.actor.memberId,
        isAdmin: authContext.actor.isAdmin,
      },
      authContext.environment,
      action,
      payload,
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/sync-app-event-attendees', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);

    const summary = await syncAppEventCalendars(
      {
        firestore: db,
        actor: {
          memberId: authContext.actor.memberId,
          isAdmin: authContext.actor.isAdmin,
        },
        environment: authContext.environment,
        collections: authContext.collections,
      },
      {
        eventId: optionalString(request.body?.eventId),
      },
    );

    response.json({
      ok: true,
      scannedCount: summary.scannedCount,
      syncedCount: summary.changedCount,
      skippedCount: summary.upToDateCount,
      failedCount: summary.failedEventIds.length,
      failedEventIds: summary.failedEventIds,
      createdEventPartCount: summary.createdEventPartCount,
      updatedEventPartCount: summary.updatedEventPartCount,
      deletedEventPartCount: summary.deletedEventPartCount,
      updatedAttendeeEventCount: summary.updatedAttendeeEventCount,
      repairedEventSyncStateCount: summary.repairedEventSyncStateCount,
      removedOrphanedCount: summary.removedOrphanedCount,
      cleanedSyncStateCount: summary.cleanedSyncStateCount,
    });
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/sync-events-and-constraints', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);

    const combined = await syncEventsAndConstraints(
      {
        firestore: db,
        actor: {
          memberId: authContext.actor.memberId,
          isAdmin: authContext.actor.isAdmin,
        },
        environment: authContext.environment,
        collections: authContext.collections,
        rejectConstraint: async (teamMemberId: string, constraintId: string) =>
          await updateConstraintStatusForTeamMember(
            authContext.collections,
            authContext.actor,
            teamMemberId,
            constraintId,
            'rejected',
            {
              wasAutoRejectedFromCalendar: true,
            },
          ),
      },
    );
    const eventSummary = combined.appEvents;
    const constraintSummary = combined.constraints;

    response.json({
      ok: true,
      scannedEventCount: eventSummary.scannedCount,
      syncedEventCount: eventSummary.changedCount,
      skippedEventCount: eventSummary.upToDateCount,
      failedEventCount: eventSummary.failedEventIds.length,
      failedEventIds: eventSummary.failedEventIds,
      scannedConstraintCount: constraintSummary.scannedCount,
      changedConstraintCount: constraintSummary.changedCount,
      upToDateConstraintCount: constraintSummary.upToDateCount,
      rejectedConstraintCount: constraintSummary.rejectedConstraintCount,
      retriedConstraintCount:
        constraintSummary.changedCount + constraintSummary.failedConstraintIds.length,
      successfulConstraintRetryCount: constraintSummary.changedCount,
      skippedConstraintCount: constraintSummary.upToDateCount,
      failedConstraintCount: constraintSummary.failedConstraintIds.length,
      failedConstraintIds: constraintSummary.failedConstraintIds,
      createdEventPartCount: eventSummary.createdEventPartCount,
      updatedEventPartCount: eventSummary.updatedEventPartCount,
      deletedEventPartCount: eventSummary.deletedEventPartCount,
      updatedAttendeeEventCount: eventSummary.updatedAttendeeEventCount,
      repairedEventSyncStateCount: eventSummary.repairedEventSyncStateCount,
      createdConstraintEventCount: constraintSummary.createdConstraintEventCount,
      updatedConstraintEventCount: constraintSummary.updatedConstraintEventCount,
      deletedConstraintEventCount: constraintSummary.deletedConstraintEventCount,
      repairedConstraintSyncStateCount: constraintSummary.repairedConstraintSyncStateCount,
      removedOrphanedEventCount: eventSummary.removedOrphanedCount,
      cleanedEventSyncStateCount: eventSummary.cleanedSyncStateCount,
      cleanedConstraintSyncStateCount: constraintSummary.cleanedSyncStateCount,
      message: combined.message,
    });
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/drive/action', async (request: Request, response: Response) => {
  try {
    const {actor} = await authenticateRequest(request);
    const action = requireString(request.body?.action, 'action');
    if (!canExecuteDriveAction(action)) {
      throw new HttpError(400, `Unsupported drive action: ${action}`);
    }

    if (action !== 'listFiles') {
      requireAdmin(actor);
    }

    const result = await executeDriveAction(
      db,
      action,
      (request.body as Record<string, unknown> | undefined) ?? {},
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/drive/export', async (request: Request, response: Response) => {
  try {
    const {actor} = await authenticateRequest(request);
    requireAdmin(actor);

    const type = request.body?.type === 'assignments' ? 'assignments' : 'full';
    const rawMode = request.body?.mode;
    if (rawMode != null && rawMode !== 'perPerson' && rawMode !== 'perEvent') {
      throw new HttpError(400, `Unsupported assignment export mode: ${String(rawMode)}`);
    }
    const assignmentMode = rawMode === 'perEvent' ? 'perEvent' : 'perPerson';
    const rawEventIds = request.body?.eventIds;
    const eventIds = Array.isArray(rawEventIds)
      ? rawEventIds
          .filter((value): value is string => typeof value === 'string')
          .map((value) => value.trim())
          .filter((value) => value.length > 0)
      : [];

    if (type === 'assignments' && assignmentMode === 'perEvent' && eventIds.length === 0) {
      throw new HttpError(400, 'Select at least one future event to export');
    }

    const result = await exportProductionDataToSheets(db, type, {
      assignmentMode,
      eventIds,
    });
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/mutate', async (request: Request, response: Response) => {
  try {
    const {actor, environment, collections} = await authenticateRequest(request);
    const operation = requireString(request.body?.operation, 'operation');
    const payload =
      (request.body?.payload as Record<string, unknown> | undefined) ?? {};
    const result = await executeMutation(
      actor,
      environment,
      collections,
      operation,
      payload,
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

function handleError(response: Response, error: unknown): void {
  if (error instanceof DriveExportValidationError) {
    response.status(400).json({
      ok: false,
      error: error.message,
    });
    return;
  }

  if (error instanceof HttpError) {
    response.status(error.status).json({
      ok: false,
      error: error.message,
    });
    return;
  }

  response.status(500).json({
    ok: false,
    error: error instanceof Error ? error.message : 'Unknown error',
  });
}

export const api = onRequest(
  {
    region: 'us-central1',
    invoker: 'public',
  },
  app,
);

// Test-only re-exports. Not part of the public API; used by availability.test.ts.
export {
  normalizeDayInIsrael as __testNormalizeDayInIsrael,
  constraintMatchesDate as __testConstraintMatchesDate,
  memberAvailableForEvent as __testMemberAvailableForEvent,
};
