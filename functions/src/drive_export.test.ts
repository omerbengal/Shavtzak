import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DriveExportValidationError,
  __testSerializeAssignmentsOnly,
} from './drive_export';

function withUtcTimezone<T>(callback: () => T): T {
  const originalTimezone = process.env.TZ;
  process.env.TZ = 'UTC';
  try {
    return callback();
  } finally {
    if (originalTimezone == null) {
      delete process.env.TZ;
    } else {
      process.env.TZ = originalTimezone;
    }
  }
}

test('per-person assignments export includes only events whose endDate is today or later', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a-past', data: {eventId: 'past', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a-today', data: {eventId: 'today', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a-future', data: {eventId: 'future', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      past: {name: 'Past', startDate: new Date('2026-05-01T00:00:00.000Z'), endDate: new Date('2026-05-02T00:00:00.000Z')},
      today: {name: 'Today', startDate: new Date('2026-05-03T00:00:00.000Z'), endDate: new Date('2026-05-03T00:00:00.000Z')},
      future: {name: 'Future', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z')},
    },
    memberNames: {m1: 'אדם אחד'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perPerson',
    selectedEventIds: [],
    now: new Date('2026-05-03T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[2]), ['Today', 'Future']);
});

test('per-person assignments export treats Israel-local endDate as today', () => {
  const sheet = withUtcTimezone(() =>
    __testSerializeAssignmentsOnly({
      assignments: [
        {id: 'a-israel-today', data: {eventId: 'israel-today', teamMemberId: 'm1', roleType: 'medic'}},
      ],
      eventsData: {
        'israel-today': {
          name: 'Israel Local Today',
          startDate: new Date('2026-05-02T21:00:00.000Z'),
          endDate: new Date('2026-05-02T21:00:00.000Z'),
        },
      },
      memberNames: {m1: 'אדם אחד'},
      roleHebrewNames: {medic: 'חובש'},
      roleSortOrders: {medic: 0},
      mode: 'perPerson',
      selectedEventIds: [],
      now: new Date('2026-05-03T12:00:00.000+03:00'),
    }),
  );

  assert.deepEqual(sheet.rows.map((row) => [row[2], row[3], row[4]]), [
    ['Israel Local Today', '03/05/2026', ''],
  ]);
});

test('per-person assignments export sorts same Israel date by start time', () => {
  const sheet = withUtcTimezone(() =>
    __testSerializeAssignmentsOnly({
      assignments: [
        {id: 'evening', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'medic'}},
        {id: 'morning', data: {eventId: 'morning', teamMemberId: 'm1', roleType: 'medic'}},
      ],
      eventsData: {
        evening: {
          name: 'Evening',
          startDate: new Date('2026-05-02T21:00:00.000Z'),
          endDate: new Date('2026-05-02T21:00:00.000Z'),
          startTime: '18:00',
        },
        morning: {
          name: 'Morning',
          startDate: new Date('2026-05-03T00:00:00.000Z'),
          endDate: new Date('2026-05-03T00:00:00.000Z'),
          startTime: '10:00',
        },
      },
      memberNames: {m1: 'אדם אחד'},
      roleHebrewNames: {medic: 'חובש'},
      roleSortOrders: {medic: 0},
      mode: 'perPerson',
      selectedEventIds: [],
      now: new Date('2026-05-03T00:00:00.000+03:00'),
    }),
  );

  assert.deepEqual(sheet.rows.map((row) => row[2]), ['Morning', 'Evening']);
});

test('per-person assignments export sorts by person then event date', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'late', data: {eventId: 'e2', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'other', data: {eventId: 'e1', teamMemberId: 'm2', roleType: 'medic'}},
      {id: 'early', data: {eventId: 'e1', teamMemberId: 'm1', roleType: 'paramedic'}},
    ],
    eventsData: {
      e1: {name: 'Early', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z'), startTime: '10:00'},
      e2: {name: 'Late', startDate: new Date('2026-05-05T00:00:00.000Z'), endDate: new Date('2026-05-05T00:00:00.000Z'), startTime: '10:00'},
    },
    memberNames: {m1: 'אדם א', m2: 'בני ב'},
    roleHebrewNames: {medic: 'חובש', paramedic: 'פרמדיק'},
    roleSortOrders: {paramedic: 0, medic: 1},
    mode: 'perPerson',
    selectedEventIds: [],
    now: new Date('2026-05-03T00:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => [row[0], row[2], row[1]]), [
    ['אדם א', 'Early', 'פרמדיק'],
    ['אדם א', 'Late', 'חובש'],
    ['בני ב', 'Early', 'חובש'],
  ]);
});

test('per-event assignments export filters selected events and sorts by event, role order, then person', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'not-selected', data: {eventId: 'e3', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'role-second-a', data: {eventId: 'e1', teamMemberId: 'm2', roleType: 'medic'}},
      {id: 'role-first', data: {eventId: 'e1', teamMemberId: 'm3', roleType: 'paramedic'}},
      {id: 'role-second-b', data: {eventId: 'e1', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'later-event', data: {eventId: 'e2', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      e1: {name: 'First Event', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z'), startTime: '18:00'},
      e2: {name: 'Second Event', startDate: new Date('2026-05-05T00:00:00.000Z'), endDate: new Date('2026-05-05T00:00:00.000Z'), startTime: '18:00'},
      e3: {name: 'Ignored Event', startDate: new Date('2026-05-06T00:00:00.000Z'), endDate: new Date('2026-05-06T00:00:00.000Z'), startTime: '18:00'},
    },
    memberNames: {m1: 'אדם א', m2: 'בני ב', m3: 'גדי ג'},
    roleHebrewNames: {medic: 'חובש', paramedic: 'פרמדיק'},
    roleSortOrders: {paramedic: 0, medic: 1},
    mode: 'perEvent',
    selectedEventIds: ['e1', 'e2'],
    now: new Date('2026-05-03T00:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => [row[2], row[1], row[0]]), [
    ['First Event', 'פרמדיק', 'גדי ג'],
    ['First Event', 'חובש', 'אדם א'],
    ['First Event', 'חובש', 'בני ב'],
    ['Second Event', 'חובש', 'אדם א'],
  ]);
});

test('per-event assignments export rejects selected past or nonexistent event IDs', () => {
  let error: unknown;
  try {
    __testSerializeAssignmentsOnly({
      assignments: [
        {id: 'future-assignment', data: {eventId: 'future', teamMemberId: 'm1', roleType: 'medic'}},
        {id: 'past-assignment', data: {eventId: 'past', teamMemberId: 'm1', roleType: 'medic'}},
      ],
      eventsData: {
        future: {name: 'Future', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z')},
        past: {name: 'Past', startDate: new Date('2026-05-01T00:00:00.000Z'), endDate: new Date('2026-05-01T00:00:00.000Z')},
      },
      memberNames: {m1: 'אדם אחד'},
      roleHebrewNames: {medic: 'חובש'},
      roleSortOrders: {medic: 0},
      mode: 'perEvent',
      selectedEventIds: ['future', 'past', 'missing', 'past'],
      now: new Date('2026-05-03T00:00:00.000Z'),
    });
  } catch (caughtError) {
    error = caughtError;
  }

  assert.ok(error instanceof DriveExportValidationError);
  assert.equal(error.message, 'Selected future event IDs are invalid: past, missing');
});
