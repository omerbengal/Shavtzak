# Excel import of stages and tasks — design

Date: 2026-10-15. Status: draft for review.

## Goal

A manager fills one Excel file with an event's stages and tasks and imports it
into that event, instead of typing every stage and task through the forms.
The file is checked in full first; nothing is saved unless the whole file is
valid, and then everything is saved at once.

## Decisions (agreed)

| Question | Decision |
|---|---|
| Event already has stages | Import is offered **only while the event has no stages**. To redo, delete the stages and import again. The backend enforces it too. |
| Problems in the file | **Any** problem blocks the import. The preview lists every problem; the file must be fixed and picked again. |
| Contacts | Stay in **one cell** on the stages sheet, parsed tolerantly. |
| Task description | New optional column **תיאור**. |
| Template | The app offers **הורדת תבנית**. |
| Matching assignee names | Exact full name first; otherwise a **unique partial** name. Only members assigned to the event are candidates. |
| Save | One backend call, **one transaction**: all or nothing. |

## Who and where

- Managers only (admins and `canManageTasks`), on `/tasks/<eventId>`.
- Shown only while the event has no stages, in the empty state ("אין עדיין
  שלבים לאירוע זה"), as two buttons: **ייבוא מאקסל** and **הורדת תבנית**.
  Once a stage exists, both buttons disappear.

## The file

An `.xlsx` workbook (at most 5 MB) with two sheets, found by name: **שלבים** and
**משימות**. Other sheets are ignored.

### General rules

- **Headers on row 1, found by text, not position.** Column order is free,
  extra columns are ignored. Header text is compared after trimming, dropping
  a trailing `:` and removing invisible characters (see below). A missing
  required header is a problem.
- **Invisible characters** (U+200E/U+200F, U+202A–U+202E, U+2066–U+2069,
  U+FEFF) are stripped from every cell, and a non-breaking space counts as a
  space. Your sample file has U+2069 glued to three phone numbers.
- **Empty rows are skipped**: a row whose cells are all empty, or whose only
  filled cell is `מספר שלב`, is skipped.
- **Row numbers in problems are the Excel row numbers**, as the person sees
  them.
- **Lists inside a cell** (assignees, subtasks, contacts) are split on `|`;
  empty pieces are dropped.
- **Limits are the forms' limits.** Text over a limit is a problem, never cut
  silently. Per file: at most **60 stages** and **400 tasks**, which keeps the
  save inside one Firestore transaction (500 writes).

### Values

- **Stage number**: a whole number (Excel's `1.0` is fine). Required on every
  non-skipped row of both sheets.
- **Date**: an Excel date cell, an Excel date serial number, or text
  `dd/MM/yyyy` (`d/M/yyyy` too). It must be one of the event's days.
- **Time**: an Excel time cell, a fraction of a day (`0.354166…` = 08:30,
  rounded to the minute), a date-time cell (its time is used), or text `H:mm` /
  `HH:mm`.

### Sheet שלבים — one row per stage

| Header | Required | Maps to | Rules |
|---|---|---|---|
| מספר שלב | yes | links tasks to the stage; **not stored** | unique on the sheet |
| שם | yes | title | ≤ 200 |
| תאריך | yes | date | one of the event's days |
| שעת התחלה | no | start time | |
| שעת סיום | no | end time | needs a start time; must be after it |
| דרישות מהמלון ולוגיסטיקה | no | requirements | ≤ 5000 |
| מיקום במלון | no | location in the hotel | ≤ 200 |
| הערות | no | notes | ≤ 5000 |
| אנשי קשר | no | contacts | see below |

Only `מספר שלב`, `שם` and `תאריך` are required headers. A missing optional
header just means that field is empty for every stage.

**Contacts cell.** Entries are split on `|` or a line break. Inside an entry, the three labels
`שם`, `טלפון` and `תפקיד` are each followed by `:`, with any spaces around it.
The labels may come in any order and each may appear at most once. A value
runs until the next label; a trailing comma is dropped. So commas and colons
inside a value are fine: `תפקיד: צייר קריקטורה (מהשעה 10:30)`.

- The name is required. Phone and role are optional.
- The phone is reduced to its digits and must then be a 10-digit number
  starting with `05`. It is stored as `05X-XXXXXXX`, the team-member format,
  the same as a phone typed in the stage form.
- Text before the first label, or an unknown label such as `מייל:`, is a
  problem.
- At most 30 contacts per stage. Name and role ≤ 100.

Example (from the sample file):
`שם: הלל, טלפון: 0522010344, תפקיד: צייר קריקטורה (מהשעה 10:30) | שם:יוכי, טלפון: 050-628-5016, תפקיד: ביטוח לאומי`

### Sheet משימות — one row per task

| Header | Required | Maps to | Rules |
|---|---|---|---|
| מספר שלב | yes | the task's stage | must be a stage number on שלבים |
| משימה | yes | title | ≤ 200 |
| תיאור | no | description | ≤ 5000 (**new**) |
| אחראי/ים | no | assignees | names split on `\|`; see below |
| שעת התייצבות | no | assembly time | |
| תתי משימות | no | subtasks | split on `\|`; ≤ 50, each ≤ 200 |

Required headers: `מספר שלב`, `משימה`. The sheet may have no task rows.

**Assignee names.** Candidates are only the members assigned to the event, the
same list as the task form's dropdown. Each name is compared after removing
invisible characters, collapsing spaces and applying the app's search
normalisation:

1. If exactly one candidate's full name equals it, that member is chosen.
2. Otherwise, a candidate matches when **every word** of the written name is a
   whole word of the candidate's name. `בועז` matches `בועז כהן` but not
   `בועזי לוי`.
3. **Exactly one** match is chosen. **None** is a problem ("לא משובץ
   לאירוע"). **Several** is a problem that names them, e.g. "תואם כמה משובצים:
   בועז כהן, בועז לוי".

The same member named twice in one cell is kept once.

## The flow

1. **Pick.** Pressing **ייבוא מאקסל** opens the browser's file picker
   (`.xlsx`). Cancelling does nothing.
2. **Parse.** The file is parsed in the browser. A short spinner shows while
   it reads. A file that is not a readable `.xlsx`, or is over 5 MB, is one
   problem: "הקובץ אינו קובץ אקסל תקין".
3. **Preview dialog.**
   - **With problems:** a title like "נמצאו 3 בעיות בקובץ" over the full list,
     each line naming the sheet, the row and what is wrong, e.g.
     - `שלבים, שורה 4: התאריך 16/06/2026 אינו מתאריכי האירוע`
     - `משימות, שורה 7: מספר שלב 9 לא קיים בגיליון שלבים`
     - `משימות, שורה 4: "בועז" תואם כמה משובצים: בועז כהן, בועז לוי`

     **ייבוא** is disabled. **בחירת קובץ אחר** picks again; **סגירה** closes.
   - **Clean:** a summary "N שלבים · M משימות · K אנשי קשר", then each stage
     in screen order (day, time, title) with its task count. **ייבוא** and
     **ביטול**.
4. **Import.** **ייבוא** shows a spinner until the backend answers. On success
   the dialog closes and a snackbar says "יובאו N שלבים ו-M משימות". The new
   stages arrive through the live stream like any other change. On failure
   the dialog stays open with the backend's message, and **ייבוא** can be
   pressed again (same ids, so a retry cannot duplicate).

The member list used for matching is read live when the dialog opens. If it
fails to load, the preview says so and offers no import.

## Template

**הורדת תבנית** downloads `תבנית משימות דו יומי.xlsx`, built in the app with
the `excel` package:

- The two sheets, right-to-left, with exactly the headers above in the order
  above.
- **One example row** on each sheet, with a made-up contact, phone and
  assignee. Its example date is the event's first day.
- Imported as is, it fails only on the made-up assignee, which is not
  assigned to the event. That shows the person what a problem looks like.

## Backend: `stage.import`

A new action, so deployed clients are unaffected (backward-compatible). It
needs a Functions deploy before the client is tested.

Payload:

```json
{
  "eventId": "<id>",
  "stages": [
    {
      "stage": { /* exactly what stage.insert takes, with its id */ },
      "tasks": [ { /* exactly what task.insert takes, with its id */ } ]
    }
  ]
}
```

Rules:

- Caller must be a task manager (`requireTaskManager`).
- 1–60 stages, 0–400 tasks in total; otherwise 400.
- Every stage's `eventId` equals `eventId`. Every task's `eventId` equals
  `eventId` and its `stageId` equals its stage's `id`. Ids are unique within
  the payload. Otherwise 400.
- One transaction:
  1. `readWritableEventDaysInTransaction` for the event (it exists, is
     writable, and gives its days).
  2. Query `stages` where `eventId == eventId`, limit 1. If anything is found:
     409 "לאירוע כבר יש שלבים. ייבוא אפשרי רק לאירוע ללא שלבים." This covers
     two managers importing at once. **Except a replay:** the client retries
     a request that timed out, so if the payload's first stage id already
     exists in this event, the import already happened. The action returns
     `{ok: true, stageCount, taskCount}` without writing anything.
  3. Build every stage with `buildNewStage` and every task with
     `buildNewTask`: the same validation as the single creates.
  4. `transaction.create` each one. An id that already exists fails the
     whole transaction.
- One audit-log entry: entity `event`, id `eventId`, details `{stageCount,
  taskCount}`. No per-document entries.
- Returns `{ok: true, stageCount, taskCount}`.

The backend does not check the assignees against the event, the same as
`task.insert`; the client does.

## Client structure

- **`lib/core/utils/task_import/`** (pure Dart, no Flutter):
  - `task_import_parser.dart`: workbook bytes + event days + candidate
    members → `TaskImportResult`, which is either `problems: List<ImportProblem>`
    or a list of `ImportedStage` (a `Stage` plus its `TaskItem`s, ids already
    chosen).
  - `contact_cell_parser.dart`, `cell_values.dart` (dates, times, numbers,
    invisible characters), `assignee_matcher.dart`, each with its own tests.
  - `task_import_template.dart`: builds the template bytes.
- **Data**: `DatabaseInterface.importStages(String eventId,
  List<ImportedStage>)`, implemented in `FirestoreDatabase` through the
  backend API and passed through `LoggingDatabase`; `TaskRepository.importStages`.
- **Bloc**: `ImportStages(eventId, stages, completion)` on `TaskBloc`,
  reporting through the completer like the other mutations.
- **UI**: `widgets/task_import_dialog.dart` (preview and import), the two
  buttons in the event screen's empty state, file picking and downloading
  through `package:web` behind a small interface, so tests can fake it.

## Testing

- **Parser unit tests**, the bulk, on workbooks built in the test with the
  `excel` package:
  - headers in any order, with a colon, with invisible characters;
  - skipped rows;
  - every value form of dates and times;
  - every problem message;
  - the contacts cell, including a role holding a colon and a comma, and the
    sample file's phone forms;
  - name matching: exact, unique partial, none, several, a duplicate;
  - the caps.
- **Template round-trip**: the template parses with exactly one stage and one
  task, with only the expected assignee problem.
- **The sample file**: parsed once locally to confirm the reader handles a
  real Excel-saved file. It is **not committed** because it holds real names
  and phones; a made-up fixture with the same shape is committed instead.
- **Backend tests**:
  - success;
  - an event that already has stages → 409;
  - the caps;
  - a mismatched `eventId` or `stageId` → 400;
  - a non-manager → 403;
  - an invalid stage or task inside → nothing written.
- **Widget tests**:
  - the buttons appear only for a manager on an event without stages;
  - the preview lists problems and disables import;
  - a clean preview imports, shows a spinner, closes, and shows the snackbar;
  - a backend failure keeps the dialog open.

## Out of scope

- Importing into an event that already has stages, merging, or updating from
  a file.
- Exporting existing stages and tasks to Excel.
- `.xls` or `.csv` files.
- A stage number stored in the app.

## Risks

- **The `excel` package and real files.** Checked on 2026-10-15: `excel`
  4.0.6 reads the sample file cleanly with typed cells (`IntCellValue`,
  `DateCellValue`, `TimeCellValue`, multi-line text). It reports 1000 rows for
  the sheet, mostly empty, which the empty-row rule handles.
- **Name matching depends on how names are typed in the system.** A problem
  list that names the candidates keeps this fixable from the file side.
