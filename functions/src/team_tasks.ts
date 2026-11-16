import {randomUUID} from 'node:crypto';
import {Timestamp} from 'firebase-admin/firestore';
import {StageContact, parseContacts, storedContacts} from './stages';
import {TaskActor, TaskError, canManageTasks, requireTaskManager} from './tasks';

/**
 * Pure transitions for the team tasks ("משימות") screen.
 *
 * Like `tasks.ts`, nothing here touches Firestore: every function takes the
 * stored task (or a client payload) plus an injected `now` and actor and
 * returns the full next document. `index.ts` runs them inside a transaction and
 * checks what needs the database (the link exists, the owners are active
 * members, a duplicate's original exists).
 *
 * Every builder recomputes `ownerIds` ([deriveOwnerIds]); the read rule and a
 * non-manager's query rely on it.
 */

export type TeamTaskStatus = 'open' | 'inProgress' | 'done' | 'cancelled' | 'duplicate';

export const TEAM_TASK_STATUSES: readonly TeamTaskStatus[] =
  ['open', 'inProgress', 'done', 'cancelled', 'duplicate'];

/**
 * `pendingEvent` = "אירוע שעוד לא נוצר" (round 10): a named placeholder in
 * `utilities/Lists` → `PendingEvents`, linked later to the real event
 * (`pendingEvent.link` moves every task of it at once).
 */
export type TaskLinkType = 'event' | 'category' | 'topic' | 'pendingEvent';

export type TaskLink = {type: TaskLinkType; id: string} | null;

/**
 * How urgent a task is (Omer, 16/11/2026: three levels). A stored task with
 * no `urgency` reads as `normal`.
 */
export type TeamTaskUrgency = 'low' | 'normal' | 'high';

export const TEAM_TASK_URGENCIES: readonly TeamTaskUrgency[] = ['low', 'normal', 'high'];

/**
 * A subtask is a task of its own nested in its parent (Omer, round 2): title,
 * description, owners, contacts, deadline, the five statuses and its own
 * update log. It has no link (the parent's) and no subtasks.
 */
export type TeamSubtask = {
  id: string;
  title: string;
  description: string;
  assigneeIds: string[];
  contacts: StageContact[];
  deadline: string | null;
  status: TeamTaskStatus;
  duplicateOfId: string | null;
  /** Newest first. */
  updates: TaskUpdateEntry[];
  completedAt: Timestamp | null;
};

/** What a manager edits on a subtask; the rest has its own operations. */
export type SubtaskFields = Pick<
  TeamSubtask, 'id' | 'title' | 'description' | 'assigneeIds' | 'contacts' | 'deadline'
>;

export type TaskUpdateEntry = {
  id: string;
  text: string;
  at: Timestamp;
  byId: string;
  byName: string | null;
  /** Set when its writer (or a manager) edited it (round 10); shown "(נערך)". */
  editedAt?: Timestamp | null;
};

export type TeamTaskDoc = {
  id: string;
  title: string;
  description: string;
  link: TaskLink;
  /**
   * Every event of a task linked to several events (16/11/2026), the link's
   * own event first; empty unless [link] is an event. Older app versions read
   * only [link], so they still see the first event.
   */
  eventIds: string[];
  urgency: TeamTaskUrgency;
  /** The task's own owners; always empty when it has subtasks. */
  assigneeIds: string[];
  subtasks: TeamSubtask[];
  contacts: StageContact[];
  /** `yyyy-MM-dd`; null = no deadline. */
  deadline: string | null;
  status: TeamTaskStatus;
  duplicateOfId: string | null;
  /** Newest first. */
  updates: TaskUpdateEntry[];
  /** Derived: [deriveOwnerIds]. */
  ownerIds: string[];
  completedAt: Timestamp | null;
  createdAt: Timestamp;
  createdById: string;
  updatedAt: Timestamp;
};

type Ctx = {now: Timestamp; actor: TaskActor};

const MAX_TITLE_LENGTH = 200;
const MAX_DESCRIPTION_LENGTH = 5000;
const MAX_SUBTASKS = 50;
const MAX_ASSIGNEES = 100;
const MAX_UPDATE_LENGTH = 2000;
const MAX_UPDATES = 500;
/** A subtask's log is capped lower: up to 50 of them share one document. */
const MAX_SUBTASK_UPDATES = 100;
const DATE_PATTERN = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const LINK_TYPES: readonly TaskLinkType[] = ['event', 'category', 'topic', 'pendingEvent'];
const MAX_EVENTS = 50;

/**
 * The events of a task: [link]'s event first, then [ids] once each; none
 * when [link] is not an event.
 */
export function normalizeEventIds(link: TaskLink, ids: readonly string[]): string[] {
  if (link == null || link.type !== 'event') return [];
  const result = [link.id];
  for (const id of ids) {
    if (!result.includes(id)) result.push(id);
  }
  return result;
}

function storedUrgency(value: unknown): TeamTaskUrgency {
  return TEAM_TASK_URGENCIES.includes(value as TeamTaskUrgency)
    ? value as TeamTaskUrgency
    : 'normal';
}

// ---- owners and permissions ----

export function deriveOwnerIds(
  task: Pick<TeamTaskDoc, 'assigneeIds' | 'subtasks'>,
): string[] {
  if (task.subtasks.length === 0) return [...new Set(task.assigneeIds)];
  const ids: string[] = [];
  for (const subtask of task.subtasks) {
    for (const id of subtask.assigneeIds) {
      if (!ids.includes(id)) ids.push(id);
    }
  }
  return ids;
}

export function isTeamTaskOwner(
  task: Pick<TeamTaskDoc, 'ownerIds'>,
  actor: TaskActor,
): boolean {
  return task.ownerIds.includes(actor.memberId);
}

function requireManagerOrOwner(task: TeamTaskDoc, actor: TaskActor): void {
  if (!canManageTasks(actor) && !isTeamTaskOwner(task, actor)) {
    throw new TaskError(403, 'אין לך הרשאה לעדכן את המשימה');
  }
}

function findSubtask(task: TeamTaskDoc, subtaskId: string): TeamSubtask {
  const subtask = task.subtasks.find((entry) => entry.id === subtaskId);
  if (subtask == null) throw new TaskError(404, 'תת-המשימה לא נמצאה');
  return subtask;
}

/** A subtask is changed by a manager or by one of ITS owners. */
function requireManagerOrSubtaskOwner(subtask: TeamSubtask, actor: TaskActor): void {
  if (!canManageTasks(actor) && !subtask.assigneeIds.includes(actor.memberId)) {
    throw new TaskError(403, 'רק אחראי על תת-המשימה יכול לעדכן אותה');
  }
}

export function teamTaskAuditDetails(
  task: Pick<TeamTaskDoc, 'title' | 'link'>,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {name: task.title, link: task.link, ...extra};
}

// ---- reading a stored document ----

function storedString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function storedTimestamp(value: unknown): Timestamp | null {
  return value instanceof Timestamp ? value : null;
}

function storedStringList(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((entry): entry is string => typeof entry === 'string')
    : [];
}

function storedLink(value: unknown): TaskLink {
  if (value == null || typeof value !== 'object') return null;
  const record = value as Record<string, unknown>;
  const type = record['type'];
  const id = record['id'];
  if (typeof id !== 'string' || id.length === 0) return null;
  if (!LINK_TYPES.includes(type as TaskLinkType)) return null;
  return {type: type as TaskLinkType, id};
}

function storedStatus(value: unknown): TeamTaskStatus {
  return TEAM_TASK_STATUSES.includes(value as TeamTaskStatus)
    ? value as TeamTaskStatus
    : 'open';
}

function storedSubtasks(value: unknown): TeamSubtask[] {
  if (!Array.isArray(value)) return [];
  const subtasks: TeamSubtask[] = [];
  for (const entry of value) {
    if (entry == null || typeof entry !== 'object') continue;
    const record = entry as Record<string, unknown>;
    const id = record['id'];
    const title = record['title'];
    if (typeof id !== 'string' || id.length === 0 || typeof title !== 'string') continue;
    // Before round 2 a subtask had one owner (`assigneeId`) and a tick
    // (`isDone`); such a document still reads.
    const legacyOwner = storedString(record['assigneeId']);
    const status = record['status'] === undefined
      ? (record['isDone'] === true ? 'done' : 'open')
      : storedStatus(record['status']);
    subtasks.push({
      id,
      title,
      description: storedString(record['description']) ?? '',
      assigneeIds: Array.isArray(record['assigneeIds'])
        ? storedStringList(record['assigneeIds'])
        : (legacyOwner == null ? [] : [legacyOwner]),
      contacts: storedContacts(record['contacts']),
      deadline: storedString(record['deadline']),
      status,
      duplicateOfId: status === 'duplicate' ? storedString(record['duplicateOfId']) : null,
      updates: storedUpdates(record['updates']),
      completedAt: storedTimestamp(record['completedAt']),
    });
  }
  return subtasks;
}

function storedUpdates(value: unknown): TaskUpdateEntry[] {
  if (!Array.isArray(value)) return [];
  const updates: TaskUpdateEntry[] = [];
  for (const entry of value) {
    if (entry == null || typeof entry !== 'object') continue;
    const record = entry as Record<string, unknown>;
    const id = record['id'];
    const text = record['text'];
    const at = storedTimestamp(record['at']);
    if (typeof id !== 'string' || typeof text !== 'string' || at == null) continue;
    updates.push({
      id,
      text,
      at,
      byId: storedString(record['byId']) ?? '',
      byName: storedString(record['byName']),
      ...(storedTimestamp(record['editedAt']) != null
        ? {editedAt: storedTimestamp(record['editedAt'])}
        : {}),
    });
  }
  return updates;
}

export function teamTaskFromStored(id: string, raw: Record<string, unknown>): TeamTaskDoc {
  const status = storedStatus(raw['status']);
  const link = storedLink(raw['link']);
  return {
    id,
    title: storedString(raw['title']) ?? '',
    description: storedString(raw['description']) ?? '',
    link,
    eventIds: normalizeEventIds(link, storedStringList(raw['eventIds'])),
    urgency: storedUrgency(raw['urgency']),
    assigneeIds: storedStringList(raw['assigneeIds']),
    subtasks: storedSubtasks(raw['subtasks']),
    contacts: storedContacts(raw['contacts']),
    deadline: storedString(raw['deadline']),
    status,
    duplicateOfId: status === 'duplicate' ? storedString(raw['duplicateOfId']) : null,
    updates: storedUpdates(raw['updates']),
    ownerIds: storedStringList(raw['ownerIds']),
    completedAt: storedTimestamp(raw['completedAt']),
    createdAt: storedTimestamp(raw['createdAt']) ?? Timestamp.fromMillis(0),
    createdById: storedString(raw['createdById']) ?? '',
    updatedAt: storedTimestamp(raw['updatedAt']) ?? Timestamp.fromMillis(0),
  };
}

// ---- validating a client payload ----

type EditableFields = {
  title: string;
  description: string;
  link: TaskLink;
  /** Null = the payload has no `eventIds` (an older app version). */
  eventIds: string[] | null;
  /** Null = the payload has no `urgency` (an older app version). */
  urgency: TeamTaskUrgency | null;
  assigneeIds: string[];
  /** Null = the payload has no `subtasks` (this app version, 16/11/2026). */
  subtasks: SubtaskFields[] | null;
  contacts: StageContact[];
  deadline: string | null;
};

export function parseTaskLink(value: unknown): TaskLink {
  if (value == null) return null;
  if (typeof value !== 'object') throw new TaskError(400, 'שיוך לא תקין');
  const record = value as Record<string, unknown>;
  const type = record['type'];
  const id = record['id'];
  if (!LINK_TYPES.includes(type as TaskLinkType)) {
    throw new TaskError(400, 'שיוך לא תקין');
  }
  if (typeof id !== 'string' || !ID_PATTERN.test(id)) {
    throw new TaskError(400, 'שיוך לא תקין');
  }
  return {type: type as TaskLinkType, id};
}

function parseEventIds(value: unknown): string[] | null {
  if (value === undefined) return null;
  if (value === null) return [];
  if (!Array.isArray(value)) throw new TaskError(400, 'שיוך לא תקין');
  const ids: string[] = [];
  for (const entry of value) {
    if (typeof entry !== 'string' || !ID_PATTERN.test(entry)) {
      throw new TaskError(400, 'שיוך לא תקין');
    }
    if (!ids.includes(entry)) ids.push(entry);
  }
  if (ids.length > MAX_EVENTS) throw new TaskError(400, 'יותר מדי אירועים');
  return ids;
}

export function parseTeamTaskUrgency(value: unknown): TeamTaskUrgency | null {
  if (value === undefined || value === null) return null;
  if (!TEAM_TASK_URGENCIES.includes(value as TeamTaskUrgency)) {
    throw new TaskError(400, 'דחיפות לא תקינה');
  }
  return value as TeamTaskUrgency;
}

function parseDeadline(value: unknown): string | null {
  if (value == null || value === '') return null;
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) {
    throw new TaskError(400, 'דד ליין לא תקין');
  }
  return value;
}

function parseMemberId(value: unknown): string {
  if (typeof value !== 'string' || !ID_PATTERN.test(value)) {
    throw new TaskError(400, 'אחראי לא תקין');
  }
  return value;
}

function parseAssigneeIds(value: unknown): string[] {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TaskError(400, 'אחראים לא תקינים');
  const ids: string[] = [];
  for (const entry of value) {
    const id = parseMemberId(entry);
    if (!ids.includes(id)) ids.push(id);
  }
  if (ids.length > MAX_ASSIGNEES) throw new TaskError(400, 'יותר מדי אחראים');
  return ids;
}

function parseDescription(value: unknown): string {
  if (value != null && typeof value !== 'string') {
    throw new TaskError(400, 'תיאור לא תקין');
  }
  const description = (value ?? '').trim();
  if (description.length > MAX_DESCRIPTION_LENGTH) {
    throw new TaskError(400, 'התיאור ארוך מדי');
  }
  return description;
}

function parseSubtasks(value: unknown): SubtaskFields[] {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TaskError(400, 'תתי-משימות לא תקינות');
  if (value.length > MAX_SUBTASKS) throw new TaskError(400, 'יותר מדי תתי-משימות');
  const subtasks: SubtaskFields[] = [];
  const seen = new Set<string>();
  for (const entry of value) {
    if (entry == null || typeof entry !== 'object') {
      throw new TaskError(400, 'תת-משימה לא תקינה');
    }
    const record = entry as Record<string, unknown>;
    const id = record['id'];
    if (typeof id !== 'string' || !ID_PATTERN.test(id) || seen.has(id)) {
      throw new TaskError(400, 'תת-משימה לא תקינה');
    }
    const title = typeof record['title'] === 'string' ? record['title'].trim() : '';
    if (title.length === 0) throw new TaskError(400, 'חובה להזין שם לתת-משימה');
    if (title.length > MAX_TITLE_LENGTH) throw new TaskError(400, 'שם תת-המשימה ארוך מדי');
    seen.add(id);
    subtasks.push({
      id,
      title,
      description: parseDescription(record['description']),
      assigneeIds: parseAssigneeIds(record['assigneeIds']),
      contacts: parseContacts(record['contacts']),
      deadline: parseDeadline(record['deadline']),
    });
  }
  return subtasks;
}

function parseEditableFields(input: Record<string, unknown>): EditableFields {
  const title = typeof input['title'] === 'string' ? input['title'].trim() : '';
  if (title.length === 0) throw new TaskError(400, 'חובה להזין כותרת');
  if (title.length > MAX_TITLE_LENGTH) throw new TaskError(400, 'הכותרת ארוכה מדי');

  const description = parseDescription(input['description']);

  const subtasks = input['subtasks'] === undefined ? null : parseSubtasks(input['subtasks']);
  return {
    title,
    description,
    link: parseTaskLink(input['link']),
    eventIds: parseEventIds(input['eventIds']),
    urgency: parseTeamTaskUrgency(input['urgency']),
    // A task with subtasks has no owners of its own (decision 6).
    assigneeIds: subtasks != null && subtasks.length > 0
      ? []
      : parseAssigneeIds(input['assigneeIds']),
    subtasks,
    contacts: parseContacts(input['contacts']),
    deadline: parseDeadline(input['deadline']),
  };
}

// ---- status ----

/**
 * A parent's status, computed from its subtasks (Omer, round 4: it is never
 * set by hand). Cancelled and duplicate subtasks do not count; of the rest:
 * every one open = open, every one done = done, anything else (one in
 * progress, or open and done mixed) = in progress. When every subtask is
 * cancelled or a duplicate there is nothing left to do: cancelled.
 */
export function deriveParentStatus(subtasks: readonly TeamSubtask[]): TeamTaskStatus {
  const counted = subtasks.filter((subtask) =>
    subtask.status !== 'cancelled' && subtask.status !== 'duplicate');
  if (counted.length === 0) return 'cancelled';
  if (counted.every((subtask) => subtask.status === 'open')) return 'open';
  if (counted.every((subtask) => subtask.status === 'done')) return 'done';
  return 'inProgress';
}

/** [next] with the status its subtasks give it; a task without subtasks keeps its own. */
function withAutoStatus(previous: TeamTaskDoc, next: TeamTaskDoc, ctx: Ctx): TeamTaskDoc {
  if (next.subtasks.length === 0) return next;
  const status = deriveParentStatus(next.subtasks);
  return {
    ...next,
    status,
    duplicateOfId: null,
    completedAt: status === 'done'
      ? (previous.status === 'done' && previous.completedAt != null ? previous.completedAt : ctx.now)
      : null,
  };
}

function finish(task: TeamTaskDoc): TeamTaskDoc {
  return {...task, ownerIds: deriveOwnerIds(task)};
}

// ---- transitions ----

function newSubtask(fields: SubtaskFields): TeamSubtask {
  return {
    ...fields,
    status: 'open',
    duplicateOfId: null,
    updates: [],
    completedAt: null,
  };
}

export function buildNewTeamTask(input: Record<string, unknown>, ctx: Ctx): TeamTaskDoc {
  requireTaskManager(ctx.actor);
  const id = input['id'];
  if (typeof id !== 'string' || !ID_PATTERN.test(id)) {
    throw new TaskError(400, 'מזהה משימה לא תקין');
  }
  const fields = parseEditableFields(input);
  return finish({
    id,
    ...fields,
    eventIds: normalizeEventIds(fields.link, fields.eventIds ?? []),
    urgency: fields.urgency ?? 'normal',
    subtasks: (fields.subtasks ?? []).map(newSubtask),
    status: 'open',
    duplicateOfId: null,
    updates: [],
    ownerIds: [],
    completedAt: null,
    createdAt: ctx.now,
    createdById: ctx.actor.memberId,
    updatedAt: ctx.now,
  });
}

export function applyTeamTaskEdit(
  task: TeamTaskDoc,
  input: Record<string, unknown>,
  ctx: Ctx,
): TeamTaskDoc {
  requireTaskManager(ctx.actor);
  if (input['id'] !== task.id) throw new TaskError(400, 'מזהה משימה לא תואם');
  const fields = parseEditableFields(input);
  const storedById = new Map(task.subtasks.map((subtask) => [subtask.id, subtask]));
  // A payload without subtasks (this app version, which no longer shows
  // them) keeps the stored ones; without the task's owners then.
  const subtasks = fields.subtasks == null
    ? task.subtasks
    : fields.subtasks.map((subtask) => {
      // A subtask keeps its status, log and completion; only what a manager
      // edits comes from the payload.
      const stored = storedById.get(subtask.id);
      return stored == null ? newSubtask(subtask) : {...stored, ...subtask};
    });
  // An older app version sends no `eventIds`: the events stay while the
  // link's event does.
  const eventIds = fields.eventIds != null
    ? normalizeEventIds(fields.link, fields.eventIds)
    : (fields.link?.type === 'event' && task.link?.type === 'event' && fields.link.id === task.link.id
      ? task.eventIds
      : normalizeEventIds(fields.link, []));
  const next: TeamTaskDoc = {
    ...task,
    ...fields,
    eventIds,
    urgency: fields.urgency ?? task.urgency,
    subtasks,
    assigneeIds: subtasks.length > 0 ? [] : fields.assigneeIds,
    updatedAt: ctx.now,
  };
  return finish(withAutoStatus(task, next, ctx));
}

export function parseTeamTaskStatus(value: unknown): TeamTaskStatus {
  if (!TEAM_TASK_STATUSES.includes(value as TeamTaskStatus)) {
    throw new TaskError(400, 'סטטוס לא תקין');
  }
  return value as TeamTaskStatus;
}

export function applyTeamTaskStatus(
  task: TeamTaskDoc,
  status: TeamTaskStatus,
  duplicateOfId: string | null,
  ctx: Ctx,
): TeamTaskDoc {
  requireManagerOrOwner(task, ctx.actor);
  if (task.subtasks.length > 0) {
    throw new TaskError(400, 'הסטטוס של משימת אב נקבע לפי תתי-המשימות');
  }
  let original: string | null = null;
  if (status === 'duplicate') {
    if (duplicateOfId == null || !ID_PATTERN.test(duplicateOfId)) {
      throw new TaskError(400, 'יש לבחור את המשימה המקורית');
    }
    if (duplicateOfId === task.id) {
      throw new TaskError(400, 'משימה לא יכולה להיות כפילות של עצמה');
    }
    original = duplicateOfId;
  }
  const completedAt = status === 'done'
    ? (task.status === 'done' ? task.completedAt : ctx.now)
    : null;
  return finish({
    ...task,
    status,
    duplicateOfId: original,
    completedAt,
    updatedAt: ctx.now,
  });
}

/**
 * A subtask's own status, by a manager or one of its owners. A duplicate
 * points to another subtask of the same task or to another task (the caller
 * checks that a task id exists). The parent's status follows.
 */
export function applyTeamSubtaskStatus(
  task: TeamTaskDoc,
  subtaskId: string,
  status: TeamTaskStatus,
  duplicateOfId: string | null,
  ctx: Ctx,
): TeamTaskDoc {
  const subtask = findSubtask(task, subtaskId);
  requireManagerOrSubtaskOwner(subtask, ctx.actor);
  let original: string | null = null;
  if (status === 'duplicate') {
    if (duplicateOfId == null || !ID_PATTERN.test(duplicateOfId)) {
      throw new TaskError(400, 'יש לבחור את המשימה המקורית');
    }
    if (duplicateOfId === subtaskId || duplicateOfId === task.id) {
      throw new TaskError(400, 'משימה לא יכולה להיות כפילות של עצמה');
    }
    original = duplicateOfId;
  }
  const completedAt = status === 'done'
    ? (subtask.status === 'done' ? subtask.completedAt : ctx.now)
    : null;
  const next: TeamTaskDoc = {
    ...task,
    subtasks: task.subtasks.map((entry) =>
      entry.id === subtaskId
        ? {...entry, status, duplicateOfId: original, completedAt}
        : entry,
    ),
    updatedAt: ctx.now,
  };
  return finish(withAutoStatus(task, next, ctx));
}

/** The quick tick in the parent's list: done, or back to open. */
export function applyTeamSubtaskToggle(
  task: TeamTaskDoc,
  subtaskId: string,
  isDone: boolean,
  ctx: Ctx,
): TeamTaskDoc {
  return applyTeamSubtaskStatus(task, subtaskId, isDone ? 'done' : 'open', null, ctx);
}

/**
 * Adds to the task's log, or with [subtaskId] to that subtask's own log (a
 * manager or one of the subtask's owners).
 */
export function appendTeamTaskUpdate(
  task: TeamTaskDoc,
  text: string,
  ctx: Ctx,
  subtaskId: string | null = null,
): TeamTaskDoc {
  if (subtaskId == null) {
    requireManagerOrOwner(task, ctx.actor);
  } else {
    requireManagerOrSubtaskOwner(findSubtask(task, subtaskId), ctx.actor);
  }
  const trimmed = typeof text === 'string' ? text.trim() : '';
  if (trimmed.length === 0) throw new TaskError(400, 'חובה להזין עדכון');
  if (trimmed.length > MAX_UPDATE_LENGTH) throw new TaskError(400, 'העדכון ארוך מדי');
  const entry: TaskUpdateEntry = {
    id: randomUUID(),
    text: trimmed,
    at: ctx.now,
    byId: ctx.actor.memberId,
    byName: ctx.actor.name,
  };
  if (subtaskId != null) {
    return finish({
      ...task,
      subtasks: task.subtasks.map((subtask) =>
        subtask.id === subtaskId
          ? {...subtask, updates: [entry, ...subtask.updates].slice(0, MAX_SUBTASK_UPDATES)}
          : subtask,
      ),
      updatedAt: ctx.now,
    });
  }
  return finish({
    ...task,
    updates: [entry, ...task.updates].slice(0, MAX_UPDATES),
    updatedAt: ctx.now,
  });
}

// ---- editing the log (round 10) ----

/**
 * Who may change an update: its writer, or a manager. An update with no
 * writer (`byId` empty, "מהאקסל") only a manager. The app offers a manager
 * the others' updates only in "כל המשימות" (Omer, round 10).
 */
function requireUpdateEditor(entry: TaskUpdateEntry, actor: TaskActor): void {
  if (canManageTasks(actor)) return;
  if (entry.byId.length > 0 && entry.byId === actor.memberId) return;
  throw new TaskError(403, 'אפשר לערוך או למחוק רק עדכון שכתבת');
}

function changeLog(
  task: TeamTaskDoc,
  subtaskId: string | null,
  updateId: string,
  ctx: Ctx,
  change: (log: TaskUpdateEntry[], index: number) => TaskUpdateEntry[],
): TeamTaskDoc {
  const log = subtaskId == null ? task.updates : findSubtask(task, subtaskId).updates;
  const index = log.findIndex((entry) => entry.id === updateId);
  if (index < 0) throw new TaskError(404, 'העדכון לא נמצא');
  requireUpdateEditor(log[index], ctx.actor);
  const next = change(log, index);
  if (subtaskId == null) {
    return finish({...task, updates: next, updatedAt: ctx.now});
  }
  return finish({
    ...task,
    subtasks: task.subtasks.map((subtask) =>
      subtask.id === subtaskId ? {...subtask, updates: next} : subtask),
    updatedAt: ctx.now,
  });
}

/** A new text for update [updateId], marked edited; its date and writer stay. */
export function editTeamTaskUpdate(
  task: TeamTaskDoc,
  updateId: string,
  text: string,
  ctx: Ctx,
  subtaskId: string | null = null,
): TeamTaskDoc {
  const trimmed = typeof text === 'string' ? text.trim() : '';
  if (trimmed.length === 0) throw new TaskError(400, 'חובה להזין עדכון');
  if (trimmed.length > MAX_UPDATE_LENGTH) throw new TaskError(400, 'העדכון ארוך מדי');
  return changeLog(task, subtaskId, updateId, ctx, (log, index) => log.map((entry, i) =>
    i === index ? {...entry, text: trimmed, editedAt: ctx.now} : entry));
}

export function deleteTeamTaskUpdate(
  task: TeamTaskDoc,
  updateId: string,
  ctx: Ctx,
  subtaskId: string | null = null,
): TeamTaskDoc {
  return changeLog(task, subtaskId, updateId, ctx,
    (log, index) => log.filter((_, i) => i !== index));
}
