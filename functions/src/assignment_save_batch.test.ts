import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {planAssignmentSaveBatch} from './index';

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
