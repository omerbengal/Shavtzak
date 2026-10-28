import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {
  eventTimesChanged,
  findSharedHoursViolations,
  hoursAfterWrites,
  inheritedHours,
  planEventHoursResolution,
  settleOccupantChangeHours,
  validateCustomHoursPair,
  type HoursResolution,
  type HoursRow,
} from './assignment_hours';

const row = (
  id: string,
  teamMemberId: string,
  customStartAt: string | null,
  customEndAt: string | null,
  eventId = 'e',
): HoursRow => ({id, eventId, teamMemberId, customStartAt, customEndAt});

// validateCustomHoursPair

test('validateCustomHoursPair: no values is none', () => {
  assert.equal(validateCustomHoursPair(null, undefined), 'none');
  assert.equal(validateCustomHoursPair(undefined, undefined), 'none');
  assert.equal(validateCustomHoursPair(null, null), 'none');
});

test('validateCustomHoursPair: one value only is incomplete', () => {
  assert.equal(validateCustomHoursPair('2026-12-01T17:00', null), 'incomplete');
  assert.equal(validateCustomHoursPair(undefined, '2026-12-01T17:00'), 'incomplete');
});

test('validateCustomHoursPair: an unreadable value is incomplete', () => {
  assert.equal(validateCustomHoursPair('2026-12-01 17:00', '2026-12-02T01:00'), 'incomplete');
  assert.equal(validateCustomHoursPair('2026-12-01T17:00', '2026-02-30T01:00'), 'incomplete');
  assert.equal(validateCustomHoursPair('', '2026-12-02T01:00'), 'incomplete');
  assert.equal(validateCustomHoursPair(17, '2026-12-02T01:00'), 'incomplete');
});

test('validateCustomHoursPair: an end not after the start is order', () => {
  assert.equal(validateCustomHoursPair('2026-12-01T17:00', '2026-12-01T17:00'), 'order');
  assert.equal(validateCustomHoursPair('2026-12-01T17:00', '2026-12-01T16:59'), 'order');
});

test('validateCustomHoursPair: a readable pair with the end after the start is ok', () => {
  assert.equal(validateCustomHoursPair('2026-12-01T17:00', '2026-12-02T01:00'), 'ok');
});

// findSharedHoursViolations

test('findSharedHoursViolations: one role with hours and one without is a violation', () => {
  const rows = [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00'), row('a2', 'm', null, null)];
  assert.deepEqual(findSharedHoursViolations(rows, new Set()), [{eventId: 'e', teamMemberId: 'm'}]);
});

test('findSharedHoursViolations: an exempt member is never a violation', () => {
  const rows = [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00'), row('a2', 'm', null, null)];
  assert.deepEqual(findSharedHoursViolations(rows, new Set(['m'])), []);
});

test('findSharedHoursViolations: equal hours on every role is fine', () => {
  const rows = [
    row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00'),
    row('a2', 'm', '2026-12-01T17:00', '2026-12-02T01:00'),
  ];
  assert.deepEqual(findSharedHoursViolations(rows, new Set()), []);
});

test('findSharedHoursViolations: only groups holding a touched row count when touchedIds is given', () => {
  const rows = [
    row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00'),
    row('a2', 'm', null, null),
    row('b1', 'n', null, null),
  ];
  assert.deepEqual(findSharedHoursViolations(rows, new Set(), new Set(['b1'])), []);
  assert.deepEqual(findSharedHoursViolations(rows, new Set(), new Set(['a2'])), [
    {eventId: 'e', teamMemberId: 'm'},
  ]);
});

test('findSharedHoursViolations: different members, or one member in different events, never clash', () => {
  const rows = [
    row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00'),
    row('a2', 'n', null, null),
    row('a3', 'm', null, null, 'other-event'),
  ];
  assert.deepEqual(findSharedHoursViolations(rows, new Set()), []);
});

test('findSharedHoursViolations: a different end alone is a violation', () => {
  const rows = [
    row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00'),
    row('a2', 'm', '2026-12-01T17:00', '2026-12-02T02:00'),
  ];
  assert.deepEqual(findSharedHoursViolations(rows, new Set()), [{eventId: 'e', teamMemberId: 'm'}]);
});

// inheritedHours

test('inheritedHours returns the member\'s valid pair in that event and skips unreadable hours', () => {
  const rows = [
    row('x', 'm', '2026-12-05T10:00', '2026-12-05T12:00', 'other-event'),
    row('y', 'n', '2026-12-01T09:00', '2026-12-01T10:00'),
    row('a1', 'm', '2026-12-01 17:00', '2026-12-02T01:00'),
    row('a2', 'm', '2026-12-01T17:00', '2026-12-01T16:00'),
    row('a3', 'm', null, null),
    row('a4', 'm', '2026-12-01T17:00', '2026-12-02T01:00'),
  ];
  assert.deepEqual(inheritedHours(rows, 'e', 'm'), {
    customStartAt: '2026-12-01T17:00',
    customEndAt: '2026-12-02T01:00',
  });
});

test('inheritedHours is null when the member has no valid hours in that event', () => {
  const rows = [row('a1', 'm', null, null), row('x', 'm', '2026-12-05T10:00', '2026-12-05T12:00', 'other-event')];
  assert.equal(inheritedHours(rows, 'e', 'm'), null);
});

// hoursAfterWrites: the rows once a batch of writes applies.

const doc = (eventId: string, teamMemberId: string, hours?: {customStartAt: unknown; customEndAt: unknown}) => ({
  eventId,
  teamMemberId,
  ...(hours ?? {}),
});

test('hoursAfterWrites: an update without the keys keeps the stored hours', () => {
  const live = [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00')];
  assert.deepEqual(hoursAfterWrites({live, updates: [{id: 'a1', doc: doc('e', 'm')}]}), [
    row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00'),
  ]);
});

test('hoursAfterWrites: an update with explicit nulls clears the hours', () => {
  const live = [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00')];
  assert.deepEqual(
    hoursAfterWrites({
      live,
      updates: [{id: 'a1', doc: doc('e', 'm', {customStartAt: null, customEndAt: null})}],
    }),
    [row('a1', 'm', null, null)],
  );
});

test('hoursAfterWrites: an update takes its event and member from the payload, never the previous occupant\'s hours', () => {
  // An old build's update carries no hours keys; settled first (as both
  // assignment.update and saveBatch do), the moved row keeps nothing of m's.
  const stored = row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00');
  const settled = settleOccupantChangeHours({
    id: 'a1',
    doc: doc('e2', 'n'),
    stored,
    liveBefore: [stored],
    exempt: false,
  });
  assert.deepEqual(hoursAfterWrites({live: [stored], updates: [{id: 'a1', doc: settled}]}), [
    row('a1', 'n', null, null, 'e2'),
  ]);
});

test('hoursAfterWrites: deletes go, creates arrive with their own hours (none when absent)', () => {
  const live = [row('a1', 'm', null, null), row('a2', 'n', null, null)];
  assert.deepEqual(
    hoursAfterWrites({
      live,
      deletes: ['a2'],
      creates: [
        {id: 'c1', doc: doc('e', 'p', {customStartAt: '2026-12-01T17:00', customEndAt: '2026-12-02T01:00'})},
        {id: 'c2', doc: doc('e', 'q')},
      ],
    }),
    [
      row('a1', 'm', null, null),
      row('c1', 'p', '2026-12-01T17:00', '2026-12-02T01:00'),
      row('c2', 'q', null, null),
    ],
  );
});

test('hoursAfterWrites: an update of an unknown row overlays nothing', () => {
  assert.deepEqual(
    hoursAfterWrites({live: [], updates: [{id: 'a1', doc: doc('e', 'm')}]}),
    [row('a1', 'm', null, null)],
  );
});

// settleOccupantChangeHours: an old build's update (no hours keys) that
// changes the member or the event is settled like a create.

const H = {customStartAt: '2026-12-01T17:00', customEndAt: '2026-12-02T01:00'};
const J = {customStartAt: '2026-12-01T18:00', customEndAt: '2026-12-01T23:00'};
const hoursRow = (id: string, teamMemberId: string, hours: typeof H | null, eventId = 'e') =>
  row(id, teamMemberId, hours?.customStartAt ?? null, hours?.customEndAt ?? null, eventId);

/** Settles every update against the rows as stored before the batch, then projects. */
function settleAndProject(
  live: HoursRow[],
  updates: Array<{id: string; doc: Record<string, unknown>}>,
  exemptMemberIds: ReadonlySet<string> = new Set(),
): HoursRow[] {
  const settled = updates.map(({id, doc: sent}) => ({
    id,
    doc: settleOccupantChangeHours({
      id,
      doc: sent,
      stored: live.find((stored) => stored.id === id) ?? null,
      liveBefore: live,
      exempt: exemptMemberIds.has(String(sent['teamMemberId'])),
    }),
  }));
  return hoursAfterWrites({live, updates: settled});
}

test('settleOccupantChangeHours: (a) replacing X by Y, who holds nothing else in the event, clears the hours', () => {
  const live = [hoursRow('a1', 'x', H)];
  assert.deepEqual(
    settleOccupantChangeHours({id: 'a1', doc: doc('e', 'y'), stored: live[0], liveBefore: live, exempt: false}),
    {...doc('e', 'y'), customStartAt: null, customEndAt: null},
  );
  assert.deepEqual(settleAndProject(live, [{id: 'a1', doc: doc('e', 'y')}]), [hoursRow('a1', 'y', null)]);
});

test('settleOccupantChangeHours: (b) replacing X by Y, who has hours J on another role, gives J', () => {
  const live = [hoursRow('a1', 'x', H), hoursRow('a2', 'y', J)];
  assert.deepEqual(
    settleOccupantChangeHours({id: 'a1', doc: doc('e', 'y'), stored: live[0], liveBefore: live, exempt: false}),
    {...doc('e', 'y'), ...J},
  );
  const after = settleAndProject(live, [{id: 'a1', doc: doc('e', 'y')}]);
  assert.deepEqual(after, [hoursRow('a1', 'y', J), hoursRow('a2', 'y', J)]);
  assert.deepEqual(findSharedHoursViolations(after, new Set(), new Set(['a1'])), []);
});

test('settleOccupantChangeHours: (c) an old build swapping X and Y in one batch leaves each their own hours', () => {
  // X also holds a third role, so the check sees a group of two after the swap.
  const live = [hoursRow('a1', 'x', H), hoursRow('a2', 'y', J), hoursRow('a3', 'x', H)];
  const after = settleAndProject(live, [
    {id: 'a1', doc: doc('e', 'y')},
    {id: 'a2', doc: doc('e', 'x')},
  ]);
  assert.deepEqual(after, [hoursRow('a1', 'y', J), hoursRow('a2', 'x', H), hoursRow('a3', 'x', H)]);
  assert.deepEqual(findSharedHoursViolations(after, new Set(), new Set(['a1', 'a2'])), []);
});

test('settleOccupantChangeHours: (d) the same member and event without the keys keeps the stored hours', () => {
  const live = [hoursRow('a1', 'x', H)];
  const sent = {...doc('e', 'x'), notes: 'הערה'};
  assert.deepEqual(
    settleOccupantChangeHours({id: 'a1', doc: sent, stored: live[0], liveBefore: live, exempt: false}),
    sent,
  );
  assert.deepEqual(settleAndProject(live, [{id: 'a1', doc: sent}]), [hoursRow('a1', 'x', H)]);
});

test('settleOccupantChangeHours: (e) an exempt incoming member gets no hours, even with hours elsewhere', () => {
  const live = [hoursRow('a1', 'x', H), hoursRow('a2', 'pool', J)];
  assert.deepEqual(
    settleOccupantChangeHours({id: 'a1', doc: doc('e', 'pool'), stored: live[0], liveBefore: live, exempt: true}),
    {...doc('e', 'pool'), customStartAt: null, customEndAt: null},
  );
  assert.deepEqual(settleAndProject(live, [{id: 'a1', doc: doc('e', 'pool')}], new Set(['pool'])), [
    hoursRow('a1', 'pool', null),
    hoursRow('a2', 'pool', J),
  ]);
});

test('settleOccupantChangeHours: (f) an update that carries the keys is written as sent', () => {
  const live = [hoursRow('a1', 'x', H), hoursRow('a2', 'y', J)];
  for (const sent of [doc('e', 'y', H), doc('e', 'y', {customStartAt: null, customEndAt: null})]) {
    assert.equal(
      settleOccupantChangeHours({id: 'a1', doc: sent, stored: live[0], liveBefore: live, exempt: false}),
      sent,
    );
  }
});

test('settleOccupantChangeHours: moving a row to another event takes the member\'s hours there, else none', () => {
  const live = [hoursRow('a1', 'x', H), hoursRow('b1', 'x', J, 'e2')];
  assert.deepEqual(
    settleOccupantChangeHours({id: 'a1', doc: doc('e2', 'x'), stored: live[0], liveBefore: live, exempt: false}),
    {...doc('e2', 'x'), ...J},
  );
  assert.deepEqual(
    settleOccupantChangeHours({id: 'a1', doc: doc('e3', 'x'), stored: live[0], liveBefore: live, exempt: false}),
    {...doc('e3', 'x'), customStartAt: null, customEndAt: null},
  );
});

test('settleOccupantChangeHours: the row itself never counts as the incoming member\'s other row', () => {
  // A stale stored row listed under the incoming member must not hand its own
  // hours back: only the member's OTHER rows count.
  const stored = hoursRow('a1', 'x', H);
  assert.deepEqual(
    settleOccupantChangeHours({
      id: 'a1',
      doc: doc('e', 'y'),
      stored,
      liveBefore: [hoursRow('a1', 'y', H)],
      exempt: false,
    }),
    {...doc('e', 'y'), customStartAt: null, customEndAt: null},
  );
});

test('settleOccupantChangeHours: an update of a row not stored is written as sent', () => {
  const sent = doc('e', 'y');
  assert.equal(
    settleOccupantChangeHours({id: 'a1', doc: sent, stored: null, liveBefore: [], exempt: false}),
    sent,
  );
});

// eventTimesChanged: the stored event against the one a save writes.

// Events store each day as the UTC instant of Israel midnight (UTC+2 in
// December): 2026-11-30T22:00Z is 1 December in Israel.
const israelMidnight = (iso: string) => Timestamp.fromDate(new Date(iso));

const storedEvent = (): Record<string, unknown> => ({
  name: 'הופעה',
  location: 'תל אביב',
  startDate: israelMidnight('2026-11-30T22:00:00Z'),
  endDate: israelMidnight('2026-11-30T22:00:00Z'),
  assemblyTime: '17:00',
  startTime: '19:00',
  actualShowStartTime: '19:30',
  endTime: '22:00',
  teamEndTime: '23:00',
});

test('eventTimesChanged: only teamEndTime changed is a change', () => {
  assert.equal(eventTimesChanged(storedEvent(), {...storedEvent(), teamEndTime: '23:30'}), true);
});

test('eventTimesChanged: every other time field counts too', () => {
  for (const field of ['assemblyTime', 'startTime', 'actualShowStartTime', 'endTime']) {
    assert.equal(eventTimesChanged(storedEvent(), {...storedEvent(), [field]: '20:15'}), true, field);
  }
});

test('eventTimesChanged: only the name or the location changed is no change', () => {
  assert.equal(eventTimesChanged(storedEvent(), {...storedEvent(), name: 'הופעה חדשה'}), false);
  assert.equal(eventTimesChanged(storedEvent(), {...storedEvent(), location: 'חיפה'}), false);
});

test('eventTimesChanged: the start date moved by one day is a change', () => {
  assert.equal(
    eventTimesChanged(storedEvent(), {...storedEvent(), startDate: israelMidnight('2026-12-01T22:00:00Z')}),
    true,
  );
});

test('eventTimesChanged: the end date moved by one day is a change', () => {
  assert.equal(
    eventTimesChanged(storedEvent(), {...storedEvent(), endDate: israelMidnight('2026-12-01T22:00:00Z')}),
    true,
  );
});

test('eventTimesChanged: dates compare by Israel day, not by instant', () => {
  // 30 November 22:00Z and 1 December 10:00Z are both 1 December in Israel,
  // while 30 November 21:59Z is still 30 November there.
  assert.equal(
    eventTimesChanged(storedEvent(), {...storedEvent(), startDate: Timestamp.fromDate(new Date('2026-12-01T10:00:00Z'))}),
    false,
  );
  assert.equal(
    eventTimesChanged(storedEvent(), {...storedEvent(), startDate: Timestamp.fromDate(new Date('2026-11-30T21:59:00Z'))}),
    true,
  );
});

test('eventTimesChanged: an absent time is the empty string, and times are trimmed', () => {
  const before = {...storedEvent(), actualShowStartTime: undefined};
  assert.equal(eventTimesChanged(before, {...storedEvent(), actualShowStartTime: ''}), false);
  assert.equal(eventTimesChanged(storedEvent(), {...storedEvent(), startTime: ' 19:00 '}), false);
});

// planEventHoursResolution: the hours an event save writes when its times change.

const HOURS: [string, string] = ['2026-12-01T17:00', '2026-12-02T01:00'];
const NEW_HOURS: [string, string] = ['2026-12-02T17:00', '2026-12-03T01:00'];

const resolution = (
  assignmentId: string,
  customStartAt: string | null,
  customEndAt: string | null,
): HoursResolution => ({assignmentId, customStartAt, customEndAt});

test('planEventHoursResolution: times unchanged ignores hours and resolutions (an old client edits a name)', () => {
  const live = [row('a1', 'm', ...HOURS), row('a2', 'n', null, null)];
  assert.deepEqual(
    planEventHoursResolution({timesChanged: false, live, resolutions: [], exemptMemberIds: new Set()}),
    {ok: true, updates: []},
  );
  assert.deepEqual(
    planEventHoursResolution({
      timesChanged: false,
      live,
      resolutions: [resolution('a1', '2026-12-01T17:00', null)],
      exemptMemberIds: new Set(),
    }),
    {ok: true, updates: []},
  );
});

test('planEventHoursResolution: times changed with no hours in the event needs no resolution (an old client)', () => {
  const live = [row('a1', 'm', null, null), row('a2', 'n', null, null)];
  assert.deepEqual(
    planEventHoursResolution({timesChanged: true, live, resolutions: [], exemptMemberIds: new Set()}),
    {ok: true, updates: []},
  );
});

test('planEventHoursResolution: times changed and a row with hours left unresolved is uncovered', () => {
  const live = [row('a1', 'm', ...HOURS), row('a2', 'n', null, null)];
  assert.deepEqual(
    planEventHoursResolution({timesChanged: true, live, resolutions: [], exemptMemberIds: new Set()}),
    {ok: false, reason: 'uncovered'},
  );
});

test('planEventHoursResolution: stored hours that cannot be read still need a resolution', () => {
  const live = [row('a1', 'm', '2026-12-01 17:00', null)];
  assert.deepEqual(
    planEventHoursResolution({timesChanged: true, live, resolutions: [], exemptMemberIds: new Set()}),
    {ok: false, reason: 'uncovered'},
  );
});

test('planEventHoursResolution: a resolution for every row with hours gives exactly those updates', () => {
  const live = [row('a1', 'm', ...HOURS), row('b1', 'n', ...HOURS), row('c1', 'p', null, null)];
  const resolutions = [resolution('a1', ...NEW_HOURS), resolution('b1', null, null)];
  assert.deepEqual(
    planEventHoursResolution({timesChanged: true, live, resolutions, exemptMemberIds: new Set()}),
    {ok: true, updates: resolutions},
  );
});

test('planEventHoursResolution: a resolution for an assignment no longer in the event is dropped', () => {
  const live = [row('a1', 'm', ...HOURS)];
  const kept = resolution('a1', ...NEW_HOURS);
  assert.deepEqual(
    planEventHoursResolution({
      timesChanged: true,
      live,
      resolutions: [kept, resolution('deleted', ...NEW_HOURS)],
      exemptMemberIds: new Set(),
    }),
    {ok: true, updates: [kept]},
  );
});

test('planEventHoursResolution: of two resolutions for one assignment, the later is the one written', () => {
  const live = [row('a1', 'm', ...HOURS)];
  const later = resolution('a1', null, null);
  assert.deepEqual(
    planEventHoursResolution({
      timesChanged: true,
      live,
      resolutions: [resolution('a1', ...NEW_HOURS), later],
      exemptMemberIds: new Set(),
    }),
    {ok: true, updates: [later]},
  );
});

test('planEventHoursResolution: a resolution with half a pair is invalid', () => {
  const live = [row('a1', 'm', ...HOURS)];
  assert.deepEqual(
    planEventHoursResolution({
      timesChanged: true,
      live,
      resolutions: [resolution('a1', '2026-12-01T17:00', null)],
      exemptMemberIds: new Set(),
    }),
    {ok: false, reason: 'invalid'},
  );
});

test('planEventHoursResolution: a resolution whose end is not after its start is invalid', () => {
  const live = [row('a1', 'm', ...HOURS)];
  assert.deepEqual(
    planEventHoursResolution({
      timesChanged: true,
      live,
      resolutions: [resolution('a1', '2026-12-02T01:00', '2026-12-01T17:00')],
      exemptMemberIds: new Set(),
    }),
    {ok: false, reason: 'invalid'},
  );
});

test('planEventHoursResolution: one of a member\'s two rows with hours resolved and the other not is uncovered', () => {
  const live = [row('a1', 'm', ...HOURS), row('a2', 'm', ...HOURS)];
  assert.deepEqual(
    planEventHoursResolution({
      timesChanged: true,
      live,
      resolutions: [resolution('a1', ...NEW_HOURS)],
      exemptMemberIds: new Set(),
    }),
    {ok: false, reason: 'uncovered'},
  );
});

test('planEventHoursResolution: a member\'s two rows resolved to different hours is shared', () => {
  const live = [row('a1', 'm', ...HOURS), row('a2', 'm', ...HOURS)];
  assert.deepEqual(
    planEventHoursResolution({
      timesChanged: true,
      live,
      resolutions: [resolution('a1', ...NEW_HOURS), resolution('a2', ...HOURS)],
      exemptMemberIds: new Set(),
    }),
    {ok: false, reason: 'shared'},
  );
});

test('planEventHoursResolution: resolving one row to hours its unresolved sibling without hours lacks is shared', () => {
  const live = [row('a1', 'm', ...HOURS), row('a2', 'm', null, null)];
  assert.deepEqual(
    planEventHoursResolution({
      timesChanged: true,
      live,
      resolutions: [resolution('a1', ...NEW_HOURS)],
      exemptMemberIds: new Set(),
    }),
    {ok: false, reason: 'shared'},
  );
});

test('planEventHoursResolution: an exempt member may end with different hours on each row', () => {
  const live = [row('a1', 'm', ...HOURS), row('a2', 'm', ...HOURS)];
  const resolutions = [resolution('a1', ...NEW_HOURS), resolution('a2', null, null)];
  assert.deepEqual(
    planEventHoursResolution({timesChanged: true, live, resolutions, exemptMemberIds: new Set(['m'])}),
    {ok: true, updates: resolutions},
  );
});
