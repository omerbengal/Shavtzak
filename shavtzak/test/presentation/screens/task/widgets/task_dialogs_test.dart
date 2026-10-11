import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_utils.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/task/widgets/assignee_update_dialog.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_filter_modal.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_form_modal.dart';

import '../../../../support/task_fixtures.dart';

/// Holds what a dialog returned. `returned` distinguishes "returned null" from
/// "has not returned yet".
class _Result<T> {
  T? value;
  bool returned = false;
}

/// Pumps a page with one button that opens a dialog and records its result.
Future<_Result<T>> _openDialog<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) open,
) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final result = _Result<T>();
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.value = await open(context);
              result.returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  final now = DateTime(2026, 10, 11, 14, 0);

  final north = buildEvent(
    id: 'e1',
    name: 'דו יומי צפון',
    startDate: DateTime(2026, 10, 20),
  );
  final south = buildEvent(
    id: 'e2',
    name: 'דו יומי דרום',
    startDate: DateTime(2026, 10, 27),
  );
  final past = buildEvent(
    id: 'e0',
    name: 'אירוע שעבר',
    startDate: DateTime(2026, 9, 1),
  );
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yoav = buildMember(id: 'm2', name: 'יואב');
  final archived = buildMember(id: 'm3', name: 'הדס', isArchived: true);

  group('task form', () {
    Future<_Result<TaskItem>> openForm(
      WidgetTester tester, {
      TaskItem? existing,
      List<Event>? events,
      List<TeamMember>? members,
    }) {
      return _openDialog<TaskItem>(
        tester,
        (context) => showTaskFormModal(
          context,
          existing: existing,
          events: events ?? [north, south, past],
          members: members ?? [dana, yoav, archived],
          currentUserId: 'm-admin',
          now: now,
        ),
      );
    }

    Future<void> pickEvent(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('task-form-event')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(name).last);
      await tester.pumpAndSettle();
    }

    bool saveEnabled(WidgetTester tester) => tester
        .widget<FilledButton>(find.byKey(const Key('task-form-save')))
        .enabled;

    testWidgets('save stays disabled until an event, a title and an assignee '
        'are chosen', (tester) async {
      await openForm(tester);
      expect(saveEnabled(tester), isFalse);

      await pickEvent(tester, 'דו יומי צפון');
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(
        find.byKey(const Key('task-form-title')),
        'להזמין אוטובוס',
      );
      await tester.pump();
      expect(saveEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('task-form-assignee-m1')));
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('a title of only spaces does not enable save', (tester) async {
      await openForm(tester);
      await pickEvent(tester, 'דו יומי צפון');
      await tester.tap(find.byKey(const Key('task-form-assignee-m1')));
      await tester.enterText(find.byKey(const Key('task-form-title')), '   ');
      await tester.pump();

      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('creating returns a task with the chosen fields', (tester) async {
      final result = await openForm(tester);
      await pickEvent(tester, 'דו יומי דרום');
      await tester.enterText(
        find.byKey(const Key('task-form-title')),
        '  להזמין אוטובוס  ',
      );
      await tester.enterText(
        find.byKey(const Key('task-form-description')),
        'שני רכבים',
      );
      await tester.tap(find.byKey(const Key('task-form-assignee-m2')));
      await tester.tap(find.byKey(const Key('task-form-assignee-m1')));
      await tester.tap(find.byKey(const Key('task-form-add-subtask')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('task-form-subtask-0')),
        'הצעת מחיר',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      final task = result.value!;
      expect(task.id, isNotEmpty);
      expect(task.eventId, 'e2');
      expect(task.title, 'להזמין אוטובוס');
      expect(task.description, 'שני רכבים');
      expect(task.assigneeIds.toSet(), {'m1', 'm2'});
      expect(task.subtasks, hasLength(1));
      expect(task.subtasks.single.title, 'הצעת מחיר');
      expect(task.subtasks.single.id, isNotEmpty);
      expect(task.subtasks.single.isDone, isFalse);
      expect(task.dueAt, isNull);
      expect(task.createdById, 'm-admin');
    });

    testWidgets('two created tasks get different ids', (tester) async {
      Future<String> createOne() async {
        final result = await openForm(tester);
        await pickEvent(tester, 'דו יומי צפון');
        await tester.enterText(find.byKey(const Key('task-form-title')), 'א');
        await tester.tap(find.byKey(const Key('task-form-assignee-m1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('task-form-save')));
        await tester.pumpAndSettle();
        return result.value!.id;
      }

      expect(await createOne(), isNot(await createOne()));
    });

    testWidgets('blank subtask rows are dropped on save', (tester) async {
      final result = await openForm(tester);
      await pickEvent(tester, 'דו יומי צפון');
      await tester.enterText(find.byKey(const Key('task-form-title')), 'כותרת');
      await tester.tap(find.byKey(const Key('task-form-assignee-m1')));
      await tester.tap(find.byKey(const Key('task-form-add-subtask')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-add-subtask')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('task-form-subtask-1')), 'שלב');
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(result.value!.subtasks.map((subtask) => subtask.title), ['שלב']);
    });

    testWidgets('editing starts from the task and returns its untouched fields',
        (tester) async {
      final existing = buildTask(
        id: 't1',
        eventId: 'e1',
        event: north,
        title: 'להזמין אוטובוס',
        description: 'שני רכבים',
        dueAt: DateTime(2026, 10, 19, 7, 30),
        assigneeIds: const ['m1'],
        assignees: [dana],
        assigneeUpdate: 'בטיפול',
        isComplete: false,
      );
      final result = await openForm(tester, existing: existing);

      expect(find.text('להזמין אוטובוס'), findsOneWidget);
      expect(find.text('שני רכבים'), findsOneWidget);
      expect(saveEnabled(tester), isTrue);

      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      final task = result.value!;
      expect(task.id, 't1');
      expect(task.eventId, 'e1');
      expect(task.title, 'להזמין אוטובוס');
      expect(task.description, 'שני רכבים');
      expect(task.dueAt, DateTime(2026, 10, 19, 7, 30));
      expect(task.assigneeIds, ['m1']);
      expect(task.assigneeUpdate, 'בטיפול');
    });

    testWidgets('editing keeps a renamed subtask\'s id and done state and '
        'drops a removed one', (tester) async {
      final existing = buildTask(
        id: 't1',
        eventId: 'e1',
        event: north,
        assigneeIds: const ['m1'],
        assignees: [dana],
        subtasks: const [
          Subtask(id: 'a', title: 'הצעת מחיר', isDone: true),
          Subtask(id: 'b', title: 'אישור'),
        ],
      );
      final result = await openForm(tester, existing: existing);

      await tester.enterText(
        find.byKey(const Key('task-form-subtask-0')),
        'הצעת מחיר מעודכנת',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-subtask-remove-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(result.value!.subtasks, const [
        Subtask(id: 'a', title: 'הצעת מחיר מעודכנת', isDone: true),
      ]);
    });

    testWidgets('clearing the due date returns a task with no due date',
        (tester) async {
      final existing = buildTask(
        id: 't1',
        eventId: 'e1',
        event: north,
        assigneeIds: const ['m1'],
        assignees: [dana],
        dueAt: DateTime(2026, 10, 19, 7, 30),
      );
      final result = await openForm(tester, existing: existing);

      await tester.tap(find.byKey(const Key('task-form-due-clear')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(result.value!.dueAt, isNull);
    });

    testWidgets('a past event is not offered when creating', (tester) async {
      await openForm(tester);
      await tester.tap(find.byKey(const Key('task-form-event')));
      await tester.pumpAndSettle();

      expect(find.textContaining('דו יומי צפון'), findsWidgets);
      expect(find.textContaining('אירוע שעבר'), findsNothing);
    });

    testWidgets('the task\'s own past event stays selected when editing',
        (tester) async {
      final existing = buildTask(
        id: 't1',
        eventId: 'e0',
        event: past,
        assigneeIds: const ['m1'],
        assignees: [dana],
      );
      final result = await openForm(tester, existing: existing);

      expect(find.textContaining('אירוע שעבר'), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(result.value!.eventId, 'e0');
    });

    testWidgets('an archived member is not offered as an assignee',
        (tester) async {
      await openForm(tester);

      expect(find.byKey(const Key('task-form-assignee-m1')), findsOneWidget);
      expect(find.byKey(const Key('task-form-assignee-m3')), findsNothing);
    });

    testWidgets('cancel returns nothing', (tester) async {
      final result = await openForm(tester);
      await tester.enterText(find.byKey(const Key('task-form-title')), 'כותרת');
      await tester.tap(find.byKey(const Key('task-form-cancel')));
      await tester.pumpAndSettle();

      expect(result.returned, isTrue);
      expect(result.value, isNull);
    });
  });

  group('task filter', () {
    Future<_Result<TaskFilterSelection>> openFilter(
      WidgetTester tester, {
      TaskFilterSelection current = const TaskFilterSelection(),
    }) {
      return _openDialog<TaskFilterSelection>(
        tester,
        (context) => showTaskFilterModal(
          context,
          current: current,
          events: [north, south],
          members: [dana, yoav],
        ),
      );
    }

    testWidgets('returns what was ticked in each group', (tester) async {
      final result = await openFilter(tester);

      await tester.tap(find.byKey(const Key('filter-status-overdue')));
      await tester.tap(find.byKey(const Key('filter-event-e2')));
      await tester.tap(find.byKey(const Key('filter-assignee-m1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-apply')));
      await tester.pumpAndSettle();

      expect(
        result.value,
        const TaskFilterSelection(
          statuses: {TaskDueStatus.overdue},
          eventIds: {'e2'},
          assigneeIds: {'m1'},
        ),
      );
    });

    testWidgets('starts from the current selection and can untick it',
        (tester) async {
      final result = await openFilter(
        tester,
        current: const TaskFilterSelection(
          statuses: {TaskDueStatus.completed},
          eventIds: {'e1'},
        ),
      );

      final ticked = tester.widget<CheckboxListTile>(
        find.byKey(const Key('filter-status-completed')),
      );
      expect(ticked.value, isTrue);

      await tester.tap(find.byKey(const Key('filter-status-completed')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-apply')));
      await tester.pumpAndSettle();

      expect(result.value, const TaskFilterSelection(eventIds: {'e1'}));
    });

    testWidgets('clear returns an empty selection', (tester) async {
      final result = await openFilter(
        tester,
        current: const TaskFilterSelection(eventIds: {'e1'}),
      );

      await tester.tap(find.byKey(const Key('filter-clear')));
      await tester.pumpAndSettle();

      expect(result.value, const TaskFilterSelection());
      expect(result.value!.isEmpty, isTrue);
    });

    testWidgets('cancel returns nothing, leaving the caller\'s filter alone',
        (tester) async {
      final result = await openFilter(tester);

      await tester.tap(find.byKey(const Key('filter-status-open')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-cancel')));
      await tester.pumpAndSettle();

      expect(result.returned, isTrue);
      expect(result.value, isNull);
    });

    test('activeCount counts the groups in use', () {
      expect(const TaskFilterSelection().activeCount, 0);
      expect(
        const TaskFilterSelection(
          statuses: {TaskDueStatus.open, TaskDueStatus.overdue},
          assigneeIds: {'m1'},
        ).activeCount,
        2,
      );
    });
  });

  group('assignee update dialog', () {
    Future<_Result<String>> openUpdate(
      WidgetTester tester, {
      String? initialText,
    }) {
      return _openDialog<String>(
        tester,
        (context) => showAssigneeUpdateDialog(context, initialText: initialText),
      );
    }

    testWidgets('returns the typed text, trimmed', (tester) async {
      final result = await openUpdate(tester);

      await tester.enterText(
        find.byKey(const Key('assignee-update-text')),
        '  ממתין לאישור  ',
      );
      await tester.tap(find.byKey(const Key('assignee-update-save')));
      await tester.pumpAndSettle();

      expect(result.value, 'ממתין לאישור');
    });

    testWidgets('starts from the current update', (tester) async {
      await openUpdate(tester, initialText: 'בטיפול');
      expect(find.text('בטיפול'), findsOneWidget);
    });

    testWidgets('emptying the text returns an empty string, which clears it',
        (tester) async {
      final result = await openUpdate(tester, initialText: 'בטיפול');

      await tester.enterText(find.byKey(const Key('assignee-update-text')), '');
      await tester.tap(find.byKey(const Key('assignee-update-save')));
      await tester.pumpAndSettle();

      expect(result.returned, isTrue);
      expect(result.value, '');
    });

    testWidgets('cancel returns nothing', (tester) async {
      final result = await openUpdate(tester, initialText: 'בטיפול');

      await tester.enterText(
        find.byKey(const Key('assignee-update-text')),
        'משהו אחר',
      );
      await tester.tap(find.byKey(const Key('assignee-update-cancel')));
      await tester.pumpAndSettle();

      expect(result.returned, isTrue);
      expect(result.value, isNull);
    });
  });
}
