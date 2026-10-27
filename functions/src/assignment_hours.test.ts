import test from 'node:test';
import assert from 'node:assert/strict';
import {
  findSharedHoursViolations,
  hoursAfterWrites,
  inheritedHours,
  validateCustomHoursPair,
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

test('hoursAfterWrites: an update takes its event and member from the payload', () => {
  const live = [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00')];
  assert.deepEqual(hoursAfterWrites({live, updates: [{id: 'a1', doc: doc('e2', 'n')}]}), [
    row('a1', 'n', '2026-12-01T17:00', '2026-12-02T01:00', 'e2'),
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
