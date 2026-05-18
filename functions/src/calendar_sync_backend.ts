import {
  FieldValue,
  Firestore,
  Timestamp,
} from 'firebase-admin/firestore';
import {executeCalendarAction} from './calendar_integration';

export type BackendEnvironmentMode = 'production' | 'test';

export type BackendCollections = {
  teamMembers: string;
  events: string;
  assignments: string;
  checklistItems: string;
  presets: string;
  calendarSync: string;
  eventCalendarSync: string;
  logs: string;
  privateCredentials: string;
  privateSessions: string;
  privateGoogleCalendarAuth: string;
};

export type BackendSyncActor = {
  memberId: string;
  isAdmin: boolean;
};

export type AppEventSyncReport = {
  scannedCount: number;
  changedCount: number;
  upToDateCount: number;
  failedEventIds: string[];
  createdEventPartCount: number;
  updatedEventPartCount: number;
  deletedEventPartCount: number;
  updatedAttendeeEventCount: number;
  repairedEventSyncStateCount: number;
  removedOrphanedCount: number;
  cleanedSyncStateCount: number;
};

export type ConstraintSyncReport = {
  scannedCount: number;
  changedCount: number;
  upToDateCount: number;
  failedConstraintIds: string[];
  rejectedConstraintCount: number;
  createdConstraintEventCount: number;
  updatedConstraintEventCount: number;
  deletedConstraintEventCount: number;
  repairedConstraintSyncStateCount: number;
  cleanedSyncStateCount: number;
};

export type CombinedCalendarSyncReport = {
  appEvents: AppEventSyncReport;
  constraints: ConstraintSyncReport;
  message: string;
};

type ManagedCalendarEventSummary = {
  id: string;
  status: string | null;
  summary: string | null;
  description: string | null;
  organizerEmail: string | null;
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

type DesiredAppEventState = {
  payload: Record<string, unknown>;
  useAllDay: boolean;
  location: string | null;
  colorId: string;
  assemblyTitle: string;
  mainTitle: string;
  assemblyStartPrefix: string | null;
  assemblyEndPrefix: string | null;
  mainStartPrefix: string | null;
  mainEndPrefix: string | null;
  allDayStartDate: string | null;
  allDayEndDate: string | null;
};

type DesiredConstraintState = {
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

type AppEventItemResult = {
  changed: boolean;
  createdEventPartCount: number;
  updatedEventPartCount: number;
  deletedEventPartCount: number;
  updatedAttendeeEventCount: number;
  repairedEventSyncStateCount: number;
};

type ConstraintItemResult = {
  changed: boolean;
  rejected: boolean;
  createdConstraintEventCount: number;
  updatedConstraintEventCount: number;
  deletedConstraintEventCount: number;
  repairedConstraintSyncStateCount: number;
};

type ConstraintEntry = {
  teamMemberId: string;
  teamMemberData: Record<string, unknown>;
  constraint: Record<string, unknown>;
};

type SyncDependencies = {
  firestore: Firestore;
  actor: BackendSyncActor;
  environment: BackendEnvironmentMode;
  collections: BackendCollections;
};

type ConstraintDependencies = SyncDependencies & {
  rejectConstraint: (teamMemberId: string, constraintId: string) => Promise<boolean>;
};

const ISRAEL_TIME_ZONE = 'Asia/Jerusalem';
const TEST_MODE_PREFIX = 'שבצק טסטינג: ';
const APP_EVENT_COLOR_ID = '7';
const TEST_MODE_COLOR_ID = '5';
const UNAVAILABILITY_COLOR_ID = '8';
const AUTOREJECTION_MESSAGE =
  '(מגבלה זו נדחתה באופן אוטומטי בגלל שאחד מהמנהלים מחק את המגבלה מגוגל קלנדר)';
const israelDateFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: ISRAEL_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

function asRecord(value: unknown, fieldName: string): Record<string, unknown> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`Missing or invalid ${fieldName}`);
  }
  return value as Record<string, unknown>;
}

function requireString(value: unknown, fieldName: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Missing or invalid ${fieldName}`);
  }
  return value;
}

function optionalString(value: unknown): string | null {
  if (value == null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new Error('Expected string value');
  }
  return value;
}

function optionalStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((entry) => (typeof entry === 'string' ? entry : null))
    .filter((entry): entry is string => entry != null);
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

function asDate(value: unknown, fieldName: string): Date {
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed;
    }
  }
  throw new Error(`Missing or invalid ${fieldName}`);
}

function normalizeOptionalText(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

function uniqueSortedStrings(values: Iterable<string>): string[] {
  return Array.from(new Set(
    Array.from(values)
      .map((value) => value.trim())
      .filter((value) => value.length > 0),
  )).sort((left, right) => left.localeCompare(right));
}

/**
 * A member is eligible for the "invite all permanent staff" calendar behavior
 * when they are a permanent, active, non-archived member with a non-empty
 * email. Mirrors the Flutter TeamMember model migration defaults: a missing
 * `isActive` is treated as active; a missing `isArchived` is derived from
 * `!isActive`.
 */
export function isEligiblePermanentMember(
  data: Record<string, unknown> | null | undefined,
): boolean {
  if (data == null) {
    return false;
  }
  if (data['isPermanent'] !== true) {
    return false;
  }
  const isActive = data['isActive'] === false ? false : true;
  const isArchived =
    typeof data['isArchived'] === 'boolean'
      ? (data['isArchived'] as boolean)
      : !isActive;
  if (!isActive || isArchived) {
    return false;
  }
  return normalizeOptionalText(data['email']) != null;
}

/**
 * The "invite all permanent staff" substitution applies when the event opted
 * in, is permanent-only (a missing `relevantForExtendedTeam` is treated as
 * permanent-only, matching the model default of `false`), and currently has
 * zero assignment records.
 */
export function shouldInviteAllPermanentForEvent(
  eventData: Record<string, unknown>,
  assignmentCount: number,
): boolean {
  return (
    assignmentCount === 0 &&
    eventData['inviteAllPermanentWhenUnassigned'] === true &&
    eventData['relevantForExtendedTeam'] !== true
  );
}

function getIsraelDateKey(date: Date): string {
  const parts = israelDateFormatter.formatToParts(date);
  const year = parts.find((part) => part.type === 'year')?.value;
  const month = parts.find((part) => part.type === 'month')?.value;
  const day = parts.find((part) => part.type === 'day')?.value;
  if (year == null || month == null || day == null) {
    throw new Error('Failed to format Israel date');
  }
  return `${year}-${month}-${day}`;
}

function dateFromKey(key: string, fieldName: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key);
  if (match == null) {
    throw new Error(`Missing or invalid ${fieldName}`);
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  return new Date(Date.UTC(year, month - 1, day));
}

function normalizeStoredDate(date: Date): Date {
  return dateFromKey(getIsraelDateKey(date), 'date');
}

function addDays(date: Date, days: number): Date {
  return new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate() + days,
  ));
}

function compareDateKeys(left: string, right: string): number {
  return left.localeCompare(right);
}

function formatDateTimePrefix(date: Date, time: string): string {
  return `${getIsraelDateKey(date)}T${time}`;
}

function toLocalDateTimePrefix(value: string | null): string | null {
  if (value == null || value.length < 16) {
    return value;
  }
  return value.slice(0, 16);
}

function createEventTitle(name: string, environment: BackendEnvironmentMode): string {
  return environment === 'test' ? `${TEST_MODE_PREFIX}${name}` : name;
}

function createAssemblyTitle(name: string, environment: BackendEnvironmentMode): string {
  const title = `${name} - התייצבות והכנות`;
  return environment === 'test' ? `${TEST_MODE_PREFIX}${title}` : title;
}

function createConstraintTitle(name: string, environment: BackendEnvironmentMode): string {
  const title = `${name} - מגבלה`;
  return environment === 'test' ? `${TEST_MODE_PREFIX}${title}` : title;
}

function cleanConstraintNote(note: string | null): string | null {
  if (note == null || note.trim().length === 0) {
    return null;
  }
  const cleaned = note
    .replace(`\n\n${AUTOREJECTION_MESSAGE}`, '')
    .replace(AUTOREJECTION_MESSAGE, '')
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

function appEventColorId(environment: BackendEnvironmentMode): string {
  return environment === 'test' ? TEST_MODE_COLOR_ID : APP_EVENT_COLOR_ID;
}

function constraintColorId(environment: BackendEnvironmentMode): string {
  return environment === 'test' ? TEST_MODE_COLOR_ID : UNAVAILABILITY_COLOR_ID;
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

function formatRRuleUntil(date: Date): string {
  const year = date.getUTCFullYear().toString().padStart(4, '0');
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${year}${month}${day}T235959Z`;
}

function buildConstraintRecurrenceRule(constraint: Record<string, unknown>): string | null {
  const repeatType = normalizeOptionalText(constraint['repeatType']);
  if (repeatType == null || constraint['repeatEndDate'] == null) {
    return null;
  }

  const repeatEndDate = normalizeStoredDate(
    asDate(constraint['repeatEndDate'], 'constraint.repeatEndDate'),
  );
  const until = formatRRuleUntil(repeatEndDate);
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
  for (let index = 0; index < 240; index += 1) {
    const daysInMonth = new Date(Date.UTC(
      cursor.getUTCFullYear(),
      cursor.getUTCMonth() + 1,
      0,
    )).getUTCDate();
    if (day <= daysInMonth) {
      const candidate = new Date(Date.UTC(
        cursor.getUTCFullYear(),
        cursor.getUTCMonth(),
        day,
      ));
      if (candidate.getTime() >= from.getTime()) {
        if (maxDate != null && candidate.getTime() > maxDate.getTime()) {
          return null;
        }
        return candidate;
      }
    }

    const nextMonth = new Date(Date.UTC(
      cursor.getUTCFullYear(),
      cursor.getUTCMonth() + 1,
      1,
    ));
    if (maxDate != null && nextMonth.getTime() > maxDate.getTime()) {
      return null;
    }
    cursor = nextMonth;
  }
  return null;
}

function resolveConstraintStartDate(constraint: Record<string, unknown>): Date {
  const startDate = normalizeStoredDate(asDate(constraint['startDate'], 'constraint.startDate'));
  const repeatType = normalizeOptionalText(constraint['repeatType']);
  if (repeatType == null || constraint['repeatEndDate'] == null) {
    return startDate;
  }

  const repeatEndDate = normalizeStoredDate(
    asDate(constraint['repeatEndDate'], 'constraint.repeatEndDate'),
  );
  switch (repeatType) {
    case 'daily':
      return startDate;
    case 'weekly': {
      const repeatDay = readInt(constraint['repeatDay']);
      if (repeatDay == null || repeatDay < 1 || repeatDay > 7) {
        return startDate;
      }
      const jsWeekday = startDate.getUTCDay() === 0 ? 7 : startDate.getUTCDay();
      const offset = (repeatDay - jsWeekday + 7) % 7;
      const candidate = addDays(startDate, offset);
      return candidate.getTime() > repeatEndDate.getTime() ? startDate : candidate;
    }
    case 'monthly': {
      const repeatDay = readInt(constraint['repeatDay']);
      if (repeatDay == null || repeatDay < 1 || repeatDay > 31) {
        return startDate;
      }
      return nextMonthlyOccurrenceOnOrAfter(startDate, repeatDay, repeatEndDate) ?? startDate;
    }
    default:
      return startDate;
  }
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

function serializeTeamMember(teamMemberId: string, teamMemberData: Record<string, unknown>): Record<string, unknown> {
  return {
    id: teamMemberId,
    name: requireString(teamMemberData['name'] ?? teamMemberId, 'teamMember.name'),
    email: optionalString(teamMemberData['email']),
    availableRoleKeys: getAvailableRoleKeys(teamMemberData),
  };
}

function serializeConstraint(constraint: Record<string, unknown>): Record<string, unknown> {
  const repeatType = normalizeOptionalText(constraint['repeatType']);
  const repeatDay = readInt(constraint['repeatDay']);
  return stripUndefined({
    id: requireString(constraint['id'], 'constraint.id'),
    startDate: getIsraelDateKey(asDate(constraint['startDate'], 'constraint.startDate')),
    endDate:
      constraint['endDate'] == null
        ? null
        : getIsraelDateKey(asDate(constraint['endDate'], 'constraint.endDate')),
    note: normalizeOptionalText(constraint['note']),
    constraintType: 'unavailability',
    startTime: normalizeOptionalText(constraint['startTime']),
    endTime: normalizeOptionalText(constraint['endTime']),
    repeatType:
      repeatType === 'daily' || repeatType === 'weekly' || repeatType === 'monthly'
        ? repeatType
        : null,
    repeatDay: repeatDay ?? undefined,
    repeatEndDate:
      constraint['repeatEndDate'] == null
        ? null
        : getIsraelDateKey(asDate(constraint['repeatEndDate'], 'constraint.repeatEndDate')),
  });
}

function stripUndefined<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(
    Object.entries(value).filter(([, entryValue]) => entryValue !== undefined),
  ) as T;
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
    organizerEmail: optionalString(record['organizerEmail']),
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

function pickCanonicalCandidate(
  candidates: ManagedCalendarEventSummary[],
  preferredId?: string | null,
): ManagedCalendarEventSummary | null {
  if (preferredId != null && preferredId.length > 0) {
    const preferred = candidates.find((candidate) => candidate.id === preferredId);
    if (preferred != null) {
      return preferred;
    }
  }
  const sorted = [...candidates].sort((left, right) => left.id.localeCompare(right.id));
  return sorted[0] ?? null;
}

function normalizeComparableAttendeeEmails(
  emails: Iterable<string>,
  ignoredEmails: Iterable<string> = [],
): string[] {
  const ignored = new Set(
    Array.from(ignoredEmails)
      .map((email) => normalizeEmail(email))
      .filter((email) => email.length > 0),
  );
  return uniqueSortedStrings(
    Array.from(emails)
      .map((email) => normalizeEmail(email))
      .filter((email) => email.length > 0 && !ignored.has(email)),
  );
}

function getImplicitAttendeeEmails(events: Iterable<ManagedCalendarEventSummary | null>): string[] {
  const organizerEmails = Array.from(events)
    .map((event) => event?.organizerEmail ?? null)
    .filter((email): email is string => email != null && email.trim().length > 0);
  return normalizeComparableAttendeeEmails(organizerEmails);
}

function attendeesMatch(
  managedEvent: ManagedCalendarEventSummary | null,
  desiredEmails: string[],
  ignoredEmails: Iterable<string> = [],
): boolean {
  if (managedEvent == null || managedEvent.attendeesKnown === false) {
    return false;
  }
  const current = normalizeComparableAttendeeEmails(
    managedEvent.attendeeEmails,
    ignoredEmails,
  );
  const desired = normalizeComparableAttendeeEmails(desiredEmails, ignoredEmails);
  return current.length === desired.length &&
    current.every((email, index) => email === desired[index]);
}

function appEventMatchesDesired(
  managedEvent: ManagedCalendarEventSummary | null,
  desired: DesiredAppEventState,
  expectedType: 'assembly' | 'main' | 'allDay',
): boolean {
  if (managedEvent == null) {
    return false;
  }
  if (
    managedEvent.eventType !== expectedType ||
    managedEvent.colorId !== desired.colorId ||
    normalizeOptionalText(managedEvent.location) !== desired.location
  ) {
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

function constraintMatchesDesired(
  managedEvent: ManagedCalendarEventSummary | null,
  desired: DesiredConstraintState,
  ignoredEmails: Iterable<string> = [],
): boolean {
  if (managedEvent == null) {
    return false;
  }

  if (
    managedEvent.summary !== desired.summary ||
    managedEvent.description !== desired.description ||
    managedEvent.colorId !== desired.colorId ||
    managedEvent.constraintType !== 'unavailability' ||
    managedEvent.teamMemberId !== String(desired.teamMemberPayload['id']) ||
    (managedEvent.repeatType ?? '') !== (desired.repeatType ?? '') ||
    (managedEvent.repeatDay ?? '') !== (desired.repeatDay ?? '') ||
    (managedEvent.repeatEndDate ?? '') !== (desired.repeatEndDate ?? '')
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

  if (!attendeesMatch(managedEvent, desired.attendeeEmails, ignoredEmails)) {
    return false;
  }

  if (desired.startDateTime != null || desired.endDateTime != null) {
    return toLocalDateTimePrefix(managedEvent.startDateTime) === desired.startDateTime &&
      toLocalDateTimePrefix(managedEvent.endDateTime) === desired.endDateTime;
  }
  return managedEvent.startDate === desired.startDate &&
    managedEvent.endDate === desired.endDate;
}

async function readEventById(
  firestore: Firestore,
  collections: BackendCollections,
  eventId: string,
): Promise<Record<string, unknown> | null> {
  const snapshot = await firestore.collection(collections.events).doc(eventId).get();
  return snapshot.exists ? snapshot.data() ?? null : null;
}

async function readTeamMemberById(
  firestore: Firestore,
  collections: BackendCollections,
  teamMemberId: string,
): Promise<Record<string, unknown> | null> {
  const snapshot = await firestore.collection(collections.teamMembers).doc(teamMemberId).get();
  return snapshot.exists ? snapshot.data() ?? null : null;
}

async function executeAction(
  dependencies: SyncDependencies,
  action: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  return executeCalendarAction(
    dependencies.firestore,
    dependencies.actor,
    dependencies.environment,
    action,
    payload,
  );
}

async function listManagedCalendarEvents(
  dependencies: SyncDependencies,
  filters: {
    kind?: 'app' | 'constraint';
    eventId?: string | null;
    constraintId?: string | null;
  } = {},
): Promise<ManagedCalendarEventSummary[]> {
  const result = await executeAction(
    dependencies,
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

async function getManagedCalendarEvent(
  dependencies: SyncDependencies,
  calendarEventId: string,
): Promise<ManagedCalendarEventSummary | null> {
  const result = await executeAction(
    dependencies,
    'getManagedCalendarEvent',
    {calendarEventId},
  );
  return asManagedCalendarEventSummary(result['event']);
}

async function loadManagedCalendarEventsById(
  dependencies: SyncDependencies,
  ids: Iterable<string>,
): Promise<Map<string, ManagedCalendarEventSummary>> {
  const result = new Map<string, ManagedCalendarEventSummary>();
  const uniqueIds = uniqueSortedStrings(ids);
  for (const calendarEventId of uniqueIds) {
    const managedEvent = await getManagedCalendarEvent(dependencies, calendarEventId);
    if (managedEvent != null) {
      result.set(calendarEventId, managedEvent);
    }
  }
  return result;
}

function buildDesiredAppEventState(
  eventId: string,
  eventData: Record<string, unknown>,
  environment: BackendEnvironmentMode,
): DesiredAppEventState {
  const eventName = requireString(eventData['name'], 'event.name');
  const startDate = normalizeStoredDate(asDate(eventData['startDate'], 'event.startDate'));
  const endDate = normalizeStoredDate(asDate(eventData['endDate'], 'event.endDate'));
  const assemblyTime = normalizeOptionalText(eventData['assemblyTime']) ?? '';
  const startTime = normalizeOptionalText(eventData['startTime']) ?? '';
  const actualShowStartTime = normalizeOptionalText(eventData['actualShowStartTime']) ?? '';
  const endTime = normalizeOptionalText(eventData['endTime']) ?? '';
  const separatorTime = actualShowStartTime.length > 0 ? actualShowStartTime : startTime;
  const useAllDay = assemblyTime.length === 0 || endTime.length === 0;
  const location = normalizeOptionalText(eventData['location']);

  return {
    payload: stripUndefined({
      eventId,
      eventName,
      startDate: getIsraelDateKey(startDate),
      endDate: getIsraelDateKey(endDate),
      assemblyTime,
      separatorTime,
      endTime,
      location,
      isTestMode: environment === 'test',
    }),
    useAllDay,
    location,
    colorId: appEventColorId(environment),
    assemblyTitle: createAssemblyTitle(eventName, environment),
    mainTitle: createEventTitle(eventName, environment),
    assemblyStartPrefix:
      !useAllDay && assemblyTime.length > 0 && separatorTime.length > 0
        ? formatDateTimePrefix(startDate, assemblyTime)
        : null,
    assemblyEndPrefix:
      !useAllDay && assemblyTime.length > 0 && separatorTime.length > 0
        ? formatDateTimePrefix(startDate, separatorTime)
        : null,
    mainStartPrefix:
      !useAllDay && (separatorTime.length > 0 || assemblyTime.length > 0)
        ? formatDateTimePrefix(
          startDate,
          separatorTime.length > 0 ? separatorTime : assemblyTime,
        )
        : null,
    mainEndPrefix:
      !useAllDay && endTime.length > 0
        ? formatDateTimePrefix(endDate, endTime)
        : null,
    allDayStartDate: useAllDay ? getIsraelDateKey(startDate) : null,
    allDayEndDate: useAllDay ? getIsraelDateKey(addDays(endDate, 1)) : null,
  };
}

async function readEligiblePermanentMemberEmails(
  dependencies: SyncDependencies,
): Promise<string[]> {
  const snapshot = await dependencies.firestore
    .collection(dependencies.collections.teamMembers)
    .get();

  const emails = new Set<string>();
  for (const doc of snapshot.docs) {
    const data = doc.data() ?? {};
    if (!isEligiblePermanentMember(data)) {
      continue;
    }
    const email = normalizeOptionalText(data['email']);
    if (email != null) {
      emails.add(normalizeEmail(email));
    }
  }
  return uniqueSortedStrings(emails);
}

async function readEventAttendeeEmails(
  dependencies: SyncDependencies,
  eventId: string,
  eventData: Record<string, unknown>,
  teamMemberCache: Map<string, Record<string, unknown> | null>,
): Promise<string[]> {
  const assignmentsSnapshot = await dependencies.firestore
    .collection(dependencies.collections.assignments)
    .where('eventId', '==', eventId)
    .get();

  if (shouldInviteAllPermanentForEvent(eventData, assignmentsSnapshot.size)) {
    return readEligiblePermanentMemberEmails(dependencies);
  }

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
      teamMemberCache.set(
        teamMemberId,
        await readTeamMemberById(
          dependencies.firestore,
          dependencies.collections,
          teamMemberId,
        ),
      );
    }
    const teamMemberData = teamMemberCache.get(teamMemberId) ?? null;
    const email = normalizeOptionalText(teamMemberData?.['email']);
    if (email != null) {
      emails.add(normalizeEmail(email));
    }
  }

  return uniqueSortedStrings(emails);
}

async function updateAppEventAttendees(
  dependencies: SyncDependencies,
  calendarEventIds: Iterable<string>,
  emails: string[],
): Promise<number> {
  const uniqueIds = uniqueSortedStrings(calendarEventIds);
  for (const calendarEventId of uniqueIds) {
    await executeAction(
      dependencies,
      'updateEventAttendees',
      {
        calendarEventId,
        emails,
      },
    );
  }
  return uniqueIds.length;
}

async function deleteAppEventById(
  dependencies: SyncDependencies,
  calendarEventId: string,
  eventType: string | null,
): Promise<void> {
  await executeAction(
    dependencies,
    'deleteAppEventCalendarEvents',
    eventType === 'assembly'
      ? {assemblyCalendarEventId: calendarEventId}
      : {mainCalendarEventId: calendarEventId},
  );
}

async function deleteConstraintEventById(
  dependencies: SyncDependencies,
  calendarEventId: string,
  teamMemberId: string,
): Promise<void> {
  await executeAction(
    dependencies,
    'deleteConstraintEvent',
    {
      calendarEventId,
      teamMemberId,
    },
  );
}

async function deleteDiscoveredAppEventArtifacts(
  dependencies: SyncDependencies,
  eventId: string,
  storedIds: string[] = [],
): Promise<void> {
  const managedEvents = await listManagedCalendarEvents(dependencies, {
    kind: 'app',
    eventId,
  });
  const seen = new Set<string>();
  for (const managedEvent of managedEvents) {
    seen.add(managedEvent.id);
    await deleteAppEventById(dependencies, managedEvent.id, managedEvent.eventType);
  }
  for (const calendarEventId of storedIds) {
    if (seen.has(calendarEventId)) {
      continue;
    }
    await deleteAppEventById(dependencies, calendarEventId, null);
  }
}

async function createAppEventPart(
  dependencies: SyncDependencies,
  payload: Record<string, unknown>,
  eventType: 'assembly' | 'main' | 'allDay',
): Promise<string> {
  const result = await executeAction(
    dependencies,
    'createAppEventCalendarEventPart',
    {
      event: payload,
      eventType,
    },
  );
  return requireString(result['calendarEventId'], 'calendarEventId');
}

async function syncEventPartAttendees(
  dependencies: SyncDependencies,
  calendarEventId: string,
  managedEvent: ManagedCalendarEventSummary | null,
  desiredEmails: string[],
): Promise<number> {
  const organizerEmail = normalizeOptionalText(managedEvent?.organizerEmail);
  const currentComparableEmails = normalizeComparableAttendeeEmails([
    ...(managedEvent?.attendeeEmails ?? []),
    ...(organizerEmail == null ? [] : [organizerEmail]),
  ]);
  const desiredComparableEmails = normalizeComparableAttendeeEmails(
    desiredEmails,
    organizerEmail == null ? [] : [organizerEmail],
  );
  const currentAttendeeEmails = normalizeComparableAttendeeEmails(
    managedEvent?.attendeeEmails ?? [],
    organizerEmail == null ? [] : [organizerEmail],
  );

  let changes = 0;
  for (const email of desiredComparableEmails) {
    if (currentComparableEmails.includes(email)) {
      continue;
    }
    await executeAction(
      dependencies,
      'addAttendeeToEvent',
      {
        calendarEventId,
        email,
      },
    );
    changes += 1;
  }

  for (const email of currentAttendeeEmails) {
    if (desiredComparableEmails.includes(email)) {
      continue;
    }
    await executeAction(
      dependencies,
      'removeAttendeeFromEvent',
      {
        calendarEventId,
        email,
      },
    );
    changes += 1;
  }

  return changes;
}

async function deleteConstraintArtifacts(
  dependencies: SyncDependencies,
  constraintId: string,
  teamMemberId: string,
  storedId?: string | null,
): Promise<number> {
  const managedEvents = await listManagedCalendarEvents(dependencies, {
    kind: 'constraint',
    constraintId,
  });
  const seen = new Set<string>();
  let deletedCount = 0;
  for (const managedEvent of managedEvents) {
    seen.add(managedEvent.id);
    await deleteConstraintEventById(dependencies, managedEvent.id, teamMemberId);
    deletedCount += 1;
  }
  if (storedId != null && storedId.length > 0 && !seen.has(storedId)) {
    await deleteConstraintEventById(dependencies, storedId, teamMemberId);
    deletedCount += 1;
  }
  return deletedCount;
}

function isEventInDefaultScope(eventData: Record<string, unknown>, todayKey: string): boolean {
  // Deactivated events have no calendar presence — the Flutter app explicitly
  // calls RemoveAppEventFromCalendar on deactivation, and reactivation runs
  // the dedicated sync path. Excluding them here prevents the reconciler
  // (syncAppEventCalendars / syncAssignedEventsBestEffort) from silently
  // recreating calendar events that were intentionally removed.
  if (eventData['isDeactivated'] === true) return false;
  const endDateKey = getIsraelDateKey(asDate(eventData['endDate'], 'event.endDate'));
  return compareDateKeys(endDateKey, todayKey) >= 0;
}

function shouldEventHaveAssemblyPart(desired: DesiredAppEventState): boolean {
  return desired.useAllDay === false &&
    desired.assemblyStartPrefix != null &&
    desired.assemblyEndPrefix != null;
}

async function reconcileSingleAppEvent(
  dependencies: SyncDependencies,
  eventId: string,
  eventData: Record<string, unknown>,
  eventSyncData: Record<string, unknown> | null,
  teamMemberCache: Map<string, Record<string, unknown> | null>,
): Promise<AppEventItemResult> {
  const desired = buildDesiredAppEventState(eventId, eventData, dependencies.environment);
  const desiredEmails = await readEventAttendeeEmails(dependencies, eventId, eventData, teamMemberCache);
  const currentStateAssemblyId = optionalString(eventSyncData?.['assemblyCalendarEventId']) ?? '';
  const currentStateMainId = optionalString(eventSyncData?.['mainCalendarEventId']) ?? '';
  const currentStateStatus = optionalString(eventSyncData?.['status']) ?? '';
  const shouldHaveAssemblyPart = shouldEventHaveAssemblyPart(desired);
  let finalAssemblyId = shouldHaveAssemblyPart ? currentStateAssemblyId : '';
  let finalMainId = currentStateMainId;

  let createdEventPartCount = 0;
  let deletedEventPartCount = 0;
  let updatedAttendeeEventCount = 0;
  let repairedEventSyncStateCount = 0;

  if (!shouldHaveAssemblyPart && currentStateAssemblyId.length > 0) {
    await deleteAppEventById(dependencies, currentStateAssemblyId, 'assembly');
    deletedEventPartCount += 1;
  }

  if (shouldHaveAssemblyPart) {
    let managedAssemblyEvent: ManagedCalendarEventSummary | null = null;
    if (finalAssemblyId.length > 0) {
      managedAssemblyEvent = await getManagedCalendarEvent(dependencies, finalAssemblyId);
    }
    if (managedAssemblyEvent == null || managedAssemblyEvent.status === 'cancelled') {
      finalAssemblyId = await createAppEventPart(
        dependencies,
        desired.payload,
        'assembly',
      );
      managedAssemblyEvent = await getManagedCalendarEvent(dependencies, finalAssemblyId);
      createdEventPartCount += 1;
    }
    updatedAttendeeEventCount += await syncEventPartAttendees(
      dependencies,
      finalAssemblyId,
      managedAssemblyEvent,
      desiredEmails,
    );
  }

  let managedMainEvent: ManagedCalendarEventSummary | null = null;
  if (finalMainId.length > 0) {
    managedMainEvent = await getManagedCalendarEvent(dependencies, finalMainId);
  }
  if (managedMainEvent == null || managedMainEvent.status === 'cancelled') {
    finalMainId = await createAppEventPart(
      dependencies,
      desired.payload,
      desired.useAllDay ? 'allDay' : 'main',
    );
    managedMainEvent = await getManagedCalendarEvent(dependencies, finalMainId);
    createdEventPartCount += 1;
  }
  updatedAttendeeEventCount += await syncEventPartAttendees(
    dependencies,
    finalMainId,
    managedMainEvent,
    desiredEmails,
  );

  if (
    currentStateAssemblyId !== finalAssemblyId ||
    currentStateMainId !== finalMainId ||
    currentStateStatus !== 'synced'
  ) {
    await dependencies.firestore
      .collection(dependencies.collections.eventCalendarSync)
      .doc(eventId)
      .set({
        assemblyCalendarEventId: finalAssemblyId,
        mainCalendarEventId: finalMainId,
        status: 'synced',
        syncedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    repairedEventSyncStateCount += 1;
  }

  return {
    changed:
      createdEventPartCount > 0 ||
      deletedEventPartCount > 0 ||
      updatedAttendeeEventCount > 0 ||
      repairedEventSyncStateCount > 0,
    createdEventPartCount,
    updatedEventPartCount: 0,
    deletedEventPartCount,
    updatedAttendeeEventCount,
    repairedEventSyncStateCount,
  };
}

function buildDesiredConstraintState(
  teamMemberId: string,
  teamMemberData: Record<string, unknown>,
  constraint: Record<string, unknown>,
  environment: BackendEnvironmentMode,
): DesiredConstraintState {
  const teamMemberPayload = serializeTeamMember(teamMemberId, teamMemberData);
  const constraintPayload = serializeConstraint(constraint);
  const startDate = resolveConstraintStartDate(constraint);
  const repeatType = normalizeOptionalText(constraint['repeatType']);
  const recurrenceRule = buildConstraintRecurrenceRule(constraint);
  const hasTimeRange =
    normalizeOptionalText(constraint['startTime']) != null &&
    normalizeOptionalText(constraint['endTime']) != null;
  const rawEndBaseDate = repeatType != null
    ? startDate
    : (constraint['endDate'] == null
      ? normalizeStoredDate(asDate(constraint['startDate'], 'constraint.startDate'))
      : normalizeStoredDate(asDate(constraint['endDate'], 'constraint.endDate')));
  const attendeeEmail = normalizeOptionalText(teamMemberData['email']);

  return {
    teamMemberPayload,
    constraintPayload,
    summary: createConstraintTitle(
      requireString(teamMemberData['name'] ?? teamMemberId, 'teamMember.name'),
      environment,
    ),
    description: createConstraintDescription(normalizeOptionalText(constraint['note'])),
    colorId: constraintColorId(environment),
    attendeeEmails:
      attendeeEmail == null ? [] : [normalizeEmail(attendeeEmail)],
    startDate: hasTimeRange ? null : getIsraelDateKey(startDate),
    startDateTime: hasTimeRange
      ? formatDateTimePrefix(startDate, requireString(constraint['startTime'], 'constraint.startTime'))
      : null,
    endDate: hasTimeRange ? null : getIsraelDateKey(addDays(rawEndBaseDate, 1)),
    endDateTime: hasTimeRange
      ? formatDateTimePrefix(rawEndBaseDate, requireString(constraint['endTime'], 'constraint.endTime'))
      : null,
    recurrence: recurrenceRule == null ? [] : [recurrenceRule],
    repeatType,
    repeatDay:
      constraintPayload['repeatDay'] == null ? null : String(constraintPayload['repeatDay']),
    repeatEndDate:
      constraintPayload['repeatEndDate'] == null ? null : String(constraintPayload['repeatEndDate']),
  };
}

async function saveFailedConstraintSyncState(
  dependencies: SyncDependencies,
  constraintId: string,
  teamMemberId: string,
  errorMessage: string,
  previousRetryCount: number,
): Promise<void> {
  await dependencies.firestore
    .collection(dependencies.collections.calendarSync)
    .doc(constraintId)
    .set({
      calendarEventId: '',
      teamMemberId,
      status: 'failed',
      syncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      retryCount: previousRetryCount + 1,
      errorMessage,
    });
}

async function saveSyncedConstraintSyncState(
  dependencies: SyncDependencies,
  constraintId: string,
  teamMemberId: string,
  calendarEventId: string,
): Promise<void> {
  await dependencies.firestore
    .collection(dependencies.collections.calendarSync)
    .doc(constraintId)
    .set({
      calendarEventId,
      teamMemberId,
      status: 'synced',
      syncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      retryCount: 0,
      errorMessage: null,
    });
}

async function reconcileSingleConstraint(
  dependencies: ConstraintDependencies,
  constraintId: string,
  entry: ConstraintEntry,
  discoveredEvents: ManagedCalendarEventSummary[],
  syncState: Record<string, unknown> | null,
): Promise<ConstraintItemResult> {
  const desired = buildDesiredConstraintState(
    entry.teamMemberId,
    entry.teamMemberData,
    entry.constraint,
    dependencies.environment,
  );
  const currentStateCalendarEventId = optionalString(syncState?.['calendarEventId']) ?? '';
  const currentStateStatus = optionalString(syncState?.['status']) ?? '';
  const currentRetryCount = readInt(syncState?.['retryCount']) ?? 0;

  const candidateIds = uniqueSortedStrings([
    ...discoveredEvents.map((event) => event.id),
    currentStateCalendarEventId,
  ]);
  const exactById = await loadManagedCalendarEventsById(dependencies, candidateIds);
  const exactEvents = Array.from(exactById.values()).filter((event) => event.status !== 'cancelled');
  const implicitAttendeeEmails = getImplicitAttendeeEmails(exactEvents);

  if (currentStateCalendarEventId.length > 0 && !exactById.has(currentStateCalendarEventId)) {
    const rejected = await dependencies.rejectConstraint(entry.teamMemberId, constraintId);
    const deletedConstraintEventCount = await deleteConstraintArtifacts(
      dependencies,
      constraintId,
      entry.teamMemberId,
    );
    await dependencies.firestore
      .collection(dependencies.collections.calendarSync)
      .doc(constraintId)
      .delete()
      .catch(() => undefined);
    return {
      changed: rejected || deletedConstraintEventCount > 0,
      rejected,
      createdConstraintEventCount: 0,
      updatedConstraintEventCount: 0,
      deletedConstraintEventCount,
      repairedConstraintSyncStateCount: 1,
    };
  }

  const canonicalCandidate = pickCanonicalCandidate([
    ...exactEvents,
    ...(currentStateCalendarEventId.length > 0 && exactById.has(currentStateCalendarEventId)
      ? [exactById.get(currentStateCalendarEventId)!]
      : []),
  ], currentStateCalendarEventId);
  const needsCreate = canonicalCandidate == null;
  const needsUpdate =
    canonicalCandidate != null &&
    !constraintMatchesDesired(canonicalCandidate, desired, implicitAttendeeEmails);
  let finalCalendarEventId = canonicalCandidate?.id ?? currentStateCalendarEventId;
  let createdConstraintEventCount = 0;
  let updatedConstraintEventCount = 0;
  let deletedConstraintEventCount = 0;
  let repairedConstraintSyncStateCount = 0;

  if (needsCreate || needsUpdate) {
    const result = await executeAction(
      dependencies,
      'ensureConstraintEvent',
      {
        calendarEventId: finalCalendarEventId.length > 0 ? finalCalendarEventId : undefined,
        teamMember: desired.teamMemberPayload,
        constraint: desired.constraintPayload,
        isTestMode: dependencies.environment === 'test',
      },
    );
    finalCalendarEventId = requireString(result['calendarEventId'], 'calendarEventId');
    if (needsCreate) {
      createdConstraintEventCount += 1;
    } else {
      updatedConstraintEventCount += 1;
    }
  }

  for (const exactEvent of exactEvents) {
    if (exactEvent.id === finalCalendarEventId) {
      continue;
    }
    await deleteConstraintEventById(dependencies, exactEvent.id, entry.teamMemberId);
    deletedConstraintEventCount += 1;
  }

  if (
    currentStateCalendarEventId !== finalCalendarEventId ||
    currentStateStatus !== 'synced' ||
    optionalString(syncState?.['teamMemberId']) !== entry.teamMemberId
  ) {
    await saveSyncedConstraintSyncState(
      dependencies,
      constraintId,
      entry.teamMemberId,
      finalCalendarEventId,
    );
    repairedConstraintSyncStateCount += 1;
  }

  return {
    changed:
      createdConstraintEventCount > 0 ||
      updatedConstraintEventCount > 0 ||
      deletedConstraintEventCount > 0 ||
      repairedConstraintSyncStateCount > 0,
    rejected: false,
    createdConstraintEventCount,
    updatedConstraintEventCount,
    deletedConstraintEventCount,
    repairedConstraintSyncStateCount,
  };
}

export async function syncAppEventCalendars(
  dependencies: SyncDependencies,
  options: {
    eventId?: string | null;
  } = {},
): Promise<AppEventSyncReport> {
  const failedEventIds: string[] = [];
  let scannedCount = 0;
  let changedCount = 0;
  let upToDateCount = 0;
  let createdEventPartCount = 0;
  let updatedEventPartCount = 0;
  let deletedEventPartCount = 0;
  let updatedAttendeeEventCount = 0;
  let repairedEventSyncStateCount = 0;
  let removedOrphanedCount = 0;
  let cleanedSyncStateCount = 0;

  const teamMemberCache = new Map<string, Record<string, unknown> | null>();

  if (options.eventId != null && options.eventId.trim().length > 0) {
    const eventId = options.eventId.trim();
    const eventData = await readEventById(dependencies.firestore, dependencies.collections, eventId);
    if (eventData == null) {
      return {
        scannedCount: 0,
        changedCount: 0,
        upToDateCount: 0,
        failedEventIds,
        createdEventPartCount: 0,
        updatedEventPartCount: 0,
        deletedEventPartCount: 0,
        updatedAttendeeEventCount: 0,
        repairedEventSyncStateCount: 0,
        removedOrphanedCount: 0,
        cleanedSyncStateCount: 0,
      };
    }

    const syncStateDoc = await dependencies.firestore
      .collection(dependencies.collections.eventCalendarSync)
      .doc(eventId)
      .get();

    scannedCount = 1;
    try {
      const result = await reconcileSingleAppEvent(
        dependencies,
        eventId,
        eventData,
        syncStateDoc.exists ? syncStateDoc.data() ?? null : null,
        teamMemberCache,
      );
      createdEventPartCount += result.createdEventPartCount;
      updatedEventPartCount += result.updatedEventPartCount;
      deletedEventPartCount += result.deletedEventPartCount;
      updatedAttendeeEventCount += result.updatedAttendeeEventCount;
      repairedEventSyncStateCount += result.repairedEventSyncStateCount;
      if (result.changed) {
        changedCount += 1;
      } else {
        upToDateCount += 1;
      }
    } catch (error) {
      console.error(`Failed to reconcile app event ${eventId}:`, error);
      failedEventIds.push(eventId);
    }

    return {
      scannedCount,
      changedCount,
      upToDateCount,
      failedEventIds,
      createdEventPartCount,
      updatedEventPartCount,
      deletedEventPartCount,
      updatedAttendeeEventCount,
      repairedEventSyncStateCount,
      removedOrphanedCount,
      cleanedSyncStateCount,
    };
  }

  const [eventsSnapshot, syncSnapshot] = await Promise.all([
    dependencies.firestore.collection(dependencies.collections.events).get(),
    dependencies.firestore.collection(dependencies.collections.eventCalendarSync).get(),
  ]);
  const todayKey = getIsraelDateKey(new Date());
  const inScopeEvents = eventsSnapshot.docs.filter((doc) =>
    isEventInDefaultScope(doc.data() ?? {}, todayKey),
  );

  const syncByEventId = new Map<string, Record<string, unknown>>();
  for (const doc of syncSnapshot.docs) {
    syncByEventId.set(doc.id, doc.data() ?? {});
  }

  scannedCount = inScopeEvents.length;
  for (const doc of inScopeEvents) {
    try {
      const result = await reconcileSingleAppEvent(
        dependencies,
        doc.id,
        doc.data() ?? {},
        syncByEventId.get(doc.id) ?? null,
        teamMemberCache,
      );
      createdEventPartCount += result.createdEventPartCount;
      updatedEventPartCount += result.updatedEventPartCount;
      deletedEventPartCount += result.deletedEventPartCount;
      updatedAttendeeEventCount += result.updatedAttendeeEventCount;
      repairedEventSyncStateCount += result.repairedEventSyncStateCount;
      if (result.changed) {
        changedCount += 1;
      } else {
        upToDateCount += 1;
      }
    } catch (error) {
      console.error(`Failed to reconcile app event ${doc.id}:`, error);
      failedEventIds.push(doc.id);
    }
  }

  return {
    scannedCount,
    changedCount,
    upToDateCount,
    failedEventIds,
    createdEventPartCount,
    updatedEventPartCount,
    deletedEventPartCount,
    updatedAttendeeEventCount,
    repairedEventSyncStateCount,
    removedOrphanedCount,
    cleanedSyncStateCount,
  };
}

export async function syncConstraintCalendars(
  dependencies: ConstraintDependencies,
): Promise<ConstraintSyncReport> {
  const failedConstraintIds: string[] = [];
  let scannedCount = 0;
  let changedCount = 0;
  let upToDateCount = 0;
  let rejectedConstraintCount = 0;
  let createdConstraintEventCount = 0;
  let updatedConstraintEventCount = 0;
  let deletedConstraintEventCount = 0;
  let repairedConstraintSyncStateCount = 0;
  let cleanedSyncStateCount = 0;

  const teamMembersSnapshot = await dependencies.firestore
    .collection(dependencies.collections.teamMembers)
    .get();
  const syncSnapshot = await dependencies.firestore
    .collection(dependencies.collections.calendarSync)
    .get();
  const managedEvents = await listManagedCalendarEvents(dependencies, {
    kind: 'constraint',
  });

  const desiredConstraints = new Map<string, ConstraintEntry>();
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

  scannedCount = desiredConstraints.size;
  for (const [constraintId, entry] of desiredConstraints.entries()) {
    try {
      const result = await reconcileSingleConstraint(
        dependencies,
        constraintId,
        entry,
        managedByConstraintId.get(constraintId) ?? [],
        syncByConstraintId.get(constraintId) ?? null,
      );
      createdConstraintEventCount += result.createdConstraintEventCount;
      updatedConstraintEventCount += result.updatedConstraintEventCount;
      deletedConstraintEventCount += result.deletedConstraintEventCount;
      repairedConstraintSyncStateCount += result.repairedConstraintSyncStateCount;
      if (result.rejected) {
        rejectedConstraintCount += 1;
      }
      if (result.changed) {
        changedCount += 1;
      } else {
        upToDateCount += 1;
      }
    } catch (error) {
      console.error(`Failed to reconcile constraint ${constraintId}:`, error);
      failedConstraintIds.push(constraintId);
      const syncState = syncByConstraintId.get(constraintId) ?? null;
      const retryCount = readInt(syncState?.['retryCount']) ?? 0;
      await saveFailedConstraintSyncState(
        dependencies,
        constraintId,
        entry.teamMemberId,
        error instanceof Error ? error.message : String(error),
        retryCount,
      );
    }
  }

  for (const doc of syncSnapshot.docs) {
    if (desiredConstraints.has(doc.id)) {
      continue;
    }
    const syncData = doc.data() ?? {};
    const teamMemberId = optionalString(syncData['teamMemberId']) ?? '';
    deletedConstraintEventCount += await deleteConstraintArtifacts(
      dependencies,
      doc.id,
      teamMemberId,
      optionalString(syncData['calendarEventId']),
    );
    await doc.ref.delete();
    cleanedSyncStateCount += 1;
  }

  for (const [constraintId, eventItems] of managedByConstraintId.entries()) {
    if (desiredConstraints.has(constraintId) || syncByConstraintId.has(constraintId)) {
      continue;
    }
    const teamMemberId = eventItems[0]?.teamMemberId ?? '';
    for (const managedEvent of eventItems) {
      await deleteConstraintEventById(dependencies, managedEvent.id, teamMemberId);
      deletedConstraintEventCount += 1;
    }
  }

  return {
    scannedCount,
    changedCount,
    upToDateCount,
    failedConstraintIds,
    rejectedConstraintCount,
    createdConstraintEventCount,
    updatedConstraintEventCount,
    deletedConstraintEventCount,
    repairedConstraintSyncStateCount,
    cleanedSyncStateCount,
  };
}

export async function syncEventsAndConstraints(
  dependencies: ConstraintDependencies,
): Promise<CombinedCalendarSyncReport> {
  const [appEvents, constraints] = await Promise.all([
    syncAppEventCalendars(dependencies),
    syncConstraintCalendars(dependencies),
  ]);

  return {
    appEvents,
    constraints,
    message: buildCombinedSyncMessage(appEvents, constraints),
  };
}

export async function syncAssignedEventsBestEffort(
  dependencies: SyncDependencies,
  eventIds: Iterable<string>,
): Promise<void> {
  const uniqueEventIds = uniqueSortedStrings(eventIds);
  for (const eventId of uniqueEventIds) {
    try {
      await syncAppEventCalendars(dependencies, {eventId});
    } catch (error) {
      console.error(`Failed to sync app event ${eventId}:`, error);
    }
  }
}

export async function syncAssignedFutureEventsForMemberEmailChange(
  dependencies: SyncDependencies,
  teamMemberId: string,
): Promise<void> {
  const snapshot = await dependencies.firestore
    .collection(dependencies.collections.assignments)
    .where('teamMemberId', '==', teamMemberId)
    .get();
  const eventIds = Array.from(new Set(
    snapshot.docs
      .map((doc) => {
        const data = doc.data() ?? {};
        return typeof data['eventId'] === 'string'
          ? data['eventId'] as string
          : null;
      })
      .filter((eventId): eventId is string => eventId != null),
  ));
  const todayKey = getIsraelDateKey(new Date());
  const futureEventIds: string[] = [];
  for (const eventId of eventIds) {
    const eventData = await readEventById(dependencies.firestore, dependencies.collections, eventId);
    if (eventData == null || !isEventInDefaultScope(eventData, todayKey)) {
      continue;
    }
    futureEventIds.push(eventId);
  }
  await syncAssignedEventsBestEffort(dependencies, futureEventIds);
}

export async function deleteAppEventCalendarArtifacts(
  dependencies: SyncDependencies,
  eventId: string,
): Promise<void> {
  const syncStateDoc = await dependencies.firestore
    .collection(dependencies.collections.eventCalendarSync)
    .doc(eventId)
    .get();
  const syncState = syncStateDoc.exists ? syncStateDoc.data() ?? {} : {};
  const storedIds = uniqueSortedStrings([
    optionalString(syncState['assemblyCalendarEventId']) ?? '',
    optionalString(syncState['mainCalendarEventId']) ?? '',
  ]);
  await deleteDiscoveredAppEventArtifacts(dependencies, eventId, storedIds);
}

export function buildCombinedSyncMessage(
  appEvents: AppEventSyncReport,
  constraints: ConstraintSyncReport,
): string {
  const parts = [
    `אירועים: בוצעו שינויים ב-${appEvents.changedCount} מתוך ${appEvents.scannedCount}, כבר היו תקינים ${appEvents.upToDateCount}, נכשלו ${appEvents.failedEventIds.length}.`,
    `מגבלות: בוצעו שינויים ב-${constraints.changedCount} מתוך ${constraints.scannedCount}, כבר היו תקינות ${constraints.upToDateCount}, נכשלו ${constraints.failedConstraintIds.length}.`,
  ];

  if (appEvents.removedOrphanedCount > 0) {
    parts.push(`אירועים: נמחקו ${appEvents.removedOrphanedCount} פריטי יומן יתומים.`);
  }
  if (constraints.rejectedConstraintCount > 0) {
    parts.push(`מגבלות: ${constraints.rejectedConstraintCount} מגבלות נדחו בעקבות מחיקה ביומן.`);
  }

  return `סנכרון אירועים ומגבלות הושלם. ${parts.join(' ')}`;
}
