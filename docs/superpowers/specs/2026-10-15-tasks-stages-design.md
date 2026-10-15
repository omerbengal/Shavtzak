# דו יומי tasks: events and stages

**Date:** 2026-10-15
**Status:** approved in conversation, awaiting written-spec review
**Builds on:** `2026-10-11-du-yomi-tasks-design.md` and the follow-up round merged as `6740a71`

## Why

The team runs each דו יומי event as a sequence of stages (arrival, sessions,
dinner, departure). Today's `/tasks` screen is one flat list of tasks across
all events, each task picking its event. The organisation wants the event to
come first, its stages to be the main blocks, and tasks to live inside stages.

## What changes, in one paragraph

`/tasks` becomes a list of דו יומי events. Choosing one opens
`/tasks/<eventId>`: that event's screen, made of stages. A stage has a title,
one day of the event, an optional time or time range, hotel requirements and
logistics, a location in the hotel, notes and a list of contacts. Tasks sit
under a stage and no longer choose an event; their due date is replaced by an
optional assembly (התייצבות) time on the stage's day. Everything else about
tasks (subtasks, assignees, status note, ticking, permissions, "my tasks / all
tasks", search, per-tab filters) carries over into the event screen.

## Decisions (from the user, 2026-10-15)

| Topic | Decision |
|---|---|
| Stage identity | Automatic internal id, like every entity. People tell stages apart by title, date and location. |
| Stage title | Required free text. |
| Stage date | One day out of the event's days. Required. Validated to fall inside the event. |
| Stage time | Optional. A single time (`08:00`) or a range (`08:00–10:45`). |
| Stage contacts | A list; each contact has a name, a phone (tap-to-call) and an optional role. |
| Task date | Always the stage's date, shown greyed out, not editable. Moves with the stage. |
| Task התייצבות | Optional single time. Without it, the task never counts as "in the next half hour". |
| Task subtasks | Kept, as today. |
| Status colours / filters | Kept, measured from the task's due moment (below). |
| Stages under a filter | Only stages with at least one matching task show, except "all tasks" with no search and no filter, which shows every stage including empty ones. |
| Event list | Upcoming events first; past events in a collapsible "אירועים שעברו" section, closed by default, as on `/user/assignments`. |
| Stage layout | Title line always visible; stage details behind a "פרטי השלב" fold, closed by default; task list underneath with a "+" on its header. |
| Who manages stages | The same people who manage tasks: admins and members with `canManageTasks`. |
| Deleting a stage | Warns, then deletes the stage and its tasks. |
| Existing tasks | Test data only. The user deletes them before the deploy; no migration. |

## Rules

**A task's due moment.** The stage's date at the task's התייצבות time, or the
end of that day (23:59) when the task has no time. This replaces `dueAt` in
every rule that used it:

- *overdue* (באיחור): unfinished and the due moment has passed;
- *due today* (להיום): unfinished, due moment still ahead, on today's date;
- *open* (פתוחה) in the filter: unfinished and the due moment has not passed
  (takes in "due today", as decided on 2026-10-12);
- *completed* (הושלמה): ticked, whatever the time.

**"התייצבות בחצי שעה הקרובה"** replaces "משימות לחצי שעה הקרובה": unfinished
tasks **that have a התייצבות time** due between now and now + 30 minutes, both
ends included. A task with no time never matches.

**Stage order.** By date, then start time (stages without a time first on
their day), then title.

**Task order inside a stage.** As today: overdue, due today, open, completed;
by due moment, then title.

## Screens

### `/tasks` — the event list

- Lists active (not deactivated) events of the "דו יומי" category
  (`duYomiCategoryId`). The category filter that the task form used moves here.
- Two sections, styled after `/user/assignments`:
  - **אירועים קרובים** with a count: events that have not ended, nearest first;
  - **אירועים שעברו** with a count: collapsible, closed by default, most recent first.
- Each row: event name; its date or date range; location; and a summary line,
  e.g. "3 שלבים · 12 משימות פתוחות · 2 שלך".
- Pressing a row opens `/tasks/<eventId>`. The home button and test-environment
  banner stay as they are on today's screen.
- Still link-only: nothing elsewhere in the app links here.

### `/tasks/<eventId>` — the event screen

- **Header:** back arrow to `/tasks`; the event's name; its dates; its location.
- **Below the header,** unchanged in behaviour from today: the
  "המשימות שלי / כל המשימות" tabs, the search field, the filter button with its
  badge.
- **Stages**, in stage order, each as a card:

  ```
  ┌───────────────────────────────────────────┐
  │ ✎ 🗑   קליטה ורישום                       │
  │ 21/10 · 08:00–10:45 · לובי המלון          │
  │ ───────────────────────────────────────── │
  │ ▸ פרטי השלב                               │  ← fold, closed by default
  │ ───────────────────────────────────────── │
  │ משימות (2/5)                       [ + ]  │
  │   task cards, as today                    │
  └───────────────────────────────────────────┘
  ```

  - The pencil and bin are shown to managers only.
  - The "פרטי השלב" fold holds the hotel requirements and logistics, notes,
    and the contacts. Each contact shows name, role and a phone link (`tel:`).
    Empty fields are left out; a stage with no details shows no fold.
  - "משימות (done/total)" counts all the stage's tasks, not only the visible ones.
  - The "+" is shown to managers only and opens the task form for that stage.
  - Task cards are today's cards, minus the event line (the event is the page).
- **"שלב חדש"** button for managers (the floating button that says "משימה
  חדשה" today).
- Which stages show: see the rule in the decisions table.
- Empty states:
  - no stages at all: "אין עדיין שלבים לאירוע זה" (managers: plus a hint to add one);
  - stages exist but nothing matches: today's "לא נמצאו משימות תואמות".
- An event id that is unknown, deactivated or not a דו יומי event: a short
  message and a button back to `/tasks`.
- Sign-in from a link returns the member to `/tasks/<eventId>`
  (`AppRouter.postAuthDestination` extended), as it already does for `/tasks`.

### Filter (per tab, as today)

- "התייצבות בחצי שעה הקרובה" on top (replaces the old half-hour option).
- Status section: unchanged.
- **Event section removed.**
- Assignee section: under "כל המשימות" only, as today; it offers the assignees
  of this event's tasks.
- Filters live on the event screen and start empty each time an event is opened.

## Forms

All forms keep today's form behaviour: spinner on save until the backend
answers, failure shown in the form, save enabled for an edit only once
something changed, and a "שינויים לא נשמרו" prompt on cancel when there are
changes. All text fields carry the RTL caret fix.

### Stage form (new)

| Field | Rule |
|---|---|
| כותרת | Required, trimmed, up to 200 characters. |
| תאריך | Required. A dropdown of the event's days only. A one-day event pre-selects its day. |
| שעת התחלה | Optional `HH:mm`. |
| שעת סיום | Optional `HH:mm`. Allowed only with a start time, and must be after it. |
| דרישות מהמלון ולוגיסטיקה | Optional, multiline, up to 5000 characters. |
| מיקום במלון | Optional, up to 200 characters. |
| הערות | Optional, multiline, up to 5000 characters. |
| אנשי קשר | A list of rows, each: name (required on a row that has anything in it), phone (optional, digits and `+ - ( )` and spaces), role (optional). Add and remove rows. Blank rows are dropped on save. Up to 30. |

Editing a stage whose date no longer falls inside the event (the event was
moved) shows the date as invalid and requires a new one before saving.

### Task form (changed)

- **Removed:** the event dropdown and the due date picker.
- **Shown, read only:** the stage's title and date (greyed).
- **התייצבות:** optional single `HH:mm` time, using the existing numpad time field.
- **Unchanged:** title, description, assignees dropdown (members assigned to
  the event, live), subtasks.
- Because the event is fixed, the assignee dropdown is open-able from the start.

## Data

### New collection `stages` (`test_stages` in test mode)

| Field | Type | Notes |
|---|---|---|
| `eventId` | string | |
| `title` | string | |
| `date` | string `yyyy-MM-dd` | The Israel-local day. A plain string, so no time zone can shift it. |
| `startTime` | string `HH:mm` or null | |
| `endTime` | string `HH:mm` or null | Only with `startTime`, and after it. |
| `requirements` | string | Hotel requirements and logistics. Empty string when none. |
| `hotelLocation` | string | |
| `notes` | string | |
| `contacts` | array of `{id, name, phone, role}` | `phone` and `role` may be empty strings. |
| `createdAt`, `createdById`, `updatedAt` | | Stamped by the backend. |

### `tasks` (changed)

- **Added:** `stageId` (string, required). The stage must belong to the task's
  `eventId`. A task's stage is fixed at creation; an edit cannot move it.
- **Added:** `assemblyTime` (`HH:mm` or null).
- **Removed:** `dueAt`. The backend stops reading and writing it.
- `eventId` stays: it is what event deletion and loading use.

### Client

- Entities `Stage` and `StageContact` (Equatable, `copyWith`), model
  `StageModel`, `DatabaseInterface.watchStages()` and the stage mutations, with
  the logging wrapper.
- `TaskItem` gains `stageId` and `assemblyTime`, loses `dueAt`; a populated
  `stage` alongside the populated `event`.
- `TaskRepository.watchBoard()` combines tasks, stages, events and members
  (four live streams, as today with three). The event list and the event screen
  both read the one board; `TaskBloc` still holds one subscription, opened by
  whichever screen opens first.
- `TaskBloc` gains stage create, update and delete, reported through the
  completer like the task mutations. Optimistic ticking is unchanged.
- Pure helpers in `task_utils.dart` (with an injected `now`): the due moment,
  stage order, which stages show under a filter, the event list split and
  summary counts, and the event-day list for the stage form.

## Backend (`functions/`)

- `stage.insert`, `stage.update`: task managers only. Validate the fields as in
  the stage form table; the event must exist and be writable; `date` must be one
  of the event's Israel-local days (events store `startDate`/`endDate` as UTC
  instants of Israel midnight). Audit-logged like tasks.
- `stage.delete`: task managers only. Deletes the stage and all its tasks in one
  transaction, and audit-logs it with the number of tasks removed.
- `task.insert`: requires `stageId`; the stage must exist and share the task's
  `eventId`. `assemblyTime` validated as `HH:mm` or null.
- `task.update`: `stageId` cannot change; `assemblyTime` as above.
- `event.delete`: also deletes the event's stages (tasks are already removed).
- Pure stage functions in a new `functions/src/stages.ts`, unit-tested like
  `tasks.ts`.
- `firestore.rules`: `stages` readable by authorized prod users, `test_stages`
  by authorized test users, no client writes.

**Deploy order:** the user deletes the six existing test tasks; then
`firebase deploy --only functions,firestore:rules`; verify with
`firebase functions:list`; only then test the client locally (local runs call
the deployed `api`). The web build ships on merge to `main`.

The new backend refuses a task without a stage, so the currently deployed web
client cannot create tasks between the backend deploy and the web deploy.
Acceptable: the screen is link-only and its data is test data.

## Out of scope

- Task leaders with people under them (the boss's "עתידית אולי").
- Moving a task to another stage.
- Reordering stages by hand (they order by date and time).
- Any link to the tasks screen from elsewhere in the app.

## Testing

- **Backend** (`npm test`): stage field validation; date-inside-event for one-
  and multi-day events across the UTC/Israel boundary; time range rules;
  stage delete takes its tasks; task insert with a missing, foreign or other
  event's stage; task update cannot move stages.
- **Flutter** (`flutter test`):
  - helpers: due moment with and without time; statuses and "פתוחה" from it;
    the half-hour assembly filter including the no-time case; stage order; which
    stages show per tab, search and filter; event list split and counts; event days;
  - repository and bloc: the four-stream board; stage mutations; ticking unchanged;
  - widgets: event list (sections, counts, opening an event); event screen
    (header, stages, fold, "+", tabs, filter without events, empty states,
    unknown event); stage form (required fields, date choices, time range rules,
    contacts rows, discard and save behaviour); task form (no event picker,
    greyed date, assembly time);
  - router: `/tasks/<eventId>` deep link and return after sign-in.
- `flutter analyze` adds nothing to the 107 baseline.
