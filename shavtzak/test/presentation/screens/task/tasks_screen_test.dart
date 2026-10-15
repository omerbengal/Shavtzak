import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shavtzak/core/services/environment_service.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/task/task_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/task/tasks_screen.dart';

import '../../../support/fake_task_repository.dart';
import '../../../support/task_fixtures.dart';

void main() {
  // Sunday afternoon; "today" is 2026-10-11.
  final now = DateTime(2026, 10, 11, 14, 0);

  final dana = buildMember(id: 'm1', name: 'דנה');

  final north = buildEvent(
    id: 'north',
    name: 'דו יומי צפון',
    startDate: DateTime(2026, 10, 20),
    endDate: DateTime(2026, 10, 21),
    location: 'מלון קיסר',
  );
  final south = buildEvent(
    id: 'south',
    name: 'דו יומי דרום',
    startDate: DateTime(2026, 11, 3),
  );
  final running = buildEvent(
    id: 'running',
    name: 'דו יומי מרכז',
    startDate: DateTime(2026, 10, 10),
    endDate: DateTime(2026, 10, 12),
  );
  final past = buildEvent(
    id: 'past',
    name: 'דו יומי ישן',
    startDate: DateTime(2026, 9, 1),
  );
  final other = buildEvent(
    id: 'other',
    name: 'חנוכה',
    startDate: DateTime(2026, 10, 25),
    categoryId: '6de41bf3-1a22-476d-b922-ec35ede6bc9f',
  );

  late FakeTaskRepository repository;
  late TaskBloc taskBloc;

  Future<void> pumpList(
    WidgetTester tester, {
    TeamMember? user,
    List<Event>? events,
    List<TaskItem> tasks = const [],
    List<Stage> stages = const [],
    bool deliver = true,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Built inside the test's fake-async zone; see the event screen tests.
    repository = FakeTaskRepository();
    taskBloc = TaskBloc(repository: repository);
    final userBloc = MockUserSelectionBloc();
    addTearDown(() {
      unawaited(taskBloc.close());
      if (!repository.controller.isClosed) {
        unawaited(repository.controller.close());
      }
    });
    whenListen(
      userBloc,
      const Stream<UserSelectionState>.empty(),
      initialState: UserAuthenticated(user ?? dana),
    );

    await tester.pumpWidget(RepositoryProvider<TaskRepository>.value(
      value: repository,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TaskBloc>.value(value: taskBloc),
          BlocProvider<UserSelectionBloc>.value(value: userBloc),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/tasks',
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (context, state) => TasksScreen(clock: () => now),
              ),
              GoRoute(
                path: '/tasks/:eventId',
                builder: (context, state) => Scaffold(
                  body: Text('event:${state.pathParameters['eventId']}'),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    if (deliver) {
      repository.controller.add(TaskBoard(
        tasks: tasks,
        events: events ?? [south, past, north, other, running],
        stages: stages,
        members: [dana],
      ));
      await tester.pump();
      await tester.pump();
    }
  }

  Finder row(String id) => find.byKey(Key('task-event-$id'));

  testWidgets('shows a spinner until the board arrives', (tester) async {
    await pumpList(tester, deliver: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('lists the upcoming דו יומי events, nearest first, with a count',
      (tester) async {
    await pumpList(tester);

    expect(find.text('אירועים קרובים'), findsOneWidget);
    expect(row('running'), findsOneWidget);
    expect(row('north'), findsOneWidget);
    expect(row('south'), findsOneWidget);
    expect(row('other'), findsNothing, reason: 'not a דו יומי event');
    double top(String id) => tester.getTopLeft(row(id)).dy;
    expect(top('running'), lessThan(top('north')));
    expect(top('north'), lessThan(top('south')));
  });

  testWidgets('past events wait in a folded section with their count',
      (tester) async {
    await pumpList(tester);

    expect(find.text('אירועים שעברו'), findsOneWidget);
    expect(row('past'), findsNothing);

    await tester.tap(find.byKey(const Key('tasks-past-toggle')));
    await tester.pump();
    expect(row('past'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tasks-past-toggle')));
    await tester.pump();
    expect(row('past'), findsNothing);
  });

  testWidgets('a row shows the event\'s days, place and what is open in it',
      (tester) async {
    await pumpList(
      tester,
      tasks: [
        buildTask(
            id: 'a',
            eventId: 'north',
            stageId: 's1',
            assigneeIds: const ['m1']),
        buildTask(
            id: 'b',
            eventId: 'north',
            stageId: 's1',
            assigneeIds: const ['m2']),
        buildTask(
          id: 'c',
          eventId: 'north',
          stageId: 's1',
          assigneeIds: const ['m1'],
          isComplete: true,
        ),
      ],
      stages: [
        buildStage(id: 's1', eventId: 'north'),
        buildStage(id: 's2', eventId: 'north'),
        buildStage(id: 's3', eventId: 'north'),
      ],
    );

    expect(find.text('20/10/2026 – 21/10/2026 · מלון קיסר'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('task-event-summary-north')))
          .data,
      '3 שלבים · 2 משימות פתוחות · 1 שלך',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('task-event-summary-south')))
          .data,
      '0 שלבים · 0 משימות פתוחות',
    );
  });

  testWidgets('pressing an event opens its screen', (tester) async {
    await pumpList(tester);

    await tester.tap(row('north'));
    await tester.pumpAndSettle();

    expect(find.text('event:north'), findsOneWidget);
  });

  testWidgets('says so when there is no upcoming event', (tester) async {
    await pumpList(tester, events: [past]);
    expect(find.text('אין אירועי דו יומי קרובים'), findsOneWidget);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    await pumpList(tester, deliver: false);
    repository.controller.addError(Exception('permission-denied'));
    await tester.pump();
    await tester.pump();

    expect(find.text('טעינת המשימות נכשלה'), findsOneWidget);
    expect(find.byKey(const Key('tasks-retry')), findsOneWidget);
  });

  testWidgets('shows the test-environment banner in test mode', (tester) async {
    EnvironmentService.instance.updateFromPath('/test/tasks');
    addTearDown(() => EnvironmentService.instance.updateFromPath('/tasks'));
    await pumpList(tester);
    expect(find.textContaining('סביבת בדיקות'), findsOneWidget);
  });
}
