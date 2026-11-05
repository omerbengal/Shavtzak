import {Timestamp} from 'firebase-admin/firestore';

import {applyStageEdit, buildNewStage, StageDoc} from './stages';
import {applyTaskEdit, buildNewTask, TaskActor, TaskDoc, TaskError} from './tasks';

/**
 * Pure rules for bringing an event that already has stages and tasks in line
 * with an updated Excel file. The client works out the difference and sends
 * it as explicit creates, updates and deletes; `index.ts` reads the event's
 * stages and tasks and writes the result in one transaction.
 *
 * Progress is never sent: an updated task keeps its completion and the
 * assignees' note, and each subtask keeps its tick by id
 * ([applyTaskEdit]). An update may move a task to another stage.
 *
 * Sending the same sync twice is harmless: a create whose document already
 * exists and a delete of a document already gone are skipped.
 */

// Under Firestore's 500 writes per transaction.
export const MAX_SYNC_WRITES = 450;

const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

/** Shown when the event changed between reading the file and saving it. */
export const SYNC_STALE_MESSAGE =
  'השלבים או המשימות השתנו בינתיים. בחרו את הקובץ שוב כדי לראות את השינויים מחדש.';

export type StageSync = {
  eventId: string;
  /** Stages to write in full: the new ones and the changed ones. */
  stageWrites: StageDoc[];
  stageDeletes: string[];
  taskWrites: TaskDoc[];
  taskDeletes: string[];
  /** Members newly put on a task, who must exist. */
  newAssigneeIds: string[];
};

type SyncContext = {
  now: Timestamp;
  actor: TaskActor;
};

type Section = {
  create: Record<string, unknown>[];
  update: Record<string, unknown>[];
  delete: string[];
};

function record(value: unknown, what: string): Record<string, unknown> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TaskError(400, `${what} לא תקין`);
  }
  return value as Record<string, unknown>;
}

function section(value: unknown, what: string): Section {
  const raw = value == null ? {} : record(value, what);
  const list = (key: string): unknown[] => {
    const entries = raw[key] ?? [];
    if (!Array.isArray(entries)) throw new TaskError(400, `${what} לא תקין`);
    return entries;
  };
  return {
    create: list('create').map((entry) => record(entry, what)),
    update: list('update').map((entry) => record(entry, what)),
    delete: list('delete').map((id) => {
      if (typeof id !== 'string' || !ID_PATTERN.test(id)) {
        throw new TaskError(400, `${what} לא תקין`);
      }
      return id;
    }),
  };
}

/** The event a sync is for, read before anything else. */
export function syncEventId(payload: Record<string, unknown>): string {
  const eventId = payload['eventId'];
  if (typeof eventId !== 'string' || !ID_PATTERN.test(eventId)) {
    throw new TaskError(400, 'אירוע לא תקין');
  }
  return eventId;
}

export function buildStageSync(
  payload: Record<string, unknown>,
  ctx: SyncContext,
  eventDays: string[],
  existingStages: StageDoc[],
  existingTasks: TaskDoc[],
): StageSync {
  const eventId = syncEventId(payload);
  const stages = section(payload['stages'], 'שלב');
  const tasks = section(payload['tasks'], 'משימה');

  const ids = new Set<string>();
  const claim = (id: unknown) => {
    if (typeof id !== 'string' || ids.has(id)) {
      throw new TaskError(400, 'מזהה כפול בעדכון');
    }
    ids.add(id);
  };
  for (const entry of [...stages.create, ...stages.update]) claim(entry['id']);
  stages.delete.forEach(claim);
  for (const entry of [...tasks.create, ...tasks.update]) claim(entry['id']);
  tasks.delete.forEach(claim);

  const stageById = new Map(existingStages.map((stage) => [stage.id, stage]));
  const taskById = new Map(existingTasks.map((task) => [task.id, task]));

  const stageWrites: StageDoc[] = [];
  for (const input of stages.create) {
    const stage = buildNewStage(input, ctx, eventDays);
    if (stage.eventId !== eventId) throw new TaskError(400, 'שלב של אירוע אחר');
    if (stageById.has(stage.id)) continue; // A replay.
    stageWrites.push(stage);
  }
  for (const input of stages.update) {
    const existing = stageById.get(input['id'] as string);
    if (existing == null) throw new TaskError(409, SYNC_STALE_MESSAGE);
    stageWrites.push(applyStageEdit(existing, input, ctx, eventDays));
  }
  const stageDeletes = stages.delete.filter((id) => stageById.has(id));

  // The stages the event holds once the sync is written.
  const finalStageIds = new Set(existingStages.map((stage) => stage.id));
  for (const stage of stageWrites) finalStageIds.add(stage.id);
  for (const id of stageDeletes) finalStageIds.delete(id);
  if (finalStageIds.size === 0) {
    throw new TaskError(400, 'אי אפשר להשאיר את האירוע בלי שלבים');
  }

  const taskWrites: TaskDoc[] = [];
  const newAssigneeIds = new Set<string>();
  for (const input of tasks.create) {
    const task = buildNewTask(input, ctx);
    if (task.eventId !== eventId) throw new TaskError(400, 'משימה של אירוע אחר');
    if (taskById.has(task.id)) continue; // A replay.
    if (!finalStageIds.has(task.stageId)) throw new TaskError(409, SYNC_STALE_MESSAGE);
    task.assigneeIds.forEach((id) => newAssigneeIds.add(id));
    taskWrites.push(task);
  }
  for (const input of tasks.update) {
    const existing = taskById.get(input['id'] as string);
    if (existing == null) throw new TaskError(409, SYNC_STALE_MESSAGE);
    const next = applyTaskEdit(existing, input, ctx, {allowStageMove: true});
    if (!finalStageIds.has(next.stageId)) throw new TaskError(409, SYNC_STALE_MESSAGE);
    next.assigneeIds
      .filter((id) => !existing.assigneeIds.includes(id))
      .forEach((id) => newAssigneeIds.add(id));
    taskWrites.push(next);
  }
  const taskDeletes = tasks.delete.filter((id) => taskById.has(id));

  // A task left under a deleted stage was added after the file was read:
  // refuse rather than delete it unseen.
  const handled = new Set([...taskWrites.map((task) => task.id), ...taskDeletes]);
  const deletedStages = new Set(stageDeletes);
  for (const task of existingTasks) {
    if (deletedStages.has(task.stageId) && !handled.has(task.id)) {
      throw new TaskError(409, SYNC_STALE_MESSAGE);
    }
  }

  const writes =
    stageWrites.length + stageDeletes.length + taskWrites.length + taskDeletes.length;
  if (writes > MAX_SYNC_WRITES) {
    throw new TaskError(400, `אפשר לעדכן עד ${MAX_SYNC_WRITES} שלבים ומשימות בבת אחת`);
  }

  return {
    eventId,
    stageWrites,
    stageDeletes,
    taskWrites,
    taskDeletes,
    newAssigneeIds: [...newAssigneeIds],
  };
}
