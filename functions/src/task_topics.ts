// Topics ("נושאים") of the team tasks screen.
//
// A managed list like the categories and "מה יש באירוע": `utilities/Lists`
// field `TaskTopics`, each {id, name, sortOrder, isArchived, updatedAt},
// changed through the `taskTopic.*` mutations by task managers (admins and
// members with "ניהול משימות"). An archived topic stays on its tasks.

import {TaskActor, TaskError, requireTaskManager} from './tasks';

const MAX_NAME_LENGTH = 60;

export interface TaskTopicChange {
  items: Array<Record<string, unknown>>;
  entityId: string;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
}

function normalizeTopic(value: unknown, nowIso: string): Record<string, unknown> {
  if (value == null || typeof value !== 'object') throw new TaskError(400, 'נושא לא תקין');
  const record = value as Record<string, unknown>;
  const id = typeof record['id'] === 'string' ? record['id'].trim() : '';
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) throw new TaskError(400, 'נושא לא תקין');
  const name = typeof record['name'] === 'string' ? record['name'].trim() : '';
  if (name.length === 0) throw new TaskError(400, 'חובה להזין שם לנושא');
  if (name.length > MAX_NAME_LENGTH) throw new TaskError(400, 'שם הנושא ארוך מדי');
  return {
    id,
    name,
    sortOrder: typeof record['sortOrder'] === 'number' ? record['sortOrder'] : 0,
    isArchived: record['isArchived'] === true,
    updatedAt: nowIso,
  };
}

/**
 * One `taskTopic.*` mutation applied to the list: insert / update (a whole
 * topic under `topic`), delete (archive) / restore / permanentlyDelete (by
 * `topicId`).
 */
export function applyTaskTopicMutation(
  items: Array<Record<string, unknown>>,
  operation: string,
  payload: Record<string, unknown>,
  nowIso: string,
  actor: TaskActor,
): TaskTopicChange {
  requireTaskManager(actor);
  if (operation === 'taskTopic.insert' || operation === 'taskTopic.update') {
    const topic = normalizeTopic(payload['topic'], nowIso);
    const id = topic['id'] as string;
    const before = items.find((entry) => entry['id'] === id) ?? null;
    if (operation === 'taskTopic.insert') {
      if (before != null) throw new TaskError(409, 'הנושא כבר קיים');
      return {items: [...items, topic], entityId: id, before: null, after: topic};
    }
    if (before == null) throw new TaskError(404, 'הנושא לא נמצא');
    return {
      items: items.map((entry) => (entry['id'] === id ? topic : entry)),
      entityId: id,
      before,
      after: topic,
    };
  }

  const id = typeof payload['topicId'] === 'string' ? payload['topicId'] : '';
  if (id.length === 0) throw new TaskError(400, 'חסר מזהה נושא');
  const before = items.find((entry) => entry['id'] === id) ?? null;
  if (before == null) throw new TaskError(404, 'הנושא לא נמצא');
  switch (operation) {
    case 'taskTopic.permanentlyDelete':
      return {items: items.filter((entry) => entry['id'] !== id), entityId: id, before, after: null};
    case 'taskTopic.delete':
    case 'taskTopic.restore': {
      const next = items.map((entry) => entry['id'] !== id
        ? entry
        : {...entry, isArchived: operation === 'taskTopic.delete', updatedAt: nowIso});
      return {items: next, entityId: id, before, after: next.find((entry) => entry['id'] === id) ?? null};
    }
    default:
      throw new TaskError(400, `Unknown operation ${operation}`);
  }
}
