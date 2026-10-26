import test from 'node:test';
import assert from 'node:assert/strict';
import {shouldCheckAvailability} from './index';

// assignment.update must never re-refuse an assignment whose member and event
// did not change: the conflict rule may have tightened since it was made, and
// an admin editing only its notes or label must not be blocked by that.

test('shouldCheckAvailability: bypass requested → false', () =>
  assert.equal(
    shouldCheckAvailability({
      bypassRequested: true,
      stored: null,
      next: {teamMemberId: 'm1', eventId: 'e1'},
    }),
    false,
  ));

test('shouldCheckAvailability: new assignment → true', () =>
  assert.equal(
    shouldCheckAvailability({
      bypassRequested: false,
      stored: null,
      next: {teamMemberId: 'm1', eventId: 'e1'},
    }),
    true,
  ));

test('shouldCheckAvailability: same member and event as stored → false', () =>
  assert.equal(
    shouldCheckAvailability({
      bypassRequested: false,
      stored: {teamMemberId: 'm1', eventId: 'e1'},
      next: {teamMemberId: 'm1', eventId: 'e1'},
    }),
    false,
  ));

test('shouldCheckAvailability: member replaced → true', () =>
  assert.equal(
    shouldCheckAvailability({
      bypassRequested: false,
      stored: {teamMemberId: 'm1', eventId: 'e1'},
      next: {teamMemberId: 'm2', eventId: 'e1'},
    }),
    true,
  ));

test('shouldCheckAvailability: moved to another event → true', () =>
  assert.equal(
    shouldCheckAvailability({
      bypassRequested: false,
      stored: {teamMemberId: 'm1', eventId: 'e1'},
      next: {teamMemberId: 'm1', eventId: 'e2'},
    }),
    true,
  ));
