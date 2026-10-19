# Handoff: דו יומי tasks screens redesign (written 2026-10-19)

For the next Claude Code session. Read this first, then the memory note
`tasks-screens-redesign.md`. **Deadline: the first real event is Thursday
2026-10-22. Do not merge while it runs.**

## Where things are

- **Worktree:** `tasks-screens-redesign` at
  `/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/tasks-screens-redesign`.
  - The branch is `worktree-tasks-screens-redesign`, started from `main` at `5a0f804` (main has not moved since).
  - The last commit is `8f59222` (16 commits since `5a0f804`). Nothing is pushed or merged.
  - Every time you ask the user to act, say this worktree's name and full path (CLAUDE.md).
- **Status:**
  - All 12 tasks of the plan are done, plus the fixes from a final whole-branch review.
  - `cd shavtzak && flutter test` shows **1168 passing**.
  - `flutter analyze` shows **113 issues**, all pre-existing (76 info, 37 warning, none in task files). "Clean" means no new ones.
- **Do not commit** `shavtzak/pubspec.lock` or `shavtzak/analysis_options.yaml`. `flutter pub get` changed them by itself; they stay out of every commit.
- **Documents** (all in the worktree):
  - Spec, the binding authority, approved by the user: `docs/superpowers/specs/2026-10-18-tasks-screens-redesign-design.md`. The mockups are in the folder next to it.
  - Plan, written in full: `docs/superpowers/plans/2026-10-18-tasks-screens-redesign.md`.
  - Ledger, git-ignored and kept until the merge: `.superpowers/sdd/2026-10-18-tasks-screens-redesign/progress.md`. It holds every decision I made (`Ruling:` lines), the review's deferred minor findings (`minor (deferred)`) and the fixes (`Final: fixed`).

## What the user is doing right now

They were testing the build from their **phone, away from home**, through a temporary public link:

- The link is a Cloudflare quick tunnel (`cloudflared`, installed with Homebrew): a random `*.trycloudflare.com` address, which the user has. It is also in the memory note; it is kept out of this file because the repo may be public. It forwards to a local dev server, `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080`, started from the worktree's `shavtzak/`.
- `caffeinate` keeps the Mac awake for as long as the tunnel runs.
- Before setting it up I checked that the public link would work:
  - the Firebase web API key accepts any referer, for both Firestore and Identity Toolkit;
  - the `api` Cloud Function uses `cors({origin: true})`.
- The local run uses **production data**, so ticks and edits there are real.
- These processes belonged to the old session and may already be gone. Check with `pgrep -fl "cloudflared tunnel"` and `lsof -iTCP:8080 -sTCP:LISTEN`.
- **When the user says "stop the link"**, stop cloudflared, the flutter process on :8080 and caffeinate.
- If they want to test again, start both again. A new quick tunnel gets a **new URL**, which you must give them.
- A local `flutter run` cannot hot-reload from a background task. After code changes, restart the dev server and tell the user to refresh.
- From the home Wi-Fi the phone can use `http://192.168.1.88:8080/#/tasks` instead, with no tunnel.

## What to do next, in order

1. **Get the user's verdict** from their phone and computer tries. Apply changes test-first (watch the test fail first), with sizes and colours only in `TaskStyle`.
2. **Offer the deferred minor findings.** The user decides which, if any. From the final review:
   - On wide screens "משימה חדשה" sits below the stage table; the spec and mockup 3 put it above.
   - The phone row's update line is cut to one line with "…".
   - The calendar tab doesn't open scrolled to now or the current stage.
   - The focus scroll puts the opened block right under the pinned row, even when it is already visible.
   - A results list's outlines follow live matches, so a ticked row's block loses its outline.
   - About 26 inline font sizes are still outside `TaskStyle` (14 in `member_timeline.dart`).
   - The wide table's hidden pencil and bin stay tappable on touch screens.
   - The `watchEventAssignees` subscription has no `onError`.
   - Rows are not keyed by task id.
   - `chevron_left` is mirrored under RTL, so the chevrons point right. Ask the user with a drawing (memory `feedback-rtl-left-right-by-appearance`).
   - The panel header isn't bold like the sheet header.
   - StageBlock measures title lines without the Rubik style.
   - `_updateLine` is duplicated in `task_row.dart` and `stage_task_table.dart`.
   - Test gaps: a `TaskView(back: StageView)` whose stage is deleted, and the timeline wrap test running at 400 px rather than 320.
3. **Check my visible choices with the user** (all listed in the ledger). The ones most worth asking about:
   - After everything late is ticked, the late banner stays green, at the same height, until the tab reopens.
   - A task that turns late while the tab is open gets the banner only on the next open or return to the page; its row turns red at once.
   - Later stages' compact rows have tick boxes.
   - The fold line adds "· אחת עדיין פתוחה".
   - Task names wrap, as well as stage names.
   - The task sheet's title is "פרטי המשימה".
   - On wide screens the "שלב חדש" button sits over the calendar, on the start side.
4. **When the user approves the merge** (they decide; merging to `main` **deploys the web build**; there is no Functions change, so no `firebase deploy`):
   - Merge the branch into `main` the way past features were merged ("Merge branch 'worktree-…'").
   - Push only if the user asks.
   - Confirm the deploy landed (memory `web-auto-deploys-on-merge`).
   - Then clean up, after asking the user:
     - stop the tunnel and the dev server;
     - remove the two agent worktrees and their branches;
     - delete `.superpowers/sdd/2026-10-18-tasks-screens-redesign/`;
     - update the memory note.
   - The agent worktrees: `.claude/worktrees/agent-adf79da372cd07102` (branch `tasks-redesign-t9`, also `worktree-agent-adf79da372cd07102`) and `.claude/worktrees/agent-a119b6308f9674d43` (branch `tasks-redesign-t11a`, also `worktree-agent-a119b6308f9674d43`). Their commits were cherry-picked into this branch, so their own commits are not merged anywhere and deleting the branches needs `git branch -D`. Ask first.

## What was built

The approved spec, plus the user's later rule: **names wrap onto new lines and never collapse into "…"**. They gave it after trying the phone view on 2026-10-19.

- **`/tasks`** (`tasks_screen.dart`): the first time in an app session it opens the nearest event that has not ended. `TasksAutoOpen` (in `tasks_auto_open.dart`) is spent by either tasks screen, so the back arrow never bounces into the event again. The list shows events only, with weekdays, dates, the place and a "מתקיים עכשיו" pill; it is centred on wide windows.
- **Event screen frame** (`event_tasks_screen.dart`):
  - Tabs "המשימות שלי" | "כל השלבים"; managers land on the second.
  - App-bar search (it matches assignee names) shows its results in the sheet.
  - One low sheet (`widgets/task_sheet.dart`, no barrier, no shared controller) whose content is a `SheetView` (`sheet_view.dart`: a stage, a results list, or a task with a back view).
  - `RowHold` (`row_hold.dart`) keeps an open list's rows in place.
  - A deleted stage or task is resolved with `_resolve` and a post-frame correction.
  - The minute ticker, plus a refresh of "now" when the page comes back (`AppLifecycleListener`).
  - Managers' assignee check: subscribes to `watchEventAssignees`, null until it first emits.
  - At ≥ 1000 px wide:
    - a toolbar on top;
    - the days side by side, or day chips when there are more than 3;
    - a left `StagePanel` with a `StageTaskTable`.
  - "המשימות שלי" stays a centred phone column on wide screens.
- **"המשימות שלי"** (`widgets/member_timeline.dart`):
  - The anchor, the folded stages and the banner's place are decided when the timeline opens and again on resume. Highlights, captions and colours update live.
  - The full rows and "N פתוחות שלך" stay on the stage it opened on.
  - It has a debug-only "תצוגה בתור" preview for managers (read-only, `kDebugMode`).
- **"כל השלבים" on a phone** (`widgets/calendar_tab.dart`):
  - The summary and the check scroll away; the one-row filter bar (`task_filter_bar.dart`) and the day chips stay pinned.
  - `DayCalendar` and `StageBlock` (`widgets/day_calendar.dart`, `stage_block.dart`).
  - Opening a stage or a task scrolls its block to just under the pinned row and moves to its day.
- **Stage in the sheet:** `widgets/stage_sheet_view.dart`. Task in the sheet: `widgets/task_detail.dart`. Rows: `widgets/task_row.dart`, with chips from `assignee_chips.dart`.
- **Pure rules, with an injected `now`:**
  - `lib/core/utils/task_schedule.dart`: spans, current stage, anchor, fold, day layout, hours, days, labels, `ltr()`.
  - `lib/core/utils/task_progress.dart`: the event board, progress, tones, labels, late and due-soon lists, the assignee check, `heldRows`.
- **Every size and colour:** `lib/presentation/screens/task/task_style.dart`. The user will tune values after the device tries.
- **Removed:** `task_filter_modal.dart`, `stage_card.dart`, `task_card.dart`, the legacy stage list and `summarizeTaskEvent`.
- **Who built it:** Tasks 9 (calendar) and 11a (table and panel) were built by background agents (Opus 5.5, medium effort, which the user allowed) and cherry-picked. Everything else was built inline.

## Gotchas learned this session

- **The Write tool turns `⁦` / `⁩` escapes into raw invisible characters**, and the analyzer flags them (`text_direction_code_point_in_literal`).
  - Prefer the `ltr()` helper.
  - If raw ones slip in, replace U+2066–U+2069 with their `\uXXXX` escapes, for example with a small `python3 -I` script that does `str.replace` over the file. The old scratchpad script is gone with the session.
- **The worktree sandbox refuses "complex" commands that mention git**, including heredocs and loops over paths that contain "Github".
  - Run git as plain single commands from the worktree root.
  - Append to files with the Edit tool, not `cat >>` heredocs.
- **Widget tests and the test font:** it draws every glyph as a full square, so text is far wider than in Rubik.
  - Use generous view sizes (`tallPhoneSize` 400×1800 in `test/support/event_tasks_harness.dart`).
  - Call `ensureVisible` before tapping chips that sit off a horizontal row.
  - Sheet and panel bodies are one box, so lines scrolled away stay built: use `.hitTestable()` to check what can be seen.
  - The FAB's exit needs `pumpAndSettle`.
  - A `DraggableScrollableSheet` needs two drags in a test: the first grows it, the second scrolls.
- **Test helpers:**
  - `test/support/sample_event.dart` holds the mockups' event (Tue 20 to Wed 21 Oct 2026; "now" is Tue 14:40), its stages and tasks, and `sampleBoard()`.
  - `test/support/event_tasks_harness.dart` has `pumpEventTasks`, `phoneSize` and `wideSize`. Assignees default to every board member.
- **Commits** end with the attribution trailers the harness gives you. This session used `git commit --trailer "Co-Authored-By: …" --trailer "Claude-Session: …"`.
- **Do not run the app for verification** (CLAUDE.md). The user tests locally against prod; this session ran it only because the user was away and asked.

## The user's standing preferences

These apply to this work; the memory holds more.

- Plain, concrete questions: no idioms and no abstract "what do they check?". Ask about RTL placement with drawings.
- They expect to change details after seeing it on real devices.
- One-row filter bar, no countdowns, no "להיום" chip, nothing moving under the reader, and names that wrap.
- Merging to `main` deploys, and the user decides when. No merges during the event.
