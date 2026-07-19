// Widget test for Task 8 of the assignments-staged-save feature: a row whose
// slotKey is in AssignmentSlotsLoaded.stagedDeletionSlotKeys (Task 7) must
// render the red-stripe "יימחק בשמירה" overlay, exactly the way
// stagedGoneSlotKeys rows already get the "deleted upstream" overlay via
// _withDeletedRemotelyOverlay (see assignment_list_screen.dart).
//
// The overlay + the _getSlotKey helper it depends on are PRIVATE to
// assignment_list_screen.dart's library, so unlike assignment_save_bar.dart
// (tested directly in assignment_save_controls_test.dart) or
// same_day_assignment_mark.dart (tested directly in
// same_day_assignment_mark_test.dart), there is no standalone public widget
// to pump in isolation here. This test therefore pumps the real
// AssignmentListScreen and drives it with a stubbed AssignmentBloc state —
// the only way to exercise this code path from outside the library.
//
// Harness notes:
// - AssignmentBloc / EventBloc are stubbed with bloc_test's MockBloc +
//   whenListen (NOT a real Bloc wired to mocked repositories — the screen's
//   own row-rendering logic is what's under test, not the bloc's fetch/merge
//   pipeline, which already has dedicated bloc-level tests).
// - AssignmentLabelRepository is read directly via context.read (not a
//   Bloc) inside _buildSlotGrid's StreamBuilder, so it is faked the same
//   way: a minimal override of the one method actually called.
// - Every other context.read the screen performs (UserSelectionBloc,
//   AssignmentRepository, EventRepository, TeamRepository) lives inside
//   interactive callbacks (save, discard, logout, filter modal, ...) that
//   this test never triggers, so none of those need a provider here.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/filter_persistence.dart';
import 'package:shavtzak/data/repositories/assignment_label_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/assignment_label.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/event/event_event.dart';
import 'package:shavtzak/presentation/bloc/event/event_state.dart';
import 'package:shavtzak/presentation/screens/assignment/assignment_list_screen.dart';
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot.dart';

class _MockAssignmentBloc extends MockBloc<AssignmentEvent, AssignmentState>
    implements AssignmentBloc {}

class _MockEventBloc extends MockBloc<EventEvent, EventState>
    implements EventBloc {}

/// Real AssignmentLabelRepository requires a DatabaseInterface; since the
/// grid only ever calls watchAssignmentLabels() on it, faking the repository
/// itself (rather than constructing a real one over a fake DB) avoids
/// standing up ~127 unrelated DatabaseInterface members.
class _FakeAssignmentLabelRepository extends Mock
    implements AssignmentLabelRepository {
  @override
  Stream<List<AssignmentLabel>> watchAssignmentLabels() =>
      Stream.value(const <AssignmentLabel>[]);
}

void main() {
  final now = DateTime(2026, 7, 1);

  // A single filled slot: event "e1" / role "medic" / slotIndex 0, i.e.
  // slotKey "e1_medic_0" (matches AssignmentBloc/_getSlotKey's
  // "${eventId}_${roleKey}_${slotIndex}" convention).
  final member = TeamMember(
    id: 'm1',
    name: 'יוסי כהן',
    isActive: true,
    constraints: const [],
    roleCapabilities: const {'medic': true},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'unique-m1',
  );

  final event = Event(
    id: 'e1',
    name: 'אירוע קיץ',
    startDate: now,
    endDate: now,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );

  final role = Role(
    id: 'medic',
    key: 'medic',
    hebrewName: 'חובש',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );

  final assignment = Assignment(
    id: 'a1',
    eventId: 'e1',
    teamMemberId: 'm1',
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
    teamMember: member,
  );

  final slot = AssignmentSlot(
    event: event,
    role: role,
    slotIndex: 0,
    currentAssignment: assignment,
    // Must be non-empty: the screen shows a spinner-until-loaded gate keyed
    // on "does any slot have availableMembers", never rendering the grid at
    // all if every slot's availableMembers list is empty.
    availableMembers: [member],
  );

  Future<void> pumpAssignmentListWith(
    WidgetTester tester, {
    required Set<String> stagedDeletionSlotKeys,
  }) async {
    // FilterPersistence is process-global static state; pin it to the
    // "show everything" defaults so no filter hides our single test slot.
    FilterPersistence.assignmentFilterIndex = 0;
    FilterPersistence.showPastEvents = false;
    FilterPersistence.selectedAssignmentCategoryIds = {};
    FilterPersistence.selectedAssignmentLabelIds = {};

    final assignmentBloc = _MockAssignmentBloc();
    whenListen(
      assignmentBloc,
      Stream<AssignmentState>.empty(),
      initialState: AssignmentSlotsLoaded(
        [slot],
        stagedDeletionSlotKeys: stagedDeletionSlotKeys,
      ),
    );

    final eventBloc = _MockEventBloc();
    whenListen(
      eventBloc,
      Stream<EventState>.empty(),
      initialState: const EventInitial(),
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AssignmentBloc>.value(value: assignmentBloc),
          BlocProvider<EventBloc>.value(value: eventBloc),
        ],
        child: RepositoryProvider<AssignmentLabelRepository>.value(
          value: _FakeAssignmentLabelRepository(),
          child: const MaterialApp(home: AssignmentListScreen()),
        ),
      ),
    );

    // Settle the label StreamBuilder's first (async) emission.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a staged-deletion row shows the "יימחק בשמירה" badge',
      (tester) async {
    await pumpAssignmentListWith(
      tester,
      stagedDeletionSlotKeys: {'e1_medic_0'},
    );

    expect(find.text('יימחק בשמירה'), findsOneWidget);
  });

  testWidgets(
      'a clean row (no staged deletion) does not show the "יימחק בשמירה" badge',
      (tester) async {
    await pumpAssignmentListWith(
      tester,
      stagedDeletionSlotKeys: const {},
    );

    expect(find.text('יימחק בשמירה'), findsNothing);
  });
}
