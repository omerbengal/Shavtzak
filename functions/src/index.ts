import cors from 'cors';
import express, {Request, Response} from 'express';
import {randomBytes, randomUUID, scryptSync, timingSafeEqual, createHash} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from 'firebase-admin/firestore';
import {onRequest} from 'firebase-functions/v2/https';
import {
  canExecuteDriveAction,
  executeDriveAction,
  exportProductionDataToSheets,
} from './drive_export';
import {
  createCalendarAuthUrl,
  disconnectCalendarAuth,
  exchangeCalendarAuthCode,
  executeCalendarAction,
  getCalendarConfigForClient,
  getCalendarStatusForClient,
} from './calendar_integration';

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
  checklistItems: string;
  presets: string;
  calendarSync: string;
  eventCalendarSync: string;
  logs: string;
  privateCredentials: string;
  privateSessions: string;
  privateGoogleCalendarAuth: string;
};

function getEnvironmentMode(value: unknown): EnvironmentMode {
  return value === 'test' ? 'test' : 'production';
}

function getCollections(environment: EnvironmentMode): Collections {
  const prefix = environment === 'test' ? 'test_' : '';
  return {
    teamMembers: `${prefix}teamMembers`,
    events: `${prefix}events`,
    assignments: `${prefix}assignments`,
    checklistItems: `${prefix}checklist_items`,
    presets: `${prefix}checklist_presets`,
    calendarSync: `${prefix}calendar_sync`,
    eventCalendarSync: `${prefix}event_calendar_sync`,
    logs: `${prefix}logs`,
    privateCredentials: `${prefix}private_member_credentials`,
    privateSessions: `${prefix}private_sessions`,
    privateGoogleCalendarAuth: `${prefix}private_google_calendar_auth`,
  };
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

function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate()
  );
}

function normalizeDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
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

async function writeAuditLog(
  firestore: Firestore,
  collections: Collections,
  actor: ActorContext,
  operation: string,
  entityType: string,
  entityId: string,
  details: Record<string, unknown> = {},
): Promise<void> {
  await firestore.collection(collections.logs).add({
    timestampUtc: FieldValue.serverTimestamp(),
    actionType: operation,
    entityType,
    entityId,
    performerId: actor.memberId,
    performerUniqueKey: actor.uniqueKey,
    status: 'success',
    source: 'cloud_function',
    details,
  });
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
    startDate: toTimestamp(event['startDate'], 'event.startDate'),
    endDate: toTimestamp(event['endDate'], 'event.endDate'),
    startTime: event['startTime'] ?? '',
    endTime: event['endTime'] ?? '',
    assemblyTime: event['assemblyTime'] ?? '',
    actualShowStartTime: event['actualShowStartTime'] ?? '',
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
    isArchived: event['isArchived'] ?? false,
    relevantForExtendedTeam: event['relevantForExtendedTeam'] ?? false,
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
    alternativePhoneNumber: assignment['alternativePhoneNumber'] ?? null,
    createdAt: toTimestamp(assignment['createdAt'], 'assignment.createdAt'),
    updatedAt: toTimestamp(assignment['updatedAt'], 'assignment.updatedAt'),
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
  const startDate = normalizeDay(constraint['startDate'] as Date);
  const endDate = constraint['endDate'] == null
    ? startDate
    : normalizeDay(constraint['endDate'] as Date);
  const repeatType = typeof constraint['repeatType'] === 'string' ? constraint['repeatType'] : null;
  const repeatDay = typeof constraint['repeatDay'] === 'number' ? constraint['repeatDay'] : null;
  const repeatEndDate = constraint['repeatEndDate'] == null
    ? null
    : normalizeDay(constraint['repeatEndDate'] as Date);
  const target = normalizeDay(date);

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
    for (let day = normalizeDay(eventStart); day <= normalizeDay(eventEnd); day = addDays(day, 1)) {
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

  for (let day = normalizeDay(eventStart); day <= normalizeDay(eventEnd); day = addDays(day, 1)) {
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
): Promise<void> {
  const eventId = requireString(assignment['eventId'], 'assignment.eventId');
  const teamMemberId = requireString(assignment['teamMemberId'], 'assignment.teamMemberId');
  const roleType = requireString(assignment['roleType'], 'assignment.roleType');

  const [eventDoc, memberDoc] = await Promise.all([
    firestore.collection(collections.events).doc(eventId).get(),
    firestore.collection(collections.teamMembers).doc(teamMemberId).get(),
  ]);

  if (!eventDoc.exists) {
    throw new HttpError(400, 'אירוע לא נמצא');
  }
  if (!memberDoc.exists) {
    throw new HttpError(400, 'חבר צוות לא נמצא');
  }

  const eventData = eventDoc.data() ?? {};
  const memberData = memberDoc.data() ?? {};

  const roleCapabilities =
    (memberData['roleCapabilities'] as Record<string, unknown> | undefined) ?? {};
  if (roleCapabilities[roleType] !== true) {
    throw new HttpError(400, 'חבר/ת הצוות אינו/ה מוסמך/ת לתפקיד זה');
  }

  if (memberData['isActive'] !== true) {
    throw new HttpError(400, 'לא ניתן לשבץ חבר/ת צוות לא פעיל/ה');
  }

  if (memberData['allowMultipleAssignments'] !== true) {
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

  if (memberData['allowMultipleAssignments'] !== true && !memberAvailableForEvent(memberData, eventData)) {
    throw new HttpError(400, 'חבר/ת הצוות לא זמין/ה לאירוע זה');
  }
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
  collections: Collections,
  operation: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  switch (operation) {
    case 'teamMember.insert': {
      requireAdmin(actor);
      const member = payload['member'] as Record<string, unknown>;
      const memberId = requireString(member['id'], 'member.id');
      await db.collection(collections.teamMembers).doc(memberId).set(teamMemberDocFromJson(member));
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {
        name: member['name'],
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
      await docRef.update(next);
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId);
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
      const credentialDoc = await credentialRef.get();

      if (!actor.isAdmin && credentialDoc.exists) {
        const existingHash = credentialDoc.data()?.['passcodeHash'];
        if (typeof existingHash === 'string') {
          if (currentPasscode == null || !verifyPasscode(currentPasscode, existingHash)) {
            throw new HttpError(403, 'קוד הגישה הנוכחי שגוי');
          }
        }
      }

      await credentialRef.set({
        passcodeHash: hashPasscode(passcode),
        passcodeLength: length,
        updatedAt: FieldValue.serverTimestamp(),
      });

      await teamRef.update({
        passcodeLength: length,
        passcode: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId, {length});
      return {ok: true};
    }

    case 'teamMember.clearPasscode': {
      const memberId = requireString(payload['memberId'], 'memberId');
      requireSelfOrAdmin(actor, memberId);
      await db.collection(collections.privateCredentials).doc(memberId).delete();
      await db.collection(collections.teamMembers).doc(memberId).update({
        passcodeLength: FieldValue.delete(),
        passcode: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId);
      return {ok: true};
    }

    case 'teamMember.delete': {
      requireAdmin(actor);
      const memberId = requireString(payload['memberId'], 'memberId');
      await db.collection(collections.teamMembers).doc(memberId).delete();
      await db.collection(collections.privateCredentials).doc(memberId).delete().catch(() => undefined);
      await writeAuditLog(db, collections, actor, operation, 'teamMember', memberId);
      return {ok: true};
    }

    case 'teamMember.insertBatch': {
      requireAdmin(actor);
      const members = Array.isArray(payload['members']) ? payload['members'] : [];
      const batch = db.batch();
      for (const rawMember of members) {
        const member = rawMember as Record<string, unknown>;
        const memberId = requireString(member['id'], 'member.id');
        batch.set(
          db.collection(collections.teamMembers).doc(memberId),
          teamMemberDocFromJson(member),
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
        const teamMembers = await db.collection(collections.teamMembers).get();
        for (const doc of teamMembers.docs) {
          const data = doc.data();
          const constraints = Array.isArray(data['constraints']) ? [...(data['constraints'] as Array<Record<string, unknown>>)] : [];
          const index = constraints.findIndex((constraint) => constraint['id'] === constraintIdOrMemberId);
          if (index < 0) continue;
          const updated = {
            ...constraints[index],
            status: newStatus,
            ...(note != null ? {note} : {}),
            ...(payload['wasAutoRejectedFromCalendar'] != null
              ? {wasAutoRejectedFromCalendar}
              : {}),
          };
          constraints[index] = updated;
          await doc.ref.update({
            constraints,
            updatedAt: FieldValue.serverTimestamp(),
          });
          await writeAuditLog(db, collections, actor, operation, 'constraint', constraintIdOrMemberId, {
            teamMemberId: doc.id,
            newStatus,
          });
          return {ok: true};
        }
        throw new HttpError(404, 'Constraint not found');
      }

      const teamMemberId = constraintIdOrMemberId;
      const constraintIndex = Number(constraintIndexValue);
      const memberDoc = await db.collection(collections.teamMembers).doc(teamMemberId).get();
      if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
      const constraints = Array.isArray(memberDoc.data()?.['constraints'])
        ? [...(memberDoc.data()?.['constraints'] as Array<Record<string, unknown>>)]
        : [];
      if (constraintIndex < 0 || constraintIndex >= constraints.length) {
        throw new HttpError(400, 'Invalid constraint index');
      }
      constraints[constraintIndex] = {
        ...constraints[constraintIndex],
        status: newStatus,
        ...(note != null ? {note} : {}),
        ...(payload['wasAutoRejectedFromCalendar'] != null
          ? {wasAutoRejectedFromCalendar}
          : {}),
      };
      await memberDoc.ref.update({
        constraints,
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(db, collections, actor, operation, 'constraint', String(constraints[constraintIndex]['id']));
      return {ok: true};
    }

    case 'constraint.add': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      requireSelfOrAdmin(actor, teamMemberId);
      const constraint = payload['constraint'] as Record<string, unknown>;
      await db.collection(collections.teamMembers).doc(teamMemberId).update({
        constraints: FieldValue.arrayUnion([constraint]),
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(db, collections, actor, operation, 'constraint', requireString(constraint['id'], 'constraint.id'));
      return {ok: true};
    }

    case 'constraint.edit': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      requireSelfOrAdmin(actor, teamMemberId);
      const updatedConstraint = payload['constraint'] as Record<string, unknown>;
      const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
      const memberDoc = await memberRef.get();
      if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
      const constraints = Array.isArray(memberDoc.data()?.['constraints'])
        ? [...(memberDoc.data()?.['constraints'] as Array<Record<string, unknown>>)]
        : [];
      const index = constraints.findIndex((constraint) => constraint['id'] === constraintId);
      if (index < 0) throw new HttpError(404, 'Constraint not found');
      constraints[index] = updatedConstraint;
      await memberRef.update({constraints, updatedAt: FieldValue.serverTimestamp()});
      await writeAuditLog(db, collections, actor, operation, 'constraint', constraintId);
      return {ok: true};
    }

    case 'constraint.remove': {
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      const constraintId = requireString(payload['constraintId'], 'constraintId');
      requireSelfOrAdmin(actor, teamMemberId);
      const memberRef = db.collection(collections.teamMembers).doc(teamMemberId);
      const memberDoc = await memberRef.get();
      if (!memberDoc.exists) throw new HttpError(404, 'Team member not found');
      const constraints = Array.isArray(memberDoc.data()?.['constraints'])
        ? [...(memberDoc.data()?.['constraints'] as Array<Record<string, unknown>>)]
        : [];
      const nextConstraints = constraints.filter((constraint) => constraint['id'] !== constraintId);
      await memberRef.update({constraints: nextConstraints, updatedAt: FieldValue.serverTimestamp()});
      await writeAuditLog(db, collections, actor, operation, 'constraint', constraintId);
      return {ok: true};
    }

    case 'event.insert': {
      requireAdmin(actor);
      const event = payload['event'] as Record<string, unknown>;
      const eventId = requireString(event['id'], 'event.id');
      const name = requireString(event['name'], 'event.name');
      const startDate = asDate(event['startDate'], 'event.startDate');
      const startOfTargetDay = Timestamp.fromDate(normalizeDay(startDate));
      const endOfTargetDay = Timestamp.fromDate(addDays(normalizeDay(startDate), 1));
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
      await db.collection(collections.events).doc(eventId).set(eventDocFromJson(event));
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {name});
      return {ok: true};
    }

    case 'event.update': {
      requireAdmin(actor);
      const event = payload['event'] as Record<string, unknown>;
      const eventId = requireString(event['id'], 'event.id');
      const name = requireString(event['name'], 'event.name');
      const startDate = asDate(event['startDate'], 'event.startDate');
      const startOfTargetDay = Timestamp.fromDate(normalizeDay(startDate));
      const endOfTargetDay = Timestamp.fromDate(addDays(normalizeDay(startDate), 1));
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
      await db.collection(collections.events).doc(eventId).update(eventDocFromJson(event));
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {name});
      return {ok: true};
    }

    case 'event.delete': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      const checklistSnapshot = await db
        .collection(collections.checklistItems)
        .where('eventId', '==', eventId)
        .get();
      const batch = db.batch();
      for (const doc of checklistSnapshot.docs) {
        batch.delete(doc.ref);
      }
      batch.delete(db.collection(collections.events).doc(eventId));
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {
        deletedChecklistItems: checklistSnapshot.docs.length,
      });
      return {ok: true};
    }

    case 'event.insertBatch': {
      requireAdmin(actor);
      const events = Array.isArray(payload['events']) ? payload['events'] : [];
      const batch = db.batch();
      for (const rawEvent of events) {
        const event = rawEvent as Record<string, unknown>;
        const eventId = requireString(event['id'], 'event.id');
        batch.set(db.collection(collections.events).doc(eventId), eventDocFromJson(event));
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'eventBatch', actor.memberId, {
        count: events.length,
      });
      return {ok: true};
    }

    case 'event.updateArchiveStatus': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      await db.collection(collections.events).doc(eventId).update({
        isArchived: payload['isArchived'] === true,
        updatedAt: FieldValue.serverTimestamp(),
      });
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {
        isArchived: payload['isArchived'] === true,
      });
      return {ok: true};
    }

    case 'assignment.insert': {
      requireAdmin(actor);
      const assignment = payload['assignment'] as Record<string, unknown>;
      const assignmentId = requireString(assignment['id'], 'assignment.id');
      await validateAssignmentPayload(db, collections, assignment);
      await db.collection(collections.assignments).doc(assignmentId).set(assignmentDocFromJson(assignment));
      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId);
      return {ok: true};
    }

    case 'assignment.update': {
      requireAdmin(actor);
      const assignment = payload['assignment'] as Record<string, unknown>;
      const assignmentId = requireString(assignment['id'], 'assignment.id');
      await validateAssignmentPayload(db, collections, assignment, assignmentId);
      await db.collection(collections.assignments).doc(assignmentId).update(assignmentDocFromJson(assignment));
      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId);
      return {ok: true};
    }

    case 'assignment.delete': {
      requireAdmin(actor);
      const assignmentId = requireString(payload['assignmentId'], 'assignmentId');
      await db.collection(collections.assignments).doc(assignmentId).delete();
      await writeAuditLog(db, collections, actor, operation, 'assignment', assignmentId);
      return {ok: true};
    }

    case 'assignment.deleteByEvent': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      const snapshot = await db.collection(collections.assignments).where('eventId', '==', eventId).get();
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', eventId, {
        deletedCount: snapshot.docs.length,
      });
      return {ok: true};
    }

    case 'assignment.deleteByPerson': {
      requireAdmin(actor);
      const teamMemberId = requireString(payload['teamMemberId'], 'teamMemberId');
      const snapshot = await db
        .collection(collections.assignments)
        .where('teamMemberId', '==', teamMemberId)
        .get();
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', teamMemberId, {
        deletedCount: snapshot.docs.length,
      });
      return {ok: true};
    }

    case 'assignment.deleteBatch': {
      requireAdmin(actor);
      const assignmentIds = Array.isArray(payload['assignmentIds']) ? payload['assignmentIds'] : [];
      const batch = db.batch();
      for (const rawId of assignmentIds) {
        batch.delete(db.collection(collections.assignments).doc(String(rawId)));
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', actor.memberId, {
        deletedCount: assignmentIds.length,
      });
      return {ok: true};
    }

    case 'assignment.insertBatch': {
      requireAdmin(actor);
      const assignments = Array.isArray(payload['assignments']) ? payload['assignments'] : [];
      const batch = db.batch();
      for (const rawAssignment of assignments) {
        const assignment = rawAssignment as Record<string, unknown>;
        const assignmentId = requireString(assignment['id'], 'assignment.id');
        await validateAssignmentPayload(db, collections, assignment);
        batch.set(
          db.collection(collections.assignments).doc(assignmentId),
          assignmentDocFromJson(assignment),
        );
      }
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'assignmentBatch', actor.memberId, {
        count: assignments.length,
      });
      return {ok: true};
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
        collections.checklistItems,
        collections.presets,
        collections.calendarSync,
        collections.eventCalendarSync,
        collections.privateCredentials,
        collections.privateSessions,
        collections.privateGoogleCalendarAuth,
      ];
      for (const collectionName of collectionNames) {
        const snapshot = await db.collection(collectionName).get();
        const batch = db.batch();
        for (const doc of snapshot.docs) {
          batch.delete(doc.ref);
        }
        await batch.commit();
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
      await db.collection(collections.eventCalendarSync).doc(eventId).set({
        assemblyCalendarEventId: requireString(
          payload['assemblyCalendarEventId'],
          'assemblyCalendarEventId',
        ),
        mainCalendarEventId: requireString(payload['mainCalendarEventId'], 'mainCalendarEventId'),
        status: requireString(payload['status'], 'status'),
        syncedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {ok: true};
    }

    case 'calendar.removeEventSyncState': {
      requireAdmin(actor);
      const eventId = requireString(payload['eventId'], 'eventId');
      await db.collection(collections.eventCalendarSync).doc(eventId).delete();
      return {ok: true};
    }

    case 'checklist.insert': {
      requireAdmin(actor);
      const item = payload['item'] as Record<string, unknown>;
      const itemId = requireString(item['id'], 'item.id');
      await db.collection(collections.checklistItems).doc(itemId).set(checklistItemDocFromJson(item));
      await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId);
      return {ok: true};
    }

    case 'checklist.update': {
      const item = payload['item'] as Record<string, unknown>;
      const itemId = requireString(item['id'], 'item.id');
      const docRef = db.collection(collections.checklistItems).doc(itemId);
      const existingDoc = await docRef.get();
      if (!existingDoc.exists) throw new HttpError(404, 'Checklist item not found');
      const existing = existingDoc.data() ?? {};
      const isResponsible = existing['responsibleId'] === actor.memberId;
      const ccIds = Array.isArray(existing['ccIds']) ? existing['ccIds'].map(String) : [];
      if (!actor.isAdmin && !isResponsible && !ccIds.includes(actor.memberId)) {
        throw new HttpError(403, 'אין לך הרשאה לערוך את הפריט');
      }

      if (actor.isAdmin || isResponsible) {
        await docRef.update(checklistItemDocFromJson(item));
      } else {
        await docRef.update({
          status: item['status'] ?? existing['status'] ?? false,
          statusLastUpdatedAt: toTimestamp(
            item['statusLastUpdatedAt'] ?? new Date().toISOString(),
            'item.statusLastUpdatedAt',
          ),
          updatedAt: toTimestamp(item['updatedAt'] ?? new Date().toISOString(), 'item.updatedAt'),
        });
      }

      await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId);
      return {ok: true};
    }

    case 'checklist.delete': {
      requireAdmin(actor);
      const itemId = requireString(payload['itemId'], 'itemId');
      await db.collection(collections.checklistItems).doc(itemId).delete();
      await writeAuditLog(db, collections, actor, operation, 'checklistItem', itemId);
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
      );
      return {ok: true};
    }

    case 'preset.insert': {
      requireAdmin(actor);
      const preset = payload['preset'] as Record<string, unknown>;
      const presetId = requireString(preset['id'], 'preset.id');
      await db.collection(collections.presets).doc(presetId).set(presetDocFromJson(preset));
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId);
      return {ok: true};
    }

    case 'preset.update': {
      requireAdmin(actor);
      const preset = payload['preset'] as Record<string, unknown>;
      const presetId = requireString(preset['id'], 'preset.id');
      await db.collection(collections.presets).doc(presetId).update(presetDocFromJson(preset));
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId);
      return {ok: true};
    }

    case 'preset.delete': {
      requireAdmin(actor);
      const presetId = requireString(payload['presetId'], 'presetId');
      await db.collection(collections.presets).doc(presetId).delete();
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId);
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
      const batch = db.batch();
      const now = new Date().toISOString();
      for (const rawItem of items) {
        const item = rawItem as Record<string, unknown>;
        const checklistItemId = randomUUID();
        const notes = typeof item['adminNote'] === 'string' && item['adminNote'].trim().length > 0
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
        batch.set(db.collection(collections.checklistItems).doc(checklistItemId), {
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
      await batch.commit();
      await writeAuditLog(db, collections, actor, operation, 'preset', presetId, {
        eventId,
        count: items.length,
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
      let roles = getRolesArray(listsData);

      if (operation === 'role.insert') {
        roles = [...roles, payload['role'] as Record<string, unknown>];
      } else if (operation === 'role.update') {
        const role = payload['role'] as Record<string, unknown>;
        const roleId = requireString(role['id'], 'role.id');
        roles = roles.map((item) => (item['id'] === roleId ? role : item));
      } else if (operation === 'role.archive' || operation === 'role.restore') {
        const roleId = requireString(payload['roleId'], 'roleId');
        roles = roles.map((item) => {
          if (item['id'] !== roleId) return item;
          return {
            ...item,
            isArchived: operation === 'role.archive',
            isVisible: operation === 'role.restore' ? true : item['isVisible'],
            updatedAt: new Date().toISOString(),
          };
        });
      } else if (operation === 'role.delete') {
        const roleId = requireString(payload['roleId'], 'roleId');
        roles = roles.filter((item) => item['id'] !== roleId);
      } else if (operation === 'role.reorder') {
        const sortOrderMap = payload['roleIdToSortOrder'] as Record<string, number>;
        roles = roles.map((item) => ({
          ...item,
          sortOrder: sortOrderMap[String(item['id'])] ?? item['sortOrder'],
          updatedAt: new Date().toISOString(),
        }));
      } else if (operation === 'role.seed') {
        if (roles.length > 0) return {ok: true};
        const seedRoles = Array.isArray(payload['roles']) ? payload['roles'] : [];
        roles = seedRoles as Array<Record<string, unknown>>;
      }

      await listsRef.set({Roles: roles}, {merge: true});
      await writeAuditLog(db, collections, actor, operation, 'role', actor.memberId, {
        count: roles.length,
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

      if (operation === 'category.insert') {
        categories = [...categories, payload['category'] as Record<string, unknown>];
      } else if (operation === 'category.update') {
        const category = payload['category'] as Record<string, unknown>;
        const categoryId = requireString(category['id'], 'category.id');
        categories = categories.map((item) => (item['id'] === categoryId ? category : item));
      } else {
        const categoryId = requireString(payload['categoryId'], 'categoryId');
        if (operation === 'category.permanentlyDelete') {
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
        }
      }

      await listsRef.set({Categories: categories}, {merge: true});
      await writeAuditLog(db, collections, actor, operation, 'category', actor.memberId, {
        count: categories.length,
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
    let length = memberData['passcodeLength'];

    if (credentialDoc.exists) {
      const hash = credentialDoc.data()?.['passcodeHash'];
      if (typeof hash === 'string') {
        isValid = verifyPasscode(passcode, hash);
        length = credentialDoc.data()?.['passcodeLength'] ?? length;
      }
    } else if (typeof memberData['passcode'] === 'string' && (memberData['passcode'] as string).length > 0) {
      isValid = memberData['passcode'] === passcode;
      if (isValid) {
        await credentialRef.set({
          passcodeHash: hashPasscode(passcode),
          passcodeLength: memberData['passcodeLength'] ?? passcode.length,
          migratedFromLegacyFieldAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
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
    const result = await executeCalendarAction(
      db,
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
    const result = await exportProductionDataToSheets(db, type);
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

app.post('/mutate', async (request: Request, response: Response) => {
  try {
    const {actor, collections} = await authenticateRequest(request);
    const operation = requireString(request.body?.operation, 'operation');
    const payload =
      (request.body?.payload as Record<string, unknown> | undefined) ?? {};
    const result = await executeMutation(actor, collections, operation, payload);
    response.json(result);
  } catch (error) {
    handleError(response, error);
  }
});

function handleError(response: Response, error: unknown): void {
  if (error instanceof HttpError) {
    response.status(error.status).json({
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
