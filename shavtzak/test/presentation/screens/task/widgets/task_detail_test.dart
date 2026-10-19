import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_detail.dart';

import '../../../../support/task_fixtures.dart';

void main() {
  // Sunday afternoon; "today" is 2026-10-11.
  final now = DateTime(2026, 10, 11, 14, 0);

  const threeSubtasks = [
    Subtask(id: 'a', title: 'הצעת מחיר', isDone: true),
    Subtask(id: 'b', title: 'אישור', isDone: true),
    Subtask(id: 'c', title: 'תשלום'),
  ];

  Future<_Calls> pumpDetail(
    WidgetTester tester,
    TaskItem task, {
    bool canManage = false,
    bool canUpdateProgress = true,
  }) async {
    final calls = _Calls();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: TaskDetail(
              task: task,
              now: now,
              canManage: canManage,
              canUpdateProgress: canUpdateProgress,
              onToggleSubtask: (subtask, isDone) =>
                  calls.subtaskToggles.add('${subtask.id}:$isDone'),
              onSetComplete: calls.completions.add,
              onEditUpdate: () => calls.editUpdate++,
              onEdit: () => calls.edit++,
              onDelete: () => calls.delete++,
              onCallPhone: calls.phoneCalls.add,
            ),
          ),
        ),
      ),
    ));
    return calls;
  }

  TextStyle titleStyle(WidgetTester tester, String title) =>
      tester.widget<Text>(find.text(title)).style!;

  /// The style of the report-time part of the stage line.
  TextStyle? timeStyle(WidgetTester tester, String line) {
    final text = tester.widget<Text>(find.text(line));
    final spans = (text.textSpan! as TextSpan).children!;
    return (spans.last as TextSpan).style;
  }

  group('status', () {
    testWidgets('a completed task is labelled הושלמה and struck through',
        (tester) async {
      await pumpDetail(
        tester,
        buildTask(title: 'אישור ביטחוני', isComplete: true),
      );

      expect(find.text('הושלמה'), findsOneWidget);
      expect(
        titleStyle(tester, 'אישור ביטחוני').decoration,
        TextDecoration.lineThrough,
      );
    });

    testWidgets('an overdue task is labelled באיחור', (tester) async {
      await pumpDetail(tester, buildTask(dueAt: DateTime(2026, 10, 10, 9)));

      expect(find.text('באיחור'), findsOneWidget);
    });

    testWidgets('a task due later today has no label', (tester) async {
      await pumpDetail(tester, buildTask(dueAt: DateTime(2026, 10, 11, 20)));

      expect(find.text('להיום'), findsNothing);
      expect(find.text('באיחור'), findsNothing);
    });

    testWidgets('an open task has no label and no strikethrough',
        (tester) async {
      await pumpDetail(
        tester,
        buildTask(title: 'להזמין אוטובוס', dueAt: DateTime(2026, 10, 20, 9)),
      );

      expect(find.text('הושלמה'), findsNothing);
      expect(find.text('באיחור'), findsNothing);
      expect(
        titleStyle(tester, 'להזמין אוטובוס').decoration,
        isNot(TextDecoration.lineThrough),
      );
    });
  });

  group('details', () {
    testWidgets('shows the stage and the report time, the assignees and the description',
        (tester) async {
      final task = buildTask(
        description: 'שני רכבים',
        stage: buildStage(title: 'סדנאות', date: DateTime(2026, 10, 20)),
        assemblyTime: '15:00',
        event: buildEvent(name: 'דו יומי צפון'),
        assignees: [
          buildMember(id: 'm1', name: 'דנה'),
          buildMember(id: 'm2', name: 'יואב'),
        ],
      );
      await pumpDetail(tester, task);

      expect(find.text('סדנאות · התייצבות ${ltr('15:00')}'), findsOneWidget);
      expect(find.text('דנה'), findsOneWidget);
      expect(find.text('יואב'), findsOneWidget);
      expect(find.text('שני רכבים'), findsOneWidget);
      // The page is the event: the view does not repeat it.
      expect(find.textContaining('דו יומי צפון'), findsNothing);
    });

    testWidgets('an untimed task says ללא שעה next to its stage',
        (tester) async {
      await pumpDetail(
        tester,
        buildTask(stage: buildStage(title: 'קליטה', date: DateTime(2026, 10, 20))),
      );

      expect(find.text('קליטה · ללא שעה'), findsOneWidget);
    });

    testWidgets('a task due in the half hour shows its time in orange',
        (tester) async {
      await pumpDetail(
        tester,
        buildTask(
          stage: buildStage(title: 'קליטה', date: DateTime(2026, 10, 11)),
          assemblyTime: '14:20',
        ),
      );

      expect(
        timeStyle(tester, 'קליטה · התייצבות ${ltr('14:20')}')?.color,
        TaskStyle.soonDark,
      );
      expect(find.textContaining('בעוד'), findsNothing);
    });

    testWidgets('an assignee with a phone gets a call button', (tester) async {
      final calls = await pumpDetail(
        tester,
        buildTask(
          assigneeIds: const ['m1', 'm2'],
          assignees: [
            buildMember(id: 'm1', name: 'דנה', phoneNumber: '0501234567'),
            buildMember(id: 'm2', name: 'יואב'),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('task-detail-call-m1')));
      expect(calls.phoneCalls, ['0501234567']);
      expect(find.byKey(const Key('task-detail-call-m2')), findsNothing);
    });

    testWidgets('a task with no resolvable assignee says so', (tester) async {
      await pumpDetail(tester, buildTask(assigneeIds: const ['deleted']));
      expect(find.text('ללא אחראים'), findsOneWidget);
    });

    testWidgets('shows the assignee update with its author', (tester) async {
      await pumpDetail(
        tester,
        buildTask(
          assigneeUpdate: 'ממתין לאישור',
          assigneeUpdateByName: 'דנה',
          assigneeUpdateAt: DateTime(2026, 10, 11, 9, 5),
        ),
      );

      expect(find.text('ממתין לאישור'), findsOneWidget);
      expect(find.textContaining('דנה'), findsOneWidget);
      expect(find.textContaining('11/10/2026 09:05'), findsWidgets);
    });

    testWidgets('shows when the task was last updated', (tester) async {
      await pumpDetail(
        tester,
        buildTask(updatedAt: DateTime(2026, 10, 9, 16, 45)),
      );

      expect(
        find.textContaining('עודכן לאחרונה: 09/10/2026 16:45'),
        findsOneWidget,
      );
    });
  });

  group('subtasks', () {
    testWidgets('shows progress as done over total', (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      await pumpDetail(tester, task);

      expect(find.text(ltr('2/3')), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(Key('task-progress-${task.id}')),
      );
      expect(bar.value, closeTo(2 / 3, 0.0001));
    });

    testWidgets('always shows one card per subtask', (tester) async {
      await pumpDetail(tester, buildTask(subtasks: threeSubtasks));

      expect(find.byKey(const Key('subtask-a')), findsOneWidget);
      expect(find.byKey(const Key('subtask-b')), findsOneWidget);
      expect(find.byKey(const Key('subtask-c')), findsOneWidget);
      expect(find.text('תשלום'), findsOneWidget);
    });

    testWidgets('a done subtask is ticked and struck through', (tester) async {
      await pumpDetail(tester, buildTask(subtasks: threeSubtasks));

      Checkbox boxOf(String id) => tester.widget<Checkbox>(find.descendant(
            of: find.byKey(Key('subtask-$id')),
            matching: find.byType(Checkbox),
          ));
      expect(boxOf('a').value, isTrue);
      expect(boxOf('c').value, isFalse);
      expect(
        titleStyle(tester, 'הצעת מחיר').decoration,
        TextDecoration.lineThrough,
      );
    });

    testWidgets('ticking a subtask reports that subtask and its new value',
        (tester) async {
      final calls = await pumpDetail(tester, buildTask(subtasks: threeSubtasks));

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
    });

    testWidgets('a task with subtasks has no completion checkbox of its own',
        (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      await pumpDetail(tester, task);

      expect(find.byKey(Key('task-complete-${task.id}')), findsNothing);
    });
  });

  group('a task without subtasks', () {
    testWidgets('has a completion checkbox and no progress', (tester) async {
      final task = buildTask();
      final calls = await pumpDetail(tester, task);

      expect(find.byKey(Key('task-progress-${task.id}')), findsNothing);

      await tester.tap(find.byKey(Key('task-complete-${task.id}')));
      expect(calls.completions, [true]);
    });

    testWidgets('unticking a completed task reports reopening', (tester) async {
      final task = buildTask(isComplete: true);
      final calls = await pumpDetail(tester, task);

      await tester.tap(find.byKey(Key('task-complete-${task.id}')));
      expect(calls.completions, [false]);
    });
  });

  group('permissions', () {
    testWidgets(
        'a member who cannot update progress gets disabled checkboxes '
        'and no update button', (tester) async {
      final task = buildTask(subtasks: threeSubtasks);
      final calls = await pumpDetail(tester, task, canUpdateProgress: false);

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
      await pumpDetail(tester, task, canUpdateProgress: false);

      final checkbox = tester.widget<Checkbox>(
        find.byKey(Key('task-complete-${task.id}')),
      );
      expect(checkbox.onChanged, isNull);
    });

    testWidgets('the update button opens the update editor', (tester) async {
      final task = buildTask();
      final calls = await pumpDetail(tester, task);

      await tester.tap(find.byKey(Key('task-update-${task.id}')));
      expect(calls.editUpdate, 1);
    });

    testWidgets('only a manager gets the edit and delete buttons',
        (tester) async {
      final task = buildTask();
      await pumpDetail(tester, task);
      expect(find.byKey(Key('task-edit-${task.id}')), findsNothing);
      expect(find.byKey(Key('task-delete-${task.id}')), findsNothing);

      final calls = await pumpDetail(tester, task, canManage: true);
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
      await pumpDetail(tester, task, canManage: true);

      Icon iconOf(String key) => tester.widget<Icon>(find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Icon),
          ));

      expect(iconOf('task-edit-${task.id}').icon, Icons.edit);
      expect(iconOf('task-edit-${task.id}').color, TaskStyle.edit);
      expect(iconOf('task-delete-${task.id}').icon, Icons.delete);
      expect(iconOf('task-delete-${task.id}').color, TaskStyle.delete);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });
  });
}

class _Calls {
  final subtaskToggles = <String>[];
  final completions = <bool>[];
  final phoneCalls = <String>[];
  int editUpdate = 0;
  int edit = 0;
  int delete = 0;
}
