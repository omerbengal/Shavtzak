import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {TaskActor, TaskError} from './tasks';
import {TeamTaskStore, runTeamTaskOperation} from './team_task_ops';
import {__testGetCollections as getCollections} from './index';

const now = Timestamp.fromMillis(1_800_000_000_000);
const manager: TaskActor = {memberId: 'mgr', name: 'מנהל', isAdmin: true, canManageTasks: false};
const owner: TaskActor = {memberId: 'a', name: 'דנה', isAdmin: false, canManageTasks: false};

class MemoryStore implements TeamTaskStore {
  tasks = new Map<string, Record<string, unknown>>();
  events = new Set<string>(['e1']);
  categories = new Set<string>(['c1']);
  topics = new Set<string>(['p1']);
  members = new Map<string, {isActive: boolean; isArchived: boolean}>([
    ['a', {isActive: true, isArchived: false}],
    ['b', {isActive: true, isArchived: false}],
    ['gone', {isActive: false, isArchived: true}],
  ]);
  async getTask(id: string) { return this.tasks.get(id) ?? null; }
  async eventExists(id: string) { return this.events.has(id); }
  async categoryExists(id: string) { return this.categories.has(id); }
  async topicExists(id: string) { return this.topics.has(id); }
  pendingEvents = new Set<string>(['pe1']);
  async pendingEventExists(id: string) { return this.pendingEvents.has(id); }
  async inactiveMemberIds(ids: string[]) {
    return ids.filter((id) => {
      const m = this.members.get(id);
      return m == null || !m.isActive || m.isArchived;
    });
  }
  async writeTask(doc: {id: string}) { this.tasks.set(doc.id, doc as Record<string, unknown>); }
  async deleteTask(id: string) { this.tasks.delete(id); }
}

function task(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {id: 't1', title: 'להזמין אולם', link: {type: 'event', id: 'e1'}, assigneeIds: ['a'], ...overrides};
}

const status = (code: number, message?: string) => (e: unknown) => {
  assert.ok(e instanceof TaskError, String(e));
  assert.equal(e.status, code);
  if (message != null) assert.equal(e.message, message);
  return true;
};

async function insert(store: MemoryStore, overrides: Record<string, unknown> = {}) {
  return runTeamTaskOperation(store, 'teamTask.insert', {task: task(overrides)}, manager, now);
}

test('insert checks the link exists', async () => {
  const store = new MemoryStore();
  await assert.rejects(insert(store, {link: {type: 'event', id: 'nope'}}), status(404, 'האירוע לא נמצא'));
  await assert.rejects(insert(store, {link: {type: 'category', id: 'nope'}}), status(404, 'הקטגוריה לא נמצאה'));
  await assert.rejects(insert(store, {link: {type: 'topic', id: 'nope'}}), status(404, 'הנושא לא נמצא'));
  const done = await insert(store);
  assert.deepEqual(done.after?.ownerIds, ['a']);
  assert.ok(store.tasks.has('t1'));
});

test('insert refuses an inactive owner', async () => {
  const store = new MemoryStore();
  await assert.rejects(insert(store, {assigneeIds: ['gone']}), status(400, 'חבר צוות לא נמצא'));
  await assert.rejects(insert(store, {
    assigneeIds: [],
    subtasks: [{id: 's1', title: 'x', assigneeIds: ['gone']}],
  }), status(400));
});

test('insert refuses an existing id', async () => {
  const store = new MemoryStore();
  await insert(store);
  await assert.rejects(insert(store), status(409));
});

test('update keeps an owner who was archived since', async () => {
  const store = new MemoryStore();
  await insert(store, {assigneeIds: ['a', 'b']});
  store.members.set('b', {isActive: false, isArchived: true});
  const result = await runTeamTaskOperation(store, 'teamTask.update',
    {task: task({assigneeIds: ['a', 'b'], title: 'חדש'})}, manager, now);
  assert.equal(result.after?.title, 'חדש');
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.update',
    {task: task({assigneeIds: ['gone']})}, manager, now), status(400));
});

test('setStatus duplicate refuses a missing original', async () => {
  const store = new MemoryStore();
  await insert(store);
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.setStatus',
    {id: 't1', status: 'duplicate', duplicateOfId: 'missing'}, owner, now), status(404));
  await insert(store, {id: 't2'});
  const result = await runTeamTaskOperation(store, 'teamTask.setStatus',
    {id: 't1', status: 'duplicate', duplicateOfId: 't2'}, owner, now);
  assert.equal(result.after?.duplicateOfId, 't2');
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.setStatus',
    {id: 't1', status: 'weird'}, owner, now), status(400));
});

test('setSubtaskDone, addUpdate and delete', async () => {
  const store = new MemoryStore();
  await insert(store, {assigneeIds: [], subtasks: [{id: 's1', title: 'x', assigneeIds: ['a']}]});
  const ticked = await runTeamTaskOperation(store, 'teamTask.setSubtaskDone',
    {id: 't1', subtaskId: 's1', isDone: true}, owner, now);
  assert.equal(ticked.after?.subtasks[0].status, 'done');
  // Subtasks no longer drive the parent's status (16/11/2026).
  assert.equal(ticked.after?.status, 'open');
  const logged = await runTeamTaskOperation(store, 'teamTask.addUpdate', {id: 't1', text: 'סגרנו'}, owner, now);
  assert.equal(logged.after?.updates[0].text, 'סגרנו');
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.delete', {id: 't1'}, owner, now), status(403));
  await runTeamTaskOperation(store, 'teamTask.delete', {id: 't1'}, manager, now);
  assert.equal(store.tasks.size, 0);
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.delete', {id: 't1'}, manager, now), status(404));
});

test('writes go to test_teamTasks in the test environment', () => {
  assert.equal(getCollections('test').teamTasks, 'test_teamTasks');
  assert.equal(getCollections('production').teamTasks, 'teamTasks');
});

test('update keeps a link to a deleted event', async () => {
  const store = new MemoryStore();
  await insert(store);
  store.events.delete('e1');
  const result = await runTeamTaskOperation(store, 'teamTask.update',
    {task: task({title: 'תיקון כתיב'})}, manager, now);
  assert.equal(result.after?.title, 'תיקון כתיב');
  // A new link to a missing event is still refused.
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.update',
    {task: task({link: {type: 'event', id: 'nope'}})}, manager, now), status(404));
});

test('setStatus and addUpdate with a subtaskId act on that subtask', async () => {
  const store = new MemoryStore();
  await insert(store, {assigneeIds: [], subtasks: [
    {id: 's1', title: 'x', assigneeIds: ['a']},
    {id: 's2', title: 'y', assigneeIds: ['a']},
  ]});
  const moved = await runTeamTaskOperation(store, 'teamTask.setStatus',
    {id: 't1', subtaskId: 's1', status: 'inProgress'}, owner, now);
  assert.equal(moved.after?.subtasks[0].status, 'inProgress');
  assert.equal(moved.after?.status, 'open');
  const dup = await runTeamTaskOperation(store, 'teamTask.setStatus',
    {id: 't1', subtaskId: 's2', status: 'duplicate', duplicateOfId: 's1'}, owner, now);
  assert.equal(dup.after?.subtasks[1].duplicateOfId, 's1');
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.setStatus',
    {id: 't1', subtaskId: 's2', status: 'duplicate', duplicateOfId: 'missing'}, owner, now), status(404));
  const logged = await runTeamTaskOperation(store, 'teamTask.addUpdate',
    {id: 't1', subtaskId: 's1', text: 'התחלתי'}, owner, now);
  assert.equal(logged.after?.subtasks[0].updates[0].text, 'התחלתי');
  assert.equal(logged.after?.updates.length, 0);
});

test('setStatus on a task that still stores subtasks sets its own status (16/11/2026)', async () => {
  const store = new MemoryStore();
  await insert(store, {assigneeIds: [], subtasks: [
    {id: 's1', title: 'x', assigneeIds: ['a']},
    {id: 's2', title: 'y', assigneeIds: ['a']},
  ]});
  const result = await runTeamTaskOperation(store, 'teamTask.setStatus',
    {id: 't1', status: 'done'}, manager, now);
  assert.equal(result.after?.status, 'done');
  assert.equal(result.after?.subtasks.length, 2);
  assert.deepEqual(result.after?.ownerIds, ['a']);
});

test('insert links to a pending event only when it exists (round 10)', async () => {
  const store = new MemoryStore();
  await assert.rejects(insert(store, {link: {type: 'pendingEvent', id: 'nope'}}),
    status(404, 'האירוע שעוד לא נוצר לא נמצא'));
  const done = await insert(store, {link: {type: 'pendingEvent', id: 'pe1'}});
  assert.deepEqual(done.after?.link, {type: 'pendingEvent', id: 'pe1'});
});

test('editUpdate / deleteUpdate: the writer, or a manager (round 10)', async () => {
  const store = new MemoryStore();
  await insert(store);
  await runTeamTaskOperation(store, 'teamTask.addUpdate', {id: 't1', text: 'שלי'}, owner, now);
  const updateId = (store.tasks.get('t1')!['updates'] as Array<{id: string}>)[0].id;
  const later = Timestamp.fromMillis(1_800_000_600_000);
  const edited = await runTeamTaskOperation(store, 'teamTask.editUpdate',
    {id: 't1', updateId, text: ' מתוקן '}, owner, later);
  assert.equal(edited.after?.updates[0].text, 'מתוקן');
  assert.deepEqual(edited.after?.updates[0].editedAt, later);
  assert.deepEqual(edited.after?.updates[0].at, now);
  assert.equal(edited.details['oldText'], 'שלי');
  const other: TaskActor = {memberId: 'b', name: 'יוסי', isAdmin: false, canManageTasks: false};
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.deleteUpdate',
    {id: 't1', updateId}, other, now), status(403));
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.deleteUpdate',
    {id: 't1', updateId: 'nope'}, manager, now), status(404));
  const deleted = await runTeamTaskOperation(store, 'teamTask.deleteUpdate',
    {id: 't1', updateId}, manager, now);
  assert.equal(deleted.after?.updates.length, 0);
});

test('several events: each one must exist; an update checks only the added ones', async () => {
  const store = new MemoryStore();
  store.events.add('e2');
  await assert.rejects(insert(store, {eventIds: ['e1', 'nope']}), status(404, 'האירוע לא נמצא'));
  const done = await insert(store, {eventIds: ['e1', 'e2']});
  assert.deepEqual(done.after?.eventIds, ['e1', 'e2']);
  // e2 deleted since: the task stays editable.
  store.events.delete('e2');
  const kept = await runTeamTaskOperation(store, 'teamTask.update',
    {task: task({title: 'x', eventIds: ['e1', 'e2']})}, manager, now);
  assert.deepEqual(kept.after?.eventIds, ['e1', 'e2']);
  await assert.rejects(runTeamTaskOperation(store, 'teamTask.update',
    {task: task({eventIds: ['e1', 'e7']})}, manager, now), status(404, 'האירוע לא נמצא'));
});

test('addUpdate with tags: an inactive member is refused; setMentionDone by the tagged one', async () => {
  const store = new MemoryStore();
  await insert(store);
  await assert.rejects(
    runTeamTaskOperation(store, 'teamTask.addUpdate', {id: 't1', text: 'x', mentionIds: ['gone']}, owner, now),
    status(400, 'חבר צוות לא נמצא'),
  );
  const added = await runTeamTaskOperation(
    store, 'teamTask.addUpdate', {id: 't1', text: 'יוסי', mentionIds: ['b']}, owner, now);
  assert.deepEqual(added.after?.mentionIds, ['b']);
  assert.deepEqual(added.details['mentionIds'], ['b']);
  const tagged: TaskActor = {memberId: 'b', name: 'יוסי', isAdmin: false, canManageTasks: false};
  const done = await runTeamTaskOperation(store, 'teamTask.setMentionDone', {id: 't1', text: 'בוצע'}, tagged, now);
  assert.notEqual(done.after?.mentions[0].doneAt, null);
  assert.equal(done.after?.status, 'open');
  await assert.rejects(
    runTeamTaskOperation(store, 'teamTask.setStatus', {id: 't1', status: 'done'}, tagged, now),
    status(403),
  );
});
