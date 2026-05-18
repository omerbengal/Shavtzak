import test from 'node:test';
import assert from 'node:assert/strict';
import {
  isEligiblePermanentMember,
  shouldInviteAllPermanentForEvent,
} from './calendar_sync_backend';

type Mutable = Record<string, unknown>;

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
