import cors from 'cors';
import express, {Request, Response} from 'express';
import {randomBytes, randomUUID, scryptSync, timingSafeEqual, createHash} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFunctions} from 'firebase-admin/functions';
import {
  FieldValue,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
  WriteBatch,
  getFirestore,
} from 'firebase-admin/firestore';
import {onRequest} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {onTaskDispatched} from 'firebase-functions/v2/tasks';
import {
  canExecuteDriveAction,
  DriveExportValidationError,
  executeDriveAction,
  exportProductionDataToSheets,
} from './drive_export';
import {
  buildDeterministicAppEventCalendarId,
  createCalendarAuthUrl,
  disconnectCalendarAuth,
  exchangeCalendarAuthCode,
  executeCalendarAction,
  getCalendarConfigForClient,
  getCalendarStatusForClient,
  GoogleApiError,
} from './calendar_integration';
import {
  listInScopeAppEventIds,
  syncAppEventCalendars,
  syncConstraintCalendars,
} from './calendar_sync_backend';
import {
  decideEventCalendarJobClaim,
  decideEventCalendarJobCompletion,
  type GuestCleanupPart,
} from './calendar_job_state';
import {classifyCalendarFailure} from './calendar_error_policy';
import type {
  ConstraintSyncReport,
} from './calendar_sync_backend';
import {normalizeParticipantGroups} from './participant_groups';

initializeApp();

const db = getFirestore();
const auth = getAuth();
const app = express();

app.use(cors({origin: true}));
app.use((request: Request, _response: Response, next) => {
  const routeOverride = request.query['route'];
  if (request.path === '/' && typeof routeOverride === 'string' && routeOverride.trim().length > 0) {
    request.url = routeOverride.startsWith('/') ? routeOverride : `/${routeOverride}`;
  }
  next();
});
app.use(express.json({limit: '2mb'}));

type EnvironmentMode = 'production' | 'test';

type ActorContext = {
  memberId: string;
  uniqueKey: string;
  isAdmin: boolean;
  sessionId: string;
  expiresAt: Timestamp;
  member: Record<string, unknown>;
};

type Collections = {
  teamMembers: string;
  events: string;
  assignments: string;
  assignmentLabels: string;
  checklistItems: string;
  presets: string;
  calendarSync: string;
  eventCalendarSync: string;
  eventCalendarJobs: string;
  calendarMaintenanceJobs: string;
  logs: string;
  privateCredentials: string;
  privateSessions: string;
  privateGoogleCalendarAuth: string;
};

const DEFAULT_TEAM_MEMBER_PASSCODE = '071023';
const DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH = DEFAULT_TEAM_MEMBER_PASSCODE.length;

const CALENDAR_TEST_MODE_PREFIX = 'שבצק טסטינג: ';
const CALENDAR_APP_EVENT_COLOR_ID = '7';
const CALENDAR_TEST_MODE_COLOR_ID = '5';
const CALENDAR_UNAVAILABILITY_COLOR_ID = '8';

// One delivery for the durable, backend-owned Calendar job queues.
type CalendarSyncTaskPayload = {
  kind?: 'eventSync' | 'guestCleanup' | 'authResume';
  eventId?: string;
  jobId?: string;
  environment: EnvironmentMode;
  actor: {memberId: string; isAdmin: boolean};
  // Kept optional so already-enqueued legacy tasks remain decodable after the
  // no-guests deployment. App-event reconciliation ignores this value.
  delta?: unknown;
  // Decoded for compatibility with tasks created by an older deployment.
  quotaRetryCount?: number;
  scheduleToken?: string;
  authGeneration?: string;
};

const CALENDAR_SYNC_TASK_QUEUE = 'calendarSyncTask';
const EVENT_SYNC_DEBOUNCE_SECONDS = 5;
const CALENDAR_JOB_LEASE_SECONDS = 5 * 60;
const CALENDAR_TASK_RESERVATION_GRACE_SECONDS = 15 * 60;
const CALENDAR_JOB_SWEEP_LIMIT = 100;
const OMER_CLEANUP_EMAIL = 'omerbengal7@gmail.com';
const GLOBAL_CALENDAR_RUNTIME_COLLECTION = 'private_google_calendar_runtime';
const CALENDAR_QUOTA_CIRCUIT_DOC_ID = '_google_calendar_quota_circuit';
const GUEST_CLEANUP_LOCK_DOC_ID = '_app_event_guest_cleanup_lock';
const EVENT_DELETION_PENDING_FIELD = '_calendarDeletionPending';
const CALENDAR_AUTH_DOC_ID = 'googleCalendar';
const AUTH_RESUME_WINDOW_SECONDS = 20 * 60;

// When Google returns a quota / usage-limit 403, defer the event's retry by
// this long (instead of Cloud Tasks' 5–60s fast-retry) so it lands after the
// per-account usage window has reset.
const QUOTA_BACKOFF_SECONDS = 30 * 60; // 30 minutes
// Calendar sync runs on a Cloud Tasks queue rather than fire-and-forget: on
// Cloud Run, un-awaited background work has its CPU throttled the instant the
// HTTP response is sent, which stretched a ~3s sync into minutes. As a task it
// runs at full CPU. Firebase provisions + secures the queue on deploy (only
// Cloud Tasks + admins may enqueue).
//
// The calendar organizer is a consumer Gmail account, which has a low,
// undocumented "Calendar usage limit" on writes. A burst of event patches can
// trip `403 Calendar usage limits exceeded`. Two guards keep sync reliable
// paying for Workspace, trading speed for reliability:
//   1. Throttle hard — one dispatch at a time, one every 2s — so a burst never
//      exceeds the per-account write cap in the first place. Slow is fine here.
//   2. One account-wide circuit breaker shared by production, test, event, and
//      constraint writers: after a quota failure, defer every Calendar write
//      until the usage window has had time to reset.
//      The fast-retry-into-exhausted-quota loop is what produced the 2026-07
//      storm (~15 events each retried 20–45×).
// `retryConfig.maxAttempts` still caps genuinely transient (non-quota) failures.
export const calendarSyncTask = onTaskDispatched<CalendarSyncTaskPayload>(
  {
    region: 'us-central1',
    timeoutSeconds: 540,
    memory: '512MiB',
    retryConfig: {maxAttempts: 5, minBackoffSeconds: 5, maxBackoffSeconds: 60},
    rateLimits: {maxConcurrentDispatches: 1, maxDispatchesPerSecond: 0.5},
  },
  async (request) => {
    if (request.data.kind === 'authResume') {
      await resumeRecentlyAuthorizedCalendarJobs(
        request.data.environment,
        request.data.authGeneration,
      );
      return;
    }
    if (request.data.kind === 'guestCleanup') {
      await drainGuestCleanupJob(request.data);
      return;
    }
    await drainEventCalendarJob(request.data);
  },
);

function getEnvironmentMode(value: unknown): EnvironmentMode {
  return value === 'test' ? 'test' : 'production';
}

function getCollections(environment: EnvironmentMode): Collections {
  const prefix = environment === 'test' ? 'test_' : '';
  return {
    teamMembers: `${prefix}teamMembers`,
    events: `${prefix}events`,
    assignments: `${prefix}assignments`,
    assignmentLabels: `${prefix}assignmentLabels`,
    checklistItems: `${prefix}checklist_items`,
    presets: `${prefix}checklist_presets`,
    calendarSync: `${prefix}calendar_sync`,
    eventCalendarSync: `${prefix}event_calendar_sync`,
    eventCalendarJobs: `${prefix}event_calendar_jobs`,
    calendarMaintenanceJobs: `${prefix}calendar_maintenance_jobs`,
    logs: `${prefix}logs`,
    privateCredentials: `${prefix}private_member_credentials`,
    privateSessions: `${prefix}private_sessions`,
    privateGoogleCalendarAuth: `${prefix}private_google_calendar_auth`,
  };
}

type CalendarJobActor = {memberId: string; isAdmin: boolean};

function timestampMillis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

function calendarQuotaCircuitRef() {
  return db
    .collection(GLOBAL_CALENDAR_RUNTIME_COLLECTION)
    .doc(CALENDAR_QUOTA_CIRCUIT_DOC_ID);
}

function guestCleanupLockRef(collections: Collections) {
  return db
    .collection(collections.calendarMaintenanceJobs)
    .doc(GUEST_CLEANUP_LOCK_DOC_ID);
}

async function openCalendarQuotaCircuit(
  error: unknown,
): Promise<number> {
  const blockedUntilMs = Date.now() + QUOTA_BACKOFF_SECONDS * 1000;
  await calendarQuotaCircuitRef().set({
    type: 'googleCalendarQuotaCircuit',
    blockedUntil: Timestamp.fromMillis(blockedUntilMs),
    lastError: String(error),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return blockedUntilMs;
}

async function activeCalendarQuotaBlockedUntil(): Promise<number | null> {
  const snapshot = await calendarQuotaCircuitRef().get();
  const blockedUntilMs = timestampMillis(snapshot.data()?.['blockedUntil']);
  return blockedUntilMs != null && blockedUntilMs > Date.now()
    ? blockedUntilMs
    : null;
}

async function executeCalendarActionWithQuotaCircuit(
  actor: CalendarJobActor,
  environment: EnvironmentMode,
  action: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const blockedUntilMs = await activeCalendarQuotaBlockedUntil();
  if (blockedUntilMs != null) {
    throw new GoogleApiError(
      429,
      `Google Calendar usage limit circuit is open until ${new Date(blockedUntilMs).toISOString()}`,
    );
  }

  try {
    return await executeCalendarAction(
      db,
      actor,
      environment,
      action,
      payload,
    );
  } catch (error: unknown) {
    if (classifyCalendarFailure(error).kind === 'quota') {
      await openCalendarQuotaCircuit(error);
    }
    throw error;
  }
}

function markEventCalendarJob(
  batch: WriteBatch,
  collections: Collections,
  eventId: string,
  actor: CalendarJobActor,
): void {
  batch.set(
    db.collection(collections.eventCalendarJobs).doc(eventId),
    {
      eventId,
      revision: FieldValue.increment(1),
      dirty: true,
      status: 'pending',
      dueAt: Timestamp.fromMillis(Date.now() + EVENT_SYNC_DEBOUNCE_SECONDS * 1000),
      requestedByMemberId: actor.memberId,
      requestedByIsAdmin: actor.isAdmin,
      updatedAt: FieldValue.serverTimestamp(),
      lastError: FieldValue.delete(),
    },
    {merge: true},
  );
}

async function enqueueCalendarTask(
  payload: CalendarSyncTaskPayload,
  scheduleDelaySeconds = 0,
  taskId?: string,
): Promise<void> {
  const queue = getFunctions().taskQueue<CalendarSyncTaskPayload>(CALENDAR_SYNC_TASK_QUEUE);
  await queue.enqueue(
    payload,
    {
      ...(scheduleDelaySeconds > 0 ? {scheduleDelaySeconds} : {}),
      ...(taskId != null ? {id: taskId} : {}),
    },
  );
}

async function reserveCalendarTask(
  jobRef: FirebaseFirestore.DocumentReference,
  terminalStatuses: Set<string>,
  scheduledForMs: number,
): Promise<string | null> {
  let token: string | null = null;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(jobRef);
    if (!snapshot.exists) return;
    const data = snapshot.data() ?? {};
    if (terminalStatuses.has(String(data['status'] ?? ''))) return;
    const existingToken = typeof data['taskScheduledToken'] === 'string'
      ? data['taskScheduledToken']
      : null;
    const existingScheduledForMs = timestampMillis(data['taskScheduledFor']);
    const existingScheduledUntilMs = timestampMillis(data['taskScheduledUntil']);
    if (
      existingToken != null &&
      existingScheduledForMs != null &&
      existingScheduledUntilMs != null &&
      existingScheduledUntilMs > Date.now() &&
      existingScheduledForMs <= scheduledForMs
    ) {
      return;
    }
    token = randomUUID();
    transaction.update(jobRef, {
      taskScheduledToken: token,
      taskScheduledFor: Timestamp.fromMillis(scheduledForMs),
      taskScheduledUntil: Timestamp.fromMillis(
        scheduledForMs + CALENDAR_TASK_RESERVATION_GRACE_SECONDS * 1000,
      ),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return token;
}

async function clearCalendarTaskReservation(
  jobRef: FirebaseFirestore.DocumentReference,
  token: string | undefined,
): Promise<void> {
  if (token == null || token.length === 0) return;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(jobRef);
    if (snapshot.data()?.['taskScheduledToken'] !== token) return;
    transaction.update(jobRef, {
      taskScheduledToken: FieldValue.delete(),
      taskScheduledFor: FieldValue.delete(),
      taskScheduledUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function consumeCalendarTaskReservation(
  jobRef: FirebaseFirestore.DocumentReference,
  token: string | undefined,
): Promise<boolean> {
  let consumed = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(jobRef);
    if (!snapshot.exists) return;
    const currentToken = snapshot.data()?.['taskScheduledToken'];

    // A task whose reservation was superseded must not drain the job. Tasks
    // from an older deployment have no token and remain valid only while no
    // newer reservation owns the job.
    if (token == null || token.length === 0) {
      if (typeof currentToken === 'string' && currentToken.length > 0) return;
      consumed = true;
      return;
    }
    if (currentToken !== token) return;

    transaction.update(jobRef, {
      taskScheduledToken: FieldValue.delete(),
      taskScheduledFor: FieldValue.delete(),
      taskScheduledUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    consumed = true;
  });
  return consumed;
}

async function enqueueEventCalendarJob(
  environment: EnvironmentMode,
  eventId: string,
  actor: CalendarJobActor,
  scheduleDelaySeconds = EVENT_SYNC_DEBOUNCE_SECONDS,
): Promise<void> {
  const collections = getCollections(environment);
  const jobRef = db.collection(collections.eventCalendarJobs).doc(eventId);
  const scheduledForMs = Date.now() + scheduleDelaySeconds * 1000;
  const scheduleToken = await reserveCalendarTask(
    jobRef,
    new Set(['completed', 'failed', 'auth-blocked']),
    scheduledForMs,
  );
  if (scheduleToken == null) return;
  try {
    await enqueueCalendarTask(
      {kind: 'eventSync', environment, eventId, actor, scheduleToken},
      scheduleDelaySeconds,
      createHash('sha256')
        .update(`event:${environment}:${eventId}:${scheduleToken}`)
        .digest('hex'),
    );
  } catch (error: unknown) {
    await clearCalendarTaskReservation(jobRef, scheduleToken);
    // The Firestore job is the durable source of truth. The scheduled sweeper
    // will enqueue it again if this best-effort nudge fails.
    console.error(
      `[calendar-sync-error] failed to enqueue event job eventId=${eventId}:`,
      error,
    );
  }
}

async function markAndEnqueueEventCalendarJobs(
  environment: EnvironmentMode,
  eventIds: Iterable<string>,
  actor: CalendarJobActor,
): Promise<number> {
  const collections = getCollections(environment);
  const ids = Array.from(new Set(Array.from(eventIds).filter((id) => id.length > 0)));
  if (ids.length === 0) return 0;

  // Manual repair requests have no accompanying domain mutation, so create
  // their durable revisions in a bounded batch here.
  for (let start = 0; start < ids.length; start += 400) {
    const batch = db.batch();
    for (const eventId of ids.slice(start, start + 400)) {
      markEventCalendarJob(batch, collections, eventId, actor);
    }
    await batch.commit();
  }
  await Promise.all(ids.map((eventId) =>
    enqueueEventCalendarJob(environment, eventId, actor),
  ));
  return ids.length;
}

async function deleteEventRelatedDocuments(
  collections: Collections,
  eventId: string,
): Promise<void> {
  while (true) {
    const [assignments, checklistItems] = await Promise.all([
      db.collection(collections.assignments)
        .where('eventId', '==', eventId)
        .limit(200)
        .get(),
      db.collection(collections.checklistItems)
        .where('eventId', '==', eventId)
        .limit(200)
        .get(),
    ]);
    const documents = [...assignments.docs, ...checklistItems.docs];
    if (documents.length === 0) return;

    const batch = db.batch();
    for (const document of documents) batch.delete(document.ref);
    await batch.commit();
  }
}

async function finalizePendingEventDeletion(
  collections: Collections,
  eventId: string,
): Promise<boolean> {
  const eventRef = db.collection(collections.events).doc(eventId);
  const eventSnapshot = await eventRef.get();
  if (!eventSnapshot.exists) {
    // Current deletions remove relations before the fenced event document. Do
    // not touch relations after the document is gone: the same explicit ID may
    // already have been recreated by a later import.
    return true;
  }
  if (
    eventSnapshot.data()?.[EVENT_DELETION_PENDING_FIELD] !== true
  ) {
    return false;
  }

  await deleteEventRelatedDocuments(collections, eventId);

  let finalized = !eventSnapshot.exists;
  await db.runTransaction(async (transaction) => {
    const latest = await transaction.get(eventRef);
    if (!latest.exists) {
      finalized = true;
      return;
    }
    if (latest.data()?.[EVENT_DELETION_PENDING_FIELD] !== true) return;
    transaction.delete(eventRef);
    finalized = true;
  });
  return finalized;
}

async function requireWritableEventInTransaction(
  transaction: FirebaseFirestore.Transaction,
  collections: Collections,
  eventId: string,
): Promise<void> {
  const event = await transaction.get(
    db.collection(collections.events).doc(eventId),
  );
  if (!event.exists) throw new HttpError(400, 'אירוע לא נמצא');
  if (event.data()?.[EVENT_DELETION_PENDING_FIELD] === true) {
    throw new HttpError(409, 'האירוע נמצא בתהליך מחיקה');
  }
}

async function drainEventCalendarJob(payload: CalendarSyncTaskPayload): Promise<void> {
  const eventId = payload.eventId;
  if (eventId == null || eventId.length === 0) return;
  const collections = getCollections(payload.environment);
  const jobRef = db.collection(collections.eventCalendarJobs).doc(eventId);
  if (!await consumeCalendarTaskReservation(jobRef, payload.scheduleToken)) return;
  const nowMs = Date.now();

  const claim = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(jobRef);
    if (!snapshot.exists) return {kind: 'none'} as const;
    const data = snapshot.data() ?? {};
    if (data['status'] === 'auth-blocked') return {kind: 'none'} as const;
    const revision = typeof data['revision'] === 'number' ? data['revision'] : 0;
    const circuitSnapshot = await transaction.get(calendarQuotaCircuitRef());
    const circuitBlockedUntilMs = timestampMillis(
      circuitSnapshot.data()?.['blockedUntil'],
    );
    const storedDueAtMs = timestampMillis(data['dueAt']);
    const effectiveDueAtMs = circuitBlockedUntilMs != null &&
        circuitBlockedUntilMs > nowMs
      ? Math.max(storedDueAtMs ?? 0, circuitBlockedUntilMs)
      : storedDueAtMs;
    const leaseUntilMs = timestampMillis(data['leaseUntil']);
    const decision = decideEventCalendarJobClaim({
      dirty: data['dirty'] === true,
      dueAtMs: effectiveDueAtMs,
      leaseUntilMs,
      revision,
      nowMs,
    });
    if (decision.kind === 'none') return decision;
    if (decision.kind === 'delay') {
      if (
        circuitBlockedUntilMs != null &&
        circuitBlockedUntilMs > nowMs &&
        (leaseUntilMs == null || leaseUntilMs <= nowMs)
      ) {
        transaction.update(jobRef, {
          status: 'backoff',
          dueAt: Timestamp.fromMillis(effectiveDueAtMs!),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return decision;
    }

    const actor: CalendarJobActor = {
      memberId:
        typeof data['requestedByMemberId'] === 'string'
          ? data['requestedByMemberId']
          : payload.actor.memberId,
      isAdmin:
        typeof data['requestedByIsAdmin'] === 'boolean'
          ? data['requestedByIsAdmin']
          : payload.actor.isAdmin,
    };
    const consecutiveFailureCount =
      typeof data['consecutiveFailureCount'] === 'number'
        ? data['consecutiveFailureCount']
        : 0;
    const leaseUntil = Timestamp.fromMillis(
      nowMs + CALENDAR_JOB_LEASE_SECONDS * 1000,
    );
    transaction.update(jobRef, {
      status: 'processing',
      claimedRevision: revision,
      leaseUntil,
      dueAt: leaseUntil,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {kind: 'claimed', revision, actor, consecutiveFailureCount} as const;
  });

  if (claim.kind === 'none') return;
  if (claim.kind === 'delay') {
    await enqueueEventCalendarJob(payload.environment, eventId, payload.actor, claim.seconds);
    return;
  }

  try {
    const eventSnapshot = await db.collection(collections.events).doc(eventId).get();
    if (
      !eventSnapshot.exists ||
      eventSnapshot.data()?.[EVENT_DELETION_PENDING_FIELD] === true
    ) {
      // The deletion fence and durable Calendar tombstone are atomic. Finish
      // the potentially large relation cascade before reconciling Google.
      await finalizePendingEventDeletion(collections, eventId);
    }
    const report = await syncAppEventCalendars(
      {
        firestore: db,
        actor: claim.actor,
        environment: payload.environment,
        collections,
      },
      {eventId},
    );
    if (report.quotaExhausted) {
      const blockedUntilMs = await openCalendarQuotaCircuit(
        'Google Calendar quota exhausted',
      );
      await jobRef.set({
        dirty: true,
        status: 'backoff',
        dueAt: Timestamp.fromMillis(blockedUntilMs),
        leaseUntil: FieldValue.delete(),
        lastError: 'Google Calendar quota exhausted',
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      await enqueueEventCalendarJob(
        payload.environment,
        eventId,
        claim.actor,
        Math.max(1, Math.ceil((blockedUntilMs - Date.now()) / 1000)),
      );
      return;
    }
    if (report.failedEventIds.length > 0) {
      throw new Error(`Calendar reconciliation failed for eventId=${eventId}`);
    }

    let needsAnotherPass = false;
    await db.runTransaction(async (transaction) => {
      const latest = await transaction.get(jobRef);
      if (!latest.exists) return;
      const latestRevision = latest.data()?.['revision'];
      const completion = decideEventCalendarJobCompletion(
        claim.revision,
        typeof latestRevision === 'number' ? latestRevision : 0,
      );
      needsAnotherPass = completion.needsAnotherPass;
      transaction.update(jobRef, {
        dirty: completion.dirty,
        status: completion.status,
        dueAt: needsAnotherPass
          ? Timestamp.fromMillis(Date.now() + EVENT_SYNC_DEBOUNCE_SECONDS * 1000)
          : FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
        lastError: FieldValue.delete(),
        lastSuccessAt: FieldValue.serverTimestamp(),
        consecutiveFailureCount: 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    if (needsAnotherPass) {
      await enqueueEventCalendarJob(payload.environment, eventId, claim.actor);
    }
  } catch (error: unknown) {
    const failure = classifyCalendarFailure(error);
    const failureCount = claim.consecutiveFailureCount + 1;

    if (failure.kind === 'quota') {
      const blockedUntilMs = await openCalendarQuotaCircuit(error);
      await jobRef.set({
        dirty: true,
        status: 'backoff',
        dueAt: Timestamp.fromMillis(blockedUntilMs),
        leaseUntil: FieldValue.delete(),
        lastError: String(error),
        consecutiveFailureCount: failureCount,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      await enqueueEventCalendarJob(
        payload.environment,
        eventId,
        claim.actor,
        Math.max(1, Math.ceil((blockedUntilMs - Date.now()) / 1000)),
      );
      return;
    }

    if (failure.kind === 'retryable-transient') {
      const baseDelay = failure.retryAfterSeconds ?? 60;
      const delaySeconds = Math.min(
        QUOTA_BACKOFF_SECONDS,
        baseDelay * (2 ** Math.min(failureCount - 1, 5)),
      );
      await jobRef.set({
        dirty: true,
        status: 'retrying',
        dueAt: Timestamp.fromMillis(Date.now() + delaySeconds * 1000),
        leaseUntil: FieldValue.delete(),
        lastError: String(error),
        consecutiveFailureCount: failureCount,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      await enqueueEventCalendarJob(
        payload.environment,
        eventId,
        claim.actor,
        delaySeconds,
      );
      return;
    }

    if (failure.kind === 'auth-blocked') {
      await jobRef.set({
        dirty: true,
        status: 'auth-blocked',
        dueAt: FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
        lastError: String(error),
        consecutiveFailureCount: failureCount,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return;
    }

    let revisionChanged = false;
    await db.runTransaction(async (transaction) => {
      const latest = await transaction.get(jobRef);
      if (!latest.exists) return;
      revisionChanged = latest.data()?.['revision'] !== claim.revision;
      transaction.update(jobRef, {
        dirty: revisionChanged,
        status: revisionChanged ? 'pending' : 'failed',
        dueAt: revisionChanged
          ? Timestamp.fromMillis(Date.now() + EVENT_SYNC_DEBOUNCE_SECONDS * 1000)
          : FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
        lastError: String(error),
        consecutiveFailureCount: failureCount,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    if (revisionChanged) {
      await enqueueEventCalendarJob(payload.environment, eventId, claim.actor);
    }
  }
}

async function enqueueGuestCleanupJob(
  environment: EnvironmentMode,
  jobId: string,
  actor: CalendarJobActor,
  scheduleDelaySeconds = 0,
): Promise<void> {
  const collections = getCollections(environment);
  const jobRef = db.collection(collections.calendarMaintenanceJobs).doc(jobId);
  const scheduledForMs = Date.now() + scheduleDelaySeconds * 1000;
  const scheduleToken = await reserveCalendarTask(
    jobRef,
    new Set(['completed', 'failed', 'auth-blocked']),
    scheduledForMs,
  );
  if (scheduleToken == null) return;
  try {
    await enqueueCalendarTask(
      {kind: 'guestCleanup', environment, jobId, actor, scheduleToken},
      scheduleDelaySeconds,
      createHash('sha256')
        .update(`cleanup:${environment}:${jobId}:${scheduleToken}`)
        .digest('hex'),
    );
  } catch (error: unknown) {
    await clearCalendarTaskReservation(jobRef, scheduleToken);
    console.error(
      `[calendar-cleanup-error] failed to enqueue cleanup job jobId=${jobId}:`,
      error,
    );
  }
}

function isEventInGuestCleanupScope(eventData: Record<string, unknown> | null): boolean {
  if (
    eventData == null ||
    eventData['isDeactivated'] === true ||
    eventData[EVENT_DELETION_PENDING_FIELD] === true
  ) {
    return false;
  }
  const endDate = asCalendarDay(eventData['endDate'], 'event.endDate');
  const todayParts = getCalendarDatePartsInTimeZone(new Date(), ISRAEL_TIME_ZONE);
  const today = buildTimeZoneMidnight(
    todayParts.year,
    todayParts.month,
    todayParts.day,
    ISRAEL_TIME_ZONE,
  );
  return endDate.getTime() >= today.getTime();
}

async function releaseGuestCleanupLock(
  collections: Collections,
  jobId: string,
): Promise<void> {
  const lockRef = guestCleanupLockRef(collections);
  await db.runTransaction(async (transaction) => {
    const lock = await transaction.get(lockRef);
    if (lock.data()?.['activeJobId'] === jobId) {
      transaction.delete(lockRef);
    }
  });
}

function guestCleanupPartDocumentId(calendarEventId: string): string {
  return createHash('sha256').update(calendarEventId).digest('hex');
}

async function deleteGuestCleanupPartDocuments(
  jobRef: FirebaseFirestore.DocumentReference,
  generation?: string,
): Promise<void> {
  while (true) {
    let query = jobRef.collection('parts').limit(400);
    if (generation != null) {
      query = query.where('generation', '==', generation).limit(400);
    }
    const snapshot = await query.get();
    if (snapshot.empty) return;
    const batch = db.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
  }
}

async function discoverGuestCleanupParts(
  collections: Collections,
  environment: EnvironmentMode,
  actor: CalendarJobActor,
  mode: 'omer' | 'all',
): Promise<GuestCleanupPart[]> {
  const dependencies = {
    firestore: db,
    actor,
    environment,
    collections,
  };
  const inScopeEventIds = new Set(await listInScopeAppEventIds(dependencies));
  const listed = await executeCalendarAction(
    db,
    actor,
    environment,
    'listManagedCalendarEvents',
    {kind: 'app'},
  );
  const managedEvents = Array.isArray(listed['events']) ? listed['events'] : [];
  const partsById = new Map<string, GuestCleanupPart>();
  for (const value of managedEvents) {
    if (value == null || typeof value !== 'object' || Array.isArray(value)) continue;
    const event = value as Record<string, unknown>;
    const calendarEventId = typeof event['id'] === 'string' ? event['id'] : '';
    const eventId = typeof event['eventId'] === 'string' ? event['eventId'] : '';
    if (
      calendarEventId.length === 0 ||
      eventId.length === 0 ||
      !inScopeEventIds.has(eventId) ||
      event['status'] === 'cancelled' ||
      event['isTestMode'] !== String(environment === 'test') ||
      (event['eventType'] !== 'assembly' &&
        event['eventType'] !== 'main' &&
        event['eventType'] !== 'allDay')
    ) {
      continue;
    }
    const attendeeEmails = Array.isArray(event['attendeeEmails'])
      ? event['attendeeEmails']
          .map((email) => String(email).trim().toLowerCase())
          .filter((email) => email.length > 0)
      : [];
    const matches = mode === 'all'
      ? attendeeEmails.length > 0
      : attendeeEmails.includes(OMER_CLEANUP_EMAIL);
    if (matches) partsById.set(calendarEventId, {calendarEventId, eventId});
  }
  return Array.from(partsById.values());
}

async function saveDiscoveredGuestCleanupParts(
  jobRef: FirebaseFirestore.DocumentReference,
  generation: string,
  parts: GuestCleanupPart[],
): Promise<void> {
  for (let start = 0; start < parts.length; start += 400) {
    const batch = db.batch();
    for (const part of parts.slice(start, start + 400)) {
      batch.set(
        jobRef.collection('parts').doc(guestCleanupPartDocumentId(part.calendarEventId)),
        {
          ...part,
          generation,
          createdAt: FieldValue.serverTimestamp(),
        },
      );
    }
    await batch.commit();
  }
}

async function commitGuestCleanupDiscovery(
  jobRef: FirebaseFirestore.DocumentReference,
  leaseToken: string,
  parts: GuestCleanupPart[],
): Promise<{stale: boolean; terminal: boolean}> {
  let result = {stale: false, terminal: parts.length === 0};
  await db.runTransaction(async (transaction) => {
    const latest = await transaction.get(jobRef);
    const data = latest.data() ?? {};
    if (
      !latest.exists ||
      data['leaseToken'] !== leaseToken ||
      data['stage'] !== 'discovery'
    ) {
      result = {stale: true, terminal: false};
      return;
    }

    const terminal = parts.length === 0;
    transaction.update(jobRef, {
      stage: terminal ? 'complete' : 'processing',
      generation: terminal ? FieldValue.delete() : leaseToken,
      status: terminal ? 'completed' : 'queued',
      totalEventCount: new Set(parts.map((part) => part.eventId)).size,
      totalPartCount: parts.length,
      processedPartCount: 0,
      changedPartCount: 0,
      skippedPartCount: 0,
      failedPartCount: 0,
      leaseToken: FieldValue.delete(),
      leaseUntil: FieldValue.delete(),
      retryAt: FieldValue.delete(),
      lastError: FieldValue.delete(),
      consecutiveFailureCount: 0,
      completedAt: terminal
        ? FieldValue.serverTimestamp()
        : FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    result = {stale: false, terminal};
  });
  return result;
}

async function commitGuestCleanupPartOutcome(
  jobRef: FirebaseFirestore.DocumentReference,
  partRef: FirebaseFirestore.DocumentReference,
  leaseToken: string,
  outcome: 'changed' | 'skipped' | 'failed',
  error: unknown = null,
): Promise<{stale: boolean; terminal: boolean; hasMore: boolean}> {
  let result = {stale: false, terminal: false, hasMore: false};
  await db.runTransaction(async (transaction) => {
    const [latest, partSnapshot] = await Promise.all([
      transaction.get(jobRef),
      transaction.get(partRef),
    ]);
    const data = latest.data() ?? {};
    if (
      !latest.exists ||
      !partSnapshot.exists ||
      data['leaseToken'] !== leaseToken ||
      data['currentPartId'] !== partRef.id
    ) {
      result = {stale: true, terminal: false, hasMore: false};
      return;
    }

    const processedBefore = Number(data['processedPartCount']) || 0;
    const totalPartCount = Number(data['totalPartCount']) || 0;
    const failedBefore = Number(data['failedPartCount']) || 0;
    const failedAfter = failedBefore + (outcome === 'failed' ? 1 : 0);
    const terminal = processedBefore + 1 >= totalPartCount;
    const updates: Record<string, unknown> = {
      processedPartCount: FieldValue.increment(1),
      changedPartCount: FieldValue.increment(outcome === 'changed' ? 1 : 0),
      skippedPartCount: FieldValue.increment(outcome === 'skipped' ? 1 : 0),
      failedPartCount: FieldValue.increment(outcome === 'failed' ? 1 : 0),
      status: terminal ? (failedAfter > 0 ? 'failed' : 'completed') : 'queued',
      currentPartId: FieldValue.delete(),
      currentCalendarEventId: FieldValue.delete(),
      leaseToken: FieldValue.delete(),
      leaseUntil: FieldValue.delete(),
      retryAt: FieldValue.delete(),
      consecutiveFailureCount: 0,
      updatedAt: FieldValue.serverTimestamp(),
      completedAt: terminal
        ? FieldValue.serverTimestamp()
        : FieldValue.delete(),
    };
    if (outcome === 'failed') {
      updates['lastError'] = String(error);
    } else if (failedBefore === 0) {
      updates['lastError'] = FieldValue.delete();
    }
    transaction.delete(partRef);
    transaction.update(jobRef, updates);
    result = {
      stale: false,
      terminal,
      hasMore: !terminal,
    };
  });
  return result;
}

async function commitGuestCleanupRetryState(
  jobRef: FirebaseFirestore.DocumentReference,
  leaseToken: string,
  updates: Record<string, unknown>,
): Promise<boolean> {
  let applied = false;
  await db.runTransaction(async (transaction) => {
    const latest = await transaction.get(jobRef);
    const data = latest.data() ?? {};
    if (!latest.exists || data['leaseToken'] !== leaseToken) return;
    transaction.update(jobRef, {
      ...updates,
      currentPartId: FieldValue.delete(),
      currentCalendarEventId: FieldValue.delete(),
      leaseToken: FieldValue.delete(),
      leaseUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    applied = true;
  });
  return applied;
}

async function drainGuestCleanupJob(payload: CalendarSyncTaskPayload): Promise<void> {
  const jobId = payload.jobId;
  if (jobId == null || jobId.length === 0) return;
  const collections = getCollections(payload.environment);
  const jobRef = db.collection(collections.calendarMaintenanceJobs).doc(jobId);
  if (!await consumeCalendarTaskReservation(jobRef, payload.scheduleToken)) return;
  const nowMs = Date.now();

  const claim = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(jobRef);
    if (!snapshot.exists) return {kind: 'none'} as const;
    const job = snapshot.data() ?? {};
    const status = typeof job['status'] === 'string' ? job['status'] : '';
    if (status === 'completed' || status === 'failed' || status === 'auth-blocked') {
      return {kind: 'none'} as const;
    }

    const circuitSnapshot = await transaction.get(calendarQuotaCircuitRef());
    const circuitBlockedUntilMs = timestampMillis(
      circuitSnapshot.data()?.['blockedUntil'],
    );
    const retryAtMs = timestampMillis(job['retryAt']);
    const leaseUntilMs = timestampMillis(job['leaseUntil']);
    const blockedUntilMs = Math.max(
      retryAtMs ?? 0,
      leaseUntilMs ?? 0,
      circuitBlockedUntilMs != null && circuitBlockedUntilMs > nowMs
        ? circuitBlockedUntilMs
        : 0,
    );
    if (blockedUntilMs > nowMs) {
      if (leaseUntilMs == null || leaseUntilMs <= nowMs) {
        transaction.update(jobRef, {
          status: 'backoff',
          retryAt: Timestamp.fromMillis(blockedUntilMs),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return {
        kind: 'delay',
        seconds: Math.max(1, Math.ceil((blockedUntilMs - nowMs) / 1000)),
      } as const;
    }

    const actor: CalendarJobActor = {
      memberId: typeof job['requestedByMemberId'] === 'string'
        ? job['requestedByMemberId']
        : payload.actor.memberId,
      isAdmin: typeof job['requestedByIsAdmin'] === 'boolean'
        ? job['requestedByIsAdmin']
        : payload.actor.isAdmin,
    };
    const mode = job['mode'] === 'all' ? 'all' as const : 'omer' as const;
    const leaseToken = randomUUID();
    const leaseUntil = Timestamp.fromMillis(
      nowMs + CALENDAR_JOB_LEASE_SECONDS * 1000,
    );
    const generation = typeof job['generation'] === 'string' ? job['generation'] : null;
    const isProcessing = job['stage'] === 'processing' && generation != null;

    if (!isProcessing) {
      transaction.update(jobRef, {
        stage: 'discovery',
        status: 'discovering',
        leaseToken,
        retryAt: FieldValue.delete(),
        leaseUntil,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        kind: 'discovery',
        actor,
        mode,
        leaseToken,
        consecutiveFailureCount:
          typeof job['consecutiveFailureCount'] === 'number'
            ? job['consecutiveFailureCount']
            : 0,
      } as const;
    }

    const parts = await transaction.get(
      jobRef.collection('parts').where('generation', '==', generation).limit(1),
    );
    if (parts.empty) {
      const terminalStatus = Number(job['failedPartCount']) > 0 ? 'failed' : 'completed';
      transaction.update(jobRef, {
        stage: 'complete',
        status: terminalStatus,
        currentPartId: FieldValue.delete(),
        currentCalendarEventId: FieldValue.delete(),
        leaseToken: FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {kind: 'terminal'} as const;
    }

    const partDocument = parts.docs[0];
    const partData = partDocument.data() ?? {};
    const part = {
      calendarEventId: typeof partData['calendarEventId'] === 'string'
        ? partData['calendarEventId']
        : '',
      eventId: typeof partData['eventId'] === 'string' ? partData['eventId'] : '',
    };
    transaction.update(jobRef, {
      status: 'running',
      currentCalendarEventId: part.calendarEventId,
      currentPartId: partDocument.id,
      leaseToken,
      retryAt: FieldValue.delete(),
      leaseUntil,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      kind: 'part',
      part,
      partRef: partDocument.ref,
      actor,
      mode,
      leaseToken,
      consecutiveFailureCount:
        typeof job['consecutiveFailureCount'] === 'number'
          ? job['consecutiveFailureCount']
          : 0,
    } as const;
  });

  if (claim.kind === 'none') return;
  if (claim.kind === 'terminal') {
    await releaseGuestCleanupLock(collections, jobId);
    await deleteGuestCleanupPartDocuments(jobRef);
    return;
  }
  if (claim.kind === 'delay') {
    await enqueueGuestCleanupJob(
      payload.environment,
      jobId,
      payload.actor,
      claim.seconds,
    );
    return;
  }

  try {
    if (claim.kind === 'discovery') {
      const parts = await discoverGuestCleanupParts(
        collections,
        payload.environment,
        claim.actor,
        claim.mode,
      );
      await saveDiscoveredGuestCleanupParts(jobRef, claim.leaseToken, parts);
      const completion = await commitGuestCleanupDiscovery(
        jobRef,
        claim.leaseToken,
        parts,
      );
      if (completion.stale) {
        await deleteGuestCleanupPartDocuments(jobRef, claim.leaseToken);
      } else if (completion.terminal) {
        await releaseGuestCleanupLock(collections, jobId);
        await deleteGuestCleanupPartDocuments(jobRef);
      } else {
        await enqueueGuestCleanupJob(payload.environment, jobId, claim.actor);
      }
      return;
    }

    const part = claim.part;
    const eventSnapshot = await db.collection(collections.events).doc(part.eventId).get();
    const eventData = eventSnapshot.exists ? eventSnapshot.data() ?? {} : null;
    let outcome: 'changed' | 'skipped' = 'skipped';
    if (isEventInGuestCleanupScope(eventData)) {
      const actionResult = await executeCalendarAction(
        db,
        claim.actor,
        payload.environment,
        'cleanupAppEventGuests',
        {
          calendarEventId: part.calendarEventId,
          eventId: part.eventId,
          isTestMode: payload.environment === 'test',
          mode: claim.mode,
        },
      );
      outcome = actionResult['changed'] === true ? 'changed' : 'skipped';
    }

    const completion = await commitGuestCleanupPartOutcome(
      jobRef,
      claim.partRef,
      claim.leaseToken,
      outcome,
    );
    if (completion.terminal) {
      await releaseGuestCleanupLock(collections, jobId);
      await deleteGuestCleanupPartDocuments(jobRef);
    } else if (!completion.stale && completion.hasMore) {
      await enqueueGuestCleanupJob(payload.environment, jobId, claim.actor);
    }
  } catch (error: unknown) {
    const failure = classifyCalendarFailure(error);
    const failureCount = claim.consecutiveFailureCount + 1;
    if (failure.kind === 'quota') {
      const blockedUntilMs = await openCalendarQuotaCircuit(error);
      const applied = await commitGuestCleanupRetryState(jobRef, claim.leaseToken, {
        status: 'backoff',
        retryAt: Timestamp.fromMillis(blockedUntilMs),
        lastError: String(error),
        consecutiveFailureCount: failureCount,
      });
      if (applied) {
        await enqueueGuestCleanupJob(
          payload.environment,
          jobId,
          claim.actor,
          Math.max(1, Math.ceil((blockedUntilMs - Date.now()) / 1000)),
        );
      }
      return;
    }

    if (failure.kind === 'retryable-transient') {
      const baseDelay = failure.retryAfterSeconds ?? 60;
      const delaySeconds = Math.min(
        QUOTA_BACKOFF_SECONDS,
        baseDelay * (2 ** Math.min(failureCount - 1, 5)),
      );
      const applied = await commitGuestCleanupRetryState(jobRef, claim.leaseToken, {
        status: 'backoff',
        retryAt: Timestamp.fromMillis(Date.now() + delaySeconds * 1000),
        lastError: String(error),
        consecutiveFailureCount: failureCount,
      });
      if (applied) {
        await enqueueGuestCleanupJob(
          payload.environment,
          jobId,
          claim.actor,
          delaySeconds,
        );
      }
      return;
    }

    if (failure.kind === 'auth-blocked') {
      await commitGuestCleanupRetryState(jobRef, claim.leaseToken, {
        status: 'auth-blocked',
        retryAt: FieldValue.delete(),
        lastError: String(error),
        consecutiveFailureCount: failureCount,
      });
      return;
    }

    if (claim.kind === 'discovery') {
      const applied = await commitGuestCleanupRetryState(jobRef, claim.leaseToken, {
        stage: 'complete',
        status: 'failed',
        lastError: String(error),
        consecutiveFailureCount: failureCount,
        completedAt: FieldValue.serverTimestamp(),
      });
      if (applied) {
        await releaseGuestCleanupLock(collections, jobId);
        await deleteGuestCleanupPartDocuments(jobRef);
      }
      return;
    }

    const completion = await commitGuestCleanupPartOutcome(
      jobRef,
      claim.partRef,
      claim.leaseToken,
      'failed',
      error,
    );
    if (completion.terminal) {
      await releaseGuestCleanupLock(collections, jobId);
      await deleteGuestCleanupPartDocuments(jobRef);
    } else if (!completion.stale && completion.hasMore) {
      await enqueueGuestCleanupJob(payload.environment, jobId, claim.actor);
    }
  }
}

export const calendarJobSweep = onSchedule(
  {region: 'us-central1', schedule: 'every 5 minutes'},
  async () => {
    for (const environment of ['production', 'test'] as const) {
      const collections = getCollections(environment);
      // OAuth reconnects open a bounded durable recovery window. This catches
      // a worker that was already in flight during the immediate resume, even
      // if either delayed Cloud Task could not be created.
      await resumeRecentlyAuthorizedCalendarJobs(environment);
      if (await activeCalendarQuotaBlockedUntil() != null) {
        continue;
      }

      // `dueAt` is removed from completed/blocked jobs and moved to the lease
      // expiry while a worker is active. Paging by it prevents backoff jobs
      // from monopolizing the first page and eventually visits every due job.
      let cursor: QueryDocumentSnapshot | null = null;
      while (true) {
        let query = db.collection(collections.eventCalendarJobs)
          .where('dueAt', '<=', Timestamp.now())
          .orderBy('dueAt', 'asc')
          .limit(CALENDAR_JOB_SWEEP_LIMIT);
        if (cursor != null) {
          query = query.startAfter(cursor);
        }
        const dueJobs = await query.get();
        for (const doc of dueJobs.docs) {
          const data = doc.data() ?? {};
          if (data['dirty'] !== true || data['status'] === 'auth-blocked') continue;
          await enqueueEventCalendarJob(
            environment,
            doc.id,
            {
              memberId:
                typeof data['requestedByMemberId'] === 'string'
                  ? data['requestedByMemberId']
                  : 'calendar-job-sweeper',
              isAdmin: true,
            },
            0,
          );
        }
        if (dueJobs.size < CALENDAR_JOB_SWEEP_LIMIT) break;
        cursor = dueJobs.docs[dueJobs.docs.length - 1];
      }

      const [queuedCleanupJobs, dueCleanupRetries, expiredCleanupLeases] =
        await Promise.all([
          db.collection(collections.calendarMaintenanceJobs)
            .where('status', '==', 'queued')
            .limit(20)
            .get(),
          db.collection(collections.calendarMaintenanceJobs)
            .where('retryAt', '<=', Timestamp.now())
            .orderBy('retryAt', 'asc')
            .limit(20)
            .get(),
          db.collection(collections.calendarMaintenanceJobs)
            .where('leaseUntil', '<=', Timestamp.now())
            .orderBy('leaseUntil', 'asc')
            .limit(20)
            .get(),
        ]);
      const cleanupDocs = new Map<string, QueryDocumentSnapshot>();
      for (const snapshot of [queuedCleanupJobs, dueCleanupRetries, expiredCleanupLeases]) {
        for (const doc of snapshot.docs) cleanupDocs.set(doc.id, doc);
      }
      for (const doc of cleanupDocs.values()) {
        const data = doc.data() ?? {};
        if (
          data['type'] !== 'appEventGuestCleanup' ||
          data['status'] === 'auth-blocked'
        ) {
          continue;
        }
        await enqueueGuestCleanupJob(
          environment,
          doc.id,
          {
            memberId:
              typeof data['requestedByMemberId'] === 'string'
                ? data['requestedByMemberId']
                : 'calendar-job-sweeper',
            isAdmin: true,
          },
          0,
        );
      }
    }
  },
);

async function resumeAuthBlockedCalendarJobs(
  environment: EnvironmentMode,
  actor: CalendarJobActor,
): Promise<void> {
  const collections = getCollections(environment);
  const [eventJobs, cleanupJobs] = await Promise.all([
    db.collection(collections.eventCalendarJobs)
      .where('status', '==', 'auth-blocked')
      .get(),
    db.collection(collections.calendarMaintenanceJobs)
      .where('status', '==', 'auth-blocked')
      .get(),
  ]);
  const now = Timestamp.now();

  for (let start = 0; start < eventJobs.docs.length; start += 400) {
    const batch = db.batch();
    for (const doc of eventJobs.docs.slice(start, start + 400)) {
      batch.update(doc.ref, {
        dirty: true,
        status: 'pending',
        dueAt: now,
        lastError: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
  for (let start = 0; start < cleanupJobs.docs.length; start += 400) {
    const batch = db.batch();
    for (const doc of cleanupJobs.docs.slice(start, start + 400)) {
      batch.update(doc.ref, {
        status: 'queued',
        retryAt: FieldValue.delete(),
        lastError: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  for (const doc of eventJobs.docs) {
    await enqueueEventCalendarJob(environment, doc.id, actor, 0);
  }
  for (const doc of cleanupJobs.docs) {
    await enqueueGuestCleanupJob(environment, doc.id, actor, 0);
  }
}

async function recordAuthResumeWindow(
  environment: EnvironmentMode,
  actor: CalendarJobActor,
): Promise<string> {
  const collections = getCollections(environment);
  const generation = randomUUID();
  await db.collection(collections.privateGoogleCalendarAuth).doc(CALENDAR_AUTH_DOC_ID).set({
    authResumeGeneration: generation,
    authResumeUntil: Timestamp.fromMillis(
      Date.now() + AUTH_RESUME_WINDOW_SECONDS * 1000,
    ),
    authResumeRequestedByMemberId: actor.memberId,
    authResumeRequestedByIsAdmin: actor.isAdmin,
  }, {merge: true});
  return generation;
}

async function resumeRecentlyAuthorizedCalendarJobs(
  environment: EnvironmentMode,
  expectedGeneration?: string,
): Promise<void> {
  const collections = getCollections(environment);
  const authDocument = await db
    .collection(collections.privateGoogleCalendarAuth)
    .doc(CALENDAR_AUTH_DOC_ID)
    .get();
  const data = authDocument.data() ?? {};
  if (
    expectedGeneration != null &&
    data['authResumeGeneration'] !== expectedGeneration
  ) {
    return;
  }
  const resumeUntilMs = timestampMillis(data['authResumeUntil']);
  if (resumeUntilMs == null || resumeUntilMs <= Date.now()) return;
  await resumeAuthBlockedCalendarJobs(environment, {
    memberId: typeof data['authResumeRequestedByMemberId'] === 'string'
      ? data['authResumeRequestedByMemberId']
      : 'calendar-auth-recovery',
    isAdmin: data['authResumeRequestedByIsAdmin'] !== false,
  });
}

async function enqueueDelayedAuthResumeTasks(
  environment: EnvironmentMode,
  actor: CalendarJobActor,
  generation: string,
): Promise<void> {
  for (const delaySeconds of [15, CALENDAR_JOB_LEASE_SECONDS + 30]) {
    try {
      await enqueueCalendarTask(
        {kind: 'authResume', environment, actor, authGeneration: generation},
        delaySeconds,
        createHash('sha256')
          .update(`auth-resume:${environment}:${generation}:${delaySeconds}`)
          .digest('hex'),
      );
    } catch (error) {
      console.error('[calendar-sync-error] failed to enqueue OAuth recovery sweep:', error);
    }
  }
}

function requireString(value: unknown, fieldName: string): string {
  if (typeof value != 'string' || value.trim().length === 0) {
    throw new Error(`Missing or invalid ${fieldName}`);
  }
  return value;
}

function optionalString(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value != 'string') {
    throw new Error('Expected string value');
  }
  return value;
}

function asDate(value: unknown, fieldName: string): Date {
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value == 'string') {
    finalDateCheck(value, fieldName);
    return new Date(value);
  }
  throw new Error(`Missing or invalid ${fieldName}`);
}

function finalDateCheck(value: string, fieldName: string): void {
  if (Number.isNaN(Date.parse(value))) {
    throw new Error(`Missing or invalid ${fieldName}`);
  }
}

function toTimestamp(value: unknown, fieldName: string): Timestamp {
  return Timestamp.fromDate(asDate(value, fieldName));
}

const ISRAEL_TIME_ZONE = 'Asia/Jerusalem';

type CalendarDateParts = {
  year: number;
  month: number;
  day: number;
};

function getCalendarDatePartsInTimeZone(
  date: Date,
  timeZone: string,
): CalendarDateParts {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });

  const partMap: Record<string, string> = {};
  for (const part of formatter.formatToParts(date)) {
    if (part.type !== 'literal') {
      partMap[part.type] = part.value;
    }
  }

  return {
    year: Number(partMap['year']),
    month: Number(partMap['month']),
    day: Number(partMap['day']),
  };
}

function getTimeZoneOffsetMinutes(date: Date, timeZone: string): number {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    timeZoneName: 'shortOffset',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });

  const offsetPart = formatter
    .formatToParts(date)
    .find((part) => part.type === 'timeZoneName')
    ?.value;

  if (offsetPart == null) {
    throw new Error(`Missing timezone offset for ${timeZone}`);
  }

  const match = /^GMT([+-])(\d{1,2})(?::?(\d{2}))?$/.exec(offsetPart);
  if (match == null) {
    throw new Error(`Unsupported timezone offset format: ${offsetPart}`);
  }

  const sign = match[1] === '-' ? -1 : 1;
  const hours = Number(match[2]);
  const minutes = Number(match[3] ?? '0');
  return sign * ((hours * 60) + minutes);
}

function buildTimeZoneMidnight(
  year: number,
  month: number,
  day: number,
  timeZone: string,
): Date {
  let candidate = new Date(Date.UTC(year, month - 1, day, 0, 0, 0));

  for (let iteration = 0; iteration < 3; iteration += 1) {
    const offsetMinutes = getTimeZoneOffsetMinutes(candidate, timeZone);
    candidate = new Date(
      Date.UTC(year, month - 1, day, 0, 0, 0) - (offsetMinutes * 60 * 1000),
    );
  }

  return candidate;
}

function asCalendarDay(value: unknown, fieldName: string): Date {
  if (value instanceof Timestamp) {
    const parts = getCalendarDatePartsInTimeZone(value.toDate(), ISRAEL_TIME_ZONE);
    return buildTimeZoneMidnight(
      parts.year,
      parts.month,
      parts.day,
      ISRAEL_TIME_ZONE,
    );
  }

  if (typeof value == 'string') {
    const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
    if (match != null) {
      const year = Number(match[1]);
      const month = Number(match[2]);
      const day = Number(match[3]);
      return buildTimeZoneMidnight(year, month, day, ISRAEL_TIME_ZONE);
    }
  }

  const parts = getCalendarDatePartsInTimeZone(
    asDate(value, fieldName),
    ISRAEL_TIME_ZONE,
  );
  return buildTimeZoneMidnight(
    parts.year,
    parts.month,
    parts.day,
    ISRAEL_TIME_ZONE,
  );
}

function toDayTimestamp(value: unknown, fieldName: string): Timestamp {
  return Timestamp.fromDate(asCalendarDay(value, fieldName));
}

function normalizeDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

// Returns a Date at UTC midnight of the Israel calendar day of `date`.
// Event day-stamps are stored as Israel midnight (e.g. 21:00Z in summer), so
// using getUTCDate() on them would skid back into the previous calendar day.
function normalizeDayInIsrael(date: Date): Date {
  const parts = getCalendarDatePartsInTimeZone(date, ISRAEL_TIME_ZONE);
  return new Date(Date.UTC(parts.year, parts.month - 1, parts.day));
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}

function parseTimeToMinutes(value: unknown): number | null {
  if (typeof value != 'string' || value.length === 0) return null;
  const parts = value.split(':');
  if (parts.length !== 2) return null;
  const hours = Number(parts[0]);
  const minutes = Number(parts[1]);
  if (!Number.isInteger(hours) || !Number.isInteger(minutes)) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
  return hours * 60 + minutes;
}

function timesOverlap(
  firstStart: string | null,
  firstEnd: string | null,
  secondStart: string | null,
  secondEnd: string | null,
): boolean {
  const aStart = parseTimeToMinutes(firstStart);
  const aEnd = parseTimeToMinutes(firstEnd);
  const bStart = parseTimeToMinutes(secondStart);
  const bEnd = parseTimeToMinutes(secondEnd);
  if (aStart == null || aEnd == null || bStart == null || bEnd == null) {
    return true;
  }
  return aStart < bEnd && bStart < aEnd;
}

function hashPasscode(passcode: string): string {
  const salt = randomBytes(16);
  const hash = scryptSync(passcode, salt, 64);
  return `${salt.toString('hex')}:${hash.toString('hex')}`;
}

function verifyPasscode(passcode: string, encodedHash: string): boolean {
  const parts = encodedHash.split(':');
  if (parts.length !== 2) return false;
  const salt = Buffer.from(parts[0], 'hex');
  const expected = Buffer.from(parts[1], 'hex');
  const actual = scryptSync(passcode, salt, expected.length);
  return timingSafeEqual(expected, actual);
}

function getStoredPrivatePasscodeValue(
  credentialData: Record<string, unknown> | undefined,
): string | null {
  const value = credentialData?.['passcodeValue'];
  return typeof value === 'string' && value.length > 0 ? value : null;
}

async function upsertPrivatePasscodeCredential(
  collections: Collections,
  memberId: string,
  passcode: string,
  length: number,
  extraFields: Record<string, unknown> = {},
): Promise<void> {
  await db.collection(collections.privateCredentials).doc(memberId).set(
    stripUndefined({
      passcodeHash: hashPasscode(passcode),
      passcodeValue: passcode,
      passcodeLength: length,
      updatedAt: FieldValue.serverTimestamp(),
      ...extraFields,
    }),
    {merge: true},
  );
}

function hashSessionToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

function stripUndefined<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(
    Object.entries(value).filter(([, entryValue]) => entryValue !== undefined),
  ) as T;
}

async function readTeamMemberByUniqueKey(
  firestore: Firestore,
  collections: Collections,
  uniqueKey: string,
): Promise<{id: string; data: Record<string, unknown>} | null> {
  const snapshot = await firestore
    .collection(collections.teamMembers)
    .where('uniqueKey', '==', uniqueKey)
    .limit(1)
    .get();
  if (snapshot.empty) {
    const directDoc = await firestore.collection(collections.teamMembers).doc(uniqueKey).get();
    if (!directDoc.exists) {
      return null;
    }
    return {id: directDoc.id, data: directDoc.data() ?? {}};
  }
  const doc = snapshot.docs[0];
  return {id: doc.id, data: doc.data()};
}

async function readTeamMemberById(
  firestore: Firestore,
  collections: Collections,
  memberId: string,
): Promise<Record<string, unknown> | null> {
  const snapshot = await firestore.collection(collections.teamMembers).doc(memberId).get();
  return snapshot.exists ? snapshot.data() ?? null : null;
}

async function readEventById(
  firestore: Firestore,
  collections: Collections,
  eventId: string,
): Promise<Record<string, unknown> | null> {
  const snapshot = await firestore.collection(collections.events).doc(eventId).get();
  return snapshot.exists ? snapshot.data() ?? null : null;
}

function optionalStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => (typeof entry === 'string' ? entry : null))
    .filter((entry): entry is string => entry != null);
}

function normalizeOptionalText(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeEmailValue(value: string): string {
  return value.trim().toLowerCase();
}

function uniqueSortedStrings(values: Iterable<string>): string[] {
  return Array.from(new Set(
    Array.from(values)
      .map((value) => value.trim())
      .filter((value) => value.length > 0),
  )).sort((left, right) => left.localeCompare(right));
}

function toLocalDateTimePrefix(value: string | null): string | null {
  if (value == null || value.length < 16) {
    return value;
  }
  return value.slice(0, 16);
}

function calendarEventColorId(environment: EnvironmentMode): string {
  return environment === 'test'
    ? CALENDAR_TEST_MODE_COLOR_ID
    : CALENDAR_APP_EVENT_COLOR_ID;
}

function constraintColorIdForEnvironment(environment: EnvironmentMode): string {
  return environment === 'test'
    ? CALENDAR_TEST_MODE_COLOR_ID
    : CALENDAR_UNAVAILABILITY_COLOR_ID;
}

function createCalendarEventMainTitle(eventName: string, environment: EnvironmentMode): string {
  return environment === 'test'
    ? `${CALENDAR_TEST_MODE_PREFIX}${eventName}`
    : eventName;
}

function createCalendarEventAssemblyTitle(eventName: string, environment: EnvironmentMode): string {
  const title = `${eventName} - התייצבות והכנות`;
  return environment === 'test'
    ? `${CALENDAR_TEST_MODE_PREFIX}${title}`
    : title;
}

function cleanConstraintNote(note: string | null): string | null {
  if (note == null || note.trim().length === 0) {
    return null;
  }

  const autoRejectionMessage =
    '(מגבלה זו נדחתה באופן אוטומטי בגלל שאחד מהמנהלים מחק את המגבלה מגוגל קלנדר)';
  const cleaned = note
    .replace(`\n\n${autoRejectionMessage}`, '')
    .replace(autoRejectionMessage, '')
    .trim();
  return cleaned.length > 0 ? cleaned : null;
}

function createConstraintDescription(note: string | null): string {
  const cleaned = cleanConstraintNote(note);
  const lines = cleaned != null && cleaned.length > 0
    ? [cleaned, '', '--- נוצר אוטומטית על ידי שבצק ---']
    : ['--- נוצר אוטומטית על ידי שבצק ---'];
  return `${lines.join('\n')}\n`;
}

function createConstraintTitle(
  memberName: string,
  environment: EnvironmentMode,
): string {
  const base = `${memberName} - מגבלה`;
  return environment === 'test'
    ? `${CALENDAR_TEST_MODE_PREFIX}${base}`
    : base;
}

async function updateAppEventAttendees(
  actor: ActorContext,
  environment: EnvironmentMode,
  calendarEventIds: Iterable<string>,
  emails: string[],
): Promise<void> {
  const uniqueIds = uniqueSortedStrings(calendarEventIds);
  for (const calendarEventId of uniqueIds) {
    await executeCalendarActionWithQuotaCircuit(
      {
        memberId: actor.memberId,
        isAdmin: actor.isAdmin,
      },
      environment,
      'updateEventAttendees',
      {
        calendarEventId,
        emails,
      },
    );
  }
}

async function updateConstraintStatusForTeamMember(
  collections: Collections,
  actor: ActorContext,
  teamMemberId: string,
  constraintId: string,
  newStatus: string,
  options: {
    note?: string | null;
    wasAutoRejectedFromCalendar?: boolean;
  } = {},
): Promise<boolean> {
  const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
  const memberDoc = await memberRef.get();
  if (!memberDoc.exists) {
    return false;
  }

  const memberData = memberDoc.data() ?? {};
  const teamMemberName =
    typeof memberData['name'] === 'string' ? memberData['name'] as string : null;
  const constraints = Array.isArray(memberData['constraints'])
    ? [...(memberData['constraints'] as Array<Record<string, unknown>>)]
    : [];
  const constraintIndex = constraints.findIndex((constraint) => constraint['id'] === constraintId);
  if (constraintIndex < 0) {
    return false;
  }

  const previousConstraint = constraints[constraintIndex];
  const wasAutoRejectedFromCalendar = options.wasAutoRejectedFromCalendar === true;
  const updatedConstraint = {
    ...constraints[constraintIndex],
    status: newStatus,
    ...(options.note != null ? {note: options.note} : {}),
    ...(options.wasAutoRejectedFromCalendar != null
      ? {wasAutoRejectedFromCalendar}
      : {}),
  };
  constraints[constraintIndex] = updatedConstraint;

  await memberRef.update({
    constraints,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await writeAuditLog(
    db,
    collections,
    actor,
    'constraint.updateStatus',
    getConstraintAuditEntityType(updatedConstraint),
    constraintId,
    buildConstraintAuditDetails(
      teamMemberId,
      teamMemberName,
      updatedConstraint,
      {
        newStatus,
        semanticAction: getConstraintStatusSemanticAction(
          newStatus,
          wasAutoRejectedFromCalendar,
        ) ?? undefined,
      },
    ),
    {
      before: previousConstraint,
      after: updatedConstraint,
    },
  );
  return true;
}

async function acquireConstraintSyncAction(
  collections: Collections,
  constraintId: string,
  teamMemberId: string,
): Promise<{
  action: 'create' | 'update';
  calendarEventId: string | null;
}> {
  return await db.runTransaction(async (transaction) => {
    const ref = db.collection(collections.calendarSync).doc(constraintId);
    const snapshot = await transaction.get(ref);
    if (snapshot.exists && snapshot.data()?.['status'] === 'synced') {
      return {
        action: 'update' as const,
        calendarEventId: optionalString(snapshot.data()?.['calendarEventId']),
      };
    }

    transaction.set(ref, {
      calendarEventId: '',
      teamMemberId,
      status: 'pending',
      syncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      retryCount: 0,
      errorMessage: null,
      reservedBy: Date.now(),
    });

    return {
      action: 'create' as const,
      calendarEventId: null,
    };
  });
}

async function saveFailedConstraintSyncState(
  collections: Collections,
  constraintId: string,
  teamMemberId: string,
  errorMessage: string,
  retryCount: number,
): Promise<void> {
  await db.collection(collections.calendarSync).doc(constraintId).set({
    calendarEventId: '',
    teamMemberId,
    status: 'failed',
    syncedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    retryCount,
    errorMessage,
  });
}

async function saveSyncedConstraintSyncState(
  collections: Collections,
  constraintId: string,
  teamMemberId: string,
  calendarEventId: string,
): Promise<void> {
  await db.collection(collections.calendarSync).doc(constraintId).set({
    calendarEventId,
    teamMemberId,
    status: 'synced',
    syncedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    retryCount: 0,
    errorMessage: null,
  });
}

async function createSession(
  firestore: Firestore,
  collections: Collections,
  memberId: string,
  uniqueKey: string,
  isAdmin: boolean,
): Promise<{sessionToken: string; expiresAt: string}> {
  const sessionToken = randomBytes(48).toString('hex');
  const sessionHash = hashSessionToken(sessionToken);
  const now = Timestamp.now();
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000));

  await firestore.collection(collections.privateSessions).doc(sessionHash).set({
    memberId,
    uniqueKey,
    isAdmin,
    createdAt: now,
    updatedAt: now,
    lastUsedAt: now,
    expiresAt,
  });

  return {
    sessionToken,
    expiresAt: expiresAt.toDate().toISOString(),
  };
}

async function authenticateRequest(request: Request): Promise<{
  actor: ActorContext;
  environment: EnvironmentMode;
  collections: Collections;
}> {
  const header = request.header('authorization');
  if (!header || !header.startsWith('Bearer ')) {
    throw new HttpError(401, 'Missing session token');
  }

  const token = header.substring('Bearer '.length).trim();
  if (token.length === 0) {
    throw new HttpError(401, 'Missing session token');
  }

  let decodedToken;
  try {
    decodedToken = await auth.verifyIdToken(token);
  } catch (error) {
    throw new HttpError(401, 'Invalid session token');
  }

  const environment = getEnvironmentMode(request.body?.environment);
  const collections = getCollections(environment);
  const memberId = requireString(decodedToken.uid, 'token.uid');
  const memberDoc = await db.collection(collections.teamMembers).doc(memberId).get();
  if (!memberDoc.exists) {
    throw new HttpError(401, 'User no longer exists');
  }

  const memberData = memberDoc.data() ?? {};
  if (memberData['isActive'] !== true || memberData['isArchived'] === true) {
    throw new HttpError(403, 'User is no longer active');
  }

  return {
    environment,
    collections,
    actor: {
      memberId,
      uniqueKey: requireString(memberData['uniqueKey'] ?? memberId, 'member.uniqueKey'),
      isAdmin: memberData['isAdmin'] === true,
      sessionId: '',
      expiresAt: Timestamp.now(),
      member: memberData,
    },
  };
}

function getConstraintStatusSemanticAction(
  newStatus: unknown,
  wasAutoRejectedFromCalendar = false,
): string | null {
  if (wasAutoRejectedFromCalendar) {
    return 'autoreject';
  }

  if (typeof newStatus !== 'string' || newStatus.trim().length === 0) {
    return null;
  }

  switch (newStatus.trim().toLowerCase()) {
    case 'approved':
      return 'approve';
    case 'rejected':
      return 'reject';
    case 'pending':
      return 'returntopending';
    default:
      return null;
  }
}

function getChecklistUpdateSemanticAction(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): string | null {
  const diff = buildAuditDiff(before, after, ['createdAt', 'updatedAt', 'statusLastUpdatedAt']);
  const changedKeys = new Set([
    ...Object.keys(diff.oldValue ?? {}),
    ...Object.keys(diff.newValue ?? {}),
  ]);

  if (changedKeys.size !== 1 || !changedKeys.has('status')) {
    return null;
  }

  if (after['status'] === true) {
    return 'complete';
  }

  if (after['status'] === false) {
    return 'reopen';
  }

  return null;
}

function normalizeAuditActionType(
  operation: string,
  details: Record<string, unknown> = {},
): string {
  const raw = operation.trim().toLowerCase();
  const finalSegment = raw.split('.').at(-1) ?? raw;
  const explicitSemanticAction = optionalString(details['semanticAction']);

  if (explicitSemanticAction != null && explicitSemanticAction.trim().length > 0) {
    return explicitSemanticAction.trim().toLowerCase();
  }

  if (finalSegment === 'updatestatus') {
    const semanticAction = getConstraintStatusSemanticAction(
      details['newStatus'],
      details['wasAutoRejectedFromCalendar'] === true,
    );
    if (semanticAction != null) {
      return semanticAction;
    }
  }

  switch (finalSegment) {
    case 'insert':
      return 'create';
    case 'edit':
      return 'update';
    default:
      return finalSegment;
  }
}

function getAuditEntityName(details: Record<string, unknown>): string | null {
  const name = details['name'];
  if (typeof name === 'string' && name.trim().length > 0) {
    return name.trim();
  }

  const entityName = details['entityName'];
  if (typeof entityName === 'string' && entityName.trim().length > 0) {
    return entityName.trim();
  }

  return null;
}

function optionalDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'string' && value.trim().length > 0 && !Number.isNaN(Date.parse(value))) {
    return new Date(value);
  }
  return null;
}

function formatIsraelDateOnly(date: Date): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Jerusalem',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

function getConstraintRepeatTypeLabel(value: unknown): string | null {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return null;
  }

  switch (value.trim().toLowerCase()) {
    case 'daily':
      return 'יומי';
    case 'weekly':
      return 'שבועי';
    case 'monthly':
      return 'חודשי';
    default:
      return value;
  }
}

function getConstraintAuditEntityType(
  constraint: Record<string, unknown> | null | undefined,
): string {
  return constraint?.['constraintType'] === 'availability'
    ? 'availability'
    : 'constraint';
}

function buildConstraintSummary(
  constraint: Record<string, unknown> | null | undefined,
): string | null {
  if (constraint == null) {
    return null;
  }

  const startDate = optionalDate(constraint['startDate']);
  const endDate = optionalDate(constraint['endDate']);
  const startTime =
    typeof constraint['startTime'] === 'string' &&
      constraint['startTime'].trim().length > 0
      ? constraint['startTime'].trim()
      : null;
  const endTime =
    typeof constraint['endTime'] === 'string' &&
      constraint['endTime'].trim().length > 0
      ? constraint['endTime'].trim()
      : null;
  const note =
    typeof constraint['note'] === 'string' && constraint['note'].trim().length > 0
      ? constraint['note'].trim()
      : null;
  const repeatTypeLabel = getConstraintRepeatTypeLabel(constraint['repeatType']);

  const parts: string[] = [];

  if (repeatTypeLabel != null) {
    parts.push(repeatTypeLabel);
  }

  if (startDate != null) {
    const startText = formatIsraelDateOnly(startDate);
    const endText = endDate == null ? null : formatIsraelDateOnly(endDate);
    parts.push(endText == null || endText === startText
      ? startText
      : `${startText} - ${endText}`);
  }

  if (startTime != null || endTime != null) {
    parts.push(startTime != null && endTime != null
      ? `${startTime} - ${endTime}`
      : (startTime ?? endTime)!);
  }

  if (note != null) {
    parts.push(note);
  }

  return parts.length > 0 ? parts.join(' | ') : null;
}

function buildConstraintAuditDetails(
  teamMemberId: string,
  teamMemberName: string | null,
  constraint: Record<string, unknown> | null | undefined,
  extras: Record<string, unknown> = {},
): Record<string, unknown> {
  return stripUndefined({
    teamMemberId,
    teamMemberName: teamMemberName ?? undefined,
    constraintType:
      typeof constraint?.['constraintType'] === 'string'
        ? constraint['constraintType']
        : undefined,
    startDate: constraint?.['startDate'] ?? undefined,
    endDate: constraint?.['endDate'] ?? undefined,
    startTime:
      typeof constraint?.['startTime'] === 'string'
        ? constraint['startTime']
        : undefined,
    endTime:
      typeof constraint?.['endTime'] === 'string'
        ? constraint['endTime']
        : undefined,
    note:
      typeof constraint?.['note'] === 'string' &&
        constraint['note'].trim().length > 0
        ? constraint['note']
        : undefined,
    status:
      typeof constraint?.['status'] === 'string'
        ? constraint['status']
        : undefined,
    repeatType:
      typeof constraint?.['repeatType'] === 'string'
        ? constraint['repeatType']
        : undefined,
    repeatDay:
      typeof constraint?.['repeatDay'] === 'number'
        ? constraint['repeatDay']
        : undefined,
    repeatEndDate: constraint?.['repeatEndDate'] ?? undefined,
    wasAutoRejectedFromCalendar:
      constraint?.['wasAutoRejectedFromCalendar'] === true ? true : undefined,
    constraintSummary: buildConstraintSummary(constraint) ?? undefined,
    ...extras,
  });
}

function buildAssignmentAuditDetails(
  assignment: Record<string, unknown> | null | undefined,
  extras: Record<string, unknown> = {},
): Record<string, unknown> {
  return stripUndefined({
    eventId:
      typeof assignment?.['eventId'] === 'string'
        ? assignment['eventId']
        : undefined,
    eventName:
      typeof extras['eventName'] === 'string' && String(extras['eventName']).trim().length > 0
        ? extras['eventName']
        : undefined,
    teamMemberId:
      typeof assignment?.['teamMemberId'] === 'string'
        ? assignment['teamMemberId']
        : undefined,
    teamMemberName:
      typeof extras['teamMemberName'] === 'string' && String(extras['teamMemberName']).trim().length > 0
        ? extras['teamMemberName']
        : undefined,
    roleType:
      typeof assignment?.['roleType'] === 'string'
        ? assignment['roleType']
        : undefined,
    status:
      typeof assignment?.['status'] === 'string'
        ? assignment['status']
        : undefined,
    ...extras,
  });
}

function buildChecklistItemAuditDetails(
  checklistItem: Record<string, unknown> | null | undefined,
  extras: Record<string, unknown> = {},
): Record<string, unknown> {
  return stripUndefined({
    name:
      typeof checklistItem?.['name'] === 'string'
        ? checklistItem['name']
        : undefined,
    responsibleId:
      typeof checklistItem?.['responsibleId'] === 'string'
        ? checklistItem['responsibleId']
        : undefined,
    responsibleName:
      typeof extras['responsibleName'] === 'string' &&
        String(extras['responsibleName']).trim().length > 0
        ? extras['responsibleName']
        : undefined,
    status:
      typeof checklistItem?.['status'] === 'boolean'
        ? checklistItem['status']
        : undefined,
    createdByAdminId:
      typeof checklistItem?.['createdByAdminId'] === 'string'
        ? checklistItem['createdByAdminId']
        : undefined,
    ...extras,
  });
}

function formatIsraelTimestamp(date: Date): string {
  const formatter = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Jerusalem',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    fractionalSecondDigits: 3,
    hour12: false,
  });

  const partMap: Record<string, string> = {};
  for (const part of formatter.formatToParts(date)) {
    if (part.type !== 'literal') {
      partMap[part.type] = part.value;
    }
  }

  return `${partMap['year']}-${partMap['month']}-${partMap['day']}`
      + `T${partMap['hour']}:${partMap['minute']}:${partMap['second']}`
      + `.${partMap['fractionalSecond'] ?? '000'}`;
}

function normalizeAuditValue(value: unknown): unknown {
  if (value == null) {
    return null;
  }

  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (Array.isArray(value)) {
    return value.map((item) => normalizeAuditValue(item));
  }

  if (typeof value === 'object') {
    const normalized: Record<string, unknown> = {};
    for (const [key, entryValue] of Object.entries(
      value as Record<string, unknown>,
    ).sort(([left], [right]) => left.localeCompare(right))) {
      if (entryValue === undefined) {
        continue;
      }
      normalized[key] = normalizeAuditValue(entryValue);
    }
    return normalized;
  }

  if (typeof value === 'bigint') {
    return value.toString();
  }

  return value;
}

function normalizeAuditRecord(
  value: Record<string, unknown> | null | undefined,
): Record<string, unknown> | null {
  if (value == null) {
    return null;
  }

  return normalizeAuditValue(value) as Record<string, unknown>;
}

function auditValuesEqual(left: unknown, right: unknown): boolean {
  return JSON.stringify(normalizeAuditValue(left)) ===
    JSON.stringify(normalizeAuditValue(right));
}

function buildAuditDiff(
  before: Record<string, unknown> | null | undefined,
  after: Record<string, unknown> | null | undefined,
  ignoreKeys: string[] = [],
): {
  changes: Record<string, unknown> | null;
  oldValue: Record<string, unknown> | null;
  newValue: Record<string, unknown> | null;
} {
  const normalizedBefore = normalizeAuditRecord(before);
  const normalizedAfter = normalizeAuditRecord(after);

  if (normalizedBefore == null && normalizedAfter == null) {
    return {
      changes: null,
      oldValue: null,
      newValue: null,
    };
  }

  const ignored = new Set(ignoreKeys);
  const keys = Array.from(
    new Set([
      ...Object.keys(normalizedBefore ?? {}),
      ...Object.keys(normalizedAfter ?? {}),
    ]),
  )
    .filter((key) => !ignored.has(key))
    .sort((left, right) => left.localeCompare(right));

  const changes: Record<string, unknown> = {};
  const oldValue: Record<string, unknown> = {};
  const newValue: Record<string, unknown> = {};

  for (const key of keys) {
    const beforeValue = normalizedBefore?.[key] ?? null;
    const afterValue = normalizedAfter?.[key] ?? null;

    if (auditValuesEqual(beforeValue, afterValue)) {
      continue;
    }

    changes[key] = {
      oldValue: beforeValue,
      newValue: afterValue,
    };
    oldValue[key] = beforeValue;
    newValue[key] = afterValue;
  }

  return {
    changes: Object.keys(changes).length > 0 ? changes : null,
    oldValue: Object.keys(oldValue).length > 0 ? oldValue : null,
    newValue: Object.keys(newValue).length > 0 ? newValue : null,
  };
}

async function writeAuditLog(
  firestore: Firestore,
  collections: Collections,
  actor: ActorContext,
  operation: string,
  entityType: string,
  entityId: string,
  details: Record<string, unknown> = {},
  diffContext: {
    before?: Record<string, unknown> | null;
    after?: Record<string, unknown> | null;
    ignoreKeys?: string[];
  } = {},
  operationContext: {
    operationId?: string;
    parentOperationId?: string | null;
  } = {},
): Promise<string> {
  const performerName = typeof actor.member['name'] === 'string'
    ? (actor.member['name'] as string)
    : null;
  const diff = buildAuditDiff(
    diffContext.before,
    diffContext.after,
    diffContext.ignoreKeys ?? ['createdAt', 'updatedAt', 'statusLastUpdatedAt'],
  );
  const operationId = typeof operationContext.operationId === 'string' &&
      operationContext.operationId.trim().length > 0
    ? operationContext.operationId.trim()
    : randomUUID();
  const parentOperationId = typeof operationContext.parentOperationId === 'string' &&
      operationContext.parentOperationId.trim().length > 0
    ? operationContext.parentOperationId.trim()
    : null;

  await firestore.collection(collections.logs).add({
    timestampUtc: FieldValue.serverTimestamp(),
    timestampLocalIsrael: formatIsraelTimestamp(new Date()),
    actionType: normalizeAuditActionType(operation, details),
    operation,
    entityType,
    entityId,
    entityName: getAuditEntityName(details),
    performerId: actor.memberId,
    performerUniqueKey: actor.uniqueKey,
    performerName,
    status: 'success',
    source: 'cloud_function',
    changes: diff.changes,
    oldValue: diff.oldValue,
    newValue: diff.newValue,
    details,
    operationId,
    ...(parentOperationId == null ? {} : {parentOperationId}),
  });

  return operationId;
}

async function ensureFirebaseAuthUser(
  memberId: string,
  memberData: Record<string, unknown>,
): Promise<void> {
  const displayName = typeof memberData['name'] === 'string'
    ? (memberData['name'] as string)
    : undefined;
  const disabled = memberData['isActive'] !== true || memberData['isArchived'] === true;

  try {
    await auth.updateUser(memberId, stripUndefined({
      displayName,
      disabled,
    }));
  } catch (error) {
    const errorCode = error instanceof Error && 'code' in error
      ? String((error as {code?: unknown}).code)
      : '';
    if (errorCode !== 'auth/user-not-found') {
      throw error;
    }

    await auth.createUser(stripUndefined({
      uid: memberId,
      displayName,
      disabled,
    }));
  }
}

function requireAdmin(actor: ActorContext): void {
  if (!actor.isAdmin) {
    throw new HttpError(403, 'Admin access is required');
  }
}

function requireSelfOrAdmin(actor: ActorContext, memberId: string): void {
  if (!actor.isAdmin && actor.memberId !== memberId) {
    throw new HttpError(403, 'You do not have access to this resource');
  }
}

function teamMemberDocFromJson(member: Record<string, unknown>, existing?: Record<string, unknown>): Record<string, unknown> {
  const next = stripUndefined({
    id: member['id'],
    name: member['name'],
    isActive: member['isActive'],
    isPermanent: member['isPermanent'] ?? false,
    isArchived: member['isArchived'] ?? false,
    constraints: member['constraints'] ?? [],
    roleCapabilities: member['roleCapabilities'] ?? {},
    comments: member['comments'] ?? '',
    createdAt: toTimestamp(member['createdAt'], 'member.createdAt'),
    updatedAt: toTimestamp(member['updatedAt'], 'member.updatedAt'),
    uniqueKey: member['uniqueKey'] ?? existing?.['uniqueKey'],
    isAdmin: member['isAdmin'] ?? false,
    passcodeLength: member['passcodeLength'] ?? existing?.['passcodeLength'] ?? null,
    allowMultipleAssignments: member['allowMultipleAssignments'] ?? false,
    phoneNumber: member['phoneNumber'] ?? null,
    email: member['email'] ?? null,
    birthday: member['birthday'] == null ? null : toTimestamp(member['birthday'], 'member.birthday'),
    canAccessSummaryScreen: member['canAccessSummaryScreen'] ?? false,
    canAccessShamapExport: member['canAccessShamapExport'] ?? false,
    canAccessConstraintsExamining: member['canAccessConstraintsExamining'] ?? false,
    vehicleInfo: member['vehicleInfo'] ?? null,
    availableEventIds: member['availableEventIds'] ?? [],
  });

  return next;
}

function eventDocFromJson(event: Record<string, unknown>): Record<string, unknown> {
  return stripUndefined({
    id: event['id'],
    name: event['name'],
    startDate: toDayTimestamp(event['startDate'], 'event.startDate'),
    endDate: toDayTimestamp(event['endDate'], 'event.endDate'),
    startTime: event['startTime'] ?? '',
    endTime: event['endTime'] ?? '',
    teamEndTime: event['teamEndTime'] ?? '',
    assemblyTime: event['assemblyTime'] ?? '',
    actualShowStartTime: event['actualShowStartTime'] ?? '',
    participantGroups: normalizeParticipantGroups(
      event['participantGroups'],
      event['participantCount'],
    ),
    // Retired, superseded by participantGroups. Written as null rather than
    // omitted: event.update is a partial merge, so an omitted key would leave
    // the stale value on the doc for old clients to render as a WRONG number.
    participantCount: null,
    location: event['location'] ?? '',
    parkingLocation: event['parkingLocation'] ?? null,
    parkingEditorIds: event['parkingEditorIds'] ?? [],
    requiresArmed: event['requiresArmed'] ?? false,
    comments: event['comments'] ?? '',
    categoryId: event['categoryId'] ?? null,
    roleRequirements: event['roleRequirements'] ?? {},
    createdAt: toTimestamp(event['createdAt'], 'event.createdAt'),
    updatedAt: toTimestamp(event['updatedAt'], 'event.updatedAt'),
    driveFolderId: event['driveFolderId'] ?? null,
    driveFolderLink: event['driveFolderLink'] ?? null,
    relevantForExtendedTeam: event['relevantForExtendedTeam'] ?? false,
    isDeactivated: event['isDeactivated'] ?? false,
    inviteAllPermanentWhenUnassigned:
      event['inviteAllPermanentWhenUnassigned'] ?? false,
  });
}

function assignmentDocFromJson(assignment: Record<string, unknown>): Record<string, unknown> {
  return stripUndefined({
    id: assignment['id'],
    eventId: assignment['eventId'],
    teamMemberId: assignment['teamMemberId'],
    roleType: assignment['roleType'],
    slotIndex: assignment['slotIndex'] ?? 0,
    status: assignment['status'] ?? 'pending',
    notes: assignment['notes'] ?? '',
    semanticLabelId: normalizeOptionalText(assignment['semanticLabelId']),
    alternativePhoneNumber: assignment['alternativePhoneNumber'] ?? null,
    createdAt: toTimestamp(assignment['createdAt'], 'assignment.createdAt'),
    updatedAt: toTimestamp(assignment['updatedAt'], 'assignment.updatedAt'),
  });
}

// Pure planning step for assignment.saveBatch: partitions the raw payload
// into id+doc pairs (via assignmentDocFromJson) for creates/updates, and
// passes deletes through untouched. Kept side-effect-free (no Firestore
// reads/writes) so it can be unit-tested directly — see
// assignment_save_batch.test.ts. The 'assignment.saveBatch' case in
// executeMutation() consumes this to build one atomic db.batch().
export function planAssignmentSaveBatch(payload: {
  creates?: Record<string, unknown>[];
  updates?: Record<string, unknown>[];
  deletes?: string[];
}): {
  creates: Array<{id: string; doc: Record<string, unknown>}>;
  updates: Array<{id: string; doc: Record<string, unknown>}>;
  deletes: string[];
} {
  const shape = (a: Record<string, unknown>) => ({
    id: requireString(a['id'], 'assignment.id'),
    doc: assignmentDocFromJson(a),
  });
  return {
    creates: (payload.creates ?? []).map(shape),
    updates: (payload.updates ?? []).map(shape),
    deletes: payload.deletes ?? [],
  };
}

// Pure helper for assignment.saveBatch's batch-aware duplicate-role check.
//
// validateAssignmentPayload's own duplicate-role check (see
// skipDuplicateRoleCheck above) only ever sees LIVE Firestore docs, one item
// at a time — it has no notion of the OTHER items in the same batch. That
// means a same-role swap (Medic#0: Dan->Ron, Medic#1: Ron->Dan) looks like a
// duplicate to each item when validated in isolation, even though the net
// result has no duplicate at all. This computes the batch's RESULTING
// per-event occupancy directly and flags any (eventId, roleType,
// teamMemberId) held by more than one assignment afterwards.
//
// Logic: start from `existing` (the live assignments for the affected
// events) MINUS every doc the batch rewrites or removes (deletes, update
// ids, create ids) -- its post-batch state is represented by the matching
// create/update entry instead (or, for deletes, by nothing). Add the
// batch's creates + updates (their NEW state) to what survives. Group the
// result by (eventId, roleType, teamMemberId) and return any group with
// more than one member.
//
// Kept side-effect-free (no Firestore reads) so it can be unit-tested
// directly -- see assignment_save_batch.test.ts. The 'assignment.saveBatch'
// case in executeMutation() reads the live docs and calls this.
export function findBatchDuplicateRoleAssignments(args: {
  existing: Array<{id: string; eventId: string; roleType: string; teamMemberId: string}>;
  creates: Array<{id: string; eventId: string; roleType: string; teamMemberId: string}>;
  updates: Array<{id: string; eventId: string; roleType: string; teamMemberId: string}>;
  deletes: string[];
  // Members with allowMultipleAssignments === true are exempt from this
  // check -- the identical exemption validateAssignmentPayload's own
  // single-item duplicate-role check already grants them (see
  // skipDuplicateRoleCheck above): they may legitimately hold the same role
  // twice at the same event. Any entry whose teamMemberId is in this set is
  // dropped before grouping, so it can never produce a flagged group.
  // Optional / defaults to no exemptions so existing callers/tests are
  // unaffected; 'assignment.saveBatch' always passes the real computed set.
  exemptMemberIds?: ReadonlySet<string>;
}): Array<{eventId: string; roleType: string; teamMemberId: string}> {
  const {existing, creates, updates, deletes, exemptMemberIds} = args;

  const removedIds = new Set<string>([
    ...deletes,
    ...updates.map((item) => item.id),
    ...creates.map((item) => item.id),
  ]);
  const survivingExisting = existing.filter((item) => !removedIds.has(item.id));

  // Drop exempt members' entries entirely -- with none left for a given
  // teamMemberId, no group (and therefore no false duplicate) can ever form
  // for them, no matter how many same-role slots they occupy.
  const resulting = [...survivingExisting, ...creates, ...updates].filter(
    (item) => !exemptMemberIds?.has(item.teamMemberId),
  );

  const groups = new Map<
    string,
    {eventId: string; roleType: string; teamMemberId: string; count: number}
  >();
  for (const item of resulting) {
    const key = `${item.eventId} ${item.roleType} ${item.teamMemberId}`;
    const group = groups.get(key);
    if (group) {
      group.count += 1;
    } else {
      groups.set(key, {
        eventId: item.eventId,
        roleType: item.roleType,
        teamMemberId: item.teamMemberId,
        count: 1,
      });
    }
  }

  return Array.from(groups.values())
    .filter((group) => group.count > 1)
    .map(({eventId, roleType, teamMemberId}) => ({eventId, roleType, teamMemberId}));
}

function assignmentLabelDocFromJson(
  label: Record<string, unknown>,
): Record<string, unknown> {
  return stripUndefined({
    id: label['id'],
    key: label['key'],
    hebrewName: label['hebrewName'],
    color: label['color'] ?? '#1565C0',
    sortOrder: label['sortOrder'] ?? 0,
    isActive: label['isActive'] ?? true,
    createdAt: toTimestamp(label['createdAt'], 'label.createdAt'),
    updatedAt: toTimestamp(label['updatedAt'], 'label.updatedAt'),
  });
}

function checklistNotesToFirestore(rawNotes: unknown): Array<Record<string, unknown>> {
  if (!Array.isArray(rawNotes)) return [];
  return rawNotes.map((note) => {
    const data = note as Record<string, unknown>;
    return stripUndefined({
      id: data['id'],
      content: data['content'],
      createdAt: toTimestamp(data['createdAt'], 'note.createdAt'),
      createdByTeamMemberId: data['createdByTeamMemberId'],
      createdByTeamMemberName: data['createdByTeamMemberName'] ?? null,
      authorRole: data['authorRole'] ?? null,
    });
  });
}

function checklistItemDocFromJson(item: Record<string, unknown>): Record<string, unknown> {
  return stripUndefined({
    eventId: item['eventId'],
    name: item['name'],
    responsibleId: item['responsibleId'],
    notes: checklistNotesToFirestore(item['notes']),
    ccIds: item['ccIds'] ?? [],
    status: item['status'] ?? false,
    createdAt: toTimestamp(item['createdAt'], 'checklistItem.createdAt'),
    updatedAt: toTimestamp(item['updatedAt'], 'checklistItem.updatedAt'),
    statusLastUpdatedAt: toTimestamp(
      item['statusLastUpdatedAt'],
      'checklistItem.statusLastUpdatedAt',
    ),
    createdByAdminId: item['createdByAdminId'] ?? null,
  });
}

function presetDocFromJson(preset: Record<string, unknown>): Record<string, unknown> {
  return stripUndefined({
    name: preset['name'],
    items: Array.isArray(preset['items']) ? preset['items'] : [],
    createdAt: toTimestamp(preset['createdAt'], 'preset.createdAt'),
    updatedAt: toTimestamp(preset['updatedAt'], 'preset.updatedAt'),
  });
}

function parseConstraint(constraint: Record<string, unknown>): Record<string, unknown> {
  return {
    ...constraint,
    startDate: asDate(constraint['startDate'], 'constraint.startDate'),
    endDate: constraint['endDate'] == null ? null : asDate(constraint['endDate'], 'constraint.endDate'),
    repeatEndDate:
      constraint['repeatEndDate'] == null
        ? null
        : asDate(constraint['repeatEndDate'], 'constraint.repeatEndDate'),
  };
}

function constraintMatchesDate(constraint: Record<string, unknown>, date: Date): boolean {
  const startDate = normalizeDayInIsrael(constraint['startDate'] as Date);
  const endDate = constraint['endDate'] == null
    ? startDate
    : normalizeDayInIsrael(constraint['endDate'] as Date);
  const repeatType = typeof constraint['repeatType'] === 'string' ? constraint['repeatType'] : null;
  const repeatDay = typeof constraint['repeatDay'] === 'number' ? constraint['repeatDay'] : null;
  const repeatEndDate = constraint['repeatEndDate'] == null
    ? null
    : normalizeDayInIsrael(constraint['repeatEndDate'] as Date);
  const target = normalizeDayInIsrael(date);

  if (repeatType == null) {
    return target >= startDate && target <= endDate;
  }

  if (repeatEndDate == null || target < startDate || target > repeatEndDate) {
    return false;
  }

  if (repeatType === 'daily') return true;
  if (repeatType === 'weekly') {
    const weekday = target.getUTCDay() === 0 ? 7 : target.getUTCDay();
    return repeatDay === weekday;
  }
  if (repeatType === 'monthly') {
    return repeatDay === target.getUTCDate();
  }
  return false;
}

function constraintBlocksEvent(
  constraint: Record<string, unknown>,
  eventData: Record<string, unknown>,
): boolean {
  const constraintStart = optionalString(constraint['startTime']);
  const constraintEnd = optionalString(constraint['endTime']);
  if (constraintStart == null && constraintEnd == null) {
    return true;
  }
  const eventStartRaw = requireString(
    typeof eventData['assemblyTime'] === 'string' &&
      (eventData['assemblyTime'] as string).length > 0
      ? eventData['assemblyTime']
      : eventData['startTime'],
    'event.startTime',
  );
  const eventEndRaw = requireString(eventData['endTime'], 'event.endTime');
  return timesOverlap(constraintStart, constraintEnd, eventStartRaw, eventEndRaw);
}

function memberAvailableForEvent(
  memberData: Record<string, unknown>,
  eventData: Record<string, unknown>,
): boolean {
  if (memberData['isArchived'] === true || memberData['isActive'] !== true) {
    return false;
  }

  const isPermanent = memberData['isPermanent'] === true;
  const constraints = Array.isArray(memberData['constraints'])
    ? memberData['constraints'].map((item) => parseConstraint(item as Record<string, unknown>))
    : [];
  const eventStart = asDate(eventData['startDate'], 'event.startDate');
  const eventEnd = asDate(eventData['endDate'], 'event.endDate');

  if (isPermanent) {
    for (let day = normalizeDayInIsrael(eventStart); day <= normalizeDayInIsrael(eventEnd); day = addDays(day, 1)) {
      for (const constraint of constraints) {
        if (constraint['status'] !== 'approved') continue;
        if (constraint['constraintType'] !== 'unavailability') continue;
        if (!constraintMatchesDate(constraint, day)) continue;
        if (constraintBlocksEvent(constraint, eventData)) {
          return false;
        }
      }
    }
    return true;
  }

  const availableEventIds = Array.isArray(memberData['availableEventIds'])
    ? memberData['availableEventIds'].map((value) => String(value))
    : [];
  if (availableEventIds.includes(requireString(eventData['id'], 'event.id'))) {
    return true;
  }

  for (let day = normalizeDayInIsrael(eventStart); day <= normalizeDayInIsrael(eventEnd); day = addDays(day, 1)) {
    let availableOnDay = false;
    for (const constraint of constraints) {
      if (constraint['status'] !== 'approved') continue;
      if (constraint['constraintType'] !== 'availability') continue;
      if (!constraintMatchesDate(constraint, day)) continue;
      if (constraintBlocksEvent(constraint, eventData)) {
        availableOnDay = true;
        break;
      }
    }
    if (!availableOnDay) {
      return false;
    }
  }
  return true;
}

async function validateAssignmentPayload(
  firestore: Firestore,
  collections: Collections,
  assignment: Record<string, unknown>,
  ignoreAssignmentId?: string,
  options?: {
    bypassAvailability?: boolean;
    // Skip ONLY the duplicate-role query below (FK existence, role-capability,
    // and the availability checks all still run). Used by
    // 'assignment.saveBatch', which re-checks duplicates itself across the
    // WHOLE batch (via findBatchDuplicateRoleAssignments) after all items are
    // known. A live, per-item Firestore query here can't see sibling items in
    // the same batch, so e.g. a same-role swap (A<->B across two slots) looks
    // like a duplicate to each item when checked in isolation. Defaults to
    // false, so assignment.insert / assignment.update are unaffected.
    skipDuplicateRoleCheck?: boolean;
  },
): Promise<void> {
  const eventId = requireString(assignment['eventId'], 'assignment.eventId');
  const teamMemberId = requireString(assignment['teamMemberId'], 'assignment.teamMemberId');
  const roleType = requireString(assignment['roleType'], 'assignment.roleType');
  const semanticLabelId = normalizeOptionalText(assignment['semanticLabelId']);

  const reads = [
    firestore.collection(collections.events).doc(eventId).get(),
    firestore.collection(collections.teamMembers).doc(teamMemberId).get(),
  ];
  if (semanticLabelId != null) {
    reads.push(
      firestore.collection(collections.assignmentLabels).doc(semanticLabelId).get(),
    );
  }

  const [eventDoc, memberDoc, semanticLabelDoc] = await Promise.all(reads);

  if (!eventDoc.exists) {
    throw new HttpError(400, 'אירוע לא נמצא');
  }
  if (!memberDoc.exists) {
    throw new HttpError(400, 'חבר צוות לא נמצא');
  }
  if (semanticLabelId != null && !semanticLabelDoc?.exists) {
    throw new HttpError(400, 'סיווג השיבוץ לא נמצא');
  }

  const eventData = eventDoc.data() ?? {};
  const memberData = memberDoc.data() ?? {};
  if (eventData[EVENT_DELETION_PENDING_FIELD] === true) {
    throw new HttpError(409, 'האירוע נמצא בתהליך מחיקה');
  }

  const roleCapabilities =
    (memberData['roleCapabilities'] as Record<string, unknown> | undefined) ?? {};
  if (roleCapabilities[roleType] !== true) {
    throw new HttpError(400, 'חבר/ת הצוות אינו/ה מוסמך/ת לתפקיד זה');
  }

  if (memberData['isActive'] !== true) {
    throw new HttpError(400, 'לא ניתן לשבץ חבר/ת צוות לא פעיל/ה');
  }

  if (
    memberData['allowMultipleAssignments'] !== true &&
    options?.skipDuplicateRoleCheck !== true
  ) {
    const duplicates = await firestore
      .collection(collections.assignments)
      .where('eventId', '==', eventId)
      .get();
    const hasDuplicate = duplicates.docs.some((doc) => {
      if (doc.id === ignoreAssignmentId) {
        return false;
      }

      const data = doc.data();
      return (
        data['teamMemberId'] === teamMemberId &&
        data['roleType'] === roleType
      );
    });
    if (hasDuplicate) {
      throw new HttpError(400, 'חבר/ת הצוות כבר משובץ/ת לתפקיד זה באירוע');
    }
  }

  if (
    options?.bypassAvailability !== true &&
    memberData['allowMultipleAssignments'] !== true &&
    !memberAvailableForEvent(memberData, eventData)
  ) {
    throw new HttpError(400, 'חבר/ת הצוות לא זמין/ה לאירוע זה');
  }
}

async function validateAssignmentMetadataPayload(
  firestore: Firestore,
  collections: Collections,
  payload: Record<string, unknown>,
): Promise<{
  notes: string;
  semanticLabelId: string | null;
  alternativePhoneNumber: string | null;
}> {
  const notes = typeof payload['notes'] === 'string' ? payload['notes'] : '';
  const semanticLabelId = normalizeOptionalText(payload['semanticLabelId']);

  if (semanticLabelId != null) {
    const semanticLabelDoc = await firestore
      .collection(collections.assignmentLabels)
      .doc(semanticLabelId)
      .get();
    if (!semanticLabelDoc.exists) {
      throw new HttpError(400, 'סיווג השיבוץ לא נמצא');
    }
  }

  return {
    notes,
    semanticLabelId,
    alternativePhoneNumber: normalizeOptionalText(payload['alternativePhoneNumber']),
  };
}

async function getUtilitiesListsDoc(): Promise<Record<string, unknown>> {
  const doc = await db.collection('utilities').doc('Lists').get();
  return doc.exists ? (doc.data() ?? {}) : {};
}

function getRolesArray(listsData: Record<string, unknown>): Array<Record<string, unknown>> {
  return Array.isArray(listsData['Roles'])
    ? (listsData['Roles'] as Array<Record<string, unknown>>)
    : [];
}

function getCategoriesArray(listsData: Record<string, unknown>): Array<Record<string, unknown>> {
  return Array.isArray(listsData['Categories'])
    ? (listsData['Categories'] as Array<Record<string, unknown>>)
    : [];
}

async function executeMutation(
  actor: ActorContext,
  environment: EnvironmentMode,
  collections: Collections,
  operation: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  switch (operation) {
    case 'teamMember.insert': {
      requireAdmin(actor);
      const member = payload['member'] as Record<string, unknown>;
      const memberId = requireString(member['id'], 'member.id');
      const nextMember = {
        ...teamMemberDocFromJson(member),
        passcodeLength: DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH,
      };
      await db.collection(collections.teamMembers).doc(memberId).set(nextMember);
      await upsertPrivatePasscodeCredential(
        collections,
        memberId,
        DEFAULT_TEAM_MEMBER_PASSCODE,
        DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH,
      );
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
        name: member['name'],
      }, {
        after: nextMember,
      });
      return {ok: true};
    }

    case 'teamMember.update': {
      const member = payload['member'] as Record<string, unknown>;
      const memberId = requireString(member['id'], 'member.id');
      const docRef = db.collection(collections.teamMembers).doc(memberId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }
      const existing = existingDoc.data() ?? {};
      let next = teamMemberDocFromJson(member, existing);
      if (!actor.isAdmin) {
        requireSelfOrAdmin(actor, memberId);
        next = {
          ...existing,
          phoneNumber: next['phoneNumber'] ?? null,
          email: next['email'] ?? null,
          birthday: next['birthday'] ?? null,
          vehicleInfo: next['vehicleInfo'] ?? null,
          updatedAt: next['updatedAt'],
        };
      }
      delete next['passcode'];
      // Constraints are owned by constraint.{add,edit,remove}. Stripping the field here
      // prevents teamMember.update (a full-document merge) from racing with — and clobbering —
      // concurrent constraint mutations dispatched from the same admin save (see modal flow).
      delete next['constraints'];
      await docRef.update(next);
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
        name: typeof next['name'] === 'string'
          ? next['name']
          : existing['name'],
      }, {
        before: existing,
        after: next,
      });
      return {ok: true};
    }

    case 'teamMember.updatePasscode': {
      const memberId = requireString(payload['memberId'], 'memberId');
      const passcode = requireString(payload['passcode'], 'passcode');
      const length = Number(payload['length']);
      const currentPasscode = optionalString(payload['currentPasscode']);
      requireSelfOrAdmin(actor, memberId);

      const teamRef = db.collection(collections.teamMembers).doc(memberId);
      const credentialRef = db.collection(collections.privateCredentials).doc(memberId);
      const teamDoc = await teamRef.get();
      if (!teamDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }
      const teamBefore = teamDoc.data() ?? {};
      const credentialDoc = await credentialRef.get();

      if (!actor.isAdmin) {
        const existingHash = credentialDoc.data()?.['passcodeHash'];
        const legacyPasscode = typeof teamBefore['passcode'] === 'string'
          ? teamBefore['passcode']
          : null;
        const hasExistingPasscode = typeof existingHash === 'string' ||
          (typeof legacyPasscode === 'string' && legacyPasscode.length > 0) ||
          teamBefore['passcodeLength'] != null;

        if (hasExistingPasscode) {
          let isCurrentPasscodeValid = false;

          if (typeof existingHash === 'string') {
            isCurrentPasscodeValid = currentPasscode != null &&
              verifyPasscode(currentPasscode, existingHash);
          } else if (typeof legacyPasscode === 'string' &&
              legacyPasscode.length > 0) {
            isCurrentPasscodeValid = currentPasscode === legacyPasscode;
          } else {
            throw new HttpError(
              409,
              'לא ניתן לאמת את קוד הגישה הנוכחי. יש לפנות למנהל/ת',
            );
          }

          if (!isCurrentPasscodeValid) {
            throw new HttpError(403, 'קוד הגישה הנוכחי שגוי');
          }
        }
      }

      await upsertPrivatePasscodeCredential(collections, memberId, passcode, length);

      await teamRef.update({
        passcodeLength: length,
        passcode: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      const teamAfter: Record<string, unknown> = {
        ...teamBefore,
        passcodeLength: length,
      };
      delete teamAfter['passcode'];
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {length}, {
        before: teamBefore,
        after: teamAfter,
      });
      return {ok: true};
    }

    case 'teamMember.clearPasscode': {
      const memberId = requireString(payload['memberId'], 'memberId');
      requireSelfOrAdmin(actor, memberId);
      const teamRef = db.collection(collections.teamMembers).doc(memberId);
      const teamDoc = await teamRef.get();
      if (!teamDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }
      const teamBefore = teamDoc.data() ?? {};
      await db.collection(collections.privateCredentials).doc(memberId).delete();
      await teamRef.update({
        passcodeLength: FieldValue.delete(),
        passcode: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      const teamAfter: Record<string, unknown> = {
        ...teamBefore,
      };
      delete teamAfter['passcodeLength'];
      delete teamAfter['passcode'];
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {}, {
        before: teamBefore,
        after: teamAfter,
      });
      return {ok: true};
    }

    case 'teamMember.getPasscode': {
      requireAdmin(actor);
      const memberId = requireString(payload['memberId'], 'memberId');
      const teamRef = db.collection(collections.teamMembers).doc(memberId);
      const credentialRef = db.collection(collections.privateCredentials).doc(memberId);
      const [teamDoc, credentialDoc] = await Promise.all([
        teamRef.get(),
        credentialRef.get(),
      ]);

      if (!teamDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }

      const teamData = teamDoc.data() ?? {};
      const credentialData = credentialDoc.data();
      const storedPasscode = getStoredPrivatePasscodeValue(credentialData);
      const storedLength =
        typeof credentialData?.['passcodeLength'] === 'number'
          ? credentialData['passcodeLength']
          : typeof teamData['passcodeLength'] === 'number'
            ? teamData['passcodeLength']
            : storedPasscode?.length ?? 0;

      if (storedPasscode != null) {
        await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
          revealed: true,
          length: storedLength,
        });
        return {
          ok: true,
          passcode: storedPasscode,
          length: storedLength,
        };
      }

      const legacyPasscode = typeof teamData['passcode'] === 'string' &&
          (teamData['passcode'] as string).length > 0
        ? (teamData['passcode'] as string)
        : null;

      if (legacyPasscode != null) {
        const length = typeof teamData['passcodeLength'] === 'number'
          ? teamData['passcodeLength']
          : legacyPasscode.length;
        await upsertPrivatePasscodeCredential(
          collections,
          memberId,
          legacyPasscode,
          length,
          {
            migratedFromLegacyFieldAt: FieldValue.serverTimestamp(),
          },
        );
        await teamRef.update({
          passcode: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
          revealed: true,
          length,
        });
        return {
          ok: true,
          passcode: legacyPasscode,
          length,
        };
      }

      if (credentialDoc.exists || teamData['passcodeLength'] != null) {
        throw new HttpError(
          409,
          'לא ניתן להציג את קוד הגישה הקיים. יש להגדיר קוד חדש',
        );
      }

      throw new HttpError(404, 'לא הוגדר קוד גישה');
    }

    case 'teamMember.delete': {
      requireAdmin(actor);
      const memberId = requireString(payload['memberId'], 'memberId');
      const docRef = db.collection(collections.teamMembers).doc(memberId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Team member not found');
      }
      const existing = existingDoc.data() ?? {};
      await docRef.delete();
      await db.collection(collections.privateCredentials).doc(memberId).delete().catch(() => undefined);
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
        name: existing['name'],
      }, {
        before: existing,
      });
      return {ok: true};
    }

    case 'teamMember.insertBatch': {
      requireAdmin(actor);
      const members = Array.isArray(payload['members']) ? payload['members'] : [];
      const batch = db.batch();
      for (const rawMember of members) {
        const member = rawMember as Record<string, unknown>;
        const memberId = requireString(member['id'], 'member.id');
        const nextMember = {
          ...teamMemberDocFromJson(member),
          passcodeLength: DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH,
        };
        batch.set(
          db.collection(collections.teamMembers).doc(memberId),
          nextMember,
        );
        batch.set(
          db.collection(collections.privateCredentials).doc(memberId),
          {
            passcodeHash: hashPasscode(DEFAULT_TEAM_MEMBER_PASSCODE),
            passcodeValue: DEFAULT_TEAM_MEMBER_PASSCODE,
            passcodeLength: DEFAULT_TEAM_MEMBER_PASSCODE_LENGTH,
            updatedAt: FieldValue.serverTimestamp(),
          },
        );
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'teamMemberBatch', actor.memberId, {
        count: members.length,
      });
      return {ok: true};
    }

    case 'constraint.updateStatus': {
      requireAdmin(actor);
      const constraintIdOrMemberId = requireString(payload['teamMemberIdOrConstraintId'], 'teamMemberIdOrConstraintId');
      const constraintIndexValue = payload['constraintIndex'];
      const newStatus = requireString(payload['newStatus'], 'newStatus');
      const note = optionalString(payload['note']);
      const wasAutoRejectedFromCalendar = payload['wasAutoRejectedFromCalendar'] === true;

      if (constraintIndexValue == null) {
        // Scan to locate the member that owns this constraint, then mutate via a transaction
        // so concurrent edits on the same member don't lose updates.
        const teamMembers = await db.collection(collections.teamMembers).get();
        for (const doc of teamMembers.docs) {
          const hasConstraint = Array.isArray(doc.data()['constraints']) &&
            (doc.data()['constraints'] as Array<Record<string, unknown>>)
              .some((c) => c['id'] === constraintIdOrMemberId);
          if (!hasConstraint) continue;
          const memberRef = doc.ref;
          const txResult = await db.runTransaction(async (transaction) => {
            const memberDoc = await transaction.get(memberRef);
            if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
            const data = memberDoc.data();
            const teamMemberName =
              typeof data?.['name'] === 'string' ? (data['name'] as string) : null;
            const constraints = Array.isArray(data?.['constraints'])
              ? [...(data['constraints'] as Array<Record<string, unknown>>)]
              : [];
            const index = constraints.findIndex((c) => c['id'] === constraintIdOrMemberId);
            if (index < 0) throw new HttpError(404, 'Constraint not found');
            const previousConstraint = constraints[index];
            const updated: Record<string, unknown> = {
              ...constraints[index],
              status: newStatus,
              ...(note != null ? {note} : {}),
              ...(payload['wasAutoRejectedFromCalendar'] != null
                ? {wasAutoRejectedFromCalendar}
                : {}),
            };
            constraints[index] = updated;
            transaction.update(memberRef, {
              constraints,
              updatedAt: FieldValue.serverTimestamp(),
            });
            return {previousConstraint, updated, teamMemberName};
          });
          await writeAuditLog(
            db,
            collections,
            actor,
            operation,
            getConstraintAuditEntityType(txResult.updated),
            constraintIdOrMemberId,
            buildConstraintAuditDetails(doc.id, txResult.teamMemberName, txResult.updated, {
              newStatus,
              semanticAction: getConstraintStatusSemanticAction(
                newStatus,
                wasAutoRejectedFromCalendar,
              ) ?? undefined,
            }),
            {
              before: txResult.previousConstraint,
              after: txResult.updated,
            },
          );
          return {ok: true};
        }
        throw new HttpError(404, 'Constraint not found');
      }

      const teamMemberId = constraintIdOrMemberId;
      const constraintIndex = Number(constraintIndexValue);
      const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
      // Transaction prevents lost updates when concurrent status updates land on the same member.
      // Note: we re-resolve the constraint by index inside the transaction; if the array shrank
      // between client-side index capture and the write, this surfaces an explicit error rather
      // than mutating the wrong constraint.
      const txResult = await db.runTransaction(async (transaction) => {
        const memberDoc = await transaction.get(memberRef);
        if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
        const data = memberDoc.data();
        const teamMemberName =
          typeof data?.['name'] === 'string' ? (data['name'] as string) : null;
        const constraints = Array.isArray(data?.['constraints'])
          ? [...(data['constraints'] as Array<Record<string, unknown>>)]
          : [];
        if (constraintIndex < 0 || constraintIndex >= constraints.length) {
          throw new HttpError(400, 'Invalid constraint index');
        }
        const previousConstraint = constraints[constraintIndex];
        const updated: Record<string, unknown> = {
          ...constraints[constraintIndex],
          status: newStatus,
          ...(note != null ? {note} : {}),
          ...(payload['wasAutoRejectedFromCalendar'] != null
            ? {wasAutoRejectedFromCalendar}
            : {}),
        };
        constraints[constraintIndex] = updated;
        transaction.update(memberRef, {
          constraints,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return {previousConstraint, updated, teamMemberName};
      });
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        getConstraintAuditEntityType(txResult.updated),
        String(txResult.updated['id']),
        buildConstraintAuditDetails(
          teamMemberId,
          txResult.teamMemberName,
          txResult.updated,
          {
            newStatus,
            semanticAction: getConstraintStatusSemanticAction(
              newStatus,
              wasAutoRejectedFromCalendar,
            ) ?? undefined,
          },
        ),
        {
          before: txResult.previousConstraint,
          after: txResult.updated,
        },
      );
      return {ok: true};
    }

    case 'constraint.add': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      const constraint = payload['constraint'] as Record<string, unknown>;
      const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
      const memberDoc = await memberRef.get();
      if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
      const teamMemberName =
        typeof memberDoc.data()?.['name'] === 'string'
          ? (memberDoc.data()?.['name'] as string)
          : null;
      await memberRef.update({
        constraints: FieldValue.arrayUnion(constraint),
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        getConstraintAuditEntityType(constraint),
        requireString(constraint['id'], 'constraint.id'),
        buildConstraintAuditDetails(teamMemberId, teamMemberName, constraint),
        {
          after: constraint,
        },
      );
      return {ok: true};
    }

    case 'constraint.edit': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      requireSelfOrAdmin(actor, teamMemberId);
      const updatedConstraint = payload['constraint'] as Record<string, unknown>;
      const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
      // Transaction prevents lost updates when multiple constraint edits arrive concurrently
      // (e.g. admin approving several pending requests in one save).
      const txResult = await db.runTransaction(async (transaction) => {
        const memberDoc = await transaction.get(memberRef);
        if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
        const data = memberDoc.data();
        const teamMemberName =
          typeof data?.['name'] === 'string' ? (data['name'] as string) : null;
        const constraints = Array.isArray(data?.['constraints'])
          ? [...(data['constraints'] as Array<Record<string, unknown>>)]
          : [];
        const index = constraints.findIndex((constraint) => constraint['id'] === constraintId);
        if (index < 0) throw new HttpError(404, 'Constraint not found');
        const previousConstraint = constraints[index];
        constraints[index] = updatedConstraint;
        transaction.update(memberRef, {
          constraints,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return {previousConstraint, teamMemberName};
      });
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        getConstraintAuditEntityType(updatedConstraint),
        constraintId,
        buildConstraintAuditDetails(
          teamMemberId,
          txResult.teamMemberName,
          updatedConstraint,
        ),
        {
          before: txResult.previousConstraint,
          after: updatedConstraint,
        },
      );
      return {ok: true};
    }

    case 'constraint.remove': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      requireSelfOrAdmin(actor, teamMemberId);
      const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
      // Transaction prevents lost updates when concurrent constraint mutations target the same member.
      const txResult = await db.runTransaction(async (transaction) => {
        const memberDoc = await transaction.get(memberRef);
        if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
        const data = memberDoc.data();
        const teamMemberName =
          typeof data?.['name'] === 'string' ? (data['name'] as string) : null;
        const constraints = Array.isArray(data?.['constraints'])
          ? [...(data['constraints'] as Array<Record<string, unknown>>)]
          : [];
        const removedConstraint =
          constraints.find((constraint) => constraint['id'] === constraintId) ?? null;
        const nextConstraints = constraints.filter((constraint) => constraint['id'] !== constraintId);
        transaction.update(memberRef, {
          constraints: nextConstraints,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return {removedConstraint, teamMemberName};
      });
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        getConstraintAuditEntityType(txResult.removedConstraint),
        constraintId,
        buildConstraintAuditDetails(
          teamMemberId,
          txResult.teamMemberName,
          txResult.removedConstraint,
        ),
        {
          before: txResult.removedConstraint,
        },
      );
      return {ok: true};
    }

    case 'event.insert': {
      requireAdmin(actor);
      const event = payload['event'] as Record<string, unknown>;
      const eventId = requireString(event['id'], 'event.id');
      const name = requireString(event['name'], 'event.name');
      const startDate = asCalendarDay(event['startDate'], 'event.startDate');
      const startOfTargetDay = Timestamp.fromDate(startDate);
      const endOfTargetDay = Timestamp.fromDate(addDays(startDate, 1));
      const duplicates = await db
        .collection(collections.events)
        .where('startDate', '>=', startOfTargetDay)
        .where('startDate', '<', endOfTargetDay)
        .get();
      const hasDuplicate = duplicates.docs.some((doc) => {
        const data = doc.data();
        return data['name'] === name;
      });
      if (hasDuplicate) {
        throw new HttpError(400, 'כבר קיים אירוע בשם זה בתאריך זה');
      }
      const nextEvent = eventDocFromJson(event);
      const eventBatch = db.batch();
      eventBatch.create(db.collection(collections.events).doc(eventId), nextEvent);
      markEventCalendarJob(eventBatch, collections, eventId, actor);
      await eventBatch.commit();
      await enqueueEventCalendarJob(environment, eventId, actor);
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {name}, {
        after: nextEvent,
      });
      return {ok: true};
    }

    case 'event.update': {
      const event = payload['event'] as Record<string, unknown>;
      const eventId = requireString(event['id'], 'event.id');
      const eventRef = db.collection(collections.events).doc(eventId);
      const existingDoc = await eventRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Event not found');
      }
      const existing = existingDoc.data() ?? {};
      if (existing[EVENT_DELETION_PENDING_FIELD] === true) {
        throw new HttpError(409, 'האירוע נמצא בתהליך מחיקה');
      }
      const existingParkingEditorIds = Array.isArray(existing['parkingEditorIds'])
        ? existing['parkingEditorIds'].map((value) => String(value))
        : [];

      if (!actor.isAdmin) {
        if (!existingParkingEditorIds.includes(actor.memberId)) {
          throw new HttpError(403, 'אין הרשאה לעדכן את מיקום החנייה של האירוע');
        }

        const nextParkingLocation = typeof event['parkingLocation'] === 'string'
          ? event['parkingLocation']
          : null;
        const nextUpdatedAt = toTimestamp(event['updatedAt'], 'event.updatedAt');

        await eventRef.update({
          parkingLocation: nextParkingLocation,
          updatedAt: nextUpdatedAt,
        });
        await writeAuditLog(db, collections, actor, operation, 'event', eventId, {
          name: typeof existing['name'] === 'string' ? existing['name'] : undefined,
          parkingLocationUpdated: true,
        }, {
          before: {
            parkingLocation: existing['parkingLocation'] ?? null,
            updatedAt: existing['updatedAt'] ?? null,
          },
          after: {
            parkingLocation: nextParkingLocation,
            updatedAt: nextUpdatedAt,
          },
        });
        return {ok: true};
      }

      const name = requireString(event['name'], 'event.name');
      const startDate = asCalendarDay(event['startDate'], 'event.startDate');
      const startOfTargetDay = Timestamp.fromDate(startDate);
      const endOfTargetDay = Timestamp.fromDate(addDays(startDate, 1));
      const duplicates = await db
        .collection(collections.events)
        .where('startDate', '>=', startOfTargetDay)
        .where('startDate', '<', endOfTargetDay)
        .get();
      const hasDuplicate = duplicates.docs.some((doc) => {
        if (doc.id === eventId) {
          return false;
        }

        const data = doc.data();
        return data['name'] === name;
      });
      if (hasDuplicate) {
        throw new HttpError(400, 'כבר קיים אירוע בשם זה בתאריך זה');
      }
      const nextEvent = eventDocFromJson(event);
      const eventBatch = db.batch();
      eventBatch.update(eventRef, nextEvent);
      markEventCalendarJob(eventBatch, collections, eventId, actor);
      await eventBatch.commit();
      await enqueueEventCalendarJob(environment, eventId, actor);
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {name}, {
        before: existing,
        after: nextEvent,
      });
      return {ok: true};
    }

    case 'event.delete': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      const eventRef = db.collection(collections.events).doc(eventId);
      const [eventDoc, assignmentSnapshot, checklistSnapshot] =
        await Promise.all([
          eventRef.get(),
          db.collection(collections.assignments).where('eventId', '==', eventId).get(),
          db.collection(collections.checklistItems).where('eventId', '==', eventId).get(),
        ]);
      if (!eventDoc.exists) {
        throw new HttpError(404, 'Event not found');
      }
      const existingEvent = eventDoc.data() ?? {};
      const existingAssignments = assignmentSnapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() ?? {},
      }));
      const existingChecklistItems = checklistSnapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() ?? {},
      }));

      const teamMemberNameCache = new Map<string, string | null>();
      const readTeamMemberName = async (memberId: string | null): Promise<string | null> => {
        if (memberId == null) {
          return null;
        }

        if (teamMemberNameCache.has(memberId)) {
          return teamMemberNameCache.get(memberId) ?? null;
        }

        const teamMemberData = await readTeamMemberById(db, collections, memberId);
        const teamMemberName = typeof teamMemberData?.['name'] === 'string'
          ? teamMemberData['name'] as string
          : null;
        teamMemberNameCache.set(memberId, teamMemberName);
        return teamMemberName;
      };

      const deletedAssignments = await Promise.all(existingAssignments.map(async (assignment) => {
        const teamMemberId = typeof assignment.data['teamMemberId'] === 'string'
          ? assignment.data['teamMemberId'] as string
          : null;
        const teamMemberName = await readTeamMemberName(teamMemberId);
        return buildAssignmentAuditDetails(assignment.data, {
          id: assignment.id,
          teamMemberName: teamMemberName ?? undefined,
        });
      }));

      const deletedChecklistItems = await Promise.all(existingChecklistItems.map(async (item) => {
        const responsibleId = typeof item.data['responsibleId'] === 'string'
          ? item.data['responsibleId'] as string
          : null;
        const responsibleName = await readTeamMemberName(responsibleId);
        return buildChecklistItemAuditDetails(item.data, {
          id: item.id,
          responsibleName: responsibleName ?? undefined,
        });
      }));
      const batch = db.batch();
      // Fence new assignment/checklist writes before the large relation
      // cascade. The Calendar job and deletion marker commit atomically, so a
      // crash at any later point is recoverable by the worker.
      batch.update(eventRef, {
        [EVENT_DELETION_PENDING_FIELD]: true,
        deletionRequestedAt: FieldValue.serverTimestamp(),
      });
      markEventCalendarJob(batch, collections, eventId, actor);
      await batch.commit();
      await enqueueEventCalendarJob(environment, eventId, actor);
      try {
        await finalizePendingEventDeletion(collections, eventId);
      } catch (cleanupError) {
        // The durable event job repeats this cascade before it touches Google.
        // Returning success is correct because the deletion marker and its
        // recovery intent have already committed atomically.
        console.error(
          `[event-delete-error] deferred relation cleanup eventId=${eventId}:`,
          cleanupError,
        );
      }
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, stripUndefined({
        name: existingEvent['name'],
        deletedAssignments:
          deletedAssignments.length > 0 ? deletedAssignments : undefined,
        deletedChecklistItems:
          deletedChecklistItems.length > 0 ? deletedChecklistItems : undefined,
      }), {
        before: existingEvent,
      });
      return {ok: true};
    }

    case 'event.insertBatch': {
      requireAdmin(actor);
      const events = Array.isArray(payload['events']) ? payload['events'] : [];
      // Validate and serialize the complete import before committing its first
      // chunk, so a malformed later row cannot leave a partial import behind.
      const preparedEvents = events.map((rawEvent) => {
        const event = rawEvent as Record<string, unknown>;
        return {
          eventId: requireString(event['id'], 'event.id'),
          data: eventDocFromJson(event),
        };
      });
      const eventIds = preparedEvents.map((event) => event.eventId);
      // Two writes per event (domain + durable calendar job), kept comfortably
      // below Firestore's 500-operation batch limit.
      for (let start = 0; start < preparedEvents.length; start += 200) {
        const batch = db.batch();
        for (const event of preparedEvents.slice(start, start + 200)) {
          batch.create(
            db.collection(collections.events).doc(event.eventId),
            event.data,
          );
          markEventCalendarJob(batch, collections, event.eventId, actor);
        }
        await batch.commit();
      }
      await Promise.all(eventIds.map((eventId) =>
        enqueueEventCalendarJob(environment, eventId, actor),
      ));
      await writeAuditLog(db, collections, actor, operation, 'eventBatch', actor.memberId, {
        count: events.length,
      });
      return {ok: true};
    }

    case 'assignment.insert': {
      requireAdmin(actor);
      const assignment = payload['assignment'] as Record<string, unknown>;
      const assignmentId = requireString(assignment['id'], 'assignment.id');
      await validateAssignmentPayload(db, collections, assignment, undefined, {
        bypassAvailability: payload['bypassAvailability'] === true,
      });
      const nextAssignment = assignmentDocFromJson(assignment);
      await db.runTransaction(async (transaction) => {
        await requireWritableEventInTransaction(
          transaction,
          collections,
          requireString(nextAssignment['eventId'], 'assignment.eventId'),
        );
        transaction.create(
          db.collection(collections.assignments).doc(assignmentId),
          nextAssignment,
        );
      });
      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId, {}, {
        after: nextAssignment,
      });
      return {ok: true};
    }

    case 'assignment.update': {
      requireAdmin(actor);
      const assignment = payload['assignment'] as Record<string, unknown>;
      const assignmentId = requireString(assignment['id'], 'assignment.id');
      const assignmentRef = db.collection(collections.assignments).doc(assignmentId);
      await validateAssignmentPayload(db, collections, assignment, assignmentId, {
        bypassAvailability: payload['bypassAvailability'] === true,
      });
      const nextAssignment = assignmentDocFromJson(assignment);
      let existing: Record<string, unknown> = {};
      await db.runTransaction(async (transaction) => {
        const current = await transaction.get(assignmentRef);
        if (!current.exists) throw new HttpError(404, 'Assignment not found');
        existing = current.data() ?? {};
        const sourceEventId = requireString(existing['eventId'], 'assignment.eventId');
        const destinationEventId = requireString(
          nextAssignment['eventId'],
          'assignment.eventId',
        );
        for (const eventId of new Set([sourceEventId, destinationEventId])) {
          await requireWritableEventInTransaction(transaction, collections, eventId);
        }
        transaction.update(assignmentRef, nextAssignment);
      });
      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId, {}, {
        before: existing,
        after: nextAssignment,
      });
      return {ok: true};
    }

    case 'assignment.updateMetadata': {
      requireAdmin(actor);
      const assignmentId = requireString(payload['assignmentId'], 'assignmentId');
      const assignmentRef = db.collection(collections.assignments).doc(assignmentId);
      const existingDoc = await assignmentRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment not found');
      }

      const existing = existingDoc.data() ?? {};
      const metadata = await validateAssignmentMetadataPayload(db, collections, payload);
      const updatedAt = Timestamp.now();

      await assignmentRef.update(stripUndefined({
        notes: metadata.notes,
        semanticLabelId: metadata.semanticLabelId,
        alternativePhoneNumber: metadata.alternativePhoneNumber ?? FieldValue.delete(),
        updatedAt,
      }));

      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId, {}, {
        before: existing,
        after: stripUndefined({
          ...existing,
          notes: metadata.notes,
          semanticLabelId: metadata.semanticLabelId,
          alternativePhoneNumber: metadata.alternativePhoneNumber,
          updatedAt,
        }),
      });
      return {ok: true};
    }

    case 'assignment.delete': {
      requireAdmin(actor);
      const assignmentId = requireString(payload['assignmentId'], 'assignmentId');
      const assignmentRef = db.collection(collections.assignments).doc(assignmentId);
      const existingDoc = await assignmentRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment not found');
      }
      const existing = existingDoc.data() ?? {};
      await assignmentRef.delete();
      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId, {}, {
        before: existing,
      });
      return {ok: true};
    }

    case 'assignment.deleteByEvent': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      const eventData = await readEventById(db, collections, eventId);
      const eventName = typeof eventData?.['name'] === 'string'
        ? eventData['name'] as string
        : null;
      const snapshot = await db.collection(collections.assignments).where('eventId', '==', eventId).get();
      const existingAssignments = snapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() ?? {},
      }));
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      const batchOperationId = randomUUID();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', eventId, {
        name: eventName ?? undefined,
        deletedCount: snapshot.docs.length,
      }, {}, {
        operationId: batchOperationId,
      });

      const teamMemberNameCache = new Map<string, string | null>();
      for (const assignment of existingAssignments) {
        const teamMemberId = typeof assignment.data['teamMemberId'] === 'string'
          ? assignment.data['teamMemberId'] as string
          : null;
        let teamMemberName: string | null = null;
        if (teamMemberId != null) {
          teamMemberName = teamMemberNameCache.get(teamMemberId) ?? null;
          if (!teamMemberNameCache.has(teamMemberId)) {
            const teamMemberData = await readTeamMemberById(db, collections, teamMemberId);
            teamMemberName = typeof teamMemberData?.['name'] === 'string'
              ? teamMemberData['name'] as string
              : null;
            teamMemberNameCache.set(teamMemberId, teamMemberName);
          }
        }

        await writeAuditLog(
          db,
          collections,
          actor,
          'assignment.delete',
          'assignment',
          assignment.id,
          buildAssignmentAuditDetails(assignment.data, {
            eventName: eventName ?? undefined,
            teamMemberName: teamMemberName ?? undefined,
          }),
          {
            before: assignment.data,
          },
          {
            parentOperationId: batchOperationId,
          },
        );
      }
      return {ok: true};
    }

    case 'assignment.deleteByPerson': {
      requireAdmin(actor);
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      const teamMemberData = await readTeamMemberById(db, collections, teamMemberId);
      const teamMemberName = typeof teamMemberData?.['name'] === 'string'
        ? teamMemberData['name'] as string
        : null;
      const snapshot = await db
        .collection(collections.assignments)
        .where('teamMemberId', '==', teamMemberId)
        .get();
      const existingAssignments = snapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() ?? {},
      }));
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      const batchOperationId = randomUUID();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', teamMemberId, {
        name: teamMemberName ?? undefined,
        deletedCount: snapshot.docs.length,
      }, {}, {
        operationId: batchOperationId,
      });

      const eventNameCache = new Map<string, string | null>();
      for (const assignment of existingAssignments) {
        const assignmentEventId = typeof assignment.data['eventId'] === 'string'
          ? assignment.data['eventId'] as string
          : null;
        let eventName: string | null = null;
        if (assignmentEventId != null) {
          eventName = eventNameCache.get(assignmentEventId) ?? null;
          if (!eventNameCache.has(assignmentEventId)) {
            const eventDoc = await readEventById(db, collections, assignmentEventId);
            eventName = typeof eventDoc?.['name'] === 'string'
              ? eventDoc['name'] as string
              : null;
            eventNameCache.set(assignmentEventId, eventName);
          }
        }

        await writeAuditLog(
          db,
          collections,
          actor,
          'assignment.delete',
          'assignment',
          assignment.id,
          buildAssignmentAuditDetails(assignment.data, {
            eventName: eventName ?? undefined,
            teamMemberName: teamMemberName ?? undefined,
          }),
          {
            before: assignment.data,
          },
          {
            parentOperationId: batchOperationId,
          },
        );
      }
      return {ok: true};
    }

    case 'assignment.deleteBatch': {
      requireAdmin(actor);
      const assignmentIds = Array.isArray(payload['assignmentIds']) ? payload['assignmentIds'] : [];
      const assignmentRefs = assignmentIds.map((rawId) =>
        db.collection(collections.assignments).doc(String(rawId)),
      );
      const assignmentDocs = assignmentRefs.length > 0 ? await db.getAll(...assignmentRefs) : [];
      const existingAssignments = assignmentDocs
        .filter((doc) => doc.exists)
        .map((doc) => ({
          id: doc.id,
          data: doc.data() ?? {},
        }));
      const batch = db.batch();
      for (const rawId of assignmentIds) {
        batch.delete(db.collection(collections.assignments).doc(String(rawId)));
      }
      await batch.commit();
      const batchOperationId = randomUUID();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', actor.memberId, {
        deletedCount: existingAssignments.length,
      }, {}, {
        operationId: batchOperationId,
      });

      const teamMemberNameCache = new Map<string, string | null>();
      const eventNameCache = new Map<string, string | null>();
      for (const assignment of existingAssignments) {
        const assignmentEventId = typeof assignment.data['eventId'] === 'string'
          ? assignment.data['eventId'] as string
          : null;
        const assignmentTeamMemberId = typeof assignment.data['teamMemberId'] === 'string'
          ? assignment.data['teamMemberId'] as string
          : null;

        let eventName: string | null = null;
        if (assignmentEventId != null) {
          eventName = eventNameCache.get(assignmentEventId) ?? null;
          if (!eventNameCache.has(assignmentEventId)) {
            const eventDoc = await readEventById(db, collections, assignmentEventId);
            eventName = typeof eventDoc?.['name'] === 'string'
              ? eventDoc['name'] as string
              : null;
            eventNameCache.set(assignmentEventId, eventName);
          }
        }

        let teamMemberName: string | null = null;
        if (assignmentTeamMemberId != null) {
          teamMemberName = teamMemberNameCache.get(assignmentTeamMemberId) ?? null;
          if (!teamMemberNameCache.has(assignmentTeamMemberId)) {
            const teamMemberDoc = await readTeamMemberById(db, collections, assignmentTeamMemberId);
            teamMemberName = typeof teamMemberDoc?.['name'] === 'string'
              ? teamMemberDoc['name'] as string
              : null;
            teamMemberNameCache.set(assignmentTeamMemberId, teamMemberName);
          }
        }

        await writeAuditLog(
          db,
          collections,
          actor,
          'assignment.delete',
          'assignment',
          assignment.id,
          buildAssignmentAuditDetails(assignment.data, {
            eventName: eventName ?? undefined,
            teamMemberName: teamMemberName ?? undefined,
          }),
          {
            before: assignment.data,
          },
          {
            parentOperationId: batchOperationId,
          },
        );
      }
      return {ok: true};
    }

    case 'assignment.insertBatch': {
      requireAdmin(actor);
      const assignments = Array.isArray(payload['assignments']) ? payload['assignments'] : [];
      const preparedAssignments: Array<{
        assignmentId: string;
        eventId: string;
        data: Record<string, unknown>;
      }> = [];
      for (const rawAssignment of assignments) {
        const assignment = rawAssignment as Record<string, unknown>;
        const assignmentId = requireString(assignment['id'], 'assignment.id');
        await validateAssignmentPayload(db, collections, assignment);
        const data = assignmentDocFromJson(assignment);
        preparedAssignments.push({
          assignmentId,
          eventId: requireString(data['eventId'], 'assignment.eventId'),
          data,
        });
      }
      await db.runTransaction(async (transaction) => {
        for (const eventId of new Set(
          preparedAssignments.map((assignment) => assignment.eventId),
        )) {
          await requireWritableEventInTransaction(transaction, collections, eventId);
        }
        for (const assignment of preparedAssignments) {
          transaction.create(
            db.collection(collections.assignments).doc(assignment.assignmentId),
            assignment.data,
          );
        }
      });
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', actor.memberId, {
        count: assignments.length,
      });
      return {ok: true};
    }

    case 'assignment.saveBatch': {
      requireAdmin(actor);
      const creates = (payload['creates'] as Record<string, unknown>[]) ?? [];
      const updates = (payload['updates'] as Record<string, unknown>[]) ?? [];
      const deletes = (payload['deletes'] as string[]) ?? [];

      // Validate every create/update up-front (reads happen before the batch).
      // skipDuplicateRoleCheck: true -- a live, per-item duplicate query can't
      // see sibling items in this same batch (e.g. a same-role swap looks
      // like a duplicate to each item checked in isolation). The batch-aware
      // equivalent (findBatchDuplicateRoleAssignments) runs below, once all
      // items are known.
      for (const a of creates) {
        requireString(a['id'], 'assignment.id');
        await validateAssignmentPayload(db, collections, a, undefined, {
          bypassAvailability: true,
          skipDuplicateRoleCheck: true,
        });
      }
      for (const a of updates) {
        const id = requireString(a['id'], 'assignment.id');
        await validateAssignmentPayload(db, collections, a, id, {
          bypassAvailability: true,
          skipDuplicateRoleCheck: true,
        });
      }

      const plan = planAssignmentSaveBatch({creates, updates, deletes});

      // Capture "before" state of updated/deleted docs for audit (also used
      // below to find which events updated/deleted docs currently belong to).
      const before = new Map<string, Record<string, unknown>>();
      for (const {id} of plan.updates) {
        const snap = await db.collection(collections.assignments).doc(id).get();
        if (snap.exists) before.set(id, snap.data() ?? {});
      }
      for (const id of plan.deletes) {
        const snap = await db.collection(collections.assignments).doc(id).get();
        if (snap.exists) before.set(id, snap.data() ?? {});
      }

      // Batch-aware duplicate-role check (see skipDuplicateRoleCheck above):
      // gather every event touched by this batch (creates/updates' target
      // event, plus whatever event the updated/deleted docs currently live
      // in), pull the LIVE assignments for exactly those events, and ask
      // findBatchDuplicateRoleAssignments whether the RESULTING per-event
      // occupancy -- after this batch applies -- has any (eventId, roleType,
      // teamMemberId) held more than once.
      const affectedEventIds = new Set<string>();
      for (const {doc} of plan.creates) {
        affectedEventIds.add(requireString(doc['eventId'], 'assignment.eventId'));
      }
      for (const {doc} of plan.updates) {
        affectedEventIds.add(requireString(doc['eventId'], 'assignment.eventId'));
      }
      for (const data of before.values()) {
        // Defensive typeof check (not optionalString/requireString, which
        // throw): this is an incidental read of the pre-existing doc, not
        // the payload being validated, so a malformed legacy doc should
        // never abort the save.
        const eventId = data['eventId'];
        if (typeof eventId === 'string') affectedEventIds.add(eventId);
      }

      const existingForAffectedEvents: Array<{
        id: string;
        eventId: string;
        roleType: string;
        teamMemberId: string;
      }> = [];
      const affectedEventIdList = Array.from(affectedEventIds);
      const FIRESTORE_IN_QUERY_LIMIT = 30;
      for (let i = 0; i < affectedEventIdList.length; i += FIRESTORE_IN_QUERY_LIMIT) {
        const chunk = affectedEventIdList.slice(i, i + FIRESTORE_IN_QUERY_LIMIT);
        if (chunk.length === 0) continue;
        const snapshot = await db
          .collection(collections.assignments)
          .where('eventId', 'in', chunk)
          .get();
        for (const doc of snapshot.docs) {
          const data = doc.data();
          const docEventId = data['eventId'];
          const docRoleType = data['roleType'];
          const docTeamMemberId = data['teamMemberId'];
          // Defensive: skip rather than throw on a malformed/legacy doc --
          // this is an incidental read of OTHER live assignments, not the
          // payload being validated, so it should never abort the save.
          if (
            typeof docEventId !== 'string' ||
            typeof docRoleType !== 'string' ||
            typeof docTeamMemberId !== 'string'
          ) {
            continue;
          }
          existingForAffectedEvents.push({
            id: doc.id,
            eventId: docEventId,
            roleType: docRoleType,
            teamMemberId: docTeamMemberId,
          });
        }
      }

      // Members with allowMultipleAssignments === true are exempt from the
      // duplicate-role check (see the identical exemption in
      // validateAssignmentPayload above) -- they may legitimately hold the
      // same role twice at the same event. That per-item exemption doesn't
      // reach the batch-aware check below on its own, so it's re-derived
      // here from the authoritative team-member docs (not trusted from the
      // payload) and threaded through explicitly.
      const distinctTeamMemberIds = new Set<string>([
        ...plan.creates.map(({doc}) =>
          requireString(doc['teamMemberId'], 'assignment.teamMemberId'),
        ),
        ...plan.updates.map(({doc}) =>
          requireString(doc['teamMemberId'], 'assignment.teamMemberId'),
        ),
      ]);
      const exemptMemberIds = new Set<string>();
      for (const memberId of distinctTeamMemberIds) {
        const memberData = await readTeamMemberById(db, collections, memberId);
        if (memberData?.['allowMultipleAssignments'] === true) {
          exemptMemberIds.add(memberId);
        }
      }

      const batchDuplicates = findBatchDuplicateRoleAssignments({
        existing: existingForAffectedEvents,
        creates: plan.creates.map(({id, doc}) => ({
          id,
          eventId: requireString(doc['eventId'], 'assignment.eventId'),
          roleType: requireString(doc['roleType'], 'assignment.roleType'),
          teamMemberId: requireString(doc['teamMemberId'], 'assignment.teamMemberId'),
        })),
        updates: plan.updates.map(({id, doc}) => ({
          id,
          eventId: requireString(doc['eventId'], 'assignment.eventId'),
          roleType: requireString(doc['roleType'], 'assignment.roleType'),
          teamMemberId: requireString(doc['teamMemberId'], 'assignment.teamMemberId'),
        })),
        deletes: plan.deletes,
        exemptMemberIds,
      });
      if (batchDuplicates.length > 0) {
        throw new HttpError(400, 'חבר/ת הצוות כבר משובץ/ת לתפקיד זה באירוע');
      }

      // One atomic batch (≤500 ops — a meeting is far under).
      const batch = db.batch();
      for (const {id, doc} of plan.creates) {
        batch.create(db.collection(collections.assignments).doc(id), doc);
      }
      for (const {id, doc} of plan.updates) {
        batch.update(db.collection(collections.assignments).doc(id), doc);
      }
      for (const id of plan.deletes) {
        batch.delete(db.collection(collections.assignments).doc(id));
      }
      await batch.commit();

      // Audit each op (best-effort, after the atomic commit succeeded).
      for (const {id, doc} of plan.creates) {
        await writeAuditLog(db, collections, actor, 'assignment.insert', 'assignment', id, {}, {
          after: doc,
        });
      }
      for (const {id, doc} of plan.updates) {
        await writeAuditLog(db, collections, actor, 'assignment.update', 'assignment', id, {}, {
          before: before.get(id) ?? {},
          after: doc,
        });
      }
      for (const id of plan.deletes) {
        await writeAuditLog(db, collections, actor, 'assignment.delete', 'assignment', id, {}, {
          before: before.get(id) ?? {},
        });
      }

      return {
        ok: true,
        counts: {
          created: plan.creates.length,
          updated: plan.updates.length,
          deleted: plan.deletes.length,
        },
      };
    }

    case 'utility.clearAllData': {
      requireAdmin(actor);
      if (collections.teamMembers.startsWith('test_') == false) {
        throw new HttpError(403, 'clearAllData is only allowed in test mode');
      }
      const collectionNames = [
        collections.teamMembers,
        collections.events,
        collections.assignments,
        collections.assignmentLabels,
        collections.checklistItems,
        collections.presets,
        collections.calendarSync,
        collections.eventCalendarSync,
        collections.eventCalendarJobs,
        collections.calendarMaintenanceJobs,
        collections.privateCredentials,
        collections.privateSessions,
        collections.privateGoogleCalendarAuth,
      ];
      for (const collectionName of collectionNames) {
        while (true) {
          const snapshot = await db.collection(collectionName).limit(400).get();
          if (snapshot.empty) break;
          if (collectionName === collections.calendarMaintenanceJobs) {
            for (const document of snapshot.docs) {
              await deleteGuestCleanupPartDocuments(document.ref);
            }
          }
          const batch = db.batch();
          for (const doc of snapshot.docs) {
            batch.delete(doc.ref);
          }
          await batch.commit();
        }
      }
      await writeAuditLog(db, collections, actor, operation, 'utility', actor.memberId);
      return {ok: true};
    }

    case 'calendar.saveSyncState': {
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      await db.collection(collections.calendarSync).doc(constraintId).set({
        calendarEventId: requireString(payload['calendarEventId'], 'calendarEventId'),
        teamMemberId,
        status: requireString(payload['status'], 'status'),
        syncedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        retryCount: 0,
        errorMessage: null,
      });
      return {ok: true};
    }

    case 'calendar.updateSyncStatus': {
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      const existingDoc = await db.collection(collections.calendarSync).doc(constraintId).get();
      const teamMemberId = requireString(existingDoc.data()?.['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      await existingDoc.ref.update(stripUndefined({
        status: requireString(payload['status'], 'status'),
        updatedAt: FieldValue.serverTimestamp(),
        errorMessage: optionalString(payload['errorMessage']),
        retryCount: payload['retryCount'],
      }));
      return {ok: true};
    }

    case 'calendar.removeSyncState': {
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      const existingDoc = await db.collection(collections.calendarSync).doc(constraintId).get();
      const teamMemberId = requireString(existingDoc.data()?.['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      await existingDoc.ref.delete();
      return {ok: true};
    }

    case 'calendar.atomicCheckAndSetSyncState': {
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      const result = await db.runTransaction(async (transaction) => {
        const ref = db.collection(collections.calendarSync).doc(constraintId);
        const snapshot = await transaction.get(ref);
        if (snapshot.exists && snapshot.data()?.['status'] === 'synced') {
          return {
            action: 'update',
            calendarEventId: snapshot.data()?.['calendarEventId'] ?? null,
            teamMemberId: snapshot.data()?.['teamMemberId'] ?? null,
          };
        }
        transaction.set(ref, {
          calendarEventId: '',
          teamMemberId,
          status: 'pending',
          syncedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          retryCount: 0,
          errorMessage: null,
          reservedBy: Date.now(),
        });
        return {
          action: 'create',
          calendarEventId: null,
          teamMemberId,
        };
      });
      return result as Record<string, unknown>;
    }

    case 'calendar.saveEventSyncState': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      await markAndEnqueueEventCalendarJobs(environment, [eventId], actor);
      return {ok: true};
    }

    case 'calendar.removeEventSyncState': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      await markAndEnqueueEventCalendarJobs(environment, [eventId], actor);
      return {ok: true};
    }

    case 'checklist.insert': {
      requireAdmin(actor);
      const item = payload['item'] as Record<string, unknown>;
      const itemId = requireString(item['id'], 'item.id');
      const nextItem = checklistItemDocFromJson(item);
      await db.runTransaction(async (transaction) => {
        await requireWritableEventInTransaction(
          transaction,
          collections,
          requireString(nextItem['eventId'], 'checklistItem.eventId'),
        );
        transaction.create(
          db.collection(collections.checklistItems).doc(itemId),
          nextItem,
        );
      });
      await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId, {
        name: item['name'],
      }, {
        after: nextItem,
      });
      return {ok: true};
    }

    case 'checklist.update': {
      const item = payload['item'] as Record<string, unknown>;
      const itemId = requireString(item['id'], 'item.id');
      const docRef = db.collection(collections.checklistItems).doc(itemId);
      const fallbackNow = new Date().toISOString();
      let existing: Record<string, unknown> = {};
      let nextItem: Record<string, unknown> = {};
      await db.runTransaction(async (transaction) => {
        const current = await transaction.get(docRef);
        if (!current.exists) throw new HttpError(404, 'Checklist item not found');
        existing = current.data() ?? {};
        const isResponsible = existing['responsibleId'] === actor.memberId;
        const ccIds = Array.isArray(existing['ccIds'])
          ? existing['ccIds'].map(String)
          : [];
        if (!actor.isAdmin && !isResponsible && !ccIds.includes(actor.memberId)) {
          throw new HttpError(403, 'אין לך הרשאה לערוך את הפריט');
        }

        const sourceEventId = requireString(
          existing['eventId'],
          'checklistItem.eventId',
        );
        if (actor.isAdmin || isResponsible) {
          nextItem = checklistItemDocFromJson(item);
          const destinationEventId = requireString(
            nextItem['eventId'],
            'checklistItem.eventId',
          );
          for (const eventId of new Set([sourceEventId, destinationEventId])) {
            await requireWritableEventInTransaction(transaction, collections, eventId);
          }
          transaction.update(docRef, nextItem);
          return;
        }

        const statusUpdate = {
          status: item['status'] ?? existing['status'] ?? false,
          statusLastUpdatedAt: toTimestamp(
            item['statusLastUpdatedAt'] ?? fallbackNow,
            'item.statusLastUpdatedAt',
          ),
          updatedAt: toTimestamp(item['updatedAt'] ?? fallbackNow, 'item.updatedAt'),
        };
        nextItem = {...existing, ...statusUpdate};
        await requireWritableEventInTransaction(transaction, collections, sourceEventId);
        transaction.update(docRef, statusUpdate);
      });
      const semanticAction = getChecklistUpdateSemanticAction(existing, nextItem);
      await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId, stripUndefined({
        name: item['name'] ?? existing['name'],
        semanticAction,
      }), {
        before: existing,
        after: nextItem,
      });
      return {ok: true};
    }

    case 'checklist.delete': {
      requireAdmin(actor);
      const itemId = requireString(payload['itemId'], 'itemId');
      const docRef = db.collection(collections.checklistItems).doc(itemId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Checklist item not found');
      }
      const existing = existingDoc.data() ?? {};
      await docRef.delete();
      await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId, {
        name: existing['name'],
      }, {
        before: existing,
      });
      return {ok: true};
    }

    case 'checklist.deleteByEvent': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      const snapshot = await db.collection(collections.checklistItems).where('eventId', '==', eventId).get();
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'checklistItemBatch', eventId, {
        deletedCount: snapshot.docs.length,
      });
      return {ok: true};
    }

    case 'checklist.addNote': {
      const checklistItemId = requireString(payload['checklistItemId'], 'checklistItemId');
      const noteData = payload['noteData'] as Record<string, unknown>;
      const docRef = db.collection(collections.checklistItems).doc(checklistItemId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) throw new HttpError(404, 'Checklist item not found');
      const existing = existingDoc.data() ?? {};
      const isResponsible = existing['responsibleId'] === actor.memberId;
      const ccIds = Array.isArray(existing['ccIds']) ? existing['ccIds'].map(String) : [];
      if (!actor.isAdmin && !isResponsible && !ccIds.includes(actor.memberId)) {
        throw new HttpError(403, 'אין לך הרשאה להוסיף הערה לפריט');
      }
      const firestoreNote = checklistNotesToFirestore([noteData])[0];
      await docRef.update({
        notes: FieldValue.arrayUnion(firestoreNote),
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(
        db,
        collections,
        actor,
        operation,
        'checklistNote',
        String(firestoreNote['id'] ?? checklistItemId),
        {
          checklistItemId,
          checklistItemName: existing['name'],
        },
        {
          after: firestoreNote,
        },
      );
      return {ok: true};
    }

    case 'preset.insert': {
      requireAdmin(actor);
      const preset = payload['preset'] as Record<string, unknown>;
      const presetId = requireString(preset['id'], 'preset.id');
      const nextPreset = presetDocFromJson(preset);
      await db.collection(collections.presets).doc(presetId).set(nextPreset);
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId, {
        name: preset['name'],
      }, {
        after: nextPreset,
      });
      return {ok: true};
    }

    case 'preset.update': {
      requireAdmin(actor);
      const preset = payload['preset'] as Record<string, unknown>;
      const presetId = requireString(preset['id'], 'preset.id');
      const presetRef = db.collection(collections.presets).doc(presetId);
      const existingDoc = await presetRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Preset not found');
      }
      const existing = existingDoc.data() ?? {};
      const nextPreset = presetDocFromJson(preset);
      await presetRef.update(nextPreset);
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId, {
        name: preset['name'],
      }, {
        before: existing,
        after: nextPreset,
      });
      return {ok: true};
    }

    case 'preset.delete': {
      requireAdmin(actor);
      const presetId = requireString(payload['presetId'], 'presetId');
      const presetRef = db.collection(collections.presets).doc(presetId);
      const existingDoc = await presetRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Preset not found');
      }
      const existing = existingDoc.data() ?? {};
      await presetRef.delete();
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId, {
        name: existing['name'],
      }, {
        before: existing,
      });
      return {ok: true};
    }

    case 'preset.loadIntoEvent': {
      requireAdmin(actor);
      const presetId = requireString(payload['presetId'], 'presetId');
      const eventId = requireString(payload['eventId'], 'eventId');
      const creatorAdminId = requireString(payload['creatorAdminId'], 'creatorAdminId');
      const presetDoc = await db.collection(collections.presets).doc(presetId).get();
      if (!presetDoc.exists) throw new HttpError(404, 'Preset not found');
      const preset = presetDoc.data() ?? {};
      const items = Array.isArray(preset['items']) ? preset['items'] : [];
      const now = new Date().toISOString();
      await db.runTransaction(async (transaction) => {
        await requireWritableEventInTransaction(transaction, collections, eventId);
        for (const rawItem of items) {
          const item = rawItem as Record<string, unknown>;
          const checklistItemId = randomUUID();
          const notes = typeof item['adminNote'] === 'string' &&
              item['adminNote'].trim().length > 0
            ? [
                {
                  id: randomUUID(),
                  content: item['adminNote'],
                  createdAt: Timestamp.fromDate(new Date(now)),
                  createdByTeamMemberId: creatorAdminId,
                  createdByTeamMemberName: null,
                  authorRole: 'מנהל',
                },
              ]
            : [];
          transaction.create(db.collection(collections.checklistItems).doc(checklistItemId), {
            eventId,
            name: item['name'],
            responsibleId: item['responsibleId'],
            ccIds: Array.isArray(item['ccIds']) ? item['ccIds'] : [],
            notes,
            status: false,
            createdAt: Timestamp.fromDate(new Date(now)),
            updatedAt: Timestamp.fromDate(new Date(now)),
            statusLastUpdatedAt: Timestamp.fromDate(new Date(now)),
            createdByAdminId: creatorAdminId,
          });
        }
      });
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId, {
        eventId,
        count: items.length,
      });
      return {ok: true};
    }

    case 'assignmentLabel.insert': {
      requireAdmin(actor);
      const label = payload['label'] as Record<string, unknown>;
      const labelId = requireString(label['id'], 'label.id');
      const nextLabel = assignmentLabelDocFromJson(label);
      await db.collection(collections.assignmentLabels).doc(labelId).set(nextLabel);
      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', labelId, {
        name: label['hebrewName'],
      }, {
        after: nextLabel,
      });
      return {ok: true};
    }

    case 'assignmentLabel.update': {
      requireAdmin(actor);
      const label = payload['label'] as Record<string, unknown>;
      const labelId = requireString(label['id'], 'label.id');
      const labelRef = db.collection(collections.assignmentLabels).doc(labelId);
      const existingDoc = await labelRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment label not found');
      }
      const existing = existingDoc.data() ?? {};
      const nextLabel = assignmentLabelDocFromJson(label);
      await labelRef.update(nextLabel);
      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', labelId, {
        name: label['hebrewName'],
      }, {
        before: existing,
        after: nextLabel,
      });
      return {ok: true};
    }

    case 'assignmentLabel.archive':
    case 'assignmentLabel.restore': {
      requireAdmin(actor);
      const labelId = requireString(payload['labelId'], 'labelId');
      const labelRef = db.collection(collections.assignmentLabels).doc(labelId);
      const existingDoc = await labelRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment label not found');
      }
      const existing = existingDoc.data() ?? {};
      const nextLabel = {
        ...existing,
        isActive: operation === 'assignmentLabel.restore',
        updatedAt: FieldValue.serverTimestamp(),
      };
      await labelRef.update({
        isActive: operation === 'assignmentLabel.restore',
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', labelId, {
        name: existing['hebrewName'],
      }, {
        before: existing,
        after: nextLabel,
      });
      return {ok: true};
    }

    case 'assignmentLabel.delete': {
      requireAdmin(actor);
      const labelId = requireString(payload['labelId'], 'labelId');
      const labelRef = db.collection(collections.assignmentLabels).doc(labelId);
      const existingDoc = await labelRef.get();
      if (!existingDoc.exists) {
        throw new HttpError(404, 'Assignment label not found');
      }
      const existing = existingDoc.data() ?? {};

      const assignmentsSnapshot = await db
        .collection(collections.assignments)
        .where('semanticLabelId', '==', labelId)
        .get();

      const assignmentDocs = assignmentsSnapshot.docs;
      const chunkSize = 400;
      for (let index = 0; index < assignmentDocs.length; index += chunkSize) {
        const batch = db.batch();
        for (const assignmentDoc of assignmentDocs.slice(index, index + chunkSize)) {
          batch.update(assignmentDoc.ref, {
            semanticLabelId: null,
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      await labelRef.delete();

      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', labelId, {
        name: existing['hebrewName'],
        clearedAssignmentsCount: assignmentDocs.length,
      }, {
        before: existing,
      });
      return {ok: true};
    }

    case 'assignmentLabel.reorder': {
      requireAdmin(actor);
      const labelIdToSortOrder = payload['labelIdToSortOrder'] as Record<string, unknown>;
      const entries = Object.entries(labelIdToSortOrder);
      const batch = db.batch();
      for (const [labelId, sortOrder] of entries) {
        if (typeof sortOrder !== 'number' || !Number.isFinite(sortOrder)) {
          throw new Error(`Missing or invalid labelIdToSortOrder.${labelId}`);
        }
        batch.update(db.collection(collections.assignmentLabels).doc(labelId), {
          sortOrder,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'assignmentLabel', actor.memberId, {
        count: entries.length,
      });
      return {ok: true};
    }

    case 'role.insert':
    case 'role.update':
    case 'role.archive':
    case 'role.restore':
    case 'role.delete':
    case 'role.reorder':
    case 'role.seed': {
      requireAdmin(actor);
      const listsRef = db.collection('utilities').doc('Lists');
      const listsData = await getUtilitiesListsDoc();
      const previousRoles = getRolesArray(listsData);
      let roles = getRolesArray(listsData);
      let auditEntityId = actor.memberId;
      let auditEntityType = 'role';
      let auditDetails: Record<string, unknown> = {
        count: roles.length,
      };
      let auditBefore: Record<string, unknown> | null = null;
      let auditAfter: Record<string, unknown> | null = null;

      if (operation === 'role.insert') {
        const role = payload['role'] as Record<string, unknown>;
        const roleId = requireString(role['id'], 'role.id');
        auditEntityId = roleId;
        auditDetails = {
          count: roles.length + 1,
          name: role['hebrewName'],
        };
        auditAfter = role;
        roles = [...roles, role];
      } else if (operation === 'role.update') {
        const role = payload['role'] as Record<string, unknown>;
        const roleId = requireString(role['id'], 'role.id');
        auditEntityId = roleId;
        auditBefore = roles.find((item) => item['id'] === roleId) ?? null;
        auditAfter = role;
        auditDetails = {
          count: roles.length,
          name: role['hebrewName'],
        };
        roles = roles.map((item) => (item['id'] === roleId ? role : item));
      } else if (operation === 'role.archive' || operation === 'role.restore') {
        const roleId = requireString(payload['roleId'], 'roleId');
        auditEntityId = roleId;
        auditBefore = roles.find((item) => item['id'] === roleId) ?? null;
        roles = roles.map((item) => {
          if (item['id'] !== roleId) return item;
          return {
            ...item,
            isArchived: operation === 'role.archive',
            isVisible: operation === 'role.restore' ? true : item['isVisible'],
            updatedAt: new Date().toISOString(),
          };
        });
        auditAfter = roles.find((item) => item['id'] === roleId) ?? null;
        auditDetails = {
          count: roles.length,
          name: auditAfter?.['hebrewName'] ?? auditBefore?.['hebrewName'],
        };
      } else if (operation === 'role.delete') {
        const roleId = requireString(payload['roleId'], 'roleId');
        auditEntityId = roleId;
        auditBefore = roles.find((item) => item['id'] === roleId) ?? null;
        auditDetails = {
          count: Math.max(roles.length - 1, 0),
          name: auditBefore?.['hebrewName'],
        };
        roles = roles.filter((item) => item['id'] !== roleId);
      } else if (operation === 'role.reorder') {
        const sortOrderMap = payload['roleIdToSortOrder'] as Record<string, number>;
        auditEntityType = 'roleBatch';
        auditDetails = {
          count: roles.length,
        };
        roles = roles.map((item) => ({
          ...item,
          sortOrder: sortOrderMap[String(item['id'])] ?? item['sortOrder'],
          updatedAt: new Date().toISOString(),
        }));
        auditBefore = {roles: previousRoles};
        auditAfter = {roles};
      } else if (operation === 'role.seed') {
        if (roles.length > 0) return {ok: true};
        const seedRoles = Array.isArray(payload['roles']) ? payload['roles'] : [];
        auditEntityType = 'roleBatch';
        auditDetails = {
          count: seedRoles.length,
        };
        auditAfter = {roles: seedRoles};
        roles = seedRoles as Array<Record<string, unknown>>;
      }

      await listsRef.set({Roles: roles}, {merge: true});
      await writeAuditLog(db, collections, actor, operation, auditEntityType, auditEntityId, auditDetails, {
        before: auditBefore,
        after: auditAfter,
      });
      return {ok: true};
    }

    case 'category.insert':
    case 'category.update':
    case 'category.delete':
    case 'category.permanentlyDelete':
    case 'category.restore': {
      requireAdmin(actor);
      const listsRef = db.collection('utilities').doc('Lists');
      const listsData = await getUtilitiesListsDoc();
      let categories = getCategoriesArray(listsData);
      let auditEntityId = actor.memberId;
      let auditDetails: Record<string, unknown> = {
        count: categories.length,
      };
      let auditBefore: Record<string, unknown> | null = null;
      let auditAfter: Record<string, unknown> | null = null;

      if (operation === 'category.insert') {
        const category = payload['category'] as Record<string, unknown>;
        const categoryId = requireString(category['id'], 'category.id');
        auditEntityId = categoryId;
        auditDetails = {
          count: categories.length + 1,
          name: category['name'],
        };
        auditAfter = category;
        categories = [...categories, category];
      } else if (operation === 'category.update') {
        const category = payload['category'] as Record<string, unknown>;
        const categoryId = requireString(category['id'], 'category.id');
        auditEntityId = categoryId;
        auditBefore = categories.find((item) => item['id'] === categoryId) ?? null;
        auditAfter = category;
        auditDetails = {
          count: categories.length,
          name: category['name'],
        };
        categories = categories.map((item) => (item['id'] === categoryId ? category : item));
      } else {
        const categoryId = requireString(payload['categoryId'], 'categoryId');
        auditEntityId = categoryId;
        auditBefore = categories.find((item) => item['id'] === categoryId) ?? null;
        if (operation === 'category.permanentlyDelete') {
          auditDetails = {
            count: Math.max(categories.length - 1, 0),
            name: auditBefore?.['name'],
          };
          categories = categories.filter((item) => item['id'] !== categoryId);
        } else {
          categories = categories.map((item) => {
            if (item['id'] !== categoryId) return item;
            return {
              ...item,
              isArchived: operation === 'category.delete',
              updatedAt: new Date().toISOString(),
            };
          });
          auditAfter = categories.find((item) => item['id'] === categoryId) ?? null;
          auditDetails = {
            count: categories.length,
            name: auditAfter?.['name'] ?? auditBefore?.['name'],
          };
        }
      }

      await listsRef.set({Categories: categories}, {merge: true});
      await writeAuditLog(db, collections, actor, operation, 'category', auditEntityId, auditDetails, {
        before: auditBefore,
        after: auditAfter,
      });
      return {ok: true};
    }

    default:
      throw new HttpError(400, `Unsupported operation: ${operation}`);
  }
}

class HttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

app.post('/auth/list-members', async (request: Request, response: Response) => {
  try {
    const environment = getEnvironmentMode(request.body?.environment);
    const collections = getCollections(environment);
    const snapshot = await db.collection(collections.teamMembers).orderBy('name').get();
    const members = snapshot.docs
      .map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          uniqueKey: data['uniqueKey'] ?? '',
          name: data['name'] ?? '',
          isActive: data['isActive'] === true,
          hasPasscode: data['passcodeLength'] != null,
          passcodeLength: data['passcodeLength'] ?? null,
          allowMultipleAssignments: data['allowMultipleAssignments'] === true,
        };
      })
      .filter((member) => member.allowMultipleAssignments !== true);
    response.json({members});
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/auth/sign-in', async (request: Request, response: Response) => {
  try {
    const uniqueKey = requireString(request.body?.uniqueKey, 'uniqueKey');
    const passcode = requireString(request.body?.passcode, 'passcode');
    const environment = getEnvironmentMode(request.body?.environment);
    const collections = getCollections(environment);
    const memberResult = await readTeamMemberByUniqueKey(db, collections, uniqueKey);

    if (memberResult == null) {
      throw new HttpError(404, 'משתמש לא נמצא');
    }

    const memberData = memberResult.data;
    if (memberData['isActive'] !== true) {
      throw new HttpError(403, 'לא ניתן להתחבר עם משתמש לא פעיל');
    }

    const credentialRef = db.collection(collections.privateCredentials).doc(memberResult.id);
    const credentialDoc = await credentialRef.get();
    let isValid = false;
    let length: number | null =
      typeof memberData['passcodeLength'] === 'number'
        ? memberData['passcodeLength']
        : null;

    if (credentialDoc.exists) {
      const credentialData = credentialDoc.data();
      const hash = credentialData?.['passcodeHash'];
      if (typeof hash === 'string') {
        isValid = verifyPasscode(passcode, hash);
        length = typeof credentialData?.['passcodeLength'] === 'number'
          ? credentialData['passcodeLength']
          : length;
        if (isValid) {
          await credentialRef.set({
            passcodeValue: passcode,
            passcodeLength: length ?? passcode.length,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      }
    } else if (typeof memberData['passcode'] === 'string' && (memberData['passcode'] as string).length > 0) {
      isValid = memberData['passcode'] === passcode;
      if (isValid) {
        await upsertPrivatePasscodeCredential(
          collections,
          memberResult.id,
          passcode,
          length ?? passcode.length,
          {
            migratedFromLegacyFieldAt: FieldValue.serverTimestamp(),
          },
        );
        await db.collection(collections.teamMembers).doc(memberResult.id).update({
          passcode: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }

    if (!isValid) {
      throw new HttpError(403, 'קוד הגישה שגוי');
    }

    await ensureFirebaseAuthUser(memberResult.id, memberData);
    const customToken = await auth.createCustomToken(
      memberResult.id,
      stripUndefined({
        uniqueKey,
        isAdmin: memberData['isAdmin'] === true,
      }),
    );

    response.json({
      ok: true,
      customToken,
      memberId: memberResult.id,
      uniqueKey,
      passcodeLength: length ?? passcode.length,
      isAdmin: memberData['isAdmin'] === true,
    });
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/auth/validate-session', async (request: Request, response: Response) => {
  try {
    const auth = await authenticateRequest(request);
    response.json({
      ok: true,
      memberId: auth.actor.memberId,
      uniqueKey: auth.actor.uniqueKey,
      isAdmin: auth.actor.isAdmin,
    });
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/auth/sign-out', async (request: Request, response: Response) => {
  try {
    response.json({ok: true});
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/config', async (request: Request, response: Response) => {
  try {
    const environment = getEnvironmentMode(request.body?.environment);
    const result = await getCalendarConfigForClient(db, environment);
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/status', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    const result = await getCalendarStatusForClient(db, authContext.environment);
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/oauth/start', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);
    const redirectUri = requireString(request.body?.redirectUri, 'redirectUri');
    const result = await createCalendarAuthUrl(
      db,
      authContext.environment,
      redirectUri,
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/oauth/exchange', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);
    const code = requireString(request.body?.code, 'code');
    const redirectUri = requireString(request.body?.redirectUri, 'redirectUri');
    const result = await exchangeCalendarAuthCode(
      db,
      authContext.environment,
      code,
      redirectUri,
      {
        memberId: authContext.actor.memberId,
        isAdmin: authContext.actor.isAdmin,
      },
    );
    const authResumeGeneration = await recordAuthResumeWindow(
      authContext.environment,
      authContext.actor,
    );
    await resumeAuthBlockedCalendarJobs(
      authContext.environment,
      authContext.actor,
    );
    await enqueueDelayedAuthResumeTasks(
      authContext.environment,
      authContext.actor,
      authResumeGeneration,
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/oauth/sign-out', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);
    const result = await disconnectCalendarAuth(db, authContext.environment);
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/action', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    const action = requireString(request.body?.action, 'action');
    const payload =
      (request.body?.payload as Record<string, unknown> | undefined) ?? {};

    // Cached web builds used to be a second writer for app events. Keep their
    // response shapes, but route their intent through the durable reconciler so
    // only one backend path can mutate managed Google events or sync state.
    if (
      action === 'createAppEventCalendarEvents' ||
      action === 'createAppEventCalendarEventPart' ||
      action === 'updateAppEventCalendarEvents'
    ) {
      requireAdmin(authContext.actor);
      const rawEvent = payload['event'];
      if (rawEvent == null || typeof rawEvent !== 'object' || Array.isArray(rawEvent)) {
        throw new HttpError(400, 'Missing or invalid event');
      }
      const event = rawEvent as Record<string, unknown>;
      const eventId = requireString(event['eventId'], 'event.eventId');
      await markAndEnqueueEventCalendarJobs(
        authContext.environment,
        [eventId],
        authContext.actor,
      );

      if (action === 'createAppEventCalendarEventPart') {
        const eventType = requireString(payload['eventType'], 'eventType');
        if (eventType !== 'assembly' && eventType !== 'main' && eventType !== 'allDay') {
          throw new HttpError(400, 'Invalid eventType');
        }
        response.json({
          calendarEventId: buildDeterministicAppEventCalendarId(
            authContext.environment,
            eventId,
            eventType,
          ),
        });
        return;
      }

      if (action === 'createAppEventCalendarEvents') {
        const assemblyTime = typeof event['assemblyTime'] === 'string'
          ? event['assemblyTime']
          : '';
        const separatorTime = typeof event['separatorTime'] === 'string'
          ? event['separatorTime']
          : '';
        const endTime = typeof event['endTime'] === 'string' ? event['endTime'] : '';
        const useAllDay = assemblyTime.length === 0 || endTime.length === 0;
        const ids: Record<string, string> = {};
        if (useAllDay) {
          ids['main'] = buildDeterministicAppEventCalendarId(
            authContext.environment,
            eventId,
            'allDay',
          );
        } else {
          if (assemblyTime.length > 0 && separatorTime.length > 0) {
            ids['assembly'] = buildDeterministicAppEventCalendarId(
              authContext.environment,
              eventId,
              'assembly',
            );
          }
          ids['main'] = buildDeterministicAppEventCalendarId(
            authContext.environment,
            eventId,
            'main',
          );
        }
        response.json({result: ids});
        return;
      }

      response.json({result: null});
      return;
    }

    if (action === 'deleteAppEventCalendarEvents') {
      requireAdmin(authContext.actor);
      // The preceding event deactivate/delete mutation already wrote a
      // tombstone job. Never trust cached Google IDs as an independent delete.
      response.json({ok: true});
      return;
    }

    if (action === 'cleanupAppEventGuests') {
      throw new HttpError(
        400,
        'App-event guest cleanup must use the scoped maintenance job endpoint',
      );
    }

    const result = await executeCalendarActionWithQuotaCircuit(
      {
        memberId: authContext.actor.memberId,
        isAdmin: authContext.actor.isAdmin,
      },
      authContext.environment,
      action,
      payload,
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/sync-app-event-attendees', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);
    // Compatibility no-op for cached web clients. Assignment membership no
    // longer has any Google Calendar attendee behavior.
    response.json({
      ok: true,
      scannedCount: 0,
      syncedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      failedEventIds: [],
      attendeeSyncDisabled: true,
    });
  } catch (error) {
    handleError(response, error);
  }
});

function serializeConstraintSyncReport(
  constraintSummary: ConstraintSyncReport,
): Record<string, unknown> {
  return {
    scannedConstraintCount: constraintSummary.scannedCount,
    changedConstraintCount: constraintSummary.changedCount,
    upToDateConstraintCount: constraintSummary.upToDateCount,
    rejectedConstraintCount: constraintSummary.rejectedConstraintCount,
    retriedConstraintCount:
      constraintSummary.changedCount + constraintSummary.failedConstraintIds.length,
    successfulConstraintRetryCount: constraintSummary.changedCount,
    skippedConstraintCount: constraintSummary.upToDateCount,
    failedConstraintCount: constraintSummary.failedConstraintIds.length,
    failedConstraintIds: constraintSummary.failedConstraintIds,
    createdConstraintEventCount: constraintSummary.createdConstraintEventCount,
    updatedConstraintEventCount: constraintSummary.updatedConstraintEventCount,
    deletedConstraintEventCount: constraintSummary.deletedConstraintEventCount,
    repairedConstraintSyncStateCount: constraintSummary.repairedConstraintSyncStateCount,
    cleanedConstraintSyncStateCount: constraintSummary.cleanedSyncStateCount,
  };
}

app.post('/calendar/sync-events-and-constraints', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);

    const dependencies = {
      firestore: db,
      actor: {
        memberId: authContext.actor.memberId,
        isAdmin: authContext.actor.isAdmin,
      },
      environment: authContext.environment,
      collections: authContext.collections,
      calendarAction: async (
        action: string,
        payload: Record<string, unknown>,
      ) => await executeCalendarActionWithQuotaCircuit(
        authContext.actor,
        authContext.environment,
        action,
        payload,
      ),
      rejectConstraint: async (teamMemberId: string, constraintId: string) =>
        await updateConstraintStatusForTeamMember(
          authContext.collections,
          authContext.actor,
          teamMemberId,
          constraintId,
          'rejected',
          {
            wasAutoRejectedFromCalendar: true,
          },
        ),
    };

    // Chunked sync protocol. The client fetches the work list ('plan'), then
    // reconciles events in small batches ('events') so no single request runs
    // long enough to hit the client/function timeout, and finally syncs
    // constraints ('constraints'). Omitting `mode` runs the legacy one-shot
    // full sync so older clients keep working.
    const mode = optionalString(request.body?.mode) ?? 'all';

    if (mode === 'plan') {
      const eventIds = await listInScopeAppEventIds(dependencies);
      response.json({ok: true, eventIds});
      return;
    }

    if (mode === 'events') {
      const eventIds = optionalStringArray(request.body?.eventIds);
      const queuedCount = await markAndEnqueueEventCalendarJobs(
        authContext.environment,
        eventIds,
        authContext.actor,
      );
      response.json({
        ok: true,
        queuedEventCount: queuedCount,
        scannedEventCount: queuedCount,
        syncedEventCount: 0,
        skippedEventCount: 0,
        failedEventCount: 0,
        failedEventIds: [],
      });
      return;
    }

    if (mode === 'constraints') {
      const constraintSummary = await syncConstraintCalendars(dependencies);
      response.json({ok: true, ...serializeConstraintSyncReport(constraintSummary)});
      return;
    }

    // Legacy one-shot request: event work is queued through the single writer;
    // constraint behavior remains synchronous and unchanged.
    const eventIds = await listInScopeAppEventIds(dependencies);
    const queuedCount = await markAndEnqueueEventCalendarJobs(
      authContext.environment,
      eventIds,
      authContext.actor,
    );
    const constraintSummary = await syncConstraintCalendars(dependencies);

    response.json({
      ok: true,
      queuedEventCount: queuedCount,
      scannedEventCount: queuedCount,
      syncedEventCount: 0,
      skippedEventCount: 0,
      failedEventCount: 0,
      failedEventIds: [],
      ...serializeConstraintSyncReport(constraintSummary),
      message: `סנכרון ${queuedCount} אירועים הועבר לתור. סנכרון המגבלות הושלם.`,
    });
  } catch (error) {
    handleError(response, error);
  }
});

function serializeGuestCleanupJob(
  jobId: string,
  data: Record<string, unknown>,
): Record<string, unknown> {
  return {
    jobId,
    mode: data['mode'] === 'all' ? 'all' : 'omer',
    status: typeof data['status'] === 'string' ? data['status'] : 'queued',
    totalEventCount: Number(data['totalEventCount']) || 0,
    totalPartCount: Number(data['totalPartCount']) || 0,
    processedPartCount: Number(data['processedPartCount']) || 0,
    changedPartCount: Number(data['changedPartCount']) || 0,
    skippedPartCount: Number(data['skippedPartCount']) || 0,
    failedPartCount: Number(data['failedPartCount']) || 0,
    lastError: typeof data['lastError'] === 'string' ? data['lastError'] : null,
  };
}

app.post('/calendar/app-event-guest-cleanup/start', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);
    const mode = requireString(request.body?.mode, 'mode');
    if (mode !== 'omer' && mode !== 'all') {
      throw new HttpError(400, 'Invalid cleanup mode');
    }

    const jobId = randomUUID();
    const jobRef = db
      .collection(authContext.collections.calendarMaintenanceJobs)
      .doc(jobId);
    const lockRef = guestCleanupLockRef(authContext.collections);
    let existingActiveJob: {
      jobId: string;
      data: Record<string, unknown>;
    } | null = null;

    // The fixed lock document closes the race where two admins both observed
    // an empty active-job query and started overlapping cleanup passes.
    await db.runTransaction(async (transaction) => {
      existingActiveJob = null;
      const lock = await transaction.get(lockRef);
      const activeJobId = typeof lock.data()?.['activeJobId'] === 'string'
        ? lock.data()?.['activeJobId'] as string
        : null;
      if (activeJobId != null && activeJobId.length > 0) {
        const activeRef = db
          .collection(authContext.collections.calendarMaintenanceJobs)
          .doc(activeJobId);
        const active = await transaction.get(activeRef);
        const activeData = active.data() ?? {};
        const activeStatus = typeof activeData['status'] === 'string'
          ? activeData['status']
          : '';
        if (
          active.exists &&
          activeStatus !== 'completed' &&
          activeStatus !== 'failed'
        ) {
          if (activeData['mode'] !== mode) {
            throw new HttpError(
              409,
              'ניקוי משתתפים מסוג אחר כבר מתבצע. יש להמתין לסיומו.',
            );
          }
          existingActiveJob = {jobId: activeJobId, data: activeData};
          return;
        }
      }

      transaction.set(jobRef, {
        type: 'appEventGuestCleanup',
        mode,
        targetEmail: mode === 'omer' ? OMER_CLEANUP_EMAIL : null,
        stage: 'discovery',
        status: 'queued',
        totalEventCount: 0,
        totalPartCount: 0,
        processedPartCount: 0,
        changedPartCount: 0,
        skippedPartCount: 0,
        failedPartCount: 0,
        requestedByMemberId: authContext.actor.memberId,
        requestedByIsAdmin: authContext.actor.isAdmin,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(lockRef, {
        type: 'appEventGuestCleanupLock',
        activeJobId: jobId,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    const activeJob = existingActiveJob as {
      jobId: string;
      data: Record<string, unknown>;
    } | null;
    if (activeJob != null) {
      response.json({
        ok: true,
        resumedExistingJob: true,
        ...serializeGuestCleanupJob(activeJob.jobId, activeJob.data),
      });
      return;
    }

    await enqueueGuestCleanupJob(
      authContext.environment,
      jobId,
      authContext.actor,
    );

    const initialJobData: Record<string, unknown> = {
      mode,
      status: 'queued',
      totalEventCount: 0,
      totalPartCount: 0,
      processedPartCount: 0,
      changedPartCount: 0,
      skippedPartCount: 0,
      failedPartCount: 0,
    };

    try {
      await writeAuditLog(
        db,
        authContext.collections,
        authContext.actor,
        'calendar.appEventGuestCleanup.start',
        'calendarMaintenance',
        jobId,
        {
          mode,
          status: 'queued',
        },
      );
    } catch (auditError) {
      console.error('[calendar-cleanup-error] failed to write start audit:', auditError);
    }

    response.json({ok: true, ...serializeGuestCleanupJob(jobId, initialJobData)});
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/calendar/app-event-guest-cleanup/status', async (request: Request, response: Response) => {
  try {
    const authContext = await authenticateRequest(request);
    requireAdmin(authContext.actor);
    const requestedJobId = optionalString(request.body?.jobId);
    let snapshot;
    if (requestedJobId != null && requestedJobId.length > 0) {
      snapshot = await db
        .collection(authContext.collections.calendarMaintenanceJobs)
        .doc(requestedJobId)
        .get();
      if (!snapshot.exists) throw new HttpError(404, 'Cleanup job not found');
    } else {
      const latest = await db
        .collection(authContext.collections.calendarMaintenanceJobs)
        .orderBy('createdAt', 'desc')
        .limit(1)
        .get();
      if (latest.empty) {
        response.json({ok: true, job: null});
        return;
      }
      snapshot = latest.docs[0];
    }
    response.json({
      ok: true,
      ...serializeGuestCleanupJob(snapshot.id, snapshot.data() ?? {}),
    });
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/drive/action', async (request: Request, response: Response) => {
  try {
    const {actor} = await authenticateRequest(request);
    const action = requireString(request.body?.action, 'action');
    if (!canExecuteDriveAction(action)) {
      throw new HttpError(400, `Unsupported drive action: ${action}`);
    }

    if (action !== 'listFiles') {
      requireAdmin(actor);
    }

    const result = await executeDriveAction(
      db,
      action,
      (request.body as Record<string, unknown> | undefined) ?? {},
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/drive/export', async (request: Request, response: Response) => {
  try {
    const {actor} = await authenticateRequest(request);
    requireAdmin(actor);

    const type = request.body?.type === 'assignments' ? 'assignments' : 'full';
    const rawMode = request.body?.mode;
    if (rawMode != null && rawMode !== 'perPerson' && rawMode !== 'perEvent') {
      throw new HttpError(400, `Unsupported assignment export mode: ${String(rawMode)}`);
    }
    const assignmentMode = rawMode === 'perEvent' ? 'perEvent' : 'perPerson';
    const rawEventIds = request.body?.eventIds;
    const eventIds = Array.isArray(rawEventIds)
      ? rawEventIds
          .filter((value): value is string => typeof value === 'string')
          .map((value) => value.trim())
          .filter((value) => value.length > 0)
      : [];

    if (type === 'assignments' && assignmentMode === 'perEvent' && eventIds.length === 0) {
      throw new HttpError(400, 'Select at least one future event to export');
    }

    const result = await exportProductionDataToSheets(db, type, {
      assignmentMode,
      eventIds,
    });
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/mutate', async (request: Request, response: Response) => {
  try {
    const {actor, environment, collections} = await authenticateRequest(request);
    const operation = requireString(request.body?.operation, 'operation');
    const payload =
      (request.body?.payload as Record<string, unknown> | undefined) ?? {};
    const result = await executeMutation(
      actor,
      environment,
      collections,
      operation,
      payload,
    );
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

function handleError(response: Response, error: unknown): void {
  if (error instanceof DriveExportValidationError) {
    response.status(400).json({
      ok: false,
      error: error.message,
    });
    return;
  }

  if (error instanceof HttpError) {
    response.status(error.status).json({
      ok: false,
      error: error.message,
    });
    return;
  }

  if (error instanceof GoogleApiError && error.status === 429) {
    response.status(429).json({
      ok: false,
      error: error.message,
    });
    return;
  }

  response.status(500).json({
    ok: false,
    error: error instanceof Error ? error.message : 'Unknown error',
  });
}

export const api = onRequest(
  {
    region: 'us-central1',
    invoker: 'public',
  },
  app,
);

// Test-only re-exports. Not part of the public API; used by availability.test.ts.
export {
  normalizeDayInIsrael as __testNormalizeDayInIsrael,
  constraintMatchesDate as __testConstraintMatchesDate,
  memberAvailableForEvent as __testMemberAvailableForEvent,
};
