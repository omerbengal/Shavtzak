// Widget tests for the assignments screen's first-load spinner, and for what
// a slot nobody can take looks like once the grid is up.
//
// --- First-load spinner ---
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
//
// --- The picker of a slot with no available member ---
// Every capable member can be blocked (pending constraints block too), and the
// picker's two fixed actions, "שובצו כבר" and "בעלי מגבלות / לא זמינים", are
// the only way to reach a blocked member and "שבץ בכל זאת". The picker used to
// be disabled when the slot had no available, current or already-assigned
// member, which made exactly that case unreachable. It must stay enabled; the
// grey background alone says "no one available".

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/utils/filter_persistence.dart';
import 'package:shavtzak/data/repositories/assignment_label_repository.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/data/repositories/team_repository.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
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
import 'package:shavtzak/presentation/screens/assignment/widgets/member_picker_field.dart';

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

/// The "בעלי מגבלות / לא זמינים" dialog reads the active members through
/// `context.read<TeamRepository>()`; nobody is on the team here.
class _FakeTeamRepository extends Mock implements TeamRepository {
  @override
  Future<List<TeamMember>> getActiveTeamMembers() async => const [];
}

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
            RepositoryProvider<TeamRepository>.value(
              value: _FakeTeamRepository(),
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

  group('picker of a slot nobody can take', () {
    final picker = find.byType(MemberPickerField);

    Color pickerBackground(WidgetTester tester) {
      // What is painted, not just what was passed in.
      final box = tester
          .widgetList<Container>(
              find.descendant(of: picker, matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.color != null);
      return box.color!;
    }

    testWidgets(
        'stays enabled, so its actions are reachable, and keeps the grey '
        'background that says no one is available', (tester) async {
      await pumpScreenWith(
        tester,
        AssignmentSlotsLoaded([unavailableToEveryone], membersLoaded: true),
      );

      expect(picker, findsOneWidget);
      expect(tester.widget<MemberPickerField>(picker).enabled, isTrue);
      expect(pickerBackground(tester), Colors.grey.shade200);
    });

    testWidgets(
        'opens on tap and offers "שובצו כבר" and "בעלי מגבלות / לא זמינים", '
        'with the empty-list note instead of members', (tester) async {
      await pumpScreenWith(
        tester,
        AssignmentSlotsLoaded([unavailableToEveryone], membersLoaded: true),
      );

      await tester.tap(picker);
      await tester.pumpAndSettle();

      expect(find.text('אין חברי צוות זמינים'), findsOneWidget);
      expect(find.text('שובצו כבר'), findsOneWidget);
      expect(find.text('בעלי מגבלות / לא זמינים'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tapping "בעלי מגבלות / לא זמינים" opens its dialog (an empty-state '
        'message when nobody is listed)', (tester) async {
      await pumpScreenWith(
        tester,
        AssignmentSlotsLoaded([unavailableToEveryone], membersLoaded: true),
      );

      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('בעלי מגבלות / לא זמינים'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('בעלי מגבלות / לא זמינים - "אירוע קיץ"'), findsOneWidget);
      expect(
        find.text('אין אנשים עם מגבלות או חוסר זמינות לתפקיד חובש באירוע זה'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('control: a slot with an available member is enabled and white',
        (tester) async {
      final someone = TeamMember(
        id: 'm1',
        name: 'יוסי כהן',
        isActive: true,
        constraints: const [],
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'unique-m1',
      );
      await pumpScreenWith(
        tester,
        AssignmentSlotsLoaded([
          AssignmentSlot(
            event: event,
            role: role,
            slotIndex: 0,
            currentAssignment: null,
            availableMembers: [someone],
          ),
        ], membersLoaded: true),
      );

      expect(tester.widget<MemberPickerField>(picker).enabled, isTrue);
      expect(pickerBackground(tester), Colors.white);
    });
  });
}
