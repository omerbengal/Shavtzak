import {randomUUID} from 'node:crypto';
import {FieldValue, Firestore} from 'firebase-admin/firestore';

export type CalendarEnvironmentMode = 'production' | 'test';

export type CalendarActor = {
  memberId: string;
  isAdmin: boolean;
};

type CalendarConfig = {
  clientId: string | null;
  clientSecret: string | null;
  calendarId: string | null;
};

type CalendarTokenState = {
  accessToken: string | null;
  refreshToken: string | null;
  expiresAtMs: number | null;
  authenticatedUserEmail: string | null;
};

type CalendarTeamMemberPayload = {
  id: string;
  name: string;
  email: string | null;
  availableRoleKeys: string[];
};

type CalendarConstraintPayload = {
  id: string;
  startDate: Date;
  endDate: Date | null;
  note: string | null;
  constraintType: 'unavailability' | 'availability';
  startTime: string | null;
  endTime: string | null;
  repeatType: 'daily' | 'weekly' | 'monthly' | null;
  repeatDay: number | null;
  repeatEndDate: Date | null;
};

type CalendarEventPayload = {
  eventId: string;
  eventName: string;
  startDate: Date;
  endDate: Date;
  assemblyTime: string;
  separatorTime: string;
  endTime: string;
  location: string | null;
  isTestMode: boolean;
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

type GoogleApiOptions = {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  query?: Record<string, string | number | boolean | null | undefined>;
  body?: unknown;
  forceRefresh?: boolean;
};

const GOOGLE_OAUTH_SCOPE = 'https://www.googleapis.com/auth/calendar email';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_REVOKE_URL = 'https://oauth2.googleapis.com/revoke';
const GOOGLE_USERINFO_URL = 'https://www.googleapis.com/oauth2/v2/userinfo';
const GOOGLE_CALENDAR_BASE_URL = 'https://www.googleapis.com/calendar/v3';
const CALENDAR_TOKEN_DOC_ID = 'googleCalendar';
const AUTH_REQUIRED_MESSAGE = 'Not authenticated. User must sign in with Google.';
const TEST_MODE_PREFIX = 'שבצק טסטינג: ';
const TIME_ZONE = 'Asia/Jerusalem';
const ALL_DAY_REMINDER_MINUTES_BEFORE = 420;
const REFRESH_BUFFER_MS = 5 * 60 * 1000;

const CalendarEventColors = {
  unavailability: '8',
  availability: '10',
  appEvent: '7',
  testMode: '5',
} as const;

class CalendarAuthError extends Error {}

class GoogleApiError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function getKeysCollection(environment: CalendarEnvironmentMode): string {
  return environment === 'test' ? 'test_keys' : 'keys';
}

function getTokenCollection(environment: CalendarEnvironmentMode): string {
  return environment === 'test'
    ? 'test_private_google_calendar_auth'
    : 'private_google_calendar_auth';
}

function requireAdmin(actor: CalendarActor): void {
  if (!actor.isAdmin) {
    throw new Error('Admin access is required');
  }
}

function requireSelfOrAdmin(actor: CalendarActor, memberId: string): void {
  if (!actor.isAdmin && actor.memberId !== memberId) {
    throw new Error('You do not have access to this resource');
  }
}

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
  if (value == null) return null;
  if (typeof value !== 'string') {
    throw new Error('Expected string value');
  }
  return value;
}

function optionalBoolean(value: unknown): boolean | null {
  if (value == null) return null;
  if (typeof value !== 'boolean') {
    throw new Error('Expected boolean value');
  }
  return value;
}

function optionalNumber(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value !== 'number' || Number.isNaN(value)) {
    throw new Error('Expected number value');
  }
  return value;
}

function optionalStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => (typeof entry === 'string' ? entry : null))
    .filter((entry): entry is string => entry != null);
}

function parseDateOnly(value: unknown, fieldName: string): Date {
  const raw = requireString(value, fieldName);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (match == null) {
    throw new Error(`Missing or invalid ${fieldName}`);
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new Error(`Missing or invalid ${fieldName}`);
  }

  return date;
}

function formatDateOnly(date: Date): string {
  const year = date.getUTCFullYear().toString().padStart(4, '0');
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function addUtcDays(date: Date, days: number): Date {
  return new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + days),
  );
}

function combineDateAndTime(date: Date, time: string): string {
  const [hourRaw, minuteRaw] = time.split(':');
  const hour = Number(hourRaw);
  const minute = Number(minuteRaw);
  if (
    !Number.isInteger(hour) ||
    !Number.isInteger(minute) ||
    hour < 0 ||
    hour > 23 ||
    minute < 0 ||
    minute > 59
  ) {
    throw new Error(`Invalid time value: ${time}`);
  }

  return `${formatDateOnly(date)}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00`;
}

function stringifyErrorBody(body: unknown): string {
  if (typeof body === 'string') return body;
  try {
    return JSON.stringify(body);
  } catch (_) {
    return String(body);
  }
}

async function parseJsonResponse(response: Response): Promise<unknown> {
  const text = await response.text();
  if (text.length === 0) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return text;
  }
}

async function postForm(
  url: string,
  body: Record<string, string>,
): Promise<unknown> {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(body),
  });

  const payload = await parseJsonResponse(response);
  if (!response.ok) {
    throw new Error(`Google request failed (${response.status}): ${stringifyErrorBody(payload)}`);
  }

  return payload;
}

async function readCalendarConfig(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
): Promise<CalendarConfig> {
  const doc = await firestore
    .collection(getKeysCollection(environment))
    .doc('googleCalendar')
    .get();

  const data = doc.exists ? (doc.data() ?? {}) : {};
  return {
    clientId: typeof data['clientId'] === 'string' ? data['clientId'] : null,
    clientSecret:
      typeof data['clientSecret'] === 'string' ? data['clientSecret'] : null,
    calendarId:
      typeof data['calendarId'] === 'string' ? data['calendarId'] : null,
  };
}

async function readTokenState(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
): Promise<CalendarTokenState> {
  const doc = await firestore
    .collection(getTokenCollection(environment))
    .doc(CALENDAR_TOKEN_DOC_ID)
    .get();

  const data = doc.exists ? (doc.data() ?? {}) : {};
  return {
    accessToken: typeof data['accessToken'] === 'string' ? data['accessToken'] : null,
    refreshToken: typeof data['refreshToken'] === 'string' ? data['refreshToken'] : null,
    expiresAtMs: typeof data['expiresAtMs'] === 'number' ? data['expiresAtMs'] : null,
    authenticatedUserEmail:
      typeof data['authenticatedUserEmail'] === 'string'
        ? data['authenticatedUserEmail']
        : null,
  };
}

function isAuthenticatedTokenState(tokenState: CalendarTokenState): boolean {
  return (
    (tokenState.refreshToken != null && tokenState.refreshToken.length > 0) ||
    (tokenState.accessToken != null &&
      tokenState.accessToken.length > 0 &&
      tokenState.expiresAtMs != null &&
      tokenState.expiresAtMs > Date.now() + REFRESH_BUFFER_MS)
  );
}

async function fetchAuthenticatedUserEmail(accessToken: string): Promise<string | null> {
  const response = await fetch(GOOGLE_USERINFO_URL, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    return null;
  }

  const payload = await parseJsonResponse(response);
  if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
    return null;
  }

  const record = payload as Record<string, unknown>;
  return typeof record['email'] === 'string' ? record['email'] : null;
}

function invalidGrantMessage(errorBody: unknown): boolean {
  const lower = stringifyErrorBody(errorBody).toLowerCase();
  return lower.includes('invalid_grant') || lower.includes('revoked') || lower.includes('expired');
}

async function refreshAccessToken(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  refreshToken: string,
): Promise<CalendarTokenState> {
  const config = await readCalendarConfig(firestore, environment);
  if (config.clientId == null || config.clientSecret == null) {
    throw new Error('Google Calendar OAuth credentials are not configured');
  }

  let payload: unknown;
  try {
    payload = await postForm(GOOGLE_TOKEN_URL, {
      client_id: config.clientId,
      client_secret: config.clientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (invalidGrantMessage(message)) {
      await firestore
        .collection(getTokenCollection(environment))
        .doc(CALENDAR_TOKEN_DOC_ID)
        .delete()
        .catch(() => undefined);
      throw new CalendarAuthError(AUTH_REQUIRED_MESSAGE);
    }
    throw error;
  }

  const record = asRecord(payload, 'tokenRefreshPayload');
  const accessToken = requireString(record['access_token'], 'access_token');
  const expiresIn = optionalNumber(record['expires_in']) ?? 3600;

  const nextState: CalendarTokenState = {
    accessToken,
    refreshToken,
    expiresAtMs: Date.now() + expiresIn * 1000,
    authenticatedUserEmail: null,
  };

  const existing = await readTokenState(firestore, environment);
  nextState.authenticatedUserEmail = existing.authenticatedUserEmail;

  await firestore
    .collection(getTokenCollection(environment))
    .doc(CALENDAR_TOKEN_DOC_ID)
    .set(
      {
        accessToken: nextState.accessToken,
        refreshToken: nextState.refreshToken,
        expiresAtMs: nextState.expiresAtMs,
        authenticatedUserEmail: nextState.authenticatedUserEmail,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

  return nextState;
}

async function getValidAccessToken(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  forceRefresh = false,
): Promise<string> {
  const tokenState = await readTokenState(firestore, environment);
  if (
    !forceRefresh &&
    tokenState.accessToken != null &&
    tokenState.expiresAtMs != null &&
    tokenState.expiresAtMs > Date.now() + REFRESH_BUFFER_MS
  ) {
    return tokenState.accessToken;
  }

  if (tokenState.refreshToken == null || tokenState.refreshToken.length === 0) {
    if (
      !forceRefresh &&
      tokenState.accessToken != null &&
      tokenState.expiresAtMs != null &&
      tokenState.expiresAtMs > Date.now()
    ) {
      return tokenState.accessToken;
    }
    throw new CalendarAuthError(AUTH_REQUIRED_MESSAGE);
  }

  const refreshed = await refreshAccessToken(
    firestore,
    environment,
    tokenState.refreshToken,
  );
  if (refreshed.accessToken == null) {
    throw new CalendarAuthError(AUTH_REQUIRED_MESSAGE);
  }
  return refreshed.accessToken;
}

async function calendarApiRequest(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  path: string,
  options: GoogleApiOptions = {},
): Promise<unknown> {
  const config = await readCalendarConfig(firestore, environment);
  if (config.calendarId == null || config.calendarId.length === 0) {
    throw new Error('Google Calendar is not configured');
  }

  const accessToken = await getValidAccessToken(
    firestore,
    environment,
    options.forceRefresh === true,
  );

  const url = new URL(
    `${GOOGLE_CALENDAR_BASE_URL}/calendars/${encodeURIComponent(config.calendarId)}/${path}`,
  );
  for (const [key, value] of Object.entries(options.query ?? {})) {
    if (value != null) {
      url.searchParams.set(key, String(value));
    }
  }

  const response = await fetch(url, {
    method: options.method ?? 'GET',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: options.body == null ? undefined : JSON.stringify(options.body),
  });

  const payload = await parseJsonResponse(response);
  if (response.status === 401 && options.forceRefresh !== true) {
    await refreshAccessToken(
      firestore,
      environment,
      requireString((await readTokenState(firestore, environment)).refreshToken, 'refreshToken'),
    );
    return calendarApiRequest(firestore, environment, path, {
      ...options,
      forceRefresh: true,
    });
  }

  if (!response.ok) {
    throw new GoogleApiError(response.status, stringifyErrorBody(payload));
  }

  return payload;
}

function createConstraintTitle(
  memberName: string,
  constraintType: CalendarConstraintPayload['constraintType'],
  isTestMode: boolean,
): string {
  const suffix = constraintType === 'unavailability' ? 'מגבלה' : 'זמינות';
  const base = `${memberName} - ${suffix}`;
  return isTestMode ? `${TEST_MODE_PREFIX}${base}` : base;
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

function constraintColorId(
  constraintType: CalendarConstraintPayload['constraintType'],
  isTestMode: boolean,
): string {
  if (isTestMode) return CalendarEventColors.testMode;
  return constraintType === 'unavailability'
    ? CalendarEventColors.unavailability
    : CalendarEventColors.availability;
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

function buildConstraintRecurrenceRule(constraint: CalendarConstraintPayload): string | null {
  if (constraint.repeatType == null || constraint.repeatEndDate == null) {
    return null;
  }

  const until = formatRRuleUntil(constraint.repeatEndDate);
  switch (constraint.repeatType) {
    case 'daily':
      return `RRULE:FREQ=DAILY;UNTIL=${until}`;
    case 'weekly': {
      const byDay = weekdayToRRule(constraint.repeatDay);
      return byDay == null ? null : `RRULE:FREQ=WEEKLY;BYDAY=${byDay};UNTIL=${until}`;
    }
    case 'monthly': {
      if (constraint.repeatDay == null || constraint.repeatDay < 1 || constraint.repeatDay > 31) {
        return null;
      }
      return `RRULE:FREQ=MONTHLY;BYMONTHDAY=${constraint.repeatDay};UNTIL=${until}`;
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

function resolveConstraintEventStartDate(constraint: CalendarConstraintPayload): Date {
  const start = new Date(
    Date.UTC(
      constraint.startDate.getUTCFullYear(),
      constraint.startDate.getUTCMonth(),
      constraint.startDate.getUTCDate(),
    ),
  );

  if (constraint.repeatType == null || constraint.repeatEndDate == null) {
    return start;
  }

  const repeatEnd = new Date(
    Date.UTC(
      constraint.repeatEndDate.getUTCFullYear(),
      constraint.repeatEndDate.getUTCMonth(),
      constraint.repeatEndDate.getUTCDate(),
    ),
  );

  switch (constraint.repeatType) {
    case 'daily':
      return start;
    case 'weekly': {
      const day = constraint.repeatDay;
      if (day == null || day < 1 || day > 7) return start;
      const jsWeekday = start.getUTCDay() === 0 ? 7 : start.getUTCDay();
      const offset = (day - jsWeekday + 7) % 7;
      const candidate = addUtcDays(start, offset);
      return candidate.getTime() > repeatEnd.getTime() ? start : candidate;
    }
    case 'monthly': {
      const day = constraint.repeatDay;
      if (day == null || day < 1 || day > 31) return start;
      return nextMonthlyOccurrenceOnOrAfter(start, day, repeatEnd) ?? start;
    }
    default:
      return start;
  }
}

function buildConstraintEventPayload(
  teamMember: CalendarTeamMemberPayload,
  constraint: CalendarConstraintPayload,
  isTestMode: boolean,
): Record<string, unknown> {
  const eventStartDate = resolveConstraintEventStartDate(constraint);
  const recurrenceRule = buildConstraintRecurrenceRule(constraint);
  const hasTimeRange =
    constraint.startTime != null &&
    constraint.startTime.length > 0 &&
    constraint.endTime != null &&
    constraint.endTime.length > 0;
  const endBaseDate = constraint.repeatType != null
    ? eventStartDate
    : (constraint.endDate ?? constraint.startDate);

  const payload: Record<string, unknown> = {
    summary: createConstraintTitle(
      teamMember.name,
      constraint.constraintType,
      isTestMode,
    ),
    description: createConstraintDescription(constraint.note),
    recurrence: recurrenceRule != null ? [recurrenceRule] : null,
    reminders: {
      useDefault: false,
      overrides: [],
    },
    attendees:
      teamMember.email != null && teamMember.email.trim().length > 0
        ? [{email: teamMember.email.trim()}]
        : null,
    colorId: constraintColorId(constraint.constraintType, isTestMode),
    extendedProperties: {
      private: {
        constraintId: constraint.id,
        teamMemberId: teamMember.id,
        constraintType: constraint.constraintType,
        repeatType: constraint.repeatType ?? '',
        repeatDay: constraint.repeatDay?.toString() ?? '',
        repeatEndDate:
          constraint.repeatEndDate != null ? formatDateOnly(constraint.repeatEndDate) : '',
        isTestMode: String(isTestMode),
      },
    },
  };

  if (hasTimeRange) {
    payload['start'] = {
      dateTime: combineDateAndTime(eventStartDate, constraint.startTime!),
      timeZone: TIME_ZONE,
    };
    payload['end'] = {
      dateTime: combineDateAndTime(endBaseDate, constraint.endTime!),
      timeZone: TIME_ZONE,
    };
  } else {
    payload['start'] = {
      date: formatDateOnly(eventStartDate),
    };
    payload['end'] = {
      date: formatDateOnly(addUtcDays(endBaseDate, 1)),
    };
  }

  return payload;
}

function createEventMainTitle(eventName: string, isTestMode: boolean): string {
  return isTestMode ? `${TEST_MODE_PREFIX}${eventName}` : eventName;
}

function createEventAssemblyTitle(eventName: string, isTestMode: boolean): string {
  const title = `${eventName} - התייצבות והכנות`;
  return isTestMode ? `${TEST_MODE_PREFIX}${title}` : title;
}

function appEventColorId(isTestMode: boolean): string {
  return isTestMode ? CalendarEventColors.testMode : CalendarEventColors.appEvent;
}

function allDayReminders(): Record<string, unknown> {
  return {
    useDefault: false,
    overrides: [
      {
        method: 'popup',
        minutes: ALL_DAY_REMINDER_MINUTES_BEFORE,
      },
    ],
  };
}

function buildAssemblyEventPayload(payload: CalendarEventPayload): Record<string, unknown> {
  return {
    summary: createEventAssemblyTitle(payload.eventName, payload.isTestMode),
    description: null,
    start: {
      dateTime: combineDateAndTime(payload.startDate, payload.assemblyTime),
      timeZone: TIME_ZONE,
    },
    end: {
      dateTime: combineDateAndTime(payload.startDate, payload.separatorTime),
      timeZone: TIME_ZONE,
    },
    location: payload.location,
    colorId: appEventColorId(payload.isTestMode),
    extendedProperties: {
      private: {
        eventId: payload.eventId,
        eventType: 'assembly',
        isTestMode: String(payload.isTestMode),
      },
    },
  };
}

function buildMainEventPayload(payload: CalendarEventPayload): Record<string, unknown> {
  const mainStartTime =
    payload.separatorTime.length > 0 ? payload.separatorTime : payload.assemblyTime;

  return {
    summary: createEventMainTitle(payload.eventName, payload.isTestMode),
    description: null,
    start: {
      dateTime: combineDateAndTime(payload.startDate, mainStartTime),
      timeZone: TIME_ZONE,
    },
    end: {
      dateTime: combineDateAndTime(payload.endDate, payload.endTime),
      timeZone: TIME_ZONE,
    },
    location: payload.location,
    colorId: appEventColorId(payload.isTestMode),
    extendedProperties: {
      private: {
        eventId: payload.eventId,
        eventType: 'main',
        isTestMode: String(payload.isTestMode),
      },
    },
  };
}

function buildAllDayEventPayload(payload: CalendarEventPayload): Record<string, unknown> {
  return {
    summary: createEventMainTitle(payload.eventName, payload.isTestMode),
    description: null,
    start: {
      date: formatDateOnly(payload.startDate),
    },
    end: {
      date: formatDateOnly(addUtcDays(payload.endDate, 1)),
    },
    reminders: allDayReminders(),
    location: payload.location,
    colorId: appEventColorId(payload.isTestMode),
    extendedProperties: {
      private: {
        eventId: payload.eventId,
        eventType: 'allDay',
        isTestMode: String(payload.isTestMode),
      },
    },
  };
}

function parseTeamMemberPayload(value: unknown): CalendarTeamMemberPayload {
  const record = asRecord(value, 'teamMember');
  const availableRoleKeys = Array.isArray(record['availableRoleKeys'])
    ? record['availableRoleKeys'].map((entry) => String(entry))
    : [];

  return {
    id: requireString(record['id'], 'teamMember.id'),
    name: requireString(record['name'], 'teamMember.name'),
    email: optionalString(record['email']),
    availableRoleKeys,
  };
}

function parseConstraintPayload(value: unknown): CalendarConstraintPayload {
  const record = asRecord(value, 'constraint');
  const constraintType = requireString(record['constraintType'], 'constraint.constraintType');
  const repeatTypeRaw = optionalString(record['repeatType']);

  if (constraintType !== 'unavailability' && constraintType !== 'availability') {
    throw new Error('Missing or invalid constraint.constraintType');
  }
  if (
    repeatTypeRaw != null &&
    repeatTypeRaw !== 'daily' &&
    repeatTypeRaw !== 'weekly' &&
    repeatTypeRaw !== 'monthly'
  ) {
    throw new Error('Missing or invalid constraint.repeatType');
  }

  return {
    id: requireString(record['id'], 'constraint.id'),
    startDate: parseDateOnly(record['startDate'], 'constraint.startDate'),
    endDate: record['endDate'] == null ? null : parseDateOnly(record['endDate'], 'constraint.endDate'),
    note: optionalString(record['note']),
    constraintType,
    startTime: optionalString(record['startTime']),
    endTime: optionalString(record['endTime']),
    repeatType: repeatTypeRaw,
    repeatDay: optionalNumber(record['repeatDay']),
    repeatEndDate:
      record['repeatEndDate'] == null
        ? null
        : parseDateOnly(record['repeatEndDate'], 'constraint.repeatEndDate'),
  };
}

function parseCalendarEventPayload(value: unknown): CalendarEventPayload {
  const record = asRecord(value, 'event');
  return {
    eventId: requireString(record['eventId'], 'event.eventId'),
    eventName: requireString(record['eventName'], 'event.eventName'),
    startDate: parseDateOnly(record['startDate'], 'event.startDate'),
    endDate: parseDateOnly(record['endDate'], 'event.endDate'),
    assemblyTime: optionalString(record['assemblyTime']) ?? '',
    separatorTime: optionalString(record['separatorTime']) ?? '',
    endTime: optionalString(record['endTime']) ?? '',
    location: optionalString(record['location']),
    isTestMode: optionalBoolean(record['isTestMode']) ?? false,
  };
}

async function createCalendarEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  eventPayload: Record<string, unknown>,
  query: Record<string, string | number | boolean | null | undefined> = {},
): Promise<string> {
  const created = asRecord(
    await calendarApiRequest(firestore, environment, 'events', {
      method: 'POST',
      query,
      body: eventPayload,
    }),
    'createdCalendarEvent',
  );
  return requireString(created['id'], 'createdEvent.id');
}

async function updateCalendarEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string,
  eventPayload: Record<string, unknown>,
  query: Record<string, string | number | boolean | null | undefined> = {},
): Promise<void> {
  await calendarApiRequest(
    firestore,
    environment,
    `events/${encodeURIComponent(calendarEventId)}`,
    {
      method: 'PUT',
      query,
      body: eventPayload,
    },
  );
}

async function deleteCalendarEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string,
): Promise<void> {
  try {
    await calendarApiRequest(
      firestore,
      environment,
      `events/${encodeURIComponent(calendarEventId)}`,
      {
        method: 'DELETE',
      },
    );
  } catch (error) {
    if (error instanceof GoogleApiError && (error.status === 404 || error.status === 410)) {
      return;
    }
    throw error;
  }
}

async function getCalendarEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string,
): Promise<Record<string, unknown>> {
  return asRecord(
    await calendarApiRequest(
      firestore,
      environment,
      `events/${encodeURIComponent(calendarEventId)}`,
      {
        method: 'GET',
      },
    ),
    'calendarEvent',
  );
}

// Attendee actions notify guests by default (`'all'`) so a deliberate,
// single-member invite/cancellation still emails that member. The background
// reconciler passes `'none'` for convergence writes so re-adding drifted
// attendees never re-emails the roster. Anything other than the literal
// `'none'` falls back to `'all'`.
function parseSendUpdates(value: unknown): 'all' | 'none' {
  return value === 'none' ? 'none' : 'all';
}

async function patchCalendarEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string,
  eventPayload: Record<string, unknown>,
  options: {
    sendUpdates?: 'all' | 'none';
  } = {},
): Promise<void> {
  await calendarApiRequest(
    firestore,
    environment,
    `events/${encodeURIComponent(calendarEventId)}`,
    {
      method: 'PATCH',
      query: {
        conferenceDataVersion: 1,
        sendUpdates: options.sendUpdates ?? 'none',
      },
      body: eventPayload,
    },
  );
}

async function createConstraintEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  teamMember: CalendarTeamMemberPayload,
  constraint: CalendarConstraintPayload,
  isTestMode: boolean,
): Promise<string> {
  return createCalendarEvent(
    firestore,
    environment,
    buildConstraintEventPayload(teamMember, constraint, isTestMode),
    {sendUpdates: 'none'},
  );
}

async function updateConstraintEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string,
  teamMember: CalendarTeamMemberPayload,
  constraint: CalendarConstraintPayload,
  isTestMode: boolean,
): Promise<void> {
  await updateCalendarEvent(
    firestore,
    environment,
    calendarEventId,
    buildConstraintEventPayload(teamMember, constraint, isTestMode),
    {sendUpdates: 'none'},
  );
}

async function createAppEventCalendarEvents(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  payload: CalendarEventPayload,
): Promise<Record<string, string>> {
  const result: Record<string, string> = {};
  const isAllDayEvent = payload.assemblyTime.length === 0 || payload.endTime.length === 0;

  if (isAllDayEvent) {
    result['main'] = await createCalendarEvent(
      firestore,
      environment,
      buildAllDayEventPayload(payload),
    );
    return result;
  }

  if (payload.assemblyTime.length > 0 && payload.separatorTime.length > 0) {
    result['assembly'] = await createCalendarEvent(
      firestore,
      environment,
      buildAssemblyEventPayload(payload),
    );
  }

  result['main'] = await createCalendarEvent(
    firestore,
    environment,
    buildMainEventPayload(payload),
  );
  return result;
}

async function createAppEventCalendarEventPart(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  payload: CalendarEventPayload,
  eventType: 'assembly' | 'main' | 'allDay',
): Promise<string> {
  switch (eventType) {
    case 'assembly':
      return await createCalendarEvent(
        firestore,
        environment,
        buildAssemblyEventPayload(payload),
      );
    case 'main':
      return await createCalendarEvent(
        firestore,
        environment,
        buildMainEventPayload(payload),
      );
    case 'allDay':
      return await createCalendarEvent(
        firestore,
        environment,
        buildAllDayEventPayload(payload),
      );
    default:
      throw new Error(`Unsupported app event part type: ${String(eventType)}`);
  }
}

async function updateAppEventCalendarEvents(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  assemblyCalendarEventId: string,
  mainCalendarEventId: string,
  payload: CalendarEventPayload,
): Promise<Record<string, string> | null> {
  // Event-detail edits push with Google's DEFAULT sendUpdates, which notifies
  // attendees ("event updated"). Logged so those emails can be attributed to an
  // event edit rather than an assignment change.
  console.log(
    `[calendar-sync] eventDetails push eventId=${payload.eventId} ` +
      `assembly=${assemblyCalendarEventId || '-'} main=${mainCalendarEventId || '-'} ` +
      '(default sendUpdates → notifies attendees)',
  );
  let recreatedIds: Record<string, string> | null = null;
  let needsAssemblyRecreation = false;
  let needsMainRecreation = false;
  const isAllDayEvent = payload.assemblyTime.length === 0 || payload.endTime.length === 0;

  if (isAllDayEvent) {
    if (assemblyCalendarEventId.length > 0) {
      await deleteCalendarEvent(firestore, environment, assemblyCalendarEventId);
      recreatedIds = recreatedIds ?? {};
      recreatedIds['assembly'] = '';
    }

    if (mainCalendarEventId.length > 0) {
      try {
        await updateCalendarEvent(
          firestore,
          environment,
          mainCalendarEventId,
          buildAllDayEventPayload(payload),
        );
      } catch (error) {
        if (error instanceof GoogleApiError && (error.status === 404 || error.status === 410)) {
          needsMainRecreation = true;
        } else {
          throw error;
        }
      }
    } else {
      needsMainRecreation = true;
    }

    if (needsMainRecreation) {
      const createdId = await createCalendarEvent(
        firestore,
        environment,
        buildAllDayEventPayload(payload),
      );
      recreatedIds = recreatedIds ?? {};
      recreatedIds['main'] = createdId;
      recreatedIds['assembly'] = '';
    }

    return recreatedIds;
  }

  const shouldHaveAssembly = payload.assemblyTime.length > 0 && payload.separatorTime.length > 0;
  const shouldHaveMain = payload.endTime.length > 0 &&
    (payload.separatorTime.length > 0 || payload.assemblyTime.length > 0);

  if (shouldHaveAssembly) {
    if (assemblyCalendarEventId.length === 0) {
      needsAssemblyRecreation = true;
    } else {
      try {
        await updateCalendarEvent(
          firestore,
          environment,
          assemblyCalendarEventId,
          buildAssemblyEventPayload(payload),
        );
      } catch (error) {
        if (error instanceof GoogleApiError && (error.status === 404 || error.status === 410)) {
          needsAssemblyRecreation = true;
        } else {
          throw error;
        }
      }
    }
  }

  if (shouldHaveMain) {
    if (mainCalendarEventId.length === 0) {
      needsMainRecreation = true;
    } else {
      try {
        await updateCalendarEvent(
          firestore,
          environment,
          mainCalendarEventId,
          buildMainEventPayload(payload),
        );
      } catch (error) {
        if (error instanceof GoogleApiError && (error.status === 404 || error.status === 410)) {
          needsMainRecreation = true;
        } else {
          throw error;
        }
      }
    }
  }

  if (needsAssemblyRecreation || needsMainRecreation) {
    recreatedIds = {};
    if (needsAssemblyRecreation) {
      recreatedIds['assembly'] = await createCalendarEvent(
        firestore,
        environment,
        buildAssemblyEventPayload(payload),
      );
    }
    if (needsMainRecreation) {
      recreatedIds['main'] = await createCalendarEvent(
        firestore,
        environment,
        buildMainEventPayload(payload),
      );
    }
  }

  return recreatedIds;
}

async function addAttendeeToEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string,
  email: string,
  sendUpdates: 'all' | 'none' = 'all',
): Promise<void> {
  try {
    const event = await getCalendarEvent(firestore, environment, calendarEventId);
    const currentAttendees = Array.isArray(event['attendees'])
      ? event['attendees'].map((entry) => asRecord(entry, 'attendee'))
      : [];
    const alreadyHasAttendee = currentAttendees.some((attendee) => attendee['email'] === email);
    if (alreadyHasAttendee) {
      return;
    }

    await patchCalendarEvent(firestore, environment, calendarEventId, {
      attendees: [
        ...currentAttendees,
        {email},
      ],
    }, {
      sendUpdates,
    });
  } catch (error) {
    if (error instanceof GoogleApiError && (error.status === 404 || error.status === 410)) {
      return;
    }
    throw error;
  }
}

async function removeAttendeeFromEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string,
  email: string,
  sendUpdates: 'all' | 'none' = 'all',
): Promise<void> {
  try {
    const event = await getCalendarEvent(firestore, environment, calendarEventId);
    const currentAttendees = Array.isArray(event['attendees'])
      ? event['attendees'].map((entry) => asRecord(entry, 'attendee'))
      : [];
    const nextAttendees = currentAttendees.filter((attendee) => attendee['email'] !== email);
    if (nextAttendees.length === currentAttendees.length) {
      return;
    }

    await patchCalendarEvent(firestore, environment, calendarEventId, {
      attendees: nextAttendees.length > 0 ? nextAttendees : null,
    }, {
      sendUpdates,
    });
  } catch (error) {
    if (error instanceof GoogleApiError && (error.status === 404 || error.status === 410)) {
      return;
    }
    throw error;
  }
}

async function updateEventAttendees(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string,
  emails: string[],
  sendUpdates: 'all' | 'none' = 'all',
): Promise<void> {
  try {
    await patchCalendarEvent(firestore, environment, calendarEventId, {
      attendees: emails.length > 0 ? emails.map((email) => ({email})) : null,
    }, {
      sendUpdates,
    });
  } catch (error) {
    if (error instanceof GoogleApiError && (error.status === 404 || error.status === 410)) {
      return;
    }
    throw error;
  }
}

function parseManagedCalendarEvent(
  value: unknown,
  options: {
    requireIdentity?: boolean;
  } = {},
): ManagedCalendarEventSummary | null {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }

  const record = value as Record<string, unknown>;
  const id = optionalString(record['id']);
  if (id == null || id.length === 0) {
    return null;
  }

  const extendedProperties = asRecord(
    record['extendedProperties'] ?? {},
    'managedCalendarEvent.extendedProperties',
  );
  const privateProps = asRecord(
    extendedProperties['private'] ?? {},
    'managedCalendarEvent.extendedProperties.private',
  );

  const eventId = optionalString(privateProps['eventId']);
  const constraintId = optionalString(privateProps['constraintId']);
  if (
    options.requireIdentity !== false &&
    (eventId == null || eventId.length === 0) &&
    (constraintId == null || constraintId.length === 0)
  ) {
    return null;
  }

  const attendeesRaw = Array.isArray(record['attendees'])
    ? record['attendees'].map((entry) => asRecord(entry, 'calendarEvent.attendee'))
    : [];
  const attendeeEmails = attendeesRaw
    .map((entry) => optionalString(entry['email']))
    .filter((email): email is string => email != null && email.trim().length > 0)
    .map((email) => email.trim());
  const organizer = asRecord(record['organizer'] ?? {}, 'managedCalendarEvent.organizer');
  const start = asRecord(record['start'] ?? {}, 'managedCalendarEvent.start');
  const end = asRecord(record['end'] ?? {}, 'managedCalendarEvent.end');

  return {
    id,
    status: optionalString(record['status']),
    summary: optionalString(record['summary']),
    description: optionalString(record['description']),
    organizerEmail: optionalString(organizer['email']),
    location: optionalString(record['location']),
    colorId: optionalString(record['colorId']),
    startDate: optionalString(start['date']),
    startDateTime: optionalString(start['dateTime']),
    endDate: optionalString(end['date']),
    endDateTime: optionalString(end['dateTime']),
    recurrence: optionalStringArray(record['recurrence']),
    attendeeEmails,
    attendeesKnown: Array.isArray(record['attendees']) || record['attendeesOmitted'] !== true,
    eventId,
    eventType: optionalString(privateProps['eventType']),
    constraintId,
    teamMemberId: optionalString(privateProps['teamMemberId']),
    constraintType: optionalString(privateProps['constraintType']),
    repeatType: optionalString(privateProps['repeatType']),
    repeatDay: optionalString(privateProps['repeatDay']),
    repeatEndDate: optionalString(privateProps['repeatEndDate']),
    isTestMode: optionalString(privateProps['isTestMode']),
  };
}

async function listManagedCalendarEvents(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  filters: {
    kind?: 'app' | 'constraint';
    eventId?: string | null;
    constraintId?: string | null;
  } = {},
): Promise<ManagedCalendarEventSummary[]> {
  const events: ManagedCalendarEventSummary[] = [];
  let pageToken: string | null = null;

  do {
    const query: Record<string, string | number | boolean | null | undefined> = {
      maxResults: 2500,
      singleEvents: false,
      showDeleted: false,
      pageToken,
    };

    if (filters.eventId != null && filters.eventId.length > 0) {
      query['privateExtendedProperty'] = `eventId=${filters.eventId}`;
    } else if (filters.constraintId != null && filters.constraintId.length > 0) {
      query['privateExtendedProperty'] = `constraintId=${filters.constraintId}`;
    } else {
      query['privateExtendedProperty'] = `isTestMode=${environment === 'test'}`;
    }

    const payload = asRecord(
      await calendarApiRequest(firestore, environment, 'events', {
        method: 'GET',
        query,
      }),
      'managedCalendarEventsResponse',
    );

    const items = Array.isArray(payload['items']) ? payload['items'] : [];
    for (const item of items) {
      const parsed = parseManagedCalendarEvent(item, {
        requireIdentity: true,
      });
      if (parsed == null) {
        continue;
      }

      if (filters.kind === 'app' && (parsed.eventId == null || parsed.eventId.length === 0)) {
        continue;
      }
      if (
        filters.kind === 'constraint' &&
        (parsed.constraintId == null || parsed.constraintId.length === 0)
      ) {
        continue;
      }

      events.push(parsed);
    }

    pageToken = optionalString(payload['nextPageToken']);
  } while (pageToken != null && pageToken.length > 0);

  return events;
}

async function getManagedCalendarEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string,
): Promise<ManagedCalendarEventSummary | null> {
  try {
    const event = await getCalendarEvent(firestore, environment, calendarEventId);
    return parseManagedCalendarEvent(event, {
      requireIdentity: false,
    });
  } catch (error) {
    if (error instanceof GoogleApiError && (error.status === 404 || error.status === 410)) {
      return null;
    }
    throw error;
  }
}

async function ensureConstraintEvent(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  calendarEventId: string | null,
  teamMember: CalendarTeamMemberPayload,
  constraint: CalendarConstraintPayload,
  isTestMode: boolean,
): Promise<{calendarEventId: string; recreated: boolean}> {
  if (calendarEventId != null && calendarEventId.length > 0) {
    try {
      await updateConstraintEvent(
        firestore,
        environment,
        calendarEventId,
        teamMember,
        constraint,
        isTestMode,
      );
      return {
        calendarEventId,
        recreated: false,
      };
    } catch (error) {
      if (!(error instanceof GoogleApiError) || (error.status !== 404 && error.status !== 410)) {
        throw error;
      }
    }
  }

  const createdId = await createConstraintEvent(
    firestore,
    environment,
    teamMember,
    constraint,
    isTestMode,
  );
  return {
    calendarEventId: createdId,
    recreated: true,
  };
}

export async function getCalendarConfigForClient(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
): Promise<Record<string, unknown>> {
  const config = await readCalendarConfig(firestore, environment);
  return {
    configured: config.calendarId != null && config.calendarId.length > 0,
    calendarId: config.calendarId,
  };
}

export async function getCalendarStatusForClient(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
): Promise<Record<string, unknown>> {
  const [config, tokenState] = await Promise.all([
    readCalendarConfig(firestore, environment),
    readTokenState(firestore, environment),
  ]);

  return {
    configured: config.calendarId != null && config.calendarId.length > 0,
    calendarId: config.calendarId,
    isAuthenticated: isAuthenticatedTokenState(tokenState),
    authenticatedUserEmail: tokenState.authenticatedUserEmail,
  };
}

export async function createCalendarAuthUrl(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  redirectUri: string,
): Promise<Record<string, unknown>> {
  const config = await readCalendarConfig(firestore, environment);
  if (config.clientId == null || config.clientSecret == null) {
    throw new Error('Google Calendar OAuth credentials are not configured');
  }

  const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  url.searchParams.set('client_id', config.clientId);
  url.searchParams.set('redirect_uri', redirectUri);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('scope', GOOGLE_OAUTH_SCOPE);
  url.searchParams.set('access_type', 'offline');
  url.searchParams.set('prompt', 'consent');
  url.searchParams.set('state', `calendar_oauth_${randomUUID()}`);

  return {authUrl: url.toString()};
}

export async function exchangeCalendarAuthCode(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
  code: string,
  redirectUri: string,
  actor: CalendarActor,
): Promise<Record<string, unknown>> {
  const config = await readCalendarConfig(firestore, environment);
  if (config.clientId == null || config.clientSecret == null) {
    throw new Error('Google Calendar OAuth credentials are not configured');
  }

  const previousState = await readTokenState(firestore, environment);
  const payload = asRecord(
    await postForm(GOOGLE_TOKEN_URL, {
      code,
      client_id: config.clientId,
      client_secret: config.clientSecret,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code',
    }),
    'tokenExchangePayload',
  );

  const accessToken = requireString(payload['access_token'], 'access_token');
  const refreshToken = optionalString(payload['refresh_token']) ?? previousState.refreshToken;
  if (refreshToken == null || refreshToken.length === 0) {
    throw new Error('Google did not return a refresh token');
  }

  const expiresIn = optionalNumber(payload['expires_in']) ?? 3600;
  const authenticatedUserEmail = await fetchAuthenticatedUserEmail(accessToken);

  await firestore
    .collection(getTokenCollection(environment))
    .doc(CALENDAR_TOKEN_DOC_ID)
    .set({
      accessToken,
      refreshToken,
      expiresAtMs: Date.now() + expiresIn * 1000,
      authenticatedUserEmail,
      authorizedByMemberId: actor.memberId,
      updatedAt: FieldValue.serverTimestamp(),
    });

  return {
    ok: true,
    authenticatedUserEmail,
  };
}

export async function disconnectCalendarAuth(
  firestore: Firestore,
  environment: CalendarEnvironmentMode,
): Promise<Record<string, unknown>> {
  const tokenState = await readTokenState(firestore, environment);
  if (tokenState.refreshToken != null && tokenState.refreshToken.length > 0) {
    await fetch(GOOGLE_REVOKE_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({token: tokenState.refreshToken}),
    }).catch(() => undefined);
  }

  await firestore
    .collection(getTokenCollection(environment))
    .doc(CALENDAR_TOKEN_DOC_ID)
    .delete()
    .catch(() => undefined);

  return {ok: true};
}

export async function executeCalendarAction(
  firestore: Firestore,
  actor: CalendarActor,
  environment: CalendarEnvironmentMode,
  action: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  switch (action) {
    case 'createConstraintEvent': {
      const teamMember = parseTeamMemberPayload(payload['teamMember']);
      requireSelfOrAdmin(actor, teamMember.id);
      const constraint = parseConstraintPayload(payload['constraint']);
      const isTestMode = optionalBoolean(payload['isTestMode']) ?? false;
      const calendarEventId = await createConstraintEvent(
        firestore,
        environment,
        teamMember,
        constraint,
        isTestMode,
      );
      return {calendarEventId};
    }

    case 'updateConstraintEvent': {
      const teamMember = parseTeamMemberPayload(payload['teamMember']);
      requireSelfOrAdmin(actor, teamMember.id);
      const constraint = parseConstraintPayload(payload['constraint']);
      const calendarEventId = requireString(payload['calendarEventId'], 'calendarEventId');
      const isTestMode = optionalBoolean(payload['isTestMode']) ?? false;
      await updateConstraintEvent(
        firestore,
        environment,
        calendarEventId,
        teamMember,
        constraint,
        isTestMode,
      );
      return {ok: true};
    }

    case 'ensureConstraintEvent': {
      requireAdmin(actor);
      const teamMember = parseTeamMemberPayload(payload['teamMember']);
      const constraint = parseConstraintPayload(payload['constraint']);
      const result = await ensureConstraintEvent(
        firestore,
        environment,
        optionalString(payload['calendarEventId']),
        teamMember,
        constraint,
        optionalBoolean(payload['isTestMode']) ?? false,
      );
      return result;
    }

    case 'deleteConstraintEvent': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      const calendarEventId = requireString(payload['calendarEventId'], 'calendarEventId');
      await deleteCalendarEvent(firestore, environment, calendarEventId);
      return {ok: true};
    }

    case 'eventExists': {
      const calendarEventId = requireString(payload['calendarEventId'], 'calendarEventId');
      try {
        const event = await getCalendarEvent(firestore, environment, calendarEventId);
        return {exists: event['status'] !== 'cancelled'};
      } catch (error) {
        if (error instanceof GoogleApiError && (error.status === 404 || error.status === 410)) {
          return {exists: false};
        }
        throw error;
      }
    }

    case 'createAppEventCalendarEvents': {
      requireAdmin(actor);
      const event = parseCalendarEventPayload(payload['event']);
      const result = await createAppEventCalendarEvents(firestore, environment, event);
      return {result};
    }

    case 'createAppEventCalendarEventPart': {
      requireAdmin(actor);
      const event = parseCalendarEventPayload(payload['event']);
      const eventTypeRaw = requireString(payload['eventType'], 'eventType');
      if (eventTypeRaw !== 'assembly' && eventTypeRaw !== 'main' && eventTypeRaw !== 'allDay') {
        throw new Error(`Unsupported app event part type: ${eventTypeRaw}`);
      }
      const calendarEventId = await createAppEventCalendarEventPart(
        firestore,
        environment,
        event,
        eventTypeRaw,
      );
      return {calendarEventId};
    }

    case 'updateAppEventCalendarEvents': {
      requireAdmin(actor);
      const event = parseCalendarEventPayload(payload['event']);
      const result = await updateAppEventCalendarEvents(
        firestore,
        environment,
        optionalString(payload['assemblyCalendarEventId']) ?? '',
        optionalString(payload['mainCalendarEventId']) ?? '',
        event,
      );
      return {result};
    }

    case 'deleteAppEventCalendarEvents': {
      requireAdmin(actor);
      const assemblyCalendarEventId = optionalString(payload['assemblyCalendarEventId']);
      const mainCalendarEventId = optionalString(payload['mainCalendarEventId']);
      if (assemblyCalendarEventId != null && assemblyCalendarEventId.length > 0) {
        await deleteCalendarEvent(firestore, environment, assemblyCalendarEventId);
      }
      if (mainCalendarEventId != null && mainCalendarEventId.length > 0) {
        await deleteCalendarEvent(firestore, environment, mainCalendarEventId);
      }
      return {ok: true};
    }

    case 'addAttendeeToEvent': {
      requireAdmin(actor);
      await addAttendeeToEvent(
        firestore,
        environment,
        requireString(payload['calendarEventId'], 'calendarEventId'),
        requireString(payload['email'], 'email'),
        parseSendUpdates(payload['sendUpdates']),
      );
      return {ok: true};
    }

    case 'removeAttendeeFromEvent': {
      requireAdmin(actor);
      await removeAttendeeFromEvent(
        firestore,
        environment,
        requireString(payload['calendarEventId'], 'calendarEventId'),
        requireString(payload['email'], 'email'),
        parseSendUpdates(payload['sendUpdates']),
      );
      return {ok: true};
    }

    case 'updateEventAttendees': {
      requireAdmin(actor);
      const emails = Array.isArray(payload['emails'])
        ? payload['emails'].map((entry) => String(entry))
        : [];
      await updateEventAttendees(
        firestore,
        environment,
        requireString(payload['calendarEventId'], 'calendarEventId'),
        emails,
        parseSendUpdates(payload['sendUpdates']),
      );
      return {ok: true};
    }

    case 'listEvents': {
      requireAdmin(actor);
      const payloadResponse = await calendarApiRequest(firestore, environment, 'events', {
        method: 'GET',
        query: {
          singleEvents: true,
          orderBy: 'startTime',
        },
      });
      return {events: payloadResponse};
    }

    case 'listManagedCalendarEvents': {
      requireAdmin(actor);
      const kindRaw = optionalString(payload['kind']);
      const kind =
        kindRaw === 'app' || kindRaw === 'constraint'
          ? kindRaw
          : undefined;
      const events = await listManagedCalendarEvents(
        firestore,
        environment,
        {
          kind,
          eventId: optionalString(payload['eventId']),
          constraintId: optionalString(payload['constraintId']),
        },
      );
      return {events};
    }

    case 'getManagedCalendarEvent': {
      requireAdmin(actor);
      const event = await getManagedCalendarEvent(
        firestore,
        environment,
        requireString(payload['calendarEventId'], 'calendarEventId'),
      );
      return {event};
    }

    default:
      throw new Error(`Unsupported calendar action: ${action}`);
  }
}
