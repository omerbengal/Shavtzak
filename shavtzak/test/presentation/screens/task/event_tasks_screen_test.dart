import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart' show DateCellValue;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/environment_service.dart';
import 'package:shavtzak/core/services/task_import_files.dart';
import 'package:shavtzak/core/theme/app_theme.dart';
import 'package:shavtzak/core/utils/rtl_text_field_utils.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/task/event_tasks_screen.dart';
import 'package:shavtzak/presentation/screens/task/widgets/legacy_stage_list.dart';
import 'package:shavtzak/presentation/screens/task/widgets/member_timeline.dart';

import '../../../support/event_tasks_harness.dart';
import '../../../support/fake_task_import_files.dart';
import '../../../support/fake_task_repository.dart';
import '../../../support/import_workbook.dart';
import '../../../support/sample_event.dart';
import '../../../support/task_fixtures.dart';

void main() {
  // Sunday afternoon; the event is the next Tuesday and Wednesday.
  final event = buildEvent(
    id: 'e1',
    name: 'דו יומי צפון',
    startDate: DateTime(2026, 10, 20),
    endDate: DateTime(2026, 10, 21),
    location: 'מלון קיסר',
  );
  // Every task in this file sits under it unless it says otherwise.
  final arrival = buildStage(
    id: 'st1',
    eventId: 'e1',
    title: 'קליטה',
    date: DateTime(2026, 10, 20),
    startTime: '08:00',
  );
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yoav = buildMember(id: 'm2', name: 'יואב');
  final admin = buildMember(id: 'boss', name: 'מנהלת', isAdmin: true);

  final mine = buildTask(
    id: 'mine',
    title: 'להזמין אוטובוס',
    event: event,
    stage: arrival,
    assigneeIds: const ['m1'],
    assignees: [dana],
  );
  final theirs = buildTask(
    id: 'theirs',
    title: 'הזמנת קייטרינג',
    event: event,
    stage: arrival,
    assigneeIds: const ['m2'],
    assignees: [yoav],
  );
  final withSubtasks = buildTask(
    id: 'steps',
    title: 'אישור ביטחוני',
    event: event,
    stage: arrival,
    assigneeIds: const ['m1'],
    assignees: [dana],
    subtasks: const [
      Subtask(id: 'a', title: 'טופס'),
      Subtask(id: 'b', title: 'חתימה'),
    ],
  );

  TaskBoard boardOf(List<TaskItem> tasks, {List<Stage>? stages}) => TaskBoard(
        tasks: tasks,
        events: [event],
        stages: stages ?? [arrival],
        members: [dana, yoav],
      );

  /// The mockups' event, at Tuesday 14:40.
  TaskBoard sampleTaskBoard({List<TaskItem>? tasks}) => TaskBoard(
        tasks: tasks ?? sampleTasks,
        events: [sampleEvent],
        stages: sampleStages,
        members: [sDana, sYoav],
      );

  late FakeTaskRepository repository;

  Future<void> pumpScreen(
    WidgetTester tester, {
    required TeamMember user,
    List<TaskItem>? tasks,
    List<Stage>? stages,
    Size size = tallPhoneSize,
    ThemeData? theme,
    String eventId = 'e1',
    FakeTaskImportFiles? importFiles,
  }) async {
    final harness = await pumpEventTasks(
      tester,
      user: user,
      size: size,
      theme: theme,
      eventId: eventId,
      importFiles: importFiles,
      board: tasks == null ? null : boardOf(tasks, stages: stages),
      assignees: {
        'e1': [dana, yoav],
      },
    );
    repository = harness.repository;
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  /// Opens a task of my timeline in the sheet, by its title.
  Future<void> openMyTask(WidgetTester tester, String id, String title) async {
    await tester.tap(find.descendant(
      of: find.byKey(Key('my-task-$id')),
      matching: find.text(title),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.tap(find.byKey(const Key('tasks-search-open')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('tasks-search')), query);
    await tester.pumpAndSettle();
  }

  /// Finds a task through the search and opens it in the sheet.
  Future<void> openBySearch(WidgetTester tester, String query, String id) async {
    await search(tester, query);
    await tester.tap(find.byKey(Key('task-row-$id')));
    await tester.pumpAndSettle();
  }

  Finder inSheet(Finder finder) =>
      find.descendant(of: find.byKey(const Key('task-sheet')), matching: finder);

  group('loading', () {
    testWidgets('shows a spinner until the first tasks arrive', (tester) async {
      final harness = await pumpEventTasks(tester, user: dana);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await harness.deliver(tester, const TaskBoard(tasks: []));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a load failure offers a retry that subscribes again',
        (tester) async {
      final harness = await pumpEventTasks(tester, user: dana);
      // Errors and stays open, like a Firestore listener killed by sign-out.
      harness.repository.controller.addError(Exception('permission-denied'));
      await tester.pump();
      await tester.pump();

      expect(find.text('טעינת המשימות נכשלה'), findsOneWidget);

      harness.repository.controller = StreamController<TaskBoard>();
      await tester.tap(find.byKey(const Key('tasks-retry')));
      await tester.pump();
      await harness.deliver(tester, boardOf([mine]));

      expect(harness.repository.watchCalls, 2);
      expect(find.byKey(const Key('my-task-mine')), findsOneWidget);
    });
  });

  group('tabs', () {
    testWidgets('a plain member lands on המשימות שלי', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine, theirs]);

      expect(find.byType(MemberTimeline), findsOneWidget);
      expect(find.byType(LegacyStageList), findsNothing);
    });

    testWidgets(
        'an admin, and a member allowed to manage tasks, land on כל השלבים',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      expect(find.byType(LegacyStageList), findsOneWidget);

      await pumpScreen(
        tester,
        user: buildMember(id: 'lead', name: 'אורי', canManageTasks: true),
        tasks: [mine],
      );
      expect(find.byType(LegacyStageList), findsOneWidget);
    });

    testWidgets('every member can open both tabs', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await openTab(tester, 'כל השלבים');
      expect(find.byType(LegacyStageList), findsOneWidget);

      await openTab(tester, 'המשימות שלי');
      expect(find.byType(MemberTimeline), findsOneWidget);
    });

    testWidgets('the selected tab is readable under the app theme',
        (tester) async {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final lighter = la > lb ? la : lb;
        final darker = la > lb ? lb : la;
        return (lighter + 0.05) / (darker + 0.05);
      }

      // The app theme's default selected-segment colours are white text on
      // light orange, which cannot be read.
      await pumpScreen(tester,
          user: dana, tasks: [mine], theme: AppTheme.lightTheme);

      final button = tester.widget<SegmentedButton<EventTasksTab>>(
        find.byType(SegmentedButton<EventTasksTab>),
      );
      const selected = {WidgetState.selected};
      final background = button.style!.backgroundColor!.resolve(selected)!;
      final foreground = button.style!.foregroundColor!.resolve(selected)!;
      expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
    });
  });

  group('search', () {
    testWidgets('the search icon opens a field with the RTL caret fix',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await tester.tap(find.byKey(const Key('tasks-search-open')));
      await tester.pump();

      final field = tester.widget<TextField>(find.byKey(const Key('tasks-search')));
      expect(field.focusNode, isA<RtlCursorFixedFocusNode>());
    });

    testWidgets('typing lists the matches in the sheet, grouped by stage',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine, theirs]);

      await search(tester, 'אוטובוס');

      expect(find.byKey(const Key('task-sheet')), findsOneWidget);
      expect(inSheet(find.text('חיפוש: "אוטובוס" · 1')), findsOneWidget);
      expect(inSheet(find.byKey(const Key('results-stage-st1'))), findsOneWidget);
      expect(inSheet(find.byKey(const Key('task-row-mine'))), findsOneWidget);
      expect(inSheet(find.byKey(const Key('task-row-theirs'))), findsNothing);
    });

    testWidgets('it finds tasks by an assignee\'s name', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine, theirs]);

      await search(tester, 'יואב');

      expect(inSheet(find.byKey(const Key('task-row-theirs'))), findsOneWidget);
      expect(inSheet(find.byKey(const Key('task-row-mine'))), findsNothing);
    });

    testWidgets('closing the search closes its sheet', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      await search(tester, 'אוטובוס');

      await tester.tap(find.byKey(const Key('tasks-search-close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('task-sheet')), findsNothing);
      expect(find.byKey(const Key('tasks-search')), findsNothing);
    });
  });

  group('sheet', () {
    testWidgets('a task opened from my timeline shows its detail, and X closes it',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await openMyTask(tester, 'mine', 'להזמין אוטובוס');
      expect(inSheet(find.byKey(const Key('task-detail-mine'))), findsOneWidget);

      await tester.tap(find.byKey(const Key('task-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-sheet')), findsNothing);
    });

    testWidgets('back returns to the list the task came from', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      await openBySearch(tester, 'אוטובוס', 'mine');
      expect(inSheet(find.byKey(const Key('task-detail-mine'))), findsOneWidget);

      await tester.tap(find.byKey(const Key('task-sheet-back')));
      await tester.pumpAndSettle();

      expect(inSheet(find.text('חיפוש: "אוטובוס" · 1')), findsOneWidget);
    });

    testWidgets('a task deleted while open goes back to its list',
        (tester) async {
      final harness = await pumpEventTasks(
        tester,
        user: dana,
        size: tallPhoneSize,
        board: boardOf([mine, theirs]),
      );
      await openBySearch(tester, 'אוטובוס', 'mine');

      await harness.deliver(tester, boardOf([theirs]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(inSheet(find.byKey(const Key('task-detail-mine'))), findsNothing);
      expect(inSheet(find.text('חיפוש: "אוטובוס" · 0')), findsOneWidget);
    });

    testWidgets('the late banner opens my late tasks', (tester) async {
      final setupLate = buildTask(
        id: 'setup-late',
        title: 'תליית שלטים',
        stage: stSetup,
        assemblyTime: '08:30',
        event: sampleEvent,
        assigneeIds: const ['m1'],
        assignees: [sDana],
      );
      await pumpEventTasks(
        tester,
        user: sDana,
        size: tallPhoneSize,
        clock: () => sampleNow,
        board: sampleTaskBoard(tasks: [...sampleTasks, setupLate]),
      );

      await tester.tap(find.byKey(const Key('my-late-banner')));
      await tester.pumpAndSettle();

      expect(inSheet(find.text('2 משימות שלך באיחור')), findsOneWidget);
      expect(inSheet(find.byKey(const Key('task-row-setup-late'))), findsOneWidget);
      expect(inSheet(find.byKey(const Key('task-row-lunch-late'))), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('ticking in my timeline is sent', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await tester.tap(find.byKey(const Key('my-task-tick-mine')));
      await tester.pump();

      expect(repository.calls, ['complete:mine:true']);
    });

    testWidgets('ticking a subtask is sent with that task and subtask',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [withSubtasks]);
      await openMyTask(tester, 'steps', 'אישור ביטחוני');

      await tester.tap(inSheet(find.descendant(
        of: find.byKey(const Key('subtask-b')),
        matching: find.byType(Checkbox),
      )));
      await tester.pump();

      expect(repository.calls, ['subtask:steps:b:true']);
    });

    testWidgets('completing a task without subtasks is sent', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      await openMyTask(tester, 'mine', 'להזמין אוטובוס');

      await tester.tap(find.byKey(const Key('task-complete-mine')));
      await tester.pump();

      expect(repository.calls, ['complete:mine:true']);
    });

    testWidgets('a ticked task is shown done before the backend answers',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      await openMyTask(tester, 'mine', 'להזמין אוטובוס');
      repository.gate = Completer<void>();

      await tester.tap(find.byKey(const Key('task-complete-mine')));
      await tester.pump();

      expect(repository.calls, ['complete:mine:true']);
      expect(
        tester.widget<Checkbox>(find.byKey(const Key('task-complete-mine'))).value,
        isTrue,
      );
      expect(inSheet(find.text('הושלמה')), findsOneWidget);

      repository.gate!.complete();
      await tester.pump();
    });

    testWidgets('a ticked subtask is shown done before the backend answers',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [withSubtasks]);
      await openMyTask(tester, 'steps', 'אישור ביטחוני');
      repository.gate = Completer<void>();

      final checkbox = inSheet(find.descendant(
        of: find.byKey(const Key('subtask-a')),
        matching: find.byType(Checkbox),
      ));
      await tester.tap(checkbox);
      await tester.pump();

      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(inSheet(find.text(ltr('1/2'))), findsOneWidget);

      repository.gate!.complete();
      await tester.pump();
    });

    testWidgets('a tick the backend refuses is taken back and explained',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      await openMyTask(tester, 'mine', 'להזמין אוטובוס');
      repository.gate = Completer<void>();
      repository.failWith = DatabaseException(
        'Failed backend mutation task.setComplete: אין הרשאה לעדכן את המשימה',
      );

      final box = find.byKey(const Key('task-complete-mine'));
      await tester.tap(box);
      await tester.pump();
      expect(tester.widget<Checkbox>(box).value, isTrue);

      repository.gate!.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.widget<Checkbox>(box).value, isFalse);
      expect(find.text('אין הרשאה לעדכן את המשימה'), findsOneWidget);
    });

    testWidgets('saving an update sends the typed text', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      await openMyTask(tester, 'mine', 'להזמין אוטובוס');

      await tester.tap(find.byKey(const Key('task-update-mine')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('assignee-update-text')),
        'ממתין לאישור',
      );
      await tester.tap(find.byKey(const Key('assignee-update-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['note:mine:ממתין לאישור']);
    });

    testWidgets('a failed action shows the backend message and keeps the list',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [withSubtasks]);
      await openMyTask(tester, 'steps', 'אישור ביטחוני');

      repository.failWith = DatabaseException(
        'Failed backend mutation task.setSubtaskDone: תת-המשימה לא נמצאה',
      );
      await tester.tap(inSheet(find.descendant(
        of: find.byKey(const Key('subtask-a')),
        matching: find.byType(Checkbox),
      )));
      await tester.pump();
      await tester.pump();

      expect(find.text('תת-המשימה לא נמצאה'), findsOneWidget);
      expect(find.byKey(const Key('my-task-steps')), findsOneWidget);
    });

    testWidgets('delete asks first, and cancelling deletes nothing',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      await openBySearch(tester, 'אוטובוס', 'mine');

      await tester.tap(find.byKey(const Key('task-delete-mine')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('task-delete-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-delete-cancel')));
      await tester.pumpAndSettle();

      expect(repository.calls, isEmpty);
    });

    testWidgets('confirming a delete sends it', (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      await openBySearch(tester, 'אוטובוס', 'mine');

      await tester.tap(find.byKey(const Key('task-delete-mine')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-delete-confirm')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['delete:mine']);
      expect(find.byKey(const Key('task-delete-confirm')), findsNothing);
    });

    testWidgets(
        'a confirmed delete shows a spinner and stays open until the '
        'backend answers', (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      await openBySearch(tester, 'אוטובוס', 'mine');
      await tester.tap(find.byKey(const Key('task-delete-mine')));
      await tester.pumpAndSettle();

      final confirm = find.byKey(const Key('task-delete-confirm'));
      final spinner = find.descendant(
        of: confirm,
        matching: find.byType(CircularProgressIndicator),
      );
      expect(spinner, findsNothing);

      repository.gate = Completer<void>();
      await tester.tap(confirm);
      await tester.pump();

      expect(repository.calls, ['delete:mine']);
      expect(spinner, findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).enabled, isFalse);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('task-delete-cancel')))
            .enabled,
        isFalse,
      );

      repository.gate!.complete();
      await tester.pumpAndSettle();

      expect(confirm, findsNothing);
    });

    testWidgets('a delete the backend refuses stays open and says why',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      await openBySearch(tester, 'אוטובוס', 'mine');
      await tester.tap(find.byKey(const Key('task-delete-mine')));
      await tester.pumpAndSettle();

      repository.failWith = DatabaseException(
        'Failed backend mutation task.delete: אין הרשאה למחוק משימות',
      );
      final confirm = find.byKey(const Key('task-delete-confirm'));
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(find.text('אין הרשאה למחוק משימות'), findsOneWidget);
      expect(confirm, findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).enabled, isTrue);
      expect(find.byKey(const Key('task-detail-mine')), findsOneWidget);
    });

    testWidgets('a manager edits a task through the form', (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      await openBySearch(tester, 'אוטובוס', 'mine');

      await tester.tap(find.byKey(const Key('task-edit-mine')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('task-form-title')),
        'להזמין שני אוטובוסים',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['update:mine']);
      expect(find.byKey(const Key('task-form-title')), findsNothing);
    });

    testWidgets('a member cannot tick someone else\'s task', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [theirs]);
      await openBySearch(tester, 'קייטרינג', 'theirs');

      expect(
        tester
            .widget<Checkbox>(find.byKey(const Key('task-complete-theirs')))
            .onChanged,
        isNull,
      );
      expect(find.byKey(const Key('task-edit-theirs')), findsNothing);
      expect(find.byKey(const Key('task-delete-theirs')), findsNothing);
    });
  });

  // Today's stage list stays on "כל השלבים" until the calendar replaces it.
  group('until the calendar lands', () {
    Future<void> openStage(WidgetTester tester) async {
      await tester.pumpAndSettle();
      if (find.byKey(const Key('stage-body-st1')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('stage-toggle-st1')));
        await tester.pump();
      }
    }

    Future<void> fillNewTask(WidgetTester tester, String title) async {
      await openStage(tester);
      await tester.tap(find.byKey(const Key('stage-add-task-st1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('task-form-title')), title);
      await tester.tap(find.byKey(const Key('task-form-assignees')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-assignee-m2')));
      await tester.pump();
    }

    testWidgets('managers get the new-stage and new-task buttons, members do not',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      await openStage(tester);
      expect(find.byKey(const Key('stage-add')), findsOneWidget);
      expect(find.byKey(const Key('stage-add-task-st1')), findsOneWidget);

      await pumpScreen(tester, user: dana, tasks: [mine]);
      await openTab(tester, 'כל השלבים');
      await openStage(tester);
      expect(find.byKey(const Key('stage-add')), findsNothing);
      expect(find.byKey(const Key('stage-add-task-st1')), findsNothing);
      expect(find.byKey(const Key('stage-edit-st1')), findsNothing);
    });

    testWidgets('a manager creates a task through the form', (tester) async {
      await pumpScreen(tester, user: admin, tasks: const []);
      await fillNewTask(tester, 'משימה חדשה לגמרי');
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['insert:משימה חדשה לגמרי']);
      expect(find.byKey(const Key('task-form-title')), findsNothing);
    });

    testWidgets(
        'the new-task form offers only the members assigned to the '
        'chosen event', (tester) async {
      await pumpScreen(tester, user: admin, tasks: const []);
      repository.assigneesByEvent = {
        'e1': [yoav],
      };
      await fillNewTask(tester, 'כותרת');

      expect(find.byKey(const Key('task-form-assignee-m2')), findsOneWidget);
      expect(find.byKey(const Key('task-form-assignee-m1')), findsNothing);
    });

    testWidgets('a create the backend refuses keeps the form open and says why',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: const []);
      await fillNewTask(tester, 'משימה שנדחתה');
      repository.failWith = DatabaseException(
        'Failed backend mutation task.insert: אין הרשאה ליצור משימות',
      );
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['insert:משימה שנדחתה']);
      expect(find.text('אין הרשאה ליצור משימות'), findsOneWidget);
      expect(find.byKey(const Key('task-form-title')), findsOneWidget);
    });

    testWidgets('a manager adds a stage on a day of the event', (tester) async {
      await pumpScreen(tester, user: admin, tasks: const []);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stage-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('stage-form-title')), 'ערב');
      await tester.tap(find.byKey(const Key('stage-form-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('21/10/2026').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-form-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['insertStage:ערב']);
      expect(find.byKey(const Key('stage-form-title')), findsNothing);
    });

    testWidgets('the new-stage button shows on כל השלבים only', (tester) async {
      await pumpScreen(tester, user: admin, tasks: const []);
      expect(find.byKey(const Key('stage-add')), findsOneWidget);

      await openTab(tester, 'המשימות שלי');
      expect(find.byKey(const Key('stage-add')), findsNothing);
    });

    testWidgets('a manager edits a stage', (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stage-edit-st1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stage-form-title')),
        'קליטה ורישום',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('stage-form-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['updateStage:st1']);
    });

    testWidgets('deleting a stage warns that its tasks go too, then sends it',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine, theirs]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stage-delete-st1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('יימחקו גם 2 המשימות שבו'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stage-delete-confirm')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['deleteStage:st1']);
      expect(find.byKey(const Key('stage-delete-confirm')), findsNothing);
    });
  });

  group('excel import', () {
    testWidgets('a manager sees import and template on an event without stages',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: const [], stages: const []);
      expect(find.byKey(const Key('tasks-import')), findsOneWidget);
      expect(find.byKey(const Key('tasks-import-template')), findsOneWidget);
    });

    testWidgets('a member gets no import buttons', (tester) async {
      await pumpScreen(tester, user: dana, tasks: const [], stages: const []);
      expect(find.text('אין עדיין שלבים לאירוע זה'), findsOneWidget);
      expect(find.byKey(const Key('tasks-import')), findsNothing);
      expect(find.byKey(const Key('tasks-import-template')), findsNothing);
    });

    testWidgets('no import once the event has a stage', (tester) async {
      await pumpScreen(tester, user: admin, tasks: const []);
      expect(find.byKey(const Key('tasks-import')), findsNothing);
    });

    testWidgets('the template downloads under its name', (tester) async {
      final files = FakeTaskImportFiles();
      await pumpScreen(
        tester,
        user: admin,
        tasks: const [],
        stages: const [],
        importFiles: files,
      );
      await tester.tap(find.byKey(const Key('tasks-import-template')));
      expect(files.saved.single.$2, 'תבנית משימות דו יומי.xlsx');
      expect(files.saved.single.$1, isNotEmpty);
    });

    testWidgets('cancelling the picker opens nothing', (tester) async {
      final files = FakeTaskImportFiles();
      await pumpScreen(
        tester,
        user: admin,
        tasks: const [],
        stages: const [],
        importFiles: files,
      );
      await tester.tap(find.byKey(const Key('tasks-import')));
      await tester.pump();
      expect(files.pickCalls, 1);
      expect(find.byKey(const Key('task-import-confirm')), findsNothing);
    });

    testWidgets('a clean file imports through the bloc and reports the counts',
        (tester) async {
      final files = FakeTaskImportFiles()
        ..picks.add(PickedImportFile(
          name: 'a.xlsx',
          bytes: Uint8List.fromList(buildImportWorkbook(
            stageRows: [
              stageRow(
                date: const DateCellValue(year: 2026, month: 10, day: 20),
              ),
            ],
            taskRows: [taskRow(assignees: 'דנה')],
          )),
        ));
      await pumpScreen(
        tester,
        user: admin,
        tasks: const [],
        stages: const [],
        importFiles: files,
      );
      await tester.tap(find.byKey(const Key('tasks-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-import-confirm')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['importStages:e1:1']);
      expect(find.text('יובאו 1 שלבים ו-1 משימות'), findsOneWidget);
    });
  });

  group('event', () {
    testWidgets(
        'an event with no stages says so, and tells a manager how to '
        'add one', (tester) async {
      await pumpScreen(tester, user: admin, tasks: const [], stages: const []);

      expect(find.text('אין עדיין שלבים לאירוע זה'), findsOneWidget);
      expect(find.text('אפשר להוסיף שלב בכפתור "שלב חדש"'), findsOneWidget);
    });

    testWidgets('an unknown event, or one that is not דו יומי, says so',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: const [], eventId: 'nope');
      expect(find.text('האירוע לא נמצא'), findsOneWidget);
      expect(find.byKey(const Key('stage-add')), findsNothing);
    });

    testWidgets('the title is the event\'s name', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('דו יומי צפון')),
        findsOneWidget,
      );
    });

    testWidgets('the back arrow returns to the event list', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await tester.tap(find.byKey(const Key('tasks-back')));
      await tester.pumpAndSettle();

      expect(find.text('רשימת האירועים'), findsOneWidget);
    });

    testWidgets('shows the test-environment banner in test mode only',
        (tester) async {
      EnvironmentService.instance.updateFromPath('/test/tasks');
      addTearDown(() => EnvironmentService.instance.updateFromPath('/tasks'));
      // Wide: the test font draws every letter as a full square, so the
      // banner's line is far longer here than in the app.
      await pumpScreen(
        tester,
        user: dana,
        tasks: [mine],
        size: const Size(900, 1800),
      );
      expect(find.textContaining('סביבת בדיקות'), findsOneWidget);

      EnvironmentService.instance.updateFromPath('/tasks');
      await tester.pump();
      expect(find.textContaining('סביבת בדיקות'), findsNothing);
    });
  });

  testWidgets('the debug preview shows a member\'s timeline, read-only',
      (tester) async {
    await pumpScreen(tester, user: admin, tasks: [mine, theirs]);
    await openTab(tester, 'המשימות שלי');
    expect(find.byKey(const Key('my-task-mine')), findsNothing);

    await tester.tap(find.byKey(const Key('view-as')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-as-m1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my-task-mine')), findsOneWidget);
    expect(find.byKey(const Key('my-task-theirs')), findsNothing);
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('my-task-tick-mine'))).onChanged,
      isNull,
    );
  });
}
