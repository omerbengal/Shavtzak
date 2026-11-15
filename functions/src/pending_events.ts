// "אירוע שעוד לא נוצר" (round 10): placeholders for events that are not in
// the app yet, so tasks can be opened before the event exists.
//
// A managed list like the topics: `utilities/Lists` field `PendingEvents`,
// each {id, name, sortOrder, isArchived, updatedAt}, changed by task managers
// (admins and members with "ניהול משימות"). A team task links to one as
// `{type: 'pendingEvent', id}`. `pendingEvent.link` moves every task of a
// placeholder to the real event and removes the placeholder.

import {TaskActor, TaskError, requireTaskManager} from './tasks';
import {TaskTopicChange, applyTaskTopicMutation} from './task_topics';

export const PENDING_EVENT_LIST_OPERATIONS = [
  'pendingEvent.insert',
  'pendingEvent.update',
  'pendingEvent.permanentlyDelete',
] as const;

/**
 * One list mutation: insert / update (a whole placeholder under
 * `pendingEvent`), permanentlyDelete (by `pendingEventId`). The same rules as
 * a topic's.
 */
export function applyPendingEventMutation(
  items: Array<Record<string, unknown>>,
  operation: string,
  payload: Record<string, unknown>,
  nowIso: string,
  actor: TaskActor,
): TaskTopicChange {
  if (!(PENDING_EVENT_LIST_OPERATIONS as readonly string[]).includes(operation)) {
    throw new TaskError(400, `Unknown operation ${operation}`);
  }
  try {
    return applyTaskTopicMutation(
      items,
      operation.replace('pendingEvent.', 'taskTopic.'),
      {topic: payload['pendingEvent'], topicId: payload['pendingEventId']},
      nowIso,
      actor,
    );
  } catch (error) {
    if (error instanceof TaskError) {
      throw new TaskError(error.status, error.message
        .replace('לנושא', 'לאירוע')
        .replace('הנושא', 'האירוע')
        .replace('נושא', 'אירוע'));
    }
    throw error;
  }
}

/** Whether a stored team task belongs to placeholder [id]. */
export function isLinkedToPendingEvent(raw: Record<string, unknown>, id: string): boolean {
  const link = raw['link'];
  if (link == null || typeof link !== 'object') return false;
  const record = link as Record<string, unknown>;
  return record['type'] === 'pendingEvent' && record['id'] === id;
}

/**
 * `pendingEvent.link`: checks the request and returns the placeholder and
 * the list without it. The caller moves the tasks (a manager only).
 */
export function planPendingEventLink(
  items: Array<Record<string, unknown>>,
  payload: Record<string, unknown>,
  actor: TaskActor,
): {pendingEventId: string; eventId: string; before: Record<string, unknown>;
    items: Array<Record<string, unknown>>} {
  requireTaskManager(actor);
  const pendingEventId = payload['pendingEventId'];
  const eventId = payload['eventId'];
  if (typeof pendingEventId !== 'string' || pendingEventId.length === 0) {
    throw new TaskError(400, 'חסר מזהה של האירוע שעוד לא נוצר');
  }
  if (typeof eventId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(eventId)) {
    throw new TaskError(400, 'אירוע לא תקין');
  }
  const before = items.find((entry) => entry['id'] === pendingEventId);
  if (before == null) throw new TaskError(404, 'האירוע שעוד לא נוצר לא נמצא');
  return {
    pendingEventId,
    eventId,
    before,
    items: items.filter((entry) => entry['id'] !== pendingEventId),
  };
}
