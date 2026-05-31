import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/data/repositories/team_repository.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/team/team_bloc.dart';
import 'package:shavtzak/presentation/bloc/team/team_event.dart';
import 'package:shavtzak/presentation/bloc/team/team_state.dart';

import 'team_bloc_subscription_test.mocks.dart';

@GenerateMocks([TeamRepository, AssignmentRepository])
void main() {
  late MockTeamRepository mockTeamRepository;
  late MockAssignmentRepository mockAssignmentRepository;
  late StreamController<List<TeamMember>> controller;

  /// Build a minimal valid TeamMember for tests.
  TeamMember member({
    required String id,
    required String name,
    bool isActive = true,
  }) {
    final now = DateTime(2024, 1, 1);
    return TeamMember(
      id: id,
      name: name,
      isActive: isActive,
      constraints: const [],
      roleCapabilities: const {},
      createdAt: now,
      updatedAt: now,
      uniqueKey: 'key-$id',
    );
  }

  setUp(() {
    mockTeamRepository = MockTeamRepository();
    mockAssignmentRepository = MockAssignmentRepository();
    // Broadcast so the bloc subscription does not consume the single-listener
    // budget and tests can also read frames if needed.
    controller = StreamController<List<TeamMember>>.broadcast();
    when(mockTeamRepository.watchTeamMembers())
        .thenAnswer((_) => controller.stream);
  });

  tearDown(() async {
    await controller.close();
  });

  TeamBloc buildBloc() => TeamBloc(
        mockTeamRepository,
        mockAssignmentRepository,
        calendarSyncBloc: null,
      );

  test(
      'subscribes to watchTeamMembers exactly once for repeated LoadTeamMembers',
      () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    bloc.add(const LoadTeamMembers());
    // Allow the first Load to process and establish the subscription.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    bloc.add(const LoadTeamMembers());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The core fix: exactly ONE subscription, never torn down/re-created
    // on a repeat Load.
    verify(mockTeamRepository.watchTeamMembers()).called(1);
  });

  test(
      'real-time updates propagate WITHOUT a reload through the single subscription',
      () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    final emitted = <TeamState>[];
    final sub = bloc.stream.listen(emitted.add);
    addTearDown(sub.cancel);

    final memberA = member(id: 'a', name: 'Alpha');

    bloc.add(const LoadTeamMembers());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Initial Firestore emission.
    controller.add([memberA]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final loadedStates = emitted.whereType<TeamLoaded>().toList();
    expect(loadedStates, isNotEmpty);
    expect(loadedStates.last.members.single.name, 'Alpha');

    // A live change in Firestore arrives on the SAME subscription, with NO
    // further Load dispatch.
    final changed = memberA.copyWith(name: 'changed');
    controller.add([changed]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final loadedAfter = emitted.whereType<TeamLoaded>().toList();
    // A NEW TeamLoaded must be emitted reflecting the change.
    expect(loadedAfter.last.members.single.name, 'changed',
        reason:
            'Live Firestore change must flow to the UI through the single subscription with no reload');
    // Still only one subscription.
    verify(mockTeamRepository.watchTeamMembers()).called(1);
  });

  test(
      'filter switch (all -> active) is served from cache without a second subscription',
      () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    final emitted = <TeamState>[];
    final sub = bloc.stream.listen(emitted.add);
    addTearDown(sub.cancel);

    final activeMember = member(id: 'a', name: 'Active', isActive: true);
    final inactiveMember = member(id: 'i', name: 'Inactive', isActive: false);

    // Load ALL members.
    bloc.add(const LoadTeamMembers());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.add([activeMember, inactiveMember]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final allLoaded = emitted.whereType<TeamLoaded>().toList();
    expect(allLoaded.last.members.length, 2,
        reason: 'LoadTeamMembers should surface both active and inactive');

    // Switch filter to ACTIVE only — must be served from cache.
    bloc.add(const LoadActiveTeamMembers());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final activeLoaded = emitted.whereType<TeamLoaded>().toList();
    expect(activeLoaded.last.members.length, 1);
    expect(activeLoaded.last.members.single.name, 'Active');

    // No second subscription was created for the filter switch.
    verify(mockTeamRepository.watchTeamMembers()).called(1);
  });
}
