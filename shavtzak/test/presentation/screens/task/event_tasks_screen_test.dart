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
import 'package:shavtzak/core/utils/task_utils.dart' show canManageTasks;
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/task/event_tasks_screen.dart';
import 'package:shavtzak/presentation/screens/task/tasks_place.dart';
import 'package:shavtzak/presentation/screens/task/widgets/calendar_tab.dart';
import 'package:shavtzak/presentation/screens/task/widgets/day_calendar.dart';
import 'package:shavtzak/presentation/screens/task/widgets/member_timeline.dart';
import 'package:shavtzak/presentation/screens/task/widgets/stage_block.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_import_dialog.dart';

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
    TasksPlace place = TasksPlace.tab,
  }) async {
    final harness = await pumpEventTasks(
      tester,
      place: place,
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
      expect(find.byType(DayCalendar), findsNothing);
    });

    testWidgets(
        'an admin, and a member allowed to manage tasks, land on כל השלבים',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      expect(find.byType(DayCalendar), findsWidgets);

      await pumpScreen(
        tester,
        user: buildMember(id: 'lead', name: 'אורי', canManageTasks: true),
        tasks: [mine],
      );
      expect(find.byType(DayCalendar), findsWidgets);
    });

    testWidgets('every member can open both tabs', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await openTab(tester, 'כל השלבים');
      expect(find.byType(DayCalendar), findsWidgets);

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

    testWidgets('coming back to the page reopens my timeline at the time of now',
        (tester) async {
      var clockNow = sampleNow;
      await pumpEventTasks(
        tester,
        user: sDana,
        clock: () => clockNow,
        board: sampleTaskBoard(),
      );
      expect(find.textContaining('2 שלבים קודמים'), findsOneWidget);

      // Hours later the phone brings the tab back to the front.
      clockNow = DateTime(2026, 10, 20, 20);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();

      expect(find.textContaining('3 שלבים קודמים'), findsOneWidget);
    });

    testWidgets('the clock moves on the minute, not a minute after opening',
        (tester) async {
      // Opened 45 seconds into 14:40.
      var clockNow = sampleNow.add(const Duration(seconds: 45));
      await pumpEventTasks(
        tester,
        user: buildMember(id: 'm1', name: 'דנה', isAdmin: true),
        clock: () => clockNow,
        board: sampleTaskBoard(),
      );
      await tester.tap(find.text('כל השלבים'));
      await tester.pumpAndSettle();
      expect(find.textContaining('14:40'), findsOneWidget);

      clockNow = sampleNow.add(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 15));
      expect(find.textContaining('14:41'), findsOneWidget);

      clockNow = sampleNow.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 1));
      expect(find.textContaining('14:42'), findsOneWidget);
    });

    testWidgets('crossing the wide breakpoint with a sheet open keeps it working',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine], size: phoneSize);
      await openMyTask(tester, 'mine', 'להזמין אוטובוס');

      tester.view.physicalSize = wideSize;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(inSheet(find.byKey(const Key('task-detail-mine'))), findsOneWidget);

      tester.view.physicalSize = phoneSize;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(inSheet(find.byKey(const Key('task-detail-mine'))), findsOneWidget);
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

    testWidgets(
        'in my late list a task with subtasks opens them in place first, '
        'and stays open after the task and back', (tester) async {
      final setupSteps = buildTask(
        id: 'setup-steps',
        title: 'תליית שלטים',
        stage: stSetup,
        assemblyTime: '08:30',
        event: sampleEvent,
        assigneeIds: const ['m1'],
        assignees: [sDana],
        subtasks: const [
          Subtask(id: 'a', title: 'שלט כניסה'),
          Subtask(id: 'b', title: 'שלט לובי'),
        ],
      );
      final harness = await pumpEventTasks(
        tester,
        user: sDana,
        size: tallPhoneSize,
        clock: () => sampleNow,
        board: sampleTaskBoard(tasks: [...sampleTasks, setupSteps]),
      );
      await tester.tap(find.byKey(const Key('my-late-banner')));
      await tester.pumpAndSettle();

      final row = inSheet(find.byKey(const Key('task-row-setup-steps')));
      final subtasks =
          inSheet(find.byKey(const Key('task-row-subtasks-setup-steps')));
      await tester.tap(
          inSheet(find.byKey(const Key('task-row-fold-setup-steps'))));
      await tester.pumpAndSettle();
      expect(subtasks, findsOneWidget);
      expect(inSheet(find.byKey(const Key('task-detail-setup-steps'))),
          findsNothing);

      final tick = find.byKey(const Key('task-row-subtask-setup-steps-b'));
      await tester.tap(tick);
      await tester.pump();
      expect(harness.repository.calls, ['subtask:setup-steps:b:true']);
      expect(tester.widget<Checkbox>(tick).value, isTrue);
      expect(subtasks, findsOneWidget);

      await tester.tap(
          find.descendant(of: row, matching: find.text('תליית שלטים')));
      await tester.pumpAndSettle();
      expect(inSheet(find.byKey(const Key('task-detail-setup-steps'))),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('task-sheet-back')));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('2 משימות שלך באיחור')), findsOneWidget);
      expect(subtasks, findsOneWidget);
    });
  });

  group('stage sheet', () {
    Future<EventTasksHarness> pumpSample(
      WidgetTester tester, {
      required TeamMember user,
    }) async {
      final harness = await pumpEventTasks(
        tester,
        user: user,
        size: tallPhoneSize,
        clock: () => sampleNow,
        board: sampleTaskBoard(),
      );
      repository = harness.repository;
      if (canManageTasks(user)) await openTab(tester, 'המשימות שלי');
      return harness;
    }

    Future<void> openWorkshops(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('my-stage-ws')));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a stage in my timeline opens it in the sheet',
        (tester) async {
      await pumpSample(tester, user: sDana);
      await openWorkshops(tester);

      expect(inSheet(find.byKey(const Key('stage-sheet-ws'))), findsOneWidget);
      expect(inSheet(find.text('הכל (5)')), findsOneWidget);
    });

    testWidgets('a row ticked in חסרות stays, struck through, until the view changes',
        (tester) async {
      await pumpSample(tester, user: sDana);
      await openWorkshops(tester);
      await tester.tap(inSheet(find.text('חסרות (4)')));
      await tester.pumpAndSettle();

      await tester.tap(inSheet(find.byKey(const Key('task-row-tick-ws-later'))));
      await tester.pump();

      expect(repository.calls, ['complete:ws-later:true']);
      final row = inSheet(find.byKey(const Key('task-row-ws-later')));
      expect(row, findsOneWidget);
      expect(
        tester
            .widget<Text>(find.descendant(
              of: row,
              matching: find.text('חלוקת ערכות למשתתפים'),
            ))
            .style
            ?.decoration,
        TextDecoration.lineThrough,
      );
      expect(inSheet(find.text('חסרות (3)')), findsOneWidget);

      await tester.tap(inSheet(find.text('הכל (5)')));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('חסרות (3)')));
      await tester.pumpAndSettle();
      expect(inSheet(find.byKey(const Key('task-row-ws-later'))), findsNothing);
    });

    testWidgets('a manager edits and deletes the stage from the sheet',
        (tester) async {
      await pumpSample(tester, user: admin);
      await openWorkshops(tester);

      await tester.tap(find.byKey(const Key('stage-edit-ws')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stage-form-title')),
        'סדנאות בוקר',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('stage-form-save')));
      await tester.pumpAndSettle();
      expect(repository.calls, ['updateStage:ws']);

      await tester.tap(find.byKey(const Key('stage-delete-ws')));
      await tester.pumpAndSettle();
      expect(find.textContaining('יימחקו גם 5 המשימות שבו'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stage-delete-confirm')));
      await tester.pumpAndSettle();
      expect(repository.calls, ['updateStage:ws', 'deleteStage:ws']);
    });

    testWidgets('a member gets no stage editing in the sheet', (tester) async {
      await pumpSample(tester, user: sDana);
      await openWorkshops(tester);

      expect(find.byKey(const Key('stage-edit-ws')), findsNothing);
      expect(find.byKey(const Key('stage-delete-ws')), findsNothing);
      expect(find.byKey(const Key('stage-add-task-ws')), findsNothing);
    });

    testWidgets('a manager adds a task from the stage', (tester) async {
      await pumpSample(tester, user: admin);
      await openWorkshops(tester);

      await tester.tap(find.byKey(const Key('stage-add-task-ws')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('task-form-title')),
        'הכנת שלטי כיוון',
      );
      await tester.tap(find.byKey(const Key('task-form-assignees')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-assignee-m2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['insert:הכנת שלטי כיוון']);
    });

    testWidgets('the sheet closes when its stage is deleted', (tester) async {
      final harness = await pumpSample(tester, user: sDana);
      await openWorkshops(tester);

      await harness.deliver(
        tester,
        TaskBoard(
          tasks: [
            for (final task in sampleTasks)
              if (task.stageId != 'ws') task,
          ],
          events: [sampleEvent],
          stages: [
            for (final stage in sampleStages)
              if (stage.id != 'ws') stage,
          ],
          members: [sDana, sYoav],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('task-sheet')), findsNothing);
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

  group('stages on the calendar', () {
    /// Opens the arrival stage from its block on the calendar.
    Future<void> openArrival(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-block-st1')));
      await tester.pumpAndSettle();
    }

    Future<void> fillNewTask(WidgetTester tester, String title) async {
      await openArrival(tester);
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
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stage-add')), findsOneWidget);
      await openArrival(tester);
      expect(find.byKey(const Key('stage-add-task-st1')), findsOneWidget);

      await pumpScreen(tester, user: dana, tasks: [mine]);
      await openTab(tester, 'כל השלבים');
      expect(find.byKey(const Key('stage-add')), findsNothing);
      await openArrival(tester);
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

    testWidgets('the new-stage button shows on כל השלבים only, and steps aside for the sheet',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: const []);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stage-add')), findsOneWidget);

      await openArrival(tester);
      expect(find.byKey(const Key('stage-add')), findsNothing);

      await tester.tap(find.byKey(const Key('task-sheet-close')));
      await tester.pumpAndSettle();
      await openTab(tester, 'המשימות שלי');
      // Let the button's exit animation finish.
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stage-add')), findsNothing);
    });

    testWidgets('a manager edits a stage', (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      await openArrival(tester);

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
      await openArrival(tester);

      await tester.tap(find.byKey(const Key('stage-delete-st1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('יימחקו גם 2 המשימות שבו'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stage-delete-confirm')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['deleteStage:st1']);
      expect(find.byKey(const Key('stage-delete-confirm')), findsNothing);
    });
  });

  group('calendar', () {
    Future<EventTasksHarness> pumpCalendar(
      WidgetTester tester, {
      TeamMember? user,
      DateTime? now,
      TaskBoard? board,
      Map<String, List<TeamMember>>? assignees,
      FakeTaskRepository? repo,
      Size size = phoneSize,
    }) async {
      final harness = await pumpEventTasks(
        tester,
        user: user ?? admin,
        size: size,
        clock: () => now ?? sampleNow,
        board: board ?? sampleTaskBoard(),
        assignees: assignees,
        repository: repo,
      );
      repository = harness.repository;
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('a manager lands on the calendar with the summary',
        (tester) async {
      await pumpCalendar(tester);
      // It opens on the stage of now; the summary is at the top.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 5000));
      await tester.pumpAndSettle();

      expect(find.byType(DayCalendar), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const Key('event-summary')),
          matching: find.text('${eventDaysLabel(sampleEvent)} · מלון רויאל'),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('event-done-count'))).data,
        '${ltr('2/8')} הושלמו',
      );
    });

    testWidgets('every day is in one scroll, a divider above each',
        (tester) async {
      await pumpCalendar(tester);
      expect(find.byKey(const Key('calendar-day-divider-2026-10-20')),
          findsOneWidget);
      expect(find.byKey(const Key('calendar-day-divider-2026-10-21')),
          findsOneWidget);
      expect(find.byKey(const Key('stage-block-ws')), findsOneWidget);
      expect(find.byKey(const Key('stage-block-bf')), findsOneWidget);
      // Tuesday above Wednesday.
      expect(
        tester.getTopLeft(find.byKey(const Key('stage-block-ws'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('stage-block-bf'))).dy),
      );
    });

    testWidgets('it opens scrolled to the stage of now', (tester) async {
      await pumpCalendar(tester, now: DateTime(2026, 10, 21, 7, 45));
      final block = tester.getRect(find.byKey(const Key('stage-block-bf')));
      final pinnedBottom =
          tester.getBottomLeft(find.byKey(const Key('calendar-pinned'))).dy;
      expect(block.top, greaterThanOrEqualTo(pinnedBottom - 0.5));
      expect(block.top, lessThan(tester.view.physicalSize.height));
    });

    testWidgets('a stage dated outside the event still gets its day',
        (tester) async {
      final stray = buildStage(id: 'stray', title: 'פירוק', date: DateTime(2026, 10, 23));
      await pumpCalendar(
        tester,
        board: TaskBoard(
          tasks: sampleTasks,
          events: [sampleEvent],
          stages: [...sampleStages, stray],
          members: [sDana, sYoav],
        ),
      );

      expect(find.byKey(const Key('calendar-day-divider-2026-10-23')),
          findsOneWidget);
      expect(find.byKey(const Key('stage-block-stray')), findsOneWidget);
    });

    testWidgets('tapping a block opens the stage all the way up; closing returns to the calendar',
        (tester) async {
      await pumpCalendar(tester);

      await tester.tap(find.byKey(const Key('stage-block-ws')));
      await tester.pumpAndSettle();
      expect(inSheet(find.byKey(const Key('stage-sheet-ws'))), findsOneWidget);
      final sheetTop = tester.getTopLeft(find.byKey(const Key('task-sheet'))).dy;
      expect(sheetTop, lessThan(tester.view.physicalSize.height * 0.2));

      await tester.tap(find.byKey(const Key('task-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-sheet')), findsNothing);
      await tester.tap(find.byKey(const Key('stage-block-dinner')));
      await tester.pumpAndSettle();
      expect(inSheet(find.byKey(const Key('stage-sheet-dinner'))), findsOneWidget);
    });

    testWidgets('the count opens חסרות, the block הכל', (tester) async {
      await pumpCalendar(tester);

      await tester.tap(find.byKey(const Key('stage-count-ws')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byKey(const Key('stage-switch')))
            .selected,
        {true},
      );

      await tester.tap(find.byKey(const Key('task-sheet-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-block-ws')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byKey(const Key('stage-switch')))
            .selected,
        {false},
      );
    });

    testWidgets('the X closes the sheet, the outline and the fade',
        (tester) async {
      await pumpCalendar(tester);
      await tester.tap(find.byKey(const Key('stage-block-ws')));
      await tester.pumpAndSettle();
      bool faded(String id) => tester
          .widget<StageBlock>(find.byKey(Key('stage-block-$id')))
          .isFaded;
      expect(faded('lunch'), isTrue);

      await tester.tap(find.byKey(const Key('task-sheet-close')));
      await tester.pumpAndSettle();

      expect(faded('lunch'), isFalse);
      expect(
        tester.widget<StageBlock>(find.byKey(const Key('stage-block-ws'))).isOutlined,
        isFalse,
      );
    });

    testWidgets('a task opened from search shows its stage outlined, on its day',
        (tester) async {
      await pumpCalendar(tester);
      await search(tester, 'אורחים');
      await tester.tap(find.byKey(const Key('task-row-dinner-guests')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<StageBlock>(find.byKey(const Key('stage-block-dinner'))).isOutlined,
        isTrue,
      );
    });

    testWidgets('an event without stages keeps the import empty state for managers',
        (tester) async {
      await pumpCalendar(
        tester,
        board: TaskBoard(
          tasks: const [],
          events: [sampleEvent],
          members: [sDana],
        ),
      );

      expect(find.byKey(const Key('tasks-import')), findsOneWidget);
      expect(find.byType(DayCalendar), findsNothing);
    });
  });

  group('filters', () {
    Future<void> pumpFilters(WidgetTester tester, {TeamMember? user}) async {
      final harness = await pumpEventTasks(
        tester,
        user: user ?? admin,
        clock: () => sampleNow,
        board: sampleTaskBoard(),
      );
      repository = harness.repository;
      await tester.pumpAndSettle();
    }

    FilterChip chip(WidgetTester tester, String key) =>
        tester.widget<FilterChip>(find.byKey(Key(key)));

    testWidgets('each toggle counts its tasks', (tester) async {
      await pumpFilters(tester);

      expect(find.text('באיחור (2)'), findsOneWidget);
      expect(find.text('התייצבות בחצי שעה הקרובה (1)'), findsOneWidget);
    });

    testWidgets('switching one on lists its tasks from every stage, longest overdue first',
        (tester) async {
      await pumpFilters(tester);

      await tester.tap(find.byKey(const Key('filter-late')));
      await tester.pumpAndSettle();

      expect(inSheet(find.text('באיחור · 2 משימות')), findsOneWidget);
      expect(inSheet(find.text('מכל השלבים, הוותיקה ראשונה')), findsOneWidget);
      expect(
        tester.getTopLeft(inSheet(find.byKey(const Key('results-stage-lunch')))).dy,
        lessThan(
          tester.getTopLeft(inSheet(find.byKey(const Key('results-stage-ws')))).dy,
        ),
      );
      expect(chip(tester, 'filter-late').selected, isTrue);
    });

    testWidgets('the stages in the results are outlined, the rest faded',
        (tester) async {
      await pumpFilters(tester);
      await tester.tap(find.byKey(const Key('filter-late')));
      await tester.pumpAndSettle();

      StageBlock block(String id) =>
          tester.widget<StageBlock>(find.byKey(Key('stage-block-$id')));
      expect(block('lunch').isOutlined, isTrue);
      expect(block('ws').isOutlined, isTrue);
      expect(block('setup').isFaded, isTrue);
    });

    testWidgets('one filter at a time', (tester) async {
      await pumpFilters(tester);
      await tester.tap(find.byKey(const Key('filter-late')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter-soon')));
      await tester.pumpAndSettle();

      expect(chip(tester, 'filter-late').selected, isFalse);
      expect(chip(tester, 'filter-soon').selected, isTrue);
      expect(inSheet(find.text('התייצבות בחצי שעה הקרובה · 1')), findsOneWidget);
    });

    testWidgets('tapping the active one, or closing the sheet, switches it off',
        (tester) async {
      await pumpFilters(tester);
      await tester.tap(find.byKey(const Key('filter-late')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-late')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-sheet')), findsNothing);

      await tester.tap(find.byKey(const Key('filter-late')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-sheet-close')));
      await tester.pumpAndSettle();
      expect(chip(tester, 'filter-late').selected, isFalse);
    });

    testWidgets('ticking a late task keeps its row while the count moves',
        (tester) async {
      await pumpFilters(tester);
      await tester.tap(find.byKey(const Key('filter-late')));
      await tester.pumpAndSettle();

      await tester.tap(inSheet(find.byKey(const Key('task-row-tick-lunch-late'))));
      await tester.pump();

      expect(repository.calls, ['complete:lunch-late:true']);
      expect(inSheet(find.byKey(const Key('task-row-lunch-late'))), findsOneWidget);
      expect(find.text('באיחור (1)'), findsOneWidget);
      expect(inSheet(find.text('באיחור · משימה אחת')), findsOneWidget);
    });
  });

  group('assignee check', () {
    Future<void> pumpCheck(
      WidgetTester tester, {
      TeamMember? user,
      Map<String, List<TeamMember>>? assignees,
      FakeTaskRepository? repo,
    }) async {
      final harness = await pumpEventTasks(
        tester,
        user: user ?? admin,
        size: tallPhoneSize,
        clock: () => sampleNow,
        board: sampleTaskBoard(),
        assignees: assignees,
        repository: repo,
      );
      repository = harness.repository;
      await tester.pumpAndSettle();
    }

    testWidgets('managers see one red line when an assignee was taken off the event',
        (tester) async {
      await pumpCheck(tester, assignees: {
        'e1': [sDana],
      });

      expect(
        find.descendant(
          of: find.byKey(const Key('assignee-check')),
          matching: find.text('3 משימות של מי שכבר לא משובץ לאירוע'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('nothing shows before the event\'s assignees have loaded',
        (tester) async {
      await pumpCheck(tester, repo: _SilentAssigneesRepository());

      expect(find.byKey(const Key('assignee-check')), findsNothing);
    });

    testWidgets('members never see it', (tester) async {
      await pumpCheck(tester, user: sDana, assignees: {
        'e1': [sDana],
      });
      await openTab(tester, 'כל השלבים');

      expect(find.byKey(const Key('assignee-check')), findsNothing);
    });

    testWidgets('nothing to fix, no line', (tester) async {
      await pumpCheck(tester);

      expect(find.byKey(const Key('assignee-check')), findsNothing);
    });

    testWidgets('tapping it lists those tasks, the removed assignee struck through',
        (tester) async {
      await pumpCheck(tester, assignees: {
        'e1': [sDana],
      });

      await tester.tap(find.byKey(const Key('assignee-check')));
      await tester.pumpAndSettle();

      expect(
        inSheet(find.text('3 משימות של מי שכבר לא משובץ לאירוע')),
        findsOneWidget,
      );
      expect(inSheet(find.text('כבר לא משובץ לאירוע')), findsNWidgets(3));
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

    testWidgets('a file the browser cannot read is reported, not ignored',
        (tester) async {
      final files = FakeTaskImportFiles()
        ..failNextPick = StateError('NotReadableError');
      await pumpScreen(
        tester,
        user: admin,
        tasks: const [],
        stages: const [],
        importFiles: files,
      );
      await tester.tap(find.byKey(const Key('tasks-import')));
      await tester.pump();
      await tester.pump();
      expect(find.text(importFileReadError), findsOneWidget);
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

    testWidgets('a long event name shrinks to one line instead of "…"',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      final name = find.descendant(
        of: find.byKey(const Key('tasks-title')),
        matching: find.text('דו יומי צפון'),
      );
      final text = tester.widget<Text>(name);
      expect(text.maxLines, 1);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(
        find.ancestor(of: name, matching: find.byType(FittedBox)),
        findsOneWidget,
      );
    });

    testWidgets('the title is the event\'s name and days', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      final title = find.byKey(const Key('tasks-title'));
      expect(
        find.descendant(of: title, matching: find.text('דו יומי צפון')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: title,
          matching: find.text(eventDaysLabel(event)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('opening an event remembers it for its place',
        (tester) async {
      TasksResume.debugReset();
      addTearDown(TasksResume.debugReset);
      await pumpScreen(tester, user: dana, tasks: [mine]);

      expect(TasksResume.lastEvent(TasksPlace.tab), event.id);
    });

    testWidgets('the title opens the event list, and the list stays chosen',
        (tester) async {
      TasksResume.debugReset();
      addTearDown(TasksResume.debugReset);
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await tester.tap(find.byKey(const Key('tasks-title')));
      await tester.pumpAndSettle();

      expect(find.text('רשימת האירועים'), findsOneWidget);
      expect(TasksResume.isListChosen(TasksPlace.tab), isTrue);
    });

    testWidgets('in the tab, leaves the test-environment banner to the shell',
        (tester) async {
      EnvironmentService.instance.updateFromPath('/test/tasks');
      addTearDown(() => EnvironmentService.instance.updateFromPath('/tasks'));
      await pumpScreen(
        tester,
        user: dana,
        tasks: [mine],
        size: const Size(900, 1800),
      );
      expect(find.textContaining('סביבת בדיקות'), findsNothing);
    });

    testWidgets('on its own screen, shows the test-environment banner in '
        'test mode only', (tester) async {
      EnvironmentService.instance.updateFromPath('/test/tasks');
      addTearDown(() => EnvironmentService.instance.updateFromPath('/tasks'));
      // Wide: the test font draws every letter as a full square, so the
      // banner's line is far longer here than in the app.
      await pumpScreen(
        tester,
        user: dana,
        tasks: [mine],
        size: const Size(900, 1800),
        place: TasksPlace.standalone,
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

/// Its event assignees never arrive, like a listener still warming up.
class _SilentAssigneesRepository extends FakeTaskRepository {
  final StreamController<List<TeamMember>> _assignees =
      StreamController<List<TeamMember>>();

  @override
  Stream<List<TeamMember>> watchEventAssignees(String eventId) =>
      _assignees.stream;
}
