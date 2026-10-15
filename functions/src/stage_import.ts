import {Timestamp} from 'firebase-admin/firestore';

import {buildNewStage, StageDoc} from './stages';
import {buildNewTask, TaskActor, TaskDoc, TaskError} from './tasks';

/**
 * Pure rules for importing a whole event's stages and tasks at once (from an
 * Excel file the client parsed). Every stage and task goes through the same
 * builder as a single create; `index.ts` reads the event's days, refuses an
 * event that already has stages and writes the result in one transaction.
 */

export const MAX_IMPORT_STAGES = 60;
// 60 stages + 400 tasks stay under Firestore's 500 writes per transaction.
export const MAX_IMPORT_TASKS = 400;

const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export type StageImport = {
  eventId: string;
  stages: StageDoc[];
  tasks: TaskDoc[];
};

type ImportContext = {
  now: Timestamp;
  actor: TaskActor;
};

function requireRecord(value: unknown, what: string): Record<string, unknown> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TaskError(400, `${what} לא תקין`);
  }
  return value as Record<string, unknown>;
}

/** The event an import is for, read before anything else. */
export function importEventId(payload: Record<string, unknown>): string {
  const eventId = payload['eventId'];
  if (typeof eventId !== 'string' || !ID_PATTERN.test(eventId)) {
    throw new TaskError(400, 'אירוע לא תקין');
  }
  return eventId;
}

export function buildStageImport(
  payload: Record<string, unknown>,
  ctx: ImportContext,
  eventDays: string[],
): StageImport {
  const eventId = importEventId(payload);
  const rawStages = payload['stages'];
  if (!Array.isArray(rawStages) || rawStages.length === 0) {
    throw new TaskError(400, 'אין שלבים לייבוא');
  }
  if (rawStages.length > MAX_IMPORT_STAGES) {
    throw new TaskError(400, `אפשר לייבא עד ${MAX_IMPORT_STAGES} שלבים`);
  }

  const stages: StageDoc[] = [];
  const tasks: TaskDoc[] = [];
  const ids = new Set<string>();
  const claim = (id: string) => {
    if (ids.has(id)) throw new TaskError(400, 'מזהה כפול בייבוא');
    ids.add(id);
  };

  for (const rawEntry of rawStages) {
    const entry = requireRecord(rawEntry, 'שלב');
    const stage = buildNewStage(requireRecord(entry['stage'], 'שלב'), ctx, eventDays);
    if (stage.eventId !== eventId) throw new TaskError(400, 'שלב של אירוע אחר');
    claim(stage.id);
    stages.push(stage);

    const rawTasks = entry['tasks'] ?? [];
    if (!Array.isArray(rawTasks)) throw new TaskError(400, 'רשימת המשימות לא תקינה');
    for (const rawTask of rawTasks) {
      const task = buildNewTask(requireRecord(rawTask, 'משימה'), ctx);
      if (task.eventId !== eventId || task.stageId !== stage.id) {
        throw new TaskError(400, 'משימה שאינה שייכת לשלב שלה');
      }
      claim(task.id);
      tasks.push(task);
      if (tasks.length > MAX_IMPORT_TASKS) {
        throw new TaskError(400, `אפשר לייבא עד ${MAX_IMPORT_TASKS} משימות`);
      }
    }
  }
  return {eventId, stages, tasks};
}
