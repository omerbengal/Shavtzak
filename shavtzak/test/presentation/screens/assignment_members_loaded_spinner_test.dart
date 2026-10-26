// Widget test for the assignments screen's first-load spinner.
//
// The screen used to guess "the team members haven't loaded yet" from "no slot
// has an available member". That is also true when members HAVE loaded and
// every one of them is unavailable for every slot, and then nothing ever
// changed the state again, so the spinner stayed up forever. The screen now
// waits on `AssignmentSlotsLoaded.membersLoaded` instead.
//
// Harness: same as assignment_staged_delete_overlay_test.dart — the real
// AssignmentListScreen driven by a stubbed AssignmentBloc state (the builder
// is private to the screen's library, so this is the only way in).

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/utils/filter_persistence.dart';
import 'package:shavtzak/data/repositories/assignment_label_repository.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/domain/entities/assignment_label.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
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

class _FakeAssignmentLabelRepository extends Mock
    implements AssignmentLabelRepository {
  @override
  Stream<List<AssignmentLabel>> watchAssignmentLabels() =>
      Stream.value(const <AssignmentLabel>[]);
}

class _MockAssignmentRepository extends Mock implements AssignmentRepository {}

void main() {
  final now = DateTime(2026, 7, 1);

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

  // An unfilled slot nobody can take: every member is unavailable for it.
  final unavailableToEveryone = AssignmentSlot(
    event: event,
    role: role,
    slotIndex: 0,
    currentAssignment: null,
    availableMembers: const [],
  );

  Future<void> pumpScreenWith(
    WidgetTester tester,
    AssignmentSlotsLoaded initialState,
  ) async {
    FilterPersistence.assignmentFilterIndex = 0;
    FilterPersistence.showPastEvents = false;
    FilterPersistence.selectedAssignmentCategoryIds = {};
    FilterPersistence.selectedAssignmentLabelIds = {};

    final assignmentBloc = _MockAssignmentBloc();
    whenListen(
      assignmentBloc,
      Stream<AssignmentState>.empty(),
      initialState: initialState,
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
            RepositoryProvider<AssignmentRepository>.value(
              value: _MockAssignmentRepository(),
            ),
          ],
          child: const MaterialApp(home: AssignmentListScreen()),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
  }

  final slotRow = find.byKey(const ValueKey('slot_e1_medic_0'));

  testWidgets(
      'members loaded but nobody available for any slot: the grid shows, '
      'not the spinner', (tester) async {
    await pumpScreenWith(
      tester,
      AssignmentSlotsLoaded([unavailableToEveryone], membersLoaded: true),
    );

    expect(slotRow, findsOneWidget,
        reason: 'the rows must render even though no slot has an available '
            'member');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'members not loaded yet: the spinner shows and the grid does not',
      (tester) async {
    await pumpScreenWith(
      tester,
      AssignmentSlotsLoaded([unavailableToEveryone], membersLoaded: false),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(slotRow, findsNothing);
  });
}
