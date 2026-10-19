import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/presentation/screens/task/widgets/member_timeline.dart';

import '../../../../support/sample_event.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  late List<String> openedTasks;
  late List<String> openedStages;
  late List<String> completions;
  late List<String> subtaskTicks;
  late int myLateOpens;
  late int showAllTaps;

  Widget timeline({
    required EventTaskBoard board,
    required DateTime now,
    String viewerId = 'm1',
    bool canTick = true,
  }) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: MemberTimeline(
            board: board,
            viewerId: viewerId,
            now: now,
            canTick: canTick,
            onOpenTask: (task) => openedTasks.add(task.id),
            onOpenStage: (stage) => openedStages.add(stage.id),
            onSetComplete: (task, isComplete) =>
                completions.add('${task.id}:$isComplete'),
            onToggleSubtask: (task, subtask, isDone) =>
                subtaskTicks.add('${task.id}:${subtask.id}:$isDone'),
            onOpenMyLate: () => myLateOpens++,
            onShowAllStages: () => showAllTaps++,
          ),
        ),
      ),
    );
  }

  Future<void> pumpTimeline(
    WidgetTester tester, {
    EventTaskBoard? board,
    DateTime? now,
    String viewerId = 'm1',
    bool canTick = true,
  }) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    openedTasks = [];
    openedStages = [];
    completions = [];
    subtaskTicks = [];
    myLateOpens = 0;
    showAllTaps = 0;
    await tester.pumpWidget(timeline(
      board: board ?? sampleBoard(),
      now: now ?? sampleNow,
      viewerId: viewerId,
      canTick: canTick,
    ));
  }

  Finder inside(String key, Finder finder) =>
      find.descendant(of: find.byKey(Key(key)), matching: finder);

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;

  testWidgets('opens on the current stage, earlier stages folded into one line',
      (tester) async {
    await pumpTimeline(tester);

    expect(
      find.text('2 שלבים קודמים · משימה אחת שלך הושלמה'),
      findsOneWidget,
    );
    expect(find.text('הקמה'), findsNothing);
    expect(inside('my-stage-ws', find.text('עכשיו')), findsOneWidget);
  });

  testWidgets('today\'s untimed stage stays out of the fold', (tester) async {
    await pumpTimeline(tester);

    expect(inside('my-stage-rooms', find.text('אין לך משימות')), findsOneWidget);
  });

  testWidgets('opening the fold shows the earlier stages in their place',
      (tester) async {
    await pumpTimeline(tester);

    await tester.tap(find.byKey(const Key('my-earlier-toggle')));
    await tester.pump();

    expect(find.text('הקמה'), findsOneWidget);
    expect(top(tester, find.text('הקמה')), lessThan(top(tester, find.text('סדנאות'))));
  });

  testWidgets('the current stage shows my open count and full rows',
      (tester) async {
    await pumpTimeline(tester);

    expect(inside('my-stage-ws', find.text('3 פתוחות שלך')), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-task-tick-ws-later')));
    expect(completions, ['ws-later:true']);
  });

  testWidgets('a task with subtasks lists them, tickable', (tester) async {
    await pumpTimeline(tester);

    await tester.tap(find.byKey(const Key('my-subtask-ws-soon-b')));
    expect(subtaskTicks, ['ws-soon:b:true']);
    expect(inside('my-task-ws-soon', find.text(ltr('1/3'))), findsOneWidget);
    expect(find.byKey(const Key('my-task-tick-ws-soon')), findsNothing);
  });

  testWidgets('rows run by report time, untimed last', (tester) async {
    await pumpTimeline(tester);

    final order = ['ws-done', 'ws-soon', 'ws-later', 'ws-untimed'];
    for (var i = 0; i < order.length - 1; i++) {
      expect(
        top(tester, find.byKey(Key('my-task-${order[i]}'))),
        lessThan(top(tester, find.byKey(Key('my-task-${order[i + 1]}')))),
      );
    }
    expect(inside('my-task-ws-soon', find.text(ltr('15:00'))), findsOneWidget);
    expect(inside('my-task-ws-soon', find.text('התייצבות')), findsOneWidget);
    expect(inside('my-task-ws-untimed', find.text('ללא שעה')), findsOneWidget);
  });

  testWidgets('a done task stays in place, struck through', (tester) async {
    await pumpTimeline(tester);

    expect(
      tester.widget<Text>(find.text('הכנת מצגות לסדנה')).style?.decoration,
      TextDecoration.lineThrough,
    );
  });

  testWidgets('other assignees read עם …', (tester) async {
    await pumpTimeline(tester);

    expect(inside('my-task-ws-soon', find.text('עם יואב')), findsOneWidget);
    expect(inside('my-task-ws-later', find.textContaining('עם ')), findsNothing);
  });

  testWidgets('the next stage reads השלב הבא and its tasks are compact',
      (tester) async {
    await pumpTimeline(tester);

    expect(inside('my-stage-dinner', find.text('השלב הבא')), findsOneWidget);
    expect(inside('my-stage-dinner', find.text('משימה אחת שלך')), findsOneWidget);
    expect(find.byKey(const Key('my-task-dinner-guests')), findsOneWidget);
    expect(find.byKey(const Key('my-task-tick-dinner-guests')), findsNothing);
  });

  testWidgets('a stage without my tasks is one line', (tester) async {
    await pumpTimeline(tester);

    expect(inside('my-stage-bf', find.text('אין לך משימות')), findsOneWidget);
  });

  testWidgets('day headers name the weekday, and today', (tester) async {
    await pumpTimeline(tester);

    expect(
      inside('my-day-2026-10-20', find.text('שלישי 20/10 · היום')),
      findsOneWidget,
    );
    expect(inside('my-day-2026-10-21', find.text('רביעי 21/10')), findsOneWidget);
  });

  testWidgets('one late task of mine is named in a one-line banner that opens it',
      (tester) async {
    await pumpTimeline(tester);

    expect(
      inside('my-late-banner', find.textContaining('בדיקת מנות מיוחדות')),
      findsOneWidget,
    );
    expect(
      inside(
        'my-late-banner',
        find.textContaining('ארוחת צהריים, ${ltr('13:00')}'),
      ),
      findsOneWidget,
    );
    final text = tester.widget<Text>(
      inside('my-late-banner', find.textContaining('בדיקת מנות מיוחדות')),
    );
    expect(text.maxLines, 1);

    await tester.tap(find.byKey(const Key('my-late-banner')));
    expect(openedTasks, ['lunch-late']);
  });

  testWidgets('several late tasks are counted and open the list',
      (tester) async {
    final setupLate = buildTask(
      id: 'setup-late',
      title: 'תליית שלטים',
      stage: stSetup,
      assemblyTime: '08:30',
      event: sampleEvent,
      assigneeIds: const ['m1'],
      assignees: [sDana],
    );
    await pumpTimeline(
      tester,
      board: sampleBoard(tasks: [...sampleTasks, setupLate]),
    );

    expect(
      inside('my-late-banner', find.text('2 משימות שלך באיחור')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('my-late-banner')));
    expect(myLateOpens, 1);
    expect(openedTasks, isEmpty);
  });

  testWidgets('with no tasks of mine, a note points to כל השלבים above the stages',
      (tester) async {
    await pumpTimeline(tester, viewerId: 'm9');

    expect(find.byKey(const Key('my-no-tasks')), findsOneWidget);
    expect(find.byKey(const Key('my-late-banner')), findsNothing);
    expect(
      top(tester, find.byKey(const Key('my-no-tasks'))),
      lessThan(top(tester, find.byKey(const Key('my-stage-ws')))),
    );
    await tester.tap(find.byKey(const Key('my-show-all')));
    expect(showAllTaps, 1);
  });

  testWidgets('time passing moves the highlight and the captions, not the fold or the rows',
      (tester) async {
    await pumpTimeline(tester);

    await tester.pumpWidget(timeline(
      board: sampleBoard(),
      now: DateTime(2026, 10, 20, 17, 30),
    ));

    expect(inside('my-stage-ws', find.text('עכשיו')), findsNothing);
    expect(inside('my-stage-dinner', find.text('השלב הבא')), findsOneWidget);
    expect(
      find.text('2 שלבים קודמים · משימה אחת שלך הושלמה'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('my-task-tick-ws-later')), findsOneWidget);
  });

  testWidgets('before the event it opens on the first stage, captioned השלב הבא',
      (tester) async {
    await pumpTimeline(tester, now: DateTime(2026, 10, 19, 10));

    expect(find.byKey(const Key('my-earlier-toggle')), findsNothing);
    expect(inside('my-stage-setup', find.text('השלב הבא')), findsOneWidget);
    expect(find.byKey(const Key('my-task-tick-setup-done')), findsOneWidget);
  });

  testWidgets('tapping a task opens it, tapping a stage line opens the stage',
      (tester) async {
    await pumpTimeline(tester);

    await tester.tap(find.text('חלוקת ערכות למשתתפים'));
    await tester.tap(find.byKey(const Key('my-stage-bf')));
    expect(openedTasks, ['ws-later']);
    expect(openedStages, ['bf']);
  });

  testWidgets('with canTick off nothing ticks', (tester) async {
    await pumpTimeline(tester, canTick: false);

    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(boxes, isNotEmpty);
    expect(boxes.every((box) => box.onChanged == null), isTrue);
  });

  testWidgets('long stage and task names wrap onto new lines instead of ending in "…"',
      (tester) async {
    final longStage = buildStage(
      id: 'long',
      title: 'התכנסות וקבלת פנים לכל המשתתפים באולם הגדול של המלון',
      date: sampleWed,
      startTime: '09:00',
      endTime: '10:00',
    );
    final longTask = buildTask(
      id: 'long-task',
      title: 'לוודא שכל הערכות, השלטים והתגים מוכנים בכניסה לאולם הגדול',
      stage: stBreakfast,
      assemblyTime: '07:45',
      event: sampleEvent,
      assigneeIds: const ['m1'],
      assignees: [sDana],
    );
    await pumpTimeline(
      tester,
      board: sampleBoard(
        stages: [...sampleStages, longStage],
        tasks: [...sampleTasks, longTask],
      ),
    );

    for (final name in [longStage.title, longTask.title]) {
      final finder = find.text(name);
      final text = tester.widget<Text>(finder);
      expect(text.maxLines, isNull, reason: name);
      expect(text.overflow, isNot(TextOverflow.ellipsis), reason: name);
      // The test font draws a 14 px letter 14 px tall: two lines or more.
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(28), reason: name);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a deleted opening stage is replaced by the next one',
      (tester) async {
    await pumpTimeline(tester);

    final withoutWorkshops = <Stage>[
      for (final stage in sampleStages)
        if (stage.id != 'ws') stage,
    ];
    await tester.pumpWidget(timeline(
      board: sampleBoard(
        stages: withoutWorkshops,
        tasks: <TaskItem>[
          for (final task in sampleTasks)
            if (task.stageId != 'ws') task,
        ],
      ),
      now: sampleNow,
    ));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('my-stage-dinner')), findsOneWidget);
    expect(find.byKey(const Key('my-task-tick-dinner-guests')), findsOneWidget);
  });
}
