# Personal ICS Calendar Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every team member a secret URL serving their own shifts as a subscribable calendar feed, so their assignments appear in their personal calendar app without any Google Calendar guest invitations.

**Architecture:** A public, unauthenticated `GET` route on the existing Express `api` Cloud Function renders an RFC 5545 `VCALENDAR` from Firestore on every request. There is no sync state, no queue, and no Google Calendar API call on this path — the feed is a pure function of Firestore. Flutter gains a token-minting mutation, a self-serve subscribe dialog, and admin copy/share actions.

**Tech Stack:** TypeScript Cloud Functions (Express, firebase-admin), `node:test` for backend tests; Flutter Web with BLoC, `url_launcher`, `flutter_test`.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-27-personal-ics-calendar-feed-design.md`. Read it before starting.
- **Do not modify any existing Google Calendar sync behaviour.** No changes to `syncAppEventCalendars`, `reconcileSingleAppEvent`, attendee handling, or the Cloud Tasks path. This feature is purely additive.
  - **One approved exception**, forced by moving the feed token onto `private_member_credentials`: that document previously held only passcode fields, so two sites treat it as wholly disposable. `teamMember.clearPasscode` (`index.ts:3492`) must change from a whole-document `.delete()` to a merge-set that removes only `passcodeHash` / `passcodeValue` / `passcodeLength`, and `teamMember.insertBatch` (`index.ts:3698`) must gain `{merge: true}`. Without these, clearing a passcode or re-importing a member silently destroys their feed token and breaks a live calendar subscription with no signal. `teamMember.delete` (`index.ts:3674`) keeps its whole-document delete — removing a member *should* remove their token.
- **Do not re-enable Google Calendar guest invitations** on any path.
- All UI text is in Hebrew. Code comments in English.
- All screens wrap in `Directionality(textDirection: TextDirection.rtl)`.
- Backend collection names always come from the `Collections` object (environment-prefixed). Never hardcode `teamMembers`/`events`/`assignments`.
  - **One documented exception:** the roles list lives at `utilities/Lists`, and `utilities` is absent from the `Collections` type because it is a known pre-existing issue that this collection is not environment-prefixed. `drive_export.ts` hardcodes it the same way. Task 5 follows that precedent; do not invent a `Collections.utilities` entry as part of this feature.
- Entities extend `Equatable` and include **all** fields in `props`.
- Backend tests: `cd functions && npm test` (this runs `tsc` first, then `node --test "lib/**/*.test.js"`).
- Flutter tests: `cd shavtzak && flutter test`. Analyzer: `cd shavtzak && flutter analyze` — the baseline has ~107 pre-existing infos, so "clean" means **zero new** findings.
- Line terminator in all ICS output is **CRLF** (`\r\n`), per RFC 5545.
- The feed's timezone strategy is **`TZID=Asia/Jerusalem` + an embedded `VTIMEZONE` block**, using local wall-clock times directly. Never convert to UTC — that would reintroduce DST arithmetic, which is the likeliest source of an off-by-one given this repo stores `events.startDate` as Israel local midnight in UTC.

---

## File Structure

**Backend (create):**
- `functions/src/calendar_feed.ts` — pure ICS rendering and feed assembly. No Firestore, no Express.
- `functions/src/calendar_feed.test.ts` — tests for the above.

**Backend (modify):**
- `functions/src/index.ts` — two mutation cases in `executeMutation`, one public GET route.

**Flutter (create):**
- `shavtzak/lib/core/services/calendar_feed_links.dart` — pure URL builders.
- `shavtzak/lib/presentation/widgets/calendar_feed_dialog.dart` — the subscribe dialog.
- `shavtzak/test/core/services/calendar_feed_links_test.dart`

**Flutter (modify):**
- `shavtzak/lib/data/data_sources/database_interface.dart`
- `shavtzak/lib/data/data_sources/firestore_database.dart`
- `shavtzak/lib/presentation/screens/user/user_assignments_screen.dart`
- `shavtzak/lib/presentation/screens/team/team_list_screen.dart`

**Deliberately not created:** no new BLoC. Token minting is a one-shot request/response with no stream and no cross-screen state; a BLoC would be ceremony. The dialog calls the database interface directly, as `passcode_change_dialog.dart` already does.

---

### Task 1: ICS primitives — escaping and line folding

These two functions are where Hebrew content silently corrupts if done wrong, so they are built and tested first, in isolation.

**Files:**
- Create: `functions/src/calendar_feed.ts`
- Test: `functions/src/calendar_feed.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `escapeIcsText(value: string): string`, `foldIcsLine(line: string): string`.

- [ ] **Step 1: Write the failing tests**

Create `functions/src/calendar_feed.test.ts`:

```typescript
import test from 'node:test';
import assert from 'node:assert/strict';
import {escapeIcsText, foldIcsLine} from './calendar_feed';

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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd functions && npm test`
Expected: FAIL — `Cannot find module './calendar_feed'`.

- [ ] **Step 3: Write the implementation**

Create `functions/src/calendar_feed.ts`:

```typescript
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd functions && npm test`
Expected: PASS — all 6 new tests green, and the pre-existing suite still passes.

- [ ] **Step 5: Commit**

```bash
git add functions/src/calendar_feed.ts functions/src/calendar_feed.test.ts
git commit -m "feat(calendar-feed): RFC 5545 text escaping and octet-safe line folding"
```

---

### Task 2: Render a VCALENDAR document

**Files:**
- Modify: `functions/src/calendar_feed.ts`
- Test: `functions/src/calendar_feed.test.ts`

**Interfaces:**
- Consumes: `escapeIcsText`, `foldIcsLine` from Task 1.
- Produces:
  - `type FeedEventPart = {uid: string; title: string; location: string | null; description: string; start: string | null; end: string | null; allDayStart: string | null; allDayEnd: string | null}`
  - `renderIcsFeed(params: {calendarName: string; dtstamp: string; parts: FeedEventPart[]}): string`

`start`/`end` are local wall-clock prefixes in the exact shape `buildDesiredAppEventState` already produces (`'2026-08-15T17:00'`). `allDayStart`/`allDayEnd` are date keys (`'2026-08-15'`), with `allDayEnd` **exclusive** — again matching what `buildDesiredAppEventState` already returns. `dtstamp` is injected rather than read from the clock so the output is deterministic in tests.

- [ ] **Step 1: Write the failing tests**

First widen the existing import at the top of `functions/src/calendar_feed.test.ts` — do not add a second `import` from the same module:

```typescript
import {
  escapeIcsText,
  foldIcsLine,
  renderIcsFeed,
  type FeedEventPart,
} from './calendar_feed';
```

Then append:

```typescript
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd functions && npm test`
Expected: FAIL — `renderIcsFeed` is not exported.

- [ ] **Step 3: Write the implementation**

Append to `functions/src/calendar_feed.ts`:

```typescript
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

function renderPart(part: FeedEventPart, dtstamp: string): string[] {
  const lines = [
    'BEGIN:VEVENT',
    `UID:${part.uid}`,
    `DTSTAMP:${dtstamp}`,
  ];

  if (part.allDayStart != null && part.allDayEnd != null) {
    lines.push(`DTSTART;VALUE=DATE:${toIcsDate(part.allDayStart)}`);
    lines.push(`DTEND;VALUE=DATE:${toIcsDate(part.allDayEnd)}`);
  } else if (part.start != null && part.end != null) {
    lines.push(`DTSTART;TZID=Asia/Jerusalem:${toIcsLocalDateTime(part.start)}`);
    lines.push(`DTEND;TZID=Asia/Jerusalem:${toIcsLocalDateTime(part.end)}`);
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd functions && npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/calendar_feed.ts functions/src/calendar_feed.test.ts
git commit -m "feat(calendar-feed): render a VCALENDAR with an Asia/Jerusalem VTIMEZONE"
```

---

### Task 3: Assemble a member's feed parts from Firestore documents

Turns raw documents into `FeedEventPart[]`. Still pure — it takes plain records, not a Firestore handle, so it is fully unit-testable.

The critical rule here is the **grouping key: one pair of parts per (member, event), not per assignment.** A member can hold two assignments in one event (production data has member `a606f320` in two `entryScreening` slots of event `2511d06b`, and `allowMultipleAssignments` members do it by design). Grouping per assignment would emit duplicate `UID`s and two identical calendar blocks.

**Files:**
- Modify: `functions/src/calendar_feed.ts`
- Test: `functions/src/calendar_feed.test.ts`

**Interfaces:**
- Consumes: `FeedEventPart` from Task 2; `buildDesiredAppEventState` and `BackendEnvironmentMode` from `./calendar_sync_backend` (both already exported — do **not** modify that file).
- Produces: `buildMemberFeedParts(params: {memberId: string; environment: BackendEnvironmentMode; assignments: Array<{eventId: string; roleType: string; notes?: string}>; eventsById: Map<string, Record<string, unknown>>; roleHebrewNames: Record<string, string>}): FeedEventPart[]`

The `DESCRIPTION` carries the member's role(s) **and their assignment notes** — production data has entries like `"מסייע לאורנה בכניסות"`, which is exactly the per-member detail worth surfacing on their own calendar. Note there is no event-level notes field; the notes live on the assignment.

- [ ] **Step 1: Write the failing tests**

Widen the existing import to include `buildMemberFeedParts`, then append:

```typescript
function timedEvent(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    name: 'היכל התרבות',
    startDate: new Date('2026-08-15T21:00:00Z'),
    endDate: new Date('2026-08-15T21:00:00Z'),
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
      startDate: new Date('2026-02-10T22:00:00Z'),
      endDate: new Date('2026-02-10T22:00:00Z'),
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd functions && npm test`
Expected: FAIL — `buildMemberFeedParts` is not exported.

- [ ] **Step 3: Write the implementation**

Add the import at the top of `functions/src/calendar_feed.ts`:

```typescript
import {
  buildDesiredAppEventState,
  type BackendEnvironmentMode,
} from './calendar_sync_backend';
```

Then append:

```typescript
type FeedAssignment = {eventId: string; roleType: string; notes?: string};

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
    } catch {
      // A malformed event document must not take down the whole feed.
      continue;
    }

    const notes = notesByEventId.get(eventId) ?? [];
    const description = [`תפקיד: ${roles.join(', ')}`, ...notes].join('\n');
    const base = {
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
        end: desired.assemblyEndPrefix,
      });
    }

    if (desired.mainStartPrefix != null && desired.mainEndPrefix != null) {
      parts.push({
        ...base,
        uid: `${eventId}-main-${params.memberId}@shavtzak`,
        title: desired.mainTitle,
        start: desired.mainStartPrefix,
        end: desired.mainEndPrefix,
      });
    }
  }

  return parts;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd functions && npm test`
Expected: PASS.

If `BackendEnvironmentMode` turns out not to be exported from `calendar_sync_backend.ts`, add `export` to its declaration — that is a type-only change and touches no behaviour.

- [ ] **Step 5: Commit**

```bash
git add functions/src/calendar_feed.ts functions/src/calendar_feed.test.ts
git commit -m "feat(calendar-feed): assemble a member's parts, one pair per event"
```

---

### Task 4: Token mutations

**Files:**
- Modify: `functions/src/index.ts` — add two cases to the `executeMutation` switch, immediately after `case 'teamMember.clearPasscode'` (around line 3500).

**Interfaces:**
- Consumes: existing `requireString`, `requireSelfOrAdmin`, `writeAuditLog`, `HttpError`, `db`, `collections`.
- Produces: mutations `teamMember.ensureCalendarFeedToken` and `teamMember.rotateCalendarFeedToken`, both returning `{ok: true, token: string}`.

- [ ] **Step 1: Add the token generator**

Near the other small helpers at the top of `functions/src/index.ts`, add:

```typescript
import {randomBytes} from 'node:crypto';

/**
 * 256 bits of entropy, base64url encoded. This value is a bearer credential
 * that ends up in a URL pasted into calendar apps and WhatsApp, so it must
 * never be derived from uniqueKey, which authenticates the member.
 */
function generateCalendarFeedToken(): string {
  return randomBytes(32).toString('base64url');
}
```

If `node:crypto` is already imported in the file, extend the existing import rather than adding a second one.

- [ ] **Step 2: Add the two mutation cases**

```typescript
    case 'teamMember.ensureCalendarFeedToken': {
      const memberId = requireString(payload['memberId'], 'memberId');
      requireSelfOrAdmin(actor, memberId);

      const teamRef = db.collection(collections.teamMembers).doc(memberId);
      const teamDoc = await teamRef.get();
      if (!teamDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }

      const existing = teamDoc.data()?.['calendarFeedToken'];
      if (typeof existing === 'string' && existing.length > 0) {
        return {ok: true, token: existing};
      }

      const token = generateCalendarFeedToken();
      await teamRef.update({
        calendarFeedToken: token,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {ok: true, token};
    }

    case 'teamMember.rotateCalendarFeedToken': {
      const memberId = requireString(payload['memberId'], 'memberId');
      requireSelfOrAdmin(actor, memberId);

      const teamRef = db.collection(collections.teamMembers).doc(memberId);
      const teamDoc = await teamRef.get();
      if (!teamDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }

      const token = generateCalendarFeedToken();
      await teamRef.update({
        calendarFeedToken: token,
        updatedAt: FieldValue.serverTimestamp(),
      });
      // The token itself is a secret, so it is deliberately absent from the
      // audit payload; only the fact of rotation is recorded.
      await writeAuditLog(
        db, collections, actor, operation, 'teamMember', memberId, {}, {},
      );
      return {ok: true, token};
    }
```

- [ ] **Step 3: Verify the build**

Run: `cd functions && npm run build`
Expected: no TypeScript errors.

- [ ] **Step 4: Commit**

```bash
git add functions/src/index.ts
git commit -m "feat(calendar-feed): mint and rotate per-member feed tokens"
```

---

### Task 5: The public feed route

**Files:**
- Modify: `functions/src/index.ts` — add a route near the other `/calendar/*` routes (around line 5613). It must be registered on `app` like the others.

**Interfaces:**
- Consumes: `buildMemberFeedParts` and `renderIcsFeed` from `./calendar_feed`; existing `db`, `buildCollections`-equivalent used by `authenticateRequest`.
- Produces: `GET /calendar/feed/:environment/:tokenFile`.

The route is **deliberately unauthenticated** — it never calls `authenticateRequest`. The `api` function is already declared `invoker: 'public'`, so no infrastructure change is needed.

Firestore creates single-field indexes automatically, so the
`calendarFeedToken` equality query needs no index deployment. There is nothing
to add to `firestore.indexes.json`.

- [ ] **Step 1: Extend the crypto import and add the route**

Add `createHash` to the `node:crypto` import introduced in Task 4, then:

```typescript
app.get('/calendar/feed/:environment/:tokenFile', async (
  request: Request,
  response: Response,
) => {
  try {
    const environmentParam = String(request.params['environment'] ?? '');
    if (environmentParam !== 'prod' && environmentParam !== 'test') {
      response.status(404).send('Not found');
      return;
    }
    const environment: EnvironmentMode =
      environmentParam === 'test' ? 'test' : 'production';
    // getCollections is the existing prefixing helper (index.ts:182). Never
    // write a second copy of the prefix logic.
    const collections = getCollections(environment);

    const token = String(request.params['tokenFile'] ?? '').replace(/\.ics$/i, '');
    if (token.length === 0) {
      response.status(404).send('Not found');
      return;
    }

    // The token lives on the Admin-SDK-only private credentials document, NOT
    // on teamMembers — every active member can read every teamMembers doc.
    // The credential doc's id IS the member id.
    const credentialSnapshot = await db
      .collection(collections.privateCredentials)
      .where('calendarFeedToken', '==', token)
      .limit(1)
      .get();
    // Unknown and malformed tokens are indistinguishable to a caller.
    if (credentialSnapshot.empty) {
      response.status(404).send('Not found');
      return;
    }

    const memberId = credentialSnapshot.docs[0].id;
    const memberDoc = await db
      .collection(collections.teamMembers)
      .doc(memberId)
      .get();
    if (!memberDoc.exists) {
      response.status(404).send('Not found');
      return;
    }
    const memberData = memberDoc.data() ?? {};
    const memberName = typeof memberData['name'] === 'string'
      ? memberData['name']
      : '';

    const assignmentsSnapshot = await db
      .collection(collections.assignments)
      .where('teamMemberId', '==', memberId)
      // Explicit order so the feed is byte-stable between polls. Without it a
      // reordered role list inside a DESCRIPTION would look like a change to
      // every subscriber's calendar on every refresh.
      .orderBy('__name__')
      .get();
    const assignments = assignmentsSnapshot.docs.map((doc) => {
      const data = doc.data() ?? {};
      return {
        eventId: typeof data['eventId'] === 'string' ? data['eventId'] : '',
        roleType: typeof data['roleType'] === 'string' ? data['roleType'] : '',
        notes: typeof data['notes'] === 'string' ? data['notes'] : '',
      };
    }).filter((assignment) => assignment.eventId.length > 0);

    const eventIds = Array.from(new Set(assignments.map((a) => a.eventId)));
    const eventsById = new Map<string, Record<string, unknown>>();
    if (eventIds.length > 0) {
      const refs = eventIds.map(
        (id) => db.collection(collections.events).doc(id),
      );
      const eventDocs = await db.getAll(...refs);
      for (const doc of eventDocs) {
        if (doc.exists) {
          eventsById.set(doc.id, doc.data() ?? {});
        }
      }
    }

    const listsDoc = await db.collection('utilities').doc('Lists').get();
    const roleHebrewNames: Record<string, string> = {};
    const rolesList = listsDoc.data()?.['Roles'];
    if (Array.isArray(rolesList)) {
      for (const entry of rolesList) {
        if (entry == null || typeof entry !== 'object') continue;
        const role = entry as Record<string, unknown>;
        const key = typeof role['key'] === 'string' ? role['key'] : '';
        const hebrewName = typeof role['hebrewName'] === 'string'
          ? role['hebrewName']
          : '';
        if (key.length > 0) {
          roleHebrewNames[key] = hebrewName.length > 0 ? hebrewName : key;
        }
      }
    }

    const parts = buildMemberFeedParts({
      memberId: memberDoc.id,
      // EnvironmentMode and BackendEnvironmentMode are both
      // 'production' | 'test', so this passes through unchanged.
      environment,
      assignments,
      eventsById,
      roleHebrewNames,
    });

    const ics = renderIcsFeed({
      calendarName: memberName.length > 0 ? `שבצק – ${memberName}` : 'שבצק',
      dtstamp: new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, ''),
      parts,
    });

    // The ETag is computed over the feed body with DTSTAMP stripped, since
    // DTSTAMP changes on every render and would defeat every 304.
    const etag = `"${createHash('sha256')
      .update(ics.replace(/^DTSTAMP:.*$/gm, ''))
      .digest('base64url')}"`;
    response.setHeader('ETag', etag);
    if (request.headers['if-none-match'] === etag) {
      response.status(304).end();
      return;
    }

    response.setHeader('Content-Type', 'text/calendar; charset=utf-8');
    response.setHeader('Cache-Control', 'public, max-age=3600');
    response.status(200).send(ics);
  } catch (error) {
    handleError(response, error);
  }
});
```

- [ ] **Step 2: Verify the build**

Run: `cd functions && npm run build && npm test`
Expected: build clean, all tests pass.

- [ ] **Step 3: Hand the route's verification to the owner — do not deploy**

**Do not run `firebase deploy`.** Deploying is the owner's action, at the owner's timing. A deploy pushes all three functions (`api`, `calendarSyncTask`, `calendarJobSweep`) and would also carry any as-yet-unreleased `functions/` commits sitting on `main` — not something to trigger as a side effect of testing a route.

The spec asked for automated endpoint tests. This repo's `functions` suite is pure-unit with no Firestore emulator harness, and standing one up for four assertions is out of proportion to this feature. The route's logic is therefore kept deliberately thin — every rule worth testing lives in the pure functions from Tasks 1–3 — and the route itself stays unverified until the owner deploys.

Record in the task report that the route is **built and type-checked but not exercised**, so the final review knows this is a known, accepted gap rather than an oversight. The owner's post-deploy checks are listed at the end of this plan.

- [ ] **Step 4: Commit**

```bash
git add functions/src/index.ts
git commit -m "feat(calendar-feed): serve a per-member ICS feed on a public route"
```

---

### Task 6: Flutter — feed token methods on the data layer

**Files:**
- Modify: `shavtzak/lib/data/data_sources/database_interface.dart`
- Modify: `shavtzak/lib/data/data_sources/firestore_database.dart`

**Interfaces:**
- Consumes: the mutations from Task 4.
- Produces: `DatabaseInterface.ensureCalendarFeedToken(String id) → Future<String>` and `rotateCalendarFeedToken(String id) → Future<String>`.

**Do NOT add `calendarFeedToken` to the `TeamMember` entity or model.** An earlier draft of this plan did. The token lives on the Admin-SDK-only `private_member_credentials` document, so the Flutter client cannot read it from Firestore at all — it only ever arrives as the return value of the minting mutation, and the dialog holds it in local widget state. Adding it to the entity would create a field that is permanently null in every streamed `TeamMember`, which is worse than useless: it would look like a token that had never been minted.

- [ ] **Step 1: Add the interface methods**

In `database_interface.dart`:

```dart
  /// Returns the member's calendar feed token, creating one if absent.
  Future<String> ensureCalendarFeedToken(String id);

  /// Issues a new token, invalidating any previously shared feed URL.
  Future<String> rotateCalendarFeedToken(String id);
```

- [ ] **Step 2: Implement them**

In `firestore_database.dart`, following the `updateTeamMemberPasscode` pattern at line 343:

```dart
  @override
  Future<String> ensureCalendarFeedToken(String id) async {
    try {
      final result = await _invokeMutation(
        'teamMember.ensureCalendarFeedToken',
        payload: {'memberId': id},
      );
      final token = result['token'] as String?;
      if (token == null || token.isEmpty) {
        throw DatabaseException('Backend returned no calendar feed token');
      }
      return token;
    } catch (e) {
      throw DatabaseException('Failed to ensure calendar feed token: $e');
    }
  }

  @override
  Future<String> rotateCalendarFeedToken(String id) async {
    try {
      final result = await _invokeMutation(
        'teamMember.rotateCalendarFeedToken',
        payload: {'memberId': id},
      );
      final token = result['token'] as String?;
      if (token == null || token.isEmpty) {
        throw DatabaseException('Backend returned no calendar feed token');
      }
      return token;
    } catch (e) {
      throw DatabaseException('Failed to rotate calendar feed token: $e');
    }
  }
```

- [ ] **Step 3: Verify**

Run: `cd shavtzak && flutter analyze && flutter test`
Expected: zero **new** analyzer findings; all tests pass. If any fake/mock implements `DatabaseInterface`, the analyzer will flag the two missing overrides — add them there too, returning a canned token.

- [ ] **Step 4: Commit**

```bash
git add shavtzak/lib/data
git commit -m "feat(calendar-feed): add feed token methods to the data layer"
```

---

### Task 7: Flutter — feed URL builders

Pure string builders, kept separate from the widget so the URL shapes are testable without pumping a widget.

**Files:**
- Create: `shavtzak/lib/core/services/calendar_feed_links.dart`
- Test: `shavtzak/test/core/services/calendar_feed_links_test.dart`

**Interfaces:**
- Consumes: `EnvironmentService.instance.isTestMode`.
- Produces: `CalendarFeedLinks.httpsUrl(String token, {required bool isTestMode})`, `.webcalUrl(String token, {required bool isTestMode})`, `.whatsappShareUrl({required String token, required String? phoneNumber, required bool isTestMode})`.

(An earlier draft of this line advertised a `memberName` parameter that appears in neither the tests nor the implementation below. There is no personalised greeting: WhatsApp already opens the specific member's chat via the normalised phone number, so a name in the message body adds nothing. The code block below is authoritative.)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/calendar_feed_links.dart';

void main() {
  group('CalendarFeedLinks', () {
    test('builds an https feed URL ending in .ics', () {
      final url = CalendarFeedLinks.httpsUrl('abc123', isTestMode: false);
      expect(url, endsWith('/calendar/feed/prod/abc123.ics'));
      expect(url, startsWith('https://'));
    });

    test('uses the test segment in test mode', () {
      final url = CalendarFeedLinks.httpsUrl('abc123', isTestMode: true);
      expect(url, contains('/calendar/feed/test/'));
    });

    test('webcal URL mirrors the https URL with the webcal scheme', () {
      final https = CalendarFeedLinks.httpsUrl('abc123', isTestMode: false);
      final webcal = CalendarFeedLinks.webcalUrl('abc123', isTestMode: false);
      expect(webcal, 'webcal://${https.substring('https://'.length)}');
    });

    test('WhatsApp URL targets the member and encodes the link', () {
      final url = CalendarFeedLinks.whatsappShareUrl(
        token: 'abc123',
        phoneNumber: '050-123-4567',
        isTestMode: false,
      );
      // Israeli local numbers must be normalised to international form and
      // stripped of separators, or wa.me rejects them.
      expect(url, startsWith('https://wa.me/972501234567?text='));
      expect(url, contains(Uri.encodeComponent('.ics')));
    });

    test('WhatsApp URL omits the recipient when there is no phone number', () {
      final url = CalendarFeedLinks.whatsappShareUrl(
        token: 'abc123',
        phoneNumber: null,
        isTestMode: false,
      );
      expect(url, startsWith('https://wa.me/?text='));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd shavtzak && flutter test test/core/services/calendar_feed_links_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
/// Builds the URLs used to share and subscribe to a member's personal
/// calendar feed. Pure string construction so the shapes stay testable.
class CalendarFeedLinks {
  const CalendarFeedLinks._();

  static const String _functionsBase =
      'https://us-central1-tsevet-shir-shavtzak.cloudfunctions.net/api';

  static String httpsUrl(String token, {required bool isTestMode}) {
    final segment = isTestMode ? 'test' : 'prod';
    return '$_functionsBase/calendar/feed/$segment/$token.ics';
  }

  /// The webcal scheme makes iOS and macOS open the Calendar subscribe sheet
  /// directly instead of downloading the file.
  static String webcalUrl(String token, {required bool isTestMode}) {
    final https = httpsUrl(token, isTestMode: isTestMode);
    return 'webcal://${https.substring('https://'.length)}';
  }

  static String whatsappShareUrl({
    required String token,
    required String? phoneNumber,
    required bool isTestMode,
  }) {
    final link = httpsUrl(token, isTestMode: isTestMode);
    final message = 'הנה קישור אישי ליומן המשמרות שלך בשבצק:\n$link';
    final recipient = _toInternational(phoneNumber);
    return 'https://wa.me/$recipient?text=${Uri.encodeComponent(message)}';
  }

  /// '050-123-4567' -> '972501234567'. Returns an empty string when there is
  /// no usable number, which makes wa.me open without a preselected chat.
  static String _toInternational(String? phoneNumber) {
    if (phoneNumber == null) return '';
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('972')) return digits;
    if (digits.startsWith('0')) return '972${digits.substring(1)}';
    return digits;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd shavtzak && flutter test test/core/services/calendar_feed_links_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/core/services/calendar_feed_links.dart shavtzak/test/core/services/calendar_feed_links_test.dart
git commit -m "feat(calendar-feed): build https, webcal and WhatsApp feed links"
```

---

### Task 8: Flutter — the subscribe dialog and its entry points

**Files:**
- Create: `shavtzak/lib/presentation/widgets/calendar_feed_dialog.dart`
- Modify: `shavtzak/lib/presentation/screens/user/user_assignments_screen.dart`
- Modify: `shavtzak/lib/presentation/screens/team/team_list_screen.dart`

**Interfaces:**
- Consumes: `DatabaseInterface.ensureCalendarFeedToken` / `rotateCalendarFeedToken` (Task 6), `CalendarFeedLinks` (Task 7), `url_launcher`, `Clipboard` from `package:flutter/services.dart`.
- Produces: `showCalendarFeedDialog(BuildContext context, {required TeamMember member, required bool isAdminView})`.

- [ ] **Step 1: Build the dialog**

Follow the structure of `shavtzak/lib/presentation/widgets/passcode_change_dialog.dart` for how a dialog calls the data layer and reports errors. Requirements:

- Wrap the content in `Directionality(textDirection: TextDirection.rtl)`.
- On open, call `ensureCalendarFeedToken(member.id)` and show a spinner until it returns. On failure show the Hebrew error and a retry button.
- Primary action: a prominent `FilledButton.icon` labelled **"הוסף ליומן"** that launches the `webcal://` URL via `url_launcher`. If `launchUrl` returns `false`, fall back to copying the link and showing a snackbar saying so — desktop browsers frequently have no `webcal` handler.
- Secondary action: **"העתק קישור"**, copying `CalendarFeedLinks.httpsUrl(...)` to the clipboard and confirming with a snackbar.
- An `ExpansionTile` labelled **"איך מוסיפים?"** containing the per-platform Hebrew instructions, and stating plainly that **Google Calendar updates the feed roughly once a day, while Apple Calendar can refresh every 5 minutes**. Members must not be surprised by the latency.
- A short warning that the link is personal and should not be forwarded.
- When `isAdminView` is true, additionally show **"שלח בוואטסאפ"** (launching the WhatsApp URL) and **"אפס קישור"**, which calls `rotateCalendarFeedToken` behind a confirmation dialog warning that the member's existing subscription will stop updating.

- [ ] **Step 2: Add the member entry point**

In `user_assignments_screen.dart`, add an `IconButton` with `Icons.calendar_month` and tooltip **"הוסף ליומן שלי"** to the screen's existing action row (there is an `IconButton` at line 535 to model it on). It opens the dialog with `isAdminView: false` for the currently authenticated member, read from `UserSelectionBloc`.

- [ ] **Step 3: Add the admin entry point**

In `team_list_screen.dart`, add a calendar action to the team-member modal that opens the same dialog with `isAdminView: true` for the selected member.

- [ ] **Step 4: Verify**

Run: `cd shavtzak && flutter analyze && flutter test`
Expected: zero **new** analyzer findings; all tests pass.

- [ ] **Step 5: Manual smoke test**

Do not run the app yourself — hand it to the owner with this checklist:

1. In `/test`, open `/user/assignments` and tap "הוסף ליומן שלי". A link appears.
2. Copy the link and open it in a browser — it downloads a `.ics` file containing that member's shifts and no one else's.
3. Subscribe in Apple Calendar (or Google Calendar → Other calendars → From URL). Shifts appear with the התייצבות and מופע blocks at the right times.
4. Unassign the member from an event in the app, then force a refresh — the entry disappears.
5. From the admin team list, send the link to a member over WhatsApp.
6. Rotate the token and confirm the old URL now returns 404.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation
git commit -m "feat(calendar-feed): subscribe dialog with member and admin entry points"
```

---

## Deployment — owner-run, and the order matters

**No subagent deploys anything.** Every task builds, type-checks and unit-tests locally.

**Deploy functions BEFORE merging the branch.** The Flutter web app auto-deploys on merge to `main` (`.github/workflows/web.yml`); Cloud Functions never do. So merging first would put a web client that calls `teamMember.ensureCalendarFeedToken` in front of a backend that doesn't know the operation, and the subscribe dialog would fail for everyone until the deploy caught up. The reverse order is harmless — the new backend simply goes unused until the web app ships.

```bash
cd "/Users/omerbengal/Documents/Github Projects/Shavtzak"
firebase deploy --only functions
```

Note this pushes all three functions (`api`, `calendarSyncTask`, `calendarJobSweep`) and carries along any unreleased `functions/` commits already on `main` — check what those are before running it.

### Post-deploy verification (owner)

Get a token by opening the subscribe dialog in `/test`, then:

```bash
BASE="https://us-central1-tsevet-shir-shavtzak.cloudfunctions.net/api/calendar/feed"
curl -i "$BASE/test/<token>.ics"                              # 200, text/calendar, BEGIN:VCALENDAR
curl -o /dev/null -w '%{http_code}\n' "$BASE/test/bogus.ics"  # 404
curl -o /dev/null -w '%{http_code}\n' "$BASE/prod/<token>.ics" # 404 — test token must not read prod
```
