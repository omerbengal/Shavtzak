import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/services/backend_api_service.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_event.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';

import 'user_selection_session_lost_test.mocks.dart';

/// main.dart opens a returning member's session from the snapshot on the
/// device and asks the bloc to confirm it in the background. A refusal must
/// sign the member out; no answer at all must not.
void main() {
  late MockUserSelectionRepository repository;
  late MockTeamRepository teamRepository;
  late StreamController<List<TeamMember>> teamController;

  final now = DateTime(2026, 10, 19);
  final restored = TeamMember(
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
    repository = MockUserSelectionRepository();
    teamRepository = MockTeamRepository();
    teamController = StreamController<List<TeamMember>>.broadcast();
    when(teamRepository.watchTeamMembers())
        .thenAnswer((_) => teamController.stream);
    when(repository.clearUserSelection()).thenAnswer((_) async {});
    when(repository.saveMemberSnapshot(any)).thenAnswer((_) async {});
  });

  tearDown(() async {
    await teamController.close();
  });

  Future<List<UserSelectionState>> revalidate() async {
    final bloc = UserSelectionBloc(repository, teamRepository, restored);
    addTearDown(bloc.close);
    final states = <UserSelectionState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(const RevalidateRestoredSession());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();
    return states;
  }

  test('a confirmed, unchanged session emits nothing', () async {
    when(repository.revalidateSession()).thenAnswer((_) async => restored);
    expect(await revalidate(), isEmpty);
  });

  test('a confirmed session takes the member as stored now', () async {
    final promoted = restored.copyWith(isAdmin: true);
    when(repository.revalidateSession()).thenAnswer((_) async => promoted);
    final states = await revalidate();
    expect(states, [UserAuthenticated(promoted)]);
  });

  test('a member who no longer exists is signed out', () async {
    when(repository.revalidateSession()).thenAnswer((_) async => null);
    expect(await revalidate(), [isA<UserSignedOut>()]);
    verify(repository.clearUserSelection()).called(1);
  });

  test('a refused session is signed out', () async {
    when(repository.revalidateSession()).thenThrow(
        const BackendApiException('User is no longer active', statusCode: 403));
    expect(await revalidate(), [isA<UserSignedOut>()]);
  });

  test('no answer from the backend keeps the session', () async {
    when(repository.revalidateSession()).thenThrow(const BackendApiException(
      BackendApiService.networkErrorMessage,
      isNetworkError: true,
    ));
    expect(await revalidate(), isEmpty);
    verifyNever(repository.clearUserSelection());
  });

  test('a server error keeps the session', () async {
    when(repository.revalidateSession())
        .thenThrow(const BackendApiException('boom', statusCode: 500));
    expect(await revalidate(), isEmpty);
  });
}
