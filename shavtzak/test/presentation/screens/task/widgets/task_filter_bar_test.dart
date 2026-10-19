import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_filter_bar.dart';

void main() {
  late List<TaskFilter?> reported;

  Future<void> pumpBar(
    WidgetTester tester, {
    int lateCount = 2,
    int soonCount = 1,
    TaskFilter? active,
    Size size = const Size(400, 800),
  }) {
    reported = [];
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: TaskFilterBar(
              lateCount: lateCount,
              soonCount: soonCount,
              active: active,
              onChanged: reported.add,
            ),
          ),
        ),
      ),
    ));
  }

  FilterChip chip(WidgetTester tester, String key) =>
      tester.widget<FilterChip>(find.byKey(Key(key)));

  testWidgets('stays one row on a 320 px phone', (tester) async {
    await pumpBar(tester, size: const Size(320, 640));

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byKey(const Key('filter-late'))).dy,
      tester.getTopLeft(find.byKey(const Key('filter-soon'))).dy,
    );
    expect(
      tester.getSize(find.byKey(const Key('task-filter-bar'))).height,
      lessThanOrEqualTo(48),
    );
  });

  testWidgets('reads סינון: and each count', (tester) async {
    await pumpBar(tester);

    expect(find.text('סינון:'), findsOneWidget);
    expect(find.text('באיחור (2)'), findsOneWidget);
    expect(find.text('התייצבות בחצי שעה הקרובה (1)'), findsOneWidget);
  });

  testWidgets('a toggle with nothing in it is disabled, unless it is on',
      (tester) async {
    await pumpBar(tester, soonCount: 0);
    expect(chip(tester, 'filter-soon').onSelected, isNull);

    await pumpBar(tester, soonCount: 0, active: TaskFilter.dueSoon);
    expect(chip(tester, 'filter-soon').onSelected, isNotNull);
  });

  testWidgets('a toggle that is off is white with a grey edge, never the theme blue',
      (tester) async {
    await pumpBar(tester);
    for (final key in ['filter-late', 'filter-soon']) {
      final off = chip(tester, key);
      expect(off.selected, isFalse);
      expect(off.backgroundColor, Colors.white, reason: key);
      expect(off.side?.color, TaskStyle.rest, reason: key);
    }
  });

  testWidgets('the one that is on is filled and ticked', (tester) async {
    await pumpBar(tester, active: TaskFilter.late);

    expect(chip(tester, 'filter-late').selected, isTrue);
    expect(chip(tester, 'filter-late').showCheckmark, isTrue);
    expect(chip(tester, 'filter-soon').selected, isFalse);
  });

  testWidgets('choosing reports it; choosing the active one reports none',
      (tester) async {
    await pumpBar(tester);
    await tester.tap(find.byKey(const Key('filter-soon')));
    expect(reported, [TaskFilter.dueSoon]);

    await pumpBar(tester, active: TaskFilter.late);
    await tester.tap(find.byKey(const Key('filter-late')));
    expect(reported, [null]);
  });
}
