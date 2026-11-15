# משימות צוות — team tasks design

Date: 2026-11-15 · Worktree: `.claude/worktrees/team-tasks` · Branch: `team-tasks`
Status: decisions confirmed by Omer in Telegram (topic "Shavtzak", msgs 3070-3141); design approved
(msg 3141) with one addition (contacts). Not yet implemented.

## Why

The headquarters team (מטה) runs its ongoing work from an Excel sheet (`todo_list.xlsx`, 83 rows on
15/11/2026): columns #, אירוע, אחראי, משימה, דד ליין, פירוט, סטטוס. Everything is free text: the
"אירוע" column is mostly a category or a topic, not one event ("אירועי חנוכה" 34 rows, "נשות מג״דים"
16, "דו יומי מ״פ סמג״ד" 13, "כללי" 5); it already splits by typo ("נשות מג״דים" vs "נשות מגדים");
"סטטוס" is empty in every row and done is a green fill; "דד ליין" is filled in 6 rows, as a number
(15.11); "פירוט" is a dated update log ("0211 עדיין פתוח", "8/11 הבוט מוכן"); one row (#938) is a
meeting summary with 22 lines, each owned by a different person.

The דו יומי task screens already moved one event series from Excel into the app. This feature does the
same for the team's general tasks, reusing that structure: instead of a stage, a task belongs to an
event, a category or a topic; there is no timeline; every task has its own (optional) deadline.

## Goals

- One place in the app for every team task, with owners, subtasks, a deadline, a status and an update
  log, replacing the Excel sheet.
- Managers see and edit everything; any other team member sees only the tasks they own.
- Same look and building blocks as the דו יומי screens.

## Non-goals

- No Excel import or export. The team starts clean (Omer, msg 3132). A one-off load of the sheet into
  the database may be requested later, after Omer and the other admins have tested the feature; it is
  not part of this feature.
- No notifications or reminders.
- No change to the דו יומי tasks, screens or the `tasks` / `stages` collections.

## Anti-goals

- Two layers of owners on one task (Omer, msg 3103: "זה עושה בלאגן").
- A free-text topic per task that splits groups by spelling.

## Decisions

| # | Decision | Source |
|---|---|---|
| 1 | A task is linked to **an event, a category or a topic** (all three are needed). | Omer, msg 3087 |
| 2 | **Owners (אחראים) are team members only** (חבר צוות), with no tie to the event's assignments. | Omer, button `taskowner:member` |
| 3 | Progress is an **update log**: every update is kept with its date and author, newest first. | Omer, button `taskupd:log` |
| 4 | **Visibility**: admins and members with "ניהול משימות" (`canManageTasks`) see every task; any other team member sees only the tasks they own. | Omer, button `taskview:managers` |
| 5 | ~~A subtask has its own owner (one team member).~~ Replaced in round 2: **a subtask is a full task nested in its parent** (title, description, owners (one or more), contacts, deadline, the five statuses, its own update log); it has no link of its own (the parent's) and no subtasks. | Omer, msg 3103; round 2: msg 3199 + button `subfull:all` |
| 6 | A task **with subtasks has no owner of its own**: its owners are its subtasks' owners. A task without subtasks has owners as usual (one or more). Adding the first subtask to a task that has owners asks: "ליצור תתי-משימות ולהסיר את האחראים" or "להשאיר כמשימה אחת". Such a task reads "משימת אב" ("משימת אב חדשה" in the new-task form). | Omer, button `taskpar:union`; round 2: msg 3199 |
| 13 | **"המשימות שלי"** lists each subtask the viewer owns as its own row, with its parent's title above it and its own deadline and status; **"כל המשימות"** shows the parent with its subtasks nested under it. | Omer, round 2: button `submine:own` |
| 7 | **Topics** come from a managed list, like "ניהול קטגוריות"; a task picks one, with "נושא חדש" right from the task. | Omer, button `tasktopic:list` |
| 8 | **Statuses**: פתוחה, בטיפול, בוצעה, לא רלוונטי/בוטל, כפילות ("managers don't want to delete duplicates for good"). | Omer, msg 3124 |
| 9 | **Deadline**: optional, a date only. | Omer, button `taskdue:date` |
| 10 | **No import**: start clean. | Omer, msg 3132 |
| 11 | **Placement**: a new "משימות" card on the admin choice screen next to "דו יומי"; for team members a 4th bottom tab "משימות", shown only to a member who owns a task or has "ניהול משימות". | Omer, button `taskplace:separate` |
| 12 | **Contacts**: every task and every subtask can have contacts (שם, תפקיד/תיאור, טלפון), exactly like a דו יומי stage's contacts. | Omer, msg 3141 |

Proposals Omer saw in the design key points (msg 3139) and approved:

- A task has **one link** (event, category or topic). Filtering by a category also shows the tasks
  linked to events of that category.
- "כפילות" **points to the original task**. "לא רלוונטי/בוטל" and "כפילות" are **hidden by default**
  and shown through the status filter.
- "באיחור" is **derived**, not a status: deadline before today and status פתוחה or בטיפול.
- When **every subtask is ticked** the task moves to בוצעה by itself.
- An **owner** may change the task's status, tick their own subtasks and write in the log; everything
  else is edited by managers.
- Team tasks get **their own collection**; the דו יומי UI pieces are shared, not copied.

## Approaches

1. **Generalize the `tasks` collection** (stage optional, new fields beside the old ones). Rejected:
   a דו יומי task's due moment, single overwritten note, done flag, fixed `stageId` and the
   assignees-must-be-assigned rule differ from team tasks in almost every field; one collection would
   tangle both rule sets, the backend checks and the Excel import/sync code.
2. **Revive the unmerged May 2026 `feat/tasks-feature` branch** (it had general tasks, statuses and an
   update history). Rejected: hundreds of commits behind `main` (387 already on 11/10), built before the דו יומי screens; its ideas
   are reused, its code is not.
3. **New collection, shared building blocks** (chosen): a `teamTasks` collection with its own backend
   endpoints, and the דו יומי widgets (subtask rows, assignee picker and chips, contact rows with tap to
   call, in-place value editors, optimistic ticks, `RowHold`) extracted where needed so both features use
   them.

## Data

`teamTasks` (`test_teamTasks` in test mode), one document per task:

- `title`, `description`
- `link`: `{type: 'event' | 'category' | 'topic', id}` or null (shown under "ללא שיוך")
- `assigneeIds`: team member ids, used only when the task has no subtasks
- `subtasks`: `[{id, title, description, assigneeIds, contacts, deadline, status, duplicateOfId,
  updates, completedAt}]` (round 2; a stored subtask from before it, `{isDone, assigneeId}`, still
  reads). A subtask's `duplicateOfId` is a sister subtask or another task. Its status, log and
  completion change only through `teamTask.setStatus` / `teamTask.addUpdate` with `subtaskId`
  (a manager or one of the subtask's owners); `teamTask.update` carries only its editable fields.
- `contacts`: `[{id, name, role, phone}]` (same shape as `StageContact`)
- `deadline`: `yyyy-MM-dd` or null
- `status`: `open | inProgress | done | cancelled | duplicate`; `duplicateOfId` when `duplicate`
- `updates`: `[{id, text, at, byId, byName}]` (the log; newest first on screen)
- `ownerIds`: derived and stored on every write = `assigneeIds` when there are no subtasks, else the
  distinct owners of all its subtasks. Used by the read rule and the "my tasks" query.
- `completedAt`, `createdAt`, `createdById`, `updatedAt`

Topics: a managed list in the same place and shape as the categories / `EventItems` lists
(`{id, name, sortOrder, isArchived}`), managed in "ניהול נושאים". An archived topic stays on its tasks.

Rules: `teamTasks` reads are allowed to a manager (admin or `canManageTasks`) or when
`request.auth.uid in resource.data.ownerIds` (the existing rules already treat `request.auth.uid` as the team member id, see `isAuthorizedProdUser`; the builder confirms this before relying on it); writes only
through the backend, as for every other collection. A non-manager's screen queries
`ownerIds array-contains <me>`.

## Screens

1. **Entry**: admin choice screen gets a "משימות" card next to "דו יומי" (route `/team-tasks`,
   `/test/team-tasks`). The member shell gets a 4th tab "משימות" (`/user/team-tasks`), present only when
   the member owns a visible task or has "ניהול משימות".
2. **Tasks list**: two tabs, "המשימות שלי" and (managers only) "כל המשימות". Tasks grouped by link
   (an event, a category, a topic, "ללא שיוך"), groups by their nearest deadline, tasks inside a group by
   deadline (none last), done at the bottom. Each row: status chip, title, deadline (red when late),
   owner chips, subtask progress (3/5). A one-row filter bar: status (default: all but בוטל/כפילות),
   owner, link. Managers: "+ משימה חדשה" and a ⋯ menu with "ניהול נושאים".
3. **Task screen** (bottom sheet on a phone, centred panel on a wide window, as in דו יומי): link,
   status (owners and managers change it), deadline, description, owners, contacts (tap = call, as in a
   stage), subtasks (tick, owner chip, the subtask's own contacts), then the update log with a "+ עדכון"
   box. A manager edits every value in place, saved at once (the דו יומי עריכה pattern).
4. **New task**: the same task screen, empty, opened from "+ משימה חדשה"; link picker with three
   segments (אירוע / קטגוריה / נושא) and "נושא חדש".
5. **ניהול נושאים**: the "ניהול קטגוריות" dialog pattern (add, rename, archive, restore).

## Behaviour

- The parent's status is derived from its subtasks and never set by hand (Omer, round 4 item 8;
  the edge cases approved in msg 3295): subtasks that are לא רלוונטי/בוטל or כפילות do not count;
  of the rest, all פתוחה = פתוחה, all בוצעה = בוצעה, anything else = בטיפול, **including פתוחה +
  בוצעה with no בטיפול** ("started, not finished"); when **every** subtask is לא רלוונטי/בוטל or
  כפילות, the parent is לא רלוונטי/בוטל ("nothing left to do"). The backend refuses a status write on
  a parent. Tapping a parent's status anywhere shows a small dialog: its status updates
  automatically, with a "הבנתי" button (round 5).
- Status "כפילות" asks for the original task (a picker of the other tasks).
- A task linked to an event that was deleted shows "אירוע שנמחק" under its group; nothing is lost.
- Deleting a task: managers only, behind a confirm (the statuses cover the "don't delete" cases).
- Every write goes through the backend (`teamTask.*`, `taskTopic.*` in `functions/`), which validates
  the link, the owners (active team members), the status/duplicate pair and recomputes `ownerIds`.

## Left to the builder

- Exact widget extraction from the דו יומי screens and their names.
- The bloc split (one `TeamTaskBloc` like `TaskBloc`, or more).
- The topics list document name and endpoint names.
- Mockup in the image sent to Omer is a sketch; follow the app's existing styles (`task_style.dart`).

## Testing

- Pure rules (grouping, sorting, late, owners derivation, auto status, visibility of the tab) as pure
  functions with unit tests, `now` injected.
- Backend: endpoint tests for validation and `ownerIds`.
- Rules: an owner can read their task and not another; a manager reads all.

## Round 2 (Omer's review of the preview, msg 3199)

Besides the subtask change above (decisions 5, 6, 13): a deleted task closes its sheet even when the
list updates first; the deadline picker allows today and later only and frames no events; the link
picker lists only events that have not ended, nearest first; the owner picker lists the picked members
first (a divider, then the rest, each part by name); every team member shown in the feature carries
the app's permanent-member mark.

## Round 5 (Omer, msg 3295)

- The status menu shows each status's circle on the right of its name (RTL: at the start), centred.
- The quick update button in "המשימות שלי" opens a card with the task's whole update log (newest
  first) and the field for a new one; the card stays open after a send and shows it.
- The funnel's submenu arrow points right and sits on the right of the word.
- A parent's status: the "updates automatically" dialog (see Behaviour); the item-8 edge cases above
  are approved.

## Round 7 (Omer, msg 3497)

- A "באיחור" chip (on/off, no menu) beside the status chip, and a "באיחור" row in the funnel's menu:
  only the tasks whose deadline is before today's Israel date while open or in progress. A parent
  counts when it or one of its subtasks still to be done is late; under it, "כל המשימות" then shows
  only the late subtasks (all of them when the parent itself is late). Both tabs.
- A tap on a link card's grey header folds the card to that header and opens it again; a small
  chevron on the header shows which. Folded cards are kept while the screen is open (both tabs);
  a search shows every matching card open.
- One button in the app bar folds every card ("סגירת כל השיוכים") and, once all are folded, opens
  them all ("פתיחת כל השיוכים").
- Wider than a phone (720 px and up): a task does not open a sheet or a dialog. The list (filter row
  and cards) slides to the right edge, narrowed to 42% of the width (340-640 px), and the task opens
  in a panel on the left, both animated (320 ms, ease in-out). Another task replaces the panel's
  content; ✕ slides it out and the list back. The row in the panel is highlighted. Both tabs, every
  member; switching tabs closes the panel; the "משימה חדשה" button moves to the right meanwhile.
  A phone keeps the sheet.
- The owner chip reads "אחראי/ת" (one name when one is picked, "אחראי/ת (n)" for several) and takes
  several owners, staying open while they are ticked, like the statuses; the names are centred in
  the menu. A task matches when any of its owners is picked.
- On a phone the search field and the chips are tighter so the four chips fit beside the field.

## Round 8 (Omer, msg 3549)

- The status filter opens on "פתוחה" and "בטיפול" only ("בוצעה" is ticked by hand).
- "באיחור" is the last chip, at the far left of the row, and the last row of the funnel's menu.

## Round 9 (Omer, msg 3569)

- The funnel's "שיוך" row carries the same arrow as "סטטוס" and "אחראי/ת" (it opens the link picker);
  once a link is set the row reads "<name> ✕" and clears it, the arrow's room left empty. Every word in
  that menu starts at the same place, "באיחור" (a checkbox row) included.
