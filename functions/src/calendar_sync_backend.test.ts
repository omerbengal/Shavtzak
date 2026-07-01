import test from 'node:test';
import assert from 'node:assert/strict';
import {
  isEligiblePermanentMember,
  shouldInviteAllPermanentForEvent,
  planAppEventReconciliation,
  listInScopeAppEventIds,
  type AppEventPartSummary,
} from './calendar_sync_backend';

type Mutable = Record<string, unknown>;

function fakeEventsFirestore(events: Array<{id: string; data: Mutable}>) {
  return {
    collection: (_name: string) => ({
      get: async () => ({
        docs: events.map((event) => ({
          id: event.id,
          data: () => event.data,
        })),
      }),
    }),
  };
}

test('listInScopeAppEventIds: keeps active future events, drops past and deactivated', async () => {
  const deps = {
    firestore: fakeEventsFirestore([
      {id: 'future', data: {endDate: '2999-12-31', isDeactivated: false}},
      {id: 'past', data: {endDate: '2000-01-01', isDeactivated: false}},
      {id: 'future-off', data: {endDate: '2999-12-31', isDeactivated: true}},
    ]),
    collections: {events: 'events'},
  } as unknown as Parameters<typeof listInScopeAppEventIds>[0];

  const ids = await listInScopeAppEventIds(deps);
  assert.deepEqual(ids, ['future']);
});

function buildPart(
  id: string,
  eventType: string | null,
  status: string | null = 'confirmed',
): AppEventPartSummary {
  return {id, eventType, status};
}

function buildMember(overrides: Mutable = {}): Mutable {
  return {
    isActive: true,
    isArchived: false,
    isPermanent: true,
    email: 'a@example.com',
    ...overrides,
  };
}

test('eligible: permanent active non-archived with email', () => {
  assert.equal(isEligiblePermanentMember(buildMember()), true);
});

test('ineligible: non-permanent', () => {
  assert.equal(
    isEligiblePermanentMember(buildMember({isPermanent: false})),
    false,
  );
});

test('ineligible: missing isPermanent', () => {
  const m = buildMember();
  delete m.isPermanent;
  assert.equal(isEligiblePermanentMember(m), false);
});

test('ineligible: archived', () => {
  assert.equal(
    isEligiblePermanentMember(buildMember({isArchived: true})),
    false,
  );
});

test('ineligible: inactive', () => {
  assert.equal(
    isEligiblePermanentMember(buildMember({isActive: false})),
    false,
  );
});

test('missing isArchived derives from !isActive (inactive => archived => ineligible)', () => {
  const m = buildMember({isActive: false});
  delete m.isArchived;
  assert.equal(isEligiblePermanentMember(m), false);
});

test('missing isActive defaults to active => eligible', () => {
  const m = buildMember();
  delete m.isActive;
  delete m.isArchived;
  assert.equal(isEligiblePermanentMember(m), true);
});

test('ineligible: blank or missing email', () => {
  assert.equal(isEligiblePermanentMember(buildMember({email: '   '})), false);
  const m = buildMember();
  delete m.email;
  assert.equal(isEligiblePermanentMember(m), false);
});

test('ineligible: null/undefined data', () => {
  assert.equal(isEligiblePermanentMember(null), false);
  assert.equal(isEligiblePermanentMember(undefined), false);
});

test('shouldInvite: flag on, permanent-only, zero assignments => true', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: true, relevantForExtendedTeam: false},
      0,
    ),
    true,
  );
});

test('shouldInvite: missing relevantForExtendedTeam treated as permanent-only', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: true},
      0,
    ),
    true,
  );
});

test('shouldInvite: any assignment => false', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: true, relevantForExtendedTeam: false},
      1,
    ),
    false,
  );
});

test('shouldInvite: flag off => false', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: false, relevantForExtendedTeam: false},
      0,
    ),
    false,
  );
});

test('shouldInvite: extended-team event => false even if flag on', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: true, relevantForExtendedTeam: true},
      0,
    ),
    false,
  );
});

test('eligible: missing isActive (defaults active) with isArchived explicitly false', () => {
  const m = buildMember();
  delete m.isActive;
  // isArchived is still present and false
  assert.equal(isEligiblePermanentMember(m), true);
});

test('shouldInvite: missing inviteAllPermanentWhenUnassigned => false (old events predate the field)', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent({relevantForExtendedTeam: false}, 0),
    false,
  );
});

// --- planAppEventReconciliation: convergent de-duplication of app-event calendar parts ---

test('reconcile plan: reuses an existing main event when stored state is empty (no duplicate create)', () => {
  const plan = planAppEventReconciliation({
    discovered: [buildPart('main-a', 'main')],
    currentStateAssemblyId: '',
    currentStateMainId: '',
    shouldHaveAssemblyPart: false,
  });
  assert.equal(plan.createMain, false);
  assert.equal(plan.keepMainId, 'main-a');
  assert.deepEqual(plan.deleteMainIds, []);
});

test('reconcile plan: keeps the stored main and deletes a duplicate orphan', () => {
  const plan = planAppEventReconciliation({
    discovered: [buildPart('main-stored', 'main'), buildPart('main-orphan', 'main')],
    currentStateAssemblyId: '',
    currentStateMainId: 'main-stored',
    shouldHaveAssemblyPart: false,
  });
  assert.equal(plan.createMain, false);
  assert.equal(plan.keepMainId, 'main-stored');
  assert.deepEqual(plan.deleteMainIds, ['main-orphan']);
});

test('reconcile plan: creates a main event when none exist', () => {
  const plan = planAppEventReconciliation({
    discovered: [],
    currentStateAssemblyId: '',
    currentStateMainId: '',
    shouldHaveAssemblyPart: false,
  });
  assert.equal(plan.createMain, true);
  assert.equal(plan.keepMainId, null);
  assert.deepEqual(plan.deleteMainIds, []);
});

test('reconcile plan: deletes assembly events when the event should not have an assembly part', () => {
  const plan = planAppEventReconciliation({
    discovered: [buildPart('main-a', 'main'), buildPart('asm-x', 'assembly')],
    currentStateAssemblyId: 'asm-x',
    currentStateMainId: 'main-a',
    shouldHaveAssemblyPart: false,
  });
  assert.equal(plan.createAssembly, false);
  assert.equal(plan.keepAssemblyId, null);
  assert.deepEqual(plan.deleteAssemblyIds, ['asm-x']);
});

test('reconcile plan: ignores cancelled events and creates a replacement', () => {
  const plan = planAppEventReconciliation({
    discovered: [buildPart('main-dead', 'main', 'cancelled')],
    currentStateAssemblyId: '',
    currentStateMainId: 'main-dead',
    shouldHaveAssemblyPart: false,
  });
  assert.equal(plan.createMain, true);
  assert.equal(plan.keepMainId, null);
  assert.deepEqual(plan.deleteMainIds, []);
});

test('reconcile plan: de-duplicates the reported 4-pair case down to one canonical pair', () => {
  const plan = planAppEventReconciliation({
    discovered: [
      buildPart('main-1', 'main'),
      buildPart('main-2', 'main'),
      buildPart('main-3', 'main'),
      buildPart('main-4', 'main'),
      buildPart('asm-1', 'assembly'),
      buildPart('asm-2', 'assembly'),
      buildPart('asm-3', 'assembly'),
      buildPart('asm-4', 'assembly'),
    ],
    currentStateAssemblyId: 'asm-4',
    currentStateMainId: 'main-4',
    shouldHaveAssemblyPart: true,
  });
  assert.equal(plan.createMain, false);
  assert.equal(plan.createAssembly, false);
  assert.equal(plan.keepMainId, 'main-4');
  assert.equal(plan.keepAssemblyId, 'asm-4');
  assert.deepEqual(plan.deleteMainIds.sort(), ['main-1', 'main-2', 'main-3']);
  assert.deepEqual(plan.deleteAssemblyIds.sort(), ['asm-1', 'asm-2', 'asm-3']);
});

test('reconcile plan: treats main and allDay as the same (main) slot', () => {
  const plan = planAppEventReconciliation({
    discovered: [buildPart('day-1', 'allDay'), buildPart('day-2', 'allDay')],
    currentStateAssemblyId: '',
    currentStateMainId: 'day-2',
    shouldHaveAssemblyPart: false,
  });
  assert.equal(plan.createMain, false);
  assert.equal(plan.keepMainId, 'day-2');
  assert.deepEqual(plan.deleteMainIds, ['day-1']);
});
