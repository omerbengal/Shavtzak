import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/task/widgets/stage_count_button.dart';

void main() {
  late int presses;

  Future<void> pumpButton(WidgetTester tester, TaskProgress progress) {
    presses = 0;
    return tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: StageCountButton(
              progress: progress,
              onPressed: () => presses++,
            ),
          ),
        ),
      ),
    ));
  }

  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  testWidgets('a done stage shows a tick and n/n', (tester) async {
    await pumpButton(tester, const TaskProgress(total: 5, done: 5));

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text(ltr('5/5')), findsOneWidget);
    expect(colorOf(tester, ltr('5/5')), TaskStyle.doneDark);
  });

  testWidgets('a late task makes the count red', (tester) async {
    await pumpButton(tester, const TaskProgress(total: 4, done: 1, late: 1));

    expect(colorOf(tester, '3 חסרות'), TaskStyle.lateDark);
  });

  testWidgets('a task due in the half hour, none late, makes it orange',
      (tester) async {
    await pumpButton(tester, const TaskProgress(total: 3, dueSoon: 1));

    expect(colorOf(tester, '3 חסרות'), TaskStyle.soonDark);
  });

  testWidgets('otherwise it is neutral, singular for one', (tester) async {
    await pumpButton(tester, const TaskProgress(total: 1));

    expect(colorOf(tester, '1 חסרה'), TaskStyle.neutralText);
  });

  testWidgets('a stage without tasks has no button', (tester) async {
    await pumpButton(tester, const TaskProgress());

    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('pressing it reports', (tester) async {
    await pumpButton(tester, const TaskProgress(total: 2));

    await tester.tap(find.text('2 חסרות'));
    expect(presses, 1);
  });

  testWidgets('its tap area is at least 40 px wide', (tester) async {
    await pumpButton(tester, const TaskProgress(total: 2, done: 2));

    expect(
      tester.getSize(find.byType(InkWell)).width,
      greaterThanOrEqualTo(40),
    );
  });
}
