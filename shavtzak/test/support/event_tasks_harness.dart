import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/task/task_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/task/event_tasks_screen.dart';
import 'package:shavtzak/presentation/screens/task/tasks_place.dart';

import 'fake_task_import_files.dart';
import 'fake_task_repository.dart';

/// A phone, a phone tall enough that an open sheet shows a whole task, and a
/// computer.
const phoneSize = Size(400, 1000);
const tallPhoneSize = Size(400, 1800);
const wideSize = Size(1280, 900);

/// The event screen under test, with the fakes behind it.
class EventTasksHarness {
  EventTasksHarness(this.repository, this.bloc);

  final FakeTaskRepository repository;
  final TaskBloc bloc;

  /// Push [board] through the live stream, as Firestore would.
  Future<void> deliver(WidgetTester tester, TaskBoard board) async {
    repository.controller.add(board);
    await tester.pump();
    await tester.pump();
  }
}

/// Pumps `/tasks/<eventId>` under a router whose `/tasks` shows the text
/// 'רשימת האירועים'. The blocs are built here, inside the test's fake-async
/// zone: built in setUp, their stream callbacks would run where `pump` never
/// reaches them.
///
/// Unless [assignees] says otherwise, every member of [board] is assigned
/// to 'e1', so the managers' assignee check stays quiet.
Future<EventTasksHarness> pumpEventTasks(
  WidgetTester tester, {
  required TeamMember user,
  DateTime Function()? clock,
  Size size = phoneSize,
  TaskBoard? board,
  Map<String, List<TeamMember>>? assignees,
  FakeTaskRepository? repository,
  FakeTaskImportFiles? importFiles,
  ThemeData? theme,
  String eventId = 'e1',
  TasksPlace place = TasksPlace.tab,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = repository ?? FakeTaskRepository();
  if (assignees != null) {
    repo.assigneesByEvent = assignees;
  } else if (repository == null) {
    repo.assigneesByEvent = {'e1': board?.members ?? const []};
  }
  final bloc = TaskBloc(repository: repo);
  final userBloc = MockUserSelectionBloc();
  addTearDown(() {
    unawaited(bloc.close());
    if (!repo.controller.isClosed) unawaited(repo.controller.close());
  });
  whenListen(
    userBloc,
    const Stream<UserSelectionState>.empty(),
    initialState: UserAuthenticated(user),
  );

  final files = importFiles ?? FakeTaskImportFiles();
  await tester.pumpWidget(RepositoryProvider<TaskRepository>.value(
    value: repo,
    child: MultiBlocProvider(
      providers: [
        BlocProvider<TaskBloc>.value(value: bloc),
        BlocProvider<UserSelectionBloc>.value(value: userBloc),
      ],
      child: MaterialApp.router(
        theme: theme,
        routerConfig: GoRouter(
          initialLocation: place.eventRoute(eventId),
          routes: [
            GoRoute(
              path: place.listRoute,
              builder: (context, state) =>
                  const Scaffold(body: Text('רשימת האירועים')),
              routes: [
                GoRoute(
                  path: ':eventId',
                  builder: (context, state) => EventTasksScreen(
                    eventId: state.pathParameters['eventId']!,
                    place: place,
                    clock: clock ?? () => DateTime(2026, 10, 11, 14),
                    importFiles: files,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();

  final harness = EventTasksHarness(repo, bloc);
  if (board != null) await harness.deliver(tester, board);
  return harness;
}
