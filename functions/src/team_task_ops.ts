import {Timestamp} from 'firebase-admin/firestore';
import {TaskActor, TaskError, requireTaskManager} from './tasks';
import {
  TeamTaskDoc,
  appendTeamTaskUpdate,
  applyTeamSubtaskToggle,
  applyTeamTaskEdit,
  applyTeamTaskStatus,
  buildNewTeamTask,
  parseTeamTaskStatus,
  teamTaskFromStored,
} from './team_tasks';

/**
 * The `teamTask.*` operations, apart from Firestore.
 *
 * `index.ts` runs each one inside a transaction through a [TeamTaskStore]
 * built on that transaction; the tests use an in-memory store. Every store
 * read happens before the one write, as a Firestore transaction requires.
 */
export interface TeamTaskStore {
  getTask(id: string): Promise<Record<string, unknown> | null>;
  eventExists(id: string): Promise<boolean>;
  categoryExists(id: string): Promise<boolean>;
  topicExists(id: string): Promise<boolean>;
  /** The ids among [ids] that are not an active, unarchived team member. */
  inactiveMemberIds(ids: string[]): Promise<string[]>;
  writeTask(doc: TeamTaskDoc): Promise<void>;
  deleteTask(id: string): Promise<void>;
}

export type TeamTaskOperationResult = {
  entityId: string;
  before: TeamTaskDoc | null;
  after: TeamTaskDoc | null;
  /** Extra audit details of the operation. */
  details: Record<string, unknown>;
};

export const TEAM_TASK_OPERATIONS = [
  'teamTask.insert',
  'teamTask.update',
  'teamTask.delete',
  'teamTask.setStatus',
  'teamTask.setSubtaskDone',
  'teamTask.addUpdate',
] as const;

function requireId(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new TaskError(400, `Missing or invalid ${field}`);
  }
  return value;
}

function requireTaskObject(value: unknown): Record<string, unknown> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TaskError(400, 'Missing or invalid task');
  }
  return value as Record<string, unknown>;
}

async function loadTask(store: TeamTaskStore, id: string): Promise<TeamTaskDoc> {
  const raw = await store.getTask(id);
  if (raw == null) throw new TaskError(404, 'המשימה לא נמצאה');
  return teamTaskFromStored(id, raw);
}

async function requireLinkExists(store: TeamTaskStore, next: TeamTaskDoc): Promise<void> {
  const link = next.link;
  if (link == null) return;
  if (link.type === 'event' && !(await store.eventExists(link.id))) {
    throw new TaskError(404, 'האירוע לא נמצא');
  }
  if (link.type === 'category' && !(await store.categoryExists(link.id))) {
    throw new TaskError(404, 'הקטגוריה לא נמצאה');
  }
  if (link.type === 'topic' && !(await store.topicExists(link.id))) {
    throw new TaskError(404, 'הנושא לא נמצא');
  }
}

/** Every owner the write adds (task or subtask) must be an active member. */
async function requireNewOwnersActive(
  store: TeamTaskStore,
  before: TeamTaskDoc | null,
  next: TeamTaskDoc,
): Promise<void> {
  const known = new Set<string>([
    ...(before?.assigneeIds ?? []),
    ...(before?.subtasks ?? []).map((subtask) => subtask.assigneeId ?? ''),
  ]);
  const named = [
    ...next.assigneeIds,
    ...next.subtasks.map((subtask) => subtask.assigneeId).filter((id): id is string => id != null),
  ];
  const added = [...new Set(named)].filter((id) => !known.has(id));
  if (added.length === 0) return;
  const inactive = await store.inactiveMemberIds(added);
  if (inactive.length > 0) throw new TaskError(400, 'חבר צוות לא נמצא');
}

export async function runTeamTaskOperation(
  store: TeamTaskStore,
  operation: string,
  payload: Record<string, unknown>,
  actor: TaskActor,
  now: Timestamp,
): Promise<TeamTaskOperationResult> {
  const ctx = {now, actor};
  switch (operation) {
    case 'teamTask.insert': {
      const next = buildNewTeamTask(requireTaskObject(payload['task']), ctx);
      if ((await store.getTask(next.id)) != null) {
        throw new TaskError(409, 'המשימה כבר קיימת');
      }
      await requireLinkExists(store, next);
      await requireNewOwnersActive(store, null, next);
      await store.writeTask(next);
      return {entityId: next.id, before: null, after: next, details: {}};
    }
    case 'teamTask.update': {
      requireTaskManager(actor);
      const input = requireTaskObject(payload['task']);
      const before = await loadTask(store, requireId(input['id'], 'task.id'));
      const next = applyTeamTaskEdit(before, input, ctx);
      await requireLinkExists(store, next);
      await requireNewOwnersActive(store, before, next);
      await store.writeTask(next);
      return {entityId: next.id, before, after: next, details: {}};
    }
    case 'teamTask.delete': {
      requireTaskManager(actor);
      const before = await loadTask(store, requireId(payload['id'], 'id'));
      await store.deleteTask(before.id);
      return {entityId: before.id, before, after: null, details: {}};
    }
    case 'teamTask.setStatus': {
      const before = await loadTask(store, requireId(payload['id'], 'id'));
      const status = parseTeamTaskStatus(payload['status']);
      const duplicateOfId = typeof payload['duplicateOfId'] === 'string'
        ? payload['duplicateOfId']
        : null;
      const next = applyTeamTaskStatus(before, status, duplicateOfId, ctx);
      if (next.duplicateOfId != null && (await store.getTask(next.duplicateOfId)) == null) {
        throw new TaskError(404, 'המשימה המקורית לא נמצאה');
      }
      await store.writeTask(next);
      return {entityId: next.id, before, after: next, details: {status, duplicateOfId: next.duplicateOfId}};
    }
    case 'teamTask.setSubtaskDone': {
      const before = await loadTask(store, requireId(payload['id'], 'id'));
      const subtaskId = requireId(payload['subtaskId'], 'subtaskId');
      if (typeof payload['isDone'] !== 'boolean') {
        throw new TaskError(400, 'Missing or invalid isDone');
      }
      const next = applyTeamSubtaskToggle(before, subtaskId, payload['isDone'], ctx);
      await store.writeTask(next);
      return {
        entityId: next.id,
        before,
        after: next,
        details: {
          subtaskTitle: next.subtasks.find((subtask) => subtask.id === subtaskId)?.title ?? null,
          isDone: payload['isDone'],
        },
      };
    }
    case 'teamTask.addUpdate': {
      const before = await loadTask(store, requireId(payload['id'], 'id'));
      const text = typeof payload['text'] === 'string' ? payload['text'] : '';
      const next = appendTeamTaskUpdate(before, text, ctx);
      await store.writeTask(next);
      return {entityId: next.id, before, after: next, details: {text: next.updates[0]?.text}};
    }
    default:
      throw new TaskError(400, `Unsupported operation: ${operation}`);
  }
}
