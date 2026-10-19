import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shavtzak/core/services/environment_service.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/task/task_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/task/tasks_auto_open.dart';
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
  // Under way: it started yesterday and ends tomorrow.
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

  setUp(TasksAutoOpen.debugReset);

  /// [comingBack] is the member returning to the list from an event, after
  /// the session's one automatic opening; turn it off to arrive fresh.
  Future<void> pumpList(
    WidgetTester tester, {
    TeamMember? user,
    List<Event>? events,
    bool deliver = true,
    bool comingBack = true,
    Size size = const Size(900, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (comingBack) TasksAutoOpen.spend();

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
        tasks: const [],
        events: events ?? [south, past, north, other, running],
        members: [dana],
      ));
      await tester.pump();
      await tester.pump();
    }
  }

  Finder row(String id) => find.byKey(Key('task-event-$id'));

  group('opening', () {
    testWidgets('opens the nearest event that has not ended, straight away',
        (tester) async {
      await pumpList(tester, comingBack: false);
      await tester.pumpAndSettle();

      expect(find.text('event:running'), findsOneWidget);
    });

    testWidgets('stays on the list when nothing is coming up', (tester) async {
      await pumpList(tester, comingBack: false, events: [past, other]);
      await tester.pumpAndSettle();

      expect(find.text('אין אירועי דו יומי קרובים'), findsOneWidget);
      expect(find.textContaining('event:'), findsNothing);
    });

    testWidgets('coming back does not bounce into the event again',
        (tester) async {
      await pumpList(tester);
      await tester.pumpAndSettle();

      expect(row('running'), findsOneWidget);
      expect(find.text('event:running'), findsNothing);
    });

    testWidgets('waits on a spinner until the board arrives', (tester) async {
      await pumpList(tester, comingBack: false, deliver: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('lists every upcoming event nearest first, and nothing but events',
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
    // No counts on a row: only the event itself.
    for (final id in ['running', 'north', 'south']) {
      for (final word in ['משימות', 'שלבים', 'שלך']) {
        expect(
          find.descendant(of: row(id), matching: find.textContaining(word)),
          findsNothing,
          reason: '$id: $word',
        );
      }
    }
  });

  testWidgets('a row shows the weekdays, the dates and the place',
      (tester) async {
    await pumpList(tester);

    expect(
      find.descendant(
        of: row('north'),
        matching: find.text('שלישי–רביעי, ${ltr('20–21/10')}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('north'), matching: find.text('מלון קיסר')),
      findsOneWidget,
    );
  });

  testWidgets('the event under way is marked מתקיים עכשיו', (tester) async {
    await pumpList(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('task-event-live-running')),
        matching: find.text('מתקיים עכשיו'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('task-event-live-north')), findsNothing);
  });

  testWidgets('past events wait in a folded section, latest first',
      (tester) async {
    final older = buildEvent(
      id: 'older',
      name: 'דו יומי ישן יותר',
      startDate: DateTime(2026, 8, 1),
    );
    await pumpList(tester, events: [older, past, north]);

    expect(find.text('אירועים שעברו'), findsOneWidget);
    expect(row('past'), findsNothing);

    await tester.tap(find.byKey(const Key('tasks-past-toggle')));
    await tester.pump();
    expect(
      tester.getTopLeft(row('past')).dy,
      lessThan(tester.getTopLeft(row('older')).dy),
    );

    await tester.tap(find.byKey(const Key('tasks-past-toggle')));
    await tester.pump();
    expect(row('past'), findsNothing);
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

  testWidgets('on a wide window the list is centred at a readable width',
      (tester) async {
    await pumpList(tester, size: const Size(1280, 900));

    expect(
      tester.getSize(row('north')).width,
      lessThanOrEqualTo(TaskStyle.readableWidth),
    );
    final centre = tester.getCenter(row('north')).dx;
    expect(centre, closeTo(640, 1));
  });

  testWidgets('shows the test-environment banner in test mode', (tester) async {
    EnvironmentService.instance.updateFromPath('/test/tasks');
    addTearDown(() => EnvironmentService.instance.updateFromPath('/tasks'));
    await pumpList(tester);
    expect(find.textContaining('סביבת בדיקות'), findsOneWidget);
  });
}
