import {Timestamp} from 'firebase-admin/firestore';

/**
 * Pure task transitions for the דו יומי task screen.
 *
 * Nothing here reads or writes Firestore: every function takes the stored task
 * (or a client payload) plus an injected `now` and actor, and returns the full
 * next document. `index.ts` runs these inside a transaction, so two members
 * acting at the same moment each transform the latest stored state rather than
 * a stale client copy.
 */

export class TaskError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export type TaskActor = {
  memberId: string;
  name: string | null;
  isAdmin: boolean;
  canManageTasks: boolean;
};

export type Subtask = {
  id: string;
  title: string;
  isDone: boolean;
};

export type TaskDoc = {
  id: string;
  eventId: string;
  title: string;
  description: string;
  subtasks: Subtask[];
  dueAt: Timestamp | null;
  assigneeIds: string[];
  assigneeUpdate: string | null;
  assigneeUpdateAt: Timestamp | null;
  assigneeUpdateById: string | null;
  assigneeUpdateByName: string | null;
  isComplete: boolean;
  completedAt: Timestamp | null;
  completedById: string | null;
  createdAt: Timestamp;
  createdById: string;
  updatedAt: Timestamp;
};

type TaskContext = {
  now: Timestamp;
  actor: TaskActor;
};

const MAX_TITLE_LENGTH = 200;
const MAX_DESCRIPTION_LENGTH = 5000;
const MAX_SUBTASKS = 50;
const MAX_ASSIGNEES = 100;
const MAX_UPDATE_LENGTH = 2000;
// 9999-12-31, the last day a Firestore Timestamp can hold, with a day to spare.
const MAX_DUE_AT_MILLIS = 253_402_214_400_000;
// The task id is a Firestore document id. The client sends a UUID; anything
// with a slash would address a nested document instead.
const TASK_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

// ---- permissions ----

export function canManageTasks(actor: TaskActor): boolean {
  return actor.isAdmin || actor.canManageTasks;
}

export function isTaskAssignee(
  task: Pick<TaskDoc, 'assigneeIds'>,
  actor: TaskActor,
): boolean {
  return task.assigneeIds.includes(actor.memberId);
}

export function requireTaskManager(actor: TaskActor): void {
  if (!canManageTasks(actor)) {
    throw new TaskError(403, 'אין לך הרשאה לנהל משימות');
  }
}

export function requireTaskParticipant(task: TaskDoc, actor: TaskActor): void {
  if (!canManageTasks(actor) && !isTaskAssignee(task, actor)) {
    throw new TaskError(403, 'אין לך הרשאה לעדכן את המשימה');
  }
}

// ---- audit ----

/**
 * The `details` of a task's audit log entry. The task's title goes under
 * `name` because that is the key the log reads an entity's display name from.
 */
export function taskAuditDetails(
  task: Pick<TaskDoc, 'title' | 'eventId'>,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {name: task.title, eventId: task.eventId, ...extra};
}

// ---- reading a stored document ----

/**
 * Coerce a stored document into a full [TaskDoc]. Tolerant by design: a document
 * missing an optional field, or carrying a malformed subtask, must not make the
 * task unreadable.
 */
export function taskFromStored(id: string, raw: Record<string, unknown>): TaskDoc {
  return {
    id,
    eventId: typeof raw['eventId'] === 'string' ? raw['eventId'] : '',
    title: typeof raw['title'] === 'string' ? raw['title'] : '',
    description: typeof raw['description'] === 'string' ? raw['description'] : '',
    subtasks: storedSubtasks(raw['subtasks']),
    dueAt: storedTimestamp(raw['dueAt']),
    assigneeIds: Array.isArray(raw['assigneeIds'])
      ? raw['assigneeIds'].filter((value): value is string => typeof value === 'string')
      : [],
    assigneeUpdate: storedString(raw['assigneeUpdate']),
    assigneeUpdateAt: storedTimestamp(raw['assigneeUpdateAt']),
    assigneeUpdateById: storedString(raw['assigneeUpdateById']),
    assigneeUpdateByName: storedString(raw['assigneeUpdateByName']),
    isComplete: raw['isComplete'] === true,
    completedAt: storedTimestamp(raw['completedAt']),
    completedById: storedString(raw['completedById']),
    createdAt: storedTimestamp(raw['createdAt']) ?? Timestamp.fromMillis(0),
    createdById: typeof raw['createdById'] === 'string' ? raw['createdById'] : '',
    updatedAt: storedTimestamp(raw['updatedAt']) ?? Timestamp.fromMillis(0),
  };
}

function storedString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function storedTimestamp(value: unknown): Timestamp | null {
  return value instanceof Timestamp ? value : null;
}

function storedSubtasks(value: unknown): Subtask[] {
  if (!Array.isArray(value)) return [];
  const subtasks: Subtask[] = [];
  for (const entry of value) {
    if (entry == null || typeof entry !== 'object') continue;
    const record = entry as Record<string, unknown>;
    const id = record['id'];
    const title = record['title'];
    if (typeof id !== 'string' || id.length === 0) continue;
    if (typeof title !== 'string') continue;
    subtasks.push({id, title, isDone: record['isDone'] === true});
  }
  return subtasks;
}

// ---- validating a client payload ----

type EditableFields = {
  eventId: string;
  title: string;
  description: string;
  dueAt: Timestamp | null;
  assigneeIds: string[];
  subtasks: {id: string; title: string}[];
};

function parseEditableFields(input: Record<string, unknown>): EditableFields {
  const eventId = input['eventId'];
  if (typeof eventId !== 'string' || eventId.trim().length === 0) {
    throw new TaskError(400, 'חובה לבחור אירוע');
  }

  const title = typeof input['title'] === 'string' ? input['title'].trim() : '';
  if (title.length === 0) throw new TaskError(400, 'חובה להזין כותרת');
  if (title.length > MAX_TITLE_LENGTH) throw new TaskError(400, 'הכותרת ארוכה מדי');

  const descriptionRaw = input['description'];
  if (descriptionRaw != null && typeof descriptionRaw !== 'string') {
    throw new TaskError(400, 'תיאור לא תקין');
  }
  const description = descriptionRaw ?? '';
  if (description.length > MAX_DESCRIPTION_LENGTH) {
    throw new TaskError(400, 'התיאור ארוך מדי');
  }

  return {
    eventId,
    title,
    description,
    dueAt: parseDueAt(input['dueAt']),
    assigneeIds: parseAssigneeIds(input['assigneeIds']),
    subtasks: parseSubtasks(input['subtasks']),
  };
}

function parseDueAt(value: unknown): Timestamp | null {
  if (value == null) return null;
  if (typeof value !== 'string' && typeof value !== 'number') {
    throw new TaskError(400, 'תאריך יעד לא תקין');
  }
  const millis = typeof value === 'number' ? value : Date.parse(value);
  // Timestamp itself throws on anything outside years 1..9999, which would
  // surface as a 500 instead of a validation error.
  if (!Number.isFinite(millis) || Math.abs(millis) > MAX_DUE_AT_MILLIS) {
    throw new TaskError(400, 'תאריך יעד לא תקין');
  }
  return Timestamp.fromMillis(millis);
}

function parseAssigneeIds(value: unknown): string[] {
  if (!Array.isArray(value)) throw new TaskError(400, 'חובה לבחור אחראי');
  const ids: string[] = [];
  for (const entry of value) {
    if (typeof entry !== 'string' || entry.length === 0) {
      throw new TaskError(400, 'אחראי לא תקין');
    }
    if (!ids.includes(entry)) ids.push(entry);
  }
  if (ids.length === 0) throw new TaskError(400, 'חובה לבחור אחראי');
  if (ids.length > MAX_ASSIGNEES) throw new TaskError(400, 'יותר מדי אחראים');
  return ids;
}

function parseSubtasks(value: unknown): {id: string; title: string}[] {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TaskError(400, 'תתי-משימות לא תקינות');
  if (value.length > MAX_SUBTASKS) throw new TaskError(400, 'יותר מדי תתי-משימות');

  const subtasks: {id: string; title: string}[] = [];
  const seenIds = new Set<string>();
  for (const entry of value) {
    if (entry == null || typeof entry !== 'object') {
      throw new TaskError(400, 'תת-משימה לא תקינה');
    }
    const record = entry as Record<string, unknown>;
    const id = record['id'];
    if (typeof id !== 'string' || id.length === 0 || seenIds.has(id)) {
      throw new TaskError(400, 'תת-משימה לא תקינה');
    }
    const title = typeof record['title'] === 'string' ? record['title'].trim() : '';
    if (title.length === 0) throw new TaskError(400, 'חובה להזין שם לתת-משימה');
    if (title.length > MAX_TITLE_LENGTH) throw new TaskError(400, 'שם תת-המשימה ארוך מדי');
    seenIds.add(id);
    subtasks.push({id, title});
  }
  return subtasks;
}

// ---- completion ----

/**
 * Re-derive completion after a transition. With subtasks the task is complete
 * exactly when all of them are done; without subtasks it keeps `manualComplete`.
 * The completion stamp is written only on the open → complete edge, so a task
 * that stays complete keeps who originally finished it.
 */
function withCompletion(
  previous: TaskDoc,
  next: TaskDoc,
  manualComplete: boolean,
  ctx: TaskContext,
): TaskDoc {
  const isComplete = next.subtasks.length > 0
    ? next.subtasks.every((subtask) => subtask.isDone)
    : manualComplete;

  if (!isComplete) {
    return {...next, isComplete: false, completedAt: null, completedById: null};
  }
  if (previous.isComplete) {
    return {
      ...next,
      isComplete: true,
      completedAt: previous.completedAt,
      completedById: previous.completedById,
    };
  }
  return {
    ...next,
    isComplete: true,
    completedAt: ctx.now,
    completedById: ctx.actor.memberId,
  };
}

// ---- transitions ----

export function buildNewTask(input: Record<string, unknown>, ctx: TaskContext): TaskDoc {
  const id = input['id'];
  if (typeof id !== 'string' || !TASK_ID_PATTERN.test(id)) {
    throw new TaskError(400, 'מזהה משימה לא תקין');
  }
  const fields = parseEditableFields(input);
  return {
    id,
    eventId: fields.eventId,
    title: fields.title,
    description: fields.description,
    subtasks: fields.subtasks.map((subtask) => ({...subtask, isDone: false})),
    dueAt: fields.dueAt,
    assigneeIds: fields.assigneeIds,
    assigneeUpdate: null,
    assigneeUpdateAt: null,
    assigneeUpdateById: null,
    assigneeUpdateByName: null,
    isComplete: false,
    completedAt: null,
    completedById: null,
    createdAt: ctx.now,
    createdById: ctx.actor.memberId,
    updatedAt: ctx.now,
  };
}

export function applyTaskEdit(
  existing: TaskDoc,
  input: Record<string, unknown>,
  ctx: TaskContext,
): TaskDoc {
  if (input['id'] !== existing.id) {
    throw new TaskError(400, 'מזהה משימה לא תואם');
  }
  const fields = parseEditableFields(input);
  const doneById = new Map(
    existing.subtasks.map((subtask) => [subtask.id, subtask.isDone]),
  );
  const next: TaskDoc = {
    ...existing,
    eventId: fields.eventId,
    title: fields.title,
    description: fields.description,
    dueAt: fields.dueAt,
    assigneeIds: fields.assigneeIds,
    subtasks: fields.subtasks.map((subtask) => ({
      ...subtask,
      isDone: doneById.get(subtask.id) ?? false,
    })),
    updatedAt: ctx.now,
  };
  return withCompletion(existing, next, existing.isComplete, ctx);
}

export function applySubtaskToggle(
  existing: TaskDoc,
  subtaskId: string,
  isDone: boolean,
  ctx: TaskContext,
): TaskDoc {
  if (!existing.subtasks.some((subtask) => subtask.id === subtaskId)) {
    throw new TaskError(404, 'תת-המשימה לא נמצאה');
  }
  const next: TaskDoc = {
    ...existing,
    subtasks: existing.subtasks.map((subtask) =>
      subtask.id === subtaskId ? {...subtask, isDone} : subtask,
    ),
    updatedAt: ctx.now,
  };
  return withCompletion(existing, next, existing.isComplete, ctx);
}

export function applySetComplete(
  existing: TaskDoc,
  isComplete: boolean,
  ctx: TaskContext,
): TaskDoc {
  if (existing.subtasks.length > 0) {
    throw new TaskError(400, 'משימה עם תתי-משימות מסתיימת אוטומטית');
  }
  return withCompletion(existing, {...existing, updatedAt: ctx.now}, isComplete, ctx);
}

export function applyAssigneeUpdate(
  existing: TaskDoc,
  text: string,
  ctx: TaskContext,
): TaskDoc {
  const trimmed = text.trim();
  if (trimmed.length > MAX_UPDATE_LENGTH) {
    throw new TaskError(400, 'העדכון ארוך מדי');
  }
  if (trimmed.length === 0) {
    return {
      ...existing,
      assigneeUpdate: null,
      assigneeUpdateAt: null,
      assigneeUpdateById: null,
      assigneeUpdateByName: null,
      updatedAt: ctx.now,
    };
  }
  return {
    ...existing,
    assigneeUpdate: trimmed,
    assigneeUpdateAt: ctx.now,
    assigneeUpdateById: ctx.actor.memberId,
    assigneeUpdateByName: ctx.actor.name,
    updatedAt: ctx.now,
  };
}
