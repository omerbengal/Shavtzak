import test from 'node:test';
import assert from 'node:assert/strict';
import {memberHoursCells} from './member_hours_cells';

const oneDay = {
  firstDayKey: '2026-12-10',
  lastDayKey: '2026-12-10',
  assemblyTime: '12:00',
  startTime: '13:00',
  endTime: '22:00',
  teamEndTime: '01:00',
};

test('same-day hours on a one-day event: own arrival, departure into the note', () => {
  assert.deepEqual(memberHoursCells(oneDay, '2026-12-10T14:00', '2026-12-10T23:00'), {
    startDate: '10/12/2026',
    endDate: '',
    assembly: '14:00 (התייצבות צוות 12:00)',
    departureNote: 'יציאה 10.12 23:00 (סיום צוות משוער 11.12 01:00)',
  });
});

test('a middle day of a three-day event carries both event notes on the start date', () => {
  const event = {
    firstDayKey: '2026-12-09',
    lastDayKey: '2026-12-11',
    assemblyTime: '',
    startTime: '',
    endTime: '20:00',
    teamEndTime: '',
  };
  assert.deepEqual(memberHoursCells(event, '2026-12-10T10:00', '2026-12-10T18:00'), {
    startDate: '10/12/2026 (האירוע מ-9.12) (האירוע עד 11.12)',
    endDate: '',
    assembly: '10.12 10:00',
    departureNote: 'יציאה 10.12 18:00 (סיום מופע משוער 11.12 20:00)',
  });
});

test('hours over two days of a longer event fill both date cells', () => {
  const event = {
    firstDayKey: '2026-12-09',
    lastDayKey: '2026-12-11',
    assemblyTime: '17:00',
    startTime: '18:00',
    endTime: '',
    teamEndTime: '23:00',
  };
  assert.deepEqual(memberHoursCells(event, '2026-12-09T18:00', '2026-12-10T02:00'), {
    startDate: '09/12/2026',
    endDate: '10/12/2026 (האירוע עד 11.12)',
    assembly: '18:00 (התייצבות צוות 17:00)',
    departureNote: 'יציאה 10.12 02:00 (סיום צוות משוער 11.12 23:00)',
  });
});

test('a departure at exactly midnight reads as the next day 00:00 and an event without times has no bracket', () => {
  const event = {
    firstDayKey: '2026-12-10',
    lastDayKey: '2026-12-10',
    assemblyTime: '',
    startTime: '',
    endTime: '',
    teamEndTime: '',
  };
  assert.deepEqual(memberHoursCells(event, '2026-12-10T20:00', '2026-12-11T00:00'), {
    startDate: '10/12/2026',
    endDate: '',
    assembly: '20:00',
    departureNote: 'יציאה 11.12 00:00',
  });
});

test('an event without readable days gives no cells instead of throwing', () => {
  assert.equal(
    memberHoursCells({...oneDay, firstDayKey: '', lastDayKey: ''}, '2026-12-10T14:00', '2026-12-10T23:00'),
    null,
  );
});

test('unreadable or backwards hours give no cells', () => {
  assert.equal(memberHoursCells(oneDay, undefined, undefined), null);
  assert.equal(memberHoursCells(oneDay, '2026-12-10T25:00', '2026-12-10T23:00'), null);
  assert.equal(memberHoursCells(oneDay, '2026-12-10T23:00', '2026-12-10T14:00'), null);
});
