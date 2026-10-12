import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/core/utils/rtl_text_field_utils.dart';
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

/// Stands in for what the tasks screen gives the form: each event's assigned
/// members, pushed by the test, and a save whose answer the test decides.
class _Form {
  /// Every task the form asked to save, in order.
  final saved = <TaskItem>[];

  /// The events whose assigned members the form asked for, in order.
  final watched = <String>[];

  /// What a save answers. Null leaves it unanswered until the test completes
  /// [pendingSave].
  CrudActionResult? saveResult = const CrudActionResult.success();
  Completer<CrudActionResult>? pendingSave;

  late _Result<bool> dialog;

  final _assignees = <String, BehaviorSubject<List<TeamMember>>>{};

  bool get closed => dialog.returned;

  BehaviorSubject<List<TeamMember>> _subject(String eventId) =>
      _assignees.putIfAbsent(eventId, BehaviorSubject<List<TeamMember>>.new);

  /// Who is assigned to [eventId] from now on. An event never set here stays
  /// "still loading".
  void setAssignees(String eventId, List<TeamMember> members) =>
      _subject(eventId).add(members);

  Stream<List<TeamMember>> watch(String eventId) {
    watched.add(eventId);
    return _subject(eventId).stream;
  }

  Future<CrudActionResult> save(TaskItem task) {
    saved.add(task);
    final result = saveResult;
    if (result != null) return Future.value(result);
    return (pendingSave = Completer<CrudActionResult>()).future;
  }

  void dispose() {
    for (final subject in _assignees.values) {
      unawaited(subject.close());
    }
  }
}

/// Stands in for what the tasks screen gives the status-note dialog: a save
/// whose answer the test decides.
class _Note {
  /// Every text the dialog asked to save, in order.
  final saved = <String>[];

  /// What a save answers. Null leaves it unanswered until the test completes
  /// [pendingSave].
  CrudActionResult? saveResult = const CrudActionResult.success();
  Completer<CrudActionResult>? pendingSave;

  late _Result<bool> dialog;

  bool get closed => dialog.returned;

  Future<CrudActionResult> save(String text) {
    saved.add(text);
    final result = saveResult;
    if (result != null) return Future.value(result);
    return (pendingSave = Completer<CrudActionResult>()).future;
  }
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
    Future<_Form> openForm(
      WidgetTester tester, {
      TaskItem? existing,
      List<Event>? events,
      Map<String, List<TeamMember>>? assignees,
    }) async {
      final form = _Form();
      addTearDown(form.dispose);
      (assignees ??
              {
                'e0': [dana, yoav],
                'e1': [dana, yoav],
                'e2': [dana, yoav],
              })
          .forEach(form.setAssignees);
      form.dialog = await _openDialog<bool>(
        tester,
        (context) async {
          await showTaskFormModal(
            context,
            existing: existing,
            events: events ?? [north, south, past],
            watchEventAssignees: form.watch,
            onSave: form.save,
            currentUserId: 'm-admin',
            now: now,
          );
          return true;
        },
      );
      return form;
    }

    Future<void> pickEvent(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('task-form-event')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(name).last);
      await tester.pumpAndSettle();
    }

    final assigneesField = find.byKey(const Key('task-form-assignees'));
    final assigneesMenu = find.byKey(const Key('task-form-assignee-menu'));
    final search = find.byKey(const Key('task-form-assignee-search'));
    Finder row(String id) => find.byKey(Key('task-form-assignee-$id'));

    Future<void> toggleAssignees(WidgetTester tester) async {
      await tester.tap(assigneesField);
      await tester.pump();
    }

    /// Ticks or unticks a member, opening the dropdown first when needed.
    Future<void> pickAssignee(WidgetTester tester, String id) async {
      if (assigneesMenu.evaluate().isEmpty) await toggleAssignees(tester);
      await tester.tap(row(id));
      await tester.pump();
    }

    bool isTicked(WidgetTester tester, String id) =>
        tester.widget<CheckboxListTile>(row(id)).value ?? false;

    bool saveEnabled(WidgetTester tester) => tester
        .widget<FilledButton>(find.byKey(const Key('task-form-save')))
        .enabled;

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();
    }

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

      await pickAssignee(tester, 'm1');
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('a title of only spaces does not enable save', (tester) async {
      await openForm(tester);
      await pickEvent(tester, 'דו יומי צפון');
      await pickAssignee(tester, 'm1');
      await tester.enterText(find.byKey(const Key('task-form-title')), '   ');
      await tester.pump();

      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('creating saves a task with the chosen fields', (tester) async {
      final form = await openForm(tester);
      await pickEvent(tester, 'דו יומי דרום');
      await tester.enterText(
        find.byKey(const Key('task-form-title')),
        '  להזמין אוטובוס  ',
      );
      await tester.enterText(
        find.byKey(const Key('task-form-description')),
        'שני רכבים',
      );
      await pickAssignee(tester, 'm2');
      await pickAssignee(tester, 'm1');
      await tester.tap(find.byKey(const Key('task-form-add-subtask')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('task-form-subtask-0')),
        'הצעת מחיר',
      );
      await tester.pump();
      await save(tester);

      final task = form.saved.single;
      expect(task.id, isNotEmpty);
      expect(task.eventId, 'e2');
      expect(task.title, 'להזמין אוטובוס');
      expect(task.description, 'שני רכבים');
      // In the order they were picked.
      expect(task.assigneeIds, ['m2', 'm1']);
      expect(task.assignees, [yoav, dana]);
      expect(task.subtasks, hasLength(1));
      expect(task.subtasks.single.title, 'הצעת מחיר');
      expect(task.subtasks.single.id, isNotEmpty);
      expect(task.subtasks.single.isDone, isFalse);
      expect(task.dueAt, isNull);
      expect(task.createdById, 'm-admin');
    });

    testWidgets('two created tasks get different ids', (tester) async {
      Future<String> createOne() async {
        final form = await openForm(tester);
        await pickEvent(tester, 'דו יומי צפון');
        await tester.enterText(find.byKey(const Key('task-form-title')), 'א');
        await pickAssignee(tester, 'm1');
        await save(tester);
        return form.saved.single.id;
      }

      expect(await createOne(), isNot(await createOne()));
    });

    testWidgets('blank subtask rows are dropped on save', (tester) async {
      final form = await openForm(tester);
      await pickEvent(tester, 'דו יומי צפון');
      await tester.enterText(find.byKey(const Key('task-form-title')), 'כותרת');
      await pickAssignee(tester, 'm1');
      await tester.tap(find.byKey(const Key('task-form-add-subtask')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-add-subtask')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('task-form-subtask-1')), 'שלב');
      await tester.pump();
      await save(tester);

      expect(form.saved.single.subtasks.map((subtask) => subtask.title), ['שלב']);
    });

    testWidgets('editing starts from the task and saves the fields that were '
        'not touched', (tester) async {
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
      final form = await openForm(tester, existing: existing);

      expect(find.text('להזמין אוטובוס'), findsOneWidget);
      expect(find.text('שני רכבים'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('task-form-description')),
        'שלושה רכבים',
      );
      await tester.pump();
      await save(tester);

      final task = form.saved.single;
      expect(task.id, 't1');
      expect(task.eventId, 'e1');
      expect(task.title, 'להזמין אוטובוס');
      expect(task.description, 'שלושה רכבים');
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
      final form = await openForm(tester, existing: existing);

      await tester.enterText(
        find.byKey(const Key('task-form-subtask-0')),
        'הצעת מחיר מעודכנת',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-subtask-remove-1')));
      await tester.pump();
      await save(tester);

      expect(form.saved.single.subtasks, const [
        Subtask(id: 'a', title: 'הצעת מחיר מעודכנת', isDone: true),
      ]);
    });

    testWidgets('clearing the due date saves a task with no due date',
        (tester) async {
      final existing = buildTask(
        id: 't1',
        eventId: 'e1',
        event: north,
        assigneeIds: const ['m1'],
        assignees: [dana],
        dueAt: DateTime(2026, 10, 19, 7, 30),
      );
      final form = await openForm(tester, existing: existing);

      await tester.tap(find.byKey(const Key('task-form-due-clear')));
      await tester.pump();
      await save(tester);

      expect(form.saved.single.dueAt, isNull);
    });

    testWidgets('an invalid due time blocks the save and says why',
        (tester) async {
      final existing = buildTask(
        id: 't1',
        eventId: 'e1',
        event: north,
        assigneeIds: const ['m1'],
        assignees: [dana],
        dueAt: DateTime(2026, 10, 19, 7, 30),
      );
      final form = await openForm(tester, existing: existing);

      // Four digits the formatter lays out as 93:00, which is not a time.
      await tester.enterText(find.byType(TextFormField), '9300');
      await tester.pump();
      await save(tester);

      expect(form.saved, isEmpty, reason: 'nothing may be sent');
      expect(form.closed, isFalse, reason: 'the form must stay open');
      expect(find.byKey(const Key('task-form-due-time-error')), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '0930');
      await tester.pump();
      expect(find.byKey(const Key('task-form-due-time-error')), findsNothing);

      await save(tester);
      expect(form.saved.single.dueAt, DateTime(2026, 10, 19, 9, 30));
    });

    testWidgets('a due date with the time left empty is due at the end of '
        'that day', (tester) async {
      final existing = buildTask(
        id: 't1',
        eventId: 'e1',
        event: north,
        assigneeIds: const ['m1'],
        assignees: [dana],
        dueAt: DateTime(2026, 10, 19, 7, 30),
      );
      final form = await openForm(tester, existing: existing);

      await tester.enterText(find.byType(TextFormField), '');
      await tester.pump();
      await save(tester);

      expect(form.saved.single.dueAt, DateTime(2026, 10, 19, 23, 59));
    });

    testWidgets('the Hebrew text fields carry the RTL caret fix',
        (tester) async {
      final existing = buildTask(
        id: 't1',
        eventId: 'e1',
        event: north,
        assigneeIds: const ['m1'],
        assignees: [dana],
        subtasks: const [Subtask(id: 'a', title: 'שלב 1')],
      );
      await openForm(tester, existing: existing);

      for (final key in const [
        'task-form-title',
        'task-form-description',
        'task-form-subtask-0',
      ]) {
        final field = tester.widget<TextField>(find.byKey(Key(key)));
        expect(
          field.focusNode,
          isA<RtlCursorFixedFocusNode>(),
          reason: key,
        );
      }

      // A subtask row added later gets one too.
      await tester.tap(find.byKey(const Key('task-form-add-subtask')));
      await tester.pump();
      final added = tester.widget<TextField>(
        find.byKey(const Key('task-form-subtask-1')),
      );
      expect(added.focusNode, isA<RtlCursorFixedFocusNode>());
    });

    testWidgets('events are listed date first, so a long name cannot push the '
        'date out of view', (tester) async {
      await openForm(tester);
      await tester.tap(find.byKey(const Key('task-form-event')));
      await tester.pumpAndSettle();

      expect(find.text('20/10/2026 · דו יומי צפון'), findsWidgets);
      expect(find.text('27/10/2026 · דו יומי דרום'), findsWidgets);
    });

    testWidgets('a past event is not offered when creating', (tester) async {
      await openForm(tester);
      await tester.tap(find.byKey(const Key('task-form-event')));
      await tester.pumpAndSettle();

      expect(find.textContaining('דו יומי צפון'), findsWidgets);
      expect(find.textContaining('אירוע שעבר'), findsNothing);
    });

    testWidgets('an event outside the דו יומי category is not offered',
        (tester) async {
      final hanukkah = buildEvent(
        id: 'e9',
        name: 'הדלקת נרות',
        startDate: DateTime(2026, 10, 22),
        categoryId: '6de41bf3-1a22-476d-b922-ec35ede6bc9f',
      );
      await openForm(tester, events: [north, hanukkah]);
      await tester.tap(find.byKey(const Key('task-form-event')));
      await tester.pumpAndSettle();

      expect(find.textContaining('דו יומי צפון'), findsWidgets);
      expect(find.textContaining('הדלקת נרות'), findsNothing);
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
      final form = await openForm(tester, existing: existing);

      expect(find.textContaining('אירוע שעבר'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('task-form-title')), 'אחר');
      await tester.pump();
      await save(tester);

      expect(form.saved.single.eventId, 'e0');
    });

    group('assignee dropdown', () {
      testWidgets('cannot be opened before an event is chosen', (tester) async {
        final form = await openForm(tester);
        expect(find.text('יש לבחור אירוע תחילה'), findsOneWidget);

        await toggleAssignees(tester);

        expect(assigneesMenu, findsNothing);
        expect(form.watched, isEmpty);
      });

      testWidgets('opens once an event is chosen, search row on top of the '
          'members', (tester) async {
        await openForm(tester);
        await pickEvent(tester, 'דו יומי צפון');
        expect(find.text('יש לבחור אירוע תחילה'), findsNothing);

        await toggleAssignees(tester);

        expect(search, findsOneWidget);
        expect(row('m1'), findsOneWidget);
        expect(row('m2'), findsOneWidget);
        expect(
          tester.getTopLeft(search).dy,
          lessThan(tester.getTopLeft(row('m1')).dy),
        );
      });

      testWidgets('has no search row and no member rows while closed',
          (tester) async {
        await openForm(tester);
        await pickEvent(tester, 'דו יומי צפון');
        expect(search, findsNothing);
        expect(row('m1'), findsNothing);

        await toggleAssignees(tester);
        expect(search, findsOneWidget);

        await toggleAssignees(tester);
        expect(search, findsNothing);
        expect(row('m1'), findsNothing);
      });

      testWidgets('lists the members assigned to the chosen event only',
          (tester) async {
        final form = await openForm(tester, assignees: {
          'e1': [dana],
          'e2': [yoav],
        });
        await pickEvent(tester, 'דו יומי צפון');
        await toggleAssignees(tester);

        expect(form.watched, ['e1']);
        expect(row('m1'), findsOneWidget);
        expect(row('m2'), findsNothing);
      });

      testWidgets('cannot be opened until the event\'s members have arrived',
          (tester) async {
        final form = await openForm(tester, assignees: const {});
        await pickEvent(tester, 'דו יומי צפון');
        expect(find.text('טוען משובצים...'), findsOneWidget);

        await toggleAssignees(tester);
        expect(assigneesMenu, findsNothing);

        form.setAssignees('e1', [dana]);
        // The field's helper text fades out rather than vanishing.
        await tester.pumpAndSettle();
        expect(find.text('טוען משובצים...'), findsNothing);

        await toggleAssignees(tester);
        expect(row('m1'), findsOneWidget);
      });

      testWidgets('a member assigned while the form is open appears, and one '
          'unassigned disappears', (tester) async {
        final form = await openForm(tester, assignees: {
          'e1': [dana],
        });
        await pickEvent(tester, 'דו יומי צפון');
        await toggleAssignees(tester);
        expect(row('m2'), findsNothing);

        form.setAssignees('e1', [dana, yoav]);
        await tester.pump();
        expect(row('m2'), findsOneWidget);

        form.setAssignees('e1', [yoav]);
        await tester.pump();
        expect(row('m1'), findsNothing);
        expect(row('m2'), findsOneWidget);
      });

      testWidgets('a picked member who is then unassigned from the event stays '
          'listed and picked', (tester) async {
        final form = await openForm(tester, assignees: {
          'e1': [dana, yoav],
        });
        await pickEvent(tester, 'דו יומי צפון');
        await tester.enterText(find.byKey(const Key('task-form-title')), 'כותרת');
        await pickAssignee(tester, 'm1');

        form.setAssignees('e1', [yoav]);
        await tester.pump();

        expect(isTicked(tester, 'm1'), isTrue);
        await save(tester);
        expect(form.saved.single.assigneeIds, ['m1']);
      });

      testWidgets('changing the event swaps the list and clears who was picked',
          (tester) async {
        final form = await openForm(tester, assignees: {
          'e1': [dana],
          'e2': [yoav],
        });
        await pickEvent(tester, 'דו יומי צפון');
        await tester.enterText(find.byKey(const Key('task-form-title')), 'כותרת');
        await pickAssignee(tester, 'm1');
        expect(saveEnabled(tester), isTrue);

        await pickEvent(tester, 'דו יומי דרום');

        expect(form.watched, ['e1', 'e2']);
        expect(saveEnabled(tester), isFalse);
        expect(assigneesMenu, findsNothing);
        await toggleAssignees(tester);
        expect(row('m1'), findsNothing);
        expect(isTicked(tester, 'm2'), isFalse);
      });

      testWidgets('an event with nobody assigned says so', (tester) async {
        await openForm(tester, assignees: const {'e1': []});
        await pickEvent(tester, 'דו יומי צפון');
        await toggleAssignees(tester);

        expect(find.text('אין משובצים לאירוע זה'), findsOneWidget);
        expect(search, findsNothing);
      });

      testWidgets('the closed field names who was picked', (tester) async {
        await openForm(tester);
        await pickEvent(tester, 'דו יומי צפון');
        await pickAssignee(tester, 'm2');
        await pickAssignee(tester, 'm1');
        await toggleAssignees(tester);

        expect(assigneesMenu, findsNothing);
        expect(find.text('יואב, דנה'), findsOneWidget);
      });

      testWidgets('unticking a member removes them from the task',
          (tester) async {
        final form = await openForm(tester);
        await pickEvent(tester, 'דו יומי צפון');
        await tester.enterText(find.byKey(const Key('task-form-title')), 'כותרת');
        await pickAssignee(tester, 'm1');
        await pickAssignee(tester, 'm2');
        await pickAssignee(tester, 'm1');
        await save(tester);

        expect(form.saved.single.assigneeIds, ['m2']);
      });

      testWidgets('editing lists the event\'s members with the task\'s '
          'assignees ticked', (tester) async {
        final existing = buildTask(
          id: 't1',
          eventId: 'e1',
          event: north,
          assigneeIds: const ['m2'],
          assignees: [yoav],
        );
        final form = await openForm(tester, existing: existing);
        expect(form.watched, ['e1']);

        await toggleAssignees(tester);

        expect(isTicked(tester, 'm1'), isFalse);
        expect(isTicked(tester, 'm2'), isTrue);
      });

      testWidgets('editing keeps an assignee who is not assigned to the event',
          (tester) async {
        final existing = buildTask(
          id: 't1',
          eventId: 'e1',
          event: north,
          assigneeIds: const ['m3', 'm1'],
          assignees: [archived, dana],
        );
        final form = await openForm(tester, existing: existing, assignees: {
          'e1': [dana, yoav],
        });
        await toggleAssignees(tester);

        expect(isTicked(tester, 'm3'), isTrue);
        await pickAssignee(tester, 'm2');
        await save(tester);
        expect(form.saved.single.assigneeIds, ['m3', 'm1', 'm2']);
      });
    });

    group('assignee search', () {
      final avi = buildMember(id: 'm4', name: "ג'ורג' אבי");
      final everyone = {
        'e1': [dana, yoav, avi],
      };

      Future<_Form> openSearch(WidgetTester tester) async {
        final form = await openForm(tester, assignees: everyone);
        await pickEvent(tester, 'דו יומי צפון');
        await toggleAssignees(tester);
        return form;
      }

      testWidgets('typing narrows the rows to matching names', (tester) async {
        await openSearch(tester);
        expect(row('m1'), findsOneWidget);
        expect(row('m2'), findsOneWidget);

        await tester.enterText(search, 'יוא');
        await tester.pump();

        expect(row('m2'), findsOneWidget);
        expect(row('m1'), findsNothing);
        expect(row('m4'), findsNothing);
      });

      testWidgets('matches in the middle of a name and ignores punctuation',
          (tester) async {
        await openSearch(tester);

        await tester.enterText(search, 'גורג');
        await tester.pump();
        expect(row('m4'), findsOneWidget);

        await tester.enterText(search, 'אבי');
        await tester.pump();
        expect(row('m4'), findsOneWidget);
        expect(row('m1'), findsNothing);
      });

      testWidgets('clearing the search shows everyone again', (tester) async {
        await openSearch(tester);
        await tester.enterText(search, 'יוא');
        await tester.pump();
        expect(row('m1'), findsNothing);

        await tester.tap(find.byKey(const Key('task-form-assignee-search-clear')));
        await tester.pump();

        expect(row('m1'), findsOneWidget);
        expect(row('m2'), findsOneWidget);
        expect(row('m4'), findsOneWidget);
        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      });

      testWidgets('a search that matches nobody says so', (tester) async {
        await openSearch(tester);

        await tester.enterText(search, 'קקטוס');
        await tester.pump();

        expect(find.text('לא נמצאו חברי צוות'), findsOneWidget);
      });

      testWidgets('reopening the dropdown starts with an empty search',
          (tester) async {
        await openSearch(tester);
        await tester.enterText(search, 'יוא');
        await tester.pump();

        await toggleAssignees(tester);
        await toggleAssignees(tester);

        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        expect(row('m1'), findsOneWidget);
      });

      testWidgets('searching for someone does not change who else is assigned',
          (tester) async {
        final form = await openSearch(tester);
        await tester.enterText(find.byKey(const Key('task-form-title')), 'כותרת');
        await pickAssignee(tester, 'm1');

        // Search hides the first pick while the second is found and picked.
        await tester.enterText(search, 'יוא');
        await tester.pump();
        expect(row('m1'), findsNothing);
        await pickAssignee(tester, 'm2');
        await save(tester);

        expect(form.saved.single.assigneeIds, ['m1', 'm2']);
      });

      testWidgets('picking someone found by search empties the search and '
          'puts the cursor back in it', (tester) async {
        // On the web a press outside a text field takes the focus away from
        // it, as on desktop. The default test platform does not, which would
        // let this pass without the form asking for the focus back.
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await openSearch(tester);
          await tester.enterText(search, 'יוא');
          await tester.pump();

          await tester.tap(row('m2'));
          await tester.pump();

          final field = tester.widget<TextField>(search);
          expect(field.controller!.text, isEmpty);
          expect(field.focusNode!.hasFocus, isTrue);
          expect(isTicked(tester, 'm2'), isTrue);
          expect(row('m1'), findsOneWidget, reason: 'everyone is listed again');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('unticking someone found by search does the same',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await openSearch(tester);
          await pickAssignee(tester, 'm2');
          await tester.enterText(search, 'יוא');
          await tester.pump();

          await tester.tap(row('m2'));
          await tester.pump();

          final field = tester.widget<TextField>(search);
          expect(field.controller!.text, isEmpty);
          expect(field.focusNode!.hasFocus, isTrue);
          expect(isTicked(tester, 'm2'), isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('picking with no search typed does not grab the focus',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await openSearch(tester);

          await tester.tap(row('m2'));
          await tester.pump();

          expect(
            tester.widget<TextField>(search).focusNode!.hasFocus,
            isFalse,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('the search field carries the RTL caret fix', (tester) async {
        await openSearch(tester);
        expect(
          tester.widget<TextField>(search).focusNode,
          isA<RtlCursorFixedFocusNode>(),
        );
      });
    });

    group('saving', () {
      Future<_Form> openFilled(WidgetTester tester) async {
        final form = await openForm(tester);
        await pickEvent(tester, 'דו יומי צפון');
        await tester.enterText(find.byKey(const Key('task-form-title')), 'כותרת');
        await pickAssignee(tester, 'm1');
        return form;
      }

      final spinner = find.descendant(
        of: find.byKey(const Key('task-form-save')),
        matching: find.byType(CircularProgressIndicator),
      );

      testWidgets('shows a spinner and stays open until the save is answered',
          (tester) async {
        final form = await openFilled(tester);
        form.saveResult = null;
        expect(spinner, findsNothing);

        await tester.tap(find.byKey(const Key('task-form-save')));
        await tester.pump();

        expect(spinner, findsOneWidget);
        expect(form.closed, isFalse);

        form.pendingSave!.complete(const CrudActionResult.success());
        await tester.pumpAndSettle();

        expect(form.closed, isTrue);
      });

      testWidgets('cannot be saved twice, cancelled or edited while saving',
          (tester) async {
        final form = await openFilled(tester);
        form.saveResult = null;
        await tester.tap(find.byKey(const Key('task-form-save')));
        await tester.pump();

        expect(saveEnabled(tester), isFalse);
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('task-form-cancel')))
              .enabled,
          isFalse,
        );
        await tester.tap(
          find.byKey(const Key('task-form-add-subtask')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(find.byKey(const Key('task-form-subtask-0')), findsNothing);
        expect(form.saved, hasLength(1));

        form.pendingSave!.complete(const CrudActionResult.success());
        await tester.pumpAndSettle();
      });

      testWidgets('a failed save keeps the form open with the reason and what '
          'was typed', (tester) async {
        final form = await openFilled(tester);
        form.saveResult =
            const CrudActionResult.failure('אין הרשאה ליצור משימות');

        await save(tester);

        expect(form.closed, isFalse);
        expect(find.text('אין הרשאה ליצור משימות'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('task-form-title')))
              .controller!
              .text,
          'כותרת',
        );
        expect(isTicked(tester, 'm1'), isTrue);
        expect(spinner, findsNothing);
        expect(saveEnabled(tester), isTrue);
      });

      testWidgets('retrying after a failure sends the same task again and '
          'closes on success', (tester) async {
        final form = await openFilled(tester);
        form.saveResult = const CrudActionResult.failure('תקלה');
        await save(tester);

        form.saveResult = const CrudActionResult.success();
        await save(tester);

        expect(form.closed, isTrue);
        expect(form.saved, hasLength(2));
        expect(form.saved.last.id, form.saved.first.id);
      });
    });

    group('unsaved changes', () {
      final existing = buildTask(
        id: 't1',
        eventId: 'e1',
        event: north,
        title: 'להזמין אוטובוס',
        description: 'שני רכבים',
        dueAt: DateTime(2026, 10, 19, 7, 30),
        assigneeIds: const ['m1'],
        assignees: [dana],
        subtasks: const [Subtask(id: 'a', title: 'הצעת מחיר')],
      );

      final title = find.byKey(const Key('task-form-title'));
      final description = find.byKey(const Key('task-form-description'));
      final cancel = find.byKey(const Key('task-form-cancel'));
      final stay = find.byKey(const Key('task-form-discard-stay'));
      final leave = find.byKey(const Key('task-form-discard-leave'));

      Future<void> type(WidgetTester tester, Finder field, String text) async {
        await tester.enterText(field, text);
        await tester.pump();
      }

      testWidgets('an edit with nothing changed cannot be saved',
          (tester) async {
        await openForm(tester, existing: existing);
        expect(saveEnabled(tester), isFalse);
      });

      testWidgets('changing the title enables save, and putting it back '
          'disables it again', (tester) async {
        await openForm(tester, existing: existing);

        await type(tester, title, 'להזמין שני אוטובוסים');
        expect(saveEnabled(tester), isTrue);

        await type(tester, title, 'להזמין אוטובוס');
        expect(saveEnabled(tester), isFalse);
      });

      testWidgets('spaces around the title are not a change', (tester) async {
        await openForm(tester, existing: existing);

        await type(tester, title, '  להזמין אוטובוס ');
        expect(saveEnabled(tester), isFalse);
      });

      testWidgets('changing the description enables save', (tester) async {
        await openForm(tester, existing: existing);

        await type(tester, description, 'שלושה רכבים');
        expect(saveEnabled(tester), isTrue);

        await type(tester, description, 'שני רכבים');
        expect(saveEnabled(tester), isFalse);
      });

      testWidgets('picking another assignee enables save, and unpicking them '
          'disables it again', (tester) async {
        await openForm(tester, existing: existing);

        await pickAssignee(tester, 'm2');
        expect(saveEnabled(tester), isTrue);

        await pickAssignee(tester, 'm2');
        expect(saveEnabled(tester), isFalse);
      });

      testWidgets('renaming, adding or removing a subtask enables save',
          (tester) async {
        await openForm(tester, existing: existing);
        final first = find.byKey(const Key('task-form-subtask-0'));

        await type(tester, first, 'הצעת מחיר מעודכנת');
        expect(saveEnabled(tester), isTrue);
        await type(tester, first, 'הצעת מחיר');
        expect(saveEnabled(tester), isFalse);

        // An empty row is dropped on save, so it is not a change yet.
        await tester.tap(find.byKey(const Key('task-form-add-subtask')));
        await tester.pump();
        expect(saveEnabled(tester), isFalse);
        await type(
          tester,
          find.byKey(const Key('task-form-subtask-1')),
          'אישור',
        );
        expect(saveEnabled(tester), isTrue);

        await tester.tap(find.byKey(const Key('task-form-subtask-remove-1')));
        await tester.pump();
        expect(saveEnabled(tester), isFalse);

        await tester.tap(find.byKey(const Key('task-form-subtask-remove-0')));
        await tester.pump();
        expect(saveEnabled(tester), isTrue);
      });

      testWidgets('changing the due time or clearing the due date enables save',
          (tester) async {
        await openForm(tester, existing: existing);

        await type(tester, find.byType(TextFormField), '0930');
        expect(saveEnabled(tester), isTrue);
        await type(tester, find.byType(TextFormField), '0730');
        expect(saveEnabled(tester), isFalse);

        await tester.tap(find.byKey(const Key('task-form-due-clear')));
        await tester.pump();
        expect(saveEnabled(tester), isTrue);
      });

      testWidgets('cancel on an untouched new task closes at once',
          (tester) async {
        final form = await openForm(tester);

        await tester.tap(cancel);
        await tester.pumpAndSettle();

        expect(form.closed, isTrue);
        expect(form.saved, isEmpty);
      });

      testWidgets('cancel on an untouched edit closes at once', (tester) async {
        final form = await openForm(tester, existing: existing);

        await tester.tap(cancel);
        await tester.pumpAndSettle();

        expect(form.closed, isTrue);
      });

      testWidgets('cancel on a new task with something typed asks first, and '
          'staying keeps the form as it was', (tester) async {
        final form = await openForm(tester);
        await type(tester, title, 'כותרת');

        await tester.tap(cancel);
        await tester.pumpAndSettle();

        expect(form.closed, isFalse);
        expect(find.text('שינויים לא נשמרו'), findsOneWidget);

        await tester.tap(stay);
        await tester.pumpAndSettle();

        expect(form.closed, isFalse);
        expect(find.text('שינויים לא נשמרו'), findsNothing);
        expect(tester.widget<TextField>(title).controller!.text, 'כותרת');
      });

      testWidgets('confirming the prompt closes the form without saving',
          (tester) async {
        final form = await openForm(tester);
        await type(tester, title, 'כותרת');

        await tester.tap(cancel);
        await tester.pumpAndSettle();
        await tester.tap(leave);
        await tester.pumpAndSettle();

        expect(form.closed, isTrue);
        expect(form.saved, isEmpty);
      });

      testWidgets('cancel on an edit with a change asks first', (tester) async {
        final form = await openForm(tester, existing: existing);
        await type(tester, description, 'שלושה רכבים');

        await tester.tap(cancel);
        await tester.pumpAndSettle();

        expect(form.closed, isFalse);
        expect(leave, findsOneWidget);
      });

      testWidgets('cancel after picking only an event asks first',
          (tester) async {
        final form = await openForm(tester);
        await pickEvent(tester, 'דו יומי צפון');

        await tester.tap(cancel);
        await tester.pumpAndSettle();

        expect(form.closed, isFalse);
        expect(leave, findsOneWidget);
      });
    });
  });

  group('task filter', () {
    /// Opens the filter and returns every selection it reported, in order.
    Future<List<TaskFilterSelection>> openFilter(
      WidgetTester tester, {
      TaskFilterSelection current = const TaskFilterSelection(),
      List<Event>? events,
      List<TeamMember>? members,
    }) async {
      final reported = <TaskFilterSelection>[];
      await _openDialog<bool>(
        tester,
        (context) async {
          await showTaskFilterModal(
            context,
            current: current,
            events: events ?? [north, south],
            members: members ?? [dana, yoav],
            onChanged: reported.add,
          );
          return true;
        },
      );
      return reported;
    }

    final closeButton = find.byKey(const Key('filter-close'));

    testWidgets('every tick is reported at once, with no apply step',
        (tester) async {
      final reported = await openFilter(tester);
      expect(find.byKey(const Key('filter-apply')), findsNothing);

      await tester.tap(find.byKey(const Key('filter-status-overdue')));
      await tester.pump();
      expect(reported, [
        const TaskFilterSelection(statuses: {TaskDueStatus.overdue}),
      ]);

      await tester.tap(find.byKey(const Key('filter-event-e2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-assignee-m1')));
      await tester.pump();

      expect(
        reported.last,
        const TaskFilterSelection(
          statuses: {TaskDueStatus.overdue},
          eventIds: {'e2'},
          assigneeIds: {'m1'},
        ),
      );
      expect(reported, hasLength(3));
    });

    testWidgets('ticking the half-hour option reports it at once',
        (tester) async {
      final reported = await openFilter(tester);
      expect(find.text('משימות לחצי שעה הקרובה'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-due-soon')));
      await tester.pump();

      expect(reported, [const TaskFilterSelection(dueSoon: true)]);
    });

    testWidgets('starts from the current selection, and unticking reports '
        'what is left', (tester) async {
      final reported = await openFilter(
        tester,
        current: const TaskFilterSelection(
          dueSoon: true,
          statuses: {TaskDueStatus.completed},
          eventIds: {'e1'},
        ),
      );

      bool ticked(String key) =>
          tester.widget<CheckboxListTile>(find.byKey(Key(key))).value ?? false;
      expect(ticked('filter-due-soon'), isTrue);
      expect(ticked('filter-status-completed'), isTrue);
      expect(ticked('filter-event-e1'), isTrue);
      expect(ticked('filter-event-e2'), isFalse);

      await tester.tap(find.byKey(const Key('filter-status-completed')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-due-soon')));
      await tester.pump();

      expect(reported.last, const TaskFilterSelection(eventIds: {'e1'}));
    });

    testWidgets('a reported selection is not changed by later ticks',
        (tester) async {
      final reported = await openFilter(tester);

      await tester.tap(find.byKey(const Key('filter-event-e1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-event-e2')));
      await tester.pump();

      expect(reported.first, const TaskFilterSelection(eventIds: {'e1'}));
    });

    testWidgets('events with the same name are told apart by their date',
        (tester) async {
      final first = buildEvent(
        id: 'd1',
        name: 'דו יומי',
        startDate: DateTime(2026, 10, 20),
      );
      final second = buildEvent(
        id: 'd2',
        name: 'דו יומי',
        startDate: DateTime(2026, 11, 3),
      );
      await openFilter(tester, events: [first, second], members: const []);

      expect(find.text('דו יומי'), findsNWidgets(2));
      expect(find.text('20/10/2026'), findsOneWidget);
      expect(find.text('03/11/2026'), findsOneWidget);
    });

    testWidgets('clear reports an empty selection, unticks everything and '
        'leaves the filter open', (tester) async {
      final reported = await openFilter(
        tester,
        current: const TaskFilterSelection(dueSoon: true, eventIds: {'e1'}),
      );

      await tester.tap(find.byKey(const Key('filter-clear')));
      await tester.pumpAndSettle();

      expect(reported, [const TaskFilterSelection()]);
      expect(reported.single.isEmpty, isTrue);
      expect(closeButton, findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('filter-event-e1')))
            .value,
        isFalse,
      );
    });

    testWidgets('close shuts the filter and reports nothing more',
        (tester) async {
      final reported = await openFilter(tester);
      await tester.tap(find.byKey(const Key('filter-status-open')));
      await tester.pump();

      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(closeButton, findsNothing);
      expect(reported, [
        const TaskFilterSelection(statuses: {TaskDueStatus.open}),
      ]);
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
      expect(const TaskFilterSelection(dueSoon: true).activeCount, 1);
      expect(const TaskFilterSelection(dueSoon: true).isEmpty, isFalse);
    });
  });

  group('assignee update dialog', () {
    Future<_Note> openUpdate(
      WidgetTester tester, {
      String? initialText,
    }) async {
      final note = _Note();
      note.dialog = await _openDialog<bool>(
        tester,
        (context) async {
          await showAssigneeUpdateDialog(
            context,
            initialText: initialText,
            onSave: note.save,
          );
          return true;
        },
      );
      return note;
    }

    final text = find.byKey(const Key('assignee-update-text'));
    final saveButton = find.byKey(const Key('assignee-update-save'));
    final spinner = find.descendant(
      of: saveButton,
      matching: find.byType(CircularProgressIndicator),
    );

    testWidgets('saves the typed text, trimmed, and closes', (tester) async {
      final note = await openUpdate(tester);

      await tester.enterText(text, '  ממתין לאישור  ');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(note.saved, ['ממתין לאישור']);
      expect(note.closed, isTrue);
    });

    testWidgets('starts from the current update', (tester) async {
      await openUpdate(tester, initialText: 'בטיפול');
      expect(find.text('בטיפול'), findsOneWidget);
    });

    testWidgets('opens with the caret at the end of a mixed Hebrew and digit '
        'note', (tester) async {
      const existing = 'הוזמנו 2 אוטובוסים';
      await openUpdate(tester, initialText: existing);
      await tester.pump();

      final field = tester.widget<TextField>(text);
      expect(field.focusNode, isA<RtlCursorFixedFocusNode>());
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: existing.length),
      );
    });

    testWidgets('emptying the text saves an empty string, which clears it',
        (tester) async {
      final note = await openUpdate(tester, initialText: 'בטיפול');

      await tester.enterText(text, '');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(note.saved, ['']);
      expect(note.closed, isTrue);
    });

    testWidgets('shows a spinner and stays open until the save is answered',
        (tester) async {
      final note = await openUpdate(tester);
      note.saveResult = null;
      await tester.enterText(text, 'בטיפול');
      expect(spinner, findsNothing);

      await tester.tap(saveButton);
      await tester.pump();

      expect(spinner, findsOneWidget);
      expect(note.closed, isFalse);
      expect(tester.widget<FilledButton>(saveButton).enabled, isFalse);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('assignee-update-cancel')),
            )
            .enabled,
        isFalse,
      );

      note.pendingSave!.complete(const CrudActionResult.success());
      await tester.pumpAndSettle();

      expect(note.closed, isTrue);
    });

    testWidgets('a failed save stays open with the reason and what was typed',
        (tester) async {
      final note = await openUpdate(tester);
      note.saveResult =
          const CrudActionResult.failure('אין הרשאה לעדכן את המשימה');
      await tester.enterText(text, 'בטיפול');

      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(note.closed, isFalse);
      expect(find.text('אין הרשאה לעדכן את המשימה'), findsOneWidget);
      expect(tester.widget<TextField>(text).controller!.text, 'בטיפול');
      expect(spinner, findsNothing);
      expect(tester.widget<FilledButton>(saveButton).enabled, isTrue);
    });

    testWidgets('cancel closes without saving', (tester) async {
      final note = await openUpdate(tester, initialText: 'בטיפול');

      await tester.enterText(text, 'משהו אחר');
      await tester.tap(find.byKey(const Key('assignee-update-cancel')));
      await tester.pumpAndSettle();

      expect(note.closed, isTrue);
      expect(note.saved, isEmpty);
    });
  });
}
