import test from 'node:test';
import assert from 'node:assert/strict';
import {TaskActor, TaskError} from './tasks';
import {applyTaskTopicMutation} from './task_topics';

const manager: TaskActor = {memberId: 'm', name: 'מנהל', isAdmin: false, canManageTasks: true};
const member: TaskActor = {memberId: 'x', name: 'חבר', isAdmin: false, canManageTasks: false};
const NOW = '2026-11-15T10:00:00.000Z';

test('taskTopic insert/rename/archive/restore', () => {
  let items: Array<Record<string, unknown>> = [];
  items = applyTaskTopicMutation(items, 'taskTopic.insert',
    {topic: {id: 'p1', name: '  נשות מגדים ', sortOrder: 2}}, NOW, manager).items;
  assert.deepEqual(items[0], {id: 'p1', name: 'נשות מגדים', sortOrder: 2, isArchived: false, updatedAt: NOW});
  items = applyTaskTopicMutation(items, 'taskTopic.update',
    {topic: {id: 'p1', name: 'נשות המגדים', sortOrder: 2}}, NOW, manager).items;
  assert.equal(items[0]['name'], 'נשות המגדים');
  items = applyTaskTopicMutation(items, 'taskTopic.delete', {topicId: 'p1'}, NOW, manager).items;
  assert.equal(items[0]['isArchived'], true);
  items = applyTaskTopicMutation(items, 'taskTopic.restore', {topicId: 'p1'}, NOW, manager).items;
  assert.equal(items[0]['isArchived'], false);
  items = applyTaskTopicMutation(items, 'taskTopic.permanentlyDelete', {topicId: 'p1'}, NOW, manager).items;
  assert.equal(items.length, 0);
});

test('taskTopic insert refuses a repeated id or a blank name', () => {
  const items = [{id: 'p1', name: 'א', sortOrder: 0, isArchived: false}];
  const is = (code: number) => (e: unknown) => e instanceof TaskError && e.status === code;
  assert.throws(() => applyTaskTopicMutation(items, 'taskTopic.insert', {topic: {id: 'p1', name: 'ב'}}, NOW, manager), is(409));
  assert.throws(() => applyTaskTopicMutation(items, 'taskTopic.insert', {topic: {id: 'p2', name: ' '}}, NOW, manager), is(400));
  assert.throws(() => applyTaskTopicMutation(items, 'taskTopic.update', {topic: {id: 'p9', name: 'ב'}}, NOW, manager), is(404));
  assert.throws(() => applyTaskTopicMutation(items, 'taskTopic.delete', {topicId: 'p9'}, NOW, manager), is(404));
});

test('a non-manager cannot add a topic', () => {
  assert.throws(
    () => applyTaskTopicMutation([], 'taskTopic.insert', {topic: {id: 'p1', name: 'א'}}, NOW, member),
    (e: unknown) => e instanceof TaskError && e.status === 403,
  );
});
