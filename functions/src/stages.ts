import {Timestamp} from 'firebase-admin/firestore';

import {TaskActor, TaskError} from './tasks';

/**
 * Pure stage rules for the דו יומי task screen.
 *
 * A stage is one block of an event (arrival, a session, dinner): it has a day
 * of the event, an optional time or time range, hotel details and contacts,
 * and tasks live under it. Like `tasks.ts`, nothing here touches Firestore:
 * `index.ts` reads the event, works out its days with [eventLocalDays] and
 * passes them in.
 */

export type StageContact = {
  id: string;
  name: string;
  phone: string;
  role: string;
};

export type StageDoc = {
  id: string;
  eventId: string;
  title: string;
  /** The Israel-local day, `yyyy-MM-dd`. */
  date: string;
  startTime: string | null;
  endTime: string | null;
  requirements: string;
  hotelLocation: string;
  notes: string;
  contacts: StageContact[];
  createdAt: Timestamp;
  createdById: string;
  updatedAt: Timestamp;
};

type StageContext = {
  now: Timestamp;
  actor: TaskActor;
};

const MAX_TITLE_LENGTH = 200;
const MAX_LONG_TEXT_LENGTH = 5000;
const MAX_LOCATION_LENGTH = 200;
const MAX_CONTACTS = 30;
const MAX_CONTACT_NAME_LENGTH = 100;
const MAX_CONTACT_PHONE_LENGTH = 30;
const MAX_CONTACT_ROLE_LENGTH = 100;
// Longer than any real event; stops a malformed event from making a huge list.
const MAX_EVENT_DAYS = 60;
const DAY_MILLIS = 24 * 60 * 60 * 1000;

const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;
const PHONE_PATTERN = /^[0-9+\-() ]+$/;

const israelDate = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Jerusalem',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/**
 * The days of an event as Israel-local `yyyy-MM-dd` strings, first to last.
 *
 * Events store `startDate` and `endDate` as the UTC instant of Israel midnight
 * (`T21:00Z` of the previous UTC day in summer, `T22:00Z` in winter), so the
 * day must be read in Israel time, not in UTC. A missing end, or one before
 * the start, makes a one-day event.
 */
export function eventLocalDays(startMillis: number, endMillis: number | null): string[] {
  const first = israelDate.format(new Date(startMillis));
  const last = endMillis == null ? first : israelDate.format(new Date(endMillis));
  if (last <= first) return [first];

  const days: string[] = [];
  // Step through calendar days on UTC noon so no clock change can skip one.
  let cursor = Date.parse(`${first}T12:00:00Z`);
  while (days.length < MAX_EVENT_DAYS) {
    const day = new Date(cursor).toISOString().slice(0, 10);
    days.push(day);
    if (day >= last) break;
    cursor += DAY_MILLIS;
  }
  return days;
}

// ---- audit ----

/** The `details` of a stage's audit log entry, named by its title. */
export function stageAuditDetails(
  stage: Pick<StageDoc, 'title' | 'eventId' | 'date'>,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {name: stage.title, eventId: stage.eventId, date: stage.date, ...extra};
}

// ---- reading a stored document ----

/** Coerce a stored document into a full [StageDoc], tolerating odd fields. */
export function stageFromStored(id: string, raw: Record<string, unknown>): StageDoc {
  return {
    id,
    eventId: storedString(raw['eventId']) ?? '',
    title: storedString(raw['title']) ?? '',
    date: storedString(raw['date']) ?? '',
    startTime: storedString(raw['startTime']),
    endTime: storedString(raw['endTime']),
    requirements: storedString(raw['requirements']) ?? '',
    hotelLocation: storedString(raw['hotelLocation']) ?? '',
    notes: storedString(raw['notes']) ?? '',
    contacts: storedContacts(raw['contacts']),
    createdAt: storedTimestamp(raw['createdAt']) ?? Timestamp.fromMillis(0),
    createdById: storedString(raw['createdById']) ?? '',
    updatedAt: storedTimestamp(raw['updatedAt']) ?? Timestamp.fromMillis(0),
  };
}

function storedString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function storedTimestamp(value: unknown): Timestamp | null {
  return value instanceof Timestamp ? value : null;
}

function storedContacts(value: unknown): StageContact[] {
  if (!Array.isArray(value)) return [];
  const contacts: StageContact[] = [];
  for (const entry of value) {
    if (entry == null || typeof entry !== 'object') continue;
    const record = entry as Record<string, unknown>;
    const id = record['id'];
    if (typeof id !== 'string' || id.length === 0) continue;
    contacts.push({
      id,
      name: storedString(record['name']) ?? '',
      phone: storedString(record['phone']) ?? '',
      role: storedString(record['role']) ?? '',
    });
  }
  return contacts;
}

// ---- validating a client payload ----

type EditableFields = Omit<StageDoc, 'id' | 'eventId' | 'createdAt' | 'createdById' | 'updatedAt'>;

function optionalText(value: unknown, max: number, label: string): string {
  if (value == null) return '';
  if (typeof value !== 'string') throw new TaskError(400, `${label} לא תקין`);
  const trimmed = value.trim();
  if (trimmed.length > max) throw new TaskError(400, `${label} ארוך מדי`);
  return trimmed;
}

function optionalTime(value: unknown): string | null {
  if (value == null || value === '') return null;
  if (typeof value !== 'string' || !TIME_PATTERN.test(value)) {
    throw new TaskError(400, 'שעה לא תקינה');
  }
  return value;
}

function parseContacts(value: unknown): StageContact[] {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TaskError(400, 'אנשי קשר לא תקינים');
  if (value.length > MAX_CONTACTS) throw new TaskError(400, 'יותר מדי אנשי קשר');

  const contacts: StageContact[] = [];
  const seenIds = new Set<string>();
  for (const entry of value) {
    if (entry == null || typeof entry !== 'object') {
      throw new TaskError(400, 'איש קשר לא תקין');
    }
    const record = entry as Record<string, unknown>;
    const id = record['id'];
    if (typeof id !== 'string' || !ID_PATTERN.test(id) || seenIds.has(id)) {
      throw new TaskError(400, 'איש קשר לא תקין');
    }
    seenIds.add(id);
    const name = optionalText(record['name'], MAX_CONTACT_NAME_LENGTH, 'שם איש הקשר');
    const phone = optionalText(record['phone'], MAX_CONTACT_PHONE_LENGTH, 'מספר הטלפון');
    const role = optionalText(record['role'], MAX_CONTACT_ROLE_LENGTH, 'התפקיד');
    // A row the manager left empty is dropped, as the form drops it.
    if (name.length === 0 && phone.length === 0 && role.length === 0) continue;
    if (name.length === 0) throw new TaskError(400, 'לכל איש קשר נדרש שם');
    if (phone.length > 0 && !PHONE_PATTERN.test(phone)) {
      throw new TaskError(400, 'מספר טלפון לא תקין');
    }
    contacts.push({id, name, phone, role});
  }
  return contacts;
}

function parseEditableFields(
  input: Record<string, unknown>,
  eventDays: string[],
): EditableFields {
  const title = typeof input['title'] === 'string' ? input['title'].trim() : '';
  if (title.length === 0) throw new TaskError(400, 'חובה להזין כותרת');
  if (title.length > MAX_TITLE_LENGTH) throw new TaskError(400, 'הכותרת ארוכה מדי');

  const date = input['date'];
  if (date == null || date === '') throw new TaskError(400, 'חובה לבחור תאריך');
  if (typeof date !== 'string' || !DATE_PATTERN.test(date)) {
    throw new TaskError(400, 'תאריך לא תקין');
  }
  if (!eventDays.includes(date)) {
    throw new TaskError(400, 'התאריך אינו מתאריכי האירוע');
  }

  const startTime = optionalTime(input['startTime']);
  const endTime = optionalTime(input['endTime']);
  if (endTime != null && startTime == null) {
    throw new TaskError(400, 'שעת סיום דורשת שעת התחלה');
  }
  // HH:mm strings compare in clock order.
  if (endTime != null && startTime != null && endTime <= startTime) {
    throw new TaskError(400, 'שעת הסיום חייבת להיות אחרי שעת ההתחלה');
  }

  return {
    title,
    date,
    startTime,
    endTime,
    requirements: optionalText(input['requirements'], MAX_LONG_TEXT_LENGTH, 'הדרישות'),
    hotelLocation: optionalText(input['hotelLocation'], MAX_LOCATION_LENGTH, 'המיקום'),
    notes: optionalText(input['notes'], MAX_LONG_TEXT_LENGTH, 'ההערות'),
    contacts: parseContacts(input['contacts']),
  };
}

/** The event id a stage payload names, checked for shape only. */
export function stageEventId(input: Record<string, unknown>): string {
  const eventId = input['eventId'];
  if (typeof eventId !== 'string' || !ID_PATTERN.test(eventId)) {
    throw new TaskError(400, 'אירוע לא תקין');
  }
  return eventId;
}

// ---- transitions ----

export function buildNewStage(
  input: Record<string, unknown>,
  ctx: StageContext,
  eventDays: string[],
): StageDoc {
  const id = input['id'];
  if (typeof id !== 'string' || !ID_PATTERN.test(id)) {
    throw new TaskError(400, 'מזהה שלב לא תקין');
  }
  const eventId = stageEventId(input);
  return {
    id,
    eventId,
    ...parseEditableFields(input, eventDays),
    createdAt: ctx.now,
    createdById: ctx.actor.memberId,
    updatedAt: ctx.now,
  };
}

export function applyStageEdit(
  existing: StageDoc,
  input: Record<string, unknown>,
  ctx: StageContext,
  eventDays: string[],
): StageDoc {
  if (input['id'] !== existing.id) {
    throw new TaskError(400, 'מזהה שלב לא תואם');
  }
  if (input['eventId'] !== existing.eventId) {
    throw new TaskError(400, 'לא ניתן להעביר שלב לאירוע אחר');
  }
  return {
    ...existing,
    ...parseEditableFields(input, eventDays),
    updatedAt: ctx.now,
  };
}
