/**
 * Pure RFC 5545 rendering for the personal calendar feed. This module holds no
 * Firestore or Express dependencies so every rule below is unit-testable.
 */

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
