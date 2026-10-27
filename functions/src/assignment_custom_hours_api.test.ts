import test from 'node:test';
import assert from 'node:assert/strict';
import {
  __testAssignmentDocFromJson as assignmentDocFromJson,
  __testRequireValidCustomHours as requireValidCustomHours,
  planAssignmentSaveBatch,
  planCreatedAssignmentHours,
} from './index';
import type {HoursRow} from './assignment_hours';

// createdAt/updatedAt go through toTimestamp(), which throws on a missing value.
const base = {
  id: 'a1',
  eventId: 'e',
  teamMemberId: 'm',
  roleType: 'medic',
  createdAt: '2026-10-27T10:00:00.000Z',
  updatedAt: '2026-10-27T10:00:00.000Z',
};

const INCOMPLETE = 'שעות מותאמות חייבות לכלול תאריך ושעה של הגעה ושל עזיבה';
const ORDER = 'שעת העזיבה חייבת להיות אחרי שעת ההגעה';
const SHARED = 'לחבר/ת צוות חייבות להיות אותן שעות מותאמות בכל התפקידים באירוע';

const httpError = (status: number, message: string) => (error: unknown) => {
  const e = error as {status?: number; message?: string};
  assert.equal(e.status, status);
  assert.equal(e.message, message);
  return true;
};

const row = (id: string, teamMemberId: string, customStartAt: string | null, customEndAt: string | null): HoursRow => ({
  id,
  eventId: 'e',
  teamMemberId,
  customStartAt,
  customEndAt,
});

// assignmentDocFromJson: only keys that are present reach the doc.

test('assignmentDocFromJson: JSON without the keys gives a doc without them', () => {
  const doc = assignmentDocFromJson({...base});
  assert.equal('customStartAt' in doc, false);
  assert.equal('customEndAt' in doc, false);
});

test('assignmentDocFromJson: keys present as null are written as null', () => {
  const doc = assignmentDocFromJson({...base, customStartAt: null, customEndAt: null});
  assert.equal('customStartAt' in doc, true);
  assert.equal('customEndAt' in doc, true);
  assert.equal(doc['customStartAt'], null);
  assert.equal(doc['customEndAt'], null);
});

test('assignmentDocFromJson: valid strings are copied verbatim', () => {
  const doc = assignmentDocFromJson({
    ...base,
    customStartAt: '2026-12-01T17:00',
    customEndAt: '2026-12-02T01:00',
  });
  assert.equal(doc['customStartAt'], '2026-12-01T17:00');
  assert.equal(doc['customEndAt'], '2026-12-02T01:00');
});

// requireValidCustomHours: the payload's shape, checked only when a key is present.

test('requireValidCustomHours: no keys, or both null, pass', () => {
  assert.doesNotThrow(() => requireValidCustomHours({...base}));
  assert.doesNotThrow(() => requireValidCustomHours({...base, customStartAt: null, customEndAt: null}));
  assert.doesNotThrow(() =>
    requireValidCustomHours({...base, customStartAt: '2026-12-01T17:00', customEndAt: '2026-12-02T01:00'}),
  );
});

test('requireValidCustomHours: a lone key is incomplete, even a lone null', () => {
  assert.throws(() => requireValidCustomHours({...base, customStartAt: '2026-12-01T17:00'}), httpError(400, INCOMPLETE));
  assert.throws(() => requireValidCustomHours({...base, customEndAt: null}), httpError(400, INCOMPLETE));
});

test('requireValidCustomHours: one value null, or an unreadable value, is incomplete', () => {
  assert.throws(
    () => requireValidCustomHours({...base, customStartAt: '2026-12-01T17:00', customEndAt: null}),
    httpError(400, INCOMPLETE),
  );
  assert.throws(
    () => requireValidCustomHours({...base, customStartAt: '2026-12-01T17:00', customEndAt: '2026-12-02 01:00'}),
    httpError(400, INCOMPLETE),
  );
});

test('requireValidCustomHours: an end not after the start is refused', () => {
  assert.throws(
    () => requireValidCustomHours({...base, customStartAt: '2026-12-01T17:00', customEndAt: '2026-12-01T17:00'}),
    httpError(400, ORDER),
  );
});

// planCreatedAssignmentHours: a direct create inherits, or must match.

test('planCreatedAssignmentHours: a create without hours inherits the member\'s hours in the event', () => {
  const doc = planCreatedAssignmentHours({
    id: 'new',
    doc: {eventId: 'e', teamMemberId: 'm'},
    rows: [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00')],
    exempt: false,
  });
  assert.equal(doc['customStartAt'], '2026-12-01T17:00');
  assert.equal(doc['customEndAt'], '2026-12-02T01:00');
});

test('planCreatedAssignmentHours: explicit nulls inherit too', () => {
  const doc = planCreatedAssignmentHours({
    id: 'new',
    doc: {eventId: 'e', teamMemberId: 'm', customStartAt: null, customEndAt: null},
    rows: [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00')],
    exempt: false,
  });
  assert.equal(doc['customStartAt'], '2026-12-01T17:00');
  assert.equal(doc['customEndAt'], '2026-12-02T01:00');
});

test('planCreatedAssignmentHours: with nothing to inherit, the create states null explicitly', () => {
  const doc = planCreatedAssignmentHours({
    id: 'new',
    doc: {eventId: 'e', teamMemberId: 'm'},
    rows: [row('a1', 'other', '2026-12-01T17:00', '2026-12-02T01:00'), row('a2', 'm', null, null)],
    exempt: false,
  });
  assert.equal('customStartAt' in doc, true);
  assert.equal(doc['customStartAt'], null);
  assert.equal(doc['customEndAt'], null);
});

test('planCreatedAssignmentHours: an exempt member never inherits', () => {
  const doc = planCreatedAssignmentHours({
    id: 'new',
    doc: {eventId: 'e', teamMemberId: 'm'},
    rows: [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00')],
    exempt: true,
  });
  assert.equal(doc['customStartAt'], null);
  assert.equal(doc['customEndAt'], null);
});

test('planCreatedAssignmentHours: a create with hours different from the member\'s is refused', () => {
  assert.throws(
    () =>
      planCreatedAssignmentHours({
        id: 'new',
        doc: {eventId: 'e', teamMemberId: 'm', customStartAt: '2026-12-01T18:00', customEndAt: '2026-12-02T01:00'},
        rows: [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00')],
        exempt: false,
      }),
    httpError(400, SHARED),
  );
  assert.throws(
    () =>
      planCreatedAssignmentHours({
        id: 'new',
        doc: {eventId: 'e', teamMemberId: 'm', customStartAt: '2026-12-01T18:00', customEndAt: '2026-12-02T01:00'},
        rows: [row('a1', 'm', null, null)],
        exempt: false,
      }),
    httpError(400, SHARED),
  );
});

test('planCreatedAssignmentHours: a create with the member\'s own hours, or exempt, is kept as sent', () => {
  const sent = {eventId: 'e', teamMemberId: 'm', customStartAt: '2026-12-01T17:00', customEndAt: '2026-12-02T01:00'};
  assert.deepEqual(
    planCreatedAssignmentHours({id: 'new', doc: sent, rows: [row('a1', 'm', '2026-12-01T17:00', '2026-12-02T01:00')], exempt: false}),
    sent,
  );
  assert.deepEqual(
    planCreatedAssignmentHours({id: 'new', doc: sent, rows: [row('a1', 'm', null, null)], exempt: true}),
    sent,
  );
});

// planAssignmentSaveBatch: creates state their hours; updates keep absent keys absent.

test('planAssignmentSaveBatch: a create without hours gets explicit nulls; an update without them leaves them out', () => {
  const plan = planAssignmentSaveBatch({
    creates: [{...base, id: 'c1'}],
    updates: [{...base, id: 'u1'}],
  });
  assert.equal(plan.creates[0].doc['customStartAt'], null);
  assert.equal(plan.creates[0].doc['customEndAt'], null);
  assert.equal('customStartAt' in plan.updates[0].doc, false);
  assert.equal('customEndAt' in plan.updates[0].doc, false);
});

test('planAssignmentSaveBatch: hours sent on a create or an update are kept', () => {
  const hours = {customStartAt: '2026-12-01T17:00', customEndAt: '2026-12-02T01:00'};
  const plan = planAssignmentSaveBatch({
    creates: [{...base, ...hours, id: 'c1'}],
    updates: [{...base, customStartAt: null, customEndAt: null, id: 'u1'}],
  });
  assert.equal(plan.creates[0].doc['customStartAt'], '2026-12-01T17:00');
  assert.equal(plan.creates[0].doc['customEndAt'], '2026-12-02T01:00');
  assert.equal(plan.updates[0].doc['customStartAt'], null);
  assert.equal(plan.updates[0].doc['customEndAt'], null);
});
