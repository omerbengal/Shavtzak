import {Firestore, Timestamp} from 'firebase-admin/firestore';

export type DriveAction =
  | 'createFolder'
  | 'renameFolder'
  | 'deleteFolder'
  | 'listFiles'
  | 'archiveCheck';

export type DriveExportType = 'full' | 'assignments';
export type AssignmentExportMode = 'perPerson' | 'perEvent';

export type AssignmentExportOptions = {
  assignmentMode?: AssignmentExportMode;
  eventIds?: string[];
  now?: Date;
};

export class DriveExportValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'DriveExportValidationError';
  }
}

type DriveConfig = {
  scriptUrl: string;
  apiKey: string;
};

type FirestoreDoc = {
  id: string;
  data: Record<string, unknown>;
};

const PRODUCTION_COLLECTIONS = {
  teamMembers: 'teamMembers',
  events: 'events',
  assignments: 'assignments',
  checklistItems: 'checklist_items',
  presets: 'checklist_presets',
  calendarSync: 'calendar_sync',
  keys: 'keys',
  utilities: 'utilities',
};

const SENSITIVE_KEY_FIELDS = new Set([
  'apikey',
  'clientsecret',
  'serviceaccountjson',
  'privatekey',
  'refreshtoken',
  'accesstoken',
]);

function asMap(value: unknown): Record<string, unknown> | null {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function asList(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asString(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value == null) return '';
  return String(value);
}

function asOptionalString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function asBool(value: unknown, fallback = false): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function normalizeJsonValue(value: unknown): unknown {
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (Array.isArray(value)) {
    return value.map((entry) => normalizeJsonValue(entry));
  }
  const map = asMap(value);
  if (map == null) {
    return value;
  }
  return Object.fromEntries(
    Object.entries(map).map(([key, entryValue]) => [key, normalizeJsonValue(entryValue)]),
  );
}

function jsonEncode(value: unknown): string {
  if (value == null) return '';
  try {
    return JSON.stringify(normalizeJsonValue(value));
  } catch {
    return String(value);
  }
}

function toTimestampString(value: unknown): string {
  if (value == null) return '';
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string') return value;
  return String(value);
}

function parseDate(value: unknown): Date | null {
  if (value == null) return null;
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'string' && value.length > 0) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

const israelDateKeyFormatter = new Intl.DateTimeFormat('en-US', {
  timeZone: 'Asia/Jerusalem',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

function israelCalendarDateKey(value: Date): string {
  if (Number.isNaN(value.getTime())) return '';
  const parts = israelDateKeyFormatter.formatToParts(value);
  const year = parts.find((part) => part.type === 'year')?.value ?? '0000';
  const month = parts.find((part) => part.type === 'month')?.value ?? '00';
  const day = parts.find((part) => part.type === 'day')?.value ?? '00';
  return `${year}-${month}-${day}`;
}

function formatIsraelCalendarDateKey(dateKey: string): string {
  const [year, month, day] = dateKey.split('-');
  if (year?.length !== 4 || month?.length !== 2 || day?.length !== 2) {
    return '';
  }
  return `${day}/${month}/${year}`;
}

function isFutureOrTodayByEndDate(
  eventData: Record<string, unknown>,
  now: Date,
): boolean {
  // Deactivated events should not appear in exports — they are hidden from
  // every in-app surface and their assignments are preserved only for
  // potential reactivation.
  if (eventData['isDeactivated'] === true) return false;
  const endDate = parseDate(eventData['endDate']);
  if (endDate == null) return false;
  return israelCalendarDateKey(endDate) >= israelCalendarDateKey(now);
}

function filterFutureEventsData(
  eventsData: Record<string, Record<string, unknown>>,
  now: Date,
): Record<string, Record<string, unknown>> {
  return Object.fromEntries(
    Object.entries(eventsData).filter(([, eventData]) =>
      isFutureOrTodayByEndDate(eventData, now),
    ),
  );
}

function formatDate(value: unknown): string {
  const date = parseDate(value);
  if (date == null) return '';
  const day = String(date.getDate()).padStart(2, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const year = String(date.getFullYear());
  return `${day}/${month}/${year}`;
}

function idsToNames(ids: unknown, lookup: Record<string, string>): string {
  if (!Array.isArray(ids)) return '';
  return ids.map((id) => lookup[String(id)] ?? String(id)).join(', ');
}

function roleCapabilitiesToHebrew(
  capabilities: unknown,
  roleHebrewNames: Record<string, string>,
): string {
  const map = asMap(capabilities);
  if (map == null) return '';
  const names: string[] = [];
  for (const [key, value] of Object.entries(map)) {
    if (value === true) {
      names.push(roleHebrewNames[key] ?? key);
    }
  }
  return names.join('<<<NEWLINE>>>');
}

function roleRequirementsToHebrew(
  requirements: unknown,
  roleHebrewNames: Record<string, string>,
): string {
  const map = asMap(requirements);
  if (map == null) return '';
  return Object.entries(map)
    .map(([key, value]) => `${roleHebrewNames[key] ?? key}: ${String(value)}`)
    .join(', ');
}

function formatEventDateTimeRange(eventData: Record<string, unknown>): string {
  const startDate = formatDate(eventData['startDate']);
  const startTime = asString(eventData['startTime']);
  const endDate = formatDate(eventData['endDate']);
  const endTime = asString(eventData['endTime']);

  if (startDate === endDate) {
    if (startTime.length > 0 && endTime.length > 0) {
      return `${startDate} ${startTime} - ${endTime}`;
    }
    if (startTime.length > 0) {
      return `${startDate} ${startTime}`;
    }
    return startDate;
  }

  const start = startTime.length > 0 ? `${startDate} ${startTime}` : startDate;
  const end = endTime.length > 0 ? `${endDate} ${endTime}` : endDate;
  return `${start} - ${end}`;
}

function formatAvailableEvents(
  eventIds: unknown,
  eventsData: Record<string, Record<string, unknown>>,
): string {
  if (!Array.isArray(eventIds) || eventIds.length === 0) return '';
  const parts = eventIds.map((idValue) => {
    const id = String(idValue);
    const eventData = eventsData[id];
    if (eventData == null) return id;
    const name = asString(eventData['name']) || id;
    return `${name} (${formatEventDateTimeRange(eventData)})`;
  });
  return parts.join('<<<NEWLINE>>>');
}

function cleanLocation(value: unknown): string {
  if (typeof value !== 'string') return '';
  let location = value;
  if (location.includes('||')) {
    location = location.split('||')[0].trim();
  }
  location = location.replace(/[\(\[]?\d+\.\d+,\s*\d+\.\d+[\)\]]?/g, '');
  return location.trim();
}

function buildMemberNames(teamMembers: FirestoreDoc[]): Record<string, string> {
  const names: Record<string, string> = {};
  for (const doc of teamMembers) {
    names[doc.id] = asString(doc.data['name']);
  }
  return names;
}

function buildEventsData(events: FirestoreDoc[]): Record<string, Record<string, unknown>> {
  const data: Record<string, Record<string, unknown>> = {};
  for (const doc of events) {
    data[doc.id] = doc.data;
  }
  return data;
}

function buildChecklistNames(items: FirestoreDoc[]): Record<string, string> {
  const names: Record<string, string> = {};
  for (const doc of items) {
    names[doc.id] = asString(doc.data['name']);
  }
  return names;
}

function buildPresetNames(items: FirestoreDoc[]): Record<string, string> {
  const names: Record<string, string> = {};
  for (const doc of items) {
    names[doc.id] = asString(doc.data['name']);
  }
  return names;
}

function buildRoleHebrewNames(listsData: Record<string, unknown>): Record<string, string> {
  const roleNames: Record<string, string> = {};
  for (const roleValue of asList(listsData['Roles'])) {
    const role = asMap(roleValue);
    if (role == null) continue;
    const key = asString(role['key']);
    if (key.length === 0) continue;
    roleNames[key] = asString(role['hebrewName']) || key;
  }
  return roleNames;
}

function buildRoleSortOrders(listsData: Record<string, unknown>): Record<string, number> {
  const sortOrders: Record<string, number> = {};
  for (const roleValue of asList(listsData['Roles'])) {
    const role = asMap(roleValue);
    if (role == null) continue;
    const key = asString(role['key']);
    if (key.length === 0) continue;
    const sortOrder = role['sortOrder'];
    sortOrders[key] = typeof sortOrder === 'number' && Number.isFinite(sortOrder)
      ? sortOrder
      : 9999;
  }
  return sortOrders;
}

function buildCategoryNames(listsData: Record<string, unknown>): Record<string, string> {
  const categories: Record<string, string> = {};
  const list = asList(listsData['Categories']);
  list.forEach((categoryValue, index) => {
    const category = asMap(categoryValue);
    if (category == null) return;
    const id = asString(category['id']) || String(index);
    categories[id] = asString(category['name']);
  });
  return categories;
}

function serializeTeamMembers(
  teamMembers: FirestoreDoc[],
  eventsData: Record<string, Record<string, unknown>>,
  roleHebrewNames: Record<string, string>,
): Record<string, unknown> {
  const headers = [
    'id',
    'name',
    'isActive',
    'isPermanent',
    'isArchived',
    'comments',
    'uniqueKey',
    'isAdmin',
    'passcode',
    'passcodeLength',
    'allowMultipleAssignments',
    'phoneNumber',
    'birthday',
    'canAccessSummaryScreen',
    'vehicleNumber',
    'vehicleManufacturer',
    'vehicleModel',
    'vehicleColor',
    'availableEvents',
    'roleCapabilities',
    'createdAt',
    'updatedAt',
  ];

  const rows = teamMembers.map((doc) => {
    const vehicle = asMap(doc.data['vehicleInfo']);
    return [
      doc.id,
      asString(doc.data['name']),
      doc.data['isActive'] ?? true,
      doc.data['isPermanent'] ?? false,
      doc.data['isArchived'] ?? false,
      asString(doc.data['comments']),
      asString(doc.data['uniqueKey']),
      doc.data['isAdmin'] ?? false,
      asString(doc.data['passcode']),
      doc.data['passcodeLength'] ?? null,
      doc.data['allowMultipleAssignments'] ?? false,
      asString(doc.data['phoneNumber']),
      formatDate(doc.data['birthday']),
      doc.data['canAccessSummaryScreen'] ?? false,
      asString(vehicle?.['vehicleNumber']),
      asString(vehicle?.['manufacturer']),
      asString(vehicle?.['model']),
      asString(vehicle?.['color']),
      formatAvailableEvents(doc.data['availableEventIds'], eventsData),
      roleCapabilitiesToHebrew(doc.data['roleCapabilities'], roleHebrewNames),
      toTimestampString(doc.data['createdAt']),
      toTimestampString(doc.data['updatedAt']),
    ];
  });

  return {
    sheetName: 'חברי צוות',
    headers,
    rows,
    textColumns: [8, 14],
  };
}

function serializeConstraints(
  teamMembers: FirestoreDoc[],
  memberNames: Record<string, string>,
): Record<string, unknown> {
  const headers = [
    'teamMemberId',
    'teamMemberName',
    'constraintId',
    'startDate',
    'endDate',
    'startTime',
    'endTime',
    'note',
    'status',
    'constraintType',
    'wasAutoRejectedFromCalendar',
  ];

  const rows: unknown[][] = [];
  for (const doc of teamMembers) {
    for (const constraintValue of asList(doc.data['constraints'])) {
      const constraint = asMap(constraintValue);
      if (constraint == null) continue;
      rows.push([
        doc.id,
        memberNames[doc.id] ?? '',
        asString(constraint['id']),
        formatDate(constraint['startDate']),
        formatDate(constraint['endDate']),
        asString(constraint['startTime']),
        asString(constraint['endTime']),
        asString(constraint['note']),
        asString(constraint['status']),
        asString(constraint['constraintType']),
        constraint['wasAutoRejectedFromCalendar'] ?? false,
      ]);
    }
  }

  return {sheetName: 'מגבלות חברי צוות', headers, rows};
}

function serializeEvents(
  events: FirestoreDoc[],
  memberNames: Record<string, string>,
  categoryNames: Record<string, string>,
  roleHebrewNames: Record<string, string>,
): Record<string, unknown> {
  const headers = [
    'id',
    'name',
    'startDate',
    'endDate',
    'startTime',
    'endTime',
    'assemblyTime',
    'actualShowStartTime',
    'location',
    'parkingLocation',
    'parkingEditors',
    'requiresArmed',
    'comments',
    'category',
    'roleRequirements',
    'driveFolderId',
    'driveFolderLink',
    'isArchived',
    'relevantForExtendedTeam',
    'createdAt',
    'updatedAt',
  ];

  const rows = events.map((doc) => [
    doc.id,
    asString(doc.data['name']),
    formatDate(doc.data['startDate']),
    formatDate(doc.data['endDate']),
    asString(doc.data['startTime']),
    asString(doc.data['endTime']),
    asString(doc.data['assemblyTime']),
    asString(doc.data['actualShowStartTime']),
    asString(doc.data['location']),
    asString(doc.data['parkingLocation']),
    idsToNames(doc.data['parkingEditorIds'], memberNames),
    doc.data['requiresArmed'] ?? false,
    asString(doc.data['comments']) || asString(doc.data['notes']),
    categoryNames[asString(doc.data['categoryId'])] ?? '',
    roleRequirementsToHebrew(doc.data['roleRequirements'], roleHebrewNames),
    asString(doc.data['driveFolderId']),
    asString(doc.data['driveFolderLink']),
    doc.data['isArchived'] ?? false,
    doc.data['relevantForExtendedTeam'] ?? false,
    toTimestampString(doc.data['createdAt']),
    toTimestampString(doc.data['updatedAt']),
  ]);

  return {sheetName: 'אירועים', headers, rows};
}

function serializeAssignments(
  assignments: FirestoreDoc[],
  eventsData: Record<string, Record<string, unknown>>,
  memberNames: Record<string, string>,
  roleHebrewNames: Record<string, string>,
): Record<string, unknown> {
  const headers = [
    'id',
    'event',
    'eventStartDate',
    'eventEndDate',
    'eventStartTime',
    'eventEndTime',
    'teamMember',
    'roleType',
    'slotIndex',
    'status',
    'notes',
    'alternativePhoneNumber',
    'createdAt',
    'updatedAt',
  ];

  const rows = assignments.map((doc) => {
    const eventId = asString(doc.data['eventId']);
    const eventData = eventsData[eventId] ?? {};
    const roleKey = asString(doc.data['roleType']);
    return [
      doc.id,
      asString(eventData['name']) || eventId,
      formatDate(eventData['startDate']),
      formatDate(eventData['endDate']),
      asString(eventData['startTime']),
      asString(eventData['endTime']),
      memberNames[asString(doc.data['teamMemberId'])] ?? asString(doc.data['teamMemberId']),
      roleHebrewNames[roleKey] ?? roleKey,
      doc.data['slotIndex'] ?? 0,
      asString(doc.data['status']),
      asString(doc.data['notes']),
      asString(doc.data['alternativePhoneNumber']),
      toTimestampString(doc.data['createdAt']),
      toTimestampString(doc.data['updatedAt']),
    ];
  });

  return {sheetName: 'שיבוצים', headers, rows};
}

function serializeChecklistItems(
  checklistItems: FirestoreDoc[],
  eventsData: Record<string, Record<string, unknown>>,
  memberNames: Record<string, string>,
): Record<string, unknown> {
  const headers = [
    'id',
    'event',
    'name',
    'responsible',
    'CCs',
    'status',
    'createdByAdmin',
    'createdAt',
    'updatedAt',
    'statusLastUpdatedAt',
  ];

  const rows = checklistItems.map((doc) => {
    const eventId = asString(doc.data['eventId']);
    const eventData = eventsData[eventId] ?? {};
    return [
      doc.id,
      asString(eventData['name']) || eventId,
      asString(doc.data['name']),
      memberNames[asString(doc.data['responsibleId'])] ?? asString(doc.data['responsibleId']),
      idsToNames(doc.data['ccIds'], memberNames),
      doc.data['status'] ?? false,
      memberNames[asString(doc.data['createdByAdminId'])] ?? asString(doc.data['createdByAdminId']),
      toTimestampString(doc.data['createdAt']),
      toTimestampString(doc.data['updatedAt']),
      toTimestampString(doc.data['statusLastUpdatedAt']),
    ];
  });

  return {sheetName: 'צ\'קליסט', headers, rows};
}

function serializeChecklistNotes(
  checklistItems: FirestoreDoc[],
  checklistNames: Record<string, string>,
  memberNames: Record<string, string>,
): Record<string, unknown> {
  const headers = [
    'checklistItemId',
    'checklistItemName',
    'noteId',
    'content',
    'createdByTeamMemberId',
    'createdByTeamMemberName',
    'authorRole',
    'createdAt',
  ];

  const rows: unknown[][] = [];
  for (const doc of checklistItems) {
    for (const noteValue of asList(doc.data['notes'])) {
      const note = asMap(noteValue);
      if (note == null) continue;
      const authorId = asString(note['createdByTeamMemberId']);
      rows.push([
        doc.id,
        checklistNames[doc.id] ?? '',
        asString(note['id']),
        asString(note['content']),
        authorId,
        asString(note['createdByTeamMemberName']) || memberNames[authorId] || '',
        asString(note['authorRole']),
        toTimestampString(note['createdAt']),
      ]);
    }
  }

  return {sheetName: 'הערות צ\'קליסט', headers, rows};
}

function serializePresets(presets: FirestoreDoc[]): Record<string, unknown> {
  const headers = ['id', 'name', 'itemCount', 'createdAt', 'updatedAt'];
  const rows = presets.map((doc) => [
    doc.id,
    asString(doc.data['name']),
    asList(doc.data['items']).length,
    toTimestampString(doc.data['createdAt']),
    toTimestampString(doc.data['updatedAt']),
  ]);
  return {sheetName: 'תבניות צ\'קליסט', headers, rows};
}

function serializePresetItems(
  presets: FirestoreDoc[],
  presetNames: Record<string, string>,
  memberNames: Record<string, string>,
): Record<string, unknown> {
  const headers = ['presetId', 'presetName', 'itemName', 'responsible', 'CCs', 'adminNote'];
  const rows: unknown[][] = [];
  for (const doc of presets) {
    for (const itemValue of asList(doc.data['items'])) {
      const item = asMap(itemValue);
      if (item == null) continue;
      rows.push([
        doc.id,
        presetNames[doc.id] ?? '',
        asString(item['name']),
        memberNames[asString(item['responsibleId'])] ?? asString(item['responsibleId']),
        idsToNames(item['ccIds'], memberNames),
        asString(item['adminNote']),
      ]);
    }
  }
  return {sheetName: 'פריטי תבניות', headers, rows};
}

function serializeCalendarSync(calendarSync: FirestoreDoc[]): Record<string, unknown> {
  const headers = [
    'constraintId',
    'calendarEventId',
    'teamMemberId',
    'status',
    'syncedAt',
    'updatedAt',
    'retryCount',
    'errorMessage',
  ];

  const rows = calendarSync.map((doc) => [
    doc.id,
    asString(doc.data['calendarEventId']),
    asString(doc.data['teamMemberId']),
    asString(doc.data['status']),
    toTimestampString(doc.data['syncedAt']),
    toTimestampString(doc.data['updatedAt']),
    doc.data['retryCount'] ?? 0,
    asString(doc.data['errorMessage']),
  ]);

  return {sheetName: 'סנכרון יומן', headers, rows};
}

function isSensitiveKeyField(documentId: string, fieldName: string): boolean {
  const normalizedField = fieldName.toLowerCase();
  if (SENSITIVE_KEY_FIELDS.has(normalizedField)) {
    return true;
  }
  return documentId === 'googleDrive' && normalizedField === 'apikey';
}

function serializeKeys(keys: FirestoreDoc[]): Record<string, unknown> {
  const headers = ['documentId', 'field', 'value'];
  const rows: unknown[][] = [];

  for (const doc of keys) {
    for (const [field, value] of Object.entries(doc.data)) {
      rows.push([
        doc.id,
        field,
        isSensitiveKeyField(doc.id, field)
          ? '[REDACTED]'
          : asMap(value) != null || Array.isArray(value)
              ? jsonEncode(value)
              : value?.toString() ?? '',
      ]);
    }
  }

  return {sheetName: 'מפתחות', headers, rows};
}

function serializeRoles(listsData: Record<string, unknown>): Record<string, unknown> {
  const headers = [
    'id',
    'key',
    'hebrewName',
    'isVisible',
    'isArchived',
    'sortOrder',
    'createdAt',
    'updatedAt',
  ];

  const rows = asList(listsData['Roles'])
    .map((value) => asMap(value))
    .filter((value): value is Record<string, unknown> => value != null)
    .map((role) => [
      asString(role['id']) || asString(role['key']),
      asString(role['key']),
      asString(role['hebrewName']),
      role['isVisible'] ?? true,
      role['isArchived'] ?? false,
      role['sortOrder'] ?? 0,
      toTimestampString(role['createdAt']),
      toTimestampString(role['updatedAt']),
    ]);

  return {sheetName: 'תפקידים', headers, rows};
}

function serializeCategories(listsData: Record<string, unknown>): Record<string, unknown> {
  const headers = ['id', 'name', 'sortOrder', 'isArchived', 'createdAt', 'updatedAt'];
  const rows = asList(listsData['Categories']).map((value, index) => {
    const category = asMap(value) ?? {};
    return [
      asString(category['id']) || String(index),
      asString(category['name']),
      category['sortOrder'] ?? index,
      category['isArchived'] ?? false,
      toTimestampString(category['createdAt']),
      toTimestampString(category['updatedAt']),
    ];
  });
  return {sheetName: 'קטגוריות', headers, rows};
}

function serializeMetadata(counts: {
  teamMembers: number;
  events: number;
  assignments: number;
  checklistItems: number;
  presets: number;
  calendarSync: number;
  keys: number;
}): Record<string, unknown> {
  const headers = ['key', 'value'];
  const rows = [
    ['exportedAt', new Date().toISOString()],
    ['teamMembers', counts.teamMembers],
    ['events', counts.events],
    ['assignments', counts.assignments],
    ['checklist_items', counts.checklistItems],
    ['checklist_presets', counts.presets],
    ['calendar_sync', counts.calendarSync],
    ['keys', counts.keys],
  ];
  return {sheetName: '_metadata', headers, rows};
}

type AssignmentOnlySerializeOptions = {
  mode: AssignmentExportMode;
  selectedEventIds: string[];
  roleSortOrders: Record<string, number>;
};

type AssignmentOnlyRow = {
  teamMember: string;
  teamMemberId: string;
  roleKey: string;
  roleType: string;
  eventId: string;
  event: string;
  eventStartDate: string;
  eventEndDate: string;
  eventStartDateKey: string;
  eventStartTime: string;
  eventEndTime: string;
  location: string;
  assemblyTime: string;
  notes: string;
};

function eventDayRange(eventData: Record<string, unknown>): [string, string] | null {
  const start = parseDate(eventData['startDate']);
  const end = parseDate(eventData['endDate']);
  if (start == null || end == null) return null;
  const startKey = israelCalendarDateKey(start);
  const endKey = israelCalendarDateKey(end);
  if (startKey.length === 0 || endKey.length === 0) return null;
  return [startKey, endKey];
}

/** Day-precision overlap. Date keys are 'YYYY-MM-DD', so string order is date order. */
function eventsShareDay(
  first: Record<string, unknown>,
  second: Record<string, unknown>,
): boolean {
  const a = eventDayRange(first);
  const b = eventDayRange(second);
  if (a == null || b == null) return false;
  return a[0] <= b[1] && b[0] <= a[1];
}

/**
 * memberId -> eventId -> names of the OTHER events sharing a calendar day with
 * that event to which the member is also assigned, sorted by start date then
 * name.
 *
 * `eventsData` is the future-filtered pool (`filterFutureEventsData`'s output) —
 * the same set the export's own rows are built from, not every event ever
 * created. This is deliberate, for parity with the UI: `/admin/assignments` and
 * `/summary` never mark a conflict on a day that has already passed, so the
 * export must not either. An event that has already ended is simply absent from
 * `eventsData` and can never be named here.
 *
 * `filterFutureEventsData` already drops deactivated events too, so the inline
 * `isDeactivated` check below is belt-and-braces — redundant given the caller's
 * current pool, but it keeps this function correct standalone if ever called
 * with a differently-filtered map.
 *
 * Symmetric by construction: if a member is in E and O on a shared day, the map
 * names O under E *and* E under O.
 */
function buildSameDayOtherEventNames(
  assignments: FirestoreDoc[],
  eventsData: Record<string, Record<string, unknown>>,
): Map<string, Map<string, string[]>> {
  const eventIdsByMember = new Map<string, Set<string>>();
  for (const doc of assignments) {
    const memberId = asString(doc.data['teamMemberId']);
    const eventId = asString(doc.data['eventId']);
    if (memberId.length === 0 || eventId.length === 0) continue;
    const eventData = eventsData[eventId];
    if (eventData == null || eventData['isDeactivated'] === true) continue;
    const ids = eventIdsByMember.get(memberId) ?? new Set<string>();
    ids.add(eventId);
    eventIdsByMember.set(memberId, ids);
  }

  const result = new Map<string, Map<string, string[]>>();
  for (const [memberId, eventIdSet] of eventIdsByMember) {
    const eventIds = Array.from(eventIdSet);
    if (eventIds.length < 2) continue;

    const perEvent = new Map<string, string[]>();
    for (const eventId of eventIds) {
      const others = eventIds
        .filter(
          (otherId) =>
            otherId !== eventId &&
            eventsShareDay(eventsData[eventId], eventsData[otherId]),
        )
        .sort((first, second) => {
          const byDate = (eventDayRange(eventsData[first])?.[0] ?? '').localeCompare(
            eventDayRange(eventsData[second])?.[0] ?? '',
          );
          if (byDate !== 0) return byDate;
          return asString(eventsData[first]['name']).localeCompare(
            asString(eventsData[second]['name']),
            'he',
          );
        })
        .map((otherId) => asString(eventsData[otherId]['name']));
      if (others.length > 0) perEvent.set(eventId, others);
    }
    if (perEvent.size > 0) result.set(memberId, perEvent);
  }
  return result;
}

function decorateTeamMemberName(
  row: AssignmentOnlyRow,
  sameDayOtherEventNames: Map<string, Map<string, string[]>>,
): string {
  const others = sameDayOtherEventNames.get(row.teamMemberId)?.get(row.eventId);
  if (others == null || others.length === 0) return row.teamMember;
  return `${row.teamMember} (משובץ גם ב${others.join(', ')})`;
}

function serializeAssignmentsOnly(
  assignments: FirestoreDoc[],
  eventsData: Record<string, Record<string, unknown>>,
  memberNames: Record<string, string>,
  roleHebrewNames: Record<string, string>,
  options: AssignmentOnlySerializeOptions,
): Record<string, unknown> {
  const headers = [
    'שם חבר צוות',
    'תפקיד',
    'אירוע',
    'תאריך תחילת אירוע',
    'תאריך סיום',
    'שעת התייצבות',
    'שעת תחילת אירוע',
    'שעת סיום אירוע',
    'מיקום',
    'הערות שיבוץ',
  ];

  const dedupedSelectedEventIds = Array.from(new Set(options.selectedEventIds));
  if (options.mode === 'perEvent') {
    const invalidEventIds = dedupedSelectedEventIds.filter((eventId) => eventsData[eventId] == null);
    if (invalidEventIds.length > 0) {
      throw new DriveExportValidationError(
        `Selected future event IDs are invalid: ${invalidEventIds.join(', ')}`,
      );
    }
  }

  const selectedEventIds = new Set(dedupedSelectedEventIds);
  const shouldIncludeEvent = (eventId: string): boolean => {
    if (options.mode === 'perPerson') return true;
    return selectedEventIds.has(eventId);
  };

  const rows = assignments
    .map((doc) => {
      const eventId = asString(doc.data['eventId']);
      if (!shouldIncludeEvent(eventId)) return null;
      const eventData = eventsData[eventId];
      if (eventData == null) return null;
      const startDate = parseDate(eventData['startDate']);
      const endDate = parseDate(eventData['endDate']);
      const startDateKey = startDate == null ? '' : israelCalendarDateKey(startDate);
      const endDateKey = endDate == null ? '' : israelCalendarDateKey(endDate);
      const singleDay =
        startDateKey.length > 0 && endDateKey.length > 0 && startDateKey === endDateKey;
      const roleKey = asString(doc.data['roleType']);
      return {
        teamMember: memberNames[asString(doc.data['teamMemberId'])] ?? '',
        teamMemberId: asString(doc.data['teamMemberId']),
        roleKey,
        roleType: roleHebrewNames[roleKey] ?? roleKey,
        eventId,
        event: asString(eventData['name']),
        eventStartDate: formatIsraelCalendarDateKey(startDateKey),
        eventEndDate: singleDay ? '' : formatIsraelCalendarDateKey(endDateKey),
        eventStartDateKey: startDateKey,
        eventStartTime: asString(eventData['startTime']),
        eventEndTime: asString(eventData['endTime']),
        location: cleanLocation(eventData['location']),
        assemblyTime: asString(eventData['assemblyTime']),
        notes: asString(doc.data['notes']),
      };
    })
    .filter(
      (
        value,
      ): value is AssignmentOnlyRow => value != null,
    );

  rows.sort((first, second) => {
    const dateCompare = compareDateKeys(first.eventStartDateKey, second.eventStartDateKey);

    if (options.mode === 'perPerson') {
      const memberCompare = first.teamMember.localeCompare(second.teamMember);
      if (memberCompare !== 0) return memberCompare;

      if (dateCompare !== 0) return dateCompare;

      const timeCompare = first.eventStartTime.localeCompare(second.eventStartTime);
      if (timeCompare !== 0) return timeCompare;

      return first.roleType.localeCompare(second.roleType);
    }

    if (dateCompare !== 0) return dateCompare;

    const timeCompare = first.eventStartTime.localeCompare(second.eventStartTime);
    if (timeCompare !== 0) return timeCompare;

    const eventCompare = first.event.localeCompare(second.event);
    if (eventCompare !== 0) return eventCompare;

    const roleOrderCompare =
      (options.roleSortOrders[first.roleKey] ?? 9999) -
      (options.roleSortOrders[second.roleKey] ?? 9999);
    if (roleOrderCompare !== 0) return roleOrderCompare;

    const roleCompare = first.roleType.localeCompare(second.roleType);
    if (roleCompare !== 0) return roleCompare;

    return first.teamMember.localeCompare(second.teamMember);
  });

  // perEvent only: the boss asked for the mark in the לפי אירוע export.
  const sameDayOtherEventNames =
    options.mode === 'perEvent'
      ? buildSameDayOtherEventNames(assignments, eventsData)
      : new Map<string, Map<string, string[]>>();

  return {
    sheetName: 'שיבוצים',
    headers,
    // The suffix is applied HERE, in the projection, and never on the row object.
    // This is load-bearing, not stylistic: the perEvent sort's last tiebreak is
    // `first.teamMember.localeCompare(second.teamMember)`, so a decorated row would
    // fold the mark into the sort key. Two members with the SAME name (namesakes, or
    // both falling back to '' when a member doc is missing) tie on the clean name and
    // keep their input order; decorate the row and the plain one jumps ahead of the
    // marked one, silently reordering the sheet. Pinned by the "sorts on the clean
    // name" test. (perPerson's colorByTeamMember also bands on column A, but that is
    // separately protected by the perEvent gate above.)
    rows: rows.map((row) => [
      decorateTeamMemberName(row, sameDayOtherEventNames),
      row.roleType,
      row.event,
      row.eventStartDate,
      row.eventEndDate,
      row.assemblyTime,
      row.eventStartTime,
      row.eventEndTime,
      row.location,
      row.notes,
    ]),
    colorByTeamMember: options.mode === 'perPerson',
  };
}

function compareDateKeys(first: string, second: string): number {
  if (first.length > 0 && second.length > 0) {
    return first.localeCompare(second);
  }
  if (first.length > 0) {
    return -1;
  }
  if (second.length > 0) {
    return 1;
  }
  return 0;
}

async function readCollection(
  firestore: Firestore,
  collectionName: string,
): Promise<FirestoreDoc[]> {
  const snapshot = await firestore.collection(collectionName).get();
  return snapshot.docs.map((doc) => ({
    id: doc.id,
    data: (doc.data() ?? {}) as Record<string, unknown>,
  }));
}

async function readDocument(
  firestore: Firestore,
  collectionName: string,
  documentId: string,
): Promise<Record<string, unknown>> {
  const doc = await firestore.collection(collectionName).doc(documentId).get();
  return doc.exists ? ((doc.data() ?? {}) as Record<string, unknown>) : {};
}

async function getDriveConfig(firestore: Firestore): Promise<DriveConfig> {
  const doc = await firestore.collection(PRODUCTION_COLLECTIONS.keys).doc('googleDrive').get();
  if (!doc.exists) {
    throw new Error('Missing Google Drive export config in keys/googleDrive');
  }

  const data = (doc.data() ?? {}) as Record<string, unknown>;
  const scriptUrl = asOptionalString(data['scriptUrl']);
  const apiKey = asOptionalString(data['apiKey']);
  if (scriptUrl == null || apiKey == null) {
    throw new Error('Missing Google Drive export config in keys/googleDrive');
  }

  return {scriptUrl, apiKey};
}

async function postToDriveScript(
  driveConfig: DriveConfig,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const response = await fetch(driveConfig.scriptUrl, {
    method: 'POST',
    headers: {'Content-Type': 'text/plain;charset=UTF-8'},
    body: JSON.stringify({
      apiKey: driveConfig.apiKey,
      ...payload,
    }),
  });

  const rawBody = await response.text();
  let decoded: Record<string, unknown> = {};
  if (rawBody.length > 0) {
    try {
      decoded = JSON.parse(rawBody) as Record<string, unknown>;
    } catch {
      decoded = {success: false, error: rawBody};
    }
  }

  if (response.ok) {
    return decoded;
  }

  const errorMessage =
    asOptionalString(decoded['error']) ??
    `HTTP ${response.status}${rawBody.length > 0 ? `: ${rawBody}` : ''}`;
  return {
    success: false,
    error: errorMessage,
  };
}

function sanitizeDriveActionPayload(
  action: DriveAction,
  body: Record<string, unknown>,
): Record<string, unknown> {
  switch (action) {
    case 'createFolder':
      return {
        action,
        name: asString(body['name']),
        date: asString(body['date']),
        endDate: body['endDate'] ?? null,
      };
    case 'renameFolder':
      return {
        action,
        folderId: asString(body['folderId']),
        name: asString(body['name']),
        date: asString(body['date']),
        endDate: body['endDate'] ?? null,
      };
    case 'deleteFolder':
      return {
        action,
        folderId: asString(body['folderId']),
      };
    case 'listFiles':
      return {
        action,
        folderId: asString(body['folderId']),
      };
    case 'archiveCheck':
      return {
        action,
        events: asList(body['events']).map((entry) => normalizeJsonValue(entry)),
      };
  }
}

export async function executeDriveAction(
  firestore: Firestore,
  action: DriveAction,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const driveConfig = await getDriveConfig(firestore);
  return await postToDriveScript(driveConfig, sanitizeDriveActionPayload(action, body));
}

export async function exportProductionDataToSheets(
  firestore: Firestore,
  exportType: DriveExportType,
  options: AssignmentExportOptions = {},
): Promise<Record<string, unknown>> {
  const driveConfig = await getDriveConfig(firestore);

  if (exportType === 'assignments') {
    const [assignments, events, teamMembers, listsData] = await Promise.all([
      readCollection(firestore, PRODUCTION_COLLECTIONS.assignments),
      readCollection(firestore, PRODUCTION_COLLECTIONS.events),
      readCollection(firestore, PRODUCTION_COLLECTIONS.teamMembers),
      readDocument(firestore, PRODUCTION_COLLECTIONS.utilities, 'Lists'),
    ]);

    const memberNames = buildMemberNames(teamMembers);
    const eventsData = buildEventsData(events);
    const futureEventsData = filterFutureEventsData(eventsData, options.now ?? new Date());
    const roleHebrewNames = buildRoleHebrewNames(listsData);
    const roleSortOrders = buildRoleSortOrders(listsData);
    const sheets = [
      serializeAssignmentsOnly(assignments, futureEventsData, memberNames, roleHebrewNames, {
        mode: options.assignmentMode ?? 'perPerson',
        selectedEventIds: options.eventIds ?? [],
        roleSortOrders,
      }),
    ];

    const response = await postToDriveScript(driveConfig, {
      action: 'exportAssignmentsOnly',
      exportData: {sheets},
    });

    return {
      success: response['success'] === true,
      spreadsheetUrl: asOptionalString(response['spreadsheetUrl']),
      error: response['success'] === true ? null : asString(response['error']),
    };
  }

  const [
    teamMembers,
    events,
    assignments,
    checklistItems,
    presets,
    calendarSync,
    keys,
    listsData,
  ] = await Promise.all([
    readCollection(firestore, PRODUCTION_COLLECTIONS.teamMembers),
    readCollection(firestore, PRODUCTION_COLLECTIONS.events),
    readCollection(firestore, PRODUCTION_COLLECTIONS.assignments),
    readCollection(firestore, PRODUCTION_COLLECTIONS.checklistItems),
    readCollection(firestore, PRODUCTION_COLLECTIONS.presets),
    readCollection(firestore, PRODUCTION_COLLECTIONS.calendarSync),
    readCollection(firestore, PRODUCTION_COLLECTIONS.keys),
    readDocument(firestore, PRODUCTION_COLLECTIONS.utilities, 'Lists'),
  ]);

  const memberNames = buildMemberNames(teamMembers);
  const eventsData = buildEventsData(events);
  const roleHebrewNames = buildRoleHebrewNames(listsData);
  const categoryNames = buildCategoryNames(listsData);
  const checklistNames = buildChecklistNames(checklistItems);
  const presetNames = buildPresetNames(presets);

  const sheets = [
    serializeTeamMembers(teamMembers, eventsData, roleHebrewNames),
    serializeConstraints(teamMembers, memberNames),
    serializeEvents(events, memberNames, categoryNames, roleHebrewNames),
    serializeAssignments(assignments, eventsData, memberNames, roleHebrewNames),
    serializeChecklistItems(checklistItems, eventsData, memberNames),
    serializeChecklistNotes(checklistItems, checklistNames, memberNames),
    serializePresets(presets),
    serializePresetItems(presets, presetNames, memberNames),
    serializeCalendarSync(calendarSync),
    serializeKeys(keys),
    serializeRoles(listsData),
    serializeCategories(listsData),
    serializeMetadata({
      teamMembers: teamMembers.length,
      events: events.length,
      assignments: assignments.length,
      checklistItems: checklistItems.length,
      presets: presets.length,
      calendarSync: calendarSync.length,
      keys: keys.length,
    }),
  ];

  const response = await postToDriveScript(driveConfig, {
    action: 'exportToSheets',
    exportData: {sheets},
  });

  return {
    success: response['success'] === true,
    spreadsheetUrl: asOptionalString(response['spreadsheetUrl']),
    error: response['success'] === true ? null : asString(response['error']),
  };
}

export function canExecuteDriveAction(action: string): action is DriveAction {
  return [
    'createFolder',
    'renameFolder',
    'deleteFolder',
    'listFiles',
    'archiveCheck',
  ].includes(action);
}

export function __testSerializeAssignmentsOnly(input: {
  assignments: FirestoreDoc[];
  eventsData: Record<string, Record<string, unknown>>;
  memberNames: Record<string, string>;
  roleHebrewNames: Record<string, string>;
  roleSortOrders: Record<string, number>;
  mode: AssignmentExportMode;
  selectedEventIds: string[];
  now: Date;
}): {sheetName: string; headers: string[]; rows: unknown[][]} {
  const futureEventsData = filterFutureEventsData(input.eventsData, input.now);
  return serializeAssignmentsOnly(
    input.assignments,
    futureEventsData,
    input.memberNames,
    input.roleHebrewNames,
    {
      mode: input.mode,
      selectedEventIds: input.selectedEventIds,
      roleSortOrders: input.roleSortOrders,
    },
  ) as {sheetName: string; headers: string[]; rows: unknown[][]};
}
