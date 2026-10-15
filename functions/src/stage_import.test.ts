import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';

import {buildStageImport, importEventId, MAX_IMPORT_STAGES, MAX_IMPORT_TASKS} from './stage_import';
import {TaskActor, TaskError} from './tasks';

const now = Timestamp.fromMillis(1_800_000_000_000);
const manager: TaskActor = {memberId: 'm-admin', name: 'מנהל', isAdmin: true, canManageTasks: false};
const ctx = {now, actor: manager};
const days = ['2026-06-15', '2026-06-16'];

function stage(id: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id, eventId: 'e1', title: `שלב ${id}`, date: '2026-06-15',
    startTime: null, endTime: null, requirements: '', hotelLocation: '', notes: '', contacts: [],
    ...overrides,
  };
}

function task(id: string, stageId: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id, eventId: 'e1', stageId, title: `משימה ${id}`, description: '',
    assemblyTime: null, assigneeIds: ['m1'], subtasks: [],
    ...overrides,
  };
}

function payload(stages: unknown[]): Record<string, unknown> {
  return {eventId: 'e1', stages};
}

function rejects(fn: () => unknown, status: number) {
  assert.throws(fn, (error: unknown) => error instanceof TaskError && error.status === status);
}

test('builds every stage and task of the import', () => {
  const built = buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('t1', 's1'), task('t2', 's1')]},
    {stage: stage('s2', {date: '2026-06-16'}), tasks: []},
  ]), ctx, days);

  assert.equal(built.eventId, 'e1');
  assert.deepEqual(built.stages.map((s) => s.id), ['s1', 's2']);
  assert.deepEqual(built.tasks.map((t) => [t.id, t.stageId]), [['t1', 's1'], ['t2', 's1']]);
  assert.equal(built.stages[0].createdById, 'm-admin');
  assert.equal(built.tasks[0].isComplete, false);
});

test('a stage without tasks may leave the tasks list out', () => {
  const built = buildStageImport(payload([{stage: stage('s1')}]), ctx, days);
  assert.equal(built.tasks.length, 0);
});

test('an import needs at least one stage and at most the cap', () => {
  rejects(() => buildStageImport(payload([]), ctx, days), 400);
  rejects(() => buildStageImport({eventId: 'e1'}, ctx, days), 400);
  const tooMany = Array.from({length: MAX_IMPORT_STAGES + 1}, (_, i) => ({stage: stage(`s${i}`)}));
  rejects(() => buildStageImport(payload(tooMany), ctx, days), 400);
});

test('at most the task cap across all stages', () => {
  const half = Math.ceil((MAX_IMPORT_TASKS + 1) / 2);
  const tasksOf = (stageId: string) =>
    Array.from({length: half}, (_, i) => task(`${stageId}-t${i}`, stageId));
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: tasksOf('s1')},
    {stage: stage('s2'), tasks: tasksOf('s2')},
  ]), ctx, days), 400);
});

test('every stage and task must belong to the import\'s event and stage', () => {
  rejects(() => buildStageImport(payload([{stage: stage('s1', {eventId: 'e2'})}]), ctx, days), 400);
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('t1', 's2')]},
  ]), ctx, days), 400);
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('t1', 's1', {eventId: 'e2'})]},
  ]), ctx, days), 400);
});

test('ids are unique across the whole import', () => {
  rejects(() => buildStageImport(payload([{stage: stage('s1')}, {stage: stage('s1')}]), ctx, days), 400);
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('x', 's1'), task('x', 's1')]},
  ]), ctx, days), 400);
});

test('each stage and task is validated like a single create', () => {
  rejects(() => buildStageImport(payload([{stage: stage('s1', {date: '2026-07-01'})}]), ctx, days), 400);
  rejects(() => buildStageImport(payload([{stage: stage('s1', {title: ''})}]), ctx, days), 400);
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('t1', 's1', {title: ''})]},
  ]), ctx, days), 400);
});

test('importEventId needs a valid id', () => {
  assert.equal(importEventId({eventId: 'e1'}), 'e1');
  rejects(() => importEventId({}), 400);
  rejects(() => importEventId({eventId: 'a/b'}), 400);
});
