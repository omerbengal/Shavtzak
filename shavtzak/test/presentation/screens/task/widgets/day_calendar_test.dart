import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/task/widgets/day_calendar.dart';

import '../../../../support/sample_event.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  // sampleNow is Tuesday 14:40; the workshops (14:30–17:00) are under way.
  const hourHeight = 56.0;

  late List<(String, bool)> opened;

  Map<DateTime, List<Stage>> byDay(List<Stage> stages) {
    final map = <DateTime, List<Stage>>{};
    for (final stage in stages) {
      final day = DateTime(stage.date.year, stage.date.month, stage.date.day);
      map.putIfAbsent(day, () => []).add(stage);
    }
    return map;
  }

  Future<void> pumpCalendar(
    WidgetTester tester, {
    List<DateTime>? days,
    List<Stage>? stages,
    Set<String> currentStageIds = const {'ws'},
    Set<String> outlinedStageIds = const {},
    bool fadeOthers = false,
    String? focusStageId,
    GlobalKey? focusKey,
    Size size = const Size(400, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    opened = [];
    final board = sampleBoard();
    final shown = stages ?? sampleStages;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: DayCalendar(
              days: days ?? [sampleTue],
              stagesByDay: byDay(shown),
              progressByStage: {
                for (final stage in shown)
                  stage.id: taskProgress(board.tasksOf(stage.id), sampleNow),
              },
              mineByStage: {
                for (final stage in shown)
                  stage.id: board
                      .tasksOf(stage.id)
                      .where((task) => task.assigneeIds.contains('m1'))
                      .length,
              },
              currentStageIds: currentStageIds,
              now: sampleNow,
              hourHeight: hourHeight,
              outlinedStageIds: outlinedStageIds,
              fadeOthers: fadeOthers,
              focusStageId: focusStageId,
              focusKey: focusKey,
              onOpenStage: (stage, {required missingOnly}) =>
                  opened.add((stage.id, missingOnly)),
            ),
          ),
        ),
      ),
    ));
  }

  Finder block(String id) => find.byKey(Key('stage-block-$id'));
  Finder tueColumn() => find.byKey(const Key('day-column-2026-10-20'));

  Color? blockColor(WidgetTester tester, String id) => tester
      .widget<Material>(
          find.descendant(of: block(id), matching: find.byType(Material)).first)
      .color;

  Color? textColor(WidgetTester tester, Finder text) =>
      tester.widget<Text>(text).style?.color;

  testWidgets('a stage sits at its start and is as tall as it lasts',
      (tester) async {
    await pumpCalendar(tester);
    // The grid starts at 08, the hour of the setup.
    final gridTop = tester.getTopLeft(tueColumn()).dy;
    expect(tester.getTopLeft(block('ws')).dy - gridTop, 6.5 * hourHeight);
    expect(tester.getSize(block('ws')).height, 2.5 * hourHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stage without an end gets the smallest readable height',
      (tester) async {
    await pumpCalendar(tester);
    expect(
      tester.getSize(block('dinner')).height,
      closeTo(TaskStyle.minBlockMinutes(hourHeight) / 60 * hourHeight, 0.01),
    );
  });

  testWidgets('a stage without a time sits in the all-day row, above the hours',
      (tester) async {
    await pumpCalendar(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('all-day-row')),
        matching: block('rooms'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(block('rooms')).dy,
      lessThanOrEqualTo(tester.getTopLeft(block('setup')).dy),
    );
  });

  testWidgets('no untimed stage, no all-day row', (tester) async {
    await pumpCalendar(tester, stages: [stSetup, stWorkshops]);
    expect(find.byKey(const Key('all-day-row')), findsNothing);
  });

  testWidgets('overlapping stages share the width side by side',
      (tester) async {
    final long = buildStage(
        id: 'long', title: 'א', date: sampleTue, startTime: '10:00', endTime: '12:00');
    final short = buildStage(
        id: 'short', title: 'ב', date: sampleTue, startTime: '11:00', endTime: '12:00');
    await pumpCalendar(tester, stages: [long, short]);
    final column = tester.getRect(tueColumn());
    final first = tester.getRect(block('long'));
    final second = tester.getRect(block('short'));
    expect(first.width, second.width);
    expect(first.width, closeTo(column.width / 2, TaskStyle.blockGap));
    // Column 0 is on the start side, the right under RTL.
    expect(first.right, closeTo(column.right, TaskStyle.blockGap));
    expect(first.left, greaterThan(second.left));
  });

  testWidgets('the now line shows on today with the time, and not on another day',
      (tester) async {
    await pumpCalendar(tester);
    expect(find.byKey(const Key('now-line')), findsOneWidget);
    expect(find.text(ltr('14:40')), findsOneWidget);
    // 14:40 is 6 h 40 min into a grid starting at 08.
    final lineTop = tester.getRect(find.byKey(const Key('now-line'))).center.dy;
    expect(
      lineTop - tester.getTopLeft(tueColumn()).dy,
      closeTo((6 + 40 / 60) * hourHeight, 0.01),
    );

    await pumpCalendar(tester, days: [sampleWed]);
    expect(find.byKey(const Key('now-line')), findsNothing);
    expect(find.text(ltr('14:40')), findsNothing);
  });

  testWidgets('the count names what is missing, coloured by the worst case',
      (tester) async {
    await pumpCalendar(tester);
    Finder countText(String id, String label) => find.descendant(
        of: find.byKey(Key('stage-count-$id')), matching: find.text(label));

    expect(textColor(tester, countText('ws', '4 חסרות')), TaskStyle.lateDark);
    expect(textColor(tester, countText('lunch', '1 חסרה')), TaskStyle.lateDark);
    expect(
        textColor(tester, countText('dinner', '1 חסרה')), TaskStyle.neutralText);
    expect(countText('setup', ltr('1/1')), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(const Key('stage-count-setup')),
          matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stage-count-rooms')), findsNothing);
  });

  testWidgets('done stages are green, the current one blue, a late task gives a red edge',
      (tester) async {
    await pumpCalendar(tester);
    expect(blockColor(tester, 'setup'), TaskStyle.doneLight);
    expect(blockColor(tester, 'ws'), TaskStyle.currentLight);
    expect(find.byKey(const Key('stage-late-ws')), findsOneWidget);
    expect(blockColor(tester, 'dinner'), Colors.white);
    expect(find.byKey(const Key('stage-late-dinner')), findsNothing);
    expect(find.byKey(const Key('stage-late-setup')), findsNothing);
    // The edge sits on the start side, the right under RTL.
    expect(
      tester.getRect(find.byKey(const Key('stage-late-ws'))).right,
      closeTo(tester.getRect(block('ws')).right, 0.01),
    );
  });

  testWidgets('a stage with my tasks carries my count', (tester) async {
    await pumpCalendar(tester);
    expect(
      find.descendant(
          of: find.byKey(const Key('stage-mine-ws')), matching: find.text('4')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stage-mine-rooms')), findsNothing);
  });

  testWidgets('the count opens the missing tasks, the block all of them',
      (tester) async {
    await pumpCalendar(tester);
    await tester.tap(find.byKey(const Key('stage-count-ws')));
    expect(opened, [('ws', true)]);
    await tester.tap(
        find.descendant(of: block('ws'), matching: find.text('סדנאות')));
    expect(opened, [('ws', true), ('ws', false)]);
  });

  testWidgets('the outlined stage stands out and the rest fade',
      (tester) async {
    await pumpCalendar(tester, outlinedStageIds: {'ws'}, fadeOthers: true);
    Finder faded(String id) => find.descendant(
          of: block(id),
          matching: find.byWidgetPredicate(
              (w) => w is Opacity && w.opacity == TaskStyle.fadedOpacity),
        );
    expect(faded('lunch'), findsOneWidget);
    expect(faded('ws'), findsNothing);
    final shape = tester
        .widget<Material>(
            find.descendant(of: block('ws'), matching: find.byType(Material)).first)
        .shape as RoundedRectangleBorder;
    expect(shape.side.color, TaskStyle.mine);
    expect(shape.side.width, TaskStyle.outlineWidth);
  });

  testWidgets('the focused stage carries the focus key', (tester) async {
    final focusKey = GlobalKey();
    await pumpCalendar(tester, focusStageId: 'lunch', focusKey: focusKey);
    expect(
      find.ancestor(of: block('lunch'), matching: find.byKey(focusKey)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: block('ws'), matching: find.byKey(focusKey)),
      findsNothing,
    );
  });

  testWidgets('a long title wraps onto more lines in a tall block',
      (tester) async {
    final title = 'כותרת ארוכה מאוד ' * 4;
    final tall = buildStage(
        id: 'tall', title: title, date: sampleTue, startTime: '10:00', endTime: '12:00');
    await pumpCalendar(tester, stages: [tall]);
    final text =
        find.descendant(of: block('tall'), matching: find.text(title));
    expect(tester.getSize(text).height,
        greaterThan(TaskStyle.blockTitleSize * 1.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long title in a narrow overlapping column ends in an ellipsis',
      (tester) async {
    final title = 'כותרת ארוכה מאוד של שלב שלא נגמרת אף פעם ' * 2;
    // Half an hour is too short to wrap: one line, cut with an ellipsis.
    final stages = [
      for (final id in ['a', 'b', 'c'])
        buildStage(
            id: id, title: title, date: sampleTue, startTime: '10:00', endTime: '10:30'),
    ];
    await pumpCalendar(tester, stages: stages, size: const Size(320, 800));
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(
        find.descendant(of: block('a'), matching: find.text(title)));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);

    // Two hours, three columns: wraps, still no overflow.
    final tallStages = [
      for (final id in ['a', 'b', 'c'])
        buildStage(
            id: id, title: title, date: sampleTue, startTime: '10:00', endTime: '12:00'),
    ];
    await pumpCalendar(tester, stages: tallStages, size: const Size(320, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late start-only stage stays inside the grid', (tester) async {
    final late = buildStage(
        id: 'night', title: 'לילה', date: sampleTue, startTime: '23:45');
    await pumpCalendar(tester, stages: [stSetup, late]);
    expect(
      tester.getBottomLeft(block('night')).dy,
      lessThanOrEqualTo(tester.getBottomLeft(tueColumn()).dy + 0.01),
    );
    expect(tester.getSize(block('night')).height,
        greaterThanOrEqualTo(TaskStyle.minBlockHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('two days side by side share one hour axis', (tester) async {
    final wedMorning = buildStage(
        id: 'wed8', title: 'פתיחה', date: sampleWed, startTime: '08:00', endTime: '09:00');
    await pumpCalendar(
      tester,
      days: [sampleTue, sampleWed],
      stages: [stSetup, wedMorning],
      size: const Size(1280, 900),
    );
    expect(tester.getTopLeft(block('setup')).dy,
        tester.getTopLeft(block('wed8')).dy);
    expect(
      find.descendant(
        of: find.byKey(const Key('day-header-2026-10-20')),
        matching: find.text('שלישי 20/10 · היום'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('day-header-2026-10-21')), findsOneWidget);
    // The first day is on the start side.
    expect(
      tester.getTopLeft(find.byKey(const Key('day-column-2026-10-20'))).dx,
      greaterThan(
          tester.getTopLeft(find.byKey(const Key('day-column-2026-10-21'))).dx),
    );
  });

  testWidgets('one day has no day header', (tester) async {
    await pumpCalendar(tester);
    expect(find.byKey(const Key('day-header-2026-10-20')), findsNothing);
  });

  testWidgets('no timed stage, no grid', (tester) async {
    await pumpCalendar(tester, stages: [stRooms]);
    expect(find.byKey(const Key('all-day-row')), findsOneWidget);
    expect(tueColumn(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
