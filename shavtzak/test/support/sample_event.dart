import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

import 'task_fixtures.dart';

/// The mockups' event: Tuesday 20 – Wednesday 21 October 2026, seen on
/// Tuesday at 14:40. Shared by the tests of the redesigned tasks screens so
/// they all describe the same day.
///
/// Screen order of [sampleStages]: rooms, setup, lunch, ws, dinner, out, bf.
final sampleNow = DateTime(2026, 10, 20, 14, 40);
final sampleTue = DateTime(2026, 10, 20);
final sampleWed = DateTime(2026, 10, 21);

final sampleEvent = buildEvent(
  id: 'e1',
  name: 'דו יומי הנהלה',
  startDate: sampleTue,
  endDate: sampleWed,
  location: 'מלון רויאל',
);

final stSetup = buildStage(
  id: 'setup',
  title: 'הקמה',
  date: sampleTue,
  startTime: '08:00',
  endTime: '09:00',
);
final stLunch = buildStage(
  id: 'lunch',
  title: 'ארוחת צהריים',
  date: sampleTue,
  startTime: '13:00',
  endTime: '14:00',
);
final stWorkshops = buildStage(
  id: 'ws',
  title: 'סדנאות',
  date: sampleTue,
  startTime: '14:30',
  endTime: '17:00',
  hotelLocation: 'חדרי הסדנה',
);
// A start time only.
final stDinner = buildStage(
  id: 'dinner',
  title: 'ארוחת ערב חגיגית',
  date: sampleTue,
  startTime: '19:30',
  hotelLocation: 'אולם האירועים',
);
// No time at all.
final stRooms = buildStage(id: 'rooms', title: 'חלוקת חדרים', date: sampleTue);
final stBreakfast = buildStage(
  id: 'bf',
  title: 'ארוחת בוקר',
  date: sampleWed,
  startTime: '07:30',
  endTime: '08:30',
);
// No time at all.
final stCheckout = buildStage(id: 'out', title: "צ'ק אאוט", date: sampleWed);

final sampleStages = [
  stSetup,
  stLunch,
  stWorkshops,
  stDinner,
  stRooms,
  stBreakfast,
  stCheckout,
];

// ---- the people and their tasks ----

/// The viewer in most tests; has a phone.
final sDana = buildMember(id: 'm1', name: 'דנה', phoneNumber: '0501234567');
final sYoav = buildMember(id: 'm2', name: 'יואב');

TaskItem _task(
  String id,
  String title,
  Stage stage, {
  String? at,
  List<TeamMember> who = const [],
  bool done = false,
  List<Subtask> subtasks = const [],
}) =>
    buildTask(
      id: id,
      title: title,
      stage: stage,
      assemblyTime: at,
      event: sampleEvent,
      assigneeIds: [for (final member in who) member.id],
      assignees: who,
      isComplete: done,
      subtasks: subtasks,
    );

final tSetupDone = _task('setup-done', 'פריסת שילוט', stSetup,
    at: '08:00', who: [sDana], done: true);
final tLunchLate = _task('lunch-late', 'בדיקת מנות מיוחדות', stLunch,
    at: '13:00', who: [sDana]);
final tWsDone = _task('ws-done', 'הכנת מצגות לסדנה', stWorkshops,
    at: '14:00', who: [sDana], done: true);
// Late at 14:40.
final tWsTheirs = _task('ws-theirs', 'הקמת עמדת קפה', stWorkshops,
    at: '14:15', who: [sYoav]);
// Due in the next half hour at 14:40.
final tWsSoon = _task('ws-soon', 'הכנת חדר סדנה 2', stWorkshops,
    at: '15:00',
    who: [sDana, sYoav],
    subtasks: const [
      Subtask(id: 'a', title: 'חיבור מקרן', isDone: true),
      Subtask(id: 'b', title: 'סידור כיסאות במעגל'),
      Subtask(id: 'c', title: 'בדיקת מיקרופון'),
    ]);
final tWsLater = _task('ws-later', 'חלוקת ערכות למשתתפים', stWorkshops,
    at: '15:45', who: [sDana]);
final tWsUntimed =
    _task('ws-untimed', 'החזרת ציוד הסדנה למחסן', stWorkshops, who: [sDana]);
final tDinner = _task('dinner-guests', 'קבלת אורחים בכניסה', stDinner,
    at: '19:00', who: [sDana, sYoav]);

final sampleTasks = [
  tSetupDone,
  tLunchLate,
  tWsDone,
  tWsTheirs,
  tWsSoon,
  tWsLater,
  tWsUntimed,
  tDinner,
];

/// The sample event's board, as the screens compute it.
EventTaskBoard sampleBoard({List<TaskItem>? tasks, List<Stage>? stages}) =>
    eventTaskBoard(
      sampleEvent,
      stages: stages ?? sampleStages,
      tasks: tasks ?? sampleTasks,
    );
