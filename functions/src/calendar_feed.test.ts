import test from 'node:test';
import assert from 'node:assert/strict';
import {
  escapeIcsText,
  foldIcsLine,
  renderIcsFeed,
  buildMemberFeedParts,
  type FeedEventPart,
} from './calendar_feed';

test('escapeIcsText escapes the RFC 5545 TEXT specials', () => {
  assert.equal(escapeIcsText('a,b'), 'a\\,b');
  assert.equal(escapeIcsText('a;b'), 'a\\;b');
  assert.equal(escapeIcsText('a\\b'), 'a\\\\b');
  assert.equal(escapeIcsText('a\nb'), 'a\\nb');
  assert.equal(escapeIcsText('a\r\nb'), 'a\\nb');
});

test('escapeIcsText escapes the backslash before anything else', () => {
  // A naive implementation that escapes commas first would turn "\," into
  // "\\\\," and corrupt the output.
  assert.equal(escapeIcsText('\\,'), '\\\\\\,');
});

test('escapeIcsText leaves colons and Hebrew untouched', () => {
  assert.equal(escapeIcsText('סינון כניסה: 17:00'), 'סינון כניסה: 17:00');
});

test('foldIcsLine leaves short lines alone', () => {
  assert.equal(foldIcsLine('SUMMARY:קצר'), 'SUMMARY:קצר');
});

test('foldIcsLine folds on octets, not characters', () => {
  // Hebrew is 2 octets per character in UTF-8, so 60 characters is 120 octets
  // and must fold even though the character count is under 75.
  const line = `SUMMARY:${'א'.repeat(60)}`;
  const folded = foldIcsLine(line);
  assert.ok(folded.includes('\r\n '), 'expected the line to be folded');
  for (const segment of folded.split('\r\n')) {
    assert.ok(
      Buffer.from(segment, 'utf8').length <= 75,
      `segment exceeds 75 octets: ${segment}`,
    );
  }
});

test('foldIcsLine never splits a multi-byte character', () => {
  const line = `DESCRIPTION:${'ש'.repeat(200)}`;
  const rejoined = foldIcsLine(line).split('\r\n ').join('');
  assert.equal(rejoined, line);
  assert.ok(!rejoined.includes('�'), 'output contains a replacement char');
});

const TIMED_PART: FeedEventPart = {
  eventId: 'evt-1',
  uid: 'evt-1-main-mem-1@shavtzak',
  title: 'היכל התרבות',
  location: 'תל אביב',
  description: 'תפקיד: סינון כניסה',
  start: '2026-08-15T20:00',
  end: '2026-08-15T23:00',
  allDayStart: null,
  allDayEnd: null,
};

test('renderIcsFeed emits a well-formed, CRLF-terminated calendar', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק – יובל',
    dtstamp: '20260727T090000Z',
    parts: [TIMED_PART],
  });

  assert.ok(ics.startsWith('BEGIN:VCALENDAR\r\n'));
  assert.ok(ics.endsWith('END:VCALENDAR\r\n'));
  assert.ok(ics.includes('VERSION:2.0\r\n'));
  assert.ok(ics.includes('PRODID:'));
  assert.ok(!/(?<!\r)\n/.test(ics), 'found a bare LF; every break must be CRLF');
});

test('renderIcsFeed embeds a VTIMEZONE and uses TZID, never UTC', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [TIMED_PART],
  });

  assert.ok(ics.includes('BEGIN:VTIMEZONE\r\nTZID:Asia/Jerusalem\r\n'));
  assert.ok(ics.includes('DTSTART;TZID=Asia/Jerusalem:20260815T200000'));
  assert.ok(ics.includes('DTEND;TZID=Asia/Jerusalem:20260815T230000'));
});

test('renderIcsFeed renders summer and winter events at their wall-clock time', () => {
  // Israel is UTC+3 in August and UTC+2 in January. Because we emit local
  // times with a TZID, both must appear verbatim as 20:00 with no shifting.
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [
      TIMED_PART,
      {...TIMED_PART, uid: 'winter@shavtzak', start: '2027-01-15T20:00', end: '2027-01-15T23:00'},
    ],
  });

  assert.ok(ics.includes('DTSTART;TZID=Asia/Jerusalem:20260815T200000'));
  assert.ok(ics.includes('DTSTART;TZID=Asia/Jerusalem:20270115T200000'));
});

test('renderIcsFeed renders an all-day part with an exclusive DTEND', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [{
      ...TIMED_PART,
      start: null,
      end: null,
      allDayStart: '2026-08-15',
      allDayEnd: '2026-08-16',
    }],
  });

  assert.ok(ics.includes('DTSTART;VALUE=DATE:20260815'));
  assert.ok(ics.includes('DTEND;VALUE=DATE:20260816'));
  assert.ok(!ics.includes('TZID=Asia/Jerusalem:2026'));
});

test('renderIcsFeed escapes text properties', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [{...TIMED_PART, title: 'מופע, ערב', description: 'שורה\nשנייה'}],
  });

  assert.ok(ics.includes('SUMMARY:מופע\\, ערב'));
  assert.ok(ics.includes('שורה\\nשנייה'));
});

test('renderIcsFeed omits LOCATION when there is none', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [{...TIMED_PART, location: null}],
  });

  assert.ok(!ics.includes('LOCATION:'));
});

test('renderIcsFeed returns a valid empty calendar for a member with no shifts', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [],
  });

  assert.ok(ics.startsWith('BEGIN:VCALENDAR\r\n'));
  assert.ok(ics.endsWith('END:VCALENDAR\r\n'));
  assert.ok(!ics.includes('BEGIN:VEVENT'));
});

test('renderIcsFeed skips a part with start set and end null (malformed pair)', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [{...TIMED_PART, end: null}],
  });

  assert.ok(ics.startsWith('BEGIN:VCALENDAR\r\n'));
  assert.ok(ics.endsWith('END:VCALENDAR\r\n'));
  assert.ok(!ics.includes('BEGIN:VEVENT'));
});

test('renderIcsFeed skips a part with a single-digit hour (invalid format)', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [{...TIMED_PART, start: '2026-08-15T9:00', end: '2026-08-15T10:00'}],
  });

  assert.ok(ics.startsWith('BEGIN:VCALENDAR\r\n'));
  assert.ok(ics.endsWith('END:VCALENDAR\r\n'));
  assert.ok(!ics.includes('BEGIN:VEVENT'));
});

test('renderIcsFeed renders good parts and silently skips malformed ones', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [
      TIMED_PART, // well-formed
      {...TIMED_PART, uid: 'malformed@shavtzak', start: '2026-08-15T9:00', end: null}, // malformed
    ],
  });

  // The good part is rendered
  assert.ok(ics.includes('UID:evt-1-main-mem-1@shavtzak'));
  assert.ok(ics.includes('DTSTART;TZID=Asia/Jerusalem:20260815T200000'));
  // The malformed part is skipped (no second UID)
  assert.ok(!ics.includes('malformed@shavtzak'));
  // Calendar is still valid
  assert.ok(ics.startsWith('BEGIN:VCALENDAR\r\n'));
  assert.ok(ics.endsWith('END:VCALENDAR\r\n'));
});

test('renderIcsFeed escapes UID like other text properties', () => {
  const ics = renderIcsFeed({
    calendarName: 'שבצק',
    dtstamp: '20260727T090000Z',
    parts: [{...TIMED_PART, uid: 'evt-with,semicolon;uid@shavtzak'}],
  });

  assert.ok(ics.includes('UID:evt-with\\,semicolon\\;uid@shavtzak'));
});

function timedEvent(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    name: 'היכל התרבות',
    startDate: new Date('2026-08-14T21:00:00Z'),
    endDate: new Date('2026-08-14T21:00:00Z'),
    assemblyTime: '17:00',
    startTime: '20:00',
    endTime: '23:00',
    location: 'תל אביב',
    isDeactivated: false,
    ...overrides,
  };
}

test('buildMemberFeedParts emits an assembly part and a main part', () => {
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [{eventId: 'evt-1', roleType: 'entryScreening'}],
    eventsById: new Map([['evt-1', timedEvent()]]),
    roleHebrewNames: {entryScreening: 'סינון כניסה'},
  });

  assert.equal(parts.length, 2);
  assert.deepEqual(
    parts.map((part) => part.uid).sort(),
    ['evt-1-assembly-mem-1@shavtzak', 'evt-1-main-mem-1@shavtzak'],
  );
  assert.ok(parts.every((part) => part.description.includes('סינון כניסה')));
});

test('buildMemberFeedParts collapses two assignments in one event to one pair', () => {
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [
      {eventId: 'evt-1', roleType: 'entryScreening'},
      {eventId: 'evt-1', roleType: 'investigation'},
    ],
    eventsById: new Map([['evt-1', timedEvent()]]),
    roleHebrewNames: {entryScreening: 'סינון כניסה', investigation: 'תחקור'},
  });

  assert.equal(parts.length, 2, 'expected one assembly + one main, not four');
  assert.equal(new Set(parts.map((part) => part.uid)).size, 2, 'UIDs collided');
  const main = parts.find((part) => part.uid.includes('-main-'))!;
  assert.ok(main.description.includes('סינון כניסה'));
  assert.ok(main.description.includes('תחקור'));
});

test('buildMemberFeedParts excludes deactivated events', () => {
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [{eventId: 'evt-1', roleType: 'entryScreening'}],
    eventsById: new Map([['evt-1', timedEvent({isDeactivated: true})]]),
    roleHebrewNames: {},
  });

  assert.deepEqual(parts, []);
});

test('buildMemberFeedParts keeps past events — history is retained forever', () => {
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [{eventId: 'old', roleType: 'entryScreening'}],
    eventsById: new Map([['old', timedEvent({
      startDate: new Date('2026-02-09T22:00:00Z'),
      endDate: new Date('2026-02-09T22:00:00Z'),
    })]]),
    roleHebrewNames: {},
  });

  assert.equal(parts.length, 2);
});

test('buildMemberFeedParts falls back to one all-day part when times are missing', () => {
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [{eventId: 'evt-1', roleType: 'entryScreening'}],
    eventsById: new Map([['evt-1', timedEvent({assemblyTime: '', endTime: ''})]]),
    roleHebrewNames: {},
  });

  assert.equal(parts.length, 1);
  assert.equal(parts[0].allDayStart, '2026-08-15');
  assert.equal(parts[0].allDayEnd, '2026-08-16');
  assert.equal(parts[0].start, null);
});

test('buildMemberFeedParts skips an assignment whose event is missing or malformed', () => {
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [
      {eventId: 'gone', roleType: 'entryScreening'},
      {eventId: 'broken', roleType: 'entryScreening'},
      {eventId: 'evt-1', roleType: 'entryScreening'},
    ],
    // 'broken' has no name, so buildDesiredAppEventState throws for it. One bad
    // document must not take down the whole feed.
    eventsById: new Map<string, Record<string, unknown>>([
      ['broken', {isDeactivated: false}],
      ['evt-1', timedEvent()],
    ]),
    roleHebrewNames: {},
  });

  assert.equal(parts.length, 2);
  assert.ok(parts.every((part) => part.uid.startsWith('evt-1-')));
});

test('buildMemberFeedParts includes assignment notes in the description', () => {
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [{
      eventId: 'evt-1',
      roleType: 'entryScreening',
      notes: 'מסייע לאורנה בכניסות',
    }],
    eventsById: new Map([['evt-1', timedEvent()]]),
    roleHebrewNames: {entryScreening: 'סינון כניסה'},
  });

  assert.ok(parts[0].description.includes('מסייע לאורנה בכניסות'));
  assert.ok(parts[0].description.includes('סינון כניסה'));
});

test('buildMemberFeedParts falls back to the raw role key when there is no Hebrew name', () => {
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [{eventId: 'evt-1', roleType: 'role_1770725991134'}],
    eventsById: new Map([['evt-1', timedEvent()]]),
    roleHebrewNames: {},
  });

  assert.ok(parts[0].description.includes('role_1770725991134'));
});

// --- DTEND roll-forward for overnight events (RFC 5545 §3.6.1: DTEND must
// be strictly after DTSTART) ---------------------------------------------

test('buildMemberFeedParts rolls the main part DTEND forward when it inverts overnight', () => {
  // Real production shape (confirmed against a live event, 20 confirmed
  // assignees): assembly 20:30, start 21:00, actualShowStartTime 22:00
  // (wins as separatorTime), endTime 00:00, startDate == endDate. Read
  // literally, mainEndPrefix (endDate+endTime) lands 22h before DTSTART.
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [{eventId: 'evt-1', roleType: 'entryScreening'}],
    eventsById: new Map([['evt-1', timedEvent({
      assemblyTime: '20:30',
      startTime: '21:00',
      actualShowStartTime: '22:00',
      endTime: '00:00',
    })]]),
    roleHebrewNames: {},
  });

  const main = parts.find((part) => part.uid.includes('-main-'))!;
  const assembly = parts.find((part) => part.uid.includes('-assembly-'))!;

  assert.equal(main.start, '2026-08-15T22:00');
  assert.equal(main.end, '2026-08-16T00:00');
  assert.ok(main.end! > main.start!, 'DTEND must be strictly after DTSTART');

  // The assembly leg (20:30 -> 22:00, both same startDate) does not invert
  // and must be left exactly as computed.
  assert.equal(assembly.start, '2026-08-15T20:30');
  assert.equal(assembly.end, '2026-08-15T22:00');

  // End to end: the rendered feed must never emit an inverted pair.
  const ics = renderIcsFeed({calendarName: 'שבצק', dtstamp: '20260727T090000Z', parts});
  assert.ok(ics.includes('DTSTART;TZID=Asia/Jerusalem:20260815T220000'));
  assert.ok(ics.includes('DTEND;TZID=Asia/Jerusalem:20260816T000000'));
});

test('buildMemberFeedParts leaves a normal same-day event completely unaffected', () => {
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    // timedEvent() defaults: assembly 17:00, start 20:00, end 23:00, no
    // actualShowStartTime override — a plain same-day event.
    assignments: [{eventId: 'evt-1', roleType: 'entryScreening'}],
    eventsById: new Map([['evt-1', timedEvent()]]),
    roleHebrewNames: {},
  });

  const main = parts.find((part) => part.uid.includes('-main-'))!;
  const assembly = parts.find((part) => part.uid.includes('-assembly-'))!;

  assert.equal(assembly.start, '2026-08-15T17:00');
  assert.equal(assembly.end, '2026-08-15T20:00');
  assert.equal(main.start, '2026-08-15T20:00');
  assert.equal(main.end, '2026-08-15T23:00');
});

test('buildMemberFeedParts rolls DTEND forward across a month boundary correctly', () => {
  // 2026-08-30T21:00Z is Israel-local midnight of 2026-08-31 (memory:
  // startDate stores Israel local-midnight as UTC). The roll-forward must
  // parse and re-format the date rather than incrementing the day digit as
  // a string, or 31 -> 32 would be invalid instead of rolling to September.
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [{eventId: 'evt-1', roleType: 'entryScreening'}],
    eventsById: new Map([['evt-1', timedEvent({
      startDate: new Date('2026-08-30T21:00:00Z'),
      endDate: new Date('2026-08-30T21:00:00Z'),
      assemblyTime: '22:00',
      startTime: '23:00',
      actualShowStartTime: '23:30',
      endTime: '01:00',
    })]]),
    roleHebrewNames: {},
  });

  const main = parts.find((part) => part.uid.includes('-main-'))!;
  assert.equal(main.start, '2026-08-31T23:30');
  assert.equal(main.end, '2026-09-01T01:00');
  assert.ok(main.end! > main.start!, 'DTEND must be strictly after DTSTART');
});

test('buildMemberFeedParts rolls the assembly part DTEND forward when it wraps past midnight', () => {
  // Assembly pinned late (23:30) against startDate, while the show's actual
  // start is recorded as just after midnight (00:15) — still the same
  // startDate in the source data, so the assembly pair inverts even though
  // the main pair (00:15 -> 02:00) does not.
  const parts = buildMemberFeedParts({
    memberId: 'mem-1',
    environment: 'production',
    assignments: [{eventId: 'evt-1', roleType: 'entryScreening'}],
    eventsById: new Map([['evt-1', timedEvent({
      assemblyTime: '23:30',
      startTime: '23:45',
      actualShowStartTime: '00:15',
      endTime: '02:00',
    })]]),
    roleHebrewNames: {},
  });

  const assembly = parts.find((part) => part.uid.includes('-assembly-'))!;
  const main = parts.find((part) => part.uid.includes('-main-'))!;

  assert.equal(assembly.start, '2026-08-15T23:30');
  assert.equal(assembly.end, '2026-08-16T00:15');
  assert.ok(assembly.end! > assembly.start!, 'DTEND must be strictly after DTSTART');

  // The main leg (00:15 -> 02:00, both against startDate) does not invert.
  assert.equal(main.start, '2026-08-15T00:15');
  assert.equal(main.end, '2026-08-15T02:00');
});

// --- console.warn observability on the two silent-skip paths -------------

test('renderIcsFeed warns with the event id when a part is malformed', () => {
  const originalWarn = console.warn;
  const calls: unknown[][] = [];
  console.warn = (...args: unknown[]) => calls.push(args);
  try {
    renderIcsFeed({
      calendarName: 'שבצק',
      dtstamp: '20260727T090000Z',
      parts: [{...TIMED_PART, eventId: 'evt-broken-1', end: null}],
    });
  } finally {
    console.warn = originalWarn;
  }

  assert.equal(calls.length, 1);
  const [message] = calls[0];
  assert.ok(typeof message === 'string' && message.includes('evt-broken-1'));
});

test('buildMemberFeedParts warns with the event id when an event document is malformed', () => {
  const originalWarn = console.warn;
  const calls: unknown[][] = [];
  console.warn = (...args: unknown[]) => calls.push(args);
  try {
    buildMemberFeedParts({
      memberId: 'mem-1',
      environment: 'production',
      assignments: [{eventId: 'evt-broken-2', roleType: 'entryScreening'}],
      // No 'name' field, so buildDesiredAppEventState throws for it.
      eventsById: new Map<string, Record<string, unknown>>([
        ['evt-broken-2', {isDeactivated: false}],
      ]),
      roleHebrewNames: {},
    });
  } finally {
    console.warn = originalWarn;
  }

  assert.equal(calls.length, 1);
  const [message] = calls[0];
  assert.ok(typeof message === 'string' && message.includes('evt-broken-2'));
});
