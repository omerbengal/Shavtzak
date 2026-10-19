import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/presentation/screens/task/widgets/progress_strip.dart';

void main() {
  Future<void> pumpStrip(WidgetTester tester, TaskProgress progress) {
    return tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(width: 200, child: ProgressStrip(progress: progress)),
          ),
        ),
      ),
    ));
  }

  double widthOf(WidgetTester tester, String key) =>
      tester.getSize(find.byKey(Key(key))).width;

  double leftOf(WidgetTester tester, String key) =>
      tester.getTopLeft(find.byKey(Key(key))).dx;

  testWidgets('fills from the left: done, late, half hour, then the rest',
      (tester) async {
    await pumpStrip(
      tester,
      const TaskProgress(total: 10, done: 4, late: 1, dueSoon: 2),
    );

    const order = ['strip-done', 'strip-late', 'strip-soon', 'strip-rest'];
    expect([for (final key in order) widthOf(tester, key)], [80, 20, 40, 60]);
    for (var i = 0; i < order.length - 1; i++) {
      expect(
        leftOf(tester, order[i]),
        lessThan(leftOf(tester, order[i + 1])),
        reason: '${order[i]} before ${order[i + 1]}',
      );
    }
  });

  testWidgets('no tasks is one grey strip', (tester) async {
    await pumpStrip(tester, const TaskProgress());

    expect(find.byKey(const Key('strip-rest')), findsOneWidget);
    expect(find.byKey(const Key('strip-done')), findsNothing);
    expect(widthOf(tester, 'strip-rest'), 200);
  });
}
