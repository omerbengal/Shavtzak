import {
  FieldValue,
  Firestore,
  Timestamp,
} from 'firebase-admin/firestore';
import {
  buildDeterministicAppEventCalendarId,
  executeCalendarAction,
  isCalendarQuotaError,
} from './calendar_integration';

export {buildDeterministicAppEventCalendarId} from './calendar_integration';

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
  // At least one event failed specifically because Google's Calendar usage
  // limit is exhausted (403 quota). The caller should defer + retry after the
  // quota window resets rather than fast-retrying into the same wall.
  quotaExhausted: boolean;
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

export type DesiredAppEventState = {
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
  calendarAction?: (
    action: string,
    payload: Record<string, unknown>,
  ) => Promise<Record<string, unknown>>;
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
 * @deprecated App events no longer manage guests. Retained only so code built
 * against the former planner remains source-compatible during rollout.
 * A member was eligible for the "invite all permanent staff" calendar behavior
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
 * @deprecated App events no longer manage guests. No reconciler calls this.
 * The former "invite all permanent staff" substitution applied when the event opted
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

function pickCanonicalCandidate<T extends {id: string}>(
  candidates: T[],
  preferredId?: string | null,
): T | null {
  if (preferredId != null && preferredId.length > 0) {
    const preferred = candidates.find((candidate) => candidate.id === preferredId);
    if (preferred != null) {
      return preferred;
    }
  }
  const sorted = [...candidates].sort((left, right) => left.id.localeCompare(right.id));
  return sorted[0] ?? null;
}

/**
 * Minimal shape of a managed calendar event needed to plan app-event reconciliation.
 * Kept narrow so the planner stays pure and trivially testable.
 */
export type AppEventPartSummary = {
  id: string;
  eventType: string | null;
  status: string | null;
};

export type AppEventReconciliationInput = {
  /** All managed calendar events discovered for one app event (may include duplicates/orphans). */
  discovered: AppEventPartSummary[];
  currentStateAssemblyId: string;
  currentStateMainId: string;
  shouldHaveAssemblyPart: boolean;
};

export type AppEventReconciliationPlan = {
  keepMainId: string | null;
  keepAssemblyId: string | null;
  createMain: boolean;
  createAssembly: boolean;
  deleteMainIds: string[];
  deleteAssemblyIds: string[];
};

/**
 * Pure decision logic for converging an app event to exactly one main part and
 * (optionally) one assembly part, given everything currently on the calendar.
 *
 * This is the fix for duplicate Google Calendar events: previously reconciliation
 * only looked at the single stored id and blindly created a new event whenever that
 * lookup came back empty (e.g. a concurrent sync had not yet persisted its id, or a
 * transient 404), leaking the previously-created event as a permanent orphan. By
 * discovering ALL managed events for the app event and keeping one canonical part
 * per slot while deleting the rest, every sync becomes convergent/self-healing —
 * mirroring the constraint sync path.
 *
 */
export function planAppEventReconciliation(
  input: AppEventReconciliationInput,
): AppEventReconciliationPlan {
  const active = input.discovered.filter((event) => event.status !== 'cancelled');
  const assemblyEvents = active.filter((event) => event.eventType === 'assembly');
  // The main slot is anything that is not an assembly part ('main' or 'allDay').
  const mainEvents = active.filter((event) => event.eventType !== 'assembly');

  const mainCanonical = pickCanonicalCandidate(mainEvents, input.currentStateMainId);
  const keepMainId = mainCanonical?.id ?? null;
  const createMain = mainCanonical == null;
  const deleteMainIds = mainEvents
    .map((event) => event.id)
    .filter((id) => id !== keepMainId);

  let keepAssemblyId: string | null = null;
  let createAssembly = false;
  let deleteAssemblyIds: string[];
  if (input.shouldHaveAssemblyPart) {
    const assemblyCanonical = pickCanonicalCandidate(
      assemblyEvents,
      input.currentStateAssemblyId,
    );
    keepAssemblyId = assemblyCanonical?.id ?? null;
    createAssembly = assemblyCanonical == null;
    deleteAssemblyIds = assemblyEvents
      .map((event) => event.id)
      .filter((id) => id !== keepAssemblyId);
  } else {
    // No assembly part wanted: every discovered assembly event is an orphan.
    deleteAssemblyIds = assemblyEvents.map((event) => event.id);
  }

  return {
    keepMainId,
    keepAssemblyId,
    createMain,
    createAssembly,
    deleteMainIds,
    deleteAssemblyIds,
  };
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

export function appEventMatchesDesired(
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

async function executeAction(
  dependencies: SyncDependencies,
  action: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (dependencies.calendarAction != null) {
    return dependencies.calendarAction(action, payload);
  }
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

export function buildDesiredAppEventState(
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

function isExpectedManagedAppEvent(
  dependencies: SyncDependencies,
  event: ManagedCalendarEventSummary | null,
  eventId: string,
): event is ManagedCalendarEventSummary {
  return event != null &&
    event.eventId === eventId &&
    event.isTestMode === String(dependencies.environment === 'test') &&
    (event.eventType === 'assembly' ||
      event.eventType === 'main' ||
      event.eventType === 'allDay');
}

async function deleteDiscoveredAppEventArtifacts(
  dependencies: SyncDependencies,
  eventId: string,
  storedIds: string[] = [],
): Promise<number> {
  const managedEvents = await listManagedCalendarEvents(dependencies, {
    kind: 'app',
    eventId,
  });
  const seen = new Set<string>();
  let deletedCount = 0;
  for (const managedEvent of managedEvents) {
    if (!isExpectedManagedAppEvent(dependencies, managedEvent, eventId)) {
      continue;
    }
    seen.add(managedEvent.id);
    await deleteAppEventById(dependencies, managedEvent.id, managedEvent.eventType);
    deletedCount += 1;
  }
  for (const calendarEventId of uniqueSortedStrings(storedIds)) {
    if (seen.has(calendarEventId)) {
      continue;
    }
    const storedEvent = await getManagedCalendarEvent(dependencies, calendarEventId);
    if (!isExpectedManagedAppEvent(dependencies, storedEvent, eventId)) {
      continue;
    }
    await deleteAppEventById(dependencies, calendarEventId, storedEvent.eventType);
    deletedCount += 1;
  }
  return deletedCount;
}

async function createAppEventPart(
  dependencies: SyncDependencies,
  payload: Record<string, unknown>,
  eventType: 'assembly' | 'main' | 'allDay',
): Promise<string> {
  const eventId = requireString(payload['eventId'], 'event.eventId');
  const calendarEventId = buildDeterministicAppEventCalendarId(
    dependencies.environment,
    eventId,
    eventType,
  );
  const result = await executeAction(
    dependencies,
    'createAppEventCalendarEventPart',
    {
      event: payload,
      eventType,
      calendarEventId,
    },
  );
  return requireString(result['calendarEventId'], 'calendarEventId');
}

/**
 * @deprecated App events no longer manage guests. The following attendee
 * planner types/functions remain only for rollout compatibility and are not
 * used by reconciliation or mutation handlers.
 * One operation's former attendee change for a single app event: which members
 * this write added to / removed from the event. Lets the reconciler notify ONLY
 * the members whose assignment actually changed, while every other attendee
 * (drift catch-up) is converged silently.
 */
export type AttendeeNotifyDelta = {
  addedMemberIds?: readonly string[];
  removedMemberIds?: readonly string[];
};

/** Per-event notify deltas keyed by app event id. */
export type AttendeeNotifyByEvent = Record<string, AttendeeNotifyDelta>;

/**
 * Resolved notify decision for one calendar event part: the normalized emails
 * that should be emailed when added/removed, plus `notifyAll` for invite-all
 * events (where the whole permanent roster is deliberately invited/cancelled on
 * the empty<->assigned boundary — the user opted into that mass email).
 */
export type AttendeeNotifyPlan = {
  emails: Set<string>;
  notifyAll: boolean;
};

export type AttendeeSyncOp = {email: string; sendUpdates: 'all' | 'none'};

export function buildAttendeeNotifyPlan(params: {
  optedIntoInviteAll: boolean;
  triggeredByChange: boolean;
  notifyEmails: Iterable<string>;
}): AttendeeNotifyPlan {
  const emails = new Set(
    Array.from(params.notifyEmails)
      .map((email) => normalizeEmail(email))
      .filter((email) => email.length > 0),
  );
  return {
    emails,
    // Invite-all events keep emailing the whole roster — but only when a real
    // assignment change triggered this reconcile. A passive full/manual sync
    // carries no delta and stays silent.
    notifyAll: params.optedIntoInviteAll && params.triggeredByChange,
  };
}

/**
 * Deduplicate the affected event ids to non-empty ids and pair each with its
 * notify delta (empty delta = a passive sync that emails no one). One returned
 * entry becomes one calendar-sync task, so batch operations touching the same
 * event collapse into a single task carrying that event's full delta.
 */
export function planCalendarSyncTasks(
  eventIds: Iterable<string>,
  notifyByEventId: AttendeeNotifyByEvent = {},
): Array<{eventId: string; delta: AttendeeNotifyDelta}> {
  const uniqueEventIds = Array.from(new Set(
    Array.from(eventIds).filter(
      (eventId): eventId is string => typeof eventId === 'string' && eventId.length > 0,
    ),
  ));
  return uniqueEventIds.map((eventId) => ({
    eventId,
    delta: notifyByEventId[eventId] ?? {},
  }));
}

/**
 * Pure current-vs-desired attendee diff for one calendar event part, tagging
 * each add/remove with whether it should notify the affected guest. Mirrors the
 * convergence diff the reconciler applies; extracted so the notify decision is
 * unit-testable in isolation.
 */
export function planAttendeeSync(params: {
  organizerEmail: string | null;
  currentAttendeeEmails: Iterable<string>;
  desiredEmails: Iterable<string>;
  notify: AttendeeNotifyPlan;
}): {adds: AttendeeSyncOp[]; removes: AttendeeSyncOp[]} {
  const organizerList = params.organizerEmail == null ? [] : [params.organizerEmail];
  const currentAttendeeList = Array.from(params.currentAttendeeEmails);
  const currentComparableEmails = normalizeComparableAttendeeEmails([
    ...currentAttendeeList,
    ...organizerList,
  ]);
  const desiredComparableEmails = normalizeComparableAttendeeEmails(
    params.desiredEmails,
    organizerList,
  );
  const currentAttendeeEmails = normalizeComparableAttendeeEmails(
    currentAttendeeList,
    organizerList,
  );

  const decide = (email: string): 'all' | 'none' =>
    params.notify.notifyAll || params.notify.emails.has(email) ? 'all' : 'none';

  const adds: AttendeeSyncOp[] = [];
  for (const email of desiredComparableEmails) {
    if (currentComparableEmails.includes(email)) {
      continue;
    }
    adds.push({email, sendUpdates: decide(email)});
  }

  const removes: AttendeeSyncOp[] = [];
  for (const email of currentAttendeeEmails) {
    if (desiredComparableEmails.includes(email)) {
      continue;
    }
    removes.push({email, sendUpdates: decide(email)});
  }

  return {adds, removes};
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

export function shouldDeleteTargetedAppEventArtifacts(
  eventData: Record<string, unknown> | null,
  todayKey: string,
): boolean {
  return eventData == null || !isEventInDefaultScope(eventData, todayKey);
}

function shouldEventHaveAssemblyPart(desired: DesiredAppEventState): boolean {
  return desired.useAllDay === false &&
    desired.assemblyStartPrefix != null &&
    desired.assemblyEndPrefix != null;
}

export type AppEventPartDetailUpdatePlan = {
  assemblyNeedsUpdate: boolean;
  mainNeedsUpdate: boolean;
  updatedEventPartCount: number;
};

export function planAppEventPartDetailUpdates(params: {
  desired: DesiredAppEventState;
  retainedAssembly: ManagedCalendarEventSummary | null;
  retainedMain: ManagedCalendarEventSummary | null;
}): AppEventPartDetailUpdatePlan {
  const assemblyNeedsUpdate =
    params.retainedAssembly != null &&
    !appEventMatchesDesired(params.retainedAssembly, params.desired, 'assembly');
  const mainNeedsUpdate =
    params.retainedMain != null &&
    !appEventMatchesDesired(
      params.retainedMain,
      params.desired,
      params.desired.useAllDay ? 'allDay' : 'main',
    );
  return {
    assemblyNeedsUpdate,
    mainNeedsUpdate,
    updatedEventPartCount:
      (assemblyNeedsUpdate ? 1 : 0) + (mainNeedsUpdate ? 1 : 0),
  };
}

async function updateAppEventParts(
  dependencies: SyncDependencies,
  desired: DesiredAppEventState,
  assemblyCalendarEventId: string,
  mainCalendarEventId: string,
): Promise<{assemblyCalendarEventId: string; mainCalendarEventId: string}> {
  const response = await executeAction(
    dependencies,
    'updateAppEventCalendarEvents',
    {
      assemblyCalendarEventId,
      mainCalendarEventId,
      event: desired.payload,
    },
  );
  const rawRecreatedIds = response['result'];
  if (
    rawRecreatedIds == null ||
    typeof rawRecreatedIds !== 'object' ||
    Array.isArray(rawRecreatedIds)
  ) {
    return {assemblyCalendarEventId, mainCalendarEventId};
  }

  const recreatedIds = rawRecreatedIds as Record<string, unknown>;
  return {
    assemblyCalendarEventId:
      optionalString(recreatedIds['assembly']) ?? assemblyCalendarEventId,
    mainCalendarEventId:
      optionalString(recreatedIds['main']) ?? mainCalendarEventId,
  };
}

async function reconcileSingleAppEvent(
  dependencies: SyncDependencies,
  eventId: string,
  eventData: Record<string, unknown>,
  eventSyncData: Record<string, unknown> | null,
): Promise<AppEventItemResult> {
  const desired = buildDesiredAppEventState(eventId, eventData, dependencies.environment);
  const currentStateAssemblyId = optionalString(eventSyncData?.['assemblyCalendarEventId']) ?? '';
  const currentStateMainId = optionalString(eventSyncData?.['mainCalendarEventId']) ?? '';
  const currentStateStatus = optionalString(eventSyncData?.['status']) ?? '';
  const shouldHaveAssemblyPart = shouldEventHaveAssemblyPart(desired);

  // Discover EVERY managed calendar event for this app event, then merge in the stored
  // ids (in case discovery missed one). This lets reconciliation converge to a single
  // canonical main + assembly part and delete any duplicates/orphans left behind by
  // earlier concurrent syncs, instead of blindly creating a new event whenever the
  // single stored id lookup comes back empty. Mirrors the self-healing constraint path.
  const discovered = await listManagedCalendarEvents(dependencies, {kind: 'app', eventId});
  const summaryById = new Map<string, ManagedCalendarEventSummary>();
  for (const managedEvent of discovered) {
    if (!isExpectedManagedAppEvent(dependencies, managedEvent, eventId)) {
      continue;
    }
    summaryById.set(managedEvent.id, managedEvent);
  }
  for (const storedId of [currentStateAssemblyId, currentStateMainId]) {
    if (storedId.length === 0 || summaryById.has(storedId)) {
      continue;
    }
    const managedEvent = await getManagedCalendarEvent(dependencies, storedId);
    if (isExpectedManagedAppEvent(dependencies, managedEvent, eventId)) {
      summaryById.set(storedId, managedEvent);
    }
  }

  const plan = planAppEventReconciliation({
    discovered: Array.from(summaryById.values()),
    currentStateAssemblyId,
    currentStateMainId,
    shouldHaveAssemblyPart,
  });
  const detailUpdatePlan = planAppEventPartDetailUpdates({
    desired,
    retainedAssembly:
      plan.keepAssemblyId == null ? null : summaryById.get(plan.keepAssemblyId) ?? null,
    retainedMain:
      plan.keepMainId == null ? null : summaryById.get(plan.keepMainId) ?? null,
  });

  let createdEventPartCount = 0;
  const updatedEventPartCount = detailUpdatePlan.updatedEventPartCount;
  let deletedEventPartCount = 0;
  let repairedEventSyncStateCount = 0;

  // Remove duplicate/orphaned parts first so the calendar converges to one of each.
  for (const calendarEventId of plan.deleteAssemblyIds) {
    await deleteAppEventById(dependencies, calendarEventId, 'assembly');
    deletedEventPartCount += 1;
  }
  for (const calendarEventId of plan.deleteMainIds) {
    await deleteAppEventById(
      dependencies,
      calendarEventId,
      summaryById.get(calendarEventId)?.eventType ?? 'main',
    );
    deletedEventPartCount += 1;
  }

  let finalAssemblyId = '';
  if (shouldHaveAssemblyPart) {
    if (plan.keepAssemblyId != null) {
      finalAssemblyId = plan.keepAssemblyId;
    } else {
      finalAssemblyId = await createAppEventPart(dependencies, desired.payload, 'assembly');
      createdEventPartCount += 1;
    }
  }

  let finalMainId: string;
  if (plan.keepMainId != null) {
    finalMainId = plan.keepMainId;
  } else {
    finalMainId = await createAppEventPart(
      dependencies,
      desired.payload,
      desired.useAllDay ? 'allDay' : 'main',
    );
    createdEventPartCount += 1;
  }

  if (updatedEventPartCount > 0) {
    const updatedIds = await updateAppEventParts(
      dependencies,
      desired,
      finalAssemblyId,
      finalMainId,
    );
    finalAssemblyId = updatedIds.assemblyCalendarEventId;
    finalMainId = updatedIds.mainCalendarEventId;
  }

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
      updatedEventPartCount > 0 ||
      deletedEventPartCount > 0 ||
      repairedEventSyncStateCount > 0,
    createdEventPartCount,
    updatedEventPartCount,
    deletedEventPartCount,
    updatedAttendeeEventCount: 0,
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

/// Returns the ids of every event currently in the default calendar scope
/// (active + not past). Cheap — a single Firestore read, no Google API calls —
/// so the client can fetch the work list up front and drive a chunked sync
/// with real progress instead of one long serial request.
export async function listInScopeAppEventIds(
  dependencies: SyncDependencies,
): Promise<string[]> {
  const eventsSnapshot = await dependencies.firestore
    .collection(dependencies.collections.events)
    .get();
  const todayKey = getIsraelDateKey(new Date());
  return eventsSnapshot.docs
    .filter((doc) => isEventInDefaultScope(doc.data() ?? {}, todayKey))
    .map((doc) => doc.id);
}

async function cleanTargetedAppEventArtifacts(
  dependencies: SyncDependencies,
  eventId: string,
  eventSyncData: Record<string, unknown> | null,
): Promise<{deletedEventPartCount: number; cleanedSyncStateCount: number}> {
  const storedIds = uniqueSortedStrings([
    optionalString(eventSyncData?.['assemblyCalendarEventId']) ?? '',
    optionalString(eventSyncData?.['mainCalendarEventId']) ?? '',
  ]);
  const deletedEventPartCount = await deleteDiscoveredAppEventArtifacts(
    dependencies,
    eventId,
    storedIds,
  );
  if (eventSyncData != null) {
    await dependencies.firestore
      .collection(dependencies.collections.eventCalendarSync)
      .doc(eventId)
      .delete();
  }
  return {
    deletedEventPartCount,
    cleanedSyncStateCount: eventSyncData == null ? 0 : 1,
  };
}

export async function syncAppEventCalendars(
  dependencies: SyncDependencies,
  options: {
    eventId?: string | null;
    eventIds?: string[] | null;
    // Retained for compatibility with older callers. App-event reconciliation
    // no longer reads or writes attendees, so notification deltas are ignored.
    notifyByEventId?: AttendeeNotifyByEvent;
    // Retained for compatibility; ignored for the same reason.
    notifyAllChanges?: boolean;
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
  let quotaExhausted = false;

  if (options.eventId != null && options.eventId.trim().length > 0) {
    const eventId = options.eventId.trim();
    const [eventData, syncStateDoc] = await Promise.all([
      readEventById(dependencies.firestore, dependencies.collections, eventId),
      dependencies.firestore
        .collection(dependencies.collections.eventCalendarSync)
        .doc(eventId)
        .get(),
    ]);
    const eventSyncData = syncStateDoc.exists ? syncStateDoc.data() ?? {} : null;

    scannedCount = 1;
    try {
      if (shouldDeleteTargetedAppEventArtifacts(eventData, getIsraelDateKey(new Date()))) {
        const cleanup = await cleanTargetedAppEventArtifacts(
          dependencies,
          eventId,
          eventSyncData,
        );
        deletedEventPartCount += cleanup.deletedEventPartCount;
        cleanedSyncStateCount += cleanup.cleanedSyncStateCount;
      } else {
        if (eventData == null) {
          throw new Error(`Missing in-scope app event ${eventId}`);
        }
        const result = await reconcileSingleAppEvent(
          dependencies,
          eventId,
          eventData,
          eventSyncData,
        );
        createdEventPartCount += result.createdEventPartCount;
        updatedEventPartCount += result.updatedEventPartCount;
        deletedEventPartCount += result.deletedEventPartCount;
        updatedAttendeeEventCount += result.updatedAttendeeEventCount;
        repairedEventSyncStateCount += result.repairedEventSyncStateCount;
      }
      if (
        createdEventPartCount > 0 ||
        updatedEventPartCount > 0 ||
        deletedEventPartCount > 0 ||
        repairedEventSyncStateCount > 0 ||
        cleanedSyncStateCount > 0
      ) {
        changedCount += 1;
      } else {
        upToDateCount += 1;
      }
    } catch (error) {
      console.error(`Failed to reconcile app event ${eventId}:`, error);
      // A targeted durable job needs the original error so its worker can
      // distinguish quota, OAuth, transient, and terminal failures.
      throw error;
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
      quotaExhausted,
    };
  }

  // Batch path: reconcile only the given ids (one chunk of a chunked sync).
  // Each event is independent (per-event reconcile handles its own orphans),
  // so a subset can be processed safely without any cross-event cleanup.
  if (options.eventIds != null) {
    const uniqueIds = uniqueSortedStrings(options.eventIds);
    const todayKey = getIsraelDateKey(new Date());
    for (const eventId of uniqueIds) {
      const [eventData, syncStateDoc] = await Promise.all([
        readEventById(
          dependencies.firestore,
          dependencies.collections,
          eventId,
        ),
        dependencies.firestore
          .collection(dependencies.collections.eventCalendarSync)
          .doc(eventId)
          .get(),
      ]);
      const eventSyncData = syncStateDoc.exists ? syncStateDoc.data() ?? {} : null;

      scannedCount += 1;
      try {
        let itemChanged = false;
        if (shouldDeleteTargetedAppEventArtifacts(eventData, todayKey)) {
          const cleanup = await cleanTargetedAppEventArtifacts(
            dependencies,
            eventId,
            eventSyncData,
          );
          deletedEventPartCount += cleanup.deletedEventPartCount;
          cleanedSyncStateCount += cleanup.cleanedSyncStateCount;
          itemChanged =
            cleanup.deletedEventPartCount > 0 || cleanup.cleanedSyncStateCount > 0;
        } else {
          if (eventData == null) {
            throw new Error(`Missing in-scope app event ${eventId}`);
          }
          const result = await reconcileSingleAppEvent(
            dependencies,
            eventId,
            eventData,
            eventSyncData,
          );
          createdEventPartCount += result.createdEventPartCount;
          updatedEventPartCount += result.updatedEventPartCount;
          deletedEventPartCount += result.deletedEventPartCount;
          updatedAttendeeEventCount += result.updatedAttendeeEventCount;
          repairedEventSyncStateCount += result.repairedEventSyncStateCount;
          itemChanged = result.changed;
        }
        if (itemChanged) {
          changedCount += 1;
        } else {
          upToDateCount += 1;
        }
      } catch (error) {
        console.error(`Failed to reconcile app event ${eventId}:`, error);
        failedEventIds.push(eventId);
        if (isCalendarQuotaError(error)) quotaExhausted = true;
      }
      // Fail fast: once Google's usage limit is exhausted, every remaining event
      // fails the same way. Stop rather than burn the rest of the chunk (and the
      // client's 30s request timeout) on work that cannot possibly succeed —
      // grinding on produces a bogus "network error" instead of an honest one.
      if (quotaExhausted) break;
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
      quotaExhausted,
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
      if (isCalendarQuotaError(error)) quotaExhausted = true;
    }
    // Fail fast on quota exhaustion (see the batch path above).
    if (quotaExhausted) break;
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
    quotaExhausted,
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
      if (isCalendarQuotaError(error)) throw error;
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
  notifyAllChanges = false,
): Promise<CombinedCalendarSyncReport> {
  const [appEvents, constraints] = await Promise.all([
    syncAppEventCalendars(dependencies, {notifyAllChanges}),
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
  _notifyByEventId?: AttendeeNotifyByEvent,
): Promise<void> {
  const uniqueEventIds = uniqueSortedStrings(eventIds);
  for (const eventId of uniqueEventIds) {
    const startedAt = Date.now();
    console.log(`[calendar-sync] start eventId=${eventId}`);
    try {
      const report = await syncAppEventCalendars(dependencies, {eventId});
      console.log(
        `[calendar-sync] done eventId=${eventId} ms=${Date.now() - startedAt} ` +
          `changed=${report.changedCount} updatedParts=${report.updatedEventPartCount} ` +
          `createdParts=${report.createdEventPartCount} deletedParts=${report.deletedEventPartCount} ` +
          `failedEvents=${report.failedEventIds.length}`,
      );
    } catch (error) {
      console.error(`Failed to sync app event ${eventId}:`, error);
    }
  }
}

export async function syncAssignedFutureEventsForMemberEmailChange(
  _dependencies: SyncDependencies,
  _teamMemberId: string,
): Promise<void> {
  // Retained as a compatibility no-op for older callers. Member email changes
  // no longer have any app-event Calendar behavior.
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
