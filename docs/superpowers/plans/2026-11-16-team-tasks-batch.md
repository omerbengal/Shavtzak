# Plan: team tasks batch (16/11/2026)

Spec: `docs/superpowers/specs/2026-11-16-team-tasks-batch-design.md`.

1. Bring round 10 (`team-tasks-r10`: backend edit/delete of updates and pending events, the app
   side, the 👥 window without the labels switch). Its TEMP `apiPreview` commit only for the
   preview, dropped before the merge.
2. Backend (`functions/src/team_tasks.ts`, `team_task_ops.ts`, `index.ts`): `eventIds`,
   `urgency`, an edit without `subtasks` keeps them; tests.
3. Entity / model / repository: `eventIds`, `urgency`, joined `events`; no subtasks.
4. Rules: `groupTeamTasks` (category cards with event sections), `compareEventsByNearest`,
   the urgency filter, a link filter that knows several events; tests.
5. Bloc: no subtask events; an edit lays the new events and urgency over the task.
6. Screens: the list's cards and sections, the row (urgency chip, event chips), the form
   (several events, urgency, no subtasks), the task screen, the filter bar, Blitz.
7. Migration script, tried on `test_teamTasks` (seeded parent + the existing demo parent).
8. Checks: analyze, test, CI web build, functions build + test. Preview with `apiPreview`.
9. After Omer's merge press: drop the TEMP commit, merge, `firebase deploy --only functions`
   (the `api` change), delete `apiPreview`, run the migration on production.
