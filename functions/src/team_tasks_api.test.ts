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
    subtasks: [{id: 's1', title: 'x', assigneeId: 'gone'}],
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
  await insert(store, {assigneeIds: [], subtasks: [{id: 's1', title: 'x', assigneeId: 'a'}]});
  const ticked = await runTeamTaskOperation(store, 'teamTask.setSubtaskDone',
    {id: 't1', subtaskId: 's1', isDone: true}, owner, now);
  assert.equal(ticked.after?.status, 'done');
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
