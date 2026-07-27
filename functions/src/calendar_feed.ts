/**
 * Pure RFC 5545 rendering for the personal calendar feed. This module holds no
 * Firestore or Express dependencies so every rule below is unit-testable.
 */

import {
  buildDesiredAppEventState,
  type BackendEnvironmentMode,
} from './calendar_sync_backend';

/** Escapes a value for an RFC 5545 TEXT property (section 3.3.11). */
export function escapeIcsText(value: string): string {
  return value
    // Backslash must be escaped first, or the escapes added below get
    // double-escaped in turn.
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r\n/g, '\\n')
    .replace(/[\r\n]/g, '\\n');
}

/**
 * Folds a content line to 75 octets (section 3.1). The limit is octets, not
 * characters: Hebrew is two octets per character in UTF-8, so folding on
 * character boundaries both under-folds and can split a multi-byte sequence.
 */
export function foldIcsLine(line: string): string {
  const bytes = Buffer.from(line, 'utf8');
  if (bytes.length <= 75) {
    return line;
  }

  const segments: string[] = [];
  let start = 0;
  // The first line gets 75 octets; continuation lines spend one on the
  // leading space that marks them as continuations.
  let limit = 75;

  while (start < bytes.length) {
    let end = Math.min(start + limit, bytes.length);
    // Walk back off any UTF-8 continuation byte (10xxxxxx) so we always cut
    // on a character boundary.
    while (end > start && end < bytes.length && (bytes[end] & 0xc0) === 0x80) {
      end -= 1;
    }
    segments.push(bytes.subarray(start, end).toString('utf8'));
    start = end;
    limit = 74;
  }

  return segments.join('\r\n ');
}

export type FeedEventPart = {
  /** The source event, kept separate from `uid` so it can be logged on its
   *  own without incidentally logging the member id folded into the uid. */
  eventId: string;
  uid: string;
  title: string;
  location: string | null;
  description: string;
  /** Local wall-clock prefix, e.g. '2026-08-15T20:00'. Null for all-day. */
  start: string | null;
  end: string | null;
  /** Date key, e.g. '2026-08-15'. Null for timed parts. */
  allDayStart: string | null;
  /** Exclusive end date key, per RFC 5545. */
  allDayEnd: string | null;
};

const CRLF = '\r\n';

/**
 * Static VTIMEZONE for Israel, derived from tzdata: DST starts on the Friday
 * before the last Sunday in March and ends on the last Sunday in October.
 * Embedding this lets us emit local wall-clock times and leave the offset
 * arithmetic to the client, which avoids DST bugs entirely.
 */
const ISRAEL_VTIMEZONE = [
  'BEGIN:VTIMEZONE',
  'TZID:Asia/Jerusalem',
  'BEGIN:DAYLIGHT',
  'TZOFFSETFROM:+0200',
  'TZOFFSETTO:+0300',
  'TZNAME:IDT',
  'DTSTART:19700327T020000',
  'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=FR;BYMONTHDAY=23,24,25,26,27,28,29',
  'END:DAYLIGHT',
  'BEGIN:STANDARD',
  'TZOFFSETFROM:+0300',
  'TZOFFSETTO:+0200',
  'TZNAME:IST',
  'DTSTART:19701025T020000',
  'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
  'END:STANDARD',
  'END:VTIMEZONE',
];

/** '2026-08-15T20:00' -> '20260815T200000' */
function toIcsLocalDateTime(prefix: string): string {
  const compact = prefix.replace(/[-:]/g, '');
  return `${compact}00`;
}

/** '2026-08-15' -> '20260815' */
function toIcsDate(dateKey: string): string {
  return dateKey.replace(/-/g, '');
}

/** Check if a string matches the timed-event format: YYYY-MM-DDTHH:MM (zero-padded hours). */
function isValidTimedFormat(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value);
}

/** Check if a string matches the all-day format: YYYY-MM-DD. */
function isValidDateFormat(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function renderPart(part: FeedEventPart, dtstamp: string): string[] {
  // Validate that the part is well-formed before emitting a VEVENT.
  // A part with only one field of a pair (e.g., start but not end, or allDayStart
  // but not allDayEnd) would produce a malformed VEVENT with no DTSTART/DTEND,
  // poisoning the entire feed for downstream clients. Skip malformed parts silently.
  const hasValidTimedPair = part.start != null && part.end != null &&
    isValidTimedFormat(part.start) && isValidTimedFormat(part.end);
  const hasValidAllDayPair = part.allDayStart != null && part.allDayEnd != null &&
    isValidDateFormat(part.allDayStart) && isValidDateFormat(part.allDayEnd);

  if (!hasValidTimedPair && !hasValidAllDayPair) {
    // No token or member name here — an event id alone is safe to log.
    console.warn(`[calendar-feed] event ${part.eventId}: skipping malformed part (incomplete or invalid start/end pair)`);
    return [];
  }

  const lines = [
    'BEGIN:VEVENT',
    `UID:${escapeIcsText(part.uid)}`,
    `DTSTAMP:${dtstamp}`,
  ];

  if (hasValidAllDayPair) {
    lines.push(`DTSTART;VALUE=DATE:${toIcsDate(part.allDayStart!)}`);
    lines.push(`DTEND;VALUE=DATE:${toIcsDate(part.allDayEnd!)}`);
  } else {
    lines.push(`DTSTART;TZID=Asia/Jerusalem:${toIcsLocalDateTime(part.start!)}`);
    lines.push(`DTEND;TZID=Asia/Jerusalem:${toIcsLocalDateTime(part.end!)}`);
  }

  lines.push(`SUMMARY:${escapeIcsText(part.title)}`);
  if (part.location != null && part.location.length > 0) {
    lines.push(`LOCATION:${escapeIcsText(part.location)}`);
  }
  if (part.description.length > 0) {
    lines.push(`DESCRIPTION:${escapeIcsText(part.description)}`);
  }
  lines.push('END:VEVENT');
  return lines;
}

export function renderIcsFeed(params: {
  calendarName: string;
  dtstamp: string;
  parts: FeedEventPart[];
}): string {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Shavtzak//Personal Feed//HE',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    `X-WR-CALNAME:${escapeIcsText(params.calendarName)}`,
    'X-WR-TIMEZONE:Asia/Jerusalem',
    ...ISRAEL_VTIMEZONE,
  ];

  for (const part of params.parts) {
    lines.push(...renderPart(part, params.dtstamp));
  }

  lines.push('END:VCALENDAR');
  return lines.map(foldIcsLine).join(CRLF) + CRLF;
}

type FeedAssignment = {eventId: string; roleType: string; notes?: string};

/**
 * Rolls the date portion of a 'YYYY-MM-DDTHH:MM' prefix forward by one day,
 * preserving the time-of-day. Parses the digits into numbers and lets
 * Date.UTC normalize the overflow, rather than doing string arithmetic on
 * the day component, so this is correct across month and year boundaries
 * (e.g. 31 August rolls to 1 September).
 */
function addOneDayToPrefix(prefix: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})(T\d{2}:\d{2})$/.exec(prefix);
  if (match == null) {
    // Defensive only: every caller passes a prefix already shaped by
    // formatDateTimePrefix. Nothing sane to roll, so return unchanged.
    return prefix;
  }
  const [, year, month, day, timePart] = match;
  const rolled = new Date(Date.UTC(Number(year), Number(month) - 1, Number(day) + 1));
  const y = String(rolled.getUTCFullYear()).padStart(4, '0');
  const m = String(rolled.getUTCMonth() + 1).padStart(2, '0');
  const d = String(rolled.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}${timePart}`;
}

/**
 * Ensures an event part's end prefix is strictly after its start prefix, per
 * RFC 5545 §3.6.1. Both are 'YYYY-MM-DDTHH:MM' strings, so lexicographic
 * comparison is a valid ordering check. An overnight shift (e.g. assembly at
 * 22:00, endTime '00:00' on the same startDate) produces an end time that is
 * on or before the start when read literally — the source data means "the
 * next day", it just doesn't say so. Roll the end date forward instead of
 * dropping the part: skipping it would delete the member's shift from their
 * calendar entirely, which is worse than briefly showing a wrong time.
 */
function rollEndPrefixForward(startPrefix: string, endPrefix: string): string {
  return endPrefix <= startPrefix ? addOneDayToPrefix(endPrefix) : endPrefix;
}

/**
 * Groups a member's assignments by event and renders each event as the same
 * assembly/main pair the shared Shavtzak calendar produces.
 *
 * The grouping key is (member, event), NOT (member, assignment): a member can
 * hold several roles in one event, and emitting a pair per assignment would
 * produce duplicate UIDs and stacked identical blocks in their calendar.
 */
export function buildMemberFeedParts(params: {
  memberId: string;
  environment: BackendEnvironmentMode;
  assignments: FeedAssignment[];
  eventsById: Map<string, Record<string, unknown>>;
  roleHebrewNames: Record<string, string>;
}): FeedEventPart[] {
  const rolesByEventId = new Map<string, string[]>();
  const notesByEventId = new Map<string, string[]>();
  for (const assignment of params.assignments) {
    const roleName = params.roleHebrewNames[assignment.roleType] ??
      assignment.roleType;
    const roles = rolesByEventId.get(assignment.eventId) ?? [];
    if (!roles.includes(roleName)) {
      roles.push(roleName);
    }
    rolesByEventId.set(assignment.eventId, roles);

    const note = (assignment.notes ?? '').trim();
    const notes = notesByEventId.get(assignment.eventId) ?? [];
    if (note.length > 0 && !notes.includes(note)) {
      notes.push(note);
    }
    notesByEventId.set(assignment.eventId, notes);
  }

  const parts: FeedEventPart[] = [];

  for (const [eventId, roles] of rolesByEventId) {
    const eventData = params.eventsById.get(eventId);
    if (eventData == null || eventData['isDeactivated'] === true) {
      continue;
    }

    let desired;
    try {
      desired = buildDesiredAppEventState(eventId, eventData, params.environment);
    } catch (error) {
      // A malformed event document must not take down the whole feed. No
      // token or member name here — an event id alone is safe to log.
      const reason = error instanceof Error ? error.message : String(error);
      console.warn(`[calendar-feed] event ${eventId}: skipping malformed event document (${reason})`);
      continue;
    }

    const notes = notesByEventId.get(eventId) ?? [];
    const description = [`תפקיד: ${roles.join(', ')}`, ...notes].join('\n');
    const base = {
      eventId,
      location: desired.location,
      description,
      start: null,
      end: null,
      allDayStart: null,
      allDayEnd: null,
    };

    if (desired.useAllDay) {
      parts.push({
        ...base,
        uid: `${eventId}-main-${params.memberId}@shavtzak`,
        title: desired.mainTitle,
        allDayStart: desired.allDayStartDate,
        allDayEnd: desired.allDayEndDate,
      });
      continue;
    }

    if (desired.assemblyStartPrefix != null && desired.assemblyEndPrefix != null) {
      parts.push({
        ...base,
        uid: `${eventId}-assembly-${params.memberId}@shavtzak`,
        title: desired.assemblyTitle,
        start: desired.assemblyStartPrefix,
        // Same-day wrap is possible here too: assemblyStart/End are both
        // pinned to startDate, so a very late assembly + past-midnight show
        // start can invert this pair exactly like the main pair below.
        end: rollEndPrefixForward(desired.assemblyStartPrefix, desired.assemblyEndPrefix),
      });
    }

    if (desired.mainStartPrefix != null && desired.mainEndPrefix != null) {
      parts.push({
        ...base,
        uid: `${eventId}-main-${params.memberId}@shavtzak`,
        title: desired.mainTitle,
        start: desired.mainStartPrefix,
        // mainEndPrefix is endDate+endTime with no roll-forward when the
        // show ends after midnight (endTime wraps but endDate often equals
        // startDate) — roll it here so DTEND is never <= DTSTART (RFC 5545
        // §3.6.1). See rollEndPrefixForward for why we roll instead of skip.
        end: rollEndPrefixForward(desired.mainStartPrefix, desired.mainEndPrefix),
      });
    }
  }

  return parts;
}
