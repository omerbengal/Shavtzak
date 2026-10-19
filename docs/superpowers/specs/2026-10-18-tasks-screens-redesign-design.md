# דו יומי tasks: screens redesign

**Date:** 2026-10-18
**Status:** agreed in conversation; written design awaiting the user's review
**Builds on:** `2026-10-15-tasks-stages-design.md`, `2026-10-15-tasks-excel-import-design.md`, main at `5a0f804`
**Mockups:** `2026-10-18-tasks-screens-redesign/` next to this file (static HTML with made-up data; open in a browser)

## Why

The tasks screens are used for the first time this week. Today the event screen is
a list of folded stage cards holding tall task cards: to learn what is missing, who
is late or what comes next, you open stage after stage and scroll. The user wants
the screens to be excellent at taking in information quickly, for two kinds of
people:

- **Team members**, on their phone during the event, to see what is theirs and when.
- **Managers** (admins and members with `canManageTasks`): before the event on a
  computer, mostly observing the plan and making some last-minute fixes; during the
  event, following how every stage is doing.

## What changes, in one paragraph

`/tasks` opens straight into the nearest דו יומי event that has not ended; the list,
one step back, shows only events. The event screen has two tabs. **"כל השלבים"** is
a day calendar of the stages on a real time axis with a live "now" line; every
stage shows how much of it is done and a button with its missing count. Tapping a
stage opens a **low sheet** that leaves the calendar visible above it; the sheet is
where stages, filter results, search results and single tasks are read and acted
on. **"המשימות שלי"** is a timeline of the member's own tasks threaded through every
stage of the event, opening on the current stage. On a wide screen the calendar
shows the days side by side and the sheet becomes a side panel with the stage's
tasks in a table. The filter sheet gives way to a one-row filter bar and a search
that also matches people. Nothing changes in the backend or the data.

## Decisions (from the user, 2026-10-18)

| Topic | Decision |
|---|---|
| Who and where | Members use it on a phone during the event. One or two managers build and watch it from a computer beforehand. |
| Manager during the event | A real timeline of the stages, how much is done and missing in each stage, and one tap on a stage to see its missing tasks. |
| Stage timeline | A day calendar where a stage's height is its duration, one day at a time on a phone, with a live "now" line (mockup option B). The equal-height stage list (A) was rejected. |
| Quick view | A low sheet that keeps the calendar visible above it (Q1, "of course"). A quick view that hides the schedule is not acceptable. The compressed day strip (Q2) was rejected. |
| Member's main view | A timeline of tasks, not of stages: the current stage's open tasks that are theirs, with their report time; a glance at the next stage; a way to see all stages (past, current, future) and their tasks. |
| Countdown | No "how long until then" for tasks. |
| Place per task | None for now. The place belongs to the stage and shows once, on the stage. |
| Tasks without a report time | At the end of their stage, marked "ללא שעה" (proposed in answer to the user's question; accepted). |
| Stages without tasks | Normal (lunch, for example). They appear in members' timelines so members see the schedule. |
| Pre-event check | Only "a task whose assignee was taken off the event". No check for two tasks at the same time (members multitask), none for stages without tasks. |
| Events list | Only events: no task counts, no progress. Every event: all future ones and the past ones. |
| Filters | The two filters stay, as toggles that clearly read as filters. The half-hour one is labelled "התייצבות בחצי שעה הקרובה". **The filter bar is one row, always**: shrink the text if needed, never wrap. |
| Later changes | The user expects to change details after seeing the result on a phone and a computer. |

## The design

### 1. Events list: `/tasks`

- **Opening `/tasks` goes straight to an event**: the nearest active דו יומי event
  that has not ended (`taskEvents(...).upcoming.first`). The list shows only when
  there is no such event, or when the member comes back from an event with the back
  arrow, and coming back must never bounce into the event again. The same holds
  after sign-in, when `AppRouter.postAuthDestination` restores `/tasks`.
- The list has "אירועים קרובים" with every upcoming event, nearest first, and
  "אירועים שעברו", folded by default, latest first. Each event shows its name, its
  weekday range and dates ("שלישי–רביעי, 20–21/10") and its place. The event under
  way carries a "מתקיים עכשיו" pill. No task counts or progress on this screen.
- The home button, loading and error states stay as today.
- Mockup: `4-events-list-and-filters.html`, phone L1.

### 2. Event screen frame: `/tasks/<eventId>`

- App bar: the event name, the back arrow on the far left (as today) and a search
  icon beside it. Search works from either tab and shows its results in the sheet.
- Tabs: "המשימות שלי" | "כל השלבים". Managers land on "כל השלבים", everyone else on
  "המשימות שלי". Both tabs are open to everyone.
- "כל השלבים" carries, above the calendar:
  - **Summary**: dates and place, the event's progress bar, "X/Y הושלמו".
  - **Filter bar, one row**: a filter icon and "סינון:", then two toggles,
    "באיחור (n)" and "התייצבות בחצי שעה הקרובה (n)". A toggle that is on fills in
    and shows a tick.
  - **Assignee check**, for managers only and only when something needs fixing: one
    red line, "N משימות של מי שכבר לא משובץ לאירוע". Tapping it lists those tasks in
    the sheet.
- The once-a-minute ticker stays: colours, "now" and the current stage move with
  time, not only with data.

### 3. "כל השלבים": the day calendar

- One day at a time, with a tab per day of `eventDays(event)`. During the event it
  opens on today, otherwise on the first day.
- Hour labels on the right, stages as blocks placed by start and end time, and a red
  "now" line with the time, on today only.
- Each block shows its title; its place and time range when tall enough; a thin
  progress bar when tall enough; and at its end a **count button**:
  - every task done: a green tick with "n/n";
  - otherwise "N חסרות" ("1 חסרה"), N being the tasks not done: red when any of them
    is late, orange when none is late but one is due in the next half hour, neutral
    otherwise;
  - a stage with no tasks has no button.
- Done stages are tinted green and the current stage blue; a stage holding a late
  task gets a red edge.
- A stage where the viewer has tasks carries a small blue person badge with their
  count (managers may have tasks too).
- Tapping the count button opens the sheet on that stage's missing tasks; tapping
  the block anywhere else opens it on all of the stage's tasks.
- Managers keep the "שלב חדש" floating button on this tab. An event with no stages
  keeps today's empty state, including "ייבוא מאקסל" and "הורדת תבנית" for managers.
- Mockups: `1-manager-calendar-and-quick-view.html` (Q1) and `2-member-view.html` (M2).

### 4. The low sheet (phones)

The one place where details are read and acted on.

- It opens low, about half the screen, **with no dark overlay**: the calendar stays
  readable and tappable above it, scrolled so the stage sits just above the sheet,
  the stage outlined and the other blocks faded. Tapping another stage, count
  button, filter or the assignee check replaces the sheet's content without closing
  it. Dragging up makes it taller; dragging down or the X closes it.
- It shows one of:
  - **A stage**: title, day, time range and place, with edit and delete for
    managers; its notes, hotel requirements and contacts with call buttons; a switch
    "חסרות (n) | הכל (m)"; then its tasks. Managers add a task from here.
  - **Filter results**: "באיחור · N משימות" (the longest overdue first) or
    "התייצבות בחצי שעה הקרובה · N" (the soonest first), from every stage, grouped by
    stage. The calendar outlines the stages they are in.
  - **Search or assignee-check results**: the same layout, grouped by stage.
  - **One task** (tap a row): title, stage and report time, status, assignees with
    call buttons, description, subtasks (tickable for whoever may), the shared update
    note with its author and time and the "הוספת עדכון" / "עדכון" action, and the last
    update time. Managers get edit and delete. A back arrow returns to the list it
    came from.
- A task row has a tick box (for whoever may tick it), the title, a status mark (red
  "באיחור"; the half-hour window shows as orange on the report time, never as a
  countdown), the report time or "ללא שעה", the subtask count, assignee chips with a
  call button when the member has a phone number, and the latest update line. Rows
  sort by report time with untimed ones last, and ticking never moves a row.

### 5. "המשימות שלי": the member's timeline

- A time-ordered list, **not** a calendar: a task has a report time but no duration,
  and some have no time at all.
- Every stage of the event appears, in stage order, under sticky day headers. A
  stage with nothing of the viewer's is one line (title, time, place, "אין לך
  משימות"). The viewer's tasks sit under their stage, each with its report time and
  the caption "התייצבות" in a time column on the right, or "ללא שעה".
- **It opens on the current stage.** Earlier stages fold into one line ("N שלבים
  קודמים · M משימות שלך הושלמו") that opens on tap.
- The current stage is highlighted with "עכשיו" and "N פתוחות שלך". Its tasks are
  full rows: a tick box, or the subtasks tickable inline when it has them, the title
  and "עם ..." for the other assignees. Done tasks stay in their place, struck
  through.
- The next stage carries the caption "השלב הבא". Its tasks and those of later stages
  are compact rows.
- The place shows once, on the stage. No countdowns, and no "להיום" chip (all of
  today is today); only late is coloured.
- **The viewer's late tasks, from any stage, are pinned in a red banner on top** until
  ticked. The banner is always one line, so the current stage stays on screen: with
  one late task it names the task, its stage and time, and opens the task; with
  several it reads "N משימות שלך באיחור" and opens them in the sheet, laid out like
  filter results.
- A task without a report time comes last in its stage, marked "ללא שעה". It turns
  late only when its day is over, as today.
- Tapping a task opens it in the sheet; tapping a stage line opens the stage there.
- A member with no tasks in the event sees a short note on top pointing to "כל
  השלבים", above the stage lines.
- No filter bar on this tab.
- Mockup: `2-member-view.html`, phone M1.

### 6. Wide screens (computer)

- "כל השלבים": the calendar on the right shows the event's days side by side. The
  sheet becomes a **panel on the left** for the clicked stage: a header with edit and
  delete; notes, hotel requirements and contacts side by side; the same
  "חסרות | הכל" switch as the sheet; and the tasks as a table (report time, task and
  description, assignees, subtasks), sorted by report time with untimed ones last.
  A table row carries everything a phone row does, laid out as columns: the tick box
  for whoever may tick, the late mark and the orange report time, and the latest
  update line under the task. Each row's pencil and bin appear on hover, and
  "משימה חדשה" sits above the table. The clicked stage stays outlined. Filter, search
  and assignee-check results and single tasks use the same panel.
- The wide layout follows the window's width, not the role: a member on a laptop or a
  tablet held sideways gets it too, and ticks their tasks in the table.
- The summary, the filter bar and the assignee check sit in a toolbar above. The check
  reads "לבדיקה: N משימות של מי שכבר לא משובץ לאירוע", and on the flagged task's row
  the removed assignee is struck through in red with "כבר לא משובץ לאירוע".
- "המשימות שלי" and the events list keep their phone layout, centred at a readable
  width.
- Mockup: `3-manager-desktop.html`.

## Rules

- **Late** is `taskDueStatus(...) == TaskDueStatus.overdue`, unchanged. **In the next
  half hour** is unchanged too: unfinished, with a report time, due between now and
  30 minutes from now (`taskDueSoonWindow`).
- **Missing** means not complete.
- **Current stage**: the stage whose span contains now, today. A stage with only a
  start time spans from it until the next stage starts. A stage with no time is
  never current. For "המשימות שלי": between stages the next stage counts as current,
  before the event the first stage, after it the last.
- **Counts** include only tasks whose stage exists, as today.
- **Assignee check**: a task is flagged when any of its `assigneeIds` is not among the
  members currently assigned to its event. `TaskRepository.watchEventAssignees(eventId)`
  already gives that list, live. Managers only.
- **Search** matches a task's title, its description and the names of its assignees
  (today it matches title, description and event name).
- **Filters**: one at a time, so switching one on switches the other off. Each
  toggle's count is live; at zero the toggle is disabled.
- **Progress bars**: green done, red late, orange due in the next half hour, grey the
  rest. They fill from the left, as the stage header does today.
- Times, time ranges and "x/y" counts are always laid out left to right inside the
  Hebrew text.
- **Nothing moves under the reader**, in the spirit of the user's "ticking no longer
  moves a task" fix (`eb9bcda`). An open list keeps its rows while it is open: a row
  ticked in "חסרות", "באיחור" or search results stays where it is, struck through,
  until the person switches view or closes the sheet. Headers and toggle counts stay
  live. Time passing (a stage starting or ending) updates highlights and colours but
  never scrolls or re-folds an open list; "המשימות שלי" opens on the new current stage
  the next time the tab opens.

## My calls (please check them while reading)

1. `/tasks` opens the nearest event that has not ended, and the list is one step back.
2. Managers land on "כל השלבים", members on "המשימות שלי".
3. One filter at a time; a filter with nothing in it is disabled.
4. The count button reads "N חסרות" everywhere, coloured by the worst case; a done
   stage shows a green tick; a stage without tasks shows no button. The mockups vary
   this wording; this is the rule.
5. No countdown text anywhere, including the managers' sheet: the mockup's
   "בעוד 20 דק׳" becomes the report time in orange.
6. Tapping the count opens "חסרות"; tapping the block opens "הכל".
7. What the stage and task sheets contain (section 4), and that managers edit from
   there.
8. "המשימות שלי" has no filter bar.
9. The assignee check also appears on phones, for managers, only when there is
   something to fix.
10. A stage with no time goes in an all-day row above the hours; a stage with no end
    time gets a block of the smallest readable height; overlapping stages share the
    width side by side; the hour range fits the day's stages.
11. Search also matches people, which replaces the assignee filter.
12. On a computer, up to three days side by side; more than that falls back to day
    tabs.
13. Open lists hold still: a ticked row stays in place, struck through, until the view
    changes or closes, while counts stay live (Rules, "Nothing moves under the
    reader").
14. The computer's task table has the phone row's live parts (tick box, late and
    half-hour marks, update line) and the "חסרות | הכל" switch, and the wide layout
    follows window width, so members can use it too.
15. The late banner in "המשימות שלי" is always one line: the task itself when there is
    one, "N משימות שלך באיחור" opening a list when there are several.
16. Phone views are built first; if Thursday gets close, the wide layout is what waits.

## Non-goals

- A place per task.
- Checks for two tasks at the same time, or for stages without tasks.
- Countdowns.
- Any change to the backend, the Firestore rules, the data model or the Excel template.
- Notifications or reminders.
- Changing the stage form, the task form, the delete and update dialogs or the import
  dialog themselves. They are opened from new places.

## Anti-goals (a failure even if it works)

- On the calendar tab, any way of showing a stage's tasks that hides the schedule.
- A filter bar that wraps to a second line.
- Tasks jumping when ticked (fixed on 2026-10-18 in `eb9bcda`).
- A backend action with nothing on screen while it waits. Dialogs keep their spinner
  and ticks stay optimistic, as today.
- Times or ranges rendered reversed inside Hebrew text.

## Constraints

- Flutter web, Hebrew, right to left, Rubik and the existing `AppTheme` colours.
- Data stays live through `TaskBloc` streams. New states and view models compare full
  objects, as CLAUDE.md requires for Equatable props.
- Client-only: no Functions deploy. Merging to `main` deploys the web build.
- `flutter analyze` with no new issues. The task screen tests are rewritten for the
  new screens and the suite stays green (982 tests on 2026-10-15).
- The user will adjust sizes, colours and layout after trying it on real devices.
  Keep those values in one place and the screens built from small widgets, so each
  change is cheap.

## Delivery

- **The redesign must be live for the first event, on Thursday 2026-10-22** (the user,
  2026-10-18: "we have basically the entire week to perfect this"). Nobody uses the
  tasks screens before then.
- The user tests with a local `flutter run` and decides when to merge; merging to
  `main` deploys. Leave room before Thursday for at least one round of the user
  trying it on a phone and a computer and asking for changes.
- No merges while the event is running.
- If time runs short, the wide layout (section 6) is the part to cut: on a computer the
  phone layout then shows, centred. The phone views come first because they carry
  the event itself (my call).

## What carries over, what goes

- **Kept**: `TaskBloc`, including optimistic ticks and the completers; the pure rules
  in `task_utils.dart`; `stage_form_modal`, `task_form_modal`, `confirm_delete_dialog`,
  `assignee_update_dialog`, `task_import_dialog` and the template download;
  `AppRouter.postAuthDestination` and link-only access; the permissions
  (`canManageTasks`, `canUpdateTaskProgress`).
- **Replaced**: the layouts of `tasks_screen.dart` and `event_tasks_screen.dart`,
  `stage_card.dart` and `task_card.dart`.
- **Removed**: `task_filter_modal.dart` and the per-tab filter selections.

## Left to the builder

Exact sizes, the hour scale and the breakpoint; how the screen holds its state (open
sheet, selected stage, active filter, search); how back from an event avoids the
bounce (the pending-link pattern in `AppRouter` matches only bare `/tasks` paths, so a
query parameter would need care there); animation, kept short and subtle; widget
decomposition; the test approach (new rules belong in pure functions with an injected
clock, like today's).

## Mockups

In `2026-10-18-tasks-screens-redesign/`, static HTML with made-up names; "now" is
Tuesday 14:40 of a Tuesday–Wednesday event:

- `1-manager-calendar-and-quick-view.html`: the calendar with the low sheet (Q1,
  chosen). Q2 stays in the file for the record.
- `2-member-view.html`: M1 "המשימות שלי" and M2 "כל השלבים" as a member sees them.
- `3-manager-desktop.html`: the wide layout two days before the event.
- `4-events-list-and-filters.html`: L1 the events list and S1 the one-row filter bar.
