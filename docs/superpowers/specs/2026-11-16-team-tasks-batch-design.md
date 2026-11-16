# Team tasks: categories, several events, urgency, no subtasks (16/11/2026)

Omer's request (msg 4101) and his answers to the plan (msgs 4105-4108, all approved).

## What changes

1. **Subtasks are removed from every screen** (list, task screen, form, Blitz, filter, search).
   The 22 subtasks in production become regular tasks in the same place as their parent,
   with their owners, status, description, deadline, contacts and log; the parent
   "מחזור 12.11 ומחזורים הבאים - משימות מהסטטוס" is closed as "לא רלוונטי/בוטל"
   (`scripts/migrate_subtasks_to_tasks.py`, run on production only after the merge).
   The backend keeps reading old subtasks, and an edit with no `subtasks` key keeps them.
2. **Categories by name (א-ב), each one card.** On top: the tasks of the category itself and
   the tasks linked to several events of it (event names as chips on the row). Below: a section
   per event of the category. A task of events in several categories is on top of each.
3. **Events inside a category**: the ones not over yet first, nearest start first (an ongoing
   one counts as upcoming); then the past ones, the latest first.
4. **Other cards**: an event with no category keeps its own card (after the categories, same
   event order); then pending events, then topics, each by name; "ללא שיוך" last.
5. **A task linked to several events.** `link` stays the first event (older app versions see
   it); `eventIds` holds them all. The link picker marks events with a box and confirms with
   "שיוך ל-N אירועים"; a tap on one name with nothing marked picks that event alone, as before.
6. **Urgency**: three levels, נמוכה / רגילה / גבוהה (msg 4108, option 3). Every existing task
   reads "רגילה". A chip on the row and in Blitz only when not "רגילה" ("גבוהה" in orange,
   "נמוכה" in grey); a "דחיפות" chip in the filter bar (and in the funnel); picked in the form
   and in the task screen.
7. **Round 10 (branch `team-tasks-r10`) comes along** (msg 4107): edit/delete of log updates,
   the form's order, "+" on a card (and now on an event's section), "אירוע שעוד לא נוצר",
   👥 on an event's card / section. Its subtask change is dropped.

## Backend

`teamTask.insert|update` accept `eventIds` (each event must exist; an update checks only the
added ones) and `urgency`. An update without either keeps the stored value (the events only
while the first event stays). `pendingEvent.link` sets `eventIds` to the real event.
