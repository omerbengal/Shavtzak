import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:excel/excel.dart' show DateCellValue;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shavtzak/core/services/environment_service.dart';
import 'package:shavtzak/core/services/task_import_files.dart';
import 'package:shavtzak/core/theme/app_theme.dart';
import 'package:shavtzak/core/utils/rtl_text_field_utils.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/task/task_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/task/event_tasks_screen.dart';

import '../../../support/fake_task_import_files.dart';
import '../../../support/fake_task_repository.dart';
import '../../../support/import_workbook.dart';
import '../../../support/task_fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 11, 14, 0);

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

  final mine = buildTask(
    id: 'mine',
    title: 'להזמין אוטובוס',
    event: event,
    assigneeIds: const ['m1'],
    assignees: [dana],
  );
  final theirs = buildTask(
    id: 'theirs',
    title: 'הזמנת קייטרינג',
    event: event,
    assigneeIds: const ['m2'],
    assignees: [yoav],
  );
  final withSubtasks = buildTask(
    id: 'steps',
    title: 'אישור ביטחוני',
    event: event,
    assigneeIds: const ['m1'],
    assignees: [dana],
    subtasks: const [
      Subtask(id: 'a', title: 'טופס'),
      Subtask(id: 'b', title: 'חתימה'),
    ],
  );

  late FakeTaskRepository repository;
  late TaskBloc taskBloc;
  late MockUserSelectionBloc userBloc;

  /// Stages start folded; open every one on screen that is still closed.
  Future<void> openAllStages(WidgetTester tester) async {
    final toggles = find.byWidgetPredicate((widget) =>
        widget is InkWell &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('stage-toggle-'));
    for (final element in toggles.evaluate().toList()) {
      final id = ((element.widget.key! as ValueKey<String>).value)
          .substring('stage-toggle-'.length);
      if (find.byKey(Key('stage-body-$id')).evaluate().isNotEmpty) continue;
      await tester.tap(find.byKey(Key('stage-toggle-$id')));
      await tester.pump();
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required TeamMember user,
    List<TaskItem>? tasks,
    List<Stage>? stages,
    ThemeData? theme,
    String eventId = 'e1',
    bool openStages = true,
    FakeTaskImportFiles? importFiles,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Built here, inside the test's fake-async zone. A bloc created in setUp
    // would run its stream callbacks in the real zone, where `pump` never
    // reaches them.
    repository = FakeTaskRepository()
      ..assigneesByEvent = {
        'e1': [dana, yoav],
      };
    taskBloc = TaskBloc(repository: repository);
    userBloc = MockUserSelectionBloc();
    addTearDown(() {
      unawaited(taskBloc.close());
      if (!repository.controller.isClosed) {
        unawaited(repository.controller.close());
      }
    });

    whenListen(
      userBloc,
      const Stream<UserSelectionState>.empty(),
      initialState: UserAuthenticated(user),
    );

    await tester.pumpWidget(RepositoryProvider<TaskRepository>.value(
      value: repository,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TaskBloc>.value(value: taskBloc),
          BlocProvider<UserSelectionBloc>.value(value: userBloc),
        ],
        child: MaterialApp.router(
          theme: theme,
          routerConfig: GoRouter(
            initialLocation: '/tasks/$eventId',
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (context, state) =>
                    const Scaffold(body: Text('רשימת האירועים')),
              ),
              GoRoute(
                path: '/tasks/:eventId',
                builder: (context, state) => EventTasksScreen(
                  eventId: state.pathParameters['eventId']!,
                  clock: () => now,
                  importFiles: importFiles ?? FakeTaskImportFiles(),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    if (tasks != null) {
      repository.controller.add(TaskBoard(
        tasks: tasks,
        events: [event],
        stages: stages ?? [arrival],
        members: [dana, yoav],
      ));
      await tester.pump();
      await tester.pump();
      if (openStages) await openAllStages(tester);
    }
  }

  group('loading', () {
    testWidgets('shows a spinner until the first tasks arrive', (tester) async {
      await pumpScreen(tester, user: dana);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.controller.add(const TaskBoard(tasks: []));
      await tester.pump();
      await tester.pump();
      await openAllStages(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a load failure offers a retry that subscribes again',
        (tester) async {
      await pumpScreen(tester, user: dana);
      // Errors and stays open, like a Firestore listener killed by sign-out.
      repository.controller.addError(Exception('permission-denied'));
      await tester.pump();
      await tester.pump();

      expect(find.text('טעינת המשימות נכשלה'), findsOneWidget);

      repository.controller = StreamController<TaskBoard>();
      await tester.tap(find.byKey(const Key('tasks-retry')));
      await tester.pump();
      repository.controller.add(TaskBoard(
        tasks: [mine],
        events: [event],
        stages: [arrival],
      ));
      await tester.pump();
      await tester.pump();
      await openAllStages(tester);

      expect(repository.watchCalls, 2);
      expect(find.text('להזמין אוטובוס'), findsOneWidget);
    });
  });

  group('mine / all', () {
    testWidgets('shows only the signed-in member\'s tasks by default',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine, theirs]);

      expect(find.text('להזמין אוטובוס'), findsOneWidget);
      expect(find.text('הזמנת קייטרינג'), findsNothing);
    });

    testWidgets('switching to all tasks shows everyone\'s', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine, theirs]);

      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);

      expect(find.text('להזמין אוטובוס'), findsOneWidget);
      expect(find.text('הזמנת קייטרינג'), findsOneWidget);

      await tester.tap(find.text('המשימות שלי'));
      await tester.pump();
      expect(find.text('הזמנת קייטרינג'), findsNothing);
    });

    testWidgets('a member with no tasks sees a prompt, not a blank screen',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [theirs]);
      expect(find.text('אין לך משימות באירוע זה'), findsOneWidget);
    });

    testWidgets('all tasks with no tasks still shows every stage, empty',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: const []);
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);
      expect(find.byKey(const Key('stage-card-st1')), findsOneWidget);
      expect(find.text('אין עדיין משימות בשלב זה'), findsOneWidget);
    });
  });

  group('search and filter', () {
    testWidgets('typing narrows the list by title', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine, withSubtasks]);
      expect(find.text('אישור ביטחוני'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('tasks-search')), 'אוטובוס');
      await tester.pump();

      expect(find.text('להזמין אוטובוס'), findsWidgets);
      expect(find.text('אישור ביטחוני'), findsNothing);
      // Let the debounced search logger fire before the test ends.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a search with no match says nothing matched', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await tester.enterText(find.byKey(const Key('tasks-search')), 'קקטוס');
      await tester.pump();

      expect(find.text('לא נמצאו משימות תואמות'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a status filter narrows the list and shows on the badge',
        (tester) async {
      final overdue = buildTask(
        id: 'late',
        title: 'משימה באיחור',
        event: event,
        assigneeIds: const ['m1'],
        assignees: [dana],
        dueAt: DateTime(2026, 10, 9, 9),
      );
      await pumpScreen(tester, user: dana, tasks: [mine, overdue]);

      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-status-overdue')));
      await tester.pump();

      // Already narrowed, with the filter still open.
      expect(find.byKey(const Key('filter-close')), findsOneWidget);
      expect(find.text('משימה באיחור'), findsOneWidget);
      expect(find.text('להזמין אוטובוס'), findsNothing);

      await tester.tap(find.byKey(const Key('filter-close')));
      await tester.pumpAndSettle();

      expect(find.text('משימה באיחור'), findsOneWidget);
      expect(find.text('להזמין אוטובוס'), findsNothing);
      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isTrue);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets(
        'the filter offers assignees under all tasks but not under my '
        'tasks', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine, theirs]);

      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      expect(find.text('אחראי'), findsNothing);
      expect(find.byKey(const Key('filter-assignee-m1')), findsNothing);
      await tester.tap(find.byKey(const Key('filter-close')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);
      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      expect(find.text('אחראי'), findsOneWidget);
      expect(find.byKey(const Key('filter-assignee-m1')), findsOneWidget);
      expect(find.byKey(const Key('filter-assignee-m2')), findsOneWidget);
    });

    testWidgets('my tasks and all tasks each keep a filter of their own',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine, theirs]);

      Future<void> tickInFilter(String key) async {
        await tester.tap(find.byKey(const Key('tasks-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(key)));
        await tester.pump();
        await tester.tap(find.byKey(const Key('filter-close')));
        await tester.pumpAndSettle();
      }

      bool badgeShown() =>
          tester.widget<Badge>(find.byType(Badge)).isLabelVisible;

      // All tasks: only Yoav's.
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);
      await tickInFilter('filter-assignee-m2');
      expect(find.text('הזמנת קייטרינג'), findsOneWidget);
      expect(find.text('להזמין אוטובוס'), findsNothing);
      expect(badgeShown(), isTrue);

      // My tasks is untouched by that.
      await tester.tap(find.text('המשימות שלי'));
      await tester.pump();
      expect(find.text('להזמין אוטובוס'), findsOneWidget);
      expect(badgeShown(), isFalse);

      // My tasks: only completed ones, of which there are none.
      await tickInFilter('filter-status-completed');
      expect(find.text('להזמין אוטובוס'), findsNothing);
      expect(find.text('לא נמצאו משימות תואמות'), findsOneWidget);
      expect(badgeShown(), isTrue);

      // All tasks still has its own filter, and not the completed one.
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);
      expect(find.text('הזמנת קייטרינג'), findsOneWidget);
      expect(find.text('להזמין אוטובוס'), findsNothing);

      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      bool ticked(String key) =>
          tester.widget<CheckboxListTile>(find.byKey(Key(key))).value ?? false;
      expect(ticked('filter-assignee-m2'), isTrue);
      expect(ticked('filter-status-completed'), isFalse);
    });

    testWidgets('clearing the filter brings every task back while it is open',
        (tester) async {
      final overdue = buildTask(
        id: 'late',
        title: 'משימה באיחור',
        event: event,
        assigneeIds: const ['m1'],
        assignees: [dana],
        dueAt: DateTime(2026, 10, 9, 9),
      );
      await pumpScreen(tester, user: dana, tasks: [mine, overdue]);

      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-status-overdue')));
      await tester.pump();
      expect(find.text('להזמין אוטובוס'), findsNothing);

      await tester.tap(find.byKey(const Key('filter-clear')));
      await tester.pump();

      expect(find.text('להזמין אוטובוס'), findsOneWidget);
      expect(find.text('משימה באיחור'), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    });

    testWidgets(
        'the half-hour filter keeps only unfinished tasks due in the '
        'next 30 minutes', (tester) async {
      TaskItem due(String id, String title, DateTime dueAt) => buildTask(
            id: id,
            title: title,
            event: event,
            assigneeIds: const ['m1'],
            assignees: [dana],
            dueAt: dueAt,
          );
      // The screen's clock reads 14:00.
      await pumpScreen(tester, user: dana, tasks: [
        due('soon', 'בעוד עשרים דקות', DateTime(2026, 10, 11, 14, 20)),
        due('edge', 'בעוד חצי שעה בדיוק', DateTime(2026, 10, 11, 14, 30)),
        due('later', 'בעוד שעה', DateTime(2026, 10, 11, 15, 0)),
        due('late', 'כבר באיחור', DateTime(2026, 10, 11, 13, 0)),
        mine,
      ]);

      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-due-soon')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-close')));
      await tester.pumpAndSettle();

      expect(find.text('בעוד עשרים דקות'), findsOneWidget);
      expect(find.text('בעוד חצי שעה בדיוק'), findsOneWidget);
      expect(find.text('בעוד שעה'), findsNothing);
      expect(find.text('כבר באיחור'), findsNothing);
      expect(find.text('להזמין אוטובוס'), findsNothing);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    });
  });

  group('who can do what', () {
    testWidgets('an admin gets the new-stage and new-task buttons',
        (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: [mine],
      );
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);
      expect(find.byKey(const Key('stage-add')), findsOneWidget);
      expect(find.byKey(const Key('stage-add-task-st1')), findsOneWidget);
    });

    testWidgets('a flagged non-admin gets the new-stage and new-task buttons',
        (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'lead', canManageTasks: true),
        tasks: [mine],
      );
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);
      expect(find.byKey(const Key('stage-add')), findsOneWidget);
      expect(find.byKey(const Key('stage-add-task-st1')), findsOneWidget);
    });

    testWidgets('a plain member gets no stage or task management buttons',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      expect(find.byKey(const Key('stage-add')), findsNothing);
      expect(find.byKey(const Key('stage-add-task-st1')), findsNothing);
      expect(find.byKey(const Key('stage-edit-st1')), findsNothing);
      expect(find.byKey(const Key('task-edit-mine')), findsNothing);
      expect(find.byKey(const Key('task-delete-mine')), findsNothing);
    });

    testWidgets('a member cannot tick someone else\'s task', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [theirs]);
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);

      final checkbox = tester.widget<Checkbox>(
        find.byKey(const Key('task-complete-theirs')),
      );
      expect(checkbox.onChanged, isNull);
    });
  });

  group('actions', () {
    testWidgets('ticking a subtask is sent with that task and subtask',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [withSubtasks]);
      await tester.tap(find.text('אישור ביטחוני'));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.byKey(const Key('subtask-b')),
        matching: find.byType(Checkbox),
      ));
      await tester.pump();

      expect(repository.calls, ['subtask:steps:b:true']);
    });

    testWidgets('completing a task without subtasks is sent', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await tester.tap(find.byKey(const Key('task-complete-mine')));
      await tester.pump();

      expect(repository.calls, ['complete:mine:true']);
    });

    testWidgets('a ticked task is shown done before the backend answers',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      repository.gate = Completer<void>();

      await tester.tap(find.byKey(const Key('task-complete-mine')));
      await tester.pump();

      expect(repository.calls, ['complete:mine:true']);
      expect(
        tester
            .widget<Checkbox>(find.byKey(const Key('task-complete-mine')))
            .value,
        isTrue,
      );
      expect(find.text('הושלמה'), findsOneWidget);

      repository.gate!.complete();
      await tester.pump();
    });

    testWidgets('a ticked subtask is shown done before the backend answers',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [withSubtasks]);
      await tester.tap(find.text('אישור ביטחוני'));
      await tester.pumpAndSettle();
      repository.gate = Completer<void>();

      final checkbox = find.descendant(
        of: find.byKey(const Key('subtask-a')),
        matching: find.byType(Checkbox),
      );
      await tester.tap(checkbox);
      await tester.pump();

      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(find.text('1/2'), findsOneWidget);

      repository.gate!.complete();
      await tester.pump();
    });

    testWidgets('a tick the backend refuses is taken back and explained',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);
      repository.gate = Completer<void>();
      repository.failWith = DatabaseException(
        'Failed backend mutation task.setComplete: אין הרשאה לעדכן את המשימה',
      );

      await tester.tap(find.byKey(const Key('task-complete-mine')));
      await tester.pump();
      expect(
        tester
            .widget<Checkbox>(find.byKey(const Key('task-complete-mine')))
            .value,
        isTrue,
      );

      repository.gate!.complete();
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<Checkbox>(find.byKey(const Key('task-complete-mine')))
            .value,
        isFalse,
      );
      expect(find.text('אין הרשאה לעדכן את המשימה'), findsOneWidget);
    });

    testWidgets('saving an update sends the typed text', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

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
      await tester.tap(find.text('אישור ביטחוני'));
      await tester.pumpAndSettle();

      repository.failWith = DatabaseException(
        'Failed backend mutation task.setSubtaskDone: תת-המשימה לא נמצאה',
      );
      await tester.tap(find.descendant(
        of: find.byKey(const Key('subtask-a')),
        matching: find.byType(Checkbox),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('תת-המשימה לא נמצאה'), findsOneWidget);
      expect(find.text('אישור ביטחוני'), findsOneWidget);
    });

    testWidgets('delete asks first, and cancelling deletes nothing',
        (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: [mine],
      );
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);

      await tester.tap(find.byKey(const Key('task-delete-mine')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('task-delete-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-delete-cancel')));
      await tester.pumpAndSettle();

      expect(repository.calls, isEmpty);
    });

    testWidgets('confirming a delete sends it', (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: [mine],
      );
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);

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
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: [mine],
      );
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);
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
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: [mine],
      );
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);
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
      expect(
        find.descendant(
          of: confirm,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.text('להזמין אוטובוס'), findsOneWidget);
    });

    Future<void> fillNewTask(WidgetTester tester, String title) async {
      // The button scales in when the list first loads and ignores taps until
      // that animation ends.
      await tester.pumpAndSettle();
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);

      await tester.tap(find.byKey(const Key('stage-add-task-st1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('task-form-title')), title);
      await tester.tap(find.byKey(const Key('task-form-assignees')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-assignee-m2')));
      await tester.pump();
    }

    testWidgets('a manager creates a task through the form', (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: const [],
      );
      await fillNewTask(tester, 'משימה חדשה לגמרי');
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['insert:משימה חדשה לגמרי']);
      expect(find.byKey(const Key('task-form-title')), findsNothing);
    });

    testWidgets(
        'the new-task form offers only the members assigned to the '
        'chosen event', (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: const [],
      );
      repository.assigneesByEvent = {
        'e1': [yoav],
      };
      await fillNewTask(tester, 'כותרת');

      expect(find.byKey(const Key('task-form-assignee-m2')), findsOneWidget);
      expect(find.byKey(const Key('task-form-assignee-m1')), findsNothing);
    });

    testWidgets('a create the backend refuses keeps the form open and says why',
        (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: const [],
      );
      await fillNewTask(tester, 'משימה שנדחתה');
      repository.failWith = DatabaseException(
        'Failed backend mutation task.insert: אין הרשאה ליצור משימות',
      );
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['insert:משימה שנדחתה']);
      expect(find.text('אין הרשאה ליצור משימות'), findsOneWidget);
      expect(find.byKey(const Key('task-form-title')), findsOneWidget);
      expect(find.text('משימה שנדחתה'), findsOneWidget);
    });

    testWidgets('a manager edits a task through the form', (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: [mine],
      );
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);

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
  });

  group('excel import', () {
    final admin = buildMember(id: 'boss', isAdmin: true);

    testWidgets('a manager sees import and template on an event without stages',
        (tester) async {
      await pumpScreen(tester, user: admin, tasks: const [], stages: const []);
      expect(find.byKey(const Key('tasks-import')), findsOneWidget);
      expect(find.byKey(const Key('tasks-import-template')), findsOneWidget);
    });

    testWidgets('a member gets no import buttons', (tester) async {
      await pumpScreen(tester, user: dana, tasks: const [], stages: const []);
      expect(find.byKey(const Key('tasks-import')), findsNothing);
      expect(find.byKey(const Key('tasks-import-template')), findsNothing);
    });

    testWidgets('no import once the event has a stage', (tester) async {
      await pumpScreen(tester, user: admin, tasks: const []);
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
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

  group('folds', () {
    testWidgets('a stage starts folded and opens and closes on its title',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine], openStages: false);

      expect(find.text('קליטה'), findsOneWidget);
      expect(find.text('להזמין אוטובוס'), findsNothing);

      await tester.tap(find.byKey(const Key('stage-toggle-st1')));
      await tester.pump();
      expect(find.text('להזמין אוטובוס'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stage-toggle-st1')));
      await tester.pump();
      expect(find.text('להזמין אוטובוס'), findsNothing);
    });

    testWidgets('an open stage stays open when its tasks change',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [withSubtasks]);
      expect(find.byKey(const Key('subtask-a')), findsOneWidget);

      // Someone creates an overdue task, which sorts above the other one.
      final overdue = buildTask(
        id: 'late',
        title: 'משימה באיחור',
        event: event,
        assigneeIds: const ['m1'],
        assignees: [dana],
        dueAt: DateTime(2026, 10, 9, 9),
      );
      repository.controller.add(TaskBoard(
        tasks: [withSubtasks, overdue],
        events: [event],
        stages: [arrival],
        members: [dana, yoav],
      ));
      await tester.pump();
      await tester.pump();
      await openAllStages(tester);

      expect(find.text('משימה באיחור'), findsOneWidget);
      expect(find.byKey(const Key('subtask-a')), findsOneWidget);
    });

    testWidgets('subtasks always show, without pressing the task',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [withSubtasks]);

      expect(find.byKey(const Key('subtask-a')), findsOneWidget);
      expect(find.byKey(const Key('subtask-b')), findsOneWidget);

      await tester.tap(find.text('אישור ביטחוני'));
      await tester.pump();
      expect(find.byKey(const Key('subtask-a')), findsOneWidget);
    });
  });

  group('text fields', () {
    testWidgets('the search field carries the RTL caret fix', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      final field = tester.widget<TextField>(
        find.byKey(const Key('tasks-search')),
      );
      expect(field.focusNode, isA<RtlCursorFixedFocusNode>());
    });
  });

  group('appearance', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final lighter = la > lb ? la : lb;
      final darker = la > lb ? lb : la;
      return (lighter + 0.05) / (darker + 0.05);
    }

    testWidgets('the selected mine/all segment is readable under the app theme',
        (tester) async {
      // The app theme's default selected-segment colours are white text on
      // light orange, which cannot be read.
      await pumpScreen(tester,
          user: dana, tasks: [mine], theme: AppTheme.lightTheme);

      final button = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      final style = button.style;
      expect(style, isNotNull);
      const selected = {WidgetState.selected};
      final background = style!.backgroundColor!.resolve(selected)!;
      final foreground = style.foregroundColor!.resolve(selected)!;
      expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
    });

    testWidgets('shows the test-environment banner in test mode only',
        (tester) async {
      EnvironmentService.instance.updateFromPath('/test/tasks');
      addTearDown(() => EnvironmentService.instance.updateFromPath('/tasks'));
      await pumpScreen(tester, user: dana, tasks: [mine]);
      expect(find.textContaining('סביבת בדיקות'), findsOneWidget);

      EnvironmentService.instance.updateFromPath('/tasks');
      await tester.pump();
      expect(find.textContaining('סביבת בדיקות'), findsNothing);
    });
  });

  group('ordering', () {
    testWidgets('overdue tasks come before open ones', (tester) async {
      final overdue = buildTask(
        id: 'late',
        title: 'משימה באיחור',
        event: event,
        assigneeIds: const ['m1'],
        assignees: [dana],
        dueAt: DateTime(2026, 10, 9, 9),
      );
      await pumpScreen(tester, user: dana, tasks: [mine, overdue]);

      final lateY = tester.getTopLeft(find.text('משימה באיחור')).dy;
      final openY = tester.getTopLeft(find.text('להזמין אוטובוס')).dy;
      expect(lateY, lessThan(openY));
    });
  });

  group('event and stages', () {
    final admin = buildMember(id: 'boss', isAdmin: true);
    final evening = buildStage(
      id: 'st2',
      eventId: 'e1',
      title: 'ערב גיבוש',
      date: DateTime(2026, 10, 20),
      startTime: '19:00',
      endTime: '22:30',
      hotelLocation: 'אולם ב',
    );
    final dayTwo = buildStage(
      id: 'st3',
      eventId: 'e1',
      title: 'יציאה',
      date: DateTime(2026, 10, 21),
    );
    final detailed = buildStage(
      id: 'st4',
      eventId: 'e1',
      title: 'כנס',
      date: DateTime(2026, 10, 21),
      requirements: 'מקרן ושני מיקרופונים',
      notes: 'להגיע חצי שעה לפני',
      contacts: const [
        StageContact(
            id: 'c1', name: 'אבי', phone: '050-1234567', role: 'מנהל אירועים'),
      ],
    );

    Future<void> showAll(WidgetTester tester) async {
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await openAllStages(tester);
    }

    testWidgets('the header shows the event, its days and its place',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      expect(find.text('דו יומי צפון'), findsOneWidget);
      expect(find.text('20/10/2026 – 21/10/2026'), findsOneWidget);
      expect(find.text('מלון קיסר'), findsOneWidget);
    });

    testWidgets('stages run by day and start time, with their time and place',
        (tester) async {
      await pumpScreen(
        tester,
        user: dana,
        tasks: const [],
        stages: [dayTwo, evening, arrival],
      );
      await showAll(tester);

      double top(String id) =>
          tester.getTopLeft(find.byKey(Key('stage-card-$id'))).dy;
      expect(top('st1'), lessThan(top('st2')));
      expect(top('st2'), lessThan(top('st3')));
      expect(
        find.text('20/10 · \u206619:00–22:30\u2069 · אולם ב'),
        findsOneWidget,
      );
      expect(find.text('20/10 · 08:00'), findsOneWidget);
    });

    testWidgets('my tasks shows only the stages holding my tasks',
        (tester) async {
      final mineAtNight = buildTask(
        id: 'night',
        title: 'סידור אולם',
        stageId: 'st2',
        assigneeIds: const ['m1'],
        assignees: [dana],
      );
      await pumpScreen(
        tester,
        user: dana,
        tasks: [mineAtNight, theirs],
        stages: [arrival, evening, dayTwo],
      );

      expect(find.byKey(const Key('stage-card-st2')), findsOneWidget);
      expect(find.byKey(const Key('stage-card-st1')), findsNothing);
      expect(find.byKey(const Key('stage-card-st3')), findsNothing);

      await showAll(tester);
      expect(find.byKey(const Key('stage-card-st1')), findsOneWidget);
      expect(find.byKey(const Key('stage-card-st3')), findsOneWidget);
    });

    testWidgets(
        'a search hides the stages with nothing matching, even under '
        'all tasks', (tester) async {
      final night = buildTask(
        id: 'night',
        title: 'סידור אולם',
        stageId: 'st2',
        assigneeIds: const ['m2'],
      );
      await pumpScreen(
        tester,
        user: dana,
        tasks: [mine, night],
        stages: [arrival, evening],
      );
      await showAll(tester);

      await tester.enterText(find.byKey(const Key('tasks-search')), 'אולם');
      await tester.pump();

      expect(find.byKey(const Key('stage-card-st2')), findsOneWidget);
      expect(find.byKey(const Key('stage-card-st1')), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
        'the task count is of all the stage\'s tasks, not only the '
        'visible ones', (tester) async {
      final theirsDone = buildTask(
        id: 'done',
        title: 'סגור',
        assigneeIds: const ['m2'],
        isComplete: true,
      );
      await pumpScreen(tester, user: dana, tasks: [mine, theirsDone]);

      expect(find.text('משימות: \u20661/2\u2069'), findsOneWidget);
    });

    testWidgets('the stage details stay folded until opened', (tester) async {
      await pumpScreen(
        tester,
        user: dana,
        tasks: const [],
        stages: [arrival, detailed],
      );
      await showAll(tester);

      expect(find.text('מקרן ושני מיקרופונים'), findsNothing);
      expect(find.byKey(const Key('stage-details-toggle-st1')), findsNothing,
          reason: 'a stage with no details has no fold');
      expect(find.text('להגיע חצי שעה לפני'), findsOneWidget,
          reason: 'the notes sit with the time and place, not in the fold');

      await tester.tap(find.byKey(const Key('stage-details-toggle-st4')));
      await tester.pump();

      expect(find.text('מקרן ושני מיקרופונים'), findsOneWidget);
      expect(find.text('להגיע חצי שעה לפני'), findsOneWidget);
      expect(find.text('אבי · מנהל אירועים'), findsOneWidget);
      expect(find.byKey(const Key('stage-contact-call-c1')), findsOneWidget);
      expect(find.text('050-1234567'), findsOneWidget);
    });

    testWidgets('a folded stage still shows its notes', (tester) async {
      await pumpScreen(
        tester,
        user: dana,
        tasks: const [],
        stages: [detailed],
        openStages: false,
      );
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();

      expect(find.byKey(const Key('stage-body-st4')), findsNothing);
      expect(find.text('להגיע חצי שעה לפני'), findsOneWidget);
    });

    testWidgets('a stage with only notes has no details fold', (tester) async {
      final notesOnly = buildStage(
        id: 'st5',
        eventId: 'e1',
        title: 'ארוחת ערב',
        date: DateTime(2026, 10, 20),
        notes: 'בחדר האוכל',
      );
      await pumpScreen(
        tester,
        user: dana,
        tasks: const [],
        stages: [notesOnly],
      );
      await showAll(tester);

      expect(find.text('בחדר האוכל'), findsOneWidget);
      expect(find.byKey(const Key('stage-details-toggle-st5')), findsNothing);
    });

    testWidgets('a task whose stage is gone is not shown', (tester) async {
      final stray = buildTask(
        id: 'stray',
        title: 'משימה יתומה',
        stageId: 'gone',
        assigneeIds: const ['m1'],
      );
      await pumpScreen(tester, user: dana, tasks: [mine, stray]);

      expect(find.text('להזמין אוטובוס'), findsOneWidget);
      expect(find.text('משימה יתומה'), findsNothing);
    });

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

    testWidgets('the back arrow returns to the event list', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      await tester.tap(find.byKey(const Key('tasks-back')));
      await tester.pumpAndSettle();

      expect(find.text('רשימת האירועים'), findsOneWidget);
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

    testWidgets('a manager edits a stage', (tester) async {
      await pumpScreen(tester, user: admin, tasks: [mine]);
      await showAll(tester);

      await tester.tap(find.byKey(const Key('stage-edit-st1')));
      await tester.pumpAndSettle();
      expect(find.text('קליטה'), findsWidgets);
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
      await showAll(tester);

      await tester.tap(find.byKey(const Key('stage-delete-st1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('יימחקו גם 2 המשימות שבו'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stage-delete-confirm')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['deleteStage:st1']);
      expect(find.byKey(const Key('stage-delete-confirm')), findsNothing);
    });
  });
}
