import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {Timestamp} from 'firebase-admin/firestore';
import {
  __testEventStretchFromData as eventStretchFromData,
  __testMemberAvailableForEvent as memberAvailableForEvent,
} from './index';
import {formatWallMinutes} from './event_stretch';

// The shared case table. The Flutter runner reads the same file and must reach
// the same answers, so the app and the backend can't drift apart again.
// Tests run from lib/, so the repo root is two levels up.
const CASES_PATH = path.join(__dirname, '..', '..', 'shared', 'test-fixtures', 'event_conflict_cases.json');

interface CaseConstraint {
  startDate: string;
  endDate: string | null;
  startTime: string | null;
  endTime: string | null;
  status: string;
  constraintType: string;
  repeatType: string | null;
  repeatDay: number | null;
  repeatEndDate: string | null;
}

interface ConflictCase {
  id: string;
  label: string;
  event: {
    startDate: string;
    endDate: string;
    assemblyTime: string;
    startTime: string;
    endTime: string;
    teamEndTime: string;
  };
  member: {
    isPermanent: boolean;
    isActive: boolean;
    isArchived: boolean;
    availableEventIds: string[];
    constraints: CaseConstraint[];
  };
  expectedAvailable: boolean;
  expectedStretch?: {start: string; end: string};
}

const cases: ConflictCase[] = JSON.parse(fs.readFileSync(CASES_PATH, 'utf8')).cases;

// Pins TZ=UTC like the deployed Cloud Function, so the naive constraint date
// strings parse the way they do in production.
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

const israelHour = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Jerusalem',
  hour: '2-digit',
  hourCycle: 'h23',
});

// Midnight of an Israel calendar day as a UTC instant, the way event dates are
// stored: whichever of the summer (+03:00) and winter (+02:00) offsets lands
// on hour 0 in Israel.
function israelMidnight(dateKey: string): Timestamp {
  for (const offset of ['+03:00', '+02:00']) {
    const candidate = new Date(`${dateKey}T00:00:00.000${offset}`);
    if (Number(israelHour.format(candidate)) === 0) {
      return Timestamp.fromDate(candidate);
    }
  }
  throw new Error(`No Israel midnight found for ${dateKey}`);
}

// Constraint dates are naive strings, the way the Flutter client stores them.
function naiveDate(dateKey: string | null): string | null {
  return dateKey == null ? null : `${dateKey}T00:00:00.000`;
}

function eventData(row: ConflictCase): Record<string, unknown> {
  return {
    id: 'evt',
    startDate: israelMidnight(row.event.startDate),
    endDate: israelMidnight(row.event.endDate),
    assemblyTime: row.event.assemblyTime,
    startTime: row.event.startTime,
    endTime: row.event.endTime,
    teamEndTime: row.event.teamEndTime,
  };
}

function memberData(row: ConflictCase): Record<string, unknown> {
  return {
    isPermanent: row.member.isPermanent,
    isActive: row.member.isActive,
    isArchived: row.member.isArchived,
    allowMultipleAssignments: false,
    availableEventIds: row.member.availableEventIds,
    roleCapabilities: {},
    constraints: row.member.constraints.map((constraint, index) => ({
      id: `c${index}`,
      ...constraint,
      startDate: naiveDate(constraint.startDate),
      endDate: naiveDate(constraint.endDate),
      repeatEndDate: naiveDate(constraint.repeatEndDate),
    })),
  };
}

test('case table holds at least 60 cases', () => {
  assert.ok(cases.length >= 60, `only ${cases.length} cases`);
  assert.equal(new Set(cases.map((row) => row.id)).size, cases.length, 'case ids must be unique');
});

for (const row of cases) {
  test(`case ${row.id}: ${row.label}`, () => {
    withUtcTimezone(() => {
      const event = eventData(row);
      if (row.expectedStretch != null) {
        const stretch = eventStretchFromData(event);
        assert.deepEqual(
          {start: formatWallMinutes(stretch.start), end: formatWallMinutes(stretch.end)},
          row.expectedStretch,
          `${row.id}: stretch`,
        );
      }
      assert.equal(
        memberAvailableForEvent(memberData(row), event),
        row.expectedAvailable,
        `${row.id}: expected ${row.expectedAvailable ? 'free' : 'blocked'}`,
      );
    });
  });
}
