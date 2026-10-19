import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/core/utils/task_utils.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_results_list.dart';

import '../../../../support/sample_event.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  Future<void> pumpList(WidgetTester tester, List<StageTasks> groups) {
    return tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: TaskResultsList(
              groups: groups,
              rowBuilder: (task) => Text('row:${task.id}'),
              emptyText: 'לא נמצאו משימות תואמות',
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('groups rows under their stage, with its time', (tester) async {
    final lunchTask = buildTask(id: 'l', stage: stLunch, assemblyTime: '13:00');
    final first = buildTask(id: 'w1', stage: stWorkshops, assemblyTime: '15:00');
    final second = buildTask(id: 'w2', stage: stWorkshops);
    final roomsTask = buildTask(id: 'r', stage: stRooms);
    await pumpList(tester, [
      StageTasks(stLunch, [lunchTask]),
      StageTasks(stWorkshops, [first, second]),
      StageTasks(stRooms, [roomsTask]),
    ]);

    expect(
      find.descendant(
        of: find.byKey(const Key('results-stage-ws')),
        matching: find.text('סדנאות · ${ltr('14:30–17:00')}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('results-stage-rooms')),
        matching: find.text('חלוקת חדרים'),
      ),
      findsOneWidget,
    );
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('row:l'), lessThan(tester.getTopLeft(find.byKey(const Key('results-stage-ws'))).dy));
    expect(top('row:w1'), lessThan(top('row:w2')));
    expect(top('row:w2'), lessThan(top('row:r')));
  });

  testWidgets('an empty list shows its text', (tester) async {
    await pumpList(tester, const []);

    expect(find.text('לא נמצאו משימות תואמות'), findsOneWidget);
  });
}
