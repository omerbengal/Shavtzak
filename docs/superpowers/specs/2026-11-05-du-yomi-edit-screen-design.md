# דו יומי — managers' editing screen ("מסך עריכה")

Date: 2026-11-05 · Worktree: `.claude/worktrees/du-yomi-edit-screen`
Mockups (brainstorm, not committed): `.superpowers/brainstorm/59535-1793869512/content/full-screen-v3.html` (option A),
`stage-edit-states.html`, `editing-stage-subtasks.html`, `mobile-v2.html`.

## Why

Managers of a דו יומי keep downloading the event to Excel ("הורדה לאקסל"), editing it, and
uploading it back ("עדכון מאקסל"). They do it for two things the app does not give them:

1. **One flat view** of every task, in order, grouped by stage, with *all* of a task's
   details (time, title, description, assignees, subtasks) and *all* of a stage's details
   visible at once, without tapping into anything.
2. **Editing in that view**: rewording, swapping assignees, changing times, adding and
   deleting tasks, moving tasks between stages, editing stage details.

The new screen replaces that round trip.

## Goals

- One screen per דו יומי event, for managers only (`canManageTasks`: admins + `canManageTasks` members).
- Laptop first (window ≥ 1000 px), and a phone layout of the same screen.
- Every stage detail and every task detail visible in the list.
- Click (laptop) / tap (phone) a single value to edit it; each change **saves immediately**
  through the existing backend calls and reaches everyone live.
- Add task, add stage, delete task, delete stage, move a task to another stage.

## Non-goals / anti-goals

- **Not a progress screen.** No ticks, no progress bars, no done counts, no late/soon colours,
  no strike-through. (User was explicit: "this is not a visual screen to see progress".)
- No staged "שמירה" for the whole screen (user chose save-immediately).
- No manual ordering within a stage: tasks inside a stage stay sorted by due time (assembly
  time), as everywhere else. The ⋮⋮ handle only moves a task to another stage.
- Existing tabs ("המשימות שלי", "כל השלבים") are untouched.
- Does not replace the Excel import/update features; "הורדה לאקסל" stays reachable.

## Decided with the user

- **Look: "soft cards" (option A).** Light grey page; each stage is a white rounded card with a
  blue edge (inline-end... visually the right edge in RTL) and soft shadow, in stage order
  (the order `eventTaskBoard` already gives). App blue `#2196F3`, Rubik font.
- **Stage card heading** shows every stage field, always visible (no "פרטי השלב" button):
  - line 1: title · 📅 day · 🕘 start–end · "🗑 מחיקת השלב" at the far (left) end;
  - below: two-column label/value grid: מיקום (hotelLocation), הערות (notes),
    דרישות (requirements), אנשי קשר (contacts, as chips `name · role · phone`, plus "+ איש קשר").
  - Empty values show a faint placeholder ("הוספת הערה") that is itself clickable.
- **Laptop task table** under each heading: columns `⋮⋮ | התייצבות | משימה | תיאור | אחראים | תת-משימות | 🗑`.
  Assignees as coloured initial circles + first names (option A style). Subtasks as their list
  (bullets), not counts. "+ משימה" at the bottom of each card.
- **Phone:** the same cards stacked; each task is a small card showing time, title, description,
  assignee chips and subtask list; ⋯ on the task opens a bottom sheet with "העברה לשלב אחר…" and
  "מחיקה". Stage card heading shows title, day·times·location, notes; the requirements and contacts
  fold under "▾ עוד פרטים: …" (collapsed by default).
- **Editing = one value at a time**, on both layouts:
  - laptop: hover shows a light-blue background + ✎; click turns *only that value* into an editor in
    place; Enter or click outside = save, Esc = cancel. Multi-line editors (description, notes,
    requirements, subtasks) save on click-outside / Ctrl+Enter; Enter there adds a line.
  - phone: tap on a value opens a small bottom sheet with that one editor + "שמירה" / "ביטול".
    The user chose this over "tap the card to edit the whole task". Give values generous tap
    padding; a scroll is not a tap.
- **Editor per value:**
  - task title, stage title, location: one-line text; title cannot be empty (reverts + message).
  - description, notes, requirements: multi-line text. *(My call: requirements is a free-text
    string in the data, so it is edited as multi-line text, not as a list.)*
  - assembly time, stage start/end: the app's `EventTimeField` (typed HH:mm); can be cleared.
    Stage end must not be before start (same rule as `stage_form_modal`).
  - day: drop-down of the event's days only (`eventDays(event)`).
  - assignees: multi-select of the members assigned to the event
    (`TaskRepository.watchEventAssignees`), at least one required (backend rule).
  - subtasks: editable list — Enter adds a line under the current one, Backspace on an empty line
    removes it, ✕ deletes, ⋮⋮ reorders. Subtask ids are kept for renamed lines so their ticks survive
    (backend matches `isDone` by id); new lines get a new uuid.
  - contacts: a chip opens into name / phone / role boxes (phone formatter + validators as in
    `stage_form_modal`); ✕ removes; "+ איש קשר" adds.
- **Save immediately**: each committed value sends one `UpdateTask` / `UpdateStage` through
  `TaskBloc` with a full entity (`copyWith`). Failure → red snackbar with the backend message and
  the cell shows the stored value again (it never stays showing an unsaved value).
- **Deletes ask first** (existing `deleteTask` / `deleteStage` confirm dialogs, which already say a
  stage delete takes its tasks).
- **Entry**: an "עריכה" button for managers on the event screen, next to the existing "אקסל" menu
  button in the "כל השלבים" summary, on every window size. Route: the event route + `/edit`
  (`/du-yomi/<id>/edit`, `/user/du-yomi/<id>/edit`, and `/test/...` mirrors). A non-manager who
  opens the URL gets "אין הרשאה" with a way back. The app bar: back arrow to the event screen,
  title "עריכה · <event name>", days below.
- **Toolbar** (under the app bar): search box (task title / description / assignee name / stage
  title — reuse the filter logic the tasks screens already use if it fits), assignee filter
  drop-down ("אחראי: כולם"), "⬇ אקסל" (existing `downloadExport`), "+ שלב חדש" (primary).
  A stage card with no visible task after filtering is hidden while a filter is on.

## Decided by me (builder may revisit with reason)

- **New task / new stage use the existing forms** (`createTask` / `createStage` in
  `TaskScreenActions`), not an inline empty row: the backend refuses a task without an assignee,
  so a name-only row could never save. "+ משימה" opens the task form pre-set to that stage.
- **Moving a task between stages**
  - laptop: drag the row's ⋮⋮ onto another stage card (the card highlights as a drop target);
    also "העברה לשלב אחר…" in a small ⋯ / context menu on the row, which lists the event's other
    stages. Phone: the ⋯ sheet only.
  - Sends `UpdateTask` with the new `stageId`. The task keeps its assembly time.
  - **Backend change** (`functions/src/index.ts` `task.update`): pass `{allowStageMove: true}` to
    `applyTaskEdit`, and when `next.stageId !== existing.stageId` call
    `requireStageOfEventInTransaction(transaction, collections, next.stageId, next.eventId)`
    inside the existing `beforeWrite` (reads before the write, as now). Backward compatible: old
    clients never send a different stageId. Tests in `functions/src` for: move OK, move to a
    stage of another event refused, move to a missing stage refused.
- **Edits racing the stream**: two quick edits to the same task before the first comes back on
  the stream must not undo each other. The screen keeps a per-task/per-stage "last sent" overlay:
  the next edit is built on the overlay version if present; an overlay entry is dropped once the
  stream delivers the entity with the same editable fields (or on failure). Two *different*
  managers editing the same task at the same time: last write wins (same as today's form).
- An open editor is not disturbed by stream updates to other rows; if the edited entity itself
  changes from elsewhere while open, the editor keeps the user's text (they will overwrite on save).
- **Layout breakpoint**: same 1000 px as the existing wide layout (`TaskStyle` has it — reuse
  the constant). Content max width ~1280 px, centred.
- All sizes/colours for this screen go in a new section of `task_style.dart` (house rule: every
  size and colour of the tasks screens is there).
- **Order after an edit**: rows and cards re-sort from the live data right away (this is an
  editing screen; the new place is the correct result). The item just edited is scrolled into view
  and briefly highlighted so it is not lost. No `RowHold` here.
- **Resume**: `/edit` is not a place the tab reopens to; leaving and coming back lands on the
  event screen (`TasksResume` unchanged).
- **"אחראי" filter** lists the event's current assignees plus anyone named on a task of the event
  (so tasks still held by someone taken off the event can be found).
- **Row actions**: each task row/card has a ⋯ menu ("העברה לשלב אחר…", "מחיקה") on both layouts,
  instead of a separate 🗑 column; the laptop row also has the ⋮⋮ drag handle.
- The removed-assignee check ("assignee taken off the event") is out of scope for v1.
- An event with no stages: the screen shows the empty card state with "+ שלב חדש" (the Excel
  import stays on the event screen).

## Constraints

- Flutter web, Hebrew, RTL everywhere, `flutter analyze` with zero *new* issues (≈107 pre-existing infos).
- Real-time: the screen renders from `TaskBloc` `TasksLoaded` (already live via `watchBoard`),
  `LoadTasks` on open (ignored if live). Equatable props on any new state/view model hold full objects.
- Every mutation through `TaskBloc` events with a `CrudActionCompleter` (as `TaskScreenActions`).
- Functions do not auto-deploy: the stage-move change must be deployed
  (`firebase deploy --only functions`, verify with `firebase functions:list`) before the user tests
  moving tasks locally. Everything else works on the deployed backend as is.
- Tests: Functions unit tests for the move; Flutter widget tests for the edit screen (render all
  fields, one inline edit dispatching `UpdateTask` with the right entity, non-manager blocked,
  phone layout renders cards) and unit tests for any pure helpers (overlay merge, subtask list edit).

## Left to the builder

File/widget breakdown, the inline-editor widget design, keyboard details beyond the above,
exact copy of secondary labels, drag-and-drop implementation details.
