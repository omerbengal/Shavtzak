import {Timestamp} from 'firebase-admin/firestore';
import {TaskActor, TaskError, requireTaskManager} from './tasks';
import {
  TeamTaskDoc,
  appendTeamTaskUpdate,
  applyTeamSubtaskStatus,
  applyTeamSubtaskToggle,
  applyTeamTaskEdit,
  applyTeamTaskStatus,
  buildNewTeamTask,
  deleteTeamTaskUpdate,
  editTeamTaskUpdate,
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
  pendingEventExists(id: string): Promise<boolean>;
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
  'teamTask.editUpdate',
  'teamTask.deleteUpdate',
] as const;

function requireId(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new TaskError(400, `Missing or invalid ${field}`);
  }
  return value;
}

function optionalId(value: unknown, field: string): string | null {
  if (value == null) return null;
  return requireId(value, field);
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

/** Every event of [next] not in [known] must exist. */
async function requireEventsExist(
  store: TeamTaskStore,
  next: TeamTaskDoc,
  known: readonly string[] = [],
): Promise<void> {
  for (const id of next.eventIds) {
    if (known.includes(id)) continue;
    if (!(await store.eventExists(id))) throw new TaskError(404, 'האירוע לא נמצא');
  }
}

async function requireLinkExists(store: TeamTaskStore, next: TeamTaskDoc): Promise<void> {
  const link = next.link;
  if (link == null) return;
  if (link.type === 'event') {
    await requireEventsExist(store, next);
    return;
  }
  if (link.type === 'category' && !(await store.categoryExists(link.id))) {
    throw new TaskError(404, 'הקטגוריה לא נמצאה');
  }
  if (link.type === 'topic' && !(await store.topicExists(link.id))) {
    throw new TaskError(404, 'הנושא לא נמצא');
  }
  if (link.type === 'pendingEvent' && !(await store.pendingEventExists(link.id))) {
    throw new TaskError(404, 'האירוע שעוד לא נוצר לא נמצא');
  }
}

function sameLink(a: TeamTaskDoc['link'], b: TeamTaskDoc['link']): boolean {
  if (a == null || b == null) return a === b;
  return a.type === b.type && a.id === b.id;
}

/** Every owner the write adds (task or subtask) must be an active member. */
async function requireNewOwnersActive(
  store: TeamTaskStore,
  before: TeamTaskDoc | null,
  next: TeamTaskDoc,
): Promise<void> {
  const known = new Set<string>([
    ...(before?.assigneeIds ?? []),
    ...(before?.subtasks ?? []).flatMap((subtask) => subtask.assigneeIds),
  ]);
  const named = [
    ...next.assigneeIds,
    ...next.subtasks.flatMap((subtask) => subtask.assigneeIds),
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
      // Only a new link is checked: a task whose event was deleted since must
      // stay editable ("nothing is lost").
      if (!sameLink(before.link, next.link)) {
        await requireLinkExists(store, next);
      } else if (next.link?.type === 'event') {
        // The same first event: only an event added beside it is checked.
        await requireEventsExist(store, next, before.eventIds);
      }
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
      const subtaskId = optionalId(payload['subtaskId'], 'subtaskId');
      if (subtaskId != null) {
        const next = applyTeamSubtaskStatus(before, subtaskId, status, duplicateOfId, ctx);
        const original = next.subtasks.find((subtask) => subtask.id === subtaskId)?.duplicateOfId;
        // A subtask's original: a sibling subtask or another task.
        if (original != null &&
            !next.subtasks.some((subtask) => subtask.id === original) &&
            (await store.getTask(original)) == null) {
          throw new TaskError(404, 'המשימה המקורית לא נמצאה');
        }
        await store.writeTask(next);
        return {
          entityId: next.id,
          before,
          after: next,
          details: {
            subtaskTitle: next.subtasks.find((subtask) => subtask.id === subtaskId)?.title ?? null,
            status,
            duplicateOfId: original ?? null,
          },
        };
      }
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
      const subtaskId = optionalId(payload['subtaskId'], 'subtaskId');
      const next = appendTeamTaskUpdate(before, text, ctx, subtaskId);
      await store.writeTask(next);
      const log = subtaskId == null
        ? next.updates
        : next.subtasks.find((subtask) => subtask.id === subtaskId)?.updates ?? [];
      return {
        entityId: next.id,
        before,
        after: next,
        details: subtaskId == null ? {text: log[0]?.text} : {text: log[0]?.text, subtaskId},
      };
    }
    case 'teamTask.editUpdate':
    case 'teamTask.deleteUpdate': {
      const before = await loadTask(store, requireId(payload['id'], 'id'));
      const updateId = requireId(payload['updateId'], 'updateId');
      const subtaskId = optionalId(payload['subtaskId'], 'subtaskId');
      const text = typeof payload['text'] === 'string' ? payload['text'] : '';
      const next = operation === 'teamTask.editUpdate'
        ? editTeamTaskUpdate(before, updateId, text, ctx, subtaskId)
        : deleteTeamTaskUpdate(before, updateId, ctx, subtaskId);
      await store.writeTask(next);
      const log = subtaskId == null
        ? before.updates
        : before.subtasks.find((subtask) => subtask.id === subtaskId)?.updates ?? [];
      const old = log.find((entry) => entry.id === updateId);
      return {
        entityId: next.id,
        before,
        after: next,
        details: {
          updateId,
          oldText: old?.text ?? null,
          ...(operation === 'teamTask.editUpdate' ? {text: text.trim()} : {}),
          ...(subtaskId == null ? {} : {subtaskId}),
        },
      };
    }
    default:
      throw new TaskError(400, `Unsupported operation: ${operation}`);
  }
}
