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

  @override
  Stream<TaskBoard> watchBoard() {
    watchCalls++;
    return controller.stream;
  }

  Future<void> _record(String call) async {
    calls.add(call);
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
    repository = _FakeTaskRepository();
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

    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider<TaskBloc>.value(value: taskBloc),
        BlocProvider<UserSelectionBloc>.value(value: userBloc),
      ],
      child: MaterialApp(
        theme: theme,
        home: TasksScreen(clock: () => now),
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
      await tester.tap(find.byKey(const Key('filter-apply')));
      await tester.pumpAndSettle();

      expect(find.text('משימה באיחור'), findsOneWidget);
      expect(find.text('להזמין אוטובוס'), findsNothing);
      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isTrue);
      expect(find.text('1'), findsOneWidget);
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

    testWidgets('a plain member gets no new-task button and no edit menu',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [mine]);

      expect(find.byKey(const Key('tasks-add')), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
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
      await tester.tap(find.byIcon(Icons.expand_more));
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
      await tester.tap(find.byIcon(Icons.expand_more));
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

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('מחיקה'));
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

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('מחיקה'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-delete-confirm')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['delete:mine']);
    });

    testWidgets('a manager creates a task through the form', (tester) async {
      await pumpScreen(
        tester,
        user: buildMember(id: 'boss', isAdmin: true),
        tasks: const [],
      );
      // The button scales in when the list first loads and ignores taps until
      // that animation ends.
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tasks-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-form-event')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('דו יומי צפון').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('task-form-title')),
        'משימה חדשה לגמרי',
      );
      await tester.tap(find.byKey(const Key('task-form-assignee-m2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-form-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['insert:משימה חדשה לגמרי']);
    });
  });

  group('expanded cards', () {
    testWidgets('a card stays open when another task moves in above it',
        (tester) async {
      await pumpScreen(tester, user: dana, tasks: [withSubtasks]);
      await tester.tap(find.byIcon(Icons.expand_more));
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
      await tester.tap(find.byIcon(Icons.expand_more));
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
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
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
