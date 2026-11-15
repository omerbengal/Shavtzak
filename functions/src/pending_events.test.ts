import test from 'node:test';
import assert from 'node:assert/strict';
import {TaskActor, TaskError} from './tasks';
import {
  applyPendingEventMutation,
  isLinkedToPendingEvent,
  planPendingEventLink,
} from './pending_events';

const NOW = '2026-11-16T10:00:00.000Z';
const manager: TaskActor = {memberId: 'm', name: 'מנהל', isAdmin: false, canManageTasks: true};
const member: TaskActor = {memberId: 'a', name: 'דנה', isAdmin: false, canManageTasks: false};
const is = (status: number) => (e: unknown) => e instanceof TaskError && e.status === status;

test('pendingEvent insert / rename / delete, managers only', () => {
  let items: Array<Record<string, unknown>> = [];
  items = applyPendingEventMutation(items, 'pendingEvent.insert',
    {pendingEvent: {id: 'pe1', name: 'חנוכה 2027'}}, NOW, manager).items;
  assert.equal(items[0]['name'], 'חנוכה 2027');
  items = applyPendingEventMutation(items, 'pendingEvent.update',
    {pendingEvent: {id: 'pe1', name: 'חנוכה'}}, NOW, manager).items;
  assert.equal(items[0]['name'], 'חנוכה');
  assert.throws(() => applyPendingEventMutation(items, 'pendingEvent.insert',
    {pendingEvent: {id: 'pe2', name: 'x'}}, NOW, member), is(403));
  assert.throws(() => applyPendingEventMutation(items, 'pendingEvent.insert',
    {pendingEvent: {id: 'pe2', name: ' '}}, NOW, manager), (e: unknown) =>
    e instanceof TaskError && e.status === 400 && e.message === 'חובה להזין שם לאירוע');
  assert.throws(() => applyPendingEventMutation(items, 'pendingEvent.delete',
    {pendingEventId: 'pe1'}, NOW, manager), is(400));
  items = applyPendingEventMutation(items, 'pendingEvent.permanentlyDelete',
    {pendingEventId: 'pe1'}, NOW, manager).items;
  assert.equal(items.length, 0);
});

test('pendingEvent.link: the plan removes the placeholder, managers only', () => {
  const items = [{id: 'pe1', name: 'חנוכה'}, {id: 'pe2', name: 'פורים'}];
  const plan = planPendingEventLink(items, {pendingEventId: 'pe1', eventId: 'e1'}, manager);
  assert.equal(plan.eventId, 'e1');
  assert.deepEqual(plan.items.map((i) => i['id']), ['pe2']);
  assert.throws(() => planPendingEventLink(items, {pendingEventId: 'pe1', eventId: 'e1'}, member), is(403));
  assert.throws(() => planPendingEventLink(items, {pendingEventId: 'nope', eventId: 'e1'}, manager), is(404));
  assert.throws(() => planPendingEventLink(items, {pendingEventId: 'pe1', eventId: ''}, manager), is(400));
});

test('isLinkedToPendingEvent matches only that placeholder', () => {
  assert.ok(isLinkedToPendingEvent({link: {type: 'pendingEvent', id: 'pe1'}}, 'pe1'));
  assert.ok(!isLinkedToPendingEvent({link: {type: 'topic', id: 'pe1'}}, 'pe1'));
  assert.ok(!isLinkedToPendingEvent({link: null}, 'pe1'));
});
