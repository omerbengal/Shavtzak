# Tasks: events and stages — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `/tasks` into a list of דו יומי events, each opening its own screen of stages, with tasks living under stages.

**Architecture:** A new `stages` collection (written only through the backend `api`, read by a live stream) sits between events and tasks. Tasks gain `stageId` and an optional `assemblyTime` and lose `dueAt`; the client derives every task's due moment from its stage's date. One `TaskBloc` subscription (tasks + stages + events + members) feeds both the event list and the event screen.

**Tech Stack:** Flutter Web, flutter_bloc, go_router, Firestore; Cloud Functions (TypeScript, `node --test`).

**Spec:** `docs/superpowers/specs/2026-10-15-tasks-stages-design.md`

**Execution:** the user asked for unattended implementation ("go with your recommendation and tell me at the end"), so this plan is executed natively in the session, TDD per task. Code is written in the tasks rather than spelled out here; each task lists its interfaces and the tests that pin it.

## Global Constraints

- All UI text Hebrew, all screens RTL; every popup route (dropdown menus, dialogs, sheets) carries its own `Directionality(rtl)`.
- Every Hebrew text field uses `createRtlCursorFixedFocusNode`.
- Stage date is stored as a plain `yyyy-MM-dd` string; it must be one of the event's Israel-local days.
- Title ≤ 200 chars; requirements / notes ≤ 5000; hotel location ≤ 200; contacts ≤ 30; contact name ≤ 100, phone ≤ 30, role ≤ 100.
- Times are `HH:mm` 24h; `endTime` only with `startTime` and strictly after it.
- No client writes to Firestore; everything goes through `api` mutations.
- `flutter analyze` adds nothing to the 107 baseline; all Flutter and Functions tests pass.

## Review Focus

1. A stage date on the last day of a multi-day event whose `endDate` is stored as `T21:00Z` of the previous UTC day — must be accepted (backend `eventLocalDays`).
2. A task whose stage was deleted or never existed (e.g. the six old test tasks) — must not crash either screen; it is simply not shown.
3. An event link for an unknown, deactivated or non-דו יומי event — friendly message, not a blank screen.
4. A task with no assembly time on today's stage — orange until 23:59, never in the half-hour filter.
5. Editing a stage whose date fell outside the event after the event moved — save blocked with a clear message, not a silent bad write.

## File map

**Backend**
- Create `functions/src/stages.ts`, `functions/src/stages.test.ts` — pure stage parsing/building, event-day math.
- Modify `functions/src/tasks.ts`, `functions/src/tasks.test.ts` — `stageId`, `assemblyTime`, drop `dueAt`.
- Modify `functions/src/index.ts` — `stages` collection, `stage.*` operations, task stage checks, event-delete cascade.
- Modify `firestore.rules` — read-only `stages` / `test_stages`.

**Client data**
- Create `lib/domain/entities/stage.dart` (`Stage`, `StageContact`), `lib/data/models/stage_model.dart`.
- Modify `task_item.dart`, `task_item_model.dart`, `database_interface.dart`, `firestore_database.dart`, `logging_database.dart`, `task_repository.dart`.

**Client logic**
- Modify `lib/core/utils/task_utils.dart` — due moment, stage order, visible stages, event list split and summary, event days.
- Modify `lib/presentation/bloc/task/*` — stages on the board, stage mutations.

**Client UI**
- Modify `lib/core/router/app_router.dart` — `/tasks/:eventId`, deep link.
- Rewrite `lib/presentation/screens/task/tasks_screen.dart` as the event list; create `event_tasks_screen.dart`.
- Create `widgets/stage_card.dart`, `widgets/stage_form_modal.dart`.
- Modify `task_form_modal.dart`, `task_card.dart`, `task_filter_modal.dart`.

## Tasks

### Task 1: Backend stage rules (`stages.ts`)
**Produces:** `StageDoc`, `StageContact`, `buildNewStage(input, ctx, eventDays)`, `applyStageEdit(existing, input, ctx, eventDays)`, `eventLocalDays(startMillis, endMillis): string[]`, `stageAuditDetails`, `stageFromStored`.
- [ ] Tests: required title/date; date must be in `eventDays`; time format; end needs start and must be after it; contact limits, blank contacts dropped, contact needs name; text limits; id pattern; `eventLocalDays` for one-day, multi-day and UTC-boundary events; edit keeps `createdAt/createdById` and cannot change `eventId`.
- [ ] Implement, run `npm test`, commit.

### Task 2: Backend task changes (`tasks.ts`)
**Produces:** `TaskDoc.stageId`, `TaskDoc.assemblyTime`; `dueAt` gone.
- [ ] Tests: insert requires `stageId`; `assemblyTime` `HH:mm` or null, bad values refused; edit cannot change `stageId` or `eventId`; stored docs without `stageId` read as `''`.
- [ ] Implement, `npm test`, commit.

### Task 3: Backend wiring (`index.ts`, rules)
- [ ] `collections.stages`; `stage.insert` / `stage.update` (manager, writable event, date in event days), `stage.delete` (manager, deletes stage + its tasks in a transaction, audit with task count); `task.insert` / `task.update` require the stage to exist and share `eventId`; `deleteEventRelatedDocuments` and `event.delete` include stages; rules for `stages` / `test_stages`.
- [ ] `npm test` (build typechecks the wiring), commit.

### Task 4: Client entities, model, data source, repository
**Produces:** `Stage{id,eventId,title,date(DateTime local midnight),startTime,endTime,requirements,hotelLocation,notes,contacts,createdAt,createdById,updatedAt}`, `StageContact{id,name,phone,role}`; `StageModel.fromMap/toMutationPayload`; `TaskItem.stageId`, `TaskItem.assemblyTime`, `TaskItem.stage`; `DatabaseInterface.watchStages()`, `insertStage`, `updateStage`, `deleteStage`; `TaskBoard.stages`; `TaskRepository` stage methods.
- [ ] Tests: model round trips and tolerance; Firestore `watchStages`; board populates `task.stage` and carries stages; re-emits on stage change.
- [ ] Implement, `flutter test` for those files, commit.

### Task 5: Pure helpers (`task_utils.dart`)
**Produces:** `taskDueMoment(TaskItem) -> DateTime?`, `taskDueStatus` on it, `filterTasks(dueWithin:)` counting only timed tasks, `sortStages`, `visibleStages(...)`, `eventDays(Event) -> List<DateTime>`, `splitTaskEvents(...)`, `TaskEventSummary`.
- [ ] Tests for each, at boundaries, with injected `now`. Commit.

### Task 6: Bloc
- [ ] Tests: board with stages reaches state; `CreateStage` / `UpdateStage` / `DeleteStage` call the repository and report through the completer; optimistic ticks unchanged.
- [ ] Implement, commit.

### Task 7: Router
- [ ] Tests: `pendingTasksLinkFor` accepts `/tasks/<id>` and `/test/tasks/<id>`; rejects `/tasks/a/b`.
- [ ] Routes `/tasks/:eventId` and `/test/tasks/:eventId` → `EventTasksScreen(eventId)`. Commit.

### Task 8: Event list screen (`tasks_screen.dart`)
- [ ] Widget tests: upcoming / past sections with counts, past collapsed by default, only active דו יומי events, row summary text, tapping opens `/tasks/<id>` (test: `onOpenEvent` callback), loading and error states, test banner.
- [ ] Implement, commit.

### Task 9: Event screen and stage card
- [ ] Widget tests: header; stages in order; details fold closed by default, contact phone link; "+" and pencil/bin for managers only; tabs and per-tab filters; visible-stage rule; empty states; unknown event; ticking still optimistic; delete stage asks and warns about its tasks.
- [ ] Implement, commit.

### Task 10: Stage form
- [ ] Widget tests: required title and date; date choices = event days; one-day event preselects; time range rules; contact rows add/remove/blank-dropped; spinner, failure, dirty-save, discard prompt; edit with out-of-range date blocks save.
- [ ] Implement, commit.

### Task 11: Task form and card
- [ ] Widget tests: no event picker; stage title and date greyed; assembly time saved as `HH:mm`; assignees open at once; card shows assembly time and no event line.
- [ ] Implement, commit.

### Task 12: Filter, docs, verification
- [ ] Filter: "התייצבות בחצי שעה הקרובה", no event section.
- [ ] CLAUDE.md (routes, collections, TaskBloc), test count.
- [ ] `flutter analyze`, `flutter test`, `npm test`; commit.
