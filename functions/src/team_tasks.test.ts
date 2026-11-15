import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {TaskActor, TaskError} from './tasks';
import {
  TeamTaskDoc,
  appendTeamTaskUpdate,
  applyTeamSubtaskToggle,
  applyTeamTaskEdit,
  applyTeamTaskStatus,
  buildNewTeamTask,
  deriveOwnerIds,
  isTeamTaskOwner,
  teamTaskAuditDetails,
  teamTaskFromStored,
} from './team_tasks';

const now = Timestamp.fromMillis(1_800_000_000_000);
const later = Timestamp.fromMillis(1_800_000_600_000);

const manager: TaskActor = {memberId: 'm-admin', name: 'מנהל', isAdmin: true, canManageTasks: false};
const flagged: TaskActor = {memberId: 'm-flag', name: 'רכזת', isAdmin: false, canManageTasks: true};
const ownerA: TaskActor = {memberId: 'a', name: 'דנה', isAdmin: false, canManageTasks: false};
const ownerB: TaskActor = {memberId: 'b', name: 'יוסי', isAdmin: false, canManageTasks: false};
const stranger: TaskActor = {memberId: 'z', name: 'אורח', isAdmin: false, canManageTasks: false};

function input(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 't1',
    title: 'להזמין אולם',
    description: 'לחנוכה',
    link: {type: 'topic', id: 'top1'},
    assigneeIds: ['a', 'b'],
    subtasks: [],
    contacts: [{id: 'c1', name: 'רונית', role: 'אולם', phone: '050-1234567'}],
    deadline: '2026-12-01',
    ...overrides,
  };
}

function withSubtasks(): TeamTaskDoc {
  return buildNewTeamTask(
    input({
      subtasks: [
        {id: 's1', title: 'מחיר', assigneeId: 'a', contacts: []},
        {id: 's2', title: 'חוזה', assigneeId: 'b', contacts: []},
      ],
    }),
    {now, actor: manager},
  );
}

function expectTaskError(fn: () => unknown, status: number, message?: string): void {
  assert.throws(fn, (error: unknown) => {
    assert.ok(error instanceof TaskError, `expected TaskError, got ${String(error)}`);
    assert.equal(error.status, status);
    if (message != null) assert.equal(error.message, message);
    return true;
  });
}

test('deriveOwnerIds uses assigneeIds without subtasks', () => {
  assert.deepEqual(deriveOwnerIds({assigneeIds: ['a', 'b'], subtasks: []}), ['a', 'b']);
});

test('deriveOwnerIds is the distinct subtask owners when there are subtasks', () => {
  const sub = (id: string, assigneeId: string | null) =>
    ({id, title: id, isDone: false, assigneeId, contacts: []});
  assert.deepEqual(
    deriveOwnerIds({
      assigneeIds: ['x'],
      subtasks: [sub('1', 'a'), sub('2', 'b'), sub('3', 'a'), sub('4', null)],
    }),
    ['a', 'b'],
  );
});

test('buildNewTeamTask clears assigneeIds when subtasks exist', () => {
  const task = withSubtasks();
  assert.deepEqual(task.assigneeIds, []);
  assert.deepEqual(task.ownerIds, ['a', 'b']);
  assert.equal(task.status, 'open');
  assert.equal(task.createdById, 'm-admin');
  assert.equal(task.contacts.length, 1);
});

test('buildNewTeamTask refuses a non-manager', () => {
  expectTaskError(() => buildNewTeamTask(input(), {now, actor: ownerA}), 403);
  // canManageTasks is enough.
  assert.equal(buildNewTeamTask(input(), {now, actor: flagged}).id, 't1');
});

test('buildNewTeamTask refuses an empty title', () => {
  expectTaskError(
    () => buildNewTeamTask(input({title: '  '}), {now, actor: manager}),
    400,
    'חובה להזין כותרת',
  );
});

test('deadline must be yyyy-MM-dd or null', () => {
  expectTaskError(() => buildNewTeamTask(input({deadline: '15.11'}), {now, actor: manager}), 400);
  assert.equal(buildNewTeamTask(input({deadline: null}), {now, actor: manager}).deadline, null);
  assert.equal(buildNewTeamTask(input({deadline: ''}), {now, actor: manager}).deadline, null);
});

test('link type must be event, category or topic', () => {
  expectTaskError(
    () => buildNewTeamTask(input({link: {type: 'stage', id: 'x'}}), {now, actor: manager}),
    400,
  );
  assert.equal(buildNewTeamTask(input({link: null}), {now, actor: manager}).link, null);
});

test('ticking the last open subtask sets done and completedAt', () => {
  let task = withSubtasks();
  task = applyTeamSubtaskToggle(task, 's1', true, {now, actor: ownerA});
  assert.equal(task.status, 'inProgress');
  task = applyTeamSubtaskToggle(task, 's2', true, {now: later, actor: ownerB});
  assert.equal(task.status, 'done');
  assert.deepEqual(task.completedAt, later);
});

test('unticking a subtask of a done task sets inProgress and clears completedAt', () => {
  let task = withSubtasks();
  task = applyTeamSubtaskToggle(task, 's1', true, {now, actor: ownerA});
  task = applyTeamSubtaskToggle(task, 's2', true, {now, actor: ownerB});
  task = applyTeamSubtaskToggle(task, 's2', false, {now: later, actor: ownerB});
  assert.equal(task.status, 'inProgress');
  assert.equal(task.completedAt, null);
});

test('ticking the last subtask of a cancelled task keeps cancelled', () => {
  let task = withSubtasks();
  task = applyTeamTaskStatus(task, 'cancelled', null, {now, actor: manager});
  task = applyTeamSubtaskToggle(task, 's1', true, {now, actor: ownerA});
  task = applyTeamSubtaskToggle(task, 's2', true, {now, actor: ownerB});
  assert.equal(task.status, 'cancelled');
  assert.equal(task.completedAt, null);
});

test('duplicate requires duplicateOfId and refuses the task\'s own id', () => {
  const task = buildNewTeamTask(input(), {now, actor: manager});
  expectTaskError(() => applyTeamTaskStatus(task, 'duplicate', null, {now, actor: manager}), 400);
  expectTaskError(() => applyTeamTaskStatus(task, 'duplicate', 't1', {now, actor: manager}), 400);
  const dup = applyTeamTaskStatus(task, 'duplicate', 't0', {now, actor: manager});
  assert.equal(dup.status, 'duplicate');
  assert.equal(dup.duplicateOfId, 't0');
});

test('a non-duplicate status clears duplicateOfId', () => {
  let task = buildNewTeamTask(input(), {now, actor: manager});
  task = applyTeamTaskStatus(task, 'duplicate', 't0', {now, actor: manager});
  task = applyTeamTaskStatus(task, 'open', 't0', {now, actor: manager});
  assert.equal(task.duplicateOfId, null);
});

test('status done sets completedAt and leaving done clears it', () => {
  let task = buildNewTeamTask(input(), {now, actor: manager});
  task = applyTeamTaskStatus(task, 'done', null, {now: later, actor: ownerA});
  assert.deepEqual(task.completedAt, later);
  task = applyTeamTaskStatus(task, 'inProgress', null, {now, actor: ownerA});
  assert.equal(task.completedAt, null);
});

test('an owner may set status, a stranger may not', () => {
  const task = buildNewTeamTask(input(), {now, actor: manager});
  assert.equal(applyTeamTaskStatus(task, 'inProgress', null, {now, actor: ownerA}).status, 'inProgress');
  expectTaskError(() => applyTeamTaskStatus(task, 'inProgress', null, {now, actor: stranger}), 403);
});

test('only the subtask\'s owner or a manager ticks it', () => {
  const task = withSubtasks();
  expectTaskError(() => applyTeamSubtaskToggle(task, 's1', true, {now, actor: ownerB}), 403);
  assert.ok(applyTeamSubtaskToggle(task, 's1', true, {now, actor: ownerA}).subtasks[0].isDone);
  assert.ok(applyTeamSubtaskToggle(task, 's1', true, {now, actor: flagged}).subtasks[0].isDone);
  expectTaskError(() => applyTeamSubtaskToggle(task, 'nope', true, {now, actor: manager}), 404);
});

test('appendTeamTaskUpdate puts the newest first with author and time', () => {
  let task = buildNewTeamTask(input(), {now, actor: manager});
  task = appendTeamTaskUpdate(task, ' עדיין פתוח ', {now, actor: ownerA});
  task = appendTeamTaskUpdate(task, 'הבוט מוכן', {now: later, actor: manager});
  assert.equal(task.updates.length, 2);
  assert.equal(task.updates[0].text, 'הבוט מוכן');
  assert.equal(task.updates[0].byId, 'm-admin');
  assert.deepEqual(task.updates[0].at, later);
  assert.equal(task.updates[1].text, 'עדיין פתוח');
  assert.equal(task.updates[1].byName, 'דנה');
});

test('appendTeamTaskUpdate refuses blank text', () => {
  const task = buildNewTeamTask(input(), {now, actor: manager});
  expectTaskError(() => appendTeamTaskUpdate(task, '   ', {now, actor: ownerA}), 400);
  expectTaskError(() => appendTeamTaskUpdate(task, 'x', {now, actor: stranger}), 403);
});

test('applyTeamTaskEdit keeps ticks, status, log and recomputes owners', () => {
  let task = withSubtasks();
  task = applyTeamSubtaskToggle(task, 's1', true, {now, actor: ownerA});
  task = appendTeamTaskUpdate(task, 'התחלנו', {now, actor: ownerA});
  const edited = applyTeamTaskEdit(
    task,
    input({
      title: 'אולם לחנוכה',
      subtasks: [
        {id: 's1', title: 'מחיר', assigneeId: 'c', contacts: []},
        {id: 's2', title: 'חוזה', assigneeId: 'b', contacts: []},
      ],
    }),
    {now: later, actor: manager},
  );
  assert.equal(edited.title, 'אולם לחנוכה');
  assert.ok(edited.subtasks[0].isDone);
  assert.deepEqual(edited.ownerIds, ['c', 'b']);
  assert.equal(edited.updates.length, 1);
  assert.equal(edited.status, 'inProgress');
  assert.deepEqual(edited.createdAt, now);
  assert.deepEqual(edited.updatedAt, later);
  expectTaskError(() => applyTeamTaskEdit(task, input(), {now, actor: ownerA}), 403);
  expectTaskError(() => applyTeamTaskEdit(task, input({id: 'other'}), {now, actor: manager}), 400);
});

test('applyTeamTaskEdit: removing the last open subtask completes the task', () => {
  let task = withSubtasks();
  task = applyTeamSubtaskToggle(task, 's1', true, {now, actor: ownerA});
  const edited = applyTeamTaskEdit(
    task,
    input({subtasks: [{id: 's1', title: 'מחיר', assigneeId: 'a', contacts: []}]}),
    {now: later, actor: manager},
  );
  assert.equal(edited.status, 'done');
});

test('isTeamTaskOwner and audit details', () => {
  const task = withSubtasks();
  assert.ok(isTeamTaskOwner(task, ownerA));
  assert.ok(!isTeamTaskOwner(task, stranger));
  assert.equal(teamTaskAuditDetails(task)['name'], 'להזמין אולם');
});

test('teamTaskFromStored tolerates missing fields', () => {
  const task = teamTaskFromStored('t9', {title: 'x', status: 'weird'});
  assert.equal(task.status, 'open');
  assert.deepEqual(task.subtasks, []);
  assert.deepEqual(task.contacts, []);
  assert.deepEqual(task.updates, []);
  assert.equal(task.link, null);
  assert.equal(task.deadline, null);
});
