import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {
  planAssignmentSaveBatch,
  findBatchDuplicateRoleAssignments,
  planEventQuotaBumps,
  planEventQuotaSets,
} from './index';

// assignmentDocFromJson (called internally by the planner) runs every
// createdAt/updatedAt through toTimestamp(), which THROWS on a missing or
// unparseable value. Give every fixture a valid ISO string (this is what the
// Flutter client sends — see AssignmentModel.toJson() /
// _assignmentEntityToMap in firestore_database.dart, which calls
// DateTime.toIso8601String()).
const CREATED_AT = '2026-07-16T10:00:00.000Z';
const UPDATED_AT = '2026-07-16T11:00:00.000Z';

test('planAssignmentSaveBatch partitions creates/updates/deletes and shapes each doc via assignmentDocFromJson', () => {
  const plan = planAssignmentSaveBatch({
    creates: [
      {
        id: 'a-new',
        eventId: 'e1',
        teamMemberId: 'm1',
        roleType: 'medic',
        slotIndex: 1,
        createdAt: CREATED_AT,
        updatedAt: UPDATED_AT,
      },
    ],
    updates: [
      {
        id: 'a-old',
        eventId: 'e1',
        teamMemberId: 'm2',
        roleType: 'paramedic',
        slotIndex: 0,
        createdAt: CREATED_AT,
        updatedAt: UPDATED_AT,
      },
    ],
    deletes: ['d1', 'd2'],
  });

  // creates: one entry, correctly shaped.
  assert.equal(plan.creates.length, 1);
  assert.equal(plan.creates[0].id, 'a-new');
  assert.equal(plan.creates[0].doc['eventId'], 'e1');
  assert.equal(plan.creates[0].doc['teamMemberId'], 'm1');
  assert.equal(plan.creates[0].doc['roleType'], 'medic');
  assert.equal(plan.creates[0].doc['slotIndex'], 1);
  // createdAt/updatedAt go through toTimestamp() -> a Firestore Timestamp,
  // not the raw ISO string.
  assert.ok(plan.creates[0].doc['createdAt'] instanceof Timestamp);
  assert.equal(
    (plan.creates[0].doc['createdAt'] as Timestamp).toMillis(),
    new Date(CREATED_AT).getTime(),
  );

  // updates: one entry, correctly shaped.
  assert.equal(plan.updates.length, 1);
  assert.equal(plan.updates[0].id, 'a-old');
  assert.equal(plan.updates[0].doc['eventId'], 'e1');
  assert.equal(plan.updates[0].doc['teamMemberId'], 'm2');
  assert.equal(plan.updates[0].doc['roleType'], 'paramedic');
  assert.ok(plan.updates[0].doc['updatedAt'] instanceof Timestamp);
  assert.equal(
    (plan.updates[0].doc['updatedAt'] as Timestamp).toMillis(),
    new Date(UPDATED_AT).getTime(),
  );

  // deletes: passed through untouched, in order.
  assert.deepEqual(plan.deletes, ['d1', 'd2']);
});

test('planAssignmentSaveBatch treats a payload with no sections as all-empty', () => {
  assert.deepEqual(planAssignmentSaveBatch({}), {
    creates: [],
    updates: [],
    deletes: [],
  });
});

test('planAssignmentSaveBatch treats explicitly-empty arrays as all-empty', () => {
  assert.deepEqual(
    planAssignmentSaveBatch({creates: [], updates: [], deletes: []}),
    {creates: [], updates: [], deletes: []},
  );
});

test('planAssignmentSaveBatch throws when a create is missing an id', () => {
  assert.throws(() =>
    planAssignmentSaveBatch({
      creates: [
        {
          eventId: 'e1',
          teamMemberId: 'm1',
          roleType: 'medic',
          createdAt: CREATED_AT,
          updatedAt: UPDATED_AT,
        },
      ],
    }),
  );
});

test('planAssignmentSaveBatch throws when an update is missing an id', () => {
  assert.throws(() =>
    planAssignmentSaveBatch({
      updates: [
        {
          eventId: 'e1',
          teamMemberId: 'm1',
          roleType: 'medic',
          createdAt: CREATED_AT,
          updatedAt: UPDATED_AT,
        },
      ],
    }),
  );
});

// findBatchDuplicateRoleAssignments backs assignment.saveBatch's batch-aware
// duplicate-role check. validateAssignmentPayload's own duplicate check only
// ever sees LIVE Firestore docs one item at a time, so it can't tell a
// same-role swap (or a move into a slot freed earlier in the same batch)
// apart from a genuine duplicate -- that's exactly what this pure helper
// disambiguates, by computing the batch's RESULTING per-event occupancy.

test('findBatchDuplicateRoleAssignments allows a same-role swap between two slots', () => {
  // Event e1 has Medic#0=Dan (a1), Medic#1=Ron (a2). Staged edit swaps them.
  const result = findBatchDuplicateRoleAssignments({
    existing: [
      {id: 'a1', eventId: 'e1', roleType: 'medic', teamMemberId: 'Dan'},
      {id: 'a2', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ron'},
    ],
    creates: [],
    updates: [
      {id: 'a1', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ron'},
      {id: 'a2', eventId: 'e1', roleType: 'medic', teamMemberId: 'Dan'},
    ],
    deletes: [],
  });
  assert.deepEqual(result, []);
});

test('findBatchDuplicateRoleAssignments allows moving a member into an empty same-role slot', () => {
  // a1 (medic=Ron) is reassigned to Dan, while a NEW slot a2 (medic) is
  // created for Ron in the same batch -- net effect: Ron moved a1 -> a2.
  const result = findBatchDuplicateRoleAssignments({
    existing: [{id: 'a1', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ron'}],
    creates: [{id: 'a2', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ron'}],
    updates: [{id: 'a1', eventId: 'e1', roleType: 'medic', teamMemberId: 'Dan'}],
    deletes: [],
  });
  assert.deepEqual(result, []);
});

test('findBatchDuplicateRoleAssignments rejects a genuine duplicate the batch does not resolve', () => {
  // a1 (medic=Ron) already exists and is untouched by this batch; creating
  // a2 for the same (event, role, member) is a real duplicate.
  const result = findBatchDuplicateRoleAssignments({
    existing: [{id: 'a1', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ron'}],
    creates: [{id: 'a2', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ron'}],
    updates: [],
    deletes: [],
  });
  assert.deepEqual(result, [{eventId: 'e1', roleType: 'medic', teamMemberId: 'Ron'}]);
});

test('findBatchDuplicateRoleAssignments allows re-filling a slot freed by a delete in the same batch', () => {
  // a1 (medic=Ron) is deleted, and a NEW slot a2 (medic=Ron) is created in
  // the same batch -- a1 no longer occupies the slot, so no duplicate.
  const result = findBatchDuplicateRoleAssignments({
    existing: [{id: 'a1', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ron'}],
    creates: [{id: 'a2', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ron'}],
    updates: [],
    deletes: ['a1'],
  });
  assert.deepEqual(result, []);
});

test('findBatchDuplicateRoleAssignments allows a member with allowMultipleAssignments to double-book the same role', () => {
  // Ziv is staged into TWO medic slots (a1, a2) of the same event in one
  // batch. Ordinarily this is a duplicate, but Ziv is in exemptMemberIds
  // (mirrors a team-member doc with allowMultipleAssignments === true), so
  // it must be allowed -- same as the single-item path already allows it.
  const result = findBatchDuplicateRoleAssignments({
    existing: [],
    creates: [
      {id: 'a1', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ziv'},
      {id: 'a2', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ziv'},
    ],
    updates: [],
    deletes: [],
    exemptMemberIds: new Set(['Ziv']),
  });
  assert.deepEqual(result, []);
});

test('findBatchDuplicateRoleAssignments rejects the same double-booking when the member is not exempt', () => {
  // Identical scenario to the previous test, but WITHOUT Ziv in
  // exemptMemberIds -- must be rejected like any other genuine duplicate.
  const result = findBatchDuplicateRoleAssignments({
    existing: [],
    creates: [
      {id: 'a1', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ziv'},
      {id: 'a2', eventId: 'e1', roleType: 'medic', teamMemberId: 'Ziv'},
    ],
    updates: [],
    deletes: [],
    exemptMemberIds: new Set(),
  });
  assert.deepEqual(result, [{eventId: 'e1', roleType: 'medic', teamMemberId: 'Ziv'}]);
});

// ---- planEventQuotaBumps: optional atomic quota restores for saveBatch ----

test('planEventQuotaBumps returns [] for missing / null / empty input', () => {
  assert.deepEqual(planEventQuotaBumps(undefined), []);
  assert.deepEqual(planEventQuotaBumps(null), []);
  assert.deepEqual(planEventQuotaBumps([]), []);
});

test('planEventQuotaBumps validates and shapes each entry', () => {
  assert.deepEqual(
    planEventQuotaBumps([
      {eventId: 'e1', roleType: 'medic', count: 2},
      {eventId: 'e2', roleType: 'investigation', count: 1},
    ]),
    [
      {eventId: 'e1', roleType: 'medic', count: 2},
      {eventId: 'e2', roleType: 'investigation', count: 1},
    ],
  );
});

test('planEventQuotaBumps throws on a non-array', () => {
  assert.throws(() =>
    planEventQuotaBumps({eventId: 'e1', roleType: 'medic', count: 1}),
  );
});

test('planEventQuotaBumps throws on a missing eventId or roleType', () => {
  assert.throws(() => planEventQuotaBumps([{roleType: 'medic', count: 1}]));
  assert.throws(() => planEventQuotaBumps([{eventId: 'e1', count: 1}]));
});

test('planEventQuotaBumps throws on a non-integer / out-of-range count', () => {
  assert.throws(() =>
    planEventQuotaBumps([{eventId: 'e1', roleType: 'medic', count: 0}]),
  );
  assert.throws(() =>
    planEventQuotaBumps([{eventId: 'e1', roleType: 'medic', count: 1.5}]),
  );
  assert.throws(() =>
    planEventQuotaBumps([{eventId: 'e1', roleType: 'medic', count: -3}]),
  );
  assert.throws(() =>
    planEventQuotaBumps([{eventId: 'e1', roleType: 'medic', count: 1000}]),
  );
  assert.throws(() =>
    planEventQuotaBumps([{eventId: 'e1', roleType: 'medic', count: '2'}]),
  );
});

// ---- planEventQuotaSets: optional exact quota targets for saveBatch ----

test('planEventQuotaSets returns [] for missing / null / empty input', () => {
  assert.deepEqual(planEventQuotaSets(undefined), []);
  assert.deepEqual(planEventQuotaSets(null), []);
  assert.deepEqual(planEventQuotaSets([]), []);
});

test('planEventQuotaSets validates and shapes each entry (target may be 0)', () => {
  assert.deepEqual(
    planEventQuotaSets([
      {eventId: 'e1', roleType: 'medic', target: 2, expected: 3},
      {eventId: 'e2', roleType: 'investigation', target: 0, expected: 1},
    ]),
    [
      {eventId: 'e1', roleType: 'medic', target: 2, expected: 3},
      {eventId: 'e2', roleType: 'investigation', target: 0, expected: 1},
    ],
  );
});

test('planEventQuotaSets throws on a non-array', () => {
  assert.throws(() =>
    planEventQuotaSets({eventId: 'e1', roleType: 'medic', target: 1, expected: 2}),
  );
});

test('planEventQuotaSets throws on a missing eventId or roleType', () => {
  assert.throws(() => planEventQuotaSets([{roleType: 'medic', target: 1, expected: 2}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', target: 1, expected: 2}]));
});

test('planEventQuotaSets throws on non-integer / out-of-range target or expected', () => {
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: -1, expected: 2}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: 1.5, expected: 2}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: 1000, expected: 2}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: 1, expected: -1}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: '1', expected: 2}]));
});
