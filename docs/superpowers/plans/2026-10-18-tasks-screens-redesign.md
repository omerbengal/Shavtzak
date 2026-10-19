# דו יומי tasks screens redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved redesign of `/tasks` and `/tasks/<eventId>`: straight into the nearest event, a stage day-calendar whose low sheet keeps the schedule in view, the member's own task timeline, and a two-pane layout on wide screens.

**Architecture:** New rules are pure functions with an injected `now`, in two new core files: `task_schedule.dart` (time on the stage axis, calendar layout, day labels) and `task_progress.dart` (the event's board, counts, filter lists, the assignee check, held rows). `EventTasksScreen` becomes a frame (tabs, app-bar search, one `SheetView` shared by both tabs, phone/wide switch) over small display-only widgets; today's mutation code moves unchanged into a `State` mixin. Every size and colour lives in `TaskStyle`. `TaskBloc`, `TaskRepository`, the forms and the dialogs stay as they are.

**Tech Stack:** Flutter 3.47 (web), flutter_bloc, go_router 14, intl, url_launcher; flutter_test, bloc_test and the existing `FakeTaskRepository`.

**Spec:** `docs/superpowers/specs/2026-10-18-tasks-screens-redesign-design.md`, mockups in `docs/superpowers/specs/2026-10-18-tasks-screens-redesign/`.

**Where:** worktree `tasks-screens-redesign`, `/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/tasks-screens-redesign`, branch `worktree-tasks-screens-redesign` from `main` at `5a0f804`. Flutter commands run from `shavtzak/`; git commands from the worktree root, one plain command at a time.

**Order and checkpoint:** Tasks 1–6 make "המשימות שלי" usable on real data first, because the user wants to judge it before anything else. Task 6 ends with a stop: the user tries it, and their verdict comes before Task 7. Until Task 10, "כל השלבים" shows today's stage list. If Thursday 2026-10-22 gets close, Task 11 (wide layout) is the part to drop; everything else is the phone experience the event runs on.

## Global Constraints

- Client-only: nothing under `functions/`; no change to `firestore.rules`, the data model, the Excel template, or what `TaskBloc` and `TaskRepository` do. No new packages.
- Hebrew, `TextDirection.rtl`, Rubik, `AppTheme`. Comments in English, in the existing style: a short `///` per public symbol saying what it is for.
- Every time, time range, date range and `x/y` count inside Hebrew text goes through `ltr()` (Task 1).
- Spec copy, verbatim: "המשימות שלי" | "כל השלבים"; "סינון:", "באיחור (n)", "התייצבות בחצי שעה הקרובה (n)"; count button "N חסרות" / "1 חסרה", a done stage a tick and "n/n"; "X/Y הושלמו"; "N משימות של מי שכבר לא משובץ לאירוע" (wide: "לבדיקה: " before it); "כבר לא משובץ לאירוע"; "חסרות (n)" | "הכל (m)"; "באיחור · N משימות"; "התייצבות בחצי שעה הקרובה · N"; "עכשיו"; "השלב הבא"; "N פתוחות שלך"; "אין לך משימות"; "N שלבים קודמים · M משימות שלך הושלמו"; "התייצבות"; "ללא שעה"; "N משימות שלך באיחור"; "מתקיים עכשיו"; "אירועים קרובים"; "אירועים שעברו"; "שלב חדש"; "משימה חדשה"; "ייבוא מאקסל"; "הורדת תבנית".
- Copy that is this plan's call: singulars through `hebrewCount` (Task 2): "משימה אחת", "שלב קודם אחד", "משימה אחת שלך הושלמה", "פתוחה אחת שלך", "משימה אחת שלך", "משימה אחת של מי שכבר לא משובץ לאירוע"; results subtitles "מכל השלבים, הוותיקה ראשונה" (late) and "מכל השלבים, הקרובה ראשונה" (half hour); search header `חיפוש: "<q>" · N`; one late task "משימה שלך באיחור · <task> · <stage>, <time>"; a removed member with no record "חבר צוות שנמחק"; wide hint "בחרו שלב בלוח כדי לראות את המשימות שלו"; search hint "חיפוש משימה או אדם...".
- No countdown ("בעוד …") and no "להיום" chip anywhere.
- The filter row is one row at every width: `FittedBox(fit: BoxFit.scaleDown)`, never `Wrap`.
- Nothing moves under the reader: an open list keeps its rows (`RowHold`, Task 4); ticking never moves a row; the minute ticker never scrolls, re-folds or switches the day.
- Sizes and colours come from `TaskStyle` (Task 3), never inline.
- View models and sheet views extend `Equatable` with full objects in `props` (CLAUDE.md).
- Every new tap or toggle logs `Logger.action('<verb>:<thing>', {...})`, like `'tap:stageAdd'` today.
- Widget tests build blocs inside `testWidgets` (as `event_tasks_screen_test.dart` does today) and set the view size: phone `Size(400, 1000)`, wide `Size(1280, 900)`.
- A task is done when its tests pass, `flutter analyze` lists no issue in a file it touched and no more than 113 in total (76 info + 37 warning on `5a0f804`), and `flutter test` is green (1000 tests on `5a0f804`).
- Commit at the end of every task on `worktree-tasks-screens-redesign`, the message ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push or merge: merging to `main` deploys, and the user decides when.

## Review Focus

1. A sheet whose stage or task is deleted while it is open (by another manager, or from the sheet itself) goes back to its list or closes: no exception, no empty sheet. Tests: Task 6 (task), Task 8 (stage).
2. A stage dated outside the event's days (the event moved after its stages were made) still appears on the calendar, under a day tab of its own. Tests: Task 1 (`calendarDays`), Task 10.
3. Long Hebrew titles in narrow places (three overlapping stages on a 320 px phone, an 80-character task title) end in an ellipsis with no RenderFlex overflow. Tests: Task 3 (row), Task 9 (block).
4. A stage whose end is not after its start, or an old malformed time such as "9:00", draws as a start-only block or in the all-day row, never with a negative height or a throw. Tests: Task 1.
5. Before `watchEventAssignees` first emits, the assignee check shows nothing, not "every task flagged" for a moment. Test: Task 10.

---

### Task 1: Time on the stage axis

**Files:**
- Create: `shavtzak/lib/core/utils/task_schedule.dart`
- Modify: `shavtzak/lib/core/utils/task_utils.dart` (add `minutesOfDay`)
- Modify: `shavtzak/lib/presentation/screens/task/widgets/stage_card.dart` and `shavtzak/lib/presentation/screens/task/widgets/task_import_dialog.dart` (`stageSummaryLine` moves to `task_schedule.dart` unchanged; both import it from there)
- Create: `shavtzak/test/support/sample_event.dart`
- Test: `shavtzak/test/core/utils/task_schedule_test.dart`, `shavtzak/test/core/utils/task_utils_test.dart`

**Interfaces:**
- Consumes: `sortStages`, `eventDays` (`task_utils.dart`).
- Produces:

```dart
// task_utils.dart
int? minutesOfDay(String? time); // '09:30' → 570; null unless a valid HH:mm

// task_schedule.dart
String ltr(String text); // '⁦$text⁩'

class StageSpan extends Equatable {
  const StageSpan(this.start, this.end);
  final DateTime start;
  final DateTime end;
  bool contains(DateTime moment); // start inclusive, end exclusive
}
StageSpan? stageSpan(Stage stage, List<Stage> eventStages);
List<Stage> currentStages(List<Stage> eventStages, DateTime now); // screen order
bool isStageOver(Stage stage, List<Stage> eventStages, DateTime now);
Stage? timelineAnchor(List<Stage> eventStages, DateTime now);
Set<String> foldedStageIds(List<Stage> eventStages, Stage anchor);

class CalendarBlock extends Equatable {
  const CalendarBlock({required this.stage, required this.startMinute,
      required this.endMinute, required this.column, required this.columnCount});
  final Stage stage;
  final int startMinute; // since midnight
  final int endMinute; // as drawn
  final int column; // 0 = the start side (right under RTL)
  final int columnCount;
}
class DayLayout extends Equatable {
  const DayLayout({required this.allDay, required this.blocks});
  final List<Stage> allDay; // stages with no usable time, screen order
  final List<CalendarBlock> blocks;
}
DayLayout layoutDay(List<Stage> dayStages, {required int minBlockMinutes});
({int first, int last})? calendarHours(Iterable<Stage> stages,
    {required int minBlockMinutes});
List<DateTime> calendarDays(Event event, List<Stage> eventStages);
DateTime initialCalendarDay(List<DateTime> days, DateTime now);
String hebrewWeekday(DateTime date); // 'ראשון' … 'שבת'
String dayLabel(DateTime day, DateTime now); // 'שלישי 20/10 · היום'
String eventDaysLabel(Event event); // 'שלישי–רביעי, ' + ltr('20–21/10')
bool isEventUnderWay(Event event, DateTime now);
String stageTimeLabel(Stage stage); // ltr('14:30–17:00'), ltr('19:30') or ''
String stageSummaryLine(Stage stage); // moved, unchanged
```

- [ ] **Step 1: Commit the spec, the mockups and this plan**

```bash
git add docs/superpowers/specs/2026-10-18-tasks-screens-redesign-design.md docs/superpowers/specs/2026-10-18-tasks-screens-redesign docs/superpowers/plans/2026-10-18-tasks-screens-redesign.md
git commit -m "docs(tasks): screens redesign spec, mockups and plan" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Add the shared sample event**

`shavtzak/test/support/sample_event.dart`, the mockups' event (Task 5 adds its members and tasks):

```dart
/// The mockups' event: Tuesday 20 – Wednesday 21 October 2026, seen on
/// Tuesday at 14:40.
final sampleNow = DateTime(2026, 10, 20, 14, 40);
final sampleTue = DateTime(2026, 10, 20);
final sampleWed = DateTime(2026, 10, 21);
final sampleEvent = buildEvent(id: 'e1', name: 'דו יומי הנהלה',
    startDate: sampleTue, endDate: sampleWed, location: 'מלון רויאל');
final stSetup = buildStage(id: 'setup', title: 'הקמה', date: sampleTue, startTime: '08:00', endTime: '09:00');
final stLunch = buildStage(id: 'lunch', title: 'ארוחת צהריים', date: sampleTue, startTime: '13:00', endTime: '14:00');
final stWorkshops = buildStage(id: 'ws', title: 'סדנאות', date: sampleTue, startTime: '14:30', endTime: '17:00', hotelLocation: 'חדרי הסדנה');
final stDinner = buildStage(id: 'dinner', title: 'ארוחת ערב חגיגית', date: sampleTue, startTime: '19:30', hotelLocation: 'אולם האירועים'); // start only
final stRooms = buildStage(id: 'rooms', title: 'חלוקת חדרים', date: sampleTue); // no time
final stBreakfast = buildStage(id: 'bf', title: 'ארוחת בוקר', date: sampleWed, startTime: '07:30', endTime: '08:30');
final stCheckout = buildStage(id: 'out', title: "צ'ק אאוט", date: sampleWed); // no time
final sampleStages = [stSetup, stLunch, stWorkshops, stDinner, stRooms, stBreakfast, stCheckout];
```

Their screen order (`sortStages`): rooms, setup, lunch, ws, dinner, out, bf.

- [ ] **Step 3: Write the failing tests**

`shavtzak/test/core/utils/task_schedule_test.dart` (`ids` maps stages to their ids):

```dart
group('stageSpan', () {
  test('a stage with both times runs from its start to its end', () {
    expect(stageSpan(stWorkshops, sampleStages),
        StageSpan(DateTime(2026, 10, 20, 14, 30), DateTime(2026, 10, 20, 17)));
  });
  test('a start-only stage runs until the next stage starts, the next day too', () {
    expect(stageSpan(stDinner, sampleStages)!.end, DateTime(2026, 10, 21, 7, 30));
  });
  test('the last start-only stage runs to the end of its day', () {
    final close = buildStage(id: 'close', date: sampleWed, startTime: '16:00');
    expect(stageSpan(close, [...sampleStages, close])!.end, DateTime(2026, 10, 22));
  });
  test('an end that is not after the start counts as no end', () {
    final odd = buildStage(id: 'odd', date: sampleTue, startTime: '15:00', endTime: '15:00');
    expect(stageSpan(odd, [odd, stDinner])!.end, DateTime(2026, 10, 20, 19, 30));
  });
  test('no time, or a malformed one, means no span', () {
    expect(stageSpan(stRooms, sampleStages), isNull);
    expect(stageSpan(buildStage(id: 'bad', date: sampleTue, startTime: '9:00'), sampleStages), isNull);
  });
});

group('currentStages', () {
  test('is the stage running now', () {
    expect(ids(currentStages(sampleStages, sampleNow)), ['ws']);
  });
  test('is empty between stages', () {
    expect(currentStages(sampleStages, DateTime(2026, 10, 20, 14, 10)), isEmpty);
  });
  test('starts on the start minute and stops on the end minute', () {
    expect(ids(currentStages(sampleStages, DateTime(2026, 10, 20, 14, 30))), ['ws']);
    expect(currentStages(sampleStages, DateTime(2026, 10, 20, 17)), isEmpty);
  });
  test('overlapping stages are both current, in screen order', () {
    final talk = buildStage(id: 'talk', date: sampleTue, startTime: '14:00', endTime: '16:00');
    expect(ids(currentStages([...sampleStages, talk], DateTime(2026, 10, 20, 15))), ['talk', 'ws']);
  });
});

group('isStageOver', () {
  test('a timed stage is over once its span ends', () {
    expect(isStageOver(stLunch, sampleStages, sampleNow), isTrue);
    expect(isStageOver(stWorkshops, sampleStages, sampleNow), isFalse);
  });
  test('a stage with no time is over once its day is', () {
    expect(isStageOver(stRooms, sampleStages, DateTime(2026, 10, 20, 23)), isFalse);
    expect(isStageOver(stRooms, sampleStages, DateTime(2026, 10, 21, 8)), isTrue);
  });
});

group('timelineAnchor', () {
  test('is the current stage', () {
    expect(timelineAnchor(sampleStages, sampleNow)!.id, 'ws');
  });
  test('between stages it is the next timed one', () {
    expect(timelineAnchor(sampleStages, DateTime(2026, 10, 20, 14, 10))!.id, 'ws');
  });
  test('before the event it is the first timed stage', () {
    expect(timelineAnchor(sampleStages, DateTime(2026, 10, 19, 10))!.id, 'setup');
  });
  test('after the event it is the last stage', () {
    expect(timelineAnchor(sampleStages, DateTime(2026, 10, 22, 10))!.id, 'bf');
  });
  test('with untimed stages only it is the first one not over', () {
    expect(timelineAnchor([stRooms, stCheckout], DateTime(2026, 10, 21, 12))!.id, 'out');
  });
  test('is null without stages', () {
    expect(timelineAnchor(const [], sampleNow), isNull);
  });
});

test('foldedStageIds folds what comes before the anchor, except untimed stages of its day', () {
  expect(foldedStageIds(sampleStages, stWorkshops), {'setup', 'lunch'});
  expect(foldedStageIds(sampleStages, stBreakfast), {'rooms', 'setup', 'lunch', 'ws', 'dinner'});
});

group('layoutDay', () {
  test('untimed stages go to the all-day row, the rest by minute', () {
    final layout = layoutDay([stRooms, stSetup, stLunch, stWorkshops, stDinner], minBlockMinutes: 33);
    expect(layout.allDay, [stRooms]);
    expect([for (final b in layout.blocks) (b.stage.id, b.startMinute, b.endMinute, b.column, b.columnCount)], [
      ('setup', 480, 540, 0, 1),
      ('lunch', 780, 840, 0, 1),
      ('ws', 870, 1020, 0, 1),
      ('dinner', 1170, 1203, 0, 1),
    ]);
  });
  test('overlapping stages take columns side by side', () {
    final a = buildStage(id: 'a', date: sampleTue, startTime: '10:00', endTime: '12:00');
    final b = buildStage(id: 'b', date: sampleTue, startTime: '11:00', endTime: '13:00');
    final c = buildStage(id: 'c', date: sampleTue, startTime: '12:30', endTime: '13:30');
    expect([for (final x in layoutDay([a, b, c], minBlockMinutes: 33).blocks) (x.stage.id, x.column, x.columnCount)],
        [('a', 0, 2), ('b', 1, 2), ('c', 0, 2)]);
  });
  test('a malformed start time goes to the all-day row', () {
    final bad = buildStage(id: 'bad', date: sampleTue, startTime: '9:00');
    expect(layoutDay([bad], minBlockMinutes: 33).allDay, [bad]);
  });
});

test('calendarHours runs from the earliest start to the latest drawn end', () {
  expect(calendarHours([stSetup, stWorkshops, stDinner], minBlockMinutes: 33), (first: 8, last: 21));
  expect(calendarHours([stRooms], minBlockMinutes: 33), isNull);
});

test('calendarDays adds the day of a stage that fell outside the event', () {
  final stray = buildStage(id: 'stray', date: DateTime(2026, 10, 23));
  expect(calendarDays(sampleEvent, [...sampleStages, stray]),
      [sampleTue, sampleWed, DateTime(2026, 10, 23)]);
});

test('initialCalendarDay is today during the event, else the first day', () {
  expect(initialCalendarDay([sampleTue, sampleWed], DateTime(2026, 10, 21, 9)), sampleWed);
  expect(initialCalendarDay([sampleTue, sampleWed], DateTime(2026, 10, 11)), sampleTue);
});

test('labels', () {
  expect(hebrewWeekday(DateTime(2026, 10, 18)), 'ראשון');
  expect(hebrewWeekday(sampleTue), 'שלישי');
  expect(hebrewWeekday(DateTime(2026, 10, 24)), 'שבת');
  expect(dayLabel(sampleTue, sampleNow), 'שלישי 20/10 · היום');
  expect(dayLabel(sampleWed, sampleNow), 'רביעי 21/10');
  expect(eventDaysLabel(sampleEvent), 'שלישי–רביעי, ${ltr('20–21/10')}');
  expect(eventDaysLabel(buildEvent(startDate: sampleTue)), 'שלישי, 20/10');
  expect(eventDaysLabel(buildEvent(startDate: DateTime(2026, 10, 30), endDate: DateTime(2026, 11, 1))),
      'שישי–ראשון, ${ltr('30/10–01/11')}');
  expect(stageTimeLabel(stWorkshops), ltr('14:30–17:00'));
  expect(stageTimeLabel(stDinner), ltr('19:30'));
  expect(stageTimeLabel(stRooms), '');
});

test('isEventUnderWay counts the event days only', () {
  expect(isEventUnderWay(sampleEvent, sampleNow), isTrue);
  expect(isEventUnderWay(sampleEvent, DateTime(2026, 10, 19, 23, 59)), isFalse);
  expect(isEventUnderWay(sampleEvent, DateTime(2026, 10, 22)), isFalse);
});
```

In `task_utils_test.dart`, a `minutesOfDay` group: `'09:30'` → 570 and `'00:00'` → 0; `'9:30'`, `'24:00'`, `''` and `null` → null.

- [ ] **Step 4: Run them to see them fail**

Run: `cd shavtzak && flutter test test/core/utils/task_schedule_test.dart test/core/utils/task_utils_test.dart`
Expected: compile errors: `task_schedule.dart` and `minutesOfDay` do not exist.

- [ ] **Step 5: Implement**

- `minutesOfDay` in `task_utils.dart`, on the existing `_parseHourMinute`.
- `task_schedule.dart` with the signatures above. What the tests leave open:
  - The event's timeline orders the stages that have a valid start by date, then start minute. A stage with no end, or an end not after its start, ends where the first later stage on that timeline starts, else at midnight after its own day.
  - `timelineAnchor`: the first stage in screen order that is current; else the first timed stage not over; else the first stage not over; else the last stage.
  - `foldedStageIds`: the stages before the anchor in `sortStages` order, minus the untimed stages on the anchor's day.
  - `layoutDay`: blocks sorted by start, longer first on a tie; drawn end `max(end, start + minBlockMinutes)`; blocks that overlap transitively form a cluster that shares one `columnCount`; each block takes the lowest column that is free at its start.
  - `calendarHours`: `first = floor(min start / 60)`, `last = min(24, ceil(max drawn end / 60))`.
  - `eventDaysLabel`: the weekdays joined by "–", a comma, then `ltr` of `dd–dd/MM` (one month) or `dd/MM–dd/MM` (two); a one-day event is `'<weekday>, dd/MM'`.
- Move `stageSummaryLine` and its `DateFormat` from `stage_card.dart` to `task_schedule.dart`; import it in `stage_card.dart` and `task_import_dialog.dart`.

- [ ] **Step 6: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/core/utils/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 7: Commit**

```bash
git add shavtzak/lib/core/utils shavtzak/lib/presentation/screens/task/widgets shavtzak/test/support/sample_event.dart shavtzak/test/core/utils
git commit -m "feat(tasks): time rules on the stage axis" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Counts, lists and the assignee check

**Files:**
- Create: `shavtzak/lib/core/utils/task_progress.dart`
- Modify: `shavtzak/lib/core/utils/task_utils.dart` (`isDueSoon`; search matches assignee names instead of the event name)
- Test: `shavtzak/test/core/utils/task_progress_test.dart`, `shavtzak/test/core/utils/task_utils_test.dart`

**Interfaces:**
- Consumes: `taskDueStatus`, `sortTasks`, `sortStages`, `filterTasks`, `taskDueSoonWindow`.
- Produces:

```dart
// task_utils.dart
bool isDueSoon(TaskItem task, DateTime now); // unfinished, has a report time, due in [now, now + taskDueSoonWindow]
// filterTasks(query:) matches title, description and assignee names.

// task_progress.dart
class EventTaskBoard extends Equatable {
  const EventTaskBoard({required this.event, required this.stages, required this.tasks});
  final Event event;
  final List<Stage> stages; // this event's, sortStages order
  final List<TaskItem> tasks; // this event's tasks whose stage exists, sortTasks order
  List<TaskItem> tasksOf(String stageId);
  Stage? stageById(String id);
  TaskItem? taskById(String id);
}
EventTaskBoard eventTaskBoard(Event event, {required List<Stage> stages, required List<TaskItem> tasks});

class TaskProgress extends Equatable {
  const TaskProgress({this.total = 0, this.done = 0, this.late = 0, this.dueSoon = 0});
  final int total, done, late, dueSoon;
  int get missing; // total - done
  int get rest; // missing - late - dueSoon
}
TaskProgress taskProgress(Iterable<TaskItem> tasks, DateTime now);
enum CountTone { none, done, late, soon, open }
CountTone countTone(TaskProgress progress);
String missingLabel(int missing); // '1 חסרה' | 'N חסרות'
String hebrewCount(int n, {required String one, required String many}); // n == 1 ? one : '$n $many'
List<TaskItem> lateTasks(Iterable<TaskItem> tasks, DateTime now); // longest overdue first
List<TaskItem> dueSoonTasks(Iterable<TaskItem> tasks, DateTime now); // soonest first
List<String> removedAssigneeIds(TaskItem task, Set<String> assignedIds); // in assigneeIds order
List<TaskItem> tasksWithRemovedAssignees(Iterable<TaskItem> tasks, Set<String> assignedIds);
List<TaskItem> heldRows({required List<TaskItem> matching, required Set<String> heldIds, required List<TaskItem> all});
```

- [ ] **Step 1: Write the failing tests**

`task_progress_test.dart`, at `sampleNow`:

```dart
final done = buildTask(id: 'done', stage: stWorkshops, assemblyTime: '14:00', isComplete: true);
final late = buildTask(id: 'late', stage: stLunch, assemblyTime: '13:00');
final soon = buildTask(id: 'soon', stage: stWorkshops, assemblyTime: '15:00');
final later = buildTask(id: 'later', stage: stWorkshops, assemblyTime: '15:45');
final untimed = buildTask(id: 'untimed', stage: stWorkshops);

test('taskProgress counts done, late, due in the half hour and the rest', () {
  final p = taskProgress([done, late, soon, later, untimed], sampleNow);
  expect(p, const TaskProgress(total: 5, done: 1, late: 1, dueSoon: 1));
  expect((p.missing, p.rest), (4, 2));
});
test('countTone takes the worst case', () {
  expect(countTone(const TaskProgress()), CountTone.none);
  expect(countTone(const TaskProgress(total: 2, done: 2)), CountTone.done);
  expect(countTone(const TaskProgress(total: 3, late: 1, dueSoon: 1)), CountTone.late);
  expect(countTone(const TaskProgress(total: 3, dueSoon: 1)), CountTone.soon);
  expect(countTone(const TaskProgress(total: 3, done: 1)), CountTone.open);
});
test('labels', () {
  expect(missingLabel(1), '1 חסרה');
  expect(missingLabel(3), '3 חסרות');
  expect(hebrewCount(1, one: 'משימה אחת', many: 'משימות'), 'משימה אחת');
  expect(hebrewCount(4, one: 'משימה אחת', many: 'משימות'), '4 משימות');
});
test('lateTasks: unfinished and past due, longest overdue first', () {
  final early = buildTask(id: 'early', stage: stSetup, assemblyTime: '08:30');
  expect(ids(lateTasks([late, done, early, soon], sampleNow)), ['early', 'late']);
});
test('dueSoonTasks: unfinished, timed, due in the next half hour, soonest first', () {
  final sooner = buildTask(id: 'sooner', stage: stWorkshops, assemblyTime: '14:50');
  expect(ids(dueSoonTasks([soon, later, untimed, sooner, late], sampleNow)), ['sooner', 'soon']);
});
test('removedAssigneeIds lists assignees no longer on the event, deleted members too', () {
  expect(removedAssigneeIds(buildTask(assigneeIds: const ['m1', 'm2', 'gone']), {'m1'}), ['m2', 'gone']);
});
test('tasksWithRemovedAssignees keeps the tasks that have any', () {
  final ok = buildTask(id: 'ok', assigneeIds: const ['m1']);
  final off = buildTask(id: 'off', assigneeIds: const ['m1', 'm2']);
  expect(ids(tasksWithRemovedAssignees([ok, off], {'m1'})), ['off']);
});
test('heldRows keeps the rows already shown, live and in order, and drops deleted ones', () {
  final a = buildTask(id: 'a', stage: stWorkshops, assemblyTime: '15:00');
  final b = buildTask(id: 'b', stage: stWorkshops, assemblyTime: '14:45', isComplete: true);
  final c = buildTask(id: 'c', stage: stWorkshops, assemblyTime: '16:00');
  expect(heldRows(matching: [a], heldIds: {'a', 'b', 'gone'}, all: [a, b, c]), [b, a]);
});
test('eventTaskBoard keeps this event\'s stages and the tasks whose stage exists', () {
  final other = buildStage(id: 'other', eventId: 'e2');
  final board = eventTaskBoard(sampleEvent, stages: [stWorkshops, other, stSetup], tasks: [
    buildTask(id: 'in', stage: stWorkshops, assemblyTime: '15:00'),
    buildTask(id: 'orphan', stageId: 'gone'),
    buildTask(id: 'elsewhere', eventId: 'e2', stage: other),
  ]);
  expect(board.stages.map((s) => s.id), ['setup', 'ws']);
  expect(board.tasks.map((t) => t.id), ['in']);
  expect(board.tasksOf('ws').map((t) => t.id), ['in']);
  expect(board.stageById('other'), isNull);
  expect(board.taskById('in')!.id, 'in');
});
```

In `task_utils_test.dart`'s `filterTasks` group, "the query matches the event name" gives way to "the query matches an assignee's name" (a task with `assignees: [buildMember(id: 'm2', name: 'יואב כהן')]` is found by `'יואב'`) and "the query no longer matches the event name" (`'דרום'` finds nothing). New `isDueSoon` group at `sampleNow`: due exactly now → true; now + 30 min → true; now + 31 min → false; no report time → false; complete → false.

- [ ] **Step 2: Run them to see them fail**

Run: `cd shavtzak && flutter test test/core/utils/task_progress_test.dart test/core/utils/task_utils_test.dart`
Expected: compile errors for the new file and `isDueSoon`.

- [ ] **Step 3: Implement**

`isDueSoon` wraps the existing `_isDueWithin(task, now, taskDueSoonWindow)`. In `filterTasks` the event-name match gives way to `task.assignees.any((m) => _searchable(m.name).contains(normalizedQuery))`. `taskProgress` counts late with `taskDueStatus(...) == TaskDueStatus.overdue` and due-soon with `isDueSoon`. `lateTasks` and `dueSoonTasks` are `sortTasks` over `filterTasks(statuses: {TaskDueStatus.overdue})` and `filterTasks(dueWithin: taskDueSoonWindow)`. `eventTaskBoard` keeps `task.eventId == event.id` with a stage id among this event's stages.

- [ ] **Step 4: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/core/utils/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 5: Commit** (`git add shavtzak/lib/core/utils shavtzak/test/core/utils`, message "feat(tasks): counts, filter lists and the assignee check" plus the co-author line).

---

### Task 3: Style values and the row pieces

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/task_style.dart`, `.../task/widgets/progress_strip.dart`, `.../task/widgets/stage_count_button.dart`, `.../task/widgets/task_row.dart`
- Modify: `shavtzak/test/support/task_fixtures.dart` (`buildMember` gains `String? phoneNumber`)
- Test: `shavtzak/test/presentation/screens/task/widgets/progress_strip_test.dart`, `stage_count_button_test.dart`, `task_row_test.dart`

**Interfaces:**
- Consumes: Task 1 (`ltr`), Task 2 (`TaskProgress`, `countTone`, `missingLabel`, `isDueSoon`).
- Produces:

```dart
/// Every size and colour of the tasks screens, kept together so that tuning
/// the look after trying it on a phone is a one-line change.
abstract final class TaskStyle {
  static const late = Color(0xFFE53935), lateLight = Color(0xFFFFEBEE), lateDark = Color(0xFFC62828);
  static const soon = Color(0xFFFB8C00), soonLight = Color(0xFFFFF3E0), soonDark = Color(0xFFBF360C);
  static const done = Color(0xFF43A047), doneLight = Color(0xFFE8F5E9), doneDark = Color(0xFF2E7D32);
  static const current = AppTheme.primary, currentLight = Color(0xFFE3F2FD), mine = Color(0xFF1565C0);
  static const rest = Color(0xFFE0E0E0), neutralText = Color(0xFF616161), faintText = Color(0xFF9E9E9E);
  static const double hourHeight = 56, wideHourHeight = 48, hourLabelWidth = 40;
  static const double minBlockHeight = 30, blockDetailsMinHeight = 52, blockProgressMinHeight = 68;
  static const double outlineWidth = 2.5, fadedOpacity = 0.35, focusTopMargin = 8;
  static const double sheetInitialSize = 0.5, sheetMaxSize = 0.92, sheetCloseBelow = 0.12;
  static const double wideBreakpoint = 1000, readableWidth = 640;
  static const int maxSideBySideDays = 3, calendarFlex = 5, panelFlex = 6;
  static const double filterFontSize = 13, rowTitleSize = 15, rowMetaSize = 12.5;
  static const double stripHeight = 6, timeColumnWidth = 52;
  static int minBlockMinutes(double hourHeight) => (minBlockHeight / hourHeight * 60).ceil();
}

class ProgressStrip extends StatelessWidget {
  const ProgressStrip({super.key, required this.progress, this.height = TaskStyle.stripHeight});
}
class StageCountButton extends StatelessWidget {
  const StageCountButton({super.key, required this.progress, required this.onPressed});
}
class TaskRow extends StatelessWidget {
  const TaskRow({super.key, required this.task, required this.now, required this.viewerId,
      required this.canTick, required this.onSetComplete, required this.onOpen,
      required this.onCallPhone, this.removedAssigneeIds = const []});
  final TaskItem task;
  final DateTime now;
  final String viewerId;
  final bool canTick;
  final ValueChanged<bool> onSetComplete;
  final VoidCallback onOpen;
  final ValueChanged<String> onCallPhone;
  final List<String> removedAssigneeIds;
}
```

Keys: `strip-done`, `strip-late`, `strip-soon`, `strip-rest`; `task-row-<id>`, `task-row-tick-<id>`, `task-row-late-<id>`, `task-row-time-<id>`, `task-row-assignee-<id>-<memberId>`, `task-row-call-<id>-<memberId>`, `task-row-update-<id>`.

What they look like:
- `ProgressStrip`: a left-to-right row of segments — done (`done`), late (`late`), half hour (`soon`), the rest (`rest`) — each as wide as its count; no tasks, one grey segment. Rounded ends.
- `StageCountButton`: nothing at all when the stage has no tasks; done: a check icon and `ltr('n/n')`, `doneDark` on `doneLight`; otherwise `missingLabel(missing)` in a pill: late `lateDark` on `lateLight`, soon `soonDark` on `soonLight`, open `neutralText` on white with a grey border. Its tap area is at least 40 px wide.
- `TaskRow`, start to end and top to bottom: a 40 px leading slot holding a `Checkbox` (`onChanged` null unless `canTick`) for a task without subtasks, or `ltr('d/n')` for one with subtasks; the title (`rowTitleSize`, at most 2 lines, ellipsis; grey and struck through when complete) with a red "באיחור" chip at its end when overdue; a meta line (`rowMetaSize`): `'התייצבות ${ltr(HH:mm)}'` or `'ללא שעה'` (`soonDark` when `isDueSoon`, `lateDark` when overdue, `neutralText` otherwise), then `ltr('d/n')` for a task with subtasks; assignee chips in a `Wrap`: the viewer's own filled `mine` with white text, a removed one (`removedAssigneeIds`) struck through in `lateDark` and followed by "כבר לא משובץ לאירוע" (an id with no member reads "חבר צוות שנמחק"), and a phone icon button (40×40 hit area) after a chip whose member has a non-empty `phoneNumber`; the update line, one line with ellipsis: `'<note> · <author>, ${ltr(time)}'`, the time `HH:mm` on `now`'s day, else `dd/MM HH:mm`. A tap anywhere else calls `onOpen`.

- [ ] **Step 1: Write the failing tests**

Each widget is pumped in `MaterialApp(home: Directionality(rtl, Scaffold(body: …)))` at `sampleNow`, with `dana = buildMember(id: 'm1', name: 'דנה', phoneNumber: '0501234567')` and `yoav = buildMember(id: 'm2', name: 'יואב')`.

```dart
// progress_strip_test.dart — a 200 px wide strip
testWidgets('fills from the left: done, late, half hour, then the rest', (tester) async {
  // TaskProgress(total: 10, done: 4, late: 1, dueSoon: 2)
  expect([for (final k in ['strip-done', 'strip-late', 'strip-soon', 'strip-rest']) tester.getSize(find.byKey(Key(k))).width],
      [80, 20, 40, 60]);
  // and each segment's left edge is left of the next one's
});
testWidgets('no tasks is one grey strip', (tester) async {
  expect(find.byKey(const Key('strip-rest')), findsOneWidget);
  expect(find.byKey(const Key('strip-done')), findsNothing);
});

// stage_count_button_test.dart
testWidgets('a done stage shows a tick and n/n'); // find.byIcon(Icons.check); find.text(ltr('5/5'))
testWidgets('a late task makes the count red'); // '3 חסרות' in TaskStyle.lateDark
testWidgets('a task due in the half hour, none late, makes it orange'); // TaskStyle.soonDark
testWidgets('otherwise it is neutral, singular for one'); // '1 חסרה' in TaskStyle.neutralText
testWidgets('a stage without tasks has no button'); // find.byType(InkWell) findsNothing
testWidgets('pressing it reports'); // onPressed called once

// task_row_test.dart
testWidgets('shows the title, the report time and the subtask count'); // 'הכנת חדר סדנה 2', 'התייצבות ${ltr('15:00')}', ltr('1/3')
testWidgets('an untimed task says ללא שעה');
testWidgets('a late task carries the red באיחור mark'); // task-row-late-<id>
testWidgets('a task due in the half hour shows its time in orange, no countdown'); // TaskStyle.soonDark; find.textContaining('בעוד') findsNothing
testWidgets('a task without subtasks ticks through its box'); // tap task-row-tick-<id> → onSetComplete(true)
testWidgets('someone who may not tick gets a disabled box'); // Checkbox.onChanged isNull
testWidgets('a task with subtasks has no tick box');
testWidgets('a done task is struck through');
testWidgets('an assignee with a phone gets a call button, one without does not'); // task-row-call-<id>-m1 → '0501234567'; none for m2
testWidgets('the viewer\'s own chip is filled in the mine colour');
testWidgets('a removed assignee is struck through in red, with the note'); // 'כבר לא משובץ לאירוע'; an unknown id reads 'חבר צוות שנמחק'
testWidgets('the update line shows the note, its author and its time'); // 'מחכים למקרן · נועה לוי, ${ltr('14:22')}'
testWidgets('pressing the row opens the task'); // tap the title → onOpen once
testWidgets('an 80-character title on a 320 px phone ends in an ellipsis'); // Size(320, 640): tester.takeException() isNull; maxLines 2, TextOverflow.ellipsis
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd shavtzak && flutter test test/presentation/screens/task/widgets/`
Expected: compile errors for the three new test files.

- [ ] **Step 3: Implement** the four files as described, and `phoneNumber` in `buildMember`.

- [ ] **Step 4: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/presentation/screens/task/widgets/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 5: Commit** (`git add shavtzak/lib/presentation/screens/task shavtzak/test/support/task_fixtures.dart shavtzak/test/presentation/screens/task/widgets`, message "feat(tasks): style values, progress strip, count button and task row").

---

### Task 4: One task's view, the sheet, and lists that hold still

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/sheet_view.dart`, `.../task/row_hold.dart`, `.../task/widgets/task_detail.dart`, `.../task/widgets/task_sheet.dart`, `.../task/widgets/task_results_list.dart`
- Test: `shavtzak/test/presentation/screens/task/row_hold_test.dart`, `.../task/widgets/task_detail_test.dart` (ported from `task_card_test.dart`, which stays until Task 10), `.../task/widgets/task_sheet_test.dart`, `.../task/widgets/task_results_list_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3; `StageTasks` (`task_utils.dart`).
- Produces:

```dart
// sheet_view.dart — what the sheet (or, on wide screens, the panel) shows.
enum ResultsKind { late, dueSoon, search, removedAssignees, myLate }
sealed class SheetView extends Equatable { const SheetView(); }
final class StageView extends SheetView {
  const StageView(this.stageId, {this.missingOnly = false});
  final String stageId;
  final bool missingOnly;
}
final class ResultsView extends SheetView {
  const ResultsView(this.kind, {this.query = ''});
  final ResultsKind kind;
  final String query; // search only
}
final class TaskView extends SheetView {
  const TaskView(this.taskId, {this.back});
  final String taskId;
  final SheetView? back; // the list it was opened from
}

// row_hold.dart
/// Keeps an open list's rows in place: a row stays until the list is left.
class RowHold {
  List<TaskItem> rows(SheetView view, {required List<TaskItem> matching, required List<TaskItem> all});
  void clear();
}

// task_sheet.dart
class SheetContent {
  const SheetContent({required this.header, required this.body});
  final Widget header;
  final Widget body;
}
class TaskSheet extends StatelessWidget {
  const TaskSheet({super.key, required this.controller, required this.viewKey,
      required this.content, required this.onClose, this.onBack});
  final DraggableScrollableController controller;
  final Object viewKey; // a new key starts the content at its top
  final SheetContent content;
  final VoidCallback onClose;
  final VoidCallback? onBack;
}

// task_detail.dart — the callbacks of today's TaskCard, plus onCallPhone
class TaskDetail extends StatelessWidget {
  const TaskDetail({super.key, required this.task, required this.now, required this.canManage,
      required this.canUpdateProgress, required this.onToggleSubtask, required this.onSetComplete,
      required this.onEditUpdate, required this.onEdit, required this.onDelete, required this.onCallPhone});
}

// task_results_list.dart
class TaskResultsList extends StatelessWidget {
  const TaskResultsList({super.key, required this.groups, required this.rowBuilder, this.emptyText = 'אין משימות'});
  final List<StageTasks> groups;
  final Widget Function(TaskItem task) rowBuilder;
  final String emptyText;
}
```

Keys: `task-sheet` (surface), `task-sheet-handle`, `task-sheet-close`, `task-sheet-back`; `task-detail-<id>`, `task-detail-call-<memberId>`, and from `TaskCard`, unchanged: `task-complete-<id>`, `subtask-<subtaskId>`, `task-update-<id>`, `task-edit-<id>`, `task-delete-<id>`, `task-progress-<id>`; `results-stage-<stageId>`.

What they do:
- `RowHold.rows`: when `view` differs from the last call's, it forgets what it held; it then adds `matching`'s ids and returns `heldRows(matching, heldIds, all)`.
- `TaskSheet`: `DraggableScrollableSheet(controller, initialChildSize: sheetInitialSize, minChildSize: 0, maxChildSize: sheetMaxSize, snap: true, snapSizes: [sheetInitialSize])` with no barrier, so what is above it stays readable and tappable; a white surface with rounded top corners and a shadow. Inside, a `CustomScrollView` keyed by `viewKey` on the sheet's scroll controller: a `PinnedHeaderSliver` with the drag handle and a row (back arrow when `onBack`, `content.header` expanded, X), then `content.body` in a `SliverToBoxAdapter`. Once the sheet is dragged below `sheetCloseBelow` it calls `onClose` (once).
- `TaskDetail`: `TaskCard`'s content without its tinted card. Title row: checkbox for a task without subtasks, the title, a status chip — "באיחור" (`late`) or "הושלמה" (`done`), never "להיום" — and edit and delete for managers. Then `'<stage title> · התייצבות ${ltr(HH:mm)}'` or `'<stage title> · ללא שעה'` (time in `soonDark` when `isDueSoon`); the assignees one per line, each with a call button when they have a phone ('ללא אחראים' when none); the description; progress bar and `ltr('d/n')`; the update block exactly as today; 'עודכן לאחרונה: dd/MM/yyyy HH:mm'; the subtasks.
- `TaskResultsList`: for each group a header `'<stage title> · ${stageTimeLabel(stage)}'` (the title alone when untimed), then `rowBuilder` per task in the order given; no groups shows `emptyText`.

- [ ] **Step 1: Write the failing tests**

```dart
// row_hold_test.dart
test('a row that stops matching stays while the view stays the same', () {
  final hold = RowHold();
  hold.rows(const StageView('ws', missingOnly: true), matching: [a, b], all: [a, b]);
  expect(hold.rows(const StageView('ws', missingOnly: true), matching: [a], all: [a, bDone]), [a, bDone]);
});
test('another view starts from scratch'); // StageView('ws') after StageView('ws', missingOnly: true) holds nothing
test('clear forgets the rows');
test('a deleted task leaves the list'); // held id missing from all → gone

// task_detail_test.dart — every task_card_test case except the tint ones, plus:
testWidgets('shows the stage and the report time'); // 'סדנאות · התייצבות ${ltr('15:00')}'
testWidgets('an untimed task says ללא שעה next to its stage');
testWidgets('late reads באיחור, done הושלמה, and a task due later today has no label'); // find.text('להיום') findsNothing
testWidgets('a task due in the half hour shows its time in orange');
testWidgets('an assignee with a phone gets a call button'); // task-detail-call-m1 → '0501234567'

// task_sheet_test.dart — the sheet in a Stack filling a Scaffold body, Size(400, 1000)
testWidgets('opens at half the height'); // tester.getTopLeft(find.byKey(const Key('task-sheet'))).dy closeTo 500 (±2)
testWidgets('what is above it stays tappable'); // a button at the top of the Stack still counts taps
testWidgets('the X closes it'); // tap task-sheet-close → onClose once
testWidgets('the back arrow shows only with onBack');
testWidgets('dragging it down closes it'); // drag task-sheet-handle by Offset(0, 600), pumpAndSettle → onClose once
testWidgets('new content starts at its top'); // scroll a long body, rebuild with another viewKey → its first line is visible

// task_results_list_test.dart
testWidgets('groups rows under their stage, with its time'); // results-stage-ws reads 'סדנאות · ${ltr('14:30–17:00')}', rows below in the given order
testWidgets('an empty list shows its text');
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd shavtzak && flutter test test/presentation/screens/task/row_hold_test.dart test/presentation/screens/task/widgets/`
Expected: compile errors for the new test files.

- [ ] **Step 3: Implement** the five files as described.

- [ ] **Step 4: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/presentation/screens/task/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 5: Commit** (`git add shavtzak/lib/presentation/screens/task shavtzak/test/presentation/screens/task`, message "feat(tasks): task view, low sheet and lists that hold still").

---

### Task 5: "המשימות שלי"

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/widgets/member_timeline.dart`
- Modify: `shavtzak/test/support/sample_event.dart` (the sample members and tasks)
- Test: `shavtzak/test/presentation/screens/task/widgets/member_timeline_test.dart`

**Interfaces:**
- Consumes: Task 1 (`timelineAnchor`, `foldedStageIds`, `currentStages`, `stageSpan`, `dayLabel`, `stageTimeLabel`, `ltr`), Task 2 (`EventTaskBoard`, `lateTasks`, `hebrewCount`), Task 3 (`TaskStyle`); `stagesToShow`, `sortTasks`.
- Produces:

```dart
class MemberTimeline extends StatefulWidget {
  const MemberTimeline({super.key, required this.board, required this.viewerId, required this.now,
      required this.canTick, required this.onOpenTask, required this.onOpenStage,
      required this.onSetComplete, required this.onToggleSubtask, required this.onOpenMyLate,
      required this.onShowAllStages, this.bottomPadding = 0});
  final EventTaskBoard board;
  final String viewerId;
  final DateTime now;
  final bool canTick; // false while previewing someone else
  final ValueChanged<TaskItem> onOpenTask;
  final ValueChanged<Stage> onOpenStage;
  final void Function(TaskItem task, bool isComplete) onSetComplete;
  final void Function(TaskItem task, Subtask subtask, bool isDone) onToggleSubtask;
  final VoidCallback onOpenMyLate;
  final VoidCallback onShowAllStages;
  final double bottomPadding; // room for an open sheet below the last stage
}
```

Keys: `my-late-banner`, `my-no-tasks`, `my-show-all`, `my-earlier-toggle`, `my-day-<yyyy-MM-dd>`, `my-stage-<stageId>`, `my-task-<taskId>`, `my-task-tick-<taskId>`, `my-subtask-<taskId>-<subtaskId>`.

Sample members and tasks, added to `sample_event.dart`:

```dart
final sDana = buildMember(id: 'm1', name: 'דנה', phoneNumber: '0501234567');
final sYoav = buildMember(id: 'm2', name: 'יואב');
TaskItem _task(String id, String title, Stage stage,
        {String? at, List<TeamMember> who = const [], bool done = false, List<Subtask> subtasks = const []}) =>
    buildTask(id: id, title: title, stage: stage, assemblyTime: at, event: sampleEvent,
        assigneeIds: [for (final m in who) m.id], assignees: who, isComplete: done, subtasks: subtasks);
final tSetupDone = _task('setup-done', 'פריסת שילוט', stSetup, at: '08:00', who: [sDana], done: true);
final tLunchLate = _task('lunch-late', 'בדיקת מנות מיוחדות', stLunch, at: '13:00', who: [sDana]);
final tWsDone = _task('ws-done', 'הכנת מצגות לסדנה', stWorkshops, at: '14:00', who: [sDana], done: true);
final tWsTheirs = _task('ws-theirs', 'הקמת עמדת קפה', stWorkshops, at: '14:15', who: [sYoav]); // late
final tWsSoon = _task('ws-soon', 'הכנת חדר סדנה 2', stWorkshops, at: '15:00', who: [sDana, sYoav], subtasks: const [
  Subtask(id: 'a', title: 'חיבור מקרן', isDone: true),
  Subtask(id: 'b', title: 'סידור כיסאות במעגל'),
  Subtask(id: 'c', title: 'בדיקת מיקרופון'),
]);
final tWsLater = _task('ws-later', 'חלוקת ערכות למשתתפים', stWorkshops, at: '15:45', who: [sDana]);
final tWsUntimed = _task('ws-untimed', 'החזרת ציוד הסדנה למחסן', stWorkshops, who: [sDana]);
final tDinner = _task('dinner-guests', 'קבלת אורחים בכניסה', stDinner, at: '19:00', who: [sDana, sYoav]);
final sampleTasks = [tSetupDone, tLunchLate, tWsDone, tWsTheirs, tWsSoon, tWsLater, tWsUntimed, tDinner];
EventTaskBoard sampleBoard({List<TaskItem>? tasks, List<Stage>? stages}) =>
    eventTaskBoard(sampleEvent, stages: stages ?? sampleStages, tasks: tasks ?? sampleTasks);
```

What it shows (spec §5, plus these rules):
- **Taken once, when the widget is created** (and again only if that stage disappears from `board`): the opening stage `timelineAnchor(board.stages, now)` and the folded set `foldedStageIds`. The opening stage carries the full rows and `hebrewCount(open, one: 'פתוחה אחת שלך', many: 'פתוחות שלך')` (left out at 0). So time passing never re-folds or reshapes the list.
- **Live with `now`**: the highlight box (`currentLight`, inset border) sits on `timelineAnchor(board.stages, now)`; "עכשיו" (a blue pill) on every stage in `currentStages`; "השלב הבא" on the first timed stage, in screen order, that has not started.
- A `CustomScrollView`: on top the late banner (when any of the viewer's tasks is late, from any stage), then the no-tasks note (when the viewer has no task in the event), then the fold line while folded, then one `SliverMainAxisGroup` per day with a pinned day header (`dayLabel`) and its stages in screen order; folded stages are left out while folded.
- A stage row: the time column on the start side (`timeColumnWidth`, left-to-right, start over end), a rail (2 px line; a node per stage: ring in `current` on the highlighted stage, filled `done` when all of the viewer's tasks there are done, grey otherwise), then the content.
  - The opening stage: kicker ("עכשיו" or "השלב הבא" as above), title, open count, place; full rows: the tick box (`my-task-tick-<id>`, enabled iff `canTick`) for a task without subtasks, otherwise its subtasks as tickable lines under the title (`my-subtask-…`) with `ltr('d/n')`; the title; "עם <the other assignees, comma-separated>"; the time column `ltr(HH:mm)` over "התייצבות", or "ללא שעה".
  - Any other stage holding the viewer's tasks: kicker when live rules give one, title, `hebrewCount(n, one: 'משימה אחת שלך', many: 'משימות שלך')`, place; compact rows (time column, title, "עם …", grey and struck through when done; no tick box).
  - A stage with none of the viewer's tasks: one line — title, place, "אין לך משימות" — with its time in the time column.
- Fold line: `'${hebrewCount(n, one: 'שלב קודם אחד', many: 'שלבים קודמים')} · ${hebrewCount(m, one: 'משימה אחת שלך הושלמה', many: 'משימות שלך הושלמו')}'`, m being the viewer's done tasks in the folded stages; the part after " · " is left out when the viewer has no task there. A tap opens or closes the fold (`'toggle:myEarlierStages'`).
- Banner, one line with ellipsis, `lateLight` with `lateDark`: one late task reads `'משימה שלך באיחור · <task> · <stage>, ${ltr(HH:mm)}'` (no ", time" when untimed) and calls `onOpenTask`; several read `'$n משימות שלך באיחור'` and call `onOpenMyLate`.
- No-tasks note: 'אין לך משימות באירוע זה' and a text button 'לכל השלבים' (`my-show-all`) → `onShowAllStages`.
- A task row → `onOpenTask`; a stage header or one-line stage → `onOpenStage`. No filter bar.

- [ ] **Step 1: Write the failing tests** (`sampleBoard()`, `sampleNow`, viewer `'m1'`, phone size)

```dart
testWidgets('opens on the current stage, earlier stages folded into one line'); // '2 שלבים קודמים · משימה אחת שלך הושלמה'; find.text('הקמה') findsNothing; 'עכשיו' inside my-stage-ws
testWidgets('today\'s untimed stage stays out of the fold'); // my-stage-rooms with 'אין לך משימות'
testWidgets('opening the fold shows the earlier stages in their place'); // tap my-earlier-toggle → 'הקמה' above 'סדנאות'
testWidgets('the current stage shows my open count and full rows'); // '3 פתוחות שלך'; tap my-task-tick-ws-later → onSetComplete(ws-later, true)
testWidgets('a task with subtasks lists them, tickable'); // tap my-subtask-ws-soon-b → (ws-soon, b, true); ltr('1/3')
testWidgets('rows run by report time, untimed last'); // dy: ws-done < ws-soon < ws-later < ws-untimed; 'התייצבות' and ltr('15:00') in my-task-ws-soon; 'ללא שעה' in my-task-ws-untimed
testWidgets('a done task stays in place, struck through'); // ws-done title lineThrough
testWidgets('other assignees read עם …'); // 'עם יואב' in my-task-ws-soon
testWidgets('the next stage reads השלב הבא and its tasks are compact'); // my-stage-dinner: 'השלב הבא', 'משימה אחת שלך'; my-task-tick-dinner-guests findsNothing
testWidgets('a stage without my tasks is one line'); // my-stage-bf with 'אין לך משימות'
testWidgets('day headers name the weekday, and today'); // 'שלישי 20/10 · היום', 'רביעי 21/10'
testWidgets('one late task of mine is named in a one-line banner that opens it'); // my-late-banner has 'בדיקת מנות מיוחדות' and 'ארוחת צהריים, ${ltr('13:00')}'; tap → onOpenTask(lunch-late)
testWidgets('several late tasks are counted and open the list'); // plus an unfinished 08:30 setup task of m1 → '2 משימות שלך באיחור'; tap → onOpenMyLate
testWidgets('with no tasks of mine, a note points to כל השלבים above the stages'); // viewer 'm9': my-no-tasks; tap my-show-all → onShowAllStages
testWidgets('time passing moves the highlight and the captions, not the fold or the rows'); // rebuild at Tuesday 17:30: no 'עכשיו' in my-stage-ws; 'השלב הבא' in my-stage-dinner; the fold line unchanged; my-task-tick-ws-later still there
testWidgets('before the event it opens on the first stage, captioned השלב הבא'); // now 2026-10-19 10:00: no fold line; 'השלב הבא' in my-stage-setup
testWidgets('tapping a task opens it, tapping a stage line opens the stage');
testWidgets('with canTick off nothing ticks'); // every Checkbox's onChanged isNull
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd shavtzak && flutter test test/presentation/screens/task/widgets/member_timeline_test.dart`
Expected: compile errors (`MemberTimeline` does not exist).

- [ ] **Step 3: Implement** `member_timeline.dart` as described.

- [ ] **Step 4: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/presentation/screens/task/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 5: Commit** (`git add shavtzak/lib/presentation/screens/task/widgets/member_timeline.dart shavtzak/test/support/sample_event.dart shavtzak/test/presentation/screens/task/widgets/member_timeline_test.dart`, message "feat(tasks): the member's task timeline").

---

### Task 6: The event screen's new frame, with "המשימות שלי" live — then stop

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/task_screen_actions.dart`, `.../task/widgets/legacy_stage_list.dart` (temporary; deleted in Task 10), `shavtzak/test/support/event_tasks_harness.dart`
- Modify: `shavtzak/lib/presentation/screens/task/event_tasks_screen.dart` (rebuilt around the same `EventTasksScreen({eventId, clock, importFiles})`)
- Delete: `shavtzak/lib/presentation/screens/task/widgets/task_filter_modal.dart`, and the `'task filter'` group in `shavtzak/test/presentation/screens/task/widgets/task_dialogs_test.dart`
- Test: `shavtzak/test/presentation/screens/task/event_tasks_screen_test.dart` (rewritten)

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces:

```dart
/// The tasks screen's actions, unchanged from today's screen: each sends one
/// TaskBloc event and reports a failure in a red snackbar.
mixin TaskScreenActions<T extends StatefulWidget> on State<T> {
  DateTime get actionTime; // the screen's ticking "now"
  TaskImportFiles get importFiles;
  Future<CrudActionResult> sendTaskEvent(TaskEvent Function(CrudActionCompleter completion) build);
  Future<void> dispatchTaskEvent(TaskEvent Function(CrudActionCompleter completion) build);
  Future<void> createStage(Event event, TeamMember user);
  Future<void> editStage(Stage stage, Event event, TeamMember user);
  Future<void> deleteStage(Stage stage, int taskCount);
  Future<void> createTask(Event event, Stage stage, TeamMember user);
  Future<void> editTask(TaskItem task, Event event, Stage stage, TeamMember user);
  Future<void> deleteTask(TaskItem task);
  Future<void> editUpdate(TaskItem task);
  void toggleSubtask(TaskItem task, Subtask subtask, bool isDone);
  void setComplete(TaskItem task, bool isComplete);
  Future<void> callPhone(String phone);
  Future<void> importFromExcel(Event event, TeamMember user);
  void downloadTemplate(Event event);
}

// test/support/event_tasks_harness.dart
const phoneSize = Size(400, 1000);
const wideSize = Size(1280, 900);
class EventTasksHarness {
  EventTasksHarness(this.repository, this.bloc);
  final FakeTaskRepository repository;
  final TaskBloc bloc;
  Future<void> deliver(WidgetTester tester, TaskBoard board); // add to the stream, pump twice
}
/// Pumps `/tasks/<eventId>` under a GoRouter whose `/tasks` route shows the
/// text 'רשימת האירועים'. [assignees] defaults to every member of [board] on 'e1'.
Future<EventTasksHarness> pumpEventTasks(WidgetTester tester, {required TeamMember user,
    DateTime Function()? clock, Size size = phoneSize, TaskBoard? board,
    Map<String, List<TeamMember>>? assignees, FakeTaskRepository? repository,
    FakeTaskImportFiles? importFiles, ThemeData? theme, String eventId = 'e1'});
```

Keys: new `tasks-search-open`, `tasks-search`, `tasks-search-close`, `tab-mine`, `tab-all` (on the segment labels), `view-as`; kept `tasks-back`, `tasks-retry`, `tasks-unknown-back`, `stage-add`, `tasks-import`, `tasks-import-template`.

How the frame behaves:
- State: `_tab` (mine or all), chosen on the first build that has the user: "כל השלבים" when `canManageTasks(user)`, else "המשימות שלי"; `_sheet` (`SheetView?`); `_searching` and `_query`; `_rowHold`; `_viewAsId` (debug preview); `_sheetController`; `_now` and today's minute ticker.
- App bar: the event's name as the title; `actions: [search, back]`, so the back arrow (`Icons.arrow_forward`, mirrored) stays on the far left with search beside it. While searching, the title is a `TextField` (`tasks-search`, `createRtlCursorFixedFocusNode`, autofocus, hint 'חיפוש משימה או אדם...', `SearchActionLogger('tasks')` as today) and the search icon turns into `tasks-search-close`. A non-blank query shows `ResultsView(ResultsKind.search, query: q)`; a blank one closes a search sheet; close clears the query, leaves search and closes a search sheet.
- Tabs: a `SegmentedButton` under the app bar, "המשימות שלי" | "כל השלבים", with today's explicit selected colours (`AppTheme.primaryDark`, white). Switching tabs leaves the sheet as it is; the tab's content is rebuilt, so the timeline opens on the current stage again.
- Body: a `Stack` of the tab's content and, while `_sheet` is set, a `TaskSheet`. While the sheet is open the content gets `bottomPadding` = body height × `sheetInitialSize`.
- "המשימות שלי": 'אין עדיין שלבים לאירוע זה' when the event has no stages; else `MemberTimeline(key: ValueKey(viewerId), viewerId: _viewAsId ?? user.id, canTick: viewer == user, …)`. **Debug preview** (for this checkpoint; release builds never show it): when `kDebugMode && canManageTasks(user)`, a row above the timeline, 'תצוגה בתור: <name>' (`view-as`), opens a `SimpleDialog` of the user and the members holding a task in this event, by name. While someone else is chosen the timeline is read-only.
- "כל השלבים", until Task 10: today's empty state (with import and template for managers) when there are no stages, else `LegacyStageList` — today's `ListView` of `StageCard`s with `TaskCard`s, every stage and task, its fold sets as its own state, the same callbacks as today. The 'שלב חדש' FAB shows on this tab for managers.
- Sheet content per view (`SheetContent`):
  - `TaskView`: header the task's title; body `TaskDetail` wired to the mixin; `onBack` when `back` is set.
  - `ResultsView(search)`: header `'חיפוש: "<q>" · <n>'`; body `TaskResultsList` over `stagesToShow(stages: board.stages, visibleTasks: _rowHold.rows(view, matching: sortTasks(filterTasks(board.tasks, now: _now, query: q)), all: board.tasks), showEveryStage: false)`; rows are `TaskRow` (tick iff `canUpdateTaskProgress`); a row opens `TaskView(id, back: view)`.
  - `ResultsView(myLate)`: header `'$n משימות שלך באיחור'`, the viewer's `lateTasks`, laid out the same way.
  - `StageView` (until Task 8): header the stage's title; body its tasks as `TaskRow`s.
  - A view whose task or stage no longer exists shows its `back` (or nothing), and `_sheet` is corrected after the frame.
- Closing the sheet clears `_rowHold`. Logged actions: `'tap:tasksSearch'`, `'tap:tasksSearchClose'`, `'toggle:tasksTab'`, `'open:taskSheet'` (`{'view': kind}`), `'close:taskSheet'`, `'tap:viewAs'`.

- [ ] **Step 1: Move the actions and the old list out, behaviour unchanged**

Move today's action methods from `_EventTasksScreenState` into `TaskScreenActions` (bodies unchanged, names as above), and the `ListView.builder` of `StageCard`s from `_buildBody` into `LegacyStageList`. Run: `cd shavtzak && flutter test test/presentation/screens/task/`. Expected: today's tests still pass.

- [ ] **Step 2: Write the failing tests**

Today's `pumpScreen` becomes `pumpEventTasks` in the harness. The old fixture at the top of the test file (`event`, `arrival`, `mine`, `theirs`, `withSubtasks`, `dana`, `yoav`) stays. Groups:

```dart
group('loading'); // port: spinner until the first board; a load failure offers a retry that subscribes again
group('tabs', () {
  testWidgets('a plain member lands on המשימות שלי'); // find.byType(MemberTimeline)
  testWidgets('an admin, and a member allowed to manage tasks, land on כל השלבים'); // find.byType(LegacyStageList), for isAdmin and for canManageTasks
  testWidgets('every member can open both tabs');
  testWidgets('the selected tab is readable under the app theme'); // port the contrast test (≥ 4.5)
});
group('search', () {
  testWidgets('the search icon opens a field with the RTL caret fix'); // TextField(tasks-search).focusNode isA<RtlCursorFixedFocusNode>
  testWidgets('typing lists the matches in the sheet, grouped by stage'); // 'אוטובוס' → task-sheet, 'חיפוש: "אוטובוס" · 1', task-row-mine
  testWidgets('it finds tasks by an assignee\'s name'); // 'יואב' → task-row-theirs
  testWidgets('closing the search closes its sheet');
});
group('sheet', () {
  testWidgets('a task opened from my timeline shows its detail, and X closes it'); // my-task-mine → task-detail-mine; task-sheet-close → task-sheet findsNothing
  testWidgets('back returns to the list the task came from'); // search → row → detail → task-sheet-back → the results header again
  testWidgets('a task deleted while open goes back to its list'); // deliver a board without it → the results show; tester.takeException() isNull
  testWidgets('the late banner opens my late tasks'); // two late tasks of dana → tap my-late-banner → '2 משימות שלך באיחור'
});
group('actions'); // port, reaching the task through my timeline and the sheet: ticking a subtask is sent; completing a task is sent; a ticked task and a ticked subtask show done before the backend answers; a refused tick is taken back and explained; saving an update sends the text; a failed action shows the backend message and keeps the list; delete asks first and cancelling deletes nothing; confirming sends it; a refused delete stays open and says why; a manager edits a task through the form.
group('until the calendar lands'); // port through LegacyStageList: a manager creates a task through the form; adds a stage (stage-add); edits a stage; deleting a stage warns that its tasks go too
group('excel import'); // port as is
group('event'); // port: an unknown or non-דו יומי event says so; the back arrow returns to the list; the test-environment banner in test mode only
testWidgets('the debug preview shows a member\'s timeline, read-only'); // admin → view-as → 'דנה' → my-task-mine shown; its Checkbox onChanged isNull
```

Today's groups 'mine / all', 'search and filter', 'folds', 'ordering' and the stage-list half of 'event and stages' are dropped: they test screens this redesign replaces.

- [ ] **Step 3: Run them to see them fail**

Run: `cd shavtzak && flutter test test/presentation/screens/task/event_tasks_screen_test.dart`
Expected: FAIL — no tabs by role, no search icon, no `MemberTimeline`.

- [ ] **Step 4: Implement the frame** as described; delete `task_filter_modal.dart` and its test group.

- [ ] **Step 5: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/presentation/screens/task/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 6: Commit** (`git add shavtzak/lib/presentation/screens/task shavtzak/test/support shavtzak/test/presentation/screens/task`, then `git add -u shavtzak` for the deletions, message "feat(tasks): new event screen frame with the member timeline").

- [ ] **Step 7: Stop — the user tries "המשימות שלי"**

Tell the user, naming the worktree `tasks-screens-redesign` and its full path: run `flutter run -d chrome` from its `shavtzak/` folder and open `#/tasks/<eventId>`; as a manager, "תצוגה בתור" shows any member's timeline (read-only, local runs only); Chrome's device toolbar gives a phone-sized window; "כל השלבים" still shows today's list. Do not run the app yourself. Wait for their verdict; timeline changes go into Task 5's widget and tests before Task 7.

---

### Task 7: The events list, and `/tasks` opening the nearest event

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/tasks_auto_open.dart`
- Modify: `shavtzak/lib/presentation/screens/task/tasks_screen.dart`; `event_tasks_screen.dart` (spend the flag in `initState`; delete `taskEventDates` and its `DateFormat`); `shavtzak/lib/core/utils/task_utils.dart` (delete `TaskEventSummary`, `summarizeTaskEvent`)
- Test: `shavtzak/test/presentation/screens/task/tasks_screen_test.dart` (rewritten), `shavtzak/test/core/utils/task_utils_test.dart` (drop the `summarizeTaskEvent` group), `event_tasks_screen_test.dart` (one test)

**Interfaces:**

```dart
/// Whether `/tasks` should still open straight into the nearest event. True
/// until a tasks screen has been shown once in this app session, so coming
/// back to the list (back arrow or browser back) never bounces into an event.
abstract final class TasksAutoOpen {
  static bool get isPending;
  static void spend();
  @visibleForTesting
  static void debugReset();
}
```

Keys: kept `task-event-<id>`, `tasks-past-toggle`, `tasks-home`, `tasks-retry`; new `task-event-live-<id>`.

Behaviour:
- `TasksScreen`, on the first `TasksLoaded` build while `TasksAutoOpen.isPending`: spend it; when `taskEvents(...).upcoming` is not empty, keep the spinner and, after the frame, `context.go('$prefix/tasks/<first id>')` (`Logger.action('auto:openNearestTaskEvent')`). Otherwise, and on every later build, the list. A sign-in that restores `/tasks` lands on this same first build, so it opens the event too; `AppRouter` does not change.
- `EventTasksScreen.initState` spends it as well, so back from a directly linked event shows the list.
- A row: the name with a 'מתקיים עכשיו' pill (`TaskStyle.current`, white text) when `isEventUnderWay`; `eventDaysLabel(event)`; the place. No counts. Sections, folding, order, home, loading, error and the test banner as today. On a window wider than `readableWidth` the list is centred at that width.

- [ ] **Step 1: Write the failing tests** (`setUp(TasksAutoOpen.debugReset)`; today's fixture and `pumpList`, now `Oct 11 14:00`)

```dart
testWidgets('opens the nearest event that has not ended, straight away'); // events [south, past, north, other, running] → find.text('event:running')
testWidgets('stays on the list when nothing is coming up'); // [past, other] → 'אין אירועי דו יומי קרובים'
testWidgets('coming back does not bounce into the event again'); // TasksAutoOpen.spend() first → the list; find.text('event:running') findsNothing
testWidgets('lists every upcoming event nearest first, and nothing but events'); // order running, north, south; find.textContaining('משימות') and find.textContaining('שלבים') findsNothing
testWidgets('a row shows the weekdays, the dates and the place'); // in task-event-north: 'שלישי–רביעי, ${ltr('20–21/10')}' and 'מלון קיסר'
testWidgets('the event under way is marked מתקיים עכשיו'); // task-event-live-running; no task-event-live-north
testWidgets('on a wide window the list is centred at a readable width'); // wideSize: width of task-event-north ≤ TaskStyle.readableWidth
// ported, with TasksAutoOpen.spend() first: past events wait folded, latest first; pressing an event opens its screen; the home button; a retry after a failure; the test banner
```

In `event_tasks_screen_test.dart`: `'opening an event spends the auto-open'` — after `pumpEventTasks`, `TasksAutoOpen.isPending` is false.

- [ ] **Step 2: Run them to see them fail**

Run: `cd shavtzak && flutter test test/presentation/screens/task/tasks_screen_test.dart`
Expected: compile errors (`TasksAutoOpen` does not exist).

- [ ] **Step 3: Implement** as described; delete `taskEventDates`, `TaskEventSummary` and `summarizeTaskEvent`, and their tests.

- [ ] **Step 4: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/presentation/screens/task/ test/core/utils/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 5: Commit** (`git add` the changed files, message "feat(tasks): /tasks opens the nearest event; the list shows events only").

---

### Task 8: The stage in the sheet

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/widgets/stage_sheet_view.dart`
- Modify: `event_tasks_screen.dart` (`StageView` content)
- Test: `shavtzak/test/presentation/screens/task/widgets/stage_sheet_view_test.dart`, `event_tasks_screen_test.dart` (group 'stage sheet')

**Interfaces:**

```dart
class StageSheetHeader extends StatelessWidget {
  const StageSheetHeader({super.key, required this.stage, required this.canManage,
      required this.onEdit, required this.onDelete});
}
class StageSheetBody extends StatelessWidget {
  const StageSheetBody({super.key, required this.stage, required this.rows, required this.progress,
      required this.missingOnly, required this.onSwitch, required this.rowBuilder,
      required this.canManage, required this.onAddTask, required this.onCallPhone});
  final Stage stage;
  final List<TaskItem> rows; // already held by the frame
  final TaskProgress progress; // the whole stage, live
  final bool missingOnly;
  final ValueChanged<bool> onSwitch; // true = missing only
  final Widget Function(TaskItem task) rowBuilder;
  final bool canManage;
  final VoidCallback onAddTask;
  final ValueChanged<String> onCallPhone;
}
```

Keys: `stage-sheet-<id>` (the body), `stage-switch` (`SegmentedButton<bool>`), `stage-done-count-<id>`; kept from `StageCard`: `stage-edit-<id>`, `stage-delete-<id>`, `stage-add-task-<id>`, `stage-contact-call-<contactId>`.

Behaviour:
- Header: the title, then `stageSummaryLine(stage)`; for managers the blue pencil and red bin of today.
- Body, each part only when it has something: the notes (sticky-note icon); 'דרישות מהמלון ולוגיסטיקה' and the requirements; 'אנשי קשר' with a call button per contact phone, as `StageCard` does today. Then, when the stage has tasks: the switch 'חסרות (missing)' | 'הכל (total)' and `'${ltr('$done/$total')} הושלמו'`, the rows, and for managers 'משימה חדשה' (`stage-add-task-<id>`). A stage without tasks: 'אין עדיין משימות בשלב זה', no switch, and 'משימה חדשה' for managers.
- The frame: rows = `_rowHold.rows(view, matching: missingOnly ? the stage's unfinished tasks : all of them, all: the stage's tasks)`; the switch replaces the view with `StageView(id, missingOnly: x)`; the pencil, bin and 'משימה חדשה' call the mixin; a row opens `TaskView(id, back: view)`; a view whose stage is gone closes the sheet.

- [ ] **Step 1: Write the failing tests**

```dart
// stage_sheet_view_test.dart — stWorkshops with notes 'להגיע חצי שעה לפני', requirements '60 מקומות',
// contacts [StageContact(id: 'c1', name: 'רונית', phone: '0500000000', role: 'מנהלת אירועים'), StageContact(id: 'c2', name: 'משה')]
testWidgets('the header shows the title, the day, the time and the place'); // 'סדנאות', stageSummaryLine(stage)
testWidgets('only managers get edit and delete');
testWidgets('notes, hotel requirements and contacts show, with a call button per phone'); // tap stage-contact-call-c1 → '0500000000'; no stage-contact-call-c2
testWidgets('the switch reads חסרות (n) | הכל (m) and reports the other side'); // 'חסרות (4)', 'הכל (5)'; tap 'הכל (5)' → onSwitch(false)
testWidgets('shows how many are done'); // '${ltr('1/5')} הושלמו'
testWidgets('lists the rows it is given, in that order');
testWidgets('managers get משימה חדשה'); // → onAddTask
testWidgets('a stage without tasks says so, with no switch');

// event_tasks_screen_test.dart, group 'stage sheet' (sampleBoard, clock sampleNow)
testWidgets('tapping a stage in my timeline opens it in the sheet'); // my-stage-ws header → stage-sheet-ws
testWidgets('a row ticked in חסרות stays, struck through, until the view changes'); // open ws, tap 'חסרות (4)', tick task-row-tick-ws-later → row still there, struck through; 'חסרות (3)'; tap 'הכל (5)' then 'חסרות (3)' → task-row-ws-later findsNothing
testWidgets('a manager edits and deletes the stage from the sheet'); // stage-edit-ws → the form; stage-delete-ws → 'יימחקו גם 5 המשימות שבו'
testWidgets('a manager adds a task from the stage'); // stage-add-task-ws → form → save → repository.calls has 'insert:<title>'
testWidgets('the sheet closes when its stage is deleted'); // deliver a board without ws → task-sheet findsNothing; tester.takeException() isNull
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd shavtzak && flutter test test/presentation/screens/task/widgets/stage_sheet_view_test.dart test/presentation/screens/task/event_tasks_screen_test.dart`
Expected: compile errors, and the frame's stage tests failing.

- [ ] **Step 3: Implement** `stage_sheet_view.dart` and wire `StageView` in the frame.

- [ ] **Step 4: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/presentation/screens/task/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 5: Commit** (message "feat(tasks): the stage in the low sheet").

---

### Task 9: The day calendar

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/widgets/stage_block.dart`, `.../task/widgets/day_calendar.dart`
- Test: `shavtzak/test/presentation/screens/task/widgets/day_calendar_test.dart`

**Interfaces:**
- Consumes: Task 1 (`layoutDay`, `calendarHours`, `dayLabel`, `stageTimeLabel`), Task 2 (`TaskProgress`), Task 3 (`TaskStyle`, `ProgressStrip`, `StageCountButton`).
- Produces:

```dart
class StageBlock extends StatelessWidget {
  const StageBlock({super.key, required this.stage, required this.progress, required this.mineCount,
      required this.isCurrent, required this.isOutlined, required this.isFaded, required this.height,
      required this.onOpen, required this.onOpenMissing});
  final Stage stage;
  final TaskProgress progress;
  final int mineCount;
  final bool isCurrent, isOutlined, isFaded;
  final double height;
  final VoidCallback onOpen, onOpenMissing;
}
class DayCalendar extends StatelessWidget {
  const DayCalendar({super.key, required this.days, required this.stagesByDay,
      required this.progressByStage, required this.mineByStage, required this.currentStageIds,
      required this.now, required this.hourHeight, this.outlinedStageIds = const {},
      this.fadeOthers = false, this.focusStageId, this.focusKey, required this.onOpenStage});
  final List<DateTime> days; // one on phones; up to TaskStyle.maxSideBySideDays side by side
  final Map<DateTime, List<Stage>> stagesByDay;
  final Map<String, TaskProgress> progressByStage;
  final Map<String, int> mineByStage;
  final Set<String> currentStageIds;
  final DateTime now;
  final double hourHeight;
  final Set<String> outlinedStageIds;
  final bool fadeOthers;
  final String? focusStageId; // that block carries focusKey, so a parent can scroll to it
  final GlobalKey? focusKey;
  final void Function(Stage stage, {required bool missingOnly}) onOpenStage;
}
```

Keys: `stage-block-<id>`, `stage-count-<id>`, `stage-mine-<id>`, `now-line`, `all-day-row`, `day-column-<yyyy-MM-dd>`, `day-header-<yyyy-MM-dd>` (with several days).

Behaviour:
- `DayCalendar` is a box that does not scroll; its parent scrolls it. Top: the all-day row (only when some shown day has untimed stages) of compact `StageBlock`s, `minBlockHeight` tall, wrapping. Then the hour grid from `calendarHours(the shown stages, minBlockMinutes: TaskStyle.minBlockMinutes(hourHeight))`: hour labels (`HH`) in a `hourLabelWidth` column on the start side, a thin line per hour, and per day a column of its `layoutDay` blocks. A block's top is `(startMinute − first × 60) / 60 × hourHeight`, its height `(endMinute − startMinute) / 60 × hourHeight` and never below `minBlockHeight`, its width the column's share by `columnCount`, column 0 on the start side. With several days a header row of `dayLabel`s sits above the columns, which share one axis. No timed stage: no grid.
- The now line: in the column of now's day, when now is inside the grid, a 2 px `TaskStyle.late` line across the column and `ltr(HH:mm)` in a red pill in the label column.
- `StageBlock`: background `doneLight` when it has tasks and none missing, else `currentLight` when current, else white; a 3 px `late` edge on the start side when any task is late; an outline (`outlineWidth`, `mine`) when outlined; `Opacity(fadedOpacity)` when faded. Content: the title (one line, two when tall, ellipsis); `'<place> · <time range>'` from `blockDetailsMinHeight`; `ProgressStrip` from `blockProgressMinHeight`; at the end of the title line the mine badge (person icon and the count, `mine`) when `mineCount > 0`, then `StageCountButton`. The button → `onOpenMissing`; anywhere else on the block → `onOpen`.

- [ ] **Step 1: Write the failing tests** (sample stages; progress from `taskProgress(sampleBoard().tasksOf(id), sampleNow)`; `hourHeight: 56`; Size(400, 1600))

```dart
testWidgets('a stage sits at its start and is as tall as it lasts'); // the grid starts at 08: ws top − grid top == 6.5 × 56; height == 2.5 × 56
testWidgets('a stage without an end gets the smallest readable height'); // dinner height == TaskStyle.minBlockMinutes(56) / 60 × 56
testWidgets('a stage without a time sits in the all-day row, above the hours'); // stage-block-rooms inside all-day-row; above stage-block-setup
testWidgets('overlapping stages share the width side by side'); // two overlapping stages: equal widths, half the column; the first on the right
testWidgets('the now line shows on today with the time, and not on another day'); // now-line and ltr('14:40'); days [sampleWed] → now-line findsNothing
testWidgets('the count names what is missing, coloured by the worst case'); // ws '4 חסרות' lateDark; lunch '1 חסרה' lateDark; dinner '1 חסרה' neutralText; setup a tick and ltr('1/1'); no stage-count-rooms
testWidgets('done stages are green, the current one blue, a late task gives a red edge'); // setup doneLight; ws currentLight with the late edge; dinner white
testWidgets('a stage with my tasks carries my count'); // stage-mine-ws reads '4'
testWidgets('the count opens the missing tasks, the block all of them'); // stage-count-ws → (ws, missingOnly: true); the block's title → (ws, missingOnly: false)
testWidgets('the outlined stage stands out and the rest fade'); // outlined {'ws'}, fadeOthers → an Opacity(0.35) above stage-block-lunch and none above ws
testWidgets('a long title in a narrow overlapping column ends in an ellipsis'); // Size(320, 800), three 10:00–12:00 stages with 60-character titles → tester.takeException() isNull
testWidgets('two days side by side share one hour axis'); // days [Tue, Wed] with an 08:00 stage on each → equal dy; day-header-2026-10-20 reads 'שלישי 20/10 · היום'
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd shavtzak && flutter test test/presentation/screens/task/widgets/day_calendar_test.dart`
Expected: compile errors.

- [ ] **Step 3: Implement** both widgets as described.

- [ ] **Step 4: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/presentation/screens/task/widgets/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 5: Commit** (message "feat(tasks): the stage day calendar").

---

### Task 10: "כל השלבים" on phones

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/widgets/event_summary.dart`, `.../task/widgets/task_filter_bar.dart`, `.../task/widgets/assignee_check_line.dart`, `.../task/widgets/calendar_tab.dart`
- Modify: `event_tasks_screen.dart`
- Delete: `widgets/legacy_stage_list.dart`, `widgets/stage_card.dart`, `widgets/task_card.dart`, and `test/presentation/screens/task/widgets/stage_card_test.dart`, `task_card_test.dart`
- Test: `shavtzak/test/presentation/screens/task/widgets/task_filter_bar_test.dart`, `event_tasks_screen_test.dart` (groups 'calendar', 'filters', 'assignee check'; the 'until the calendar lands' group goes)

**Interfaces:**

```dart
enum TaskFilter { late, dueSoon }
class TaskFilterBar extends StatelessWidget {
  const TaskFilterBar({super.key, required this.lateCount, required this.soonCount,
      required this.active, required this.onChanged});
  final int lateCount, soonCount;
  final TaskFilter? active;
  final ValueChanged<TaskFilter?> onChanged;
}
class EventSummary extends StatelessWidget {
  const EventSummary({super.key, required this.event, required this.progress});
}
class AssigneeCheckLine extends StatelessWidget {
  const AssigneeCheckLine({super.key, required this.count, required this.onTap, this.wide = false});
}
/// The phone's calendar tab: [top] scrolls away; [filterBar] and the day
/// tabs stay pinned; [calendar] scrolls under them.
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key, required this.top, required this.filterBar, required this.days,
      required this.selectedDay, required this.now, required this.onSelectDay,
      required this.calendar, this.focusKey, this.focusRequest = 0, this.bottomPadding = 0});
  final Widget top;
  final Widget filterBar;
  final List<DateTime> days;
  final DateTime selectedDay;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDay;
  final Widget calendar;
  final GlobalKey? focusKey; // the block to bring just under the pinned row
  final int focusRequest; // bumped by the frame each time it should scroll there
  final double bottomPadding;
}
```

Keys: `task-filter-bar`, `filter-late`, `filter-soon`, `event-summary`, `assignee-check`, `calendar-pinned`, `calendar-day-<yyyy-MM-dd>`.

Behaviour:
- `TaskFilterBar`: `FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart)` around one `Row`: `Icon(Icons.filter_list)`, 'סינון:', and two `FilterChip`s with `showCheckmark: true` — 'באיחור ($lateCount)' (selected: `lateLight` and `lateDark`) and 'התייצבות בחצי שעה הקרובה ($soonCount)' (`soonLight` and `soonDark`) — in `filterFontSize`. A chip with a zero count is disabled unless it is the active one. Choosing one reports it; choosing the active one reports null.
- `EventSummary`: `'${eventDaysLabel(event)} · <place>'`, a `ProgressStrip`, `'${ltr('done/total')} הושלמו'`.
- `AssigneeCheckLine`: one red line (warning icon), `hebrewCount(count, one: 'משימה אחת של מי שכבר לא משובץ לאירוע', many: 'משימות של מי שכבר לא משובץ לאירוע')`, with `'לבדיקה: '` before it when `wide`.
- `CalendarTab`: a `CustomScrollView` — `top`, then a pinned header (`calendar-pinned`) holding the filter bar and a row of day chips (`dayLabel`), then the calendar, then `bottomPadding`. When `focusRequest` changes it scrolls so the `focusKey` block's top sits `focusTopMargin` under the pinned header (`RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset` minus the pinned height, clamped).
- The frame, on "כל השלבים" when the event has stages:
  - `top`: `EventSummary(event, taskProgress(board.tasks, now))`, and for managers, once the assignees are loaded and `tasksWithRemovedAssignees` is not empty, `AssigneeCheckLine` → `ResultsView(removedAssignees)`.
  - `filterBar`: counts from `lateTasks` and `dueSoonTasks`; `active` is the late or due-soon results view the sheet is showing, directly or as a task's `back`; choosing opens that `ResultsView`, null closes the sheet.
  - Days `calendarDays(event, stages)`, starting on `initialCalendarDay` (taken once when the tab is built). Opening a stage, or a task, on another day switches the day; results never do.
  - `DayCalendar(days: [selected day], hourHeight: TaskStyle.hourHeight, …)`: outlined = the sheet's stage (a task's stage for `TaskView`) or the stages of its results; `fadeOthers` while the sheet is open; `onOpenStage` opens `StageView(id, missingOnly: …)` and bumps `focusRequest`.
  - Results sheets, each held through `_rowHold` and drawn with `TaskResultsList` and `TaskRow`: late — `'באיחור · ${hebrewCount(n, one: 'משימה אחת', many: 'משימות')}'`, under it 'מכל השלבים, הוותיקה ראשונה'; due soon — `'התייצבות בחצי שעה הקרובה · $n'`, under it 'מכל השלבים, הקרובה ראשונה'; removed assignees — the check line's wording, rows with `removedAssigneeIds`. `n` is the live count, not the held rows.
  - Assignees: for managers only, subscribe once to `context.read<TaskRepository>().watchEventAssignees(widget.eventId)` (cancelled in `dispose`); `_assignedIds` stays null until the first emission, and null means no check.
  - The 'שלב חדש' FAB shows for managers while no sheet is open.
- No stages: the empty state with import and template, as in Task 6.

- [ ] **Step 1: Write the failing tests**

```dart
// task_filter_bar_test.dart
testWidgets('stays one row on a 320 px phone'); // Size(320, 640): filter-late and filter-soon share a top dy; task-filter-bar height ≤ 48; takeException isNull
testWidgets('reads סינון: and each count'); // 'סינון:', 'באיחור (2)', 'התייצבות בחצי שעה הקרובה (1)'
testWidgets('a toggle with nothing in it is disabled, unless it is on'); // soonCount 0 → onSelected null; active dueSoon with 0 → enabled
testWidgets('the one that is on is filled and ticked'); // FilterChip.selected, showCheckmark
testWidgets('choosing reports it; choosing the active one reports none');

// event_tasks_screen_test.dart (sampleBoard, clock sampleNow, an admin unless said; assignees default to [sDana, sYoav])
group('calendar', () {
  testWidgets('a manager lands on the calendar with the summary'); // eventDaysLabel(sampleEvent) + ' · מלון רויאל'; '${ltr('2/8')} הושלמו'
  testWidgets('it opens on today during the event, on the first day before it'); // Wed 09:00 → calendar-day-2026-10-21 selected; Oct 11 → 2026-10-20
  testWidgets('a stage dated outside the event still gets its day'); // a stage on Oct 23 → calendar-day-2026-10-23
  testWidgets('tapping a block opens the stage low; the calendar stays visible and tappable'); // stage-block-ws → stage-sheet-ws; stage-block-lunch → stage-sheet-lunch, one task-sheet
  testWidgets('the opened stage sits just above the sheet'); // stage-block-ws: top ≥ bottom of calendar-pinned, bottom ≤ top of task-sheet
  testWidgets('the count opens חסרות, the block הכל'); // after stage-count-ws, SegmentedButton<bool>(stage-switch).selected == {true}
  testWidgets('the X closes the sheet, the outline and the fade'); // no Opacity(TaskStyle.fadedOpacity) left
  testWidgets('the FAB adds a stage for managers and steps aside while the sheet is open'); // port 'adds a stage'; stage-add findsNothing while open; never for dana
  testWidgets('an event without stages keeps the import empty state for managers'); // port
});
group('filters', () {
  testWidgets('switching one on lists its tasks from every stage, longest overdue first'); // filter-late → 'באיחור · 2 משימות', 'מכל השלבים, הוותיקה ראשונה'; results-stage-lunch above results-stage-ws
  testWidgets('the stages in the results are outlined'); // lunch and ws outlined, the rest faded
  testWidgets('one filter at a time'); // filter-late then filter-soon → late not selected; 'התייצבות בחצי שעה הקרובה · 1'
  testWidgets('closing the sheet switches the filter off');
  testWidgets('ticking a late task keeps its row while the count moves'); // tick task-row-tick-lunch-late → still there, struck through; 'באיחור (1)'
});
group('assignee check', () {
  testWidgets('managers see one red line when an assignee was taken off the event'); // assignees [sDana] → '3 משימות של מי שכבר לא משובץ לאירוע'
  testWidgets('nothing shows before the event\'s assignees have loaded'); // a FakeTaskRepository subclass whose watchEventAssignees never emits → assignee-check findsNothing
  testWidgets('members never see it'); // dana
  testWidgets('nothing to fix, no line'); // assignees [sDana, sYoav]
  testWidgets('tapping it lists those tasks, the removed assignee struck through'); // header as the line; find.text('כבר לא משובץ לאירוע') findsNWidgets(3)
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd shavtzak && flutter test test/presentation/screens/task/`
Expected: compile errors for the new widgets, and the calendar tests failing.

- [ ] **Step 3: Implement** the four widgets and the frame's calendar tab; delete the old list, `StageCard`, `TaskCard` and their tests.

- [ ] **Step 4: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test test/presentation/screens/task/ && flutter analyze && flutter test`
Expected: all green; analyze within the baseline.

- [ ] **Step 5: Commit** (with `git add -u shavtzak` for the deletions; message "feat(tasks): stage calendar, filters and assignee check on phones").

---

### Task 11: Wide screens (the part to drop if time runs short)

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/widgets/stage_task_table.dart`, `.../task/widgets/stage_panel.dart`
- Modify: `event_tasks_screen.dart`, `widgets/stage_sheet_view.dart` (`StageSheetBody` gains `tableBuilder`)
- Test: `shavtzak/test/presentation/screens/task/widgets/stage_task_table_test.dart`, `shavtzak/test/presentation/screens/task/event_tasks_wide_test.dart`

**Interfaces:**

```dart
class StageTaskTable extends StatelessWidget {
  const StageTaskTable({super.key, required this.tasks, required this.now, required this.viewerId,
      required this.canTick, required this.canManage, required this.removedAssigneeIds,
      required this.onSetComplete, required this.onOpen, required this.onEdit,
      required this.onDelete, required this.onCallPhone});
  final List<TaskItem> tasks; // drawn in the order given
  final DateTime now;
  final String viewerId;
  final bool Function(TaskItem task) canTick;
  final bool canManage;
  final List<String> Function(TaskItem task) removedAssigneeIds;
  final void Function(TaskItem task, bool isComplete) onSetComplete;
  final ValueChanged<TaskItem> onOpen, onEdit, onDelete;
  final ValueChanged<String> onCallPhone;
}
/// The wide layout's left panel: the sheet's content without the sheet.
class StagePanel extends StatelessWidget {
  const StagePanel({super.key, required this.content, required this.onClose, this.onBack});
  final SheetContent? content; // null shows the hint
}
// StageSheetBody: final Widget Function(List<TaskItem> rows)? tableBuilder; // set → the rows are drawn by it
```

Keys: `wide-toolbar`, `stage-panel`, `stage-panel-hint`, `stage-table`, `table-row-<id>`, `table-tick-<id>`, `table-edit-<id>`, `table-delete-<id>`.

Behaviour:
- A `LayoutBuilder` on the body: wide when `maxWidth ≥ TaskStyle.wideBreakpoint`, whatever the role.
- "כל השלבים", wide: `wide-toolbar` on top (`EventSummary` expanded, then `TaskFilterBar`; under them `AssigneeCheckLine(wide: true)` when there is something to fix); below, `Row(calendar (flex calendarFlex), VerticalDivider, StagePanel (flex panelFlex))` — under RTL the calendar is on the right and the panel on the left. The calendar scrolls on its own, `hourHeight: TaskStyle.wideHourHeight`, every day side by side when there are at most `maxSideBySideDays`, else the day chips and one day. Outlines as on phones; nothing fades.
- `StagePanel` shows the same `SheetView` the sheet would — stage, results, task — with a header row (back, title, X) and no drag handle; with nothing open, 'בחרו שלב בלוח כדי לראות את המשימות שלו'. In a stage, the rows are a `StageTaskTable`; contacts and requirements sit side by side above it (`Wrap`).
- `StageTaskTable`: a header row 'התייצבות' | 'משימה' | 'אחראים' | 'תת-משימות'; per task, a tick box when allowed, then the time `ltr(HH:mm)` (`soonDark` when due soon, `lateDark` when late) or 'ללא שעה'; the title with the "באיחור" mark, and under it the description and the update line; the assignee chips as in `TaskRow` (removed ones struck through in red with 'כבר לא משובץ לאירוע'); `ltr('d/n')` or '—'; for managers a pencil and a bin at the end, at opacity 0 until the row is hovered (`MouseRegion`), so a touch screen still reaches them. A click elsewhere opens `TaskView`.
- "המשימות שלי", wide: the phone layout centred at `readableWidth`, the phone sheet inside that column.

- [ ] **Step 1: Write the failing tests**

```dart
// stage_task_table_test.dart
testWidgets('has the four columns and keeps the given order, untimed last');
testWidgets('a row carries the tick box, the late mark, the orange time and the update line');
testWidgets('the pencil and the bin show on hover, for managers only'); // mouse gesture over table-row-ws-later → Opacity of table-edit-ws-later is 1; tap → onEdit
testWidgets('a removed assignee is struck through in red, with the note');

// event_tasks_wide_test.dart (wideSize, sampleBoard, clock sampleNow, an admin)
testWidgets('the days sit side by side and the panel waits on the left'); // day-header-2026-10-20 and -21; stage-panel-hint; the panel's dx < the calendar's dx
testWidgets('clicking a stage opens it in the panel as a table; it stays outlined and nothing fades'); // stage-table; no Opacity(TaskStyle.fadedOpacity)
testWidgets('the toolbar holds the summary, the filters and the check'); // assignees [sDana] → 'לבדיקה: 3 משימות של מי שכבר לא משובץ לאירוע'
testWidgets('filter, search and check results, and tasks, use the panel'); // filter-late → the panel reads 'באיחור · 2 משימות'; task-sheet findsNothing
testWidgets('more than three days fall back to day chips'); // a four-day event → calendar-day chips and a single day column
testWidgets('a member at this width gets the same layout and ticks their own tasks'); // dana on 'כל השלבים' → table-tick-ws-later → 'complete:ws-later:true'; table-tick-ws-theirs disabled
testWidgets('המשימות שלי stays a centred column of readable width'); // MemberTimeline width ≤ TaskStyle.readableWidth
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd shavtzak && flutter test test/presentation/screens/task/widgets/stage_task_table_test.dart test/presentation/screens/task/event_tasks_wide_test.dart`
Expected: compile errors.

- [ ] **Step 3: Implement** as described.

- [ ] **Step 4: Run the tests, then the whole check**

Run: `cd shavtzak && flutter test && flutter analyze`
Expected: all green; analyze within the baseline.

- [ ] **Step 5: Commit** (message "feat(tasks): wide layout with the stage panel and task table").

---

### Task 12: Finish and hand over

**Files:**
- Modify: `CLAUDE.md` (the TaskBloc paragraph, the route comments, the test count)

- [ ] **Step 1: Update CLAUDE.md**

In the TaskBloc paragraph: `/tasks` opens the nearest דו יומי event that has not ended (once per app session; back shows the list); the event screen has "המשימות שלי" (the member's task timeline) and "כל השלבים" (the stage day calendar with a low sheet; a side panel on wide screens); the rules live in `task_schedule.dart` and `task_progress.dart`, sizes and colours in `task_style.dart`. In the route tree, `/tasks` reads "opens the nearest event; the list one step back". The test count becomes today's number with today's date.

- [ ] **Step 2: The whole check**

Run: `cd shavtzak && flutter analyze && flutter test`
Expected: green; analyze within the baseline. Note both numbers for the hand-over.

- [ ] **Step 3: Commit** (message "docs(tasks): CLAUDE.md for the redesigned tasks screens").

- [ ] **Step 4: Hand over**

Tell the user, with the worktree's name and full path, what to try on a phone (Chrome's device toolbar, or the phone itself through `flutter run -d web-server --web-hostname 0.0.0.0` on the same Wi-Fi) and on a computer; that nothing is merged; that merging to `main` deploys the web build and no Functions deploy is needed. Merge only when they say so, and not while the event runs.
