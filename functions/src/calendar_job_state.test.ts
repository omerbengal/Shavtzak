import test from 'node:test';
import assert from 'node:assert/strict';
import {
  decideEventCalendarJobClaim,
  decideEventCalendarJobCompletion,
  terminalGuestCleanupStatus,
  transitionGuestCleanupPart,
  type GuestCleanupPart,
} from './calendar_job_state';

const nowMs = 1_000_000;

test('event job claim ignores a clean job', () => {
  assert.deepEqual(
    decideEventCalendarJobClaim({
      dirty: false,
      dueAtMs: null,
      leaseUntilMs: null,
      revision: 4,
      nowMs,
    }),
    {kind: 'none'},
  );
});

test('event job claim defers to dueAt with a ceiling in seconds', () => {
  assert.deepEqual(
    decideEventCalendarJobClaim({
      dirty: true,
      dueAtMs: nowMs + 1_001,
      leaseUntilMs: null,
      revision: 4,
      nowMs,
    }),
    {kind: 'delay', reason: 'dueAt', seconds: 2},
  );
});

test('event job claim defers an active lease for crash recovery', () => {
  assert.deepEqual(
    decideEventCalendarJobClaim({
      dirty: true,
      dueAtMs: nowMs,
      leaseUntilMs: nowMs + 5_000,
      revision: 4,
      nowMs,
    }),
    {kind: 'delay', reason: 'lease', seconds: 5},
  );
});

test('event job claim waits for the latest of dueAt and lease', () => {
  assert.deepEqual(
    decideEventCalendarJobClaim({
      dirty: true,
      dueAtMs: nowMs + 2_000,
      leaseUntilMs: nowMs + 7_000,
      revision: 4,
      nowMs,
    }),
    {kind: 'delay', reason: 'lease', seconds: 7},
  );
});

test('event job claim accepts expired dueAt and lease', () => {
  assert.deepEqual(
    decideEventCalendarJobClaim({
      dirty: true,
      dueAtMs: nowMs,
      leaseUntilMs: nowMs - 1,
      revision: 7,
      nowMs,
    }),
    {kind: 'claim', revision: 7},
  );
});

test('event completion clears dirty only when the claimed revision is current', () => {
  assert.deepEqual(decideEventCalendarJobCompletion(7, 7), {
    needsAnotherPass: false,
    dirty: false,
    status: 'completed',
  });
  assert.deepEqual(decideEventCalendarJobCompletion(7, 8), {
    needsAnotherPass: true,
    dirty: true,
    status: 'pending',
  });
});

const cleanupParts: GuestCleanupPart[] = [
  {calendarEventId: 'part-a', eventId: 'event-1'},
  {calendarEventId: 'part-b', eventId: 'event-2'},
];

test('cleanup changed outcome consumes one part and increments changed', () => {
  assert.deepEqual(
    transitionGuestCleanupPart(cleanupParts, 'part-a', 'changed', 0),
    {
      pendingParts: [{calendarEventId: 'part-b', eventId: 'event-2'}],
      status: 'queued',
      processedIncrement: 1,
      changedIncrement: 1,
      skippedIncrement: 0,
      failedIncrement: 0,
      isTerminal: false,
    },
  );
});

test('cleanup skipped outcome completes a final successful job', () => {
  assert.deepEqual(
    transitionGuestCleanupPart(cleanupParts.slice(0, 1), 'part-a', 'skipped', 0),
    {
      pendingParts: [],
      status: 'completed',
      processedIncrement: 1,
      changedIncrement: 0,
      skippedIncrement: 1,
      failedIncrement: 0,
      isTerminal: true,
    },
  );
});

test('cleanup success remains failed at terminal state after an earlier failure', () => {
  const transition = transitionGuestCleanupPart(
    cleanupParts.slice(1),
    'part-b',
    'changed',
    1,
  );
  assert.equal(transition.status, 'failed');
  assert.equal(transition.isTerminal, true);
  assert.equal(transition.failedIncrement, 0);
});

test('cleanup failure consumes the part and records one processed failure', () => {
  assert.deepEqual(
    transitionGuestCleanupPart(cleanupParts, 'part-a', 'failed', 0),
    {
      pendingParts: [{calendarEventId: 'part-b', eventId: 'event-2'}],
      status: 'queued',
      processedIncrement: 1,
      changedIncrement: 0,
      skippedIncrement: 0,
      failedIncrement: 1,
      isTerminal: false,
    },
  );
  assert.equal(
    transitionGuestCleanupPart(cleanupParts.slice(0, 1), 'part-a', 'failed', 0).status,
    'failed',
  );
});

test('cleanup quota outcome keeps the part and counters unchanged for retry', () => {
  assert.deepEqual(
    transitionGuestCleanupPart(cleanupParts, 'part-a', 'quota', 0),
    {
      pendingParts: cleanupParts,
      status: 'backoff',
      processedIncrement: 0,
      changedIncrement: 0,
      skippedIncrement: 0,
      failedIncrement: 0,
      isTerminal: false,
    },
  );
});

test('cleanup rejects a stale part instead of double-counting it', () => {
  assert.throws(
    () => transitionGuestCleanupPart(cleanupParts, 'not-pending', 'changed', 0),
    /Cleanup part not pending/,
  );
});

test('empty cleanup terminal status reflects accumulated failures', () => {
  assert.equal(terminalGuestCleanupStatus(0), 'completed');
  assert.equal(terminalGuestCleanupStatus(2), 'failed');
});
