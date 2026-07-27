import test from 'node:test';
import assert from 'node:assert/strict';
import {
  escapeIcsText,
  foldIcsLine,
  renderIcsFeed,
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
