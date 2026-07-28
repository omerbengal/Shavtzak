import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/data/repositories/team_repository.dart';
import 'package:shavtzak/data/repositories/user_selection_repository.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_event.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';

import 'user_selection_session_lost_test.mocks.dart';

/// When the Firebase credential disappears underneath an authenticated session,
/// the app must say so. Staying on [UserAuthenticated] leaves every screen
/// rendering a snapshot that can no longer refresh, and the reference-data
/// reload in main.dart is gated on a *change* of identity — so a silent
/// re-authentication as the same person would never resubscribe roles and
/// categories.
@GenerateMocks([UserSelectionRepository, TeamRepository])
void main() {
  late MockUserSelectionRepository userSelectionRepository;
  late MockTeamRepository teamRepository;
  late StreamController<List<TeamMember>> teamController;

  final now = DateTime(2024, 1, 1);
  final authenticatedUser = TeamMember(
    id: 'member-1',
    name: 'עומר',
    isActive: true,
    constraints: const [],
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'key-member-1',
  );

  setUp(() {
    userSelectionRepository = MockUserSelectionRepository();
    teamRepository = MockTeamRepository();
    teamController = StreamController<List<TeamMember>>.broadcast();
    when(teamRepository.watchTeamMembers())
        .thenAnswer((_) => teamController.stream);
    when(userSelectionRepository.clearUserSelection())
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    await teamController.close();
  });

  UserSelectionBloc buildBloc({
    TeamMember? preAuthenticatedUser,
    Stream<bool>? sessionPresence,
  }) =>
      UserSelectionBloc(
        userSelectionRepository,
        teamRepository,
        preAuthenticatedUser,
        sessionPresence,
      );

  test('SessionLost while authenticated emits UserSignedOut', () async {
    final bloc = buildBloc(preAuthenticatedUser: authenticatedUser);
    addTearDown(bloc.close);

    expect(bloc.state, isA<UserAuthenticated>());

    final emitted = expectLater(
      bloc.stream,
      emits(isA<UserSignedOut>()),
    );
    bloc.add(const SessionLost());
    await emitted;

    verify(userSelectionRepository.clearUserSelection()).called(1);
  });

  test('SessionLost while not authenticated is ignored', () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    expect(bloc.state, isA<UserSelectionInitial>());

    final states = <UserSelectionState>[];
    final subscription = bloc.stream.listen(states.add);
    bloc.add(const SessionLost());
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(states, isEmpty);
    verifyNever(userSelectionRepository.clearUserSelection());
  });

  test('a session-presence stream reporting false drives the sign-out',
      () async {
    final presence = StreamController<bool>();
    addTearDown(presence.close);

    final bloc = buildBloc(
      preAuthenticatedUser: authenticatedUser,
      sessionPresence: presence.stream,
    );
    addTearDown(bloc.close);

    final emitted = expectLater(bloc.stream, emits(isA<UserSignedOut>()));
    presence.add(false);
    await emitted;
  });

  test('a session-presence stream reporting true changes nothing', () async {
    final presence = StreamController<bool>();
    addTearDown(presence.close);

    final bloc = buildBloc(
      preAuthenticatedUser: authenticatedUser,
      sessionPresence: presence.stream,
    );
    addTearDown(bloc.close);

    final states = <UserSelectionState>[];
    final subscription = bloc.stream.listen(states.add);
    presence.add(true);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(states, isEmpty);
    expect(bloc.state, isA<UserAuthenticated>());
  });
}
