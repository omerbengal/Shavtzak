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
import 'package:shavtzak/data/repositories/assignment_repository.dart';
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
    implements AssignmentBloc {
  /// Task 9: events the screen dispatched onto this mock bloc.
  ///
  /// bloc_test's `MockBloc` is backed by the `mocktail` package (not
  /// `mockito`, which the rest of this file uses for
  /// `_MockAssignmentRepository`) — the two libraries track calls in
  /// separate, unrelated ledgers, so `package:mockito`'s `verify`/`any`
  /// cannot observe calls to a mocktail-backed mock. Overriding `add` to
  /// record into a plain list sidesteps both libraries' matcher machinery
  /// (and the non-nullable-parameter `any`/`argThat` typing issue described
  /// in mockito's NULL_SAFETY_README) for this one simple assertion.
  final List<AssignmentEvent> addedEvents = [];

  @override
  void add(AssignmentEvent event) {
    addedEvents.add(event);
  }
}

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

/// Task 9: a bare Mockito `Mock` (no `@GenerateMocks` codegen needed, same
/// rationale as `_FakeAssignmentLabelRepository` above) so a swipe-to-delete
/// test can assert `verifyNever(repo.deleteAssignment(any))` — proving the
/// screen no longer writes to the repository directly and instead stages the
/// deletion through the (mocked) AssignmentBloc.
///
/// `deleteAssignment(String id)` takes a non-nullable parameter, so per
/// mockito's NULL_SAFETY_README ("Solution 2: manual mock implementation")
/// it must be overridden by hand — widening the parameter to nullable and
/// forwarding to `super.noSuchMethod` — for `any`/`verifyNever` to type-check
/// (a plain `extends Mock implements AssignmentRepository` with no override
/// fails to compile at the `any` call site: `any` is statically `Null`,
/// which isn't assignable to a non-nullable `String` parameter).
class _MockAssignmentRepository extends Mock implements AssignmentRepository {
  @override
  Future<void> deleteAssignment(String? id) => super.noSuchMethod(
        Invocation.method(#deleteAssignment, [id]),
        returnValue: Future<void>.value(),
      );
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

  /// Returns the mocked [AssignmentBloc] so callers can `verify(...)` events
  /// dispatched onto it (Task 9: swipe-to-delete must stage, not write).
  Future<_MockAssignmentBloc> pumpAssignmentListWith(
    WidgetTester tester, {
    required Set<String> stagedDeletionSlotKeys,
    AssignmentRepository? assignmentRepository,
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
        child: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AssignmentLabelRepository>.value(
              value: _FakeAssignmentLabelRepository(),
            ),
            // Task 9: wired even though the screen no longer reads it on the
            // swipe-delete path, so a regression that reintroduces a direct
            // `context.read<AssignmentRepository>()` call there would call
            // INTO this mock and be caught by verifyNever, instead of the
            // test just never noticing.
            RepositoryProvider<AssignmentRepository>.value(
              value: assignmentRepository ?? _MockAssignmentRepository(),
            ),
          ],
          child: const MaterialApp(home: AssignmentListScreen()),
        ),
      ),
    );

    // Settle the label StreamBuilder's first (async) emission.
    await tester.pump();
    await tester.pump();

    return assignmentBloc;
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

  // Task 9: swipe-delete on an in-quota row must STAGE the deletion (dispatch
  // StageSlotDeletion to the bloc) instead of writing to the repository
  // immediately, and must never let the Dismissible actually dismiss — the
  // row stays in the tree (the bloc's rebuilt state re-renders it striped;
  // see the two tests above for that overlay). If confirmDismiss ever
  // returned true / dismissal were allowed to proceed, the very next rebuild
  // with the row still present in AssignmentSlotsLoaded.slots would throw
  // Flutter's "A dismissed Dismissible widget is still part of the tree".
  testWidgets(
      'swiping a filled in-quota row stages a deletion via the bloc, '
      'writes nothing to the repository, and does not throw',
      (tester) async {
    final repo = _MockAssignmentRepository();
    final assignmentBloc = await pumpAssignmentListWith(
      tester,
      stagedDeletionSlotKeys: const {},
      assignmentRepository: repo,
    );

    // AssignmentListScreen wraps its whole build() in
    // Directionality(textDirection: TextDirection.rtl) (see
    // assignment_list_screen.dart's build method). Flutter's Dismissible
    // resolves DismissDirection from the ambient Directionality
    // (_extentToDirection in the Flutter SDK's dismissible.dart): under RTL,
    // a NEGATIVE drag extent (finger moving left) resolves to
    // DismissDirection.startToEnd — this row's notes-edit swipe, not delete
    // — and a POSITIVE extent (finger moving right) resolves to endToStart,
    // which is the delete swipe here. A positive offset is therefore
    // required to hit the delete branch; a negative one would silently
    // exercise the notes dialog instead and never stage anything.
    await tester.drag(
      find.byKey(const ValueKey('slot_e1_medic_0')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Filter for StageSlotDeletion specifically: mounting the real screen
    // also dispatches its own lifecycle events onto this mock bloc (e.g.
    // LoadAssignmentSlots, RehydrateStagedChanges), which are irrelevant here.
    final stagedDeletions =
        assignmentBloc.addedEvents.whereType<StageSlotDeletion>().toList();
    expect(stagedDeletions, hasLength(1));
    expect(stagedDeletions.single.slot.event.id, 'e1');
    expect(stagedDeletions.single.slot.role.key, 'medic');
    expect(stagedDeletions.single.slot.slotIndex, 0);
    verifyNever(repo.deleteAssignment(any));

    // Not actually dismissed: the same slot key still resolves to a widget
    // (MockBloc's fixed state never removes the slot; confirmDismiss must
    // have returned false rather than letting Dismissible remove the row).
    expect(find.byKey(const ValueKey('slot_e1_medic_0')), findsOneWidget);
  });
}
