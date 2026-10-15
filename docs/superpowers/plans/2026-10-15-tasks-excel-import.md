# Excel Import of Stages and Tasks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A manager imports an `.xlsx` file of stages and tasks into a דו יומי event that has no stages. The whole file is checked first; nothing is saved unless it is entirely valid, and then everything is saved in one transaction.

**Architecture:** The browser parses the workbook with the `excel` package into ready-made `Stage`/`TaskItem` entities with ids already chosen, matching assignee names against the event's assigned members. A preview dialog lists every problem, or a summary when there are none. The confirmed import goes to a new backend action `stage.import`, which validates every stage and task with the existing builders and writes them all in one Firestore transaction. The transaction also refuses an event that already has stages, and treats a replay of the same import as success.

**Tech Stack:** Flutter Web (Dart 3), `excel` 4.0.6 (already a dependency, so far unused), `package:web` for file picking and downloading, Firebase Cloud Functions (TypeScript, `node --test`), Firestore.

**Spec:** `docs/superpowers/specs/2026-10-15-tasks-excel-import-design.md`

## Global Constraints

- All UI text is Hebrew; every screen and dialog is wrapped in `Directionality(textDirection: TextDirection.rtl)`.
- Flutter commands run from `shavtzak/`; Functions commands from `functions/`.
- `flutter analyze` baseline is 107 pre-existing issues. "Clean" means no new ones.
- Do not run the app. The user tests it with a local `flutter run` against **production** data, which calls the **deployed** `api` function, so Functions must be deployed before they test.
- Backend changes must be backward-compatible. `stage.import` is a new action and touches nothing existing.
- Sheets: `שלבים`, `משימות`. Stage headers: `מספר שלב`, `שם`, `תאריך`, `שעת התחלה`, `שעת סיום`, `דרישות מהמלון ולוגיסטיקה`, `מיקום במלון`, `הערות`, `אנשי קשר`. Task headers: `מספר שלב`, `משימה`, `תיאור`, `אחראי/ים`, `שעת התייצבות`, `תתי משימות`.
- Limits: title ≤ 200; requirements, notes and description ≤ 5000; location ≤ 200; contact name and role ≤ 100; ≤ 30 contacts per stage; ≤ 50 subtasks per task, each ≤ 200; ≤ 60 stages and ≤ 400 tasks per file; file ≤ 5 MB.
- Contact phones are stored as `05X-XXXXXXX` (10 digits starting `05`), the team-member format.
- Any problem blocks the import. Import is offered only while the event has no stages.
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_011Zy3M4n5NqAzqCWmHbV839
  ```
- The sandbox refuses heredocs and `cd`+git chains in this worktree. Write commit messages to a file in the scratchpad (`/private/tmp/claude-501/-Users-omerbengal-Documents-Github-Projects-Shavtzak/3772abe7-b08d-43be-8f83-2bea25762b7f/scratchpad/`) and use `git commit -F <file>`. Run `git add` and `git commit` as separate commands.

## Review Focus

1. **Dates typed as text in other shapes** (`15.06.2026`, `15/6/2026`). Expected: read as that day. Test pinned in Task 3.
2. **Headers with a trailing colon, extra spaces or invisible marks** (the sample has `תתי משימות:`). Expected: found. Test pinned in Task 6.
3. **The ~1000 "rows" `excel` reports for a sheet** (formatting only) and rows holding only spaces. Expected: skipped, never "missing title" problems. Test pinned in Task 6.
4. **Names with a geresh or quotes** (`צ'רלי` vs `צרלי`) and the same member named twice. Expected: matched, kept once. Test pinned in Task 5.
5. **Pressing ייבוא twice, or a retry after a timeout.** Expected: the button is disabled while importing (Task 10 test), and the backend treats a replay as success (Task 2 code; stated in its review checklist, because the handler has no unit-test harness).

---

## File structure

**Backend**
- Create `functions/src/stage_import.ts`: pure `buildStageImport` and `importEventId`.
- Create `functions/src/stage_import.test.ts`.
- Modify `functions/src/index.ts`: the `case 'stage.import'` handler.

**Client: import logic** (`shavtzak/lib/core/utils/task_import/`)
- `cell_values.dart`: invisible characters, and reading text, whole numbers, dates and times from cells.
- `contact_cell_parser.dart`: the contacts cell.
- `assignee_matcher.dart`: names → members.
- `task_import_parser.dart`: workbook → `TaskImportResult`, plus the column-name constants.
- `task_import_template.dart`: the template workbook.

**Client: domain and data**
- Create `lib/domain/entities/imported_stage.dart`.
- Create `lib/data/models/stage_import_model.dart`: the backend payload.
- Modify `database_interface.dart`, `firestore_database.dart`, `logging_database.dart` and `task_repository.dart`: add `importStages`.
- Modify `lib/presentation/bloc/task/task_event.dart` and `task_bloc.dart`: add `ImportStages`.

**Client: browser files**
- Create `lib/core/services/picked_import_file.dart`, `task_import_files.dart`, `task_import_files_web.dart` and `task_import_files_stub.dart`.

**Client: UI**
- Create `lib/presentation/screens/task/widgets/task_import_dialog.dart`.
- Modify `lib/presentation/screens/task/event_tasks_screen.dart`: the empty-state buttons and wiring.

**Tests**
- Create `test/support/import_workbook.dart` and `test/support/fake_task_import_files.dart`.
- Create `test/core/utils/task_import/*_test.dart`, `test/data/models/stage_import_model_test.dart` and `test/presentation/screens/task/widgets/task_import_dialog_test.dart`.
- Modify `test/support/fake_task_repository.dart`, `test/presentation/bloc/task_bloc_test.dart` and `test/presentation/screens/task/event_tasks_screen_test.dart`.

---

### Task 1: Backend: pure import builder

**Files:**
- Create: `functions/src/stage_import.ts`
- Test: `functions/src/stage_import.test.ts`

**Interfaces:**
- Consumes: `buildNewStage(input, ctx, eventDays)` and `StageDoc` from `./stages`; `buildNewTask(input, ctx)`, `TaskDoc`, `TaskActor` and `TaskError` from `./tasks`.
- Produces:
  - `export const MAX_IMPORT_STAGES = 60`
  - `export const MAX_IMPORT_TASKS = 400`
  - `export function importEventId(payload: Record<string, unknown>): string`
  - `export function buildStageImport(payload: Record<string, unknown>, ctx: {now: Timestamp; actor: TaskActor}, eventDays: string[]): StageImport`, where `StageImport = {eventId: string; stages: StageDoc[]; tasks: TaskDoc[]}`

- [ ] **Step 1: Write the failing tests**

```ts
// functions/src/stage_import.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';

import {buildStageImport, importEventId, MAX_IMPORT_STAGES, MAX_IMPORT_TASKS} from './stage_import';
import {TaskActor, TaskError} from './tasks';

const now = Timestamp.fromMillis(1_800_000_000_000);
const manager: TaskActor = {memberId: 'm-admin', name: 'מנהל', isAdmin: true, canManageTasks: false};
const ctx = {now, actor: manager};
const days = ['2026-06-15', '2026-06-16'];

function stage(id: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id, eventId: 'e1', title: `שלב ${id}`, date: '2026-06-15',
    startTime: null, endTime: null, requirements: '', hotelLocation: '', notes: '', contacts: [],
    ...overrides,
  };
}

function task(id: string, stageId: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id, eventId: 'e1', stageId, title: `משימה ${id}`, description: '',
    assemblyTime: null, assigneeIds: [], subtasks: [],
    ...overrides,
  };
}

function payload(stages: unknown[]): Record<string, unknown> {
  return {eventId: 'e1', stages};
}

function rejects(fn: () => unknown, status: number) {
  assert.throws(fn, (error: unknown) => error instanceof TaskError && error.status === status);
}

test('builds every stage and task of the import', () => {
  const built = buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('t1', 's1'), task('t2', 's1')]},
    {stage: stage('s2', {date: '2026-06-16'}), tasks: []},
  ]), ctx, days);

  assert.equal(built.eventId, 'e1');
  assert.deepEqual(built.stages.map((s) => s.id), ['s1', 's2']);
  assert.deepEqual(built.tasks.map((t) => [t.id, t.stageId]), [['t1', 's1'], ['t2', 's1']]);
  assert.equal(built.stages[0].createdById, 'm-admin');
  assert.equal(built.tasks[0].isComplete, false);
});

test('a stage without tasks may leave the tasks list out', () => {
  const built = buildStageImport(payload([{stage: stage('s1')}]), ctx, days);
  assert.equal(built.tasks.length, 0);
});

test('an import needs at least one stage and at most the cap', () => {
  rejects(() => buildStageImport(payload([]), ctx, days), 400);
  rejects(() => buildStageImport({eventId: 'e1'}, ctx, days), 400);
  const tooMany = Array.from({length: MAX_IMPORT_STAGES + 1}, (_, i) => ({stage: stage(`s${i}`)}));
  rejects(() => buildStageImport(payload(tooMany), ctx, days), 400);
});

test('at most the task cap across all stages', () => {
  const half = Math.ceil((MAX_IMPORT_TASKS + 1) / 2);
  const tasksOf = (stageId: string) =>
    Array.from({length: half}, (_, i) => task(`${stageId}-t${i}`, stageId));
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: tasksOf('s1')},
    {stage: stage('s2'), tasks: tasksOf('s2')},
  ]), ctx, days), 400);
});

test('every stage and task must belong to the import\'s event and stage', () => {
  rejects(() => buildStageImport(payload([{stage: stage('s1', {eventId: 'e2'})}]), ctx, days), 400);
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('t1', 's2')]},
  ]), ctx, days), 400);
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('t1', 's1', {eventId: 'e2'})]},
  ]), ctx, days), 400);
});

test('ids are unique across the whole import', () => {
  rejects(() => buildStageImport(payload([{stage: stage('s1')}, {stage: stage('s1')}]), ctx, days), 400);
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('x', 's1'), task('x', 's1')]},
  ]), ctx, days), 400);
});

test('each stage and task is validated like a single create', () => {
  rejects(() => buildStageImport(payload([{stage: stage('s1', {date: '2026-07-01'})}]), ctx, days), 400);
  rejects(() => buildStageImport(payload([{stage: stage('s1', {title: ''})}]), ctx, days), 400);
  rejects(() => buildStageImport(payload([
    {stage: stage('s1'), tasks: [task('t1', 's1', {title: ''})]},
  ]), ctx, days), 400);
});

test('importEventId needs a valid id', () => {
  assert.equal(importEventId({eventId: 'e1'}), 'e1');
  rejects(() => importEventId({}), 400);
  rejects(() => importEventId({eventId: 'a/b'}), 400);
});
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `cd functions && npm test 2>&1 | tail -20`
Expected: the TypeScript build fails with `Cannot find module './stage_import'`.

- [ ] **Step 3: Implement**

```ts
// functions/src/stage_import.ts
import {Timestamp} from 'firebase-admin/firestore';

import {buildNewStage, StageDoc} from './stages';
import {buildNewTask, TaskActor, TaskDoc, TaskError} from './tasks';

/**
 * Pure rules for importing a whole event's stages and tasks at once (from an
 * Excel file the client parsed). Every stage and task goes through the same
 * builder as a single create; `index.ts` reads the event's days, refuses an
 * event that already has stages and writes the result in one transaction.
 */

export const MAX_IMPORT_STAGES = 60;
// 60 stages + 400 tasks stay under Firestore's 500 writes per transaction.
export const MAX_IMPORT_TASKS = 400;

const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export type StageImport = {
  eventId: string;
  stages: StageDoc[];
  tasks: TaskDoc[];
};

type ImportContext = {
  now: Timestamp;
  actor: TaskActor;
};

function requireRecord(value: unknown, what: string): Record<string, unknown> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TaskError(400, `${what} לא תקין`);
  }
  return value as Record<string, unknown>;
}

/** The event an import is for, read before anything else. */
export function importEventId(payload: Record<string, unknown>): string {
  const eventId = payload['eventId'];
  if (typeof eventId !== 'string' || !ID_PATTERN.test(eventId)) {
    throw new TaskError(400, 'אירוע לא תקין');
  }
  return eventId;
}

export function buildStageImport(
  payload: Record<string, unknown>,
  ctx: ImportContext,
  eventDays: string[],
): StageImport {
  const eventId = importEventId(payload);
  const rawStages = payload['stages'];
  if (!Array.isArray(rawStages) || rawStages.length === 0) {
    throw new TaskError(400, 'אין שלבים לייבוא');
  }
  if (rawStages.length > MAX_IMPORT_STAGES) {
    throw new TaskError(400, `אפשר לייבא עד ${MAX_IMPORT_STAGES} שלבים`);
  }

  const stages: StageDoc[] = [];
  const tasks: TaskDoc[] = [];
  const ids = new Set<string>();
  const claim = (id: string) => {
    if (ids.has(id)) throw new TaskError(400, 'מזהה כפול בייבוא');
    ids.add(id);
  };

  for (const rawEntry of rawStages) {
    const entry = requireRecord(rawEntry, 'שלב');
    const stage = buildNewStage(requireRecord(entry['stage'], 'שלב'), ctx, eventDays);
    if (stage.eventId !== eventId) throw new TaskError(400, 'שלב של אירוע אחר');
    claim(stage.id);
    stages.push(stage);

    const rawTasks = entry['tasks'] ?? [];
    if (!Array.isArray(rawTasks)) throw new TaskError(400, 'רשימת המשימות לא תקינה');
    for (const rawTask of rawTasks) {
      const task = buildNewTask(requireRecord(rawTask, 'משימה'), ctx);
      if (task.eventId !== eventId || task.stageId !== stage.id) {
        throw new TaskError(400, 'משימה שאינה שייכת לשלב שלה');
      }
      claim(task.id);
      tasks.push(task);
      if (tasks.length > MAX_IMPORT_TASKS) {
        throw new TaskError(400, `אפשר לייבא עד ${MAX_IMPORT_TASKS} משימות`);
      }
    }
  }
  return {eventId, stages, tasks};
}
```

- [ ] **Step 4: Run the tests and check they pass**

Run: `cd functions && npm test 2>&1 | tail -5`
Expected: all pass. The count is 247 + 8 = 255.

- [ ] **Step 5: Commit**

```bash
git add functions/src/stage_import.ts functions/src/stage_import.test.ts
git commit -F <scratchpad>/msg.txt   # "feat(functions): pure rules for importing an event's stages and tasks"
```

---

### Task 2: Backend: the `stage.import` action

**Files:**
- Modify: `functions/src/index.ts`. Add the import next to the other `./stages` import, and add the case right after `case 'stage.delete'`.

**Interfaces:**
- Consumes: `buildStageImport` and `importEventId` (Task 1); the existing `taskActorFrom`, `requireTaskManager`, `readWritableEventDaysInTransaction`, `requireTaskAssigneesInTransaction`, `writeAuditLog`, `HttpError`, `collections.stages` and `collections.tasks`.
- Produces: the backend operation `stage.import` with payload `{eventId, stages: [{stage, tasks}]}`, returning `{ok: true, stageCount, taskCount}`.

- [ ] **Step 1: Add the import**

```ts
import {buildStageImport, importEventId} from './stage_import';
```

- [ ] **Step 2: Add the case**

```ts
    case 'stage.import': {
      const taskActor = taskActorFrom(actor);
      requireTaskManager(taskActor);
      const eventId = importEventId(payload);
      const now = Timestamp.now();
      const {built, replayed} = await db.runTransaction(async (transaction) => {
        const eventDays = await readWritableEventDaysInTransaction(
          transaction,
          collections,
          eventId,
        );
        const next = buildStageImport(payload, {now, actor: taskActor}, eventDays);
        const existing = await transaction.get(
          db.collection(collections.stages).where('eventId', '==', eventId).limit(1),
        );
        if (!existing.empty) {
          // The client retries a request that timed out. If this import's own
          // first stage is already there, the first attempt went through.
          const own = await transaction.get(
            db.collection(collections.stages).doc(next.stages[0].id),
          );
          if (own.exists && own.data()?.['eventId'] === eventId) {
            return {built: next, replayed: true};
          }
          throw new HttpError(409, 'לאירוע כבר יש שלבים. ייבוא אפשרי רק לאירוע ללא שלבים.');
        }
        await requireTaskAssigneesInTransaction(
          transaction,
          collections,
          [...new Set(next.tasks.flatMap((task) => task.assigneeIds))],
        );
        for (const stage of next.stages) {
          transaction.create(db.collection(collections.stages).doc(stage.id), stage);
        }
        for (const task of next.tasks) {
          transaction.create(db.collection(collections.tasks).doc(task.id), task);
        }
        return {built: next, replayed: false};
      });
      if (!replayed) {
        await writeAuditLog(
          db, collections, actor, operation, 'event', eventId,
          {stageCount: built.stages.length, taskCount: built.tasks.length},
        );
      }
      return {ok: true, stageCount: built.stages.length, taskCount: built.tasks.length};
    }
```

- [ ] **Step 3: Build and run all Functions tests**

Run: `cd functions && npm test 2>&1 | tail -5`
Expected: builds; 255 pass.

- [ ] **Step 4: Review checklist** (the handler has no unit harness)
  - All reads (event, stages query, own stage, assignees) come before the first `transaction.create`.
  - At most 460 creates, under the 500-write limit.
  - A replay writes nothing and no audit entry.

- [ ] **Step 5: Commit**: `feat(functions): stage.import writes a whole event's stages and tasks in one transaction`

---

### Task 3: Cell value readers

**Files:**
- Create: `shavtzak/lib/core/utils/task_import/cell_values.dart`
- Test: `shavtzak/test/core/utils/task_import/cell_values_test.dart`

**Interfaces:**
- Produces:
  - `String cleanText(String text)`
  - `String cellText(CellValue? value)`
  - `bool isBlankCell(CellValue? value)`
  - `int? cellWholeNumber(CellValue? value)`
  - `DateTime? cellDate(CellValue? value)` (local midnight)
  - `String? cellTime(CellValue? value)` (`HH:mm`)
  - `String formatImportDay(DateTime day)` (`dd/MM/yyyy`)
  - The readers return null when a non-blank cell can't be read; callers check `isBlankCell` first.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/cell_values.dart';

void main() {
  group('text', () {
    test('drops invisible marks and turns non-breaking spaces into spaces', () {
      expect(cleanText('050-628-5016⁩'), '050-628-5016');
      expect(cleanText('‏שם מלא﻿'), 'שם מלא');
    });

    test('reads every kind of cell as trimmed text', () {
      expect(cellText(null), '');
      expect(cellText(TextCellValue('  שלום ⁩ ')), 'שלום');
      expect(cellText(const IntCellValue(3)), '3');
      expect(cellText(const DoubleCellValue(2.0)), '2');
      expect(cellText(const DoubleCellValue(2.5)), '2.5');
      expect(cellText(const DateCellValue(year: 2026, month: 6, day: 15)), '15/06/2026');
      expect(cellText(const TimeCellValue(hour: 8, minute: 5)), '08:05');
    });

    test('keeps line breaks inside the text', () {
      expect(cellText(TextCellValue('• א\n• ב')), '• א\n• ב');
    });

    test('a cell of spaces is blank', () {
      expect(isBlankCell(TextCellValue('   ')), isTrue);
      expect(isBlankCell(null), isTrue);
      expect(isBlankCell(const IntCellValue(0)), isFalse);
    });
  });

  group('whole numbers', () {
    test('reads ints, whole doubles and number text', () {
      expect(cellWholeNumber(const IntCellValue(4)), 4);
      expect(cellWholeNumber(const DoubleCellValue(1.0)), 1);
      expect(cellWholeNumber(TextCellValue(' 7 ')), 7);
      expect(cellWholeNumber(TextCellValue('7.0')), 7);
    });

    test('refuses fractions and words', () {
      expect(cellWholeNumber(const DoubleCellValue(1.5)), isNull);
      expect(cellWholeNumber(TextCellValue('שלב א')), isNull);
    });
  });

  group('dates', () {
    test('reads date cells, date-time cells and serial numbers', () {
      expect(cellDate(const DateCellValue(year: 2026, month: 6, day: 15)), DateTime(2026, 6, 15));
      expect(
        cellDate(const DateTimeCellValue(year: 2026, month: 6, day: 15, hour: 9, minute: 0)),
        DateTime(2026, 6, 15),
      );
      expect(cellDate(const IntCellValue(46188)), DateTime(2026, 6, 15));
      expect(cellDate(const DoubleCellValue(46188.75)), DateTime(2026, 6, 15));
    });

    test('reads day/month/year text with slashes or dots', () {
      expect(cellDate(TextCellValue('15/06/2026')), DateTime(2026, 6, 15));
      expect(cellDate(TextCellValue('15/6/2026')), DateTime(2026, 6, 15));
      expect(cellDate(TextCellValue('15.06.2026')), DateTime(2026, 6, 15));
    });

    test('refuses impossible or unreadable dates', () {
      expect(cellDate(TextCellValue('31/02/2026')), isNull);
      expect(cellDate(TextCellValue('מחר')), isNull);
      expect(cellDate(const IntCellValue(0)), isNull);
    });
  });

  group('times', () {
    test('reads time cells, rounding seconds to the minute', () {
      expect(cellTime(const TimeCellValue(hour: 8, minute: 30)), '08:30');
      expect(cellTime(const TimeCellValue(hour: 8, minute: 29, second: 59)), '08:30');
    });

    test('reads date-time cells and fractions of a day', () {
      expect(
        cellTime(const DateTimeCellValue(year: 2026, month: 6, day: 15, hour: 14, minute: 5)),
        '14:05',
      );
      expect(cellTime(const DoubleCellValue(0.3541666666666667)), '08:30');
    });

    test('reads H:mm and HH:mm text, with or without seconds', () {
      expect(cellTime(TextCellValue('8:30')), '08:30');
      expect(cellTime(TextCellValue('08:30:00')), '08:30');
    });

    test('refuses impossible or unreadable times', () {
      expect(cellTime(TextCellValue('24:00')), isNull);
      expect(cellTime(TextCellValue('8:75')), isNull);
      expect(cellTime(TextCellValue('בבוקר')), isNull);
      expect(cellTime(const DoubleCellValue(1.5)), isNull);
    });
  });
}
```

- [ ] **Step 2: Run and check they fail**

Run: `cd shavtzak && flutter test test/core/utils/task_import/cell_values_test.dart`
Expected: compile error, because the file does not exist.

- [ ] **Step 3: Implement**

```dart
import 'package:excel/excel.dart';

/// Reading single cells of an import workbook. Every reader takes the cell as
/// `excel` decoded it, so a date typed as a date, as a serial number or as
/// text all arrive at the same value.

/// Marks Excel and copy-paste leave in Hebrew text that nobody can see:
/// direction marks, embeddings and isolates, and the byte-order mark.
final RegExp _invisible =
    RegExp('[‎‏‪-‮⁦-⁩﻿]');

/// [text] without invisible marks, with non-breaking spaces as spaces.
String cleanText(String text) =>
    text.replaceAll(_invisible, '').replaceAll(' ', ' ');

/// The cell as text, cleaned and trimmed; '' for an empty cell. Line breaks
/// inside the text are kept.
String cellText(CellValue? value) {
  return switch (value) {
    null => '',
    TextCellValue(value: final span) => cleanText(span.toString()).trim(),
    IntCellValue(value: final number) => '$number',
    DoubleCellValue(value: final number) => number == number.roundToDouble()
        ? '${number.toInt()}'
        : '$number',
    DateCellValue(:final year, :final month, :final day) =>
      formatImportDay(DateTime(year, month, day)),
    DateTimeCellValue(:final year, :final month, :final day,
        :final hour, :final minute) =>
      '${formatImportDay(DateTime(year, month, day))} ${_hourMinute(hour, minute)}',
    TimeCellValue(:final hour, :final minute) => _hourMinute(hour, minute),
    BoolCellValue(value: final flag) => flag ? 'TRUE' : 'FALSE',
    FormulaCellValue(:final formula) => cleanText(formula).trim(),
  };
}

/// Whether the cell holds nothing a person typed.
bool isBlankCell(CellValue? value) => cellText(value).isEmpty;

/// A whole number such as a stage number. Excel often stores 1 as 1.0.
int? cellWholeNumber(CellValue? value) {
  switch (value) {
    case IntCellValue(value: final number):
      return number;
    case DoubleCellValue(value: final number):
      return number == number.roundToDouble() ? number.toInt() : null;
    case TextCellValue():
      final text = cellText(value);
      final asInt = int.tryParse(text);
      if (asInt != null) return asInt;
      final asDouble = double.tryParse(text);
      if (asDouble == null || asDouble != asDouble.roundToDouble()) return null;
      return asDouble.toInt();
    default:
      return null;
  }
}

final RegExp _dayText = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{4})$');

/// A calendar day at local midnight.
DateTime? cellDate(CellValue? value) {
  switch (value) {
    case DateCellValue(:final year, :final month, :final day):
      return DateTime(year, month, day);
    case DateTimeCellValue(:final year, :final month, :final day):
      return DateTime(year, month, day);
    case IntCellValue(value: final serial):
      return _fromSerial(serial);
    case DoubleCellValue(value: final serial):
      return _fromSerial(serial.floor());
    case TextCellValue():
      final match = _dayText.firstMatch(cellText(value));
      if (match == null) return null;
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      final date = DateTime(year, month, day);
      // DateTime rolls 31/02 over into March; refuse instead.
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }
      return date;
    default:
      return null;
  }
}

/// Excel's day count, where 1 is 1/1/1900 and 30/12/1899 is day zero.
DateTime? _fromSerial(int serial) =>
    serial < 1 ? null : DateTime(1899, 12, 30 + serial);

final RegExp _timeText = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$');

/// A time of day as `HH:mm`.
String? cellTime(CellValue? value) {
  switch (value) {
    case TimeCellValue(:final hour, :final minute, :final second):
      return _fromMinutes(hour * 60 + minute + (second >= 30 ? 1 : 0));
    case DateTimeCellValue(:final hour, :final minute):
      return _fromMinutes(hour * 60 + minute);
    case DoubleCellValue(value: final fraction):
      if (fraction < 0 || fraction >= 1) return null;
      return _fromMinutes((fraction * 24 * 60).round());
    case TextCellValue():
      final match = _timeText.firstMatch(cellText(value));
      if (match == null) return null;
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      if (hour > 23 || minute > 59) return null;
      return _hourMinute(hour, minute);
    default:
      return null;
  }
}

String? _fromMinutes(int minutes) => minutes < 0 || minutes >= 24 * 60
    ? null
    : _hourMinute(minutes ~/ 60, minutes % 60);

String _hourMinute(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// `dd/MM/yyyy`, the way the app and the problem messages write a day.
String formatImportDay(DateTime day) =>
    '${day.day.toString().padLeft(2, '0')}/'
    '${day.month.toString().padLeft(2, '0')}/${day.year}';
```

- [ ] **Step 4: Run and check they pass**

Run: `cd shavtzak && flutter test test/core/utils/task_import/cell_values_test.dart`
Expected: all pass. If a `switch` pattern fails to compile (field names), check the class in `~/.pub-cache/hosted/pub.dev/excel-4.0.6/lib/src/sheet/data_model.dart`.

- [ ] **Step 5: Commit**: `feat(tasks): read import cells as text, numbers, days and times`

---

### Task 4: Contacts cell parser

**Files:**
- Create: `shavtzak/lib/core/utils/task_import/contact_cell_parser.dart`
- Test: `shavtzak/test/core/utils/task_import/contact_cell_parser_test.dart`

**Interfaces:**
- Consumes: `cleanText` (Task 3); `StageContact` from `lib/domain/entities/stage.dart`.
- Produces:
  - `const int maxImportContacts = 30;`
  - `class ContactCellResult { final List<StageContact> contacts; final List<String> problems; }`
  - `ContactCellResult parseContactCell(String cell, {required String Function() newId})`
  - Problem strings carry no sheet or row; the caller prefixes them.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/contact_cell_parser.dart';

void main() {
  var counter = 0;
  String newId() => 'c${++counter}';
  setUp(() => counter = 0);

  ContactCellResult parse(String cell) => parseContactCell(cell, newId: newId);

  test('reads the sample file\'s cell', () {
    final result = parse(
      'שם: הלל, טלפון: 0522010344, תפקיד: צייר קריקטורה (מהשעה 10:30) | '
      'שם:יוכי, טלפון: 050-628-5016⁩, תפקיד: ביטוח לאומי | '
      'שם: אמיר פידלמן, טלפון: 052-2756524⁩, תפקיד: קרן הסיוע',
    );

    expect(result.problems, isEmpty);
    expect(result.contacts.map((c) => [c.name, c.phone, c.role]), [
      ['הלל', '052-2010344', 'צייר קריקטורה (מהשעה 10:30)'],
      ['יוכי', '050-6285016', 'ביטוח לאומי'],
      ['אמיר פידלמן', '052-2756524', 'קרן הסיוע'],
    ]);
    expect(result.contacts.map((c) => c.id), ['c1', 'c2', 'c3']);
  });

  test('labels may come in any order; phone and role are optional', () {
    final result = parse('תפקיד: קבלה, שם: דנה | שם: אבי');
    expect(result.problems, isEmpty);
    expect(result.contacts.map((c) => [c.name, c.phone, c.role]), [
      ['דנה', '', 'קבלה'],
      ['אבי', '', ''],
    ]);
  });

  test('a comma inside a value stays in it', () {
    final result = parse('שם: רונית, תפקיד: מנהלת אירועים, קומה 2');
    expect(result.problems, isEmpty);
    expect(result.contacts.single.role, 'מנהלת אירועים, קומה 2');
  });

  test('an empty cell or empty entries give nothing', () {
    expect(parse('').contacts, isEmpty);
    expect(parse(' | ').problems, isEmpty);
  });

  test('a contact without a name is a problem', () {
    final result = parse('טלפון: 0501234567');
    expect(result.contacts, isEmpty);
    expect(result.problems, ['איש קשר 1: חסר שם']);
  });

  test('a phone that is not a mobile number is a problem', () {
    final result = parse('שם: אבי, טלפון: 02-6234567');
    expect(result.contacts, isEmpty);
    expect(result.problems.single, contains('איש קשר 1 (אבי): מספר הטלפון "02-6234567"'));
  });

  test('text before the first label is a problem', () {
    expect(parse('אבי 0501234567').problems.single, contains('איש קשר 1'));
    expect(parse('אבי, שם: דנה').problems.single, contains('טקסט לא מזוהה "אבי"'));
  });

  test('an unknown label is a problem', () {
    expect(
      parse('שם: אבי, מייל: avi@example.com').problems.single,
      contains('תווית לא מוכרת "מייל"'),
    );
  });

  test('a label twice in one contact is a problem', () {
    expect(parse('שם: אבי, שם: דנה').problems.single, contains('"שם" מופיע פעמיים'));
  });

  test('long names and roles, and too many contacts, are problems', () {
    expect(parse('שם: ${'א' * 101}').problems.single, contains('ארוך מ-100'));
    final many = List.generate(maxImportContacts + 1, (i) => 'שם: איש $i').join(' | ');
    expect(parse(many).problems, contains('יותר מ-$maxImportContacts אנשי קשר'));
  });
}
```

- [ ] **Step 2: Run and check they fail**

Run: `cd shavtzak && flutter test test/core/utils/task_import/contact_cell_parser_test.dart`
Expected: compile error, because the file does not exist.

- [ ] **Step 3: Implement**

```dart
import '../../../domain/entities/stage.dart';
import 'cell_values.dart';

/// The "אנשי קשר" cell of an import file:
/// `שם: הלל, טלפון: 0522010344, תפקיד: צייר | שם: יוכי, ...`.
///
/// Entries are split on `|`. Inside an entry each of the three labels is
/// followed by a colon; a value runs until the next label, so commas and
/// colons inside a value are kept.

const int maxImportContacts = 30;
const int _maxContactText = 100;

class ContactCellResult {
  const ContactCellResult(this.contacts, this.problems);

  final List<StageContact> contacts;

  /// Without a sheet or row; the caller adds those.
  final List<String> problems;
}

// A label is not part of a longer word: "רשם:" is no label.
final RegExp _label =
    RegExp(r'(?<![א-תA-Za-z])(שם|טלפון|תפקיד)\s*:');

// One or two words and a colon right after a comma inside a value: a label
// this format does not know, such as ", מייל:". "(מהשעה 10:30)" is not one.
final RegExp _unknownLabel = RegExp(
  r',\s*([א-תA-Za-z]+(?: [א-תA-Za-z]+)?)\s*:',
);

final RegExp _trailingCommas = RegExp(r'[,\s]+$');
final RegExp _notDigit = RegExp(r'\D');

ContactCellResult parseContactCell(
  String cell, {
  required String Function() newId,
}) {
  final contacts = <StageContact>[];
  final problems = <String>[];
  final entries = cleanText(cell)
      .split('|')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();

  for (var index = 0; index < entries.length; index++) {
    final where = 'איש קשר ${index + 1}';
    final entry = entries[index];
    final labels = _label.allMatches(entry).toList();
    if (labels.isEmpty) {
      problems.add('$where: לא נמצאו "שם:", "טלפון:" או "תפקיד:"');
      continue;
    }

    var isValid = true;
    final before = _value(entry.substring(0, labels.first.start));
    if (before.isNotEmpty) {
      problems.add('$where: טקסט לא מזוהה "$before"');
      isValid = false;
    }

    final values = <String, String>{};
    for (var i = 0; i < labels.length; i++) {
      final label = labels[i].group(1)!;
      final end = i + 1 < labels.length ? labels[i + 1].start : entry.length;
      final value = _value(entry.substring(labels[i].end, end));
      if (values.containsKey(label)) {
        problems.add('$where: "$label" מופיע פעמיים');
        isValid = false;
        continue;
      }
      final unknown = _unknownLabel.firstMatch(value);
      if (unknown != null) {
        problems.add('$where: תווית לא מוכרת "${unknown.group(1)}"');
        isValid = false;
      }
      values[label] = value;
    }

    final name = values['שם'] ?? '';
    final phoneText = values['טלפון'] ?? '';
    final role = values['תפקיד'] ?? '';
    final who = name.isEmpty ? where : '$where ($name)';

    if (name.isEmpty) {
      problems.add('$where: חסר שם');
      isValid = false;
    } else if (name.length > _maxContactText) {
      problems.add('$who: השם ארוך מ-$_maxContactText תווים');
      isValid = false;
    }
    if (role.length > _maxContactText) {
      problems.add('$who: התפקיד ארוך מ-$_maxContactText תווים');
      isValid = false;
    }

    var phone = '';
    if (phoneText.isNotEmpty) {
      final digits = phoneText.replaceAll(_notDigit, '');
      if (digits.length != 10 || !digits.startsWith('05')) {
        problems.add(
          '$who: מספר הטלפון "$phoneText" אינו מספר נייד תקין (05X-XXXXXXX)',
        );
        isValid = false;
      } else {
        // The team-member format, the same as a phone typed in the form.
        phone = '${digits.substring(0, 3)}-${digits.substring(3)}';
      }
    }

    if (isValid) {
      contacts.add(StageContact(id: newId(), name: name, phone: phone, role: role));
    }
  }

  if (entries.length > maxImportContacts) {
    problems.add('יותר מ-$maxImportContacts אנשי קשר');
  }
  return ContactCellResult(contacts, problems);
}

String _value(String raw) => raw.trim().replaceAll(_trailingCommas, '').trim();
```

- [ ] **Step 4: Run and check they pass**

Run: `cd shavtzak && flutter test test/core/utils/task_import/contact_cell_parser_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**: `feat(tasks): parse the contacts cell of an import file`

---

### Task 5: Assignee matcher

**Files:**
- Create: `shavtzak/lib/core/utils/task_import/assignee_matcher.dart`
- Test: `shavtzak/test/core/utils/task_import/assignee_matcher_test.dart`

**Interfaces:**
- Consumes: `cleanText` (Task 3); `normalizeForSearch` from `lib/core/utils/search_utils.dart`; `TeamMember`.
- Produces:
  - `sealed class AssigneeMatch`, with subclasses `AssigneeFound(TeamMember member)`, `AssigneeNotFound()` and `AssigneeAmbiguous(List<TeamMember> members)`.
  - `AssigneeMatch matchAssignee(String written, List<TeamMember> candidates)`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/assignee_matcher.dart';

import '../../../support/task_fixtures.dart';

void main() {
  final omer = buildMember(id: 'm1', name: 'עומר אליהו');
  final matan = buildMember(id: 'm2', name: 'מתן סלפטי');
  final boazCohen = buildMember(id: 'm3', name: 'בועז כהן');
  final boazLevi = buildMember(id: 'm4', name: 'בועז לוי');
  final boazi = buildMember(id: 'm5', name: 'בועזי דוד');
  final charlie = buildMember(id: 'm6', name: "צ'רלי ברק");
  final all = [omer, matan, boazCohen, boazLevi, boazi, charlie];

  TeamMember? found(AssigneeMatch match) =>
      match is AssigneeFound ? match.member : null;

  test('a full name matches, ignoring spaces and invisible marks', () {
    expect(found(matchAssignee('עומר אליהו', all)), omer);
    expect(found(matchAssignee('  עומר   אליהו⁩ ', all)), omer);
  });

  test('a unique part of a name matches on whole words', () {
    expect(found(matchAssignee('סלפטי', all)), matan);
    expect(found(matchAssignee('בועז לוי', all)), boazLevi);
  });

  test('a part shared by several members is ambiguous, and names them', () {
    final match = matchAssignee('בועז', [boazCohen, boazLevi, boazi]);
    expect(match, isA<AssigneeAmbiguous>());
    expect((match as AssigneeAmbiguous).members, [boazCohen, boazLevi]);
  });

  test('a word is not matched inside a longer word', () {
    expect(found(matchAssignee('בועז', [boazi])), isNull);
  });

  test('a geresh or quote does not stop a match', () {
    expect(found(matchAssignee('צרלי', all)), charlie);
    expect(found(matchAssignee("צ'רלי ברק", all)), charlie);
  });

  test('a name of nobody assigned is not found', () {
    expect(matchAssignee('יצחק דני', all), isA<AssigneeNotFound>());
    expect(matchAssignee('', all), isA<AssigneeNotFound>());
  });

  test('an exact full name wins over partial matches', () {
    final dan = buildMember(id: 'd1', name: 'דן');
    final danCohen = buildMember(id: 'd2', name: 'דן כהן');
    expect(found(matchAssignee('דן', [dan, danCohen])), dan);
  });
}
```

- [ ] **Step 2: Run and check they fail.** Expected: compile error.

- [ ] **Step 3: Implement**

```dart
import '../../../domain/entities/team_member.dart';
import '../search_utils.dart';
import 'cell_values.dart';

/// Matching a name written in an import file to one of the members assigned
/// to the event.

sealed class AssigneeMatch {
  const AssigneeMatch();
}

class AssigneeFound extends AssigneeMatch {
  const AssigneeFound(this.member);
  final TeamMember member;
}

class AssigneeNotFound extends AssigneeMatch {
  const AssigneeNotFound();
}

class AssigneeAmbiguous extends AssigneeMatch {
  const AssigneeAmbiguous(this.members);
  final List<TeamMember> members;
}

/// An exact full name first. Otherwise a member matches when every word of
/// [written] is a whole word of their name; exactly one such member is a
/// match, more than one is ambiguous.
AssigneeMatch matchAssignee(String written, List<TeamMember> candidates) {
  final words = _words(written);
  if (words.isEmpty) return const AssigneeNotFound();
  final key = words.join(' ');

  final exact =
      candidates.where((member) => _words(member.name).join(' ') == key).toList();
  if (exact.length == 1) return AssigneeFound(exact.single);
  if (exact.length > 1) return AssigneeAmbiguous(exact);

  final partial = candidates.where((member) {
    final nameWords = _words(member.name).toSet();
    return words.every(nameWords.contains);
  }).toList();
  if (partial.length == 1) return AssigneeFound(partial.single);
  if (partial.isEmpty) return const AssigneeNotFound();
  return AssigneeAmbiguous(partial);
}

final RegExp _whitespace = RegExp(r'\s+');

List<String> _words(String text) => normalizeForSearch(
      cleanText(text).replaceAll(_whitespace, ' '),
    ).toLowerCase().split(' ').where((word) => word.isNotEmpty).toList();
```

- [ ] **Step 4: Run and check they pass.**

- [ ] **Step 5: Commit**: `feat(tasks): match import assignee names to the event's members`

---

### Task 6: Workbook parser

**Files:**
- Create: `shavtzak/lib/domain/entities/imported_stage.dart`
- Create: `shavtzak/lib/core/utils/task_import/task_import_parser.dart`
- Create: `shavtzak/test/support/import_workbook.dart`
- Test: `shavtzak/test/core/utils/task_import/task_import_parser_test.dart`

**Interfaces:**
- Consumes: Tasks 3–5; `eventDays(Event)` from `lib/core/utils/task_utils.dart`; the entities `Stage`, `TaskItem`, `Subtask`, `Event` and `TeamMember`.
- Produces:
  - `class ImportedStage extends Equatable { final Stage stage; final List<TaskItem> tasks; }`
  - Constants `stagesSheetName`, `tasksSheetName`, `maxImportStages = 60`, `maxImportTasks = 400` and `maxImportFileBytes`.
  - `abstract final class StageColumns` / `TaskColumns`, each with the header constants plus `all` (template order) and `required`.
  - `class ImportProblem extends Equatable { final String? sheet; final int? row; final String message; String get text; }`
  - `class TaskImportResult { final List<ImportedStage> stages; final List<ImportProblem> problems; bool get isValid; int get taskCount; int get contactCount; }`
  - `TaskImportResult parseTaskImport(List<int> bytes, {required Event event, required List<TeamMember> candidates, required String currentUserId, required DateTime now, String Function()? newId})`

- [ ] **Step 1: The entity**

```dart
// lib/domain/entities/imported_stage.dart
import 'package:equatable/equatable.dart';

import 'stage.dart';
import 'task_item.dart';

/// A stage read from an import file, with the tasks that go under it. Every
/// id is chosen already, so sending the same import twice cannot create it
/// twice.
class ImportedStage extends Equatable {
  const ImportedStage({required this.stage, required this.tasks});

  final Stage stage;
  final List<TaskItem> tasks;

  @override
  List<Object?> get props => [stage, tasks];
}
```

- [ ] **Step 2: The test workbook builder**

```dart
// test/support/import_workbook.dart
import 'package:excel/excel.dart';
import 'package:shavtzak/core/utils/task_import/task_import_parser.dart';

/// Builds an import workbook in memory. Values: null or '' leave the cell
/// empty, a String is text, an int or double a number, a CellValue itself.
List<int> buildImportWorkbook({
  List<String>? stageHeaders,
  List<List<Object?>> stageRows = const [],
  List<String>? taskHeaders,
  List<List<Object?>> taskRows = const [],
  bool withStagesSheet = true,
  bool withTasksSheet = true,
}) {
  final excel = Excel.createExcel();
  final first = excel.getDefaultSheet()!;
  if (withStagesSheet) {
    excel.rename(first, stagesSheetName);
    final sheet = excel[stagesSheetName];
    sheet.appendRow([for (final h in stageHeaders ?? StageColumns.all) TextCellValue(h)]);
    for (final row in stageRows) {
      sheet.appendRow(row.map(_cell).toList());
    }
  }
  if (withTasksSheet) {
    final sheet = excel[tasksSheetName];
    sheet.appendRow([for (final h in taskHeaders ?? TaskColumns.all) TextCellValue(h)]);
    for (final row in taskRows) {
      sheet.appendRow(row.map(_cell).toList());
    }
  }
  return excel.encode()!;
}

/// A stage row in [StageColumns.all] order.
List<Object?> stageRow({
  Object? number = 1,
  Object? title = 'קליטה',
  Object? date = const DateCellValue(year: 2026, month: 6, day: 15),
  Object? start,
  Object? end,
  Object? requirements,
  Object? location,
  Object? notes,
  Object? contacts,
}) =>
    [number, title, date, start, end, requirements, location, notes, contacts];

/// A task row in [TaskColumns.all] order.
List<Object?> taskRow({
  Object? number = 1,
  Object? title = 'הקמת עמדה',
  Object? description,
  Object? assignees,
  Object? assembly,
  Object? subtasks,
}) =>
    [number, title, description, assignees, assembly, subtasks];

CellValue? _cell(Object? value) => switch (value) {
      null => null,
      '' => null,
      String() => TextCellValue(value),
      int() => IntCellValue(value),
      double() => DoubleCellValue(value),
      CellValue() => value,
      _ => throw ArgumentError('Unsupported cell $value'),
    };
```

- [ ] **Step 3: Write the failing tests**

```dart
// test/core/utils/task_import/task_import_parser_test.dart
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/task_import_parser.dart';

import '../../../support/import_workbook.dart';
import '../../../support/task_fixtures.dart';

void main() {
  final event = buildEvent(
    id: 'e1',
    name: 'דו יומי',
    startDate: DateTime(2026, 6, 15),
    endDate: DateTime(2026, 6, 16),
  );
  final omer = buildMember(id: 'm1', name: 'עומר אליהו');
  final matan = buildMember(id: 'm2', name: 'מתן סלפטי');
  final now = DateTime(2026, 6, 1, 12);

  TaskImportResult parse(List<int> bytes, {List<TeamMember>? candidates}) {
    var counter = 0;
    return parseTaskImport(
      bytes,
      event: event,
      candidates: candidates ?? [omer, matan],
      currentUserId: 'boss',
      now: now,
      newId: () => 'id${++counter}',
    );
  }

  List<String> texts(TaskImportResult result) =>
      result.problems.map((problem) => problem.text).toList();

  test('reads stages and tasks, linking tasks by stage number', () {
    final result = parse(buildImportWorkbook(
      stageRows: [
        stageRow(
          number: 1,
          title: 'מוכנות עמדות',
          start: const TimeCellValue(hour: 8, minute: 30),
          end: const TimeCellValue(hour: 10),
          requirements: '• שולחנות\n• מפות',
          location: 'אולם ימים',
          notes: 'ב-09:30 מוכנים',
          contacts: 'שם: הלל, טלפון: 0522010344, תפקיד: צייר',
        ),
        stageRow(number: 2, title: 'קליטה', date: const DateCellValue(year: 2026, month: 6, day: 16)),
      ],
      taskRows: [
        taskRow(
          number: 1,
          title: 'וידוא עמדת הקליטה',
          description: 'כולל מדפסות',
          assignees: 'עומר אליהו | סלפטי',
          assembly: const TimeCellValue(hour: 8, minute: 30),
          subtasks: 'חיבור מדפסות | סידור תגים',
        ),
        taskRow(number: 2, title: 'איוש'),
      ],
    ));

    expect(texts(result), isEmpty);
    expect(result.isValid, isTrue);
    expect(result.stages, hasLength(2));
    final first = result.stages.first;
    expect(first.stage.eventId, 'e1');
    expect(first.stage.title, 'מוכנות עמדות');
    expect(first.stage.date, DateTime(2026, 6, 15));
    expect(first.stage.startTime, '08:30');
    expect(first.stage.endTime, '10:00');
    expect(first.stage.requirements, '• שולחנות\n• מפות');
    expect(first.stage.hotelLocation, 'אולם ימים');
    expect(first.stage.notes, 'ב-09:30 מוכנים');
    expect(first.stage.contacts.single.phone, '052-2010344');
    expect(first.stage.createdById, 'boss');
    final task = first.tasks.single;
    expect(task.stageId, first.stage.id);
    expect(task.eventId, 'e1');
    expect(task.description, 'כולל מדפסות');
    expect(task.assigneeIds, ['m1', 'm2']);
    expect(task.assemblyTime, '08:30');
    expect(task.subtasks.map((s) => s.title), ['חיבור מדפסות', 'סידור תגים']);
    expect(result.stages.last.tasks.single.title, 'איוש');
    expect(result.taskCount, 2);
    expect(result.contactCount, 1);
  });

  test('headers are found by text: any order, trailing colon, invisible marks', () {
    final result = parse(buildImportWorkbook(
      stageHeaders: ['תאריך', 'שם⁩', 'מספר שלב'],
      stageRows: [
        [const DateCellValue(year: 2026, month: 6, day: 15), 'קליטה', 1],
      ],
      taskHeaders: ['משימה', 'תתי משימות:', ' מספר שלב '],
      taskRows: [
        ['הקמה', 'א | ב', 1],
      ],
    ));
    expect(texts(result), isEmpty);
    expect(result.stages.single.tasks.single.subtasks, hasLength(2));
  });

  test('rows that are empty, spaces only, or only a stage number are skipped', () {
    final result = parse(buildImportWorkbook(
      stageRows: [
        stageRow(),
        stageRow(number: 3, title: null, date: null),
        stageRow(number: null, title: '   ', date: null),
      ],
    ));
    expect(texts(result), isEmpty);
    expect(result.stages, hasLength(1));
  });

  test('missing sheets and required headers are problems', () {
    expect(
      texts(parse(buildImportWorkbook(withTasksSheet: false, stageRows: [stageRow()]))),
      ['חסר גיליון "משימות"'],
    );
    expect(
      texts(parse(buildImportWorkbook(stageHeaders: ['מספר שלב', 'שם'], stageRows: [stageRow()]))),
      ['שלבים, שורה 1: חסרה עמודה "תאריך"'],
    );
  });

  test('a file that is not a workbook is one problem', () {
    expect(texts(parse([1, 2, 3])), ['הקובץ אינו קובץ אקסל תקין']);
  });

  test('stage problems name the sheet and the Excel row', () {
    final result = parse(buildImportWorkbook(stageRows: [
      stageRow(number: 1, title: null),
      stageRow(number: 1, title: 'כפול'),
      stageRow(number: 'שלב', title: 'מילה'),
      stageRow(number: 4, title: 'מחוץ', date: const DateCellValue(year: 2026, month: 6, day: 20)),
      stageRow(number: 5, title: 'שעות', start: '10:00', end: '09:00'),
      stageRow(number: 6, title: 'סיום בלבד', end: '09:00'),
      stageRow(number: 7, title: 'שעה שבורה', start: '25:00'),
      stageRow(number: 8, title: 'ללא תאריך', date: null),
    ]));

    expect(texts(result), [
      'שלבים, שורה 2: חסר שם לשלב',
      'שלבים, שורה 3: מספר שלב 1 מופיע פעמיים (גם בשורה 2)',
      'שלבים, שורה 4: מספר השלב "שלב" אינו מספר שלם',
      'שלבים, שורה 5: התאריך 20/06/2026 אינו מתאריכי האירוע (15/06/2026 – 16/06/2026)',
      'שלבים, שורה 6: שעת הסיום חייבת להיות אחרי שעת ההתחלה',
      'שלבים, שורה 7: שעת סיום דורשת שעת התחלה',
      'שלבים, שורה 8: "שעת התחלה" אינה שעה תקינה: "25:00"',
      'שלבים, שורה 9: חסר תאריך',
    ]);
    expect(result.isValid, isFalse);
  });

  test('contact problems are prefixed with the stage row', () {
    final result = parse(buildImportWorkbook(stageRows: [
      stageRow(contacts: 'טלפון: 0501234567'),
    ]));
    expect(texts(result), ['שלבים, שורה 2: איש קשר 1: חסר שם']);
  });

  test('task problems: unknown stage, missing title, names, long text', () {
    final result = parse(buildImportWorkbook(
      stageRows: [stageRow()],
      taskRows: [
        taskRow(number: 9),
        taskRow(title: null, description: 'רק תיאור'),
        taskRow(assignees: 'יצחק דני'),
        taskRow(title: 'א' * 201),
      ],
    ));
    expect(texts(result), [
      'משימות, שורה 2: מספר שלב 9 לא קיים בגיליון "שלבים"',
      'משימות, שורה 3: חסרה כותרת למשימה',
      'משימות, שורה 4: "יצחק דני" אינו משובץ לאירוע',
      'משימות, שורה 5: הטקסט בעמודה "משימה" ארוך מ-200 תווים',
    ]);
  });

  test('an ambiguous name lists the members it could be', () {
    final boazA = buildMember(id: 'b1', name: 'בועז כהן');
    final boazB = buildMember(id: 'b2', name: 'בועז לוי');
    final result = parse(
      buildImportWorkbook(stageRows: [stageRow()], taskRows: [taskRow(assignees: 'בועז')]),
      candidates: [boazA, boazB],
    );
    expect(texts(result), ['משימות, שורה 2: "בועז" תואם כמה משובצים: בועז כהן, בועז לוי']);
  });

  test('the same member named twice is assigned once', () {
    final result = parse(buildImportWorkbook(
      stageRows: [stageRow()],
      taskRows: [taskRow(assignees: 'עומר אליהו | עומר')],
    ));
    expect(result.stages.single.tasks.single.assigneeIds, ['m1']);
  });

  test('a file with no stage rows is a problem', () {
    expect(texts(parse(buildImportWorkbook())), ['שלבים: אין שלבים בקובץ']);
  });

  test('the stage and task caps are problems', () {
    final stages = [for (var i = 1; i <= maxImportStages + 1; i++) stageRow(number: i, title: 'שלב $i')];
    expect(
      texts(parse(buildImportWorkbook(stageRows: stages))),
      ['שלבים: בקובץ ${maxImportStages + 1} שלבים; אפשר לייבא עד $maxImportStages'],
    );
    final tasks = [for (var i = 0; i <= maxImportTasks; i++) taskRow(title: 'משימה $i')];
    expect(
      texts(parse(buildImportWorkbook(stageRows: [stageRow()], taskRows: tasks))),
      ['משימות: בקובץ ${maxImportTasks + 1} משימות; אפשר לייבא עד $maxImportTasks'],
    );
  });
}
```

Add the missing `TeamMember` import to the test (`package:shavtzak/domain/entities/team_member.dart`).

- [ ] **Step 4: Run and check they fail.** Expected: compile errors.

- [ ] **Step 5: Implement**

```dart
// lib/core/utils/task_import/task_import_parser.dart
import 'package:equatable/equatable.dart';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/event.dart';
import '../../../domain/entities/imported_stage.dart';
import '../../../domain/entities/stage.dart';
import '../../../domain/entities/subtask.dart';
import '../../../domain/entities/task_item.dart';
import '../../../domain/entities/team_member.dart';
import '../task_utils.dart';
import 'assignee_matcher.dart';
import 'cell_values.dart';
import 'contact_cell_parser.dart';

/// Reads an import workbook into stages and tasks for one event, or into the
/// list of everything wrong with it. Nothing here saves anything.

const String stagesSheetName = 'שלבים';
const String tasksSheetName = 'משימות';
const int maxImportStages = 60;
const int maxImportTasks = 400;
const int maxImportFileBytes = 5 * 1024 * 1024;

abstract final class StageColumns {
  static const number = 'מספר שלב';
  static const title = 'שם';
  static const date = 'תאריך';
  static const start = 'שעת התחלה';
  static const end = 'שעת סיום';
  static const requirements = 'דרישות מהמלון ולוגיסטיקה';
  static const location = 'מיקום במלון';
  static const notes = 'הערות';
  static const contacts = 'אנשי קשר';

  static const all = [
    number, title, date, start, end, requirements, location, notes, contacts,
  ];
  static const required = [number, title, date];
}

abstract final class TaskColumns {
  static const number = 'מספר שלב';
  static const title = 'משימה';
  static const description = 'תיאור';
  static const assignees = 'אחראי/ים';
  static const assembly = 'שעת התייצבות';
  static const subtasks = 'תתי משימות';

  static const all = [number, title, description, assignees, assembly, subtasks];
  static const required = [number, title];
}

/// One thing wrong with the file. [row] is the Excel row number.
class ImportProblem extends Equatable {
  const ImportProblem(this.message, {this.sheet, this.row});

  final String message;
  final String? sheet;
  final int? row;

  String get text {
    if (sheet == null) return message;
    if (row == null) return '$sheet: $message';
    return '$sheet, שורה $row: $message';
  }

  @override
  List<Object?> get props => [message, sheet, row];
}

class TaskImportResult {
  const TaskImportResult({required this.stages, required this.problems});

  final List<ImportedStage> stages;
  final List<ImportProblem> problems;

  bool get isValid => problems.isEmpty && stages.isNotEmpty;

  int get taskCount =>
      stages.fold(0, (sum, imported) => sum + imported.tasks.length);

  int get contactCount =>
      stages.fold(0, (sum, imported) => sum + imported.stage.contacts.length);
}

const String _unreadable = 'הקובץ אינו קובץ אקסל תקין';

TaskImportResult parseTaskImport(
  List<int> bytes, {
  required Event event,
  required List<TeamMember> candidates,
  required String currentUserId,
  required DateTime now,
  String Function()? newId,
}) {
  final makeId = newId ?? const Uuid().v4;
  if (bytes.length > maxImportFileBytes) {
    return const TaskImportResult(
      stages: [],
      problems: [ImportProblem('הקובץ גדול מ-5MB')],
    );
  }
  final Excel workbook;
  try {
    workbook = Excel.decodeBytes(bytes);
  } catch (_) {
    return const TaskImportResult(stages: [], problems: [ImportProblem(_unreadable)]);
  }

  final problems = <ImportProblem>[];
  final stageSheet = _findSheet(workbook, stagesSheetName);
  final taskSheet = _findSheet(workbook, tasksSheetName);
  if (stageSheet == null) problems.add(const ImportProblem('חסר גיליון "$stagesSheetName"'));
  if (taskSheet == null) problems.add(const ImportProblem('חסר גיליון "$tasksSheetName"'));
  if (stageSheet == null || taskSheet == null) {
    return TaskImportResult(stages: const [], problems: problems);
  }

  final stageTable =
      _Table.read(stageSheet, stagesSheetName, StageColumns.required, problems);
  final taskTable =
      _Table.read(taskSheet, tasksSheetName, TaskColumns.required, problems);
  if (stageTable == null || taskTable == null) {
    return TaskImportResult(stages: const [], problems: problems);
  }

  final days = eventDays(event);
  final drafts = <_StageDraft>[];
  final draftByNumber = <int, _StageDraft>{};
  final firstRowOfNumber = <int, int>{};

  for (final row in stageTable.rows) {
    void at(String message) => problems
        .add(ImportProblem(message, sheet: stagesSheetName, row: row.number));

    final number = _stageNumber(row, at);
    var isDuplicate = false;
    if (number != null) {
      final first = firstRowOfNumber[number];
      if (first != null) {
        at('מספר שלב $number מופיע פעמיים (גם בשורה $first)');
        isDuplicate = true;
      } else {
        firstRowOfNumber[number] = row.number;
      }
    }

    final title = row.text(StageColumns.title);
    if (title.isEmpty) {
      at('חסר שם לשלב');
    } else {
      _limit(title, 200, StageColumns.title, at);
    }
    final date = _readDate(row, days, at);
    final start = _readTime(row, StageColumns.start, at);
    final end = _readTime(row, StageColumns.end, at);
    if (end != null && row.text(StageColumns.start).isEmpty) {
      at('שעת סיום דורשת שעת התחלה');
    } else if (start != null && end != null && end.compareTo(start) <= 0) {
      at('שעת הסיום חייבת להיות אחרי שעת ההתחלה');
    }
    final requirements = row.text(StageColumns.requirements);
    _limit(requirements, 5000, StageColumns.requirements, at);
    final location = row.text(StageColumns.location);
    _limit(location, 200, StageColumns.location, at);
    final notes = row.text(StageColumns.notes);
    _limit(notes, 5000, StageColumns.notes, at);
    final contacts =
        parseContactCell(row.text(StageColumns.contacts), newId: makeId);
    contacts.problems.forEach(at);

    if (number == null || isDuplicate || title.isEmpty || date == null) continue;
    final draft = _StageDraft(Stage(
      id: makeId(),
      eventId: event.id,
      title: title,
      date: date,
      startTime: start,
      endTime: end,
      requirements: requirements,
      hotelLocation: location,
      notes: notes,
      contacts: contacts.contacts,
      createdAt: now,
      createdById: currentUserId,
      updatedAt: now,
    ));
    drafts.add(draft);
    draftByNumber[number] = draft;
  }

  if (stageTable.rows.isEmpty) {
    problems.add(const ImportProblem('אין שלבים בקובץ', sheet: stagesSheetName));
  } else if (stageTable.rows.length > maxImportStages) {
    problems.add(ImportProblem(
      'בקובץ ${stageTable.rows.length} שלבים; אפשר לייבא עד $maxImportStages',
      sheet: stagesSheetName,
    ));
  }

  for (final row in taskTable.rows) {
    void at(String message) => problems
        .add(ImportProblem(message, sheet: tasksSheetName, row: row.number));

    final number = _stageNumber(row, at);
    if (number != null && !firstRowOfNumber.containsKey(number)) {
      at('מספר שלב $number לא קיים בגיליון "$stagesSheetName"');
    }
    final title = row.text(TaskColumns.title);
    if (title.isEmpty) {
      at('חסרה כותרת למשימה');
    } else {
      _limit(title, 200, TaskColumns.title, at);
    }
    final description = row.text(TaskColumns.description);
    _limit(description, 5000, TaskColumns.description, at);
    final assembly = _readTime(row, TaskColumns.assembly, at);

    final subtaskTitles = _pieces(row.text(TaskColumns.subtasks));
    if (subtaskTitles.length > 50) at('יותר מ-50 תתי משימות');
    for (final subtask in subtaskTitles) {
      if (subtask.length > 200) at('תת המשימה "${subtask.substring(0, 20)}…" ארוכה מ-200 תווים');
    }

    final assignees = <TeamMember>[];
    for (final written in _pieces(row.text(TaskColumns.assignees))) {
      switch (matchAssignee(written, candidates)) {
        case AssigneeFound(:final member):
          if (!assignees.contains(member)) assignees.add(member);
        case AssigneeNotFound():
          at('"$written" אינו משובץ לאירוע');
        case AssigneeAmbiguous(:final members):
          at('"$written" תואם כמה משובצים: ${members.map((m) => m.name).join(', ')}');
      }
    }

    final draft = number == null ? null : draftByNumber[number];
    if (draft == null || title.isEmpty) continue;
    draft.tasks.add(TaskItem(
      id: makeId(),
      eventId: event.id,
      stageId: draft.stage.id,
      title: title,
      description: description,
      subtasks: [
        for (final subtask in subtaskTitles) Subtask(id: makeId(), title: subtask),
      ],
      assemblyTime: assembly,
      assigneeIds: [for (final member in assignees) member.id],
      createdAt: now,
      createdById: currentUserId,
      updatedAt: now,
      event: event,
      stage: draft.stage,
      assignees: assignees,
    ));
  }

  if (taskTable.rows.length > maxImportTasks) {
    problems.add(ImportProblem(
      'בקובץ ${taskTable.rows.length} משימות; אפשר לייבא עד $maxImportTasks',
      sheet: tasksSheetName,
    ));
  }

  return TaskImportResult(
    stages: [
      for (final draft in drafts)
        ImportedStage(stage: draft.stage, tasks: List.unmodifiable(draft.tasks)),
    ],
    problems: problems,
  );
}

class _StageDraft {
  _StageDraft(this.stage);
  final Stage stage;
  final List<TaskItem> tasks = [];
}

Sheet? _findSheet(Excel workbook, String name) {
  for (final entry in workbook.tables.entries) {
    if (cleanText(entry.key).trim() == name) return entry.value;
  }
  return null;
}

final RegExp _spaces = RegExp(r'\s+');
final RegExp _trailingColon = RegExp(r'\s*:\s*$');

String _header(String text) =>
    text.replaceAll(_spaces, ' ').replaceAll(_trailingColon, '').trim();

/// A sheet's header row and the rows worth reading.
class _Table {
  _Table(this.rows);

  final List<_Row> rows;

  static _Table? read(
    Sheet sheet,
    String name,
    List<String> required,
    List<ImportProblem> problems,
  ) {
    final all = sheet.rows;
    final columns = <String, int>{};
    if (all.isNotEmpty) {
      for (var i = 0; i < all.first.length; i++) {
        final header = _header(cellText(all.first[i]?.value));
        if (header.isNotEmpty) columns.putIfAbsent(header, () => i);
      }
    }
    final missing = required.where((h) => !columns.containsKey(h)).toList();
    for (final header in missing) {
      problems.add(ImportProblem('חסרה עמודה "$header"', sheet: name, row: 1));
    }
    if (missing.isNotEmpty) return null;

    final numberColumn = columns[StageColumns.number];
    final rows = <_Row>[];
    for (var index = 1; index < all.length; index++) {
      final cells = all[index];
      var hasContent = false;
      for (var i = 0; i < cells.length; i++) {
        if (i != numberColumn && !isBlankCell(cells[i]?.value)) {
          hasContent = true;
          break;
        }
      }
      if (hasContent) rows.add(_Row(index + 1, cells, columns));
    }
    return _Table(rows);
  }
}

class _Row {
  _Row(this.number, this._cells, this._columns);

  /// The Excel row number, as the person sees it.
  final int number;
  final List<Data?> _cells;
  final Map<String, int> _columns;

  CellValue? operator [](String header) {
    final index = _columns[header];
    if (index == null || index >= _cells.length) return null;
    return _cells[index]?.value;
  }

  String text(String header) => cellText(this[header]);
}

int? _stageNumber(_Row row, void Function(String) at) {
  final text = row.text(StageColumns.number);
  if (text.isEmpty) {
    at('חסר מספר שלב');
    return null;
  }
  final number = cellWholeNumber(row[StageColumns.number]);
  if (number == null) at('מספר השלב "$text" אינו מספר שלם');
  return number;
}

DateTime? _readDate(_Row row, List<DateTime> days, void Function(String) at) {
  final text = row.text(StageColumns.date);
  if (text.isEmpty) {
    at('חסר תאריך');
    return null;
  }
  final date = cellDate(row[StageColumns.date]);
  if (date == null) {
    at('התאריך "$text" אינו תאריך תקין');
    return null;
  }
  if (!days.contains(date)) {
    final range = days.length == 1
        ? formatImportDay(days.single)
        : '${formatImportDay(days.first)} – ${formatImportDay(days.last)}';
    at('התאריך ${formatImportDay(date)} אינו מתאריכי האירוע ($range)');
    return null;
  }
  return date;
}

String? _readTime(_Row row, String header, void Function(String) at) {
  final text = row.text(header);
  if (text.isEmpty) return null;
  final time = cellTime(row[header]);
  if (time == null) at('"$header" אינה שעה תקינה: "$text"');
  return time;
}

void _limit(String text, int max, String header, void Function(String) at) {
  if (text.length > max) at('הטקסט בעמודה "$header" ארוך מ-$max תווים');
}

List<String> _pieces(String cell) => cleanText(cell)
    .split('|')
    .map((piece) => piece.trim())
    .where((piece) => piece.isNotEmpty)
    .toList();
```

- [ ] **Step 6: Run and check they pass**

Run: `cd shavtzak && flutter test test/core/utils/task_import/`
Expected: all pass. If an expected problem string differs only in wording, fix the **code** to match the test; the test strings are the agreed copy.

- [ ] **Step 7: Commit**: `feat(tasks): parse an import workbook into stages and tasks, or its problems`

---

### Task 7: Template workbook

**Files:**
- Create: `shavtzak/lib/core/utils/task_import/task_import_template.dart`
- Test: `shavtzak/test/core/utils/task_import/task_import_template_test.dart`

**Interfaces:**
- Consumes: `StageColumns`, `TaskColumns`, the sheet names and `parseTaskImport` (Task 6); `eventDays`.
- Produces: `const String taskImportTemplateFileName = 'תבנית משימות דו יומי.xlsx';` and `List<int> buildTaskImportTemplate(Event event)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/task_import_parser.dart';
import 'package:shavtzak/core/utils/task_import/task_import_template.dart';

import '../../../support/task_fixtures.dart';

void main() {
  final event = buildEvent(
    id: 'e1',
    startDate: DateTime(2026, 6, 15),
    endDate: DateTime(2026, 6, 16),
  );

  test('the template parses to one stage and one task on the event\'s first day', () {
    final result = parseTaskImport(
      buildTaskImportTemplate(event),
      event: event,
      candidates: const [],
      currentUserId: 'boss',
      now: DateTime(2026, 6, 1),
    );

    // The only problem is the made-up assignee, by design.
    expect(
      result.problems.map((p) => p.text),
      ['משימות, שורה 2: "ישראל ישראלי" אינו משובץ לאירוע'],
    );
    final stage = result.stages.single;
    expect(stage.stage.date, DateTime(2026, 6, 15));
    expect(stage.stage.startTime, '09:00');
    expect(stage.stage.contacts.single.phone, '050-0000000');
    expect(stage.tasks.single.subtasks, hasLength(2));
  });

  test('with the example assignee assigned, the template imports cleanly', () {
    final israel = buildMember(id: 'i1', name: 'ישראל ישראלי');
    final result = parseTaskImport(
      buildTaskImportTemplate(event),
      event: event,
      candidates: [israel],
      currentUserId: 'boss',
      now: DateTime(2026, 6, 1),
    );
    expect(result.isValid, isTrue);
  });
}
```

- [ ] **Step 2: Run and check it fails.**

- [ ] **Step 3: Implement**

```dart
import 'package:excel/excel.dart';

import '../../../domain/entities/event.dart';
import '../task_utils.dart';
import 'task_import_parser.dart';

const String taskImportTemplateFileName = 'תבנית משימות דו יומי.xlsx';

/// An empty import file for [event]: both sheets, right to left, with every
/// header and one made-up example row each.
List<int> buildTaskImportTemplate(Event event) {
  final excel = Excel.createExcel();
  excel.rename(excel.getDefaultSheet()!, stagesSheetName);
  final stages = excel[stagesSheetName];
  final tasks = excel[tasksSheetName];
  stages.isRTL = true;
  tasks.isRTL = true;

  stages.appendRow([for (final header in StageColumns.all) TextCellValue(header)]);
  stages.appendRow([
    const IntCellValue(1),
    TextCellValue('קליטה והתכנסות'),
    DateCellValue.fromDateTime(eventDays(event).first),
    const TimeCellValue(hour: 9),
    const TimeCellValue(hour: 10, minute: 30),
    TextCellValue('• שולחן קליטה בלובי\n• עמדת כיבוד קל'),
    TextCellValue('לובי המלון'),
    TextCellValue('להגיע חצי שעה לפני'),
    TextCellValue('שם: ישראל ישראלי, טלפון: 050-0000000, תפקיד: מנהל המלון'),
  ]);

  tasks.appendRow([for (final header in TaskColumns.all) TextCellValue(header)]);
  tasks.appendRow([
    const IntCellValue(1),
    TextCellValue('הקמת עמדת הקליטה'),
    TextCellValue('לוודא שיש מדפסת ותגים'),
    TextCellValue('ישראל ישראלי'),
    const TimeCellValue(hour: 8, minute: 30),
    TextCellValue('חיבור מדפסות | סידור תגים'),
  ]);

  excel.setDefaultSheet(stagesSheetName);
  return excel.encode()!;
}
```

- [ ] **Step 4: Run and check it passes.** If `DateCellValue` reads back as a number or a `DateTimeCellValue`, the parser already handles both; the test checks the day only.

- [ ] **Step 5: Commit**: `feat(tasks): build the import template workbook`

---

### Task 8: Data layer and bloc

**Files:**
- Create: `shavtzak/lib/data/models/stage_import_model.dart`
- Test: `shavtzak/test/data/models/stage_import_model_test.dart`
- Modify:
  - `shavtzak/lib/data/data_sources/database_interface.dart`: add after `deleteStage`.
  - `shavtzak/lib/data/data_sources/firestore_database.dart`: add after `deleteStage`, around line 2657.
  - `shavtzak/lib/data/data_sources/logging_database.dart`: add after `deleteStage`.
  - `shavtzak/lib/data/repositories/task_repository.dart`: add after `insertStage`, line 111.
  - `shavtzak/lib/presentation/bloc/task/task_event.dart` and `task_bloc.dart`.
  - `shavtzak/test/support/fake_task_repository.dart`.
  - `shavtzak/test/presentation/bloc/task_bloc_test.dart`.

**Interfaces:**
- Consumes: `ImportedStage` (Task 6), `StageModel.toMutationPayload` and `TaskItemModel.toMutationPayload`.
- Produces:
  - `StageImportModel.toMutationPayload(String eventId, List<ImportedStage> stages) → Map<String, dynamic>`
  - `Future<void> importStages(String eventId, List<ImportedStage> stages)` on `DatabaseInterface`, `FirestoreDatabase`, `LoggingDatabase`, `TaskRepository` and `FakeTaskRepository`. The fake records `'importStages:<eventId>:<stageCount>'`.
  - `class ImportStages extends TaskEvent { final String eventId; final List<ImportedStage> stages; final CrudActionCompleter? completion; }`

- [ ] **Step 1: Write the failing model test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/stage_import_model.dart';
import 'package:shavtzak/domain/entities/imported_stage.dart';

import '../../support/task_fixtures.dart';

void main() {
  test('the payload carries the event and every stage with its tasks', () {
    final stage = buildStage(id: 's1', eventId: 'e1', date: DateTime(2026, 6, 15));
    final task = buildTask(id: 't1', eventId: 'e1', stageId: 's1');
    final payload = StageImportModel.toMutationPayload('e1', [
      ImportedStage(stage: stage, tasks: [task]),
    ]);

    expect(payload['eventId'], 'e1');
    final stages = payload['stages'] as List;
    expect(stages, hasLength(1));
    final entry = stages.single as Map<String, dynamic>;
    expect((entry['stage'] as Map)['id'], 's1');
    expect((entry['stage'] as Map)['date'], '2026-06-15');
    expect(((entry['tasks'] as List).single as Map)['stageId'], 's1');
  });
}
```

- [ ] **Step 2: Implement the model**

```dart
import '../../domain/entities/imported_stage.dart';
import 'stage_model.dart';
import 'task_item_model.dart';

/// The payload of the backend's `stage.import`: each stage and its tasks in
/// exactly the shape `stage.insert` and `task.insert` take.
class StageImportModel {
  static Map<String, dynamic> toMutationPayload(
    String eventId,
    List<ImportedStage> stages,
  ) {
    return {
      'eventId': eventId,
      'stages': [
        for (final imported in stages)
          {
            'stage': StageModel.toMutationPayload(imported.stage),
            'tasks': [
              for (final task in imported.tasks)
                TaskItemModel.toMutationPayload(task),
            ],
          },
      ],
    };
  }
}
```

- [ ] **Step 3: Add `importStages` to every layer**

`database_interface.dart`:
```dart
  /// Creates every stage of [stages] and their tasks in one go, for an event
  /// that has no stages yet. All or nothing.
  Future<void> importStages(String eventId, List<ImportedStage> stages);
```

`firestore_database.dart`:
```dart
  @override
  Future<void> importStages(String eventId, List<ImportedStage> stages) async {
    await _invokeMutation(
      'stage.import',
      payload: StageImportModel.toMutationPayload(eventId, stages),
    );
  }
```

`logging_database.dart`:
```dart
  @override
  Future<void> importStages(String eventId, List<ImportedStage> stages) =>
      _runFuture(
        op: 'importStages',
        ctx: {'collection': 'stages', 'eventId': eventId, 'count': stages.length},
        countOf: (_) => null,
        action: () => _inner.importStages(eventId, stages),
      );
```

`task_repository.dart`:
```dart
  Future<void> importStages(String eventId, List<ImportedStage> stages) =>
      _database.importStages(eventId, stages);
```

`fake_task_repository.dart`:
```dart
  @override
  Future<void> importStages(String eventId, List<ImportedStage> stages) =>
      _record('importStages:$eventId:${stages.length}');
```

Add the imports each file needs (`imported_stage.dart`, `stage_import_model.dart`).

- [ ] **Step 4: Add the bloc event and handler**

`task_event.dart`:
```dart
class ImportStages extends TaskEvent {
  final String eventId;
  final List<ImportedStage> stages;
  final CrudActionCompleter? completion;

  const ImportStages(this.eventId, this.stages, {this.completion});

  @override
  List<Object?> get props => [eventId, stages];
}
```

`task_bloc.dart`, next to `on<DeleteStage>`:
```dart
    on<ImportStages>(
      (event, emit) => _run(
        event.completion,
        () => _repository.importStages(event.eventId, event.stages),
      ),
    );
```

- [ ] **Step 5: Add a bloc test** to `test/presentation/bloc/task_bloc_test.dart`, next to the test that dispatches `CreateStage`, using the same `dispatch` helper:

```dart
    test('ImportStages sends the whole import to the repository', () async {
      final bloc = TaskBloc(repository: repository);
      final result = await dispatch(
        bloc,
        (c) => ImportStages(
          'e1',
          [ImportedStage(stage: buildStage(id: 's1'), tasks: const [])],
          completion: c,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(repository.calls, ['importStages:e1:1']);
      await bloc.close();
    });
```

If that file's repository double is not `FakeTaskRepository`, give its double the same `importStages` recording line.

- [ ] **Step 6: Run analyze and the tests**

Run: `cd shavtzak && flutter analyze 2>&1 | tail -1 && flutter test test/data test/presentation/bloc`
Expected: 107 issues; all pass. The generated mockito mocks need no regeneration: classes with `noSuchMethod` may leave members out.

- [ ] **Step 7: Commit**: `feat(tasks): send an import to the backend through the task bloc`

---

### Task 9: Browser file picking and download

**Files:**
- Create: `shavtzak/lib/core/services/picked_import_file.dart`, `task_import_files.dart`, `task_import_files_web.dart` and `task_import_files_stub.dart`
- Create: `shavtzak/test/support/fake_task_import_files.dart`

**Interfaces:**
- Produces:
  - `class PickedImportFile { final String name; final Uint8List bytes; }`
  - `abstract class TaskImportFiles { Future<PickedImportFile?> pickXlsx(); void saveXlsx(List<int> bytes, String filename); }`
  - `class BrowserTaskImportFiles implements TaskImportFiles` (const constructor)
  - `class FakeTaskImportFiles implements TaskImportFiles` (tests), with `picks` (a queue), `pickCalls` and `saved`.

- [ ] **Step 1: Implement**

```dart
// picked_import_file.dart
import 'dart:typed_data';

/// A file the person picked to import.
class PickedImportFile {
  const PickedImportFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}
```

```dart
// task_import_files.dart
import 'picked_import_file.dart';
import 'task_import_files_stub.dart'
    if (dart.library.html) 'task_import_files_web.dart' as platform;

export 'picked_import_file.dart';

/// Picking an import file and saving the template. An interface so the
/// screens can be tested without a browser.
abstract class TaskImportFiles {
  /// Opens the file picker; null when the person cancels.
  Future<PickedImportFile?> pickXlsx();

  void saveXlsx(List<int> bytes, String filename);
}

class BrowserTaskImportFiles implements TaskImportFiles {
  const BrowserTaskImportFiles();

  @override
  Future<PickedImportFile?> pickXlsx() => platform.pickXlsxFile();

  @override
  void saveXlsx(List<int> bytes, String filename) =>
      platform.saveXlsxFile(bytes, filename);
}
```

```dart
// task_import_files_stub.dart
import 'picked_import_file.dart';

Future<PickedImportFile?> pickXlsxFile() =>
    throw UnsupportedError('Picking files needs a browser');

void saveXlsxFile(List<int> bytes, String filename) =>
    throw UnsupportedError('Saving files needs a browser');
```

```dart
// task_import_files_web.dart
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'picked_import_file.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

Future<PickedImportFile?> pickXlsxFile() {
  final completer = Completer<PickedImportFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.xlsx,$_xlsxMime';

  void finish(PickedImportFile? file) {
    if (!completer.isCompleted) completer.complete(file);
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        finish(null);
        return;
      }
      file.arrayBuffer().toDart.then(
        (buffer) => finish(
          PickedImportFile(name: file.name, bytes: buffer.toDart.asUint8List()),
        ),
        onError: (Object error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      );
    }).toJS,
  );
  // Fired by current browsers when the picker closes without a file.
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  input.click();
  return completer.future;
}

void saveXlsxFile(List<int> bytes, String filename) {
  final blob = web.Blob(
    <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: _xlsxMime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Revoking at once can cancel the download in some browsers.
  Timer(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}
```

```dart
// test/support/fake_task_import_files.dart
import 'package:shavtzak/core/services/task_import_files.dart';

class FakeTaskImportFiles implements TaskImportFiles {
  /// What each pick returns, in order; an empty queue means "cancelled".
  final List<PickedImportFile?> picks = [];
  final List<(List<int>, String)> saved = [];
  int pickCalls = 0;

  @override
  Future<PickedImportFile?> pickXlsx() async {
    pickCalls++;
    return picks.isEmpty ? null : picks.removeAt(0);
  }

  @override
  void saveXlsx(List<int> bytes, String filename) => saved.add((bytes, filename));
}
```

- [ ] **Step 2: Analyze**

Run: `cd shavtzak && flutter analyze 2>&1 | tail -1`
Expected: 107. If the conditional import key has to be `dart.library.js_interop`, match `assignment_share_image_service.dart`, which uses `dart.library.html`.

- [ ] **Step 3: Commit**: `feat(tasks): pick an import file and save the template in the browser`

---

### Task 10: The import dialog

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/widgets/task_import_dialog.dart`
- Test: `shavtzak/test/presentation/screens/task/widgets/task_import_dialog_test.dart`

**Interfaces:**
- Consumes: `parseTaskImport` and `TaskImportResult` (Task 6), `TaskImportFiles` and `PickedImportFile` (Task 9), `sortStages` (`task_utils.dart`), `stageSummaryLine` (`widgets/stage_card.dart`) and `CrudActionResult`.
- Produces: `Future<TaskImportResult?> showTaskImportDialog(BuildContext context, {required PickedImportFile file, required Event event, required TaskImportFiles files, required Stream<List<TeamMember>> assignees, required Future<CrudActionResult> Function(List<ImportedStage> stages) onImport, required String currentUserId, required DateTime now})`. It returns the result on a successful import and null otherwise.
- Keys:
  - `task-import-summary`
  - `task-import-problem-count`
  - `task-import-problem-<i>`
  - `task-import-members-error`
  - `task-import-error`
  - `task-import-confirm`
  - `task-import-pick-again`
  - `task-import-cancel`
  - `task-import-stage-<stageId>`

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/task_import_files.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/core/utils/task_import/task_import_parser.dart';
import 'package:shavtzak/domain/entities/imported_stage.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_import_dialog.dart';

import '../../../../support/fake_task_import_files.dart';
import '../../../../support/import_workbook.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  final event = buildEvent(id: 'e1', startDate: DateTime(2026, 6, 15), endDate: DateTime(2026, 6, 16));
  final omer = buildMember(id: 'm1', name: 'עומר אליהו');

  PickedImportFile file(List<int> bytes) =>
      PickedImportFile(name: 'משימות.xlsx', bytes: Uint8List.fromList(bytes));

  final clean = file(buildImportWorkbook(
    stageRows: [stageRow(title: 'קליטה'), stageRow(number: 2, title: 'ערב')],
    taskRows: [taskRow(assignees: 'עומר')],
  ));
  final broken = file(buildImportWorkbook(
    stageRows: [stageRow(title: null)],
  ));

  late FakeTaskImportFiles files;
  late List<List<ImportedStage>> sent;
  late Completer<CrudActionResult> backend;
  TaskImportResult? returned;

  Future<void> open(
    WidgetTester tester,
    PickedImportFile picked, {
    Stream<List<TeamMember>>? assignees,
  }) async {
    files = FakeTaskImportFiles();
    sent = [];
    backend = Completer<CrudActionResult>();
    returned = null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              returned = await showTaskImportDialog(
                context,
                file: picked,
                event: event,
                files: files,
                assignees: assignees ?? Stream.value([omer]),
                onImport: (stages) {
                  sent.add(stages);
                  return backend.future;
                },
                currentUserId: 'boss',
                now: DateTime(2026, 6, 1),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a clean file shows the summary and every stage', (tester) async {
    await open(tester, clean);
    expect(
      tester.widget<Text>(find.byKey(const Key('task-import-summary'))).data,
      '2 שלבים · 1 משימות · 0 אנשי קשר',
    );
    expect(find.text('קליטה'), findsOneWidget);
    expect(find.text('ערב'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('task-import-confirm'))).onPressed, isNotNull);
  });

  testWidgets('problems are listed and the import is disabled', (tester) async {
    await open(tester, broken);
    expect(find.text('נמצאה בעיה אחת בקובץ'), findsOneWidget);
    expect(find.text('שלבים, שורה 2: חסר שם לשלב'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('task-import-confirm'))).onPressed, isNull);
  });

  testWidgets('picking another file checks it again', (tester) async {
    await open(tester, broken);
    files.picks.add(clean);
    await tester.tap(find.byKey(const Key('task-import-pick-again')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('task-import-summary')), findsOneWidget);
  });

  testWidgets('importing shows a spinner, sends once, and closes on success', (tester) async {
    await open(tester, clean);
    await tester.tap(find.byKey(const Key('task-import-confirm')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('task-import-confirm'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('task-import-confirm')), warnIfMissed: false);
    expect(sent, hasLength(1));
    expect(sent.single, hasLength(2));

    backend.complete(const CrudActionResult.success());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-import-confirm')), findsNothing);
    expect(returned?.stages, hasLength(2));
  });

  testWidgets('a refused import stays open and says why', (tester) async {
    await open(tester, clean);
    await tester.tap(find.byKey(const Key('task-import-confirm')));
    await tester.pump();
    backend.complete(const CrudActionResult.failure('לאירוע כבר יש שלבים'));
    await tester.pump();

    expect(find.text('לאירוע כבר יש שלבים'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('task-import-confirm'))).onPressed, isNotNull);
  });

  testWidgets('when the assigned members fail to load, nothing can be imported', (tester) async {
    await open(tester, clean, assignees: Stream.error(Exception('denied')));
    expect(find.byKey(const Key('task-import-members-error')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('task-import-confirm'))).onPressed, isNull);
  });
}
```

Add `import 'dart:typed_data';` at the top of the test.

- [ ] **Step 2: Run and check they fail.**

- [ ] **Step 3: Implement**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/task_import_files.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/task_import/task_import_parser.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/imported_stage.dart';
import '../../../../domain/entities/team_member.dart';
import 'stage_card.dart';

/// Checks [file] against [event] and, when it is clean, imports it.
///
/// The file is parsed here, once the members assigned to the event arrive
/// (names are matched against them). Any problem blocks the import; the
/// person fixes the file and picks it again from this dialog. The import
/// itself goes through [onImport]; the dialog stays open with a spinner until
/// it answers and returns the result on success.
Future<TaskImportResult?> showTaskImportDialog(
  BuildContext context, {
  required PickedImportFile file,
  required Event event,
  required TaskImportFiles files,
  required Stream<List<TeamMember>> assignees,
  required Future<CrudActionResult> Function(List<ImportedStage> stages)
      onImport,
  required String currentUserId,
  required DateTime now,
}) {
  return showDialog<TaskImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TaskImportDialog(
      file: file,
      event: event,
      files: files,
      assignees: assignees,
      onImport: onImport,
      currentUserId: currentUserId,
      now: now,
    ),
  );
}

class _TaskImportDialog extends StatefulWidget {
  const _TaskImportDialog({
    required this.file,
    required this.event,
    required this.files,
    required this.assignees,
    required this.onImport,
    required this.currentUserId,
    required this.now,
  });

  final PickedImportFile file;
  final Event event;
  final TaskImportFiles files;
  final Stream<List<TeamMember>> assignees;
  final Future<CrudActionResult> Function(List<ImportedStage> stages) onImport;
  final String currentUserId;
  final DateTime now;

  @override
  State<_TaskImportDialog> createState() => _TaskImportDialogState();
}

class _TaskImportDialogState extends State<_TaskImportDialog> {
  late PickedImportFile _file = widget.file;
  StreamSubscription<List<TeamMember>>? _subscription;
  List<TeamMember>? _members;
  bool _membersFailed = false;
  TaskImportResult? _result;
  bool _isImporting = false;
  String? _importError;

  bool get _canImport =>
      !_isImporting && !_membersFailed && (_result?.isValid ?? false);

  @override
  void initState() {
    super.initState();
    _subscription = widget.assignees.listen(
      (members) {
        if (!mounted) return;
        setState(() {
          _members = members;
          _membersFailed = false;
          // Not while importing: new ids would no longer match what was sent.
          if (!_isImporting) _result = _parse();
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _membersFailed = true);
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  TaskImportResult? _parse() {
    final members = _members;
    if (members == null) return null;
    return parseTaskImport(
      _file.bytes,
      event: widget.event,
      candidates: members,
      currentUserId: widget.currentUserId,
      now: widget.now,
    );
  }

  Future<void> _pickAgain() async {
    final picked = await widget.files.pickXlsx();
    if (picked == null || !mounted) return;
    setState(() {
      _file = picked;
      _importError = null;
      _result = _parse();
    });
  }

  Future<void> _import() async {
    final result = _result;
    if (!_canImport || result == null) return;
    setState(() {
      _isImporting = true;
      _importError = null;
    });
    final outcome = await widget.onImport(result.stages);
    if (!mounted) return;
    if (outcome.isSuccess) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _isImporting = false;
      _importError = outcome.message ?? 'הייבוא נכשל. נסו שוב.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: !_isImporting,
        child: Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                  child: Text('ייבוא מאקסל', style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _file.name,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: _buildContent(theme, result),
                  ),
                ),
                if (_importError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Text(
                      _importError!,
                      key: const Key('task-import-error'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        key: const Key('task-import-pick-again'),
                        onPressed: _isImporting ? null : _pickAgain,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('בחירת קובץ אחר'),
                      ),
                      TextButton(
                        key: const Key('task-import-cancel'),
                        onPressed: _isImporting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(result?.isValid ?? false ? 'ביטול' : 'סגירה'),
                      ),
                      FilledButton(
                        key: const Key('task-import-confirm'),
                        onPressed: _canImport ? _import : null,
                        child: _isImporting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('ייבוא'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, TaskImportResult? result) {
    if (_membersFailed) {
      return Text(
        'טעינת המשובצים לאירוע נכשלה, ולכן לא ניתן לבדוק את האחראים. נסו שוב.',
        key: const Key('task-import-members-error'),
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.error),
      );
    }
    if (result == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (result.problems.isNotEmpty) {
      final count = result.problems.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 1 ? 'נמצאה בעיה אחת בקובץ' : 'נמצאו $count בעיות בקובץ',
            key: const Key('task-import-problem-count'),
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      result.problems[i].text,
                      key: Key('task-import-problem-$i'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'יש לתקן את הקובץ ולבחור אותו שוב. דבר לא נשמר.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey.shade700),
          ),
        ],
      );
    }
    final stages = {for (final s in result.stages) s.stage.id: s};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${result.stages.length} שלבים · ${result.taskCount} משימות · '
          '${result.contactCount} אנשי קשר',
          key: const Key('task-import-summary'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final stage in sortStages([for (final s in result.stages) s.stage]))
          Padding(
            key: Key('task-import-stage-${stage.id}'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stage.title,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(stageSummaryLine(stage),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                Text('${stages[stage.id]!.tasks.length} משימות'),
              ],
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run and check they pass**

Run: `cd shavtzak && flutter test test/presentation/screens/task/widgets/task_import_dialog_test.dart`

- [ ] **Step 5: Commit**: `feat(tasks): import dialog with a preview and the file's problems`

---

### Task 11: Wire the screen

**Files:**
- Modify: `shavtzak/lib/presentation/screens/task/event_tasks_screen.dart`
- Test: `shavtzak/test/presentation/screens/task/event_tasks_screen_test.dart`

**Interfaces:**
- Consumes: `showTaskImportDialog` (Task 10), `TaskImportFiles` (Task 9), `buildTaskImportTemplate` and `taskImportTemplateFileName` (Task 7), `ImportStages` (Task 8).
- Produces: `EventTasksScreen({..., TaskImportFiles importFiles = const BrowserTaskImportFiles()})`, and the empty-state buttons `tasks-import` and `tasks-import-template`.

- [ ] **Step 1: Write the failing tests** (in `event_tasks_screen_test.dart`)

Add `FakeTaskImportFiles? importFiles` to `pumpScreen` and pass `importFiles: importFiles ?? FakeTaskImportFiles()` to `EventTasksScreen`. Then add:

```dart
  group('excel import', () {
    final admin = buildMember(id: 'boss', isAdmin: true);

    testWidgets('a manager sees import and template on an event without stages',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: const [], stages: const []);
      expect(find.byKey(const Key('tasks-import')), findsOneWidget);
      expect(find.byKey(const Key('tasks-import-template')), findsOneWidget);
    });

    testWidgets('a member does not, and nobody does once there are stages',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: const [], stages: const []);
      expect(find.byKey(const Key('tasks-import')), findsNothing);
    });

    testWidgets('no import once the event has a stage', (tester) async {
      await pumpScreen(tester, user: admin, tasks: const []);
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      expect(find.byKey(const Key('tasks-import')), findsNothing);
    });

    testWidgets('the template downloads under its name', (tester) async {
      final files = FakeTaskImportFiles();
      await pumpScreen(tester, user: admin, tasks: const [], stages: const [], importFiles: files);
      await tester.tap(find.byKey(const Key('tasks-import-template')));
      expect(files.saved.single.$2, 'תבנית משימות דו יומי.xlsx');
      expect(files.saved.single.$1, isNotEmpty);
    });

    testWidgets('cancelling the picker opens nothing', (tester) async {
      final files = FakeTaskImportFiles();
      await pumpScreen(tester, user: admin, tasks: const [], stages: const [], importFiles: files);
      await tester.tap(find.byKey(const Key('tasks-import')));
      await tester.pump();
      expect(files.pickCalls, 1);
      expect(find.byKey(const Key('task-import-confirm')), findsNothing);
    });

    testWidgets('a clean file imports through the bloc and reports the counts',
        (tester) async {
      final files = FakeTaskImportFiles()
        ..picks.add(PickedImportFile(
          name: 'a.xlsx',
          bytes: Uint8List.fromList(buildImportWorkbook(
            stageRows: [stageRow(date: const DateCellValue(year: 2026, month: 10, day: 20))],
            taskRows: [taskRow(assignees: 'דנה')],
          )),
        ));
      await pumpScreen(tester, user: admin, tasks: const [], stages: const [], importFiles: files);
      await tester.tap(find.byKey(const Key('tasks-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-import-confirm')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['importStages:e1:1']);
      expect(find.text('יובאו 1 שלבים ו-1 משימות'), findsOneWidget);
    });
  });
```

The screen test's event `e1` runs 20–21/10/2026, and `repository.assigneesByEvent['e1']` holds דנה and יואב, so `'דנה'` matches. Add imports for `dart:typed_data`, `package:excel/excel.dart` (for `DateCellValue`; hide anything that clashes with Flutter, e.g. `import 'package:excel/excel.dart' show DateCellValue;`), `task_import_files.dart`, `import_workbook.dart` and `fake_task_import_files.dart`.

- [ ] **Step 2: Run and check they fail.**

- [ ] **Step 3: Implement** in `event_tasks_screen.dart`

Constructor:
```dart
  const EventTasksScreen({
    super.key,
    required this.eventId,
    this.clock,
    this.importFiles = const BrowserTaskImportFiles(),
  });

  /// Picking the import file and saving the template; faked in tests.
  final TaskImportFiles importFiles;
```

Actions (next to `_createStage`):
```dart
  Future<void> _importFromExcel(Event event, TeamMember user) async {
    Logger.action('tap:tasksImport');
    final file = await widget.importFiles.pickXlsx();
    if (file == null || !mounted) return;
    final result = await showTaskImportDialog(
      context,
      file: file,
      event: event,
      files: widget.importFiles,
      assignees: context.read<TaskRepository>().watchEventAssignees(event.id),
      onImport: (stages) => _send(
        (completion) => ImportStages(event.id, stages, completion: completion),
      ),
      currentUserId: user.id,
      now: _now,
    );
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          'יובאו ${result.stages.length} שלבים ו-${result.taskCount} משימות',
        ),
      ));
  }

  void _downloadTemplate(Event event) {
    Logger.action('tap:tasksImportTemplate');
    widget.importFiles.saveXlsx(
      buildTaskImportTemplate(event),
      taskImportTemplateFileName,
    );
  }
```

Empty state: change the call to `_buildEmptyState(hasStages: stages.isNotEmpty, user: user, event: event)` and the signature to take `required Event event`. In the `!hasStages` branch, after the hint text, add:

```dart
            if (!hasStages && canManageTasks(user)) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('tasks-import'),
                    onPressed: () => _importFromExcel(event, user),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('ייבוא מאקסל'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('tasks-import-template'),
                    onPressed: () => _downloadTemplate(event),
                    icon: const Icon(Icons.download),
                    label: const Text('הורדת תבנית'),
                  ),
                ],
              ),
            ],
```

- [ ] **Step 4: Run the whole suite and analyze**

Run: `cd shavtzak && flutter analyze 2>&1 | tail -1 && flutter test 2>&1 | tail -1`
Expected: 107 issues; all pass.

- [ ] **Step 5: Commit**: `feat(tasks): import stages and tasks from Excel on an event without stages`

---

### Task 12: Real-file check, docs, review

- [ ] **Step 1: Parse the sample file locally, without committing it**

Write `shavtzak/test/zz_sample_import_test.dart` (temporary). It reads `/private/tmp/claude-501/-Users-omerbengal-Documents-Github-Projects-Shavtzak/3772abe7-b08d-43be-8f83-2bea25762b7f/scratchpad/xlsx_in/format.xlsx`, runs `parseTaskImport` against a two-day event on 15–16/06/2026 with candidates `עומר אליהו`, `מתן סלפטי`, `בועז כהן` and `יצחק דני`, and prints every problem's `text`. Expected:
- 2 stages and 4 tasks.
- 4 contacts on stage 1, with phones `052-2010344`, `050-6285016`, `052-2756524` and `052-2349392`.
- No problems.

Report anything else to the user. Delete the file; `git status` must not list it.

- [ ] **Step 2: Docs**

In `CLAUDE.md`, add to the TaskBloc paragraph: an event with no stages can be filled from an Excel file (`lib/core/utils/task_import/`, backend `stage.import`, all or nothing). Then update the test counts on the Testing line.

- [ ] **Step 3: Full verification**

Run:
- `cd functions && npm test 2>&1 | tail -3`
- `cd shavtzak && flutter analyze 2>&1 | tail -1 && flutter test 2>&1 | tail -1`

Expected: all pass; analyze shows 107.

- [ ] **Step 4: Independent review.** Dispatch one reviewer over the branch diff against `main`, with the spec. Fix what it confirms.

- [ ] **Step 5: Commit**: `docs: describe the Excel import`

- [ ] **Step 6: Hand-off.** Tell the user:
  - the worktree name and path;
  - that Functions must be deployed first: `firebase deploy --only functions` from the worktree root, checked with `firebase functions:list`;
  - that the client is then tested with `flutter run` from `shavtzak/`.

  Do not deploy without the user's go.
