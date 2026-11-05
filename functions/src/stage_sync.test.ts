import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';

import {buildStageSync, MAX_SYNC_WRITES, syncEventId} from './stage_sync';
import {StageDoc} from './stages';
import {TaskActor, TaskDoc, TaskError} from './tasks';

const earlier = Timestamp.fromMillis(1_700_000_000_000);
const now = Timestamp.fromMillis(1_800_000_000_000);
const manager: TaskActor = {memberId: 'm-admin', name: 'מנהל', isAdmin: true, canManageTasks: false};
const ctx = {now, actor: manager};
const days = ['2026-06-15', '2026-06-16'];

function stageInput(id: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id, eventId: 'e1', title: `שלב ${id}`, date: '2026-06-15',
    startTime: null, endTime: null, requirements: '', hotelLocation: '', notes: '', contacts: [],
    ...overrides,
  };
}

function taskInput(id: string, stageId: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id, eventId: 'e1', stageId, title: `משימה ${id}`, description: '',
    assemblyTime: null, assigneeIds: ['m1'], subtasks: [],
    ...overrides,
  };
}

function storedStage(id: string): StageDoc {
  return {
    id, eventId: 'e1', title: `שלב ${id}`, date: '2026-06-15', startTime: null, endTime: null,
    requirements: '', hotelLocation: '', notes: '', contacts: [],
    createdAt: earlier, createdById: 'm-old', updatedAt: earlier,
  };
}

function storedTask(id: string, stageId: string, overrides: Partial<TaskDoc> = {}): TaskDoc {
  return {
    id, eventId: 'e1', stageId, title: `משימה ${id}`, description: '', subtasks: [],
    assemblyTime: null, assigneeIds: ['m1'],
    assigneeUpdate: null, assigneeUpdateAt: null, assigneeUpdateById: null, assigneeUpdateByName: null,
    isComplete: false, completedAt: null, completedById: null,
    createdAt: earlier, createdById: 'm-old', updatedAt: earlier,
    ...overrides,
  };
}

type Sections = {
  stages?: {create?: unknown[]; update?: unknown[]; delete?: unknown[]};
  tasks?: {create?: unknown[]; update?: unknown[]; delete?: unknown[]};
};

function sync(sections: Sections, stages: StageDoc[], tasks: TaskDoc[]) {
  return buildStageSync({eventId: 'e1', ...sections}, ctx, days, stages, tasks);
}

function rejects(fn: () => unknown, status: number) {
  assert.throws(fn, (error: unknown) => error instanceof TaskError && error.status === status);
}

test('syncEventId needs a valid id', () => {
  assert.equal(syncEventId({eventId: 'e1'}), 'e1');
  rejects(() => syncEventId({}), 400);
  rejects(() => syncEventId({eventId: 'a/b'}), 400);
});

test('creates, updates and deletes stages and tasks', () => {
  const built = sync({
    stages: {create: [stageInput('s2')], update: [stageInput('s1', {notes: 'חדש'})], delete: ['s3']},
    tasks: {
      create: [taskInput('t9', 's2', {assigneeIds: ['m7']})],
      update: [taskInput('t1', 's1', {description: 'עודכן'})],
      delete: ['t3'],
    },
  }, [storedStage('s1'), storedStage('s3')], [storedTask('t1', 's1'), storedTask('t3', 's3')]);

  assert.deepEqual(built.stageWrites.map((s) => s.id), ['s2', 's1']);
  assert.equal(built.stageWrites[1].notes, 'חדש');
  assert.equal(built.stageWrites[1].createdById, 'm-old');
  assert.deepEqual(built.stageDeletes, ['s3']);
  assert.deepEqual(built.taskWrites.map((t) => t.id), ['t9', 't1']);
  assert.equal(built.taskWrites[1].description, 'עודכן');
  assert.deepEqual(built.taskDeletes, ['t3']);
  assert.deepEqual(built.newAssigneeIds, ['m7']);
});

test('an updated task keeps its ticks, completion and note', () => {
  const existing = storedTask('t1', 's1', {
    subtasks: [{id: 'a', title: 'א', isDone: true}, {id: 'b', title: 'ב', isDone: true}],
    isComplete: true, completedAt: earlier, completedById: 'm1',
    assigneeUpdate: 'בדרך', assigneeUpdateById: 'm1',
  });
  const built = sync({
    tasks: {update: [taskInput('t1', 's1', {
      subtasks: [{id: 'a', title: 'א מעודכן'}, {id: 'b', title: 'ב'}],
    })]},
  }, [storedStage('s1')], [existing]);

  const task = built.taskWrites[0];
  assert.deepEqual(task.subtasks.map((s) => s.isDone), [true, true]);
  assert.equal(task.subtasks[0].title, 'א מעודכן');
  assert.equal(task.isComplete, true);
  assert.equal(task.completedById, 'm1');
  assert.equal(task.assigneeUpdate, 'בדרך');
});

test('a new subtask on a complete task reopens it', () => {
  const existing = storedTask('t1', 's1', {
    subtasks: [{id: 'a', title: 'א', isDone: true}], isComplete: true, completedAt: earlier,
  });
  const built = sync({
    tasks: {update: [taskInput('t1', 's1', {subtasks: [{id: 'a', title: 'א'}, {id: 'n', title: 'חדש'}]})]},
  }, [storedStage('s1')], [existing]);
  assert.equal(built.taskWrites[0].isComplete, false);
});

test('a task moves to another stage, also to a new one', () => {
  const built = sync({
    stages: {create: [stageInput('s2')], delete: ['s1']},
    tasks: {update: [taskInput('t1', 's2')]},
  }, [storedStage('s1'), storedStage('s0')], [storedTask('t1', 's1', {isComplete: true})]);
  assert.equal(built.taskWrites[0].stageId, 's2');
  assert.equal(built.taskWrites[0].isComplete, true);
  assert.deepEqual(built.stageDeletes, ['s1']);
});

test('only newly added assignees are checked', () => {
  const built = sync({
    tasks: {update: [taskInput('t1', 's1', {assigneeIds: ['m1', 'm2']})]},
  }, [storedStage('s1')], [storedTask('t1', 's1', {assigneeIds: ['m1']})]);
  assert.deepEqual(built.newAssigneeIds, ['m2']);
});

test('a replay skips what is already there or already gone', () => {
  const built = sync({
    stages: {create: [stageInput('s2')], delete: ['gone']},
    tasks: {create: [taskInput('t2', 's2')], delete: ['gone-task']},
  }, [storedStage('s1'), storedStage('s2')], [storedTask('t2', 's2')]);
  assert.equal(built.stageWrites.length, 0);
  assert.equal(built.taskWrites.length, 0);
  assert.deepEqual(built.stageDeletes, []);
  assert.deepEqual(built.taskDeletes, []);
});

test('updating a stage or task that was deleted meanwhile is stale', () => {
  rejects(() => sync({stages: {update: [stageInput('s9')]}}, [storedStage('s1')], []), 409);
  rejects(() => sync({tasks: {update: [taskInput('t9', 's1')]}}, [storedStage('s1')], []), 409);
});

test('a task under a missing or deleted stage is stale', () => {
  rejects(() => sync({tasks: {create: [taskInput('t2', 's9')]}}, [storedStage('s1')], []), 409);
  rejects(() => sync({
    stages: {delete: ['s2']},
    tasks: {update: [taskInput('t1', 's2')]},
  }, [storedStage('s1'), storedStage('s2')], [storedTask('t1', 's1')]), 409);
});

test('a task left behind under a deleted stage is stale, not deleted unseen', () => {
  rejects(() => sync(
    {stages: {delete: ['s2']}},
    [storedStage('s1'), storedStage('s2')],
    [storedTask('new-meanwhile', 's2')],
  ), 409);
});

test('the event cannot end up with no stages', () => {
  rejects(() => sync({stages: {delete: ['s1']}}, [storedStage('s1')], []), 400);
});

test('ids may not repeat across the sync', () => {
  rejects(() => sync({
    stages: {create: [stageInput('x')]},
    tasks: {delete: ['x']},
  }, [storedStage('s1')], []), 400);
});

test('a stage or task of another event is refused', () => {
  rejects(() => sync({stages: {create: [stageInput('s2', {eventId: 'e2'})]}}, [storedStage('s1')], []), 400);
  rejects(() => sync({tasks: {create: [taskInput('t2', 's1', {eventId: 'e2'})]}}, [storedStage('s1')], []), 400);
});

test('a stage date outside the event is refused', () => {
  rejects(() => sync({stages: {create: [stageInput('s2', {date: '2026-07-01'})]}}, [storedStage('s1')], []), 400);
});

test('too many writes are refused', () => {
  const stage = storedStage('s1');
  const tasks = Array.from({length: MAX_SYNC_WRITES + 1}, (_, i) => storedTask(`t${i}`, 's1'));
  rejects(() => sync({tasks: {delete: tasks.map((t) => t.id)}}, [stage], tasks), 400);
});

test('malformed sections are refused', () => {
  rejects(() => sync({stages: {create: 'x' as unknown as unknown[]}}, [storedStage('s1')], []), 400);
  rejects(() => sync({tasks: {delete: [3]}}, [storedStage('s1')], []), 400);
});
