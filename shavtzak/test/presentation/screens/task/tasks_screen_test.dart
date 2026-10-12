import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/environment_service.dart';
import 'package:shavtzak/core/theme/app_theme.dart';
import 'package:shavtzak/core/utils/rtl_text_field_utils.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/task/task_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_event.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/task/tasks_screen.dart';

import '../../../support/task_fixtures.dart';

class _MockUserSelectionBloc
    extends MockBloc<UserSelectionEvent, UserSelectionState>
    implements UserSelectionBloc {}

/// A repository whose board the test pushes and whose mutations can fail.
class _FakeTaskRepository extends Fake implements TaskRepository {
  StreamController<TaskBoard> controller = StreamController<TaskBoard>();
  int watchCalls = 0;
  final calls = <String>[];
  Object? failWith;

  /// While set, a mutation does not answer until the test completes it.
  Completer<void>? gate;

  /// Who is assigned to each event, as the task form sees it.
  Map<String, List<TeamMember>> assigneesByEvent = {};

  @override
  Stream<List<TeamMember>> watchEventAssignees(String eventId) =>
      Stream.value(assigneesByEvent[eventId] ?? const []);

  @override
  Stream<TaskBoard> watchBoard() {
    watchCalls++;
    return controller.stream;
  }

  Future<void> _record(String call) async {
    calls.add(call);
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<void> insertTask(TaskItem task) => _record('insert:${task.title}');

  @override
  Future<void> updateTask(TaskItem task) => _record('update:${task.id}');

  @override
  Future<void> deleteTask(String taskId) => _record('delete:$taskId');

  @override
  Future<void> setSubtaskDone(String taskId, String subtaskId, bool isDone) =>
      _record('subtask:$taskId:$subtaskId:$isDone');

  @override
  Future<void> setTaskComplete(String taskId, bool isComplete) =>
      _record('complete:$taskId:$isComplete');

  @override
  Future<void> setTaskAssigneeUpdate(String taskId, String text) =>
      _record('note:$taskId:$text');
}

void main() {
  final now = DateTime(2026, 10, 11, 14, 0);

  final event = buildEvent(
    id: 'e1',
    name: 'דו יומי צפון',
    startDate: DateTime(2026, 10, 20),
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

  late _FakeTaskRepository repository;
  late TaskBloc taskBloc;
  late _MockUserSelectionBloc userBloc;

  Future<void> pumpScreen(
    WidgetTester tester, {
    required TeamMember user,
    List<TaskItem>? tasks,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Built here, inside the test's fake-async zone. A bloc created in setUp
    // would run its stream callbacks in the real zone, where `pump` never
    // reaches them.
    repository = _FakeTaskRepository()
      ..assigneesByEvent = {
        'e1': [dana, yoav],
      };
    taskBloc = TaskBloc(repository: repository);
    userBloc = _MockUserSelectionBloc();
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
        child: MaterialApp(
          theme: theme,
          home: TasksScreen(clock: () => now),
        ),
      ),
    ));
    await tester.pump();

    if (tasks != null) {
      repository.controller.add(TaskBoard(
        tasks: tasks,
        events: [event],
        members: [dana, yoav],
      ));
      await tester.pump();
      await tester.pump();
    }
  }

  group('loading', () {
    testWidgets('shows a spinner until the first tasks arrive', (tester) async {
      await pumpScreen(tester, user: dana);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.controller.add(const TaskBoard(tasks: []));
      await tester.pump();
      await tester.pump();
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
      repository.controller.add(TaskBoard(tasks: [mine]));
      await tester.pump();
      await tester.pump();

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

      expect(find.text('להזמין אוטובוס'), findsOneWidget);
      expect(find.text('הזמנת קייטרינג'), findsOneWidget);

      await tester.tap(find.text('המשימות שלי'));
      await tester.pump();
      expect(find.text('הזמנת קייטרינג'), findsNothing);
    });

    testWidgets('a member with no tasks sees a prompt, not a blank screen',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [theirs]);
      expect(find.text('אין לך משימות'), findsOneWidget);
    });

    testWidgets('all tasks with none at all says so', (tester) async {
      await pumpScreen(tester, user: dana, tasks: const []);
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      expect(find.text('אין משימות'), findsOneWidget);
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

    testWidgets('the filter offers assignees under all tasks but not under my '
        'tasks', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine, theirs]);

      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      expect(find.text('אחראי'), findsNothing);
      expect(find.byKey(const Key('filter-assignee-m1')), findsNothing);
      expect(find.byKey(const Key('filter-event-e1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('filter-close')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      expect(find.text('אחראי'), findsOneWidget);
      expect(find.byKey(const Key('filter-assignee-m1')), findsOneWidget);
      expect(find.byKey(const Key('filter-assignee-m2')), findsOneWidget);
    });

    testWidgets('under my tasks the filter offers only the events the member '
        'has tasks in, under all tasks every event with a task',
        (tester) async {
      final south = buildEvent(
        id: 'e2',
        name: 'דו יומי דרום',
        startDate: DateTime(2026, 10, 27),
      );
      final theirsSouth = buildTask(
        id: 'south',
        title: 'הסעות לדרום',
        eventId: 'e2',
        event: south,
        assigneeIds: const ['m2'],
        assignees: [yoav],
      );
      await pumpScreen(tester, user: dana, tasks: [mine, theirsSouth]);

      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filter-event-e1')), findsOneWidget);
      expect(find.byKey(const Key('filter-event-e2')), findsNothing);
      await tester.tap(find.byKey(const Key('filter-close')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tasks-filter')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filter-event-e1')), findsOneWidget);
      expect(find.byKey(const Key('filter-event-e2')), findsOneWidget);
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

    testWidgets('the half-hour filter keeps only unfinished tasks due in the '
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
    testWidgets('an admin gets the new-task button', (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: [mine],
      );
      expect(find.byKey(const Key('tasks-add')), findsOneWidget);
    });

    testWidgets('a flagged non-admin gets the new-task button', (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'lead', canManageTasks: true),
        tasks: [mine],
      );
      expect(find.byKey(const Key('tasks-add')), findsOneWidget);
    });

    testWidgets('a plain member gets no new-task, edit or delete button',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      expect(find.byKey(const Key('tasks-add')), findsNothing);
      expect(find.byKey(const Key('task-edit-mine')), findsNothing);
      expect(find.byKey(const Key('task-delete-mine')), findsNothing);
    });

    testWidgets('a member cannot tick someone else\'s task', (tester) async {
      await pumpScreen(tester, user: dana, tasks: [theirs]);
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();

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

      await tester.tap(find.byKey(const Key('task-delete-mine')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-delete-confirm')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['delete:mine']);
      expect(find.byKey(const Key('task-delete-confirm')), findsNothing);
    });

    testWidgets('a confirmed delete shows a spinner and stays open until the '
        'backend answers', (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: [mine],
      );
      await tester.tap(find.text('כל המשימות'));
      await tester.pump();
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

      await tester.tap(find.byKey(const Key('tasks-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-form-event')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('דו יומי צפון').last);
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

    testWidgets('the new-task form offers only the members assigned to the '
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

  group('expanded cards', () {
    testWidgets('a card stays open when another task moves in above it',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [withSubtasks]);
      await tester.tap(find.text('אישור ביטחוני'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('subtask-a')), findsOneWidget);

      // Someone creates an overdue task, which sorts above the open card.
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
        members: [dana, yoav],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('משימה באיחור'), findsOneWidget);
      expect(find.byKey(const Key('subtask-a')), findsOneWidget);
      expect(find.byKey(const Key('subtask-b')), findsOneWidget);
    });

    testWidgets('a card stays open when ticking its last subtask completes it',
        (tester) async {
      final other = buildTask(
        id: 'other',
        title: 'משימה אחרת',
        event: event,
        assigneeIds: const ['m1'],
        assignees: [dana],
      );
      await pumpScreen(tester, user: dana, tasks: [withSubtasks, other]);
      await tester.tap(find.text('אישור ביטחוני'));
      await tester.pumpAndSettle();

      // The backend answers: every subtask done, so the task is complete and
      // drops to the bottom of the list.
      repository.controller.add(TaskBoard(
        tasks: [
          withSubtasks.copyWith(
            isComplete: true,
            subtasks: const [
              Subtask(id: 'a', title: 'טופס', isDone: true),
              Subtask(id: 'b', title: 'חתימה', isDone: true),
            ],
          ),
          other,
        ],
        events: [event],
        members: [dana, yoav],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('subtask-a')), findsOneWidget);
      expect(find.byKey(const Key('subtask-b')), findsOneWidget);
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
      await pumpScreen(tester, user: dana, tasks: [mine], theme: AppTheme.lightTheme);

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
}
