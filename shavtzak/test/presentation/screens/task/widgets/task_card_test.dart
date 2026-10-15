import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_card.dart';

import '../../../../support/task_fixtures.dart';

void main() {
  // Sunday afternoon; "today" is 2026-10-11.
  final now = DateTime(2026, 10, 11, 14, 0);

  const threeSubtasks = [
    Subtask(id: 'a', title: 'הצעת מחיר', isDone: true),
    Subtask(id: 'b', title: 'אישור', isDone: true),
    Subtask(id: 'c', title: 'תשלום'),
  ];

  Future<_Calls> pumpCard(
    WidgetTester tester,
    TaskItem task, {
    bool canManage = false,
    bool canUpdateProgress = true,
  }) async {
    final calls = _Calls();
    // The card does not own its expanded state; this host plays the screen.
    var isExpanded = false;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => TaskCard(
                task: task,
                now: now,
                canManage: canManage,
                canUpdateProgress: canUpdateProgress,
                isExpanded: isExpanded,
                onToggleExpanded: () {
                  calls.expandToggles++;
                  setState(() => isExpanded = !isExpanded);
                },
                onToggleSubtask: (subtask, isDone) =>
                    calls.subtaskToggles.add('${subtask.id}:$isDone'),
                onSetComplete: calls.completions.add,
                onEditUpdate: () => calls.editUpdate++,
                onEdit: () => calls.edit++,
                onDelete: () => calls.delete++,
              ),
            ),
          ),
        ),
      ),
    ));
    return calls;
  }

  Color? tintOf(WidgetTester tester, TaskItem task) {
    final card = tester.widget<Card>(find.byKey(Key('task-card-${task.id}')));
    return card.color;
  }

  TextStyle titleStyle(WidgetTester tester, String title) =>
      tester.widget<Text>(find.text(title)).style!;

  /// Presses the card itself, on its title.
  Future<void> tapCard(WidgetTester tester, TaskItem task) async {
    await tester.tap(find.text(task.title));
    await tester.pumpAndSettle();
  }

  group('status colouring', () {
    testWidgets('a completed task is green, labelled and struck through',
        (tester) async {
      final task = buildTask(title: 'אישור ביטחוני', isComplete: true);
      await pumpCard(tester, task);

      expect(tintOf(tester, task), Colors.green.shade50);
      expect(find.text('הושלמה'), findsOneWidget);
      expect(
        titleStyle(tester, 'אישור ביטחוני').decoration,
        TextDecoration.lineThrough,
      );
    });

    testWidgets('an overdue task is red and labelled', (tester) async {
      final task = buildTask(dueAt: DateTime(2026, 10, 10, 9));
      await pumpCard(tester, task);

      expect(tintOf(tester, task), Colors.red.shade50);
      expect(find.text('באיחור'), findsOneWidget);
    });

    testWidgets('a task due later today is orange and labelled',
        (tester) async {
      final task = buildTask(dueAt: DateTime(2026, 10, 11, 20));
      await pumpCard(tester, task);

      expect(tintOf(tester, task), Colors.orange.shade50);
      expect(find.text('להיום'), findsOneWidget);
    });

    testWidgets('an open task has no tint, no label and no strikethrough',
        (tester) async {
      final task = buildTask(
        title: 'להזמין אוטובוס',
        dueAt: DateTime(2026, 10, 20, 9),
      );
      await pumpCard(tester, task);

      expect(tintOf(tester, task), isNull);
      expect(find.text('הושלמה'), findsNothing);
      expect(find.text('באיחור'), findsNothing);
      expect(find.text('להיום'), findsNothing);
      expect(
        titleStyle(tester, 'להזמין אוטובוס').decoration,
        isNot(TextDecoration.lineThrough),
      );
    });
  });

  group('details', () {
    testWidgets('shows the assembly time, assignees and description, and no '
        'event line', (tester) async {
      final task = buildTask(
        description: 'שני רכבים',
        stage: buildStage(date: DateTime(2026, 10, 20)),
        assemblyTime: '07:30',
        event: buildEvent(name: 'דו יומי צפון'),
        assignees: [
          buildMember(id: 'm1', name: 'דנה'),
          buildMember(id: 'm2', name: 'יואב'),
        ],
      );
      await pumpCard(tester, task);

      expect(find.text('התייצבות 07:30'), findsOneWidget);
      expect(find.text('דנה, יואב'), findsOneWidget);
      expect(find.text('שני רכבים'), findsOneWidget);
      // The page is the event: the card does not repeat it.
      expect(find.textContaining('דו יומי צפון'), findsNothing);
    });

    testWidgets('a task with no resolvable assignee says so', (tester) async {
      await pumpCard(tester, buildTask(assigneeIds: const ['deleted']));
      expect(find.text('ללא אחראים'), findsOneWidget);
    });

    testWidgets('a task with no assembly time shows no time line',
        (tester) async {
      await pumpCard(
        tester,
        buildTask(stage: buildStage(date: DateTime(2026, 10, 20))),
      );
      expect(find.byIcon(Icons.schedule), findsNothing);
    });

    testWidgets('shows the assignee update with its author', (tester) async {
      final task = buildTask(
        assigneeUpdate: 'ממתין לאישור',
        assigneeUpdateByName: 'דנה',
        assigneeUpdateAt: DateTime(2026, 10, 11, 9, 5),
      );
      await pumpCard(tester, task);

      expect(find.text('ממתין לאישור'), findsOneWidget);
      expect(find.textContaining('דנה'), findsOneWidget);
      expect(find.textContaining('11/10/2026 09:05'), findsWidgets);
    });

    testWidgets('shows when the task was last updated', (tester) async {
      final task = buildTask(updatedAt: DateTime(2026, 10, 9, 16, 45));
      await pumpCard(tester, task);

      expect(
        find.textContaining('עודכן לאחרונה: 09/10/2026 16:45'),
        findsOneWidget,
      );
    });
  });

  group('subtasks', () {
    testWidgets('shows progress as done over total', (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      await pumpCard(tester, task);

      expect(find.text('2/3'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(Key('task-progress-${task.id}')),
      );
      expect(bar.value, closeTo(2 / 3, 0.0001));
    });

    testWidgets('is collapsed at first, and pressing the card shows one card '
        'per subtask', (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      await pumpCard(tester, task);

      expect(find.byKey(const Key('subtask-a')), findsNothing);

      await tapCard(tester, task);

      expect(find.byKey(const Key('subtask-a')), findsOneWidget);
      expect(find.byKey(const Key('subtask-b')), findsOneWidget);
      expect(find.byKey(const Key('subtask-c')), findsOneWidget);
      expect(find.text('תשלום'), findsOneWidget);
    });

    testWidgets('pressing the card again hides the subtasks', (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      await pumpCard(tester, task);

      await tapCard(tester, task);
      await tapCard(tester, task);

      expect(find.byKey(const Key('subtask-a')), findsNothing);
    });

    testWidgets('has no expand arrow', (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      await pumpCard(tester, task);

      expect(find.byIcon(Icons.expand_more), findsNothing);
      await tapCard(tester, task);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });

    testWidgets('pressing a subtask row does not hide the subtasks',
        (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      final calls = await pumpCard(tester, task);
      await tapCard(tester, task);

      await tester.tap(find.text('תשלום'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('subtask-c')), findsOneWidget);
      expect(calls.expandToggles, 1);
      expect(calls.subtaskToggles, isEmpty);
    });

    testWidgets('a done subtask is ticked and struck through', (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      await pumpCard(tester, task);
      await tapCard(tester, task);

      final done = tester.widget<Checkbox>(find.descendant(
        of: find.byKey(const Key('subtask-a')),
        matching: find.byType(Checkbox),
      ));
      final open = tester.widget<Checkbox>(find.descendant(
        of: find.byKey(const Key('subtask-c')),
        matching: find.byType(Checkbox),
      ));
      expect(done.value, isTrue);
      expect(open.value, isFalse);
      expect(
        titleStyle(tester, 'הצעת מחיר').decoration,
        TextDecoration.lineThrough,
      );
    });

    testWidgets('ticking a subtask reports that subtask and its new value',
        (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      final calls = await pumpCard(tester, task);
      await tapCard(tester, task);

      await tester.tap(find.descendant(
        of: find.byKey(const Key('subtask-c')),
        matching: find.byType(Checkbox),
      ));
      await tester.tap(find.descendant(
        of: find.byKey(const Key('subtask-a')),
        matching: find.byType(Checkbox),
      ));
      await tester.pumpAndSettle();

      expect(calls.subtaskToggles, ['c:true', 'a:false']);
      // Ticking is not a press on the card.
      expect(find.byKey(const Key('subtask-c')), findsOneWidget);
    });

    testWidgets('a task with subtasks has no completion checkbox of its own',
        (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      await pumpCard(tester, task);

      expect(find.byKey(Key('task-complete-${task.id}')), findsNothing);
    });
  });

  group('a task without subtasks', () {
    testWidgets('has a completion checkbox and no progress', (tester) async {
      final task = buildTask();
      final calls = await pumpCard(tester, task);

      expect(find.byKey(Key('task-progress-${task.id}')), findsNothing);

      await tester.tap(find.byKey(Key('task-complete-${task.id}')));
      expect(calls.completions, [true]);
    });

    testWidgets('pressing the card does nothing, there being nothing to show',
        (tester) async {
      final task = buildTask();
      final calls = await pumpCard(tester, task);

      await tapCard(tester, task);

      expect(calls.expandToggles, 0);
    });

    testWidgets('unticking a completed task reports reopening', (tester) async {
      final task = buildTask(isComplete: true);
      final calls = await pumpCard(tester, task);

      await tester.tap(find.byKey(Key('task-complete-${task.id}')));
      expect(calls.completions, [false]);
    });
  });

  group('permissions', () {
    testWidgets('a member who cannot update progress gets disabled checkboxes '
        'and no update button', (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      final calls = await pumpCard(tester, task, canUpdateProgress: false);
      await tapCard(tester, task);

      final checkbox = tester.widget<Checkbox>(find.descendant(
        of: find.byKey(const Key('subtask-c')),
        matching: find.byType(Checkbox),
      ));
      expect(checkbox.onChanged, isNull);
      expect(find.byKey(Key('task-update-${task.id}')), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('subtask-c')),
          matching: find.byType(Checkbox),
        ),
        warnIfMissed: false,
      );
      expect(calls.subtaskToggles, isEmpty);
    });

    testWidgets('a read-only member cannot complete a task without subtasks',
        (tester) async {
      final task = buildTask();
      await pumpCard(tester, task, canUpdateProgress: false);

      final checkbox = tester.widget<Checkbox>(
        find.byKey(Key('task-complete-${task.id}')),
      );
      expect(checkbox.onChanged, isNull);
    });

    testWidgets('the update button opens the update editor', (tester) async {
      final task = buildTask();
      final calls = await pumpCard(tester, task);

      await tester.tap(find.byKey(Key('task-update-${task.id}')));
      expect(calls.editUpdate, 1);
    });

    testWidgets('only a manager gets the edit and delete buttons',
        (tester) async {
      final task = buildTask();
      await pumpCard(tester, task);
      expect(find.byKey(Key('task-edit-${task.id}')), findsNothing);
      expect(find.byKey(Key('task-delete-${task.id}')), findsNothing);

      final calls = await pumpCard(tester, task, canManage: true);
      await tester.tap(find.byKey(Key('task-edit-${task.id}')));
      expect(calls.edit, 1);
      expect(calls.delete, 0);

      await tester.tap(find.byKey(Key('task-delete-${task.id}')));
      expect(calls.delete, 1);
      expect(calls.edit, 1);
    });

    testWidgets('edit is a blue pencil and delete a red bin, not a menu',
        (tester) async {
      final task = buildTask();
      await pumpCard(tester, task, canManage: true);

      Icon iconOf(String key) => tester.widget<Icon>(find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Icon),
          ));

      expect(iconOf('task-edit-${task.id}').icon, Icons.edit);
      expect(iconOf('task-edit-${task.id}').color, Colors.blue);
      expect(iconOf('task-delete-${task.id}').icon, Icons.delete);
      expect(iconOf('task-delete-${task.id}').color, Colors.red);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('pressing edit or delete does not open the subtasks',
        (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      final calls = await pumpCard(tester, task, canManage: true);

      await tester.tap(find.byKey(Key('task-edit-${task.id}')));
      await tester.tap(find.byKey(Key('task-delete-${task.id}')));
      await tester.pumpAndSettle();

      expect(calls.expandToggles, 0);
      expect(find.byKey(const Key('subtask-a')), findsNothing);
    });
  });
}

class _Calls {
  final subtaskToggles = <String>[];
  final completions = <bool>[];
  int editUpdate = 0;
  int edit = 0;
  int delete = 0;
  int expandToggles = 0;
}
