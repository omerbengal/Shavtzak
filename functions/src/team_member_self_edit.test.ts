import test from 'node:test';
import assert from 'node:assert/strict';
import {__testApplySelfEditableFields as applySelfEditableFields} from './index';

// The existing document for a non-permanent, non-admin member. `availableEventIds`
// starts empty; privileged/identity fields must survive a self-edit unchanged.
function buildExisting(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'm1',
    name: 'עומר בנגל 2',
    isAdmin: false,
    isPermanent: false,
    roleCapabilities: {medic: true},
    availableEventIds: [],
    phoneNumber: null,
    email: null,
    ...overrides,
  };
}

test('applySelfEditableFields: persists availableEventIds from the incoming edit (the bug)', () => {
  const existing = buildExisting();
  const next = {
    ...existing,
    availableEventIds: ['evt-a', 'evt-b'],
    updatedAt: 'ts',
  };

  const result = applySelfEditableFields(existing, next);

  // Regression: previously this branch dropped availableEventIds, keeping the
  // empty existing value, so a non-admin member could never mark availability.
  assert.deepEqual(result['availableEventIds'], ['evt-a', 'evt-b']);
});

test('applySelfEditableFields: defaults availableEventIds to [] when the edit omits it', () => {
  const existing = buildExisting({availableEventIds: ['old']});
  const next: Record<string, unknown> = {updatedAt: 'ts'};

  const result = applySelfEditableFields(existing, next);

  assert.deepEqual(result['availableEventIds'], []);
});

test('applySelfEditableFields: self-editable contact fields are taken from the edit', () => {
  const existing = buildExisting();
  const next = {
    ...existing,
    phoneNumber: '050-1234567',
    email: 'a@b.com',
    availableEventIds: [],
    updatedAt: 'ts',
  };

  const result = applySelfEditableFields(existing, next);

  assert.equal(result['phoneNumber'], '050-1234567');
  assert.equal(result['email'], 'a@b.com');
});

test('applySelfEditableFields: privileged/identity fields cannot be escalated via self-edit', () => {
  const existing = buildExisting();
  const next = {
    // A malicious/self client tries to grant itself admin, new roles, and a new name.
    id: 'm1',
    name: 'HACKED',
    isAdmin: true,
    isPermanent: true,
    roleCapabilities: {medic: true, eventCommander: true},
    availableEventIds: ['evt-a'],
    updatedAt: 'ts',
  };

  const result = applySelfEditableFields(existing, next);

  // Privileged + identity fields must come from `existing`, not the edit...
  assert.equal(result['isAdmin'], false);
  assert.equal(result['isPermanent'], false);
  assert.deepEqual(result['roleCapabilities'], {medic: true});
  assert.equal(result['name'], 'עומר בנגל 2');
  // ...while the member's own availability edit still lands.
  assert.deepEqual(result['availableEventIds'], ['evt-a']);
});
