import test from 'node:test';
import assert from 'node:assert/strict';
import {TaskError} from './tasks';
import {
  PushStore,
  StoredSubscription,
  addedOwnerIds,
  canReceiveTaskPush,
  parseSubscription,
  sendTaskAssignedPush,
  subscriptionDocId,
  taskAssignedMessage,
} from './push';

const admin = {isAdmin: true, isActive: true};
const member = {isAdmin: false, isActive: true};

function sub(id: string, memberId: string, site: 'main' | 'preview' = 'main'): StoredSubscription {
  return {id, memberId, site, endpoint: `https://push.example/${id}`, keys: {p256dh: 'p', auth: 'a'}};
}

class FakeStore implements PushStore {
  deleted: string[] = [];
  constructor(
    private readonly people: Record<string, Record<string, unknown>>,
    private readonly subs: StoredSubscription[],
    private readonly failMembers = false,
  ) {}
  async members(ids: string[]) {
    if (this.failMembers) throw new Error('firestore down');
    const found = new Map<string, Record<string, unknown>>();
    for (const id of ids) if (this.people[id]) found.set(id, this.people[id]);
    return found;
  }
  async subscriptionsOf(memberIds: string[], site: 'main' | 'preview') {
    return this.subs.filter((s) => memberIds.includes(s.memberId) && s.site === site);
  }
  async deleteSubscription(id: string) {
    this.deleted.push(id);
  }
}

function recorder(failures: Record<string, number> = {}) {
  const calls: Array<{id: string; payload: Record<string, unknown>}> = [];
  const send = async (s: StoredSubscription, payload: string) => {
    calls.push({id: s.id, payload: JSON.parse(payload)});
    const status = failures[s.id];
    if (status != null) throw Object.assign(new Error('push failed'), {statusCode: status});
  };
  return {calls, send};
}

const task = (ownerIds: string[]) => ({id: 't1', title: 'הוספת סבב נוסף', ownerIds});

test('addedOwnerIds: only owners the write added, never the actor', () => {
  assert.deepEqual(addedOwnerIds(null, task(['a', 'b', 'me']), 'me'), ['a', 'b']);
  assert.deepEqual(addedOwnerIds(task(['a']), task(['a', 'b']), 'me'), ['b']);
  assert.deepEqual(addedOwnerIds(task(['a', 'b']), task(['a']), 'me'), []);
  assert.deepEqual(addedOwnerIds(task(['a']), task(['a']), 'me'), []);
  assert.deepEqual(addedOwnerIds(task(['a']), null, 'me'), []);
});

test('canReceiveTaskPush: every active, unarchived member', () => {
  assert.equal(canReceiveTaskPush(admin), true);
  assert.equal(canReceiveTaskPush(member), true);
  assert.equal(canReceiveTaskPush({isAdmin: true, isActive: false}), false);
  assert.equal(canReceiveTaskPush({isAdmin: false, isActive: false}), false);
  assert.equal(canReceiveTaskPush({isAdmin: true, isActive: true, isArchived: true}), false);
  assert.equal(canReceiveTaskPush({isAdmin: false, isActive: true, isArchived: true}), false);
  assert.equal(canReceiveTaskPush({}), false);
});

test('taskAssignedMessage: fixed title, the task title as body, no urgency', () => {
  assert.deepEqual(taskAssignedMessage({id: 't1', title: 'הוספת סבב'}, ''), {
    title: '📋 שובצת למשימה',
    body: 'הוספת סבב',
    tag: 'task-t1',
    path: '/team-tasks?task=t1',
  });
  assert.equal(taskAssignedMessage({id: 't1', title: 'x'}, '/test').path, '/test/team-tasks?task=t1');
});

test('subscriptionDocId: stable per endpoint, different per endpoint', () => {
  const a = subscriptionDocId('https://push.example/a');
  assert.equal(a, subscriptionDocId('https://push.example/a'));
  assert.notEqual(a, subscriptionDocId('https://push.example/b'));
  assert.match(a, /^[0-9a-f]{64}$/);
});

test('parseSubscription: accepts a browser subscription, rejects broken ones', () => {
  const ok = {endpoint: 'https://fcm.googleapis.com/x', keys: {p256dh: 'k', auth: 'a'}, expirationTime: null};
  assert.deepEqual(parseSubscription(ok), {endpoint: ok.endpoint, keys: {p256dh: 'k', auth: 'a'}});
  for (const bad of [
    null,
    {endpoint: 'http://insecure/x', keys: {p256dh: 'k', auth: 'a'}},
    {endpoint: 'https://x/y'},
    {endpoint: 'https://x/y', keys: {p256dh: '', auth: 'a'}},
    {endpoint: 'not a url', keys: {p256dh: 'k', auth: 'a'}},
  ]) {
    assert.throws(() => parseSubscription(bad), (e: unknown) => e instanceof TaskError && e.status === 400);
  }
});

test('send: an edit that adds no owner sends nothing', async () => {
  const store = new FakeStore({a: admin}, [sub('s1', 'a')]);
  const {calls, send} = recorder();
  const result = await sendTaskAssignedPush(store, send, {
    before: task(['a']), after: task(['a']), actorId: 'me', site: 'main', routePrefix: '',
  });
  assert.equal(calls.length, 0);
  assert.equal(result.sent, 0);
});

test('send: every device of each added member, admin or not, never the actor or an archived one', async () => {
  const store = new FakeStore(
    {a: admin, b: member, c: {isAdmin: false, isActive: true, isArchived: true}, me: admin},
    [sub('s1', 'a'), sub('s2', 'a'), sub('s3', 'b'), sub('s4', 'me'), sub('s5', 'c')],
  );
  const {calls, send} = recorder();
  const result = await sendTaskAssignedPush(store, send, {
    before: null, after: task(['a', 'b', 'c', 'me']), actorId: 'me', site: 'main', routePrefix: '',
  });
  assert.deepEqual(calls.map((c) => c.id).sort(), ['s1', 's2', 's3']);
  assert.deepEqual(calls[0].payload, {
    title: '📋 שובצת למשימה', body: 'הוספת סבב נוסף', tag: 'task-t1', path: '/team-tasks?task=t1',
  });
  assert.equal(result.sent, 3);
});

test('send: only the calling site\'s devices', async () => {
  const store = new FakeStore({a: admin}, [sub('main1', 'a', 'main'), sub('prev1', 'a', 'preview')]);
  const main = recorder();
  await sendTaskAssignedPush(store, main.send, {
    before: null, after: task(['a']), actorId: 'me', site: 'main', routePrefix: '',
  });
  assert.deepEqual(main.calls.map((c) => c.id), ['main1']);
  const preview = recorder();
  await sendTaskAssignedPush(store, preview.send, {
    before: null, after: task(['a']), actorId: 'me', site: 'preview', routePrefix: '',
  });
  assert.deepEqual(preview.calls.map((c) => c.id), ['prev1']);
});

test('send: 404 / 410 delete the subscription, other failures keep it', async () => {
  const store = new FakeStore({a: admin}, [sub('gone', 'a'), sub('missing', 'a'), sub('busy', 'a'), sub('ok', 'a')]);
  const {send} = recorder({gone: 410, missing: 404, busy: 500});
  const result = await sendTaskAssignedPush(store, send, {
    before: null, after: task(['a']), actorId: 'me', site: 'main', routePrefix: '',
  });
  assert.deepEqual(store.deleted.sort(), ['gone', 'missing']);
  assert.deepEqual(result, {sent: 1, dropped: 2, failed: 1});
});

test('send: a store failure never throws', async () => {
  const store = new FakeStore({a: admin}, [sub('s1', 'a')], true);
  const {send} = recorder();
  const result = await sendTaskAssignedPush(store, send, {
    before: null, after: task(['a']), actorId: 'me', site: 'main', routePrefix: '',
  });
  assert.equal(result.sent, 0);
});
