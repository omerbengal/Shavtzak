# Google Sheets Assignment Export Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the admin assignments Google Sheets export so it exports only future events and supports either per-person export or selected per-event export.

**Architecture:** Keep Google Sheets creation on the existing backend `drive/export` path so the browser never talks to Google Drive directly. Add an assignments export mode to the Flutter request, enforce all filtering and sorting again in Cloud Functions, and use `utilities/Lists.Roles[*].sortOrder` as the source of truth for role ordering.

**Tech Stack:** Flutter Web, Dart, `flutter_bloc`, Cloud Functions v2, TypeScript, Firestore Admin SDK, existing Google Apps Script sheet writer.

---

## Assumptions

- This plan targets the admin app-bar "ייצוא שיבוצים" Google Sheets export, not the Shamap clipboard export.
- "Future event" means `event.endDate` is on or after today's date, using date-only comparison.
- Per-person mode exports every assignment whose event is future, preserving the current sort: person name, event date/time, then role.
- Per-event mode exports assignment rows only, not empty quota slots.
- Per-event mode lets the admin choose multiple future events in the Flutter UI, then exports assignments only for those selected event IDs.
- The full database export remains unchanged unless the product owner later asks for future-only filtering there too.

## File Structure

- Modify `functions/src/drive_export.ts`
  - Extend assignment export options.
  - Add future-event filtering helpers.
  - Add role sort-order lookup from `utilities/Lists.Roles`.
  - Split assignment-only serialization into per-person and per-event sort modes.
- Modify `functions/src/index.ts`
  - Accept `mode` and `eventIds` for `type: 'assignments'`.
  - Validate malformed per-event requests before calling the exporter.
- Create `functions/src/drive_export.test.ts`
  - Unit-test future filtering and both assignment sort modes with deterministic dates.
- Modify `functions/package.json`
  - Add a lightweight `test` script using Node's built-in test runner.
- Modify `shavtzak/lib/core/services/export_service.dart`
  - Add a typed assignment export mode and optional selected event IDs.
- Create `shavtzak/lib/presentation/widgets/assignment_export_dialog.dart`
  - Mode picker: per person or per event.
  - Future-event multi-select for per-event mode.
  - Calls back with the selected mode and event IDs.
- Modify `shavtzak/lib/presentation/screens/admin/admin_choice_screen.dart`
  - Replace the current assignments confirmation dialog with the new mode dialog.
  - Keep loading, success, error, and link dialogs unchanged.

---

## Task 1: Backend Contract And Validation

**Files:**
- Modify: `functions/src/drive_export.ts`
- Modify: `functions/src/index.ts`

- [ ] **Step 1: Update backend export types**

In `functions/src/drive_export.ts`, replace:

```ts
export type DriveExportType = 'full' | 'assignments';
```

with:

```ts
export type DriveExportType = 'full' | 'assignments';
export type AssignmentExportMode = 'perPerson' | 'perEvent';

export type AssignmentExportOptions = {
  assignmentMode?: AssignmentExportMode;
  eventIds?: string[];
  now?: Date;
};
```

- [ ] **Step 2: Update `exportProductionDataToSheets` signature**

Change:

```ts
export async function exportProductionDataToSheets(
  firestore: Firestore,
  exportType: DriveExportType,
): Promise<Record<string, unknown>> {
```

to:

```ts
export async function exportProductionDataToSheets(
  firestore: Firestore,
  exportType: DriveExportType,
  options: AssignmentExportOptions = {},
): Promise<Record<string, unknown>> {
```

- [ ] **Step 3: Parse and validate assignment export request body**

In `functions/src/index.ts`, replace the current `/drive/export` body handling:

```ts
const type = request.body?.type === 'assignments' ? 'assignments' : 'full';
const result = await exportProductionDataToSheets(db, type);
```

with:

```ts
const type = request.body?.type === 'assignments' ? 'assignments' : 'full';
const rawMode = request.body?.mode;
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
```

- [ ] **Step 4: Build functions**

Run:

```bash
npm --prefix functions run build
```

Expected: TypeScript compilation succeeds.

---

## Task 2: Future-Only Assignment Export Filtering

**Files:**
- Modify: `functions/src/drive_export.ts`
- Test: `functions/src/drive_export.test.ts`
- Modify: `functions/package.json`

- [ ] **Step 1: Add deterministic date helpers**

Add helpers near `parseDate` in `functions/src/drive_export.ts`:

```ts
function dateOnlyUtc(value: Date): Date {
  return new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate()));
}

function isFutureOrTodayByEndDate(
  eventData: Record<string, unknown>,
  now: Date,
): boolean {
  const endDate = parseDate(eventData['endDate']);
  if (endDate == null) return false;
  return dateOnlyUtc(endDate).getTime() >= dateOnlyUtc(now).getTime();
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
```

- [ ] **Step 2: Apply future filter before assignment serialization**

Inside the `exportType === 'assignments'` branch in `exportProductionDataToSheets`, replace:

```ts
const eventsData = buildEventsData(events);
const roleHebrewNames = buildRoleHebrewNames(listsData);
const sheets = [
  serializeAssignmentsOnly(assignments, eventsData, memberNames, roleHebrewNames),
];
```

with:

```ts
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
```

- [ ] **Step 3: Add Node test script**

In `functions/package.json`, add:

```json
"test": "npm run build && node --test \"lib/**/*.test.js\""
```

Keep the existing scripts unchanged.

- [ ] **Step 4: Write future filtering test**

Create `functions/src/drive_export.test.ts` and test through exported pure helpers from Task 3:

```ts
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  __testSerializeAssignmentsOnly,
} from './drive_export';

test('per-person assignments export includes only events whose endDate is today or later', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a-past', data: {eventId: 'past', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a-today', data: {eventId: 'today', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a-future', data: {eventId: 'future', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      past: {name: 'Past', startDate: new Date('2026-05-01T00:00:00.000Z'), endDate: new Date('2026-05-02T00:00:00.000Z')},
      today: {name: 'Today', startDate: new Date('2026-05-03T00:00:00.000Z'), endDate: new Date('2026-05-03T00:00:00.000Z')},
      future: {name: 'Future', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z')},
    },
    memberNames: {m1: 'אדם אחד'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perPerson',
    selectedEventIds: [],
    now: new Date('2026-05-03T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[2]), ['Today', 'Future']);
});
```

- [ ] **Step 5: Run tests**

Run:

```bash
npm --prefix functions test
```

Expected: the new test passes.

---

## Task 3: Per-Person And Per-Event Serialization

**Files:**
- Modify: `functions/src/drive_export.ts`
- Modify: `functions/src/drive_export.test.ts`

- [ ] **Step 1: Add role sort-order helper**

Add near `buildRoleHebrewNames`:

```ts
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
```

- [ ] **Step 2: Replace `serializeAssignmentsOnly` options**

Change its signature to:

```ts
type AssignmentOnlySerializeOptions = {
  mode: AssignmentExportMode;
  selectedEventIds: string[];
  roleSortOrders: Record<string, number>;
};

type AssignmentOnlyRow = {
  teamMember: string;
  roleKey: string;
  roleType: string;
  eventId: string;
  event: string;
  eventStartDate: string;
  eventEndDate: string;
  eventStartDateObj: Date | null;
  eventStartTime: string;
  eventEndTime: string;
  location: string;
  assemblyTime: string;
  notes: string;
};

function serializeAssignmentsOnly(
  assignments: FirestoreDoc[],
  eventsData: Record<string, Record<string, unknown>>,
  memberNames: Record<string, string>,
  roleHebrewNames: Record<string, string>,
  options: AssignmentOnlySerializeOptions,
): Record<string, unknown> {
```

- [ ] **Step 3: Filter selected events only for per-event mode**

At the top of `serializeAssignmentsOnly`, add:

```ts
const selectedEventIds = new Set(options.selectedEventIds);
const shouldIncludeEvent = (eventId: string): boolean => {
  if (options.mode === 'perPerson') return true;
  return selectedEventIds.has(eventId);
};
```

Inside the assignment `.map`, after reading `eventId`, add:

```ts
if (!shouldIncludeEvent(eventId)) return null;
```

Because `eventsData` was already future-filtered in Task 2, this guarantees both modes exclude past events.

- [ ] **Step 4: Preserve current per-person sort**

Keep the current sort logic for `options.mode === 'perPerson'`:

```ts
if (options.mode === 'perPerson') {
  rows.sort((first, second) => {
    const memberCompare = first.teamMember.localeCompare(second.teamMember);
    if (memberCompare !== 0) return memberCompare;

    if (first.eventStartDateObj != null && second.eventStartDateObj != null) {
      const dateCompare = first.eventStartDateObj.getTime() - second.eventStartDateObj.getTime();
      if (dateCompare !== 0) return dateCompare;
    } else if (first.eventStartDateObj != null) {
      return -1;
    } else if (second.eventStartDateObj != null) {
      return 1;
    }

    const timeCompare = first.eventStartTime.localeCompare(second.eventStartTime);
    if (timeCompare !== 0) return timeCompare;

    return first.roleType.localeCompare(second.roleType);
  });
}
```

- [ ] **Step 5: Add per-event sort**

For `options.mode === 'perEvent'`, sort by event start date, event time/name tie-breakers, role sort order, role name, then person name:

```ts
if (options.mode === 'perEvent') {
  rows.sort((first, second) => {
    if (first.eventStartDateObj != null && second.eventStartDateObj != null) {
      const dateCompare = first.eventStartDateObj.getTime() - second.eventStartDateObj.getTime();
      if (dateCompare !== 0) return dateCompare;
    } else if (first.eventStartDateObj != null) {
      return -1;
    } else if (second.eventStartDateObj != null) {
      return 1;
    }

    const timeCompare = first.eventStartTime.localeCompare(second.eventStartTime);
    if (timeCompare !== 0) return timeCompare;

    const eventCompare = first.event.localeCompare(second.event);
    if (eventCompare !== 0) return eventCompare;

    const firstRoleOrder = options.roleSortOrders[first.roleKey] ?? 9999;
    const secondRoleOrder = options.roleSortOrders[second.roleKey] ?? 9999;
    const roleOrderCompare = firstRoleOrder - secondRoleOrder;
    if (roleOrderCompare !== 0) return roleOrderCompare;

    const roleNameCompare = first.roleType.localeCompare(second.roleType);
    if (roleNameCompare !== 0) return roleNameCompare;

    return first.teamMember.localeCompare(second.teamMember);
  });
}
```

- [ ] **Step 6: Include role key in row mapping**

When building each row object, store both key and Hebrew display name:

```ts
const roleKey = asString(doc.data['roleType']);
return {
  teamMember: memberNames[asString(doc.data['teamMemberId'])] ?? '',
  roleKey,
  roleType: roleHebrewNames[roleKey] ?? roleKey,
  eventId,
  event: asString(eventData['name']),
  eventStartDate: formatDate(eventData['startDate']),
  eventEndDate: singleDay ? '' : formatDate(eventData['endDate']),
  eventStartDateObj: startDate,
  eventStartTime: asString(eventData['startTime']),
  eventEndTime: asString(eventData['endTime']),
  location: cleanLocation(eventData['location']),
  assemblyTime: asString(eventData['assemblyTime']),
  notes: asString(doc.data['notes']),
};
```

- [ ] **Step 7: Keep sheet output shape unchanged**

Return the same headers and row columns as today. Set row coloring only for per-person mode:

```ts
return {
  sheetName: 'שיבוצים',
  headers,
  rows: rows.map((row) => [
    row.teamMember,
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
```

- [ ] **Step 8: Export test-only serializer wrapper**

At the bottom of `functions/src/drive_export.ts`, add:

```ts
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
```

- [ ] **Step 9: Add per-person sort regression test**

In `functions/src/drive_export.test.ts`, add:

```ts
test('per-person assignments export sorts by person then event date', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'late', data: {eventId: 'e2', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'other', data: {eventId: 'e1', teamMemberId: 'm2', roleType: 'medic'}},
      {id: 'early', data: {eventId: 'e1', teamMemberId: 'm1', roleType: 'paramedic'}},
    ],
    eventsData: {
      e1: {name: 'Early', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z'), startTime: '10:00'},
      e2: {name: 'Late', startDate: new Date('2026-05-05T00:00:00.000Z'), endDate: new Date('2026-05-05T00:00:00.000Z'), startTime: '10:00'},
    },
    memberNames: {m1: 'אדם א', m2: 'בני ב'},
    roleHebrewNames: {medic: 'חובש', paramedic: 'פרמדיק'},
    roleSortOrders: {paramedic: 0, medic: 1},
    mode: 'perPerson',
    selectedEventIds: [],
    now: new Date('2026-05-03T00:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => [row[0], row[2], row[1]]), [
    ['אדם א', 'Early', 'פרמדיק'],
    ['אדם א', 'Late', 'חובש'],
    ['בני ב', 'Early', 'חובש'],
  ]);
});
```

- [ ] **Step 10: Add per-event selection and role-order test**

In `functions/src/drive_export.test.ts`, add:

```ts
test('per-event assignments export filters selected events and sorts by event, role order, then person', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'not-selected', data: {eventId: 'e3', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'role-second-a', data: {eventId: 'e1', teamMemberId: 'm2', roleType: 'medic'}},
      {id: 'role-first', data: {eventId: 'e1', teamMemberId: 'm3', roleType: 'paramedic'}},
      {id: 'role-second-b', data: {eventId: 'e1', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'later-event', data: {eventId: 'e2', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      e1: {name: 'First Event', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z'), startTime: '18:00'},
      e2: {name: 'Second Event', startDate: new Date('2026-05-05T00:00:00.000Z'), endDate: new Date('2026-05-05T00:00:00.000Z'), startTime: '18:00'},
      e3: {name: 'Ignored Event', startDate: new Date('2026-05-06T00:00:00.000Z'), endDate: new Date('2026-05-06T00:00:00.000Z'), startTime: '18:00'},
    },
    memberNames: {m1: 'אדם א', m2: 'בני ב', m3: 'גדי ג'},
    roleHebrewNames: {medic: 'חובש', paramedic: 'פרמדיק'},
    roleSortOrders: {paramedic: 0, medic: 1},
    mode: 'perEvent',
    selectedEventIds: ['e1', 'e2'],
    now: new Date('2026-05-03T00:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => [row[2], row[1], row[0]]), [
    ['First Event', 'פרמדיק', 'גדי ג'],
    ['First Event', 'חובש', 'אדם א'],
    ['First Event', 'חובש', 'בני ב'],
    ['Second Event', 'חובש', 'אדם א'],
  ]);
});
```

- [ ] **Step 11: Run backend tests**

Run:

```bash
npm --prefix functions test
```

Expected: all tests pass.

---

## Task 4: Flutter Export Service Contract

**Files:**
- Modify: `shavtzak/lib/core/services/export_service.dart`

- [ ] **Step 1: Add mode enum**

Add above `ExportService`:

```dart
enum AssignmentExportMode {
  perPerson('perPerson'),
  perEvent('perEvent');

  const AssignmentExportMode(this.apiValue);

  final String apiValue;
}
```

- [ ] **Step 2: Extend assignments export method**

Replace:

```dart
Future<ExportResult> exportAssignmentsOnly() async {
  return _runExport('assignments');
}
```

with:

```dart
Future<ExportResult> exportAssignmentsOnly({
  AssignmentExportMode mode = AssignmentExportMode.perPerson,
  List<String> eventIds = const [],
}) async {
  return _runExport(
    'assignments',
    mode: mode,
    eventIds: eventIds,
  );
}
```

- [ ] **Step 3: Extend private request builder**

Replace:

```dart
Future<ExportResult> _runExport(String type) async {
```

with:

```dart
Future<ExportResult> _runExport(
  String type, {
  AssignmentExportMode? mode,
  List<String> eventIds = const [],
}) async {
```

Inside the method, replace:

```dart
body: {'type': type},
```

with:

```dart
body: {
  'type': type,
  if (mode != null) 'mode': mode.apiValue,
  if (eventIds.isNotEmpty) 'eventIds': eventIds,
},
```

- [ ] **Step 4: Analyze client contract change**

Run:

```bash
cd shavtzak
flutter analyze
```

Expected: no new analyzer errors.

---

## Task 5: Assignment Export Mode Dialog

**Files:**
- Create: `shavtzak/lib/presentation/widgets/assignment_export_dialog.dart`
- Modify: `shavtzak/lib/presentation/screens/admin/admin_choice_screen.dart`

- [ ] **Step 1: Create dialog skeleton**

Create `assignment_export_dialog.dart` with a stateful dialog that receives an export callback:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/export_service.dart';
import '../../core/utils/date_utils.dart' as app_date_utils;
import '../../data/repositories/event_repository.dart';
import '../../domain/entities/event.dart';

class AssignmentExportDialog extends StatefulWidget {
  const AssignmentExportDialog({
    super.key,
    required this.onExport,
  });

  final Future<void> Function(
    AssignmentExportMode mode,
    List<String> eventIds,
  ) onExport;

  @override
  State<AssignmentExportDialog> createState() => _AssignmentExportDialogState();
}
```

- [ ] **Step 2: Add state and load future events**

Inside `_AssignmentExportDialogState`, use local one-shot loading from `EventRepository.getAllEvents()` so the export picker does not mutate global `EventBloc` state:

```dart
class _AssignmentExportDialogState extends State<AssignmentExportDialog> {
  AssignmentExportMode _mode = AssignmentExportMode.perPerson;
  final Set<String> _selectedEventIds = {};
  List<Event> _futureEvents = [];
  bool _isLoadingEvents = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadFutureEvents();
  }

  Future<void> _loadFutureEvents() async {
    try {
      final events = await context.read<EventRepository>().getAllEvents();
      final today = _dateOnly(DateTime.now());
      final futureEvents = events.where((event) {
        final endDate = _dateOnly(event.endDate);
        return !endDate.isBefore(today);
      }).toList()
        ..sort((a, b) {
          final dateCompare = _dateOnly(a.startDate).compareTo(_dateOnly(b.startDate));
          if (dateCompare != 0) return dateCompare;
          final timeCompare = a.startTime.compareTo(b.startTime);
          if (timeCompare != 0) return timeCompare;
          return a.name.compareTo(b.name);
        });

      if (!mounted) return;
      setState(() {
        _futureEvents = futureEvents;
        _isLoadingEvents = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _isLoadingEvents = false;
      });
    }
  }

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
}
```

- [ ] **Step 3: Build the RTL dialog UI**

Use Hebrew text and a segmented mode choice:

```dart
@override
Widget build(BuildContext context) {
  final canExport = _mode == AssignmentExportMode.perPerson ||
      _selectedEventIds.isNotEmpty;

  return Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: const Text('ייצוא שיבוצים'),
      content: SizedBox(
        width: 520,
        height: _mode == AssignmentExportMode.perEvent ? 520 : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<AssignmentExportMode>(
              segments: const [
                ButtonSegment(
                  value: AssignmentExportMode.perPerson,
                  label: Text('לפי אדם'),
                  icon: Icon(Icons.person),
                ),
                ButtonSegment(
                  value: AssignmentExportMode.perEvent,
                  label: Text('לפי אירוע'),
                  icon: Icon(Icons.event),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            if (_mode == AssignmentExportMode.perPerson)
              const Text('ייצוא כל השיבוצים של אירועים עתידיים, ממויין לפי אדם ואז לפי תאריך אירוע.'),
            if (_mode == AssignmentExportMode.perEvent)
              Expanded(child: _buildEventMultiSelect()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        ElevatedButton(
          onPressed: canExport
              ? () async {
                  Navigator.of(context).pop();
                  await widget.onExport(_mode, _selectedEventIds.toList());
                }
              : null,
          child: const Text('ייצוא'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 4: Build event multi-select**

Add:

```dart
Widget _buildEventMultiSelect() {
  if (_isLoadingEvents) {
    return const Center(child: CircularProgressIndicator());
  }

  if (_loadError != null) {
    return Center(
      child: Text(
        'שגיאה בטעינת אירועים: $_loadError',
        textAlign: TextAlign.center,
      ),
    );
  }

  if (_futureEvents.isEmpty) {
    return const Center(
      child: Text('אין אירועים עתידיים לייצוא'),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('נבחרו ${_selectedEventIds.length} מתוך ${_futureEvents.length} אירועים'),
      const SizedBox(height: 8),
      Expanded(
        child: ListView.separated(
          itemCount: _futureEvents.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final event = _futureEvents[index];
            final isSelected = _selectedEventIds.contains(event.id);
            return CheckboxListTile(
              value: isSelected,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(event.name),
              subtitle: Text(_formatEventDate(event)),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedEventIds.add(event.id);
                  } else {
                    _selectedEventIds.remove(event.id);
                  }
                });
              },
            );
          },
        ),
      ),
    ],
  );
}

String _formatEventDate(Event event) {
  final start = app_date_utils.DateUtils.formatDate(event.startDate);
  final end = app_date_utils.DateUtils.formatDate(event.endDate);
  if (start == end) return start;
  return '$start - $end';
}
```

- [ ] **Step 5: Wire dialog into admin screen imports**

In `admin_choice_screen.dart`, add:

```dart
import '../../widgets/assignment_export_dialog.dart';
```

- [ ] **Step 6: Replace assignments confirmation dialog**

Replace `_showAssignmentsExportDialog` with:

```dart
void _showAssignmentsExportDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return AssignmentExportDialog(
        onExport: (mode, eventIds) async {
          await _performAssignmentsExport(
            context,
            mode: mode,
            eventIds: eventIds,
          );
        },
      );
    },
  );
}
```

- [ ] **Step 7: Split assignment export execution from full export execution**

Add:

```dart
Future<void> _performAssignmentsExport(
  BuildContext context, {
  required AssignmentExportMode mode,
  required List<String> eventIds,
}) async {
  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('מייצא שיבוצים...'),
            ],
          ),
        ),
      );
    },
  );

  final result = await ExportService().exportAssignmentsOnly(
    mode: mode,
    eventIds: eventIds,
  );

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (result.success && result.spreadsheetUrl != null) {
    _showExportSuccessDialog(context, result.spreadsheetUrl!);
  } else {
    _showExportErrorDialog(context, result.error ?? 'שגיאה לא ידועה');
  }
}
```

Keep `_performExport(context, isFullExport: true)` for full database export. The old assignment branch inside `_performExport` can remain unused or be simplified to full-export only in the implementation.

- [ ] **Step 8: Analyze client**

Run:

```bash
cd shavtzak
flutter analyze
```

Expected: no new analyzer errors.

---

## Task 6: End-To-End Verification And Deployment

**Files:**
- Verify only; no new files.

- [ ] **Step 1: Run backend tests**

Run:

```bash
npm --prefix functions test
```

Expected: all assignment export tests pass.

- [ ] **Step 2: Run backend build**

Run:

```bash
npm --prefix functions run build
```

Expected: TypeScript build passes.

- [ ] **Step 3: Run Flutter analyzer**

Run:

```bash
cd shavtzak
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 4: Deploy Cloud Functions**

Because this plan changes `functions/`, deploy before finishing implementation:

```bash
firebase deploy --only functions
```

Expected: deploy succeeds.

- [ ] **Step 5: Manual production smoke test**

Without running the app from the agent, ask the user to test:

- Open admin home.
- Click the cloud "ייצוא שיבוצים" button.
- Choose "לפי אדם" and export.
- Confirm the sheet excludes events where `endDate` is before today.
- Confirm rows are grouped by person and then event date.
- Open the export dialog again.
- Choose "לפי אירוע".
- Select at least two future events.
- Confirm the sheet includes only selected events.
- Confirm rows are sorted by event date ascending, then role management order, then person name.

---

## Self-Review

- Requirement coverage: future-only filtering is enforced in Cloud Functions and reflected in the Flutter event picker. Per-person mode keeps the current sort. Per-event mode adds multi-select future events and role-order sorting from `utilities/Lists.Roles`.
- Scope check: the plan touches one backend endpoint and one admin UI flow. The full database export and Shamap clipboard flow are intentionally out of scope.
- Ambiguity resolved: selected past/missing event IDs cannot leak rows because the backend filters `eventsData` to future events first. If a per-event request has no selected IDs, the API rejects it with HTTP 400.
- Verification coverage: backend unit tests cover future filtering and both sort modes; `flutter analyze` covers the Dart client; deployment is included because `functions/` changes are required.
