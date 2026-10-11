import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';

import '../../support/task_fixtures.dart';
import 'user_selection_session_lost_test.mocks.dart';

/// The tasks screen reads the signed-in member from [UserSelectionBloc] to
/// decide whether to show the manager controls. An admin flipping the member's
/// `canManageTasks` switch must reach an already-open screen without a reload.
void main() {
  late MockUserSelectionRepository userSelectionRepository;
  late MockTeamRepository teamRepository;
  late StreamController<List<TeamMember>> teamController;

  setUp(() {
    userSelectionRepository = MockUserSelectionRepository();
    teamRepository = MockTeamRepository();
    teamController = StreamController<List<TeamMember>>.broadcast();
    when(teamRepository.watchTeamMembers())
        .thenAnswer((_) => teamController.stream);
  });

  tearDown(() async {
    await teamController.close();
  });

  test('granting canManageTasks re-emits the signed-in member with the flag',
      () async {
    final member = buildMember(id: 'm1');
    final bloc = UserSelectionBloc(
      userSelectionRepository,
      teamRepository,
      member,
    );
    addTearDown(bloc.close);
    await Future<void>.delayed(Duration.zero);

    final emitted = expectLater(
      bloc.stream,
      emits(
        isA<UserAuthenticated>().having(
          (state) => state.user.canManageTasks,
          'user.canManageTasks',
          isTrue,
        ),
      ),
    );
    teamController.add([member.copyWith(canManageTasks: true)]);
    await emitted;
  });

  test('revoking canManageTasks re-emits the signed-in member without it',
      () async {
    final manager = buildMember(id: 'm1', canManageTasks: true);
    final bloc = UserSelectionBloc(
      userSelectionRepository,
      teamRepository,
      manager,
    );
    addTearDown(bloc.close);
    await Future<void>.delayed(Duration.zero);

    final emitted = expectLater(
      bloc.stream,
      emits(
        isA<UserAuthenticated>().having(
          (state) => state.user.canManageTasks,
          'user.canManageTasks',
          isFalse,
        ),
      ),
    );
    teamController.add([manager.copyWith(canManageTasks: false)]);
    await emitted;
  });
}
