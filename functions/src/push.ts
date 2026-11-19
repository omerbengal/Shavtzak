import {createHash} from 'node:crypto';
import {TaskError} from './tasks';

/**
 * Web Push for the team tasks ("שובצת למשימה"), apart from Firestore and
 * from the web-push library: index.ts gives [sendTaskAssignedPush] a store
 * and a sender, the tests give it fakes.
 */

/** The VAPID public key; its private half is the Firebase secret
 * `WEB_PUSH_VAPID_PRIVATE_KEY`. The app subscribes with the same key
 * (`PushNotificationService.vapidPublicKey`). */
export const VAPID_PUBLIC_KEY =
  'BFG-lA4XBV-QImmU-vJNKvD-TssSHXTAvMqFct1B5h9lH_fO0G1kDUoJXng1Sjy6n_3vsoW9XgH_pDls0-XIg80';

/** The VAPID "subject": who the push services may contact about the sender. */
export const PUSH_SUBJECT = 'https://omerbengal.github.io/Shavtzak/';

/** Which function stored a subscription: `api` (the real site) or
 * `apiPreview` (a branch preview). Each sends only to its own, so a push from
 * the real site never opens an expired preview link, and the reverse. */
export type PushSite = 'main' | 'preview';

export type PushKeys = {p256dh: string; auth: string};

export type StoredSubscription = {
  id: string;
  memberId: string;
  site: PushSite;
  endpoint: string;
  keys: PushKeys;
};

export interface PushStore {
  /** The team member documents among [ids] that exist. */
  members(ids: string[]): Promise<Map<string, Record<string, unknown>>>;
  subscriptionsOf(memberIds: string[], site: PushSite): Promise<StoredSubscription[]>;
  deleteSubscription(id: string): Promise<void>;
}

/** Sends [payload] to [subscription]; throws an error carrying the push
 * service's `statusCode` on a refusal (as web-push does). */
export type PushSend = (subscription: StoredSubscription, payload: string) => Promise<void>;

type WithOwners = {ownerIds: string[]};

/** The owners [after] has and [before] did not (all of them for a new task),
 * without [actorId]: nobody is told about a change they made themselves. */
export function addedOwnerIds(
  before: WithOwners | null,
  after: WithOwners | null,
  actorId: string,
): string[] {
  if (after == null) return [];
  const had = new Set(before?.ownerIds ?? []);
  return [...new Set(after.ownerIds)].filter((id) => !had.has(id) && id !== actorId);
}

/** Who gets the team-task notifications: every active, unarchived member
 * (Omer, 17/11/2026; an owner can open the task from the members' "משימות"
 * tab). Its twin in the app is `canGetTeamTaskNotifications`: change both. */
export function canReceiveTaskPush(member: Record<string, unknown>): boolean {
  return member['isActive'] === true && member['isArchived'] !== true;
}

export type PushMessage = {title: string; body: string; tag: string; path: string};

/** The notification (Omer, 16/11/2026, msg 4302): a fixed title and the
 * task's title, nothing else; a tap opens [path] (the app's hash route). */
export function taskAssignedMessage(
  task: {id: string; title: string},
  routePrefix: '' | '/test',
): PushMessage {
  return {
    title: '📋 שובצת למשימה',
    body: task.title,
    tag: `task-${task.id}`,
    path: `${routePrefix}/team-tasks?task=${encodeURIComponent(task.id)}`,
  };
}

/** The tag notification (Omer, 19/11/2026): "@ תויגת במשימה" + the title;
 * a tap opens the task, as [taskAssignedMessage]. */
export function taskMentionedMessage(
  task: {id: string; title: string},
  routePrefix: '' | '/test',
): PushMessage {
  return {
    title: '@ תויגת במשימה',
    body: task.title,
    tag: `task-mention-${task.id}`,
    path: `${routePrefix}/team-tasks?task=${encodeURIComponent(task.id)}`,
  };
}

type WithMentions = {mentions: {memberId: string; doneAt: unknown}[]};

/** The members whose tag [after] opened (a new tag, or a done one tagged
 * again), without [actorId]. */
export function openedMentionIds(
  before: WithMentions | null,
  after: WithMentions | null,
  actorId: string,
): string[] {
  if (after == null) return [];
  const wasOpen = new Set(
    (before?.mentions ?? []).filter((m) => m.doneAt == null).map((m) => m.memberId),
  );
  return after.mentions
    .filter((m) => m.doneAt == null && !wasOpen.has(m.memberId) && m.memberId !== actorId)
    .map((m) => m.memberId);
}

/** One document per browser subscription: the same device signing in as
 * someone else overwrites it, so a shared computer never keeps getting the
 * previous member's notifications. */
export function subscriptionDocId(endpoint: string): string {
  return createHash('sha256').update(endpoint).digest('hex');
}

function nonEmpty(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0;
}

/** A browser `PushSubscription.toJSON()`, checked. */
export function parseSubscription(raw: unknown): {endpoint: string; keys: PushKeys} {
  if (raw == null || typeof raw !== 'object') throw new TaskError(400, 'Missing subscription');
  const record = raw as Record<string, unknown>;
  const endpoint = record['endpoint'];
  let url: URL | null = null;
  try {
    url = nonEmpty(endpoint) ? new URL(endpoint) : null;
  } catch {
    url = null;
  }
  if (url == null || url.protocol !== 'https:') throw new TaskError(400, 'Invalid subscription endpoint');
  const keys = record['keys'] as Record<string, unknown> | undefined;
  if (keys == null || !nonEmpty(keys['p256dh']) || !nonEmpty(keys['auth'])) {
    throw new TaskError(400, 'Invalid subscription keys');
  }
  return {endpoint: endpoint as string, keys: {p256dh: keys['p256dh'] as string, auth: keys['auth'] as string}};
}

export type PushResult = {sent: number; dropped: number; failed: number};

/** Tells every owner a team-task write added ([addedOwnerIds], who may get
 * it, [canReceiveTaskPush]) on each of their devices of [site]. Never throws:
 * a notification must not fail the write that already happened. A
 * subscription the push service no longer knows (404 / 410) is deleted. */
export async function sendTaskAssignedPush(
  store: PushStore,
  send: PushSend,
  input: {
    before: (WithOwners & {id: string; title: string}) | null;
    after: (WithOwners & {id: string; title: string}) | null;
    actorId: string;
    site: PushSite;
    routePrefix: '' | '/test';
  },
): Promise<PushResult> {
  if (input.after == null) return {sent: 0, dropped: 0, failed: 0};
  return sendToMembers(
    store,
    send,
    addedOwnerIds(input.before, input.after, input.actorId),
    taskAssignedMessage(input.after, input.routePrefix),
    input.site,
  );
}

/** Tells every member a log update newly tagged ([openedMentionIds]) on
 * each of their devices of [site]; like [sendTaskAssignedPush], never
 * throws. */
export async function sendTaskMentionedPush(
  store: PushStore,
  send: PushSend,
  input: {
    before: (WithMentions & {id: string; title: string}) | null;
    after: (WithMentions & {id: string; title: string}) | null;
    actorId: string;
    site: PushSite;
    routePrefix: '' | '/test';
  },
): Promise<PushResult> {
  if (input.after == null) return {sent: 0, dropped: 0, failed: 0};
  return sendToMembers(
    store,
    send,
    openedMentionIds(input.before, input.after, input.actorId),
    taskMentionedMessage(input.after, input.routePrefix),
    input.site,
  );
}

/** [message] to every one of [ids] who may get it ([canReceiveTaskPush]),
 * on each of their devices of [site]. Never throws; a subscription the push
 * service no longer knows (404 / 410) is deleted. */
async function sendToMembers(
  store: PushStore,
  send: PushSend,
  ids: string[],
  message: PushMessage,
  site: PushSite,
): Promise<PushResult> {
  const result: PushResult = {sent: 0, dropped: 0, failed: 0};
  try {
    const added = ids;
    if (added.length === 0) return result;
    const members = await store.members(added);
    const recipients = added.filter((id) => {
      const member = members.get(id);
      return member != null && canReceiveTaskPush(member);
    });
    if (recipients.length === 0) return result;
    const subscriptions = await store.subscriptionsOf(recipients, site);
    const payload = JSON.stringify(message);
    await Promise.all(subscriptions.map(async (subscription) => {
      try {
        await send(subscription, payload);
        result.sent++;
      } catch (error) {
        const status = (error as {statusCode?: unknown})?.statusCode;
        if (status === 404 || status === 410) {
          result.dropped++;
          await store.deleteSubscription(subscription.id).catch(() => {});
        } else {
          result.failed++;
          console.warn('push send failed', subscription.id, status ?? error);
        }
      }
    }));
  } catch (error) {
    console.warn('push: team-task notification skipped', error);
  }
  return result;
}
