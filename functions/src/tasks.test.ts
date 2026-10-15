import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {
  TaskActor,
  TaskDoc,
  TaskError,
  applyAssigneeUpdate,
  applySetComplete,
  applySubtaskToggle,
  applyTaskEdit,
  buildNewTask,
  canManageTasks,
  isTaskAssignee,
  requireTaskManager,
  requireTaskParticipant,
  taskAuditDetails,
  taskFromStored,
} from './tasks';

const now = Timestamp.fromMillis(1_800_000_000_000);
const later = Timestamp.fromMillis(1_800_000_600_000);

const manager: TaskActor = {
  memberId: 'm-admin',
  name: 'מנהל',
  isAdmin: true,
  canManageTasks: false,
};
const flagged: TaskActor = {
  memberId: 'm-flag',
  name: 'רכזת',
  isAdmin: false,
  canManageTasks: true,
};
const assignee: TaskActor = {
  memberId: 'm1',
  name: 'דנה',
  isAdmin: false,
  canManageTasks: false,
};
const outsider: TaskActor = {
  memberId: 'm9',
  name: 'אורח',
  isAdmin: false,
  canManageTasks: false,
};

function baseInput(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 't1',
    eventId: 'e1',
    stageId: 's1',
    title: 'להזמין אוטובוס',
    description: 'שני אוטובוסים',
    assemblyTime: '07:30',
    assigneeIds: ['m1', 'm2'],
    subtasks: [
      {id: 'a', title: 'הצעת מחיר'},
      {id: 'b', title: 'אישור'},
    ],
    ...overrides,
  };
}

function newTask(overrides: Record<string, unknown> = {}): TaskDoc {
  return buildNewTask(baseInput(overrides), {now, actor: manager});
}

function assertTaskError(fn: () => unknown, status: number): TaskError {
  try {
    fn();
  } catch (error) {
    assert.ok(error instanceof TaskError, `expected TaskError, got ${error}`);
    assert.equal(error.status, status);
    return error;
  }
  assert.fail('expected a TaskError to be thrown');
}

// ---- permissions ----

test('an admin and a flagged member can manage tasks; a plain member cannot', () => {
  assert.equal(canManageTasks(manager), true);
  assert.equal(canManageTasks(flagged), true);
  assert.equal(canManageTasks(assignee), false);
});

test('requireTaskManager rejects a plain member with 403', () => {
  assertTaskError(() => requireTaskManager(assignee), 403);
  requireTaskManager(flagged);
});

test('isTaskAssignee is membership in assigneeIds', () => {
  const task = newTask();
  assert.equal(isTaskAssignee(task, assignee), true);
  assert.equal(isTaskAssignee(task, outsider), false);
});

test('requireTaskParticipant passes an assignee and a flagged manager, rejects an outsider with 403', () => {
  const task = newTask();
  requireTaskParticipant(task, assignee);
  requireTaskParticipant(task, flagged);
  requireTaskParticipant(task, manager);
  assertTaskError(() => requireTaskParticipant(task, outsider), 403);
});

// ---- buildNewTask ----

test('buildNewTask builds an open task stamped with the injected time and actor', () => {
  const task = newTask();
  assert.equal(task.id, 't1');
  assert.equal(task.eventId, 'e1');
  assert.equal(task.title, 'להזמין אוטובוס');
  assert.equal(task.description, 'שני אוטובוסים');
  assert.deepEqual(task.assigneeIds, ['m1', 'm2']);
  assert.deepEqual(task.subtasks, [
    {id: 'a', title: 'הצעת מחיר', isDone: false},
    {id: 'b', title: 'אישור', isDone: false},
  ]);
  assert.equal(task.stageId, 's1');
  assert.equal(task.assemblyTime, '07:30');
  assert.equal(task.isComplete, false);
  assert.equal(task.completedAt, null);
  assert.equal(task.completedById, null);
  assert.equal(task.assigneeUpdate, null);
  assert.equal(task.createdAt, now);
  assert.equal(task.updatedAt, now);
  assert.equal(task.createdById, 'm-admin');
});

test('buildNewTask ignores an isDone sent by the client: new subtasks always start open', () => {
  const task = newTask({subtasks: [{id: 'a', title: 'א', isDone: true}]});
  assert.equal(task.subtasks[0].isDone, false);
  assert.equal(task.isComplete, false);
});

test('buildNewTask trims the title and subtask titles and de-duplicates assignees', () => {
  const task = newTask({
    title: '  כותרת  ',
    assigneeIds: ['m1', 'm1', 'm2'],
    subtasks: [{id: 'a', title: '  שלב  '}],
  });
  assert.equal(task.title, 'כותרת');
  assert.deepEqual(task.assigneeIds, ['m1', 'm2']);
  assert.equal(task.subtasks[0].title, 'שלב');
});

test('buildNewTask accepts no subtasks, no description and no assembly time', () => {
  const task = newTask({subtasks: undefined, description: undefined, assemblyTime: null});
  assert.deepEqual(task.subtasks, []);
  assert.equal(task.description, '');
  assert.equal(task.assemblyTime, null);
  assert.equal(newTask({assemblyTime: ''}).assemblyTime, null);
});

test('buildNewTask stores no due date: the stage date and assembly time replace it', () => {
  const task = newTask({dueAt: '2026-10-20T07:30:00.000Z'});
  assert.equal('dueAt' in task, false);
});

test('buildNewTask rejects invalid input with 400', () => {
  const invalid: Record<string, unknown>[] = [
    {title: '   '},
    {title: 'x'.repeat(201)},
    {description: 'x'.repeat(5001)},
    {eventId: ''},
    {stageId: ''},
    {stageId: undefined},
    {stageId: 'a/b'},
    {id: ''},
    {assigneeIds: []},
    {assigneeIds: 'm1'},
    {assigneeIds: Array.from({length: 101}, (_, i) => `m${i}`)},
    {assemblyTime: '7:30'},
    {assemblyTime: '24:00'},
    {assemblyTime: '07:60'},
    {assemblyTime: 730},
    {subtasks: [{id: 'a', title: '  '}]},
    {subtasks: [{id: '', title: 'x'}]},
    {subtasks: [{id: 'a', title: 'x'}, {id: 'a', title: 'y'}]},
    {subtasks: Array.from({length: 51}, (_, i) => ({id: `s${i}`, title: 'x'}))},
    {subtasks: [{id: 'a', title: 'x'.repeat(201)}]},
    {subtasks: 'nope'},
  ];
  for (const overrides of invalid) {
    assertTaskError(() => newTask(overrides), 400);
  }
});

test('buildNewTask rejects an id that is not a plain document id', () => {
  // The id becomes a Firestore document path segment: a slash would address a
  // nested document instead of a task.
  for (const id of ['a/b/c', '../x', 'has space', 'x'.repeat(65), '.']) {
    assertTaskError(() => newTask({id}), 400);
  }
  assert.equal(newTask({id: '3f2a9c1e-7b4d-4e8a-9c0f-1a2b3c4d5e6f'}).id.length, 36);
});


// ---- audit details ----

test('taskAuditDetails names the task so the log viewer can show it', () => {
  const details = taskAuditDetails(newTask(), {isDone: true});
  assert.deepEqual(details, {
    name: 'להזמין אוטובוס',
    eventId: 'e1',
    isDone: true,
  });
});

// ---- applyTaskEdit ----

test('applyTaskEdit replaces the editable fields and bumps updatedAt only', () => {
  const existing = newTask();
  const edited = applyTaskEdit(
    existing,
    baseInput({
      title: 'כותרת חדשה',
      description: '',
      assemblyTime: null,
      assigneeIds: ['m3'],
    }),
    {now: later, actor: flagged},
  );
  assert.equal(edited.eventId, 'e1');
  assert.equal(edited.stageId, 's1');
  assert.equal(edited.title, 'כותרת חדשה');
  assert.equal(edited.description, '');
  assert.equal(edited.assemblyTime, null);
  assert.deepEqual(edited.assigneeIds, ['m3']);
  assert.equal(edited.updatedAt, later);
  assert.equal(edited.createdAt, now);
  assert.equal(edited.createdById, 'm-admin');
  assert.equal(edited.id, 't1');
});

test('applyTaskEdit cannot move a task to another stage or event', () => {
  const existing = newTask();
  assertTaskError(
    () => applyTaskEdit(existing, baseInput({stageId: 's2'}), {now: later, actor: flagged}),
    400,
  );
  assertTaskError(
    () => applyTaskEdit(existing, baseInput({eventId: 'e2'}), {now: later, actor: flagged}),
    400,
  );
});

test('applyTaskEdit keeps isDone for a surviving subtask id and opens a new one', () => {
  const existing = applySubtaskToggle(newTask(), 'a', true, {now, actor: assignee});
  const edited = applyTaskEdit(
    existing,
    baseInput({
      subtasks: [
        {id: 'a', title: 'שם חדש'},
        {id: 'c', title: 'חדש'},
      ],
    }),
    {now: later, actor: manager},
  );
  assert.deepEqual(edited.subtasks, [
    {id: 'a', title: 'שם חדש', isDone: true},
    {id: 'c', title: 'חדש', isDone: false},
  ]);
});

test('applyTaskEdit does not touch the assignee update', () => {
  const existing = applyAssigneeUpdate(newTask(), 'בטיפול', {now, actor: assignee});
  const edited = applyTaskEdit(existing, baseInput({title: 'אחר'}), {now: later, actor: manager});
  assert.equal(edited.assigneeUpdate, 'בטיפול');
  assert.equal(edited.assigneeUpdateAt, now);
  assert.equal(edited.assigneeUpdateById, 'm1');
  assert.equal(edited.assigneeUpdateByName, 'דנה');
});

test('applyTaskEdit cannot change the task id', () => {
  assertTaskError(
    () => applyTaskEdit(newTask(), baseInput({id: 'other'}), {now: later, actor: manager}),
    400,
  );
});

test('editing a completed task to add a subtask reopens it', () => {
  let task = newTask();
  task = applySubtaskToggle(task, 'a', true, {now, actor: assignee});
  task = applySubtaskToggle(task, 'b', true, {now, actor: assignee});
  assert.equal(task.isComplete, true);

  const edited = applyTaskEdit(
    task,
    baseInput({
      subtasks: [
        {id: 'a', title: 'הצעת מחיר'},
        {id: 'b', title: 'אישור'},
        {id: 'c', title: 'תשלום'},
      ],
    }),
    {now: later, actor: manager},
  );
  assert.equal(edited.isComplete, false);
  assert.equal(edited.completedAt, null);
  assert.equal(edited.completedById, null);
});

test('editing away the only open subtask completes the task', () => {
  const half = applySubtaskToggle(newTask(), 'a', true, {now, actor: assignee});
  const edited = applyTaskEdit(
    half,
    baseInput({subtasks: [{id: 'a', title: 'הצעת מחיר'}]}),
    {now: later, actor: manager},
  );
  assert.equal(edited.isComplete, true);
  assert.equal(edited.completedAt, later);
  assert.equal(edited.completedById, 'm-admin');
});

test('removing every subtask leaves completion as it was', () => {
  const open = applyTaskEdit(newTask(), baseInput({subtasks: []}), {now: later, actor: manager});
  assert.equal(open.isComplete, false);

  let done = newTask();
  done = applySubtaskToggle(done, 'a', true, {now, actor: assignee});
  done = applySubtaskToggle(done, 'b', true, {now, actor: assignee});
  const stillDone = applyTaskEdit(done, baseInput({subtasks: []}), {now: later, actor: manager});
  assert.equal(stillDone.isComplete, true);
  assert.equal(stillDone.completedAt, now);
  assert.equal(stillDone.completedById, 'm1');
});

// ---- applySubtaskToggle ----

test('ticking the last open subtask completes the task and stamps who and when', () => {
  const half = applySubtaskToggle(newTask(), 'a', true, {now, actor: assignee});
  assert.equal(half.isComplete, false);
  assert.equal(half.completedAt, null);

  const done = applySubtaskToggle(half, 'b', true, {now: later, actor: assignee});
  assert.equal(done.isComplete, true);
  assert.equal(done.completedAt, later);
  assert.equal(done.completedById, 'm1');
  assert.equal(done.updatedAt, later);
});

test('toggling one subtask leaves the stored state of the others alone', () => {
  const stored = applySubtaskToggle(newTask(), 'a', true, {now, actor: assignee});
  const next = applySubtaskToggle(stored, 'b', true, {now: later, actor: flagged});
  assert.deepEqual(next.subtasks, [
    {id: 'a', title: 'הצעת מחיר', isDone: true},
    {id: 'b', title: 'אישור', isDone: true},
  ]);
  assert.equal(next.isComplete, true);
});

test('unticking a subtask of a completed task reopens it', () => {
  let task = newTask();
  task = applySubtaskToggle(task, 'a', true, {now, actor: assignee});
  task = applySubtaskToggle(task, 'b', true, {now, actor: assignee});
  const reopened = applySubtaskToggle(task, 'a', false, {now: later, actor: manager});
  assert.equal(reopened.isComplete, false);
  assert.equal(reopened.completedAt, null);
  assert.equal(reopened.completedById, null);
});

test('re-ticking an already completed task keeps the original completion stamp', () => {
  let task = newTask();
  task = applySubtaskToggle(task, 'a', true, {now, actor: assignee});
  task = applySubtaskToggle(task, 'b', true, {now, actor: assignee});
  const again = applySubtaskToggle(task, 'b', true, {now: later, actor: manager});
  assert.equal(again.completedAt, now);
  assert.equal(again.completedById, 'm1');
  assert.equal(again.updatedAt, later);
});

test('toggling a subtask that is no longer on the task is a 404', () => {
  assertTaskError(
    () => applySubtaskToggle(newTask(), 'gone', true, {now, actor: assignee}),
    404,
  );
});

// ---- applySetComplete ----

test('a task without subtasks is completed and reopened by hand', () => {
  const task = newTask({subtasks: []});
  const done = applySetComplete(task, true, {now: later, actor: assignee});
  assert.equal(done.isComplete, true);
  assert.equal(done.completedAt, later);
  assert.equal(done.completedById, 'm1');
  assert.equal(done.updatedAt, later);

  const reopened = applySetComplete(done, false, {now, actor: manager});
  assert.equal(reopened.isComplete, false);
  assert.equal(reopened.completedAt, null);
  assert.equal(reopened.completedById, null);
});

test('a task with subtasks cannot be completed by hand', () => {
  assertTaskError(() => applySetComplete(newTask(), true, {now, actor: manager}), 400);
});

// ---- applyAssigneeUpdate ----

test('saving the assignee update records the text, the author and the time', () => {
  const updated = applyAssigneeUpdate(newTask(), '  ממתין לאישור  ', {now: later, actor: assignee});
  assert.equal(updated.assigneeUpdate, 'ממתין לאישור');
  assert.equal(updated.assigneeUpdateAt, later);
  assert.equal(updated.assigneeUpdateById, 'm1');
  assert.equal(updated.assigneeUpdateByName, 'דנה');
  assert.equal(updated.updatedAt, later);
});

test('saving an empty assignee update clears the note', () => {
  const withNote = applyAssigneeUpdate(newTask(), 'בטיפול', {now, actor: assignee});
  const cleared = applyAssigneeUpdate(withNote, '   ', {now: later, actor: manager});
  assert.equal(cleared.assigneeUpdate, null);
  assert.equal(cleared.assigneeUpdateAt, null);
  assert.equal(cleared.assigneeUpdateById, null);
  assert.equal(cleared.assigneeUpdateByName, null);
  assert.equal(cleared.updatedAt, later);
});

test('an assignee update longer than 2000 characters is rejected', () => {
  assertTaskError(
    () => applyAssigneeUpdate(newTask(), 'x'.repeat(2001), {now, actor: assignee}),
    400,
  );
});

test('the assignee update does not change completion or subtasks', () => {
  const half = applySubtaskToggle(newTask(), 'a', true, {now, actor: assignee});
  const updated = applyAssigneeUpdate(half, 'בדרך', {now: later, actor: assignee});
  assert.deepEqual(updated.subtasks, half.subtasks);
  assert.equal(updated.isComplete, false);
});

// ---- taskFromStored ----

test('taskFromStored fills defaults for a document missing its optional fields', () => {
  const task = taskFromStored('t9', {
    eventId: 'e1',
    title: 'ישן',
    assigneeIds: ['m1'],
    createdAt: now,
    createdById: 'm-admin',
    updatedAt: now,
  });
  assert.equal(task.id, 't9');
  assert.equal(task.description, '');
  assert.deepEqual(task.subtasks, []);
  assert.equal(task.stageId, '');
  assert.equal(task.assemblyTime, null);
  assert.equal(task.assigneeUpdate, null);
  assert.equal(task.assigneeUpdateAt, null);
  assert.equal(task.assigneeUpdateById, null);
  assert.equal(task.assigneeUpdateByName, null);
  assert.equal(task.isComplete, false);
  assert.equal(task.completedAt, null);
  assert.equal(task.completedById, null);
});

test('taskFromStored round-trips a document built by buildNewTask', () => {
  const built = newTask();
  const {id, ...stored} = built;
  assert.deepEqual(taskFromStored(id, stored), built);
});

test('taskFromStored drops malformed subtask entries instead of throwing', () => {
  const task = taskFromStored('t9', {
    eventId: 'e1',
    title: 'ישן',
    assigneeIds: ['m1'],
    subtasks: [{id: 'a', title: 'טוב', isDone: true}, 'זבל', {title: 'בלי מזהה'}, null],
    createdAt: now,
    createdById: 'm-admin',
    updatedAt: now,
  });
  assert.deepEqual(task.subtasks, [{id: 'a', title: 'טוב', isDone: true}]);
});
