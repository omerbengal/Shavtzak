import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {TaskActor, TaskError} from './tasks';
import {
  TeamSubtask,
  TeamTaskDoc,
  appendTeamTaskUpdate,
  applyTeamSubtaskStatus,
  applyTeamSubtaskToggle,
  applyTeamTaskEdit,
  applyTeamTaskStatus,
  buildNewTeamTask,
  deriveOwnerIds,
  deriveParentStatus,
  deleteTeamTaskUpdate,
  editTeamTaskUpdate,
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
        {id: 's1', title: 'מחיר', assigneeIds: ['a'], contacts: []},
        {id: 's2', title: 'חוזה', assigneeIds: ['b'], contacts: []},
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
  const sub = (id: string, assigneeIds: string[]) => ({
    id, title: id, description: '', assigneeIds, contacts: [], deadline: null,
    status: 'open' as const, duplicateOfId: null, updates: [], completedAt: null,
  });
  assert.deepEqual(
    deriveOwnerIds({
      assigneeIds: ['x'],
      subtasks: [sub('1', ['a']), sub('2', ['b', 'c']), sub('3', ['a']), sub('4', [])],
    }),
    ['a', 'b', 'c'],
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

test("a parent's status is never set by hand", () => {
  const task = withSubtasks();
  expectTaskError(
    () => applyTeamTaskStatus(task, 'cancelled', null, {now, actor: manager}),
    400,
    'הסטטוס של משימת אב נקבע לפי תתי-המשימות',
  );
});

test("deriveParentStatus follows Omer's round-4 rules", () => {
  const sub = (status: TeamSubtask['status']): TeamSubtask => ({
    id: status, title: status, description: '', assigneeIds: [], contacts: [], deadline: null,
    status, duplicateOfId: null, updates: [], completedAt: null,
  });
  // Cancelled and duplicate subtasks do not count.
  assert.equal(deriveParentStatus([sub('open'), sub('open'), sub('cancelled')]), 'open');
  assert.equal(deriveParentStatus([sub('done'), sub('duplicate'), sub('done')]), 'done');
  assert.equal(deriveParentStatus([sub('open'), sub('inProgress'), sub('done')]), 'inProgress');
  // Not in the rules: open and done mixed = in progress; nothing left = cancelled.
  assert.equal(deriveParentStatus([sub('open'), sub('done')]), 'inProgress');
  assert.equal(deriveParentStatus([sub('cancelled'), sub('duplicate')]), 'cancelled');
});

test('cancelling every subtask cancels the parent; reopening one reopens it', () => {
  let task = withSubtasks();
  task = applyTeamSubtaskStatus(task, 's1', 'cancelled', null, {now, actor: ownerA});
  task = applyTeamSubtaskStatus(task, 's2', 'cancelled', null, {now, actor: ownerB});
  assert.equal(task.status, 'cancelled');
  assert.equal(task.completedAt, null);
  task = applyTeamSubtaskStatus(task, 's2', 'open', null, {now, actor: ownerB});
  assert.equal(task.status, 'open');
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
  assert.ok(applyTeamSubtaskToggle(task, 's1', true, {now, actor: ownerA}).subtasks[0].status === 'done');
  assert.ok(applyTeamSubtaskToggle(task, 's1', true, {now, actor: flagged}).subtasks[0].status === 'done');
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
        {id: 's1', title: 'מחיר', assigneeIds: ['c'], contacts: []},
        {id: 's2', title: 'חוזה', assigneeIds: ['b'], contacts: []},
      ],
    }),
    {now: later, actor: manager},
  );
  assert.equal(edited.title, 'אולם לחנוכה');
  assert.ok(edited.subtasks[0].status === 'done');
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
    input({subtasks: [{id: 's1', title: 'מחיר', assigneeIds: ['a'], contacts: []}]}),
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

test('an edit recomputes a stored parent status that does not fit its subtasks', () => {
  let task = withSubtasks();
  task = applyTeamSubtaskToggle(task, 's1', true, {now, actor: ownerA});
  // A document written before round 4 may hold a status set by hand.
  task = {...task, status: 'done'};
  const edited = applyTeamTaskEdit(task, input({
    title: 'אולם חדש',
    subtasks: [
      {id: 's1', title: 'מחיר', assigneeIds: ['a'], contacts: []},
      {id: 's2', title: 'חוזה מעודכן', assigneeIds: ['b'], contacts: []},
    ],
  }), {now: later, actor: manager});
  assert.equal(edited.status, 'inProgress');
  assert.equal(edited.completedAt, null);
});

test('a subtask is a full task: its fields, its status and its own log', () => {
  let task = buildNewTeamTask(input({
    assigneeIds: [],
    subtasks: [{
      id: 's1', title: 'מחיר', description: 'שלוש הצעות', assigneeIds: ['a', 'b'],
      contacts: [{id: 'c9', name: 'רונית', role: '', phone: '050-1234567'}], deadline: '2026-11-30',
    }],
  }), {now, actor: manager});
  const sub = task.subtasks[0];
  assert.equal(sub.description, 'שלוש הצעות');
  assert.deepEqual(sub.assigneeIds, ['a', 'b']);
  assert.equal(sub.deadline, '2026-11-30');
  assert.equal(sub.status, 'open');
  assert.deepEqual(task.ownerIds, ['a', 'b']);
  task = applyTeamSubtaskStatus(task, 's1', 'inProgress', null, {now, actor: ownerB});
  assert.equal(task.subtasks[0].status, 'inProgress');
  assert.equal(task.status, 'inProgress');
  task = appendTeamTaskUpdate(task, 'ביקשתי הצעות', {now, actor: ownerA}, 's1');
  assert.equal(task.subtasks[0].updates[0].text, 'ביקשתי הצעות');
  assert.equal(task.updates.length, 0);
  expectTaskError(() => appendTeamTaskUpdate(task, 'x', {now, actor: stranger}, 's1'), 403);
  expectTaskError(
    () => applyTeamSubtaskStatus(task, 's1', 'done', null, {now, actor: stranger}), 403);
});

test('the parent is done when every subtask is closed and one is done', () => {
  let task = withSubtasks();
  task = applyTeamSubtaskStatus(task, 's1', 'cancelled', null, {now, actor: ownerA});
  assert.notEqual(task.status, 'done');
  task = applyTeamSubtaskStatus(task, 's2', 'done', null, {now: later, actor: ownerB});
  assert.equal(task.status, 'done');
  assert.deepEqual(task.completedAt, later);
  task = applyTeamSubtaskStatus(task, 's2', 'inProgress', null, {now: later, actor: ownerB});
  assert.equal(task.status, 'inProgress');
});

test('a subtask duplicate points elsewhere, never to itself', () => {
  const task = withSubtasks();
  expectTaskError(
    () => applyTeamSubtaskStatus(task, 's1', 'duplicate', 's1', {now, actor: manager}), 400);
  expectTaskError(
    () => applyTeamSubtaskStatus(task, 's1', 'duplicate', null, {now, actor: manager}), 400);
  const dup = applyTeamSubtaskStatus(task, 's1', 'duplicate', 's2', {now, actor: manager});
  assert.equal(dup.subtasks[0].duplicateOfId, 's2');
});

test('an edit keeps a subtask\'s status and log', () => {
  let task = withSubtasks();
  task = applyTeamSubtaskStatus(task, 's1', 'inProgress', null, {now, actor: ownerA});
  task = appendTeamTaskUpdate(task, 'עדכון', {now, actor: ownerA}, 's1');
  const edited = applyTeamTaskEdit(task, input({
    subtasks: [
      {id: 's1', title: 'מחיר חדש', assigneeIds: ['a'], deadline: '2026-12-05'},
      {id: 's2', title: 'חוזה', assigneeIds: ['b']},
    ],
  }), {now: later, actor: manager});
  assert.equal(edited.subtasks[0].title, 'מחיר חדש');
  assert.equal(edited.subtasks[0].deadline, '2026-12-05');
  assert.equal(edited.subtasks[0].status, 'inProgress');
  assert.equal(edited.subtasks[0].updates.length, 1);
});

test('a stored subtask from before round 2 still reads', () => {
  const task = teamTaskFromStored('t9', {
    title: 'x',
    subtasks: [
      {id: 's1', title: 'ישן', isDone: true, assigneeId: 'a'},
      {id: 's2', title: 'ישן 2', isDone: false, assigneeId: null},
    ],
  });
  assert.equal(task.subtasks[0].status, 'done');
  assert.deepEqual(task.subtasks[0].assigneeIds, ['a']);
  assert.equal(task.subtasks[1].status, 'open');
  assert.deepEqual(task.subtasks[1].assigneeIds, []);
});

test('the log: a writer edits and deletes only their own update (round 10)', () => {
  let task = buildNewTeamTask(input(), {now, actor: manager});
  task = appendTeamTaskUpdate(task, 'של דנה', {now, actor: ownerA});
  task = appendTeamTaskUpdate(task, 'של יוסי', {now, actor: ownerB});
  const [byB, byA] = task.updates;
  const edited = editTeamTaskUpdate(task, byA.id, 'דנה מתקנת', {now: later, actor: ownerA});
  assert.equal(edited.updates[1].text, 'דנה מתקנת');
  assert.deepEqual(edited.updates[1].editedAt, later);
  assert.equal(edited.updates[0].editedAt, undefined);
  expectTaskError(() => editTeamTaskUpdate(task, byB.id, 'x', {now, actor: ownerA}), 403);
  expectTaskError(() => deleteTeamTaskUpdate(task, byB.id, {now, actor: ownerA}), 403);
  expectTaskError(() => editTeamTaskUpdate(task, byA.id, '  ', {now, actor: ownerA}), 400);
  assert.equal(deleteTeamTaskUpdate(task, byA.id, {now, actor: ownerA}).updates.length, 1);
  // A manager (also "ניהול משימות") changes anyone's.
  assert.equal(deleteTeamTaskUpdate(task, byB.id, {now, actor: flagged}).updates[0].id, byA.id);
});

test('the log: an update with no writer only a manager changes', () => {
  const stored = teamTaskFromStored('t9', {
    title: 'מיובא',
    assigneeIds: ['a'],
    ownerIds: ['a'],
    updates: [{id: 'u1', text: 'מהאקסל', at: now, byId: '', byName: 'מהאקסל'}],
  });
  expectTaskError(() => editTeamTaskUpdate(stored, 'u1', 'x', {now, actor: ownerA}), 403);
  assert.equal(editTeamTaskUpdate(stored, 'u1', 'x', {now, actor: manager}).updates[0].text, 'x');
});

test('the log: the updates of a subtask', () => {
  let task = withSubtasks();
  task = appendTeamTaskUpdate(task, 'מחיר התקבל', {now, actor: ownerA}, 's1');
  const id = task.subtasks[0].updates[0].id;
  expectTaskError(() => editTeamTaskUpdate(task, id, 'x', {now, actor: ownerB}, 's1'), 403);
  const edited = editTeamTaskUpdate(task, id, 'מחיר סופי', {now, actor: ownerA}, 's1');
  assert.equal(edited.subtasks[0].updates[0].text, 'מחיר סופי');
  assert.equal(deleteTeamTaskUpdate(task, id, {now, actor: ownerA}, 's1').subtasks[0].updates.length, 0);
});

test('a task may link to a pending event (round 10)', () => {
  const task = buildNewTeamTask(input({link: {type: 'pendingEvent', id: 'pe1'}}), {now, actor: manager});
  assert.deepEqual(task.link, {type: 'pendingEvent', id: 'pe1'});
  assert.deepEqual(teamTaskFromStored('x', {link: {type: 'pendingEvent', id: 'pe1'}}).link,
    {type: 'pendingEvent', id: 'pe1'});
});

// ---- several events and urgency (16/11/2026) ----

test('several events: the link event first, once each; none for another link', () => {
  const doc = buildNewTeamTask(
    input({link: {type: 'event', id: 'e1'}, eventIds: ['e2', 'e1', 'e3', 'e2']}),
    {now, actor: manager},
  );
  assert.deepEqual(doc.eventIds, ['e1', 'e2', 'e3']);
  const topic = buildNewTeamTask(input({eventIds: ['e2']}), {now, actor: manager});
  assert.deepEqual(topic.eventIds, []);
});

test('a stored task with one event link reads its event; no urgency reads normal', () => {
  const doc = teamTaskFromStored('t1', {title: 'x', link: {type: 'event', id: 'e9'}});
  assert.deepEqual(doc.eventIds, ['e9']);
  assert.equal(doc.urgency, 'normal');
});

test('urgency: set on insert, kept by an edit without it, refused when unknown', () => {
  const doc = buildNewTeamTask(input({urgency: 'high'}), {now, actor: manager});
  assert.equal(doc.urgency, 'high');
  assert.equal(buildNewTeamTask(input(), {now, actor: manager}).urgency, 'normal');
  const edited = applyTeamTaskEdit(doc, input({title: 'אחר'}), {now: later, actor: manager});
  assert.equal(edited.urgency, 'high');
  const lowered = applyTeamTaskEdit(doc, input({urgency: 'low'}), {now: later, actor: manager});
  assert.equal(lowered.urgency, 'low');
  expectTaskError(() => buildNewTeamTask(input({urgency: 'urgent'}), {now, actor: manager}), 400);
});

test('an edit from an older app (no eventIds) keeps the events while the first stays', () => {
  const doc = buildNewTeamTask(
    input({link: {type: 'event', id: 'e1'}, eventIds: ['e1', 'e2']}),
    {now, actor: manager},
  );
  const same = applyTeamTaskEdit(doc, input({link: {type: 'event', id: 'e1'}}), {now: later, actor: manager});
  assert.deepEqual(same.eventIds, ['e1', 'e2']);
  const moved = applyTeamTaskEdit(doc, input({link: {type: 'event', id: 'e5'}}), {now: later, actor: manager});
  assert.deepEqual(moved.eventIds, ['e5']);
  const cleared = applyTeamTaskEdit(
    doc, input({link: {type: 'event', id: 'e1'}, eventIds: ['e1']}), {now: later, actor: manager},
  );
  assert.deepEqual(cleared.eventIds, ['e1']);
});

test('an edit with no subtasks key keeps the stored subtasks', () => {
  const doc = withSubtasks();
  const payload = input({title: 'חדש'});
  delete payload['subtasks'];
  const edited = applyTeamTaskEdit(doc, payload, {now: later, actor: manager});
  assert.deepEqual(edited.subtasks.map((s) => s.id), ['s1', 's2']);
  assert.deepEqual(edited.assigneeIds, []);
  assert.deepEqual(edited.ownerIds, ['a', 'b']);
});
