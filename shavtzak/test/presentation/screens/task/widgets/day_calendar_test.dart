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
  // Tall enough that the sample stages' names fit without stretching.
  const hourHeight = 80.0;

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
    // Lunch runs 13:00–14:00, the workshops 14:30–17:00.
    expect(
      tester.getTopLeft(block('ws')).dy - tester.getTopLeft(block('lunch')).dy,
      closeTo(1.5 * hourHeight, 0.01),
    );
    expect(tester.getSize(block('ws')).height, closeTo(2.5 * hourHeight, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long empty stretch squashes into a thin gap', (tester) async {
    await pumpCalendar(tester);
    // Nothing runs from the end of the setup at 09:00 until lunch at 13:00.
    expect(
      tester.getTopLeft(block('lunch')).dy -
          tester.getBottomLeft(block('setup')).dy,
      closeTo(TaskStyle.squashedGapHeight, 0.01),
    );
  });

  testWidgets('a start-only stage is as tall as its name needs',
      (tester) async {
    await pumpCalendar(tester);
    final title = find.descendant(of: block('dinner'), matching: find.text(stDinner.title));
    expect(tester.getRect(block('dinner')).bottom,
        greaterThanOrEqualTo(tester.getRect(title).bottom));
    expect(tester.getSize(block('dinner')).height,
        greaterThanOrEqualTo(TaskStyle.minBlockHeight));
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
    // 14:40 is ten minutes into the workshops.
    final lineTop = tester.getRect(find.byKey(const Key('now-line'))).center.dy;
    expect(
      lineTop - tester.getTopLeft(block('ws')).dy,
      closeTo(10 / 60 * hourHeight, 0.01),
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

  testWidgets('a block fills green from the left with its share of done tasks',
      (tester) async {
    await pumpCalendar(tester);
    Rect fill(String id) =>
        tester.getRect(find.byKey(Key('stage-fill-$id')));
    final ws = tester.getRect(block('ws'));
    final wsProgress = taskProgress(sampleBoard().tasksOf('ws'), sampleNow);
    expect(fill('ws').left, closeTo(ws.left, 0.01));
    expect(fill('ws').width,
        closeTo(ws.width * wsProgress.done / wsProgress.total, 0.01));
    expect(fill('setup').width, closeTo(tester.getRect(block('setup')).width, 0.01));
    expect(find.byKey(const Key('stage-fill-dinner')), findsNothing);
    expect(find.byKey(const Key('strip-done')), findsNothing);
    expect(find.byKey(const Key('strip-rest')), findsNothing);
  });

  testWidgets('every stage is white, the red line alone marks now; a late task gives a red edge',
      (tester) async {
    await pumpCalendar(tester);
    expect(blockColor(tester, 'ws'), Colors.white);
    expect(blockColor(tester, 'dinner'), Colors.white);
    expect(find.byKey(const Key('stage-late-ws')), findsOneWidget);
    expect(find.byKey(const Key('stage-late-dinner')), findsNothing);
    expect(find.byKey(const Key('stage-late-setup')), findsNothing);
    // The edge sits on the start side, the right under RTL.
    expect(
      tester.getRect(find.byKey(const Key('stage-late-ws'))).right,
      closeTo(tester.getRect(block('ws')).right, 0.01),
    );
  });

  testWidgets('a block carries no count of my tasks', (tester) async {
    await pumpCalendar(tester);
    expect(find.byKey(const Key('stage-mine-ws')), findsNothing);
    expect(
      find.descendant(of: block('ws'), matching: find.byIcon(Icons.person)),
      findsNothing,
    );
  });

  testWidgets('an hour label sits centred on its line, which reaches into the label column',
      (tester) async {
    await pumpCalendar(tester);
    final label = tester.getRect(find.byKey(const Key('hour-label-13')));
    final tick = tester.getRect(find.byKey(const Key('hour-tick-13')));
    final lunchTop = tester.getTopLeft(block('lunch')).dy;
    // Lunch starts at 13:00, on the line.
    expect(tick.center.dy, closeTo(lunchTop, 1));
    expect(label.center.dy, closeTo(tick.center.dy, 1));
    // The tick runs between the label and the grid, the left of it under RTL.
    expect(tick.right, lessThanOrEqualTo(label.left + 0.01));
    expect(tick.left, closeTo(tester.getRect(tueColumn()).right, 0.5));
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

  testWidgets('three overlapping stages sit side by side, each to its end, names in full',
      (tester) async {
    final title = 'כותרת ארוכה מאוד של שלב שלא נגמרת אף פעם ' * 2;
    final stages = [
      for (final (id, end) in [('a', '11:00'), ('b', '10:30'), ('c', '10:45')])
        buildStage(
            id: id, title: title, date: sampleTue, startTime: '10:00', endTime: end),
    ];
    await pumpCalendar(tester, stages: stages, size: const Size(320, 6000));
    expect(tester.takeException(), isNull);
    final column = tester.getRect(tueColumn());
    final tops = <double>{};
    for (final id in ['a', 'b', 'c']) {
      final rect = tester.getRect(block(id));
      expect(rect.width, closeTo(column.width / 3, TaskStyle.blockGap + 0.5), reason: id);
      tops.add(rect.top);
      final text = find.descendant(of: block(id), matching: find.text(title));
      expect(tester.widget<Text>(text).maxLines, isNull);
      expect(rect.bottom, greaterThanOrEqualTo(tester.getRect(text).bottom - 0.01));
    }
    // All start together, and each ends where its time ends: the longest
    // reaches furthest.
    expect(tops.length, 1);
    expect(tester.getRect(block('a')).bottom,
        greaterThan(tester.getRect(block('c')).bottom));
    expect(tester.getRect(block('c')).bottom,
        greaterThan(tester.getRect(block('b')).bottom));
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
