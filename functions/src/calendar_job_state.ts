export type EventCalendarJobClaimInput = {
  dirty: boolean;
  dueAtMs: number | null;
  leaseUntilMs: number | null;
  revision: number;
  nowMs: number;
};

export type EventCalendarJobClaimDecision =
  | {kind: 'none'}
  | {kind: 'delay'; reason: 'dueAt' | 'lease'; seconds: number}
  | {kind: 'claim'; revision: number};

function delaySeconds(untilMs: number, nowMs: number): number {
  return Math.max(1, Math.ceil((untilMs - nowMs) / 1000));
}

/**
 * Decides whether a task delivery should claim, defer, or ignore an event job.
 * An active lease is deferred until its expiry so a crashed worker is recovered
 * without waiting for the periodic sweeper.
 */
export function decideEventCalendarJobClaim(
  input: EventCalendarJobClaimInput,
): EventCalendarJobClaimDecision {
  if (!input.dirty) {
    return {kind: 'none'};
  }
  const dueAtMs = input.dueAtMs != null && input.dueAtMs > input.nowMs
    ? input.dueAtMs
    : null;
  const leaseUntilMs = input.leaseUntilMs != null && input.leaseUntilMs > input.nowMs
    ? input.leaseUntilMs
    : null;
  if (dueAtMs != null || leaseUntilMs != null) {
    const leaseIsLatest = leaseUntilMs != null &&
      (dueAtMs == null || leaseUntilMs > dueAtMs);
    const blockedUntilMs = leaseIsLatest ? leaseUntilMs! : dueAtMs!;
    return {
      kind: 'delay',
      reason: leaseIsLatest ? 'lease' : 'dueAt',
      seconds: delaySeconds(blockedUntilMs, input.nowMs),
    };
  }
  return {kind: 'claim', revision: input.revision};
}

export type EventCalendarJobCompletionDecision = {
  needsAnotherPass: boolean;
  dirty: boolean;
  status: 'pending' | 'completed';
};

/** A successful worker may clear dirty only for the revision it claimed. */
export function decideEventCalendarJobCompletion(
  claimedRevision: number,
  latestRevision: number,
): EventCalendarJobCompletionDecision {
  const needsAnotherPass = latestRevision !== claimedRevision;
  return {
    needsAnotherPass,
    dirty: needsAnotherPass,
    status: needsAnotherPass ? 'pending' : 'completed',
  };
}

export type GuestCleanupPart = {
  calendarEventId: string;
  eventId: string;
};

export type GuestCleanupPartOutcome = 'changed' | 'skipped' | 'failed' | 'quota';

export type GuestCleanupJobStatus =
  | 'queued'
  | 'backoff'
  | 'completed'
  | 'failed';

export type GuestCleanupPartTransition = {
  pendingParts: GuestCleanupPart[];
  status: GuestCleanupJobStatus;
  processedIncrement: 0 | 1;
  changedIncrement: 0 | 1;
  skippedIncrement: 0 | 1;
  failedIncrement: 0 | 1;
  isTerminal: boolean;
};

/**
 * Advances one cleanup part. Quota failures retain the part for retry; every
 * other outcome consumes it exactly once and derives the next job status.
 */
export function transitionGuestCleanupPart(
  pendingParts: readonly GuestCleanupPart[],
  calendarEventId: string,
  outcome: GuestCleanupPartOutcome,
  failedPartCount: number,
): GuestCleanupPartTransition {
  if (!pendingParts.some((part) => part.calendarEventId === calendarEventId)) {
    throw new Error(`Cleanup part not pending: ${calendarEventId}`);
  }

  if (outcome === 'quota') {
    return {
      pendingParts: [...pendingParts],
      status: 'backoff',
      processedIncrement: 0,
      changedIncrement: 0,
      skippedIncrement: 0,
      failedIncrement: 0,
      isTerminal: false,
    };
  }

  const remaining = pendingParts.filter(
    (part) => part.calendarEventId !== calendarEventId,
  );
  const isTerminal = remaining.length === 0;
  const finalFailedCount = failedPartCount + (outcome === 'failed' ? 1 : 0);
  const status: GuestCleanupJobStatus = isTerminal
    ? (finalFailedCount > 0 ? 'failed' : 'completed')
    : 'queued';

  return {
    pendingParts: remaining,
    status,
    processedIncrement: 1,
    changedIncrement: outcome === 'changed' ? 1 : 0,
    skippedIncrement: outcome === 'skipped' ? 1 : 0,
    failedIncrement: outcome === 'failed' ? 1 : 0,
    isTerminal,
  };
}

export function terminalGuestCleanupStatus(
  failedPartCount: number,
): 'completed' | 'failed' {
  return failedPartCount > 0 ? 'failed' : 'completed';
}
