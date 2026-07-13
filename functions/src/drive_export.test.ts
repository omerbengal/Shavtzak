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

test('per-event export suffixes a member who is booked in another event the same day', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a3', data: {eventId: 'summer', teamMemberId: 'm2', roleType: 'medic'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      evening: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן', m2: 'דנה לוי'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    // Only 'summer' is exported — the mark still names the event that is NOT
    // in the file, because it describes the person's real calendar.
    selectedEventIds: ['summer'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), [
    'דנה לוי',
    'יוסי כהן (משובץ גם במופע ערב)',
  ]);
});

test('per-event export comma-joins several same-day events, sorted by date then name', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'anchor', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'later', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a3', data: {eventId: 'sooner', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      anchor: {
        name: 'עוגן',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-14T00:00:00.000Z'),
      },
      later: {
        name: 'טקס',
        startDate: new Date('2026-07-14T00:00:00.000Z'),
        endDate: new Date('2026-07-14T00:00:00.000Z'),
      },
      sooner: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['anchor'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), [
    'יוסי כהן (משובץ גם במופע ערב, טקס)',
  ]);
});

test('per-event export does not suffix when the other event is on a different day', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'nextDay', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      nextDay: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-13T00:00:00.000Z'),
        endDate: new Date('2026-07-13T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['summer'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), ['יוסי כהן']);
});

test('per-event export never counts a deactivated event as the other event', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'onHold', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      onHold: {
        name: 'אירוע מוקפא',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
        isDeactivated: true,
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['summer'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), ['יוסי כהן']);
});

test('per-event export lists the other event once when the member holds two roles in it', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a3', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'commander'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      evening: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש', commander: 'מפקד אירוע'},
    roleSortOrders: {medic: 0, commander: 1},
    mode: 'perEvent',
    selectedEventIds: ['summer'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), [
    'יוסי כהן (משובץ גם במופע ערב)',
  ]);
});

test('per-person export never suffixes the member name', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      evening: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perPerson',
    selectedEventIds: [],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), ['יוסי כהן', 'יוסי כהן']);
});

test('per-event export finds the other event among ALL events, including one that already ended', () => {
  // The only test that tells the `allEventsData` pool apart from the row-scoped
  // `futureEventsData`: 'ended' finished BEFORE `now`, so it is absent from the
  // future-filtered map and can only be found in the full one. Every other test
  // dates its events on or after `now`, where the two pools are identical.
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'anchor', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'ended', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      // Still running on `now` (10–14 July), so it survives the future filter
      // and can be exported.
      anchor: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-10T00:00:00.000Z'),
        endDate: new Date('2026-07-14T00:00:00.000Z'),
      },
      // Over and done with, but it shared 10 July with the anchor.
      ended: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-10T00:00:00.000Z'),
        endDate: new Date('2026-07-10T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['anchor'],
    now: new Date('2026-07-12T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), [
    'יוסי כהן (משובץ גם במופע ערב)',
  ]);
});

test('per-event export sorts on the clean name, so the mark never reorders same-named members', () => {
  // Two DIFFERENT people share a display name and sit in the same event and role,
  // so the perEvent sort runs out of tiebreaks and falls through to `teamMember`.
  // Only m1 is double-booked. The comparator must see the CLEAN names, which tie
  // and leave the rows in input order. Decorating the row object instead of the
  // projection would fold the suffix into the sort key: ' (' outranks nothing, so
  // the plain namesake would jump ahead of the marked one and the export order
  // would silently change.
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'summer', teamMemberId: 'm2', roleType: 'medic'}},
      {id: 'a3', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      evening: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן', m2: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['summer'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), [
    'יוסי כהן (משובץ גם במופע ערב)',
    'יוסי כהן',
  ]);
});
