import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/team_task/team_task_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/team_task/team_tasks_screen.dart';

import 'fake_task_repository.dart' show MockUserSelectionBloc;
import 'fake_team_task_repository.dart';

const teamPhoneSize = Size(400, 1000);
const teamWideSize = Size(1280, 900);

class TeamTasksHarness {
  TeamTasksHarness(this.repository, this.bloc);

  final FakeTeamTaskRepository repository;
  final TeamTaskBloc bloc;

  Future<void> deliver(WidgetTester tester, TeamTaskBoard board) async {
    repository.controller.add(board);
    await tester.pump();
    await tester.pump();
  }
}

/// Pumps the team tasks screen for [user], then delivers [board].
Future<TeamTasksHarness> pumpTeamTasks(
  WidgetTester tester, {
  required TeamMember user,
  required TeamTaskBoard board,
  Size size = teamPhoneSize,
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = FakeTeamTaskRepository();
  final bloc = TeamTaskBloc(
    repository: repository,
    clock: clock ?? () => DateTime.utc(2026, 11, 15, 8),
  );
  final userBloc = MockUserSelectionBloc();
  addTearDown(() {
    unawaited(bloc.close());
    unawaited(repository.controller.close());
  });
  whenListen(
    userBloc,
    const Stream<UserSelectionState>.empty(),
    initialState: UserAuthenticated(user),
  );
  await tester.pumpWidget(MultiBlocProvider(
    providers: [
      BlocProvider<TeamTaskBloc>.value(value: bloc),
      BlocProvider<UserSelectionBloc>.value(value: userBloc),
    ],
    child: MaterialApp(home: const TeamTasksScreen()),
  ));
  await tester.pump();
  final harness = TeamTasksHarness(repository, bloc);
  await harness.deliver(tester, board);
  return harness;
}
