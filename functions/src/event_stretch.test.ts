import test from 'node:test';
import assert from 'node:assert/strict';
import {customHoursInterval, parseWallMoment, shiftWallMoment, wallDayKeysTouched} from './event_stretch';

// Minutes on the Israel wall clock since 1970-01-01T00:00, as the module holds them.
const minutes = (iso: string): number => Date.parse(`${iso}:00.000Z`) / 60000;

test('parseWallMoment reads yyyy-MM-ddTHH:mm into wall-clock minutes', () => {
  assert.equal(parseWallMoment('2026-10-25T01:30'), minutes('2026-10-25T01:30'));
  assert.equal(parseWallMoment('2026-12-31T23:59'), minutes('2026-12-31T23:59'));
});

test('parseWallMoment is null for anything else, and never throws', () => {
  for (const value of [
    '2026-02-30T10:00',
    '2026-10-25T24:00',
    '2026-10-25T10:60',
    '2026-10-25T9:00',
    '2026-12-01 17:00',
    '2026-10-25T10:00 ',
    '2026-10-25T10:00:00',
    '',
    null,
    undefined,
    42,
    {},
  ]) {
    assert.equal(parseWallMoment(value), null, JSON.stringify(value));
  }
});

test('customHoursInterval needs both values readable and the end after the start', () => {
  assert.deepEqual(customHoursInterval('2026-12-01T17:00', '2026-12-02T02:00'), {
    start: minutes('2026-12-01T17:00'),
    end: minutes('2026-12-02T02:00'),
  });
  assert.equal(customHoursInterval(null, '2026-12-01T22:00'), null);
  assert.equal(customHoursInterval('2026-12-01T17:00', undefined), null);
  assert.equal(customHoursInterval('2026-12-01 17:00', '2026-12-01T22:00'), null);
  assert.equal(customHoursInterval('2026-12-01T17:00', '2026-12-01T17:00'), null);
  assert.equal(customHoursInterval('2026-12-01T23:00', '2026-12-01T17:00'), null);
});

test('shiftWallMoment moves whole calendar days with the clock unchanged, across the DST change of 2026-10-25', () => {
  assert.equal(shiftWallMoment('2026-10-24T22:00', 2), '2026-10-26T22:00');
  assert.equal(shiftWallMoment('2026-10-26T22:00', -2), '2026-10-24T22:00');
  assert.equal(shiftWallMoment('2026-12-01T17:00', -1), '2026-11-30T17:00');
});

test('shiftWallMoment is null when the value is unreadable', () => {
  assert.equal(shiftWallMoment('2026-12-01 17:00', 1), null);
  assert.equal(shiftWallMoment('', 1), null);
});

test('wallDayKeysTouched runs from the start day to the day of the last minute inside', () => {
  assert.deepEqual(wallDayKeysTouched({start: minutes('2026-10-27T18:00'), end: minutes('2026-10-28T00:00')}), [
    '2026-10-27',
    '2026-10-27',
  ]);
  assert.deepEqual(wallDayKeysTouched({start: minutes('2026-10-27T18:00'), end: minutes('2026-10-28T00:01')}), [
    '2026-10-27',
    '2026-10-28',
  ]);
});
