import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {
  __testMemberAvailableForEvent as memberAvailableForEvent,
  __testNormalizeDayInIsrael as normalizeDayInIsrael,
} from './index';

// All tests pin TZ=UTC to mirror the deployed Cloud Function environment.
// The fix should be TZ-independent, but pinning makes the assertions about
// "naive string parse" inputs (which depend on local TZ in the JS spec)
// deterministic.
function withUtcTimezone<T>(callback: () => T): T {
  const original = process.env.TZ;
  process.env.TZ = 'UTC';
  try {
    return callback();
  } finally {
    if (original == null) {
      delete process.env.TZ;
    } else {
      process.env.TZ = original;
    }
  }
}

type Mutable = Record<string, unknown>;

function buildMember(overrides: Mutable = {}): Mutable {
  return {
    isActive: true,
    isArchived: false,
    isPermanent: true,
    allowMultipleAssignments: false,
    constraints: [],
    availableEventIds: [],
    roleCapabilities: {},
    ...overrides,
  };
}

// Default event mirrors production "אירוע הוקרה בית הנשיא":
// startDate stored as 2026-06-07T21:00Z, which is midnight on June 8 in IDT.
function buildEvent(overrides: Mutable = {}): Mutable {
  return {
    id: 'evt-test',
    startDate: Timestamp.fromDate(new Date('2026-06-07T21:00:00.000Z')),
    endDate: Timestamp.fromDate(new Date('2026-06-07T21:00:00.000Z')),
    assemblyTime: '16:00',
    startTime: '17:00',
    endTime: '20:30',
    ...overrides,
  };
}

test('normalizeDayInIsrael: summer (IDT, UTC+3) Israel midnight → Israel calendar day', () => {
  withUtcTimezone(() => {
    const result = normalizeDayInIsrael(new Date('2026-06-07T21:00:00.000Z'));
    assert.equal(result.getUTCFullYear(), 2026);
    assert.equal(result.getUTCMonth(), 5); // June (0-indexed)
    assert.equal(result.getUTCDate(), 8);
  });
});

test('normalizeDayInIsrael: winter (IST, UTC+2) Israel midnight → Israel calendar day', () => {
  withUtcTimezone(() => {
    // 22:00Z on Jan 14 = midnight on Jan 15 in Israel winter
    const result = normalizeDayInIsrael(new Date('2026-01-14T22:00:00.000Z'));
    assert.equal(result.getUTCFullYear(), 2026);
    assert.equal(result.getUTCMonth(), 0);
    assert.equal(result.getUTCDate(), 15);
  });
});

test('normalizeDayInIsrael: UTC-midnight constraint string still maps to same Israel day', () => {
  withUtcTimezone(() => {
    // "2026-06-07T00:00:00.000" parses as 2026-06-07T00:00:00Z under TZ=UTC.
    // In Israel that is 2026-06-07T03:00:00 → calendar day June 7.
    const result = normalizeDayInIsrael(new Date('2026-06-07T00:00:00.000Z'));
    assert.equal(result.getUTCDate(), 7);
  });
});

test("memberAvailableForEvent: Omer's bug — June 7 doctor constraint vs June 8 event → available", () => {
  withUtcTimezone(() => {
    const member = buildMember({
      constraints: [
        {
          id: 'travel',
          startDate: '2026-02-24T00:00:00.000',
          endDate: '2026-03-03T00:00:00.000',
          status: 'approved',
          constraintType: 'unavailability',
          startTime: null,
          endTime: null,
        },
        {
          id: 'ceremony',
          startDate: '2026-06-09T00:00:00.000',
          endDate: '2026-06-09T00:00:00.000',
          status: 'approved',
          constraintType: 'unavailability',
          startTime: '17:30',
          endTime: '21:30',
        },
        {
          id: 'doctor',
          startDate: '2026-06-07T00:00:00.000',
          endDate: '2026-06-07T00:00:00.000',
          status: 'approved',
          constraintType: 'unavailability',
          startTime: '17:50',
          endTime: '19:00',
        },
      ],
    });
    const event = buildEvent();
    assert.equal(memberAvailableForEvent(member, event), true);
  });
});

test('memberAvailableForEvent: same-day Israel constraint overlapping event time → blocked', () => {
  withUtcTimezone(() => {
    const member = buildMember({
      constraints: [
        {
          id: 'same-day',
          startDate: '2026-06-08T00:00:00.000',
          endDate: '2026-06-08T00:00:00.000',
          status: 'approved',
          constraintType: 'unavailability',
          startTime: '17:50',
          endTime: '19:00',
        },
      ],
    });
    assert.equal(memberAvailableForEvent(member, buildEvent()), false);
  });
});

test('memberAvailableForEvent: all-day same-day constraint → blocked', () => {
  withUtcTimezone(() => {
    const member = buildMember({
      constraints: [
        {
          id: 'allday',
          startDate: '2026-06-08T00:00:00.000',
          endDate: '2026-06-08T00:00:00.000',
          status: 'approved',
          constraintType: 'unavailability',
          startTime: null,
          endTime: null,
        },
      ],
    });
    assert.equal(memberAvailableForEvent(member, buildEvent()), false);
  });
});

test('memberAvailableForEvent: weekly repeat uses Israel weekday, not UTC weekday', () => {
  withUtcTimezone(() => {
    // June 8, 2026 is a Monday in Israel. The event Timestamp 2026-06-07T21:00Z
    // is Sunday in UTC. A weekly Monday (repeatDay=1) unavailability must block.
    const member = buildMember({
      constraints: [
        {
          id: 'every-monday',
          startDate: '2026-01-05T00:00:00.000', // Mon
          repeatType: 'weekly',
          repeatDay: 1,
          repeatEndDate: '2027-01-01T00:00:00.000',
          status: 'approved',
          constraintType: 'unavailability',
          startTime: null,
          endTime: null,
        },
      ],
    });
    assert.equal(memberAvailableForEvent(member, buildEvent()), false);
  });
});

test('memberAvailableForEvent: monthly repeat uses Israel day-of-month, not UTC day-of-month', () => {
  withUtcTimezone(() => {
    // Event is June 8 Israel; UTC date is 7. Monthly-on-8 must match.
    const member = buildMember({
      constraints: [
        {
          id: 'every-8th',
          startDate: '2026-01-08T00:00:00.000',
          repeatType: 'monthly',
          repeatDay: 8,
          repeatEndDate: '2027-01-01T00:00:00.000',
          status: 'approved',
          constraintType: 'unavailability',
          startTime: null,
          endTime: null,
        },
      ],
    });
    assert.equal(memberAvailableForEvent(member, buildEvent()), false);
  });
});

test('memberAvailableForEvent: multi-day event with a middle-day Israel constraint → blocked', () => {
  withUtcTimezone(() => {
    const member = buildMember({
      constraints: [
        {
          id: 'mid-day',
          startDate: '2026-06-09T00:00:00.000',
          endDate: '2026-06-09T00:00:00.000',
          status: 'approved',
          constraintType: 'unavailability',
          startTime: null,
          endTime: null,
        },
      ],
    });
    const event = buildEvent({
      // June 8 → June 10 in Israel (3 days)
      startDate: Timestamp.fromDate(new Date('2026-06-07T21:00:00.000Z')),
      endDate: Timestamp.fromDate(new Date('2026-06-09T21:00:00.000Z')),
    });
    assert.equal(memberAvailableForEvent(member, event), false);
  });
});

test('memberAvailableForEvent: non-permanent member without availability → unavailable', () => {
  withUtcTimezone(() => {
    const member = buildMember({isPermanent: false});
    assert.equal(memberAvailableForEvent(member, buildEvent()), false);
  });
});

test('memberAvailableForEvent: non-permanent with availability on Israel day → available', () => {
  withUtcTimezone(() => {
    const member = buildMember({
      isPermanent: false,
      constraints: [
        {
          id: 'avail',
          startDate: '2026-06-08T00:00:00.000',
          endDate: '2026-06-08T00:00:00.000',
          status: 'approved',
          constraintType: 'availability',
          startTime: null,
          endTime: null,
        },
      ],
    });
    assert.equal(memberAvailableForEvent(member, buildEvent()), true);
  });
});

test('memberAvailableForEvent: non-permanent with availability only on UTC day (June 7) → unavailable', () => {
  // Pre-fix regression check: previously the backend would have matched a
  // June 7 availability against the June 8 (Israel) event due to UTC normalization.
  // With the fix, June 7 availability does NOT cover the June 8 event.
  withUtcTimezone(() => {
    const member = buildMember({
      isPermanent: false,
      constraints: [
        {
          id: 'avail-wrong-day',
          startDate: '2026-06-07T00:00:00.000',
          endDate: '2026-06-07T00:00:00.000',
          status: 'approved',
          constraintType: 'availability',
          startTime: null,
          endTime: null,
        },
      ],
    });
    assert.equal(memberAvailableForEvent(member, buildEvent()), false);
  });
});
