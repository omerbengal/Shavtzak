import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/presentation/screens/task/widgets/stage_card.dart';

import '../../../../support/task_fixtures.dart';

void main() {
  final stage = buildStage();

  Future<void> pumpCard(WidgetTester tester, List<TaskItem> allTasks) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: StageCard(
              stage: stage,
              tasks: allTasks,
              allTasks: allTasks,
              canManage: false,
              isOpen: false,
              onToggleOpen: () {},
              isDetailsOpen: false,
              onToggleDetails: () {},
              onEdit: () {},
              onDelete: () {},
              onAddTask: () {},
              onCallPhone: (_) {},
              taskBuilder: (task) => Text(task.title),
            ),
          ),
        ),
      ),
    ));
  }

  List<TaskItem> tasks(int done, int total) => [
        for (var i = 0; i < total; i++)
          buildTask(id: 't$i', title: 'משימה $i', isComplete: i < done),
      ];

  Rect headerRect(WidgetTester tester) =>
      tester.getRect(find.byKey(Key('stage-toggle-${stage.id}')));

  final doneFill = find.byKey(Key('stage-progress-done-${stage.id}'));
  final leftFill = find.byKey(Key('stage-progress-left-${stage.id}'));

  group('progress fill', () {
    testWidgets('one of four done fills a quarter in green, from the left',
        (tester) async {
      await pumpCard(tester, tasks(1, 4));

      final header = headerRect(tester);
      final done = tester.getRect(doneFill);
      final left = tester.getRect(leftFill);
      expect(done.left, header.left);
      expect(done.width, closeTo(header.width / 4, 0.5));
      expect(left.right, header.right);
      expect(left.width, closeTo(header.width * 3 / 4, 0.5));
      expect(done.height, header.height);
    });

    testWidgets('nothing done stays all blue', (tester) async {
      await pumpCard(tester, tasks(0, 3));

      expect(doneFill, findsNothing);
      expect(tester.getRect(leftFill).width, headerRect(tester).width);
    });

    testWidgets('everything done turns all green', (tester) async {
      await pumpCard(tester, tasks(3, 3));

      expect(leftFill, findsNothing);
      expect(tester.getRect(doneFill).width, headerRect(tester).width);
    });

    testWidgets('a stage with no tasks stays all blue', (tester) async {
      await pumpCard(tester, const []);

      expect(doneFill, findsNothing);
      expect(tester.getRect(leftFill).width, headerRect(tester).width);
    });
  });

  testWidgets('the task count sits on the left of the header', (tester) async {
    await pumpCard(tester, tasks(1, 4));

    final count =
        tester.getRect(find.byKey(Key('stage-task-count-${stage.id}')));
    final title = tester.getRect(find.text(stage.title));
    expect(find.text('משימות: \u20661/4\u2069'), findsOneWidget);
    expect(count.right, lessThan(title.left));
  });
}
