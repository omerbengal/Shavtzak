// The hours step of filling or replacing a slot on the admin assignments
// screen, and the "פנוי בשעות של …" hint in the "בעלי מגבלות" list.
//
// Pumps the real AssignmentListScreen over a stubbed AssignmentBloc (the same
// harness as notes_dialog_custom_hours_test.dart): what the bloc stages is
// covered by stage_member_change_hours_test.dart, and the dialog's own
// behaviour by replacement_hours_dialog_test.dart. Here only when the step
// runs and what the screen dispatches are under test.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/core/utils/filter_persistence.dart';
import 'package:shavtzak/data/repositories/assignment_label_repository.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/data/repositories/team_repository.dart';
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
import 'package:shavtzak/presentation/screens/assignment/widgets/member_picker_field.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/replacement_hours_dialog.dart';

class _MockAssignmentBloc extends MockBloc<AssignmentEvent, AssignmentState>
    implements AssignmentBloc {
  /// Events the screen dispatched (see assignment_staged_delete_overlay_test.dart
  /// for why `add` is overridden instead of verified).
  final List<AssignmentEvent> addedEvents = [];

  /// What the bloc says the slot's effective assignment holds.
  WallInterval? slotHours;

  /// What the bloc says the incoming member holds on other roles.
  List<AssignmentSlot> incomingOtherSlots = const [];
  WallInterval? incomingHours;

  @override
  void add(AssignmentEvent event) {
    addedEvents.add(event);
  }

  @override
  WallInterval? effectiveCustomWindow(AssignmentSlot slot) => slotHours;

  @override
  List<AssignmentSlot> otherSlotsHeldBy(
          TeamMember member, AssignmentSlot slot) =>
      incomingOtherSlots;

  @override
  WallInterval? hoursHeldElsewhere(TeamMember member, AssignmentSlot slot) =>
      incomingHours;

  List<StageMemberChange> get staged =>
      addedEvents.whereType<StageMemberChange>().toList();
}

class _MockEventBloc extends MockBloc<EventEvent, EventState>
    implements EventBloc {}

class _FakeAssignmentLabelRepository extends Mock
    implements AssignmentLabelRepository {
  @override
  Stream<List<AssignmentLabel>> watchAssignmentLabels() =>
      Stream.value(const <AssignmentLabel>[]);
}

class _MockAssignmentRepository extends Mock implements AssignmentRepository {}

/// The "בעלי מגבלות" dialog reads the active members from here.
class _FakeTeamRepository extends Mock implements TeamRepository {
  _FakeTeamRepository(this.members);

  final List<TeamMember> members;

  @override
  Future<List<TeamMember>> getActiveTeamMembers() async => members;
}

void main() {
  final now = DateTime(2026, 10, 1);

  TeamMember memberNamed(
    String id,
    String name, {
    List<DateConstraint> constraints = const [],
  }) =>
      TeamMember(
        id: id,
        name: name,
        isActive: true,
        isPermanent: true,
        constraints: constraints,
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'unique-$id',
      );

  DateConstraint unavailable(DateTime day) => DateConstraint(
        id: 'c-${day.day}',
        startDate: day,
        constraintType: ConstraintType.unavailability,
      );

  // 27-28.10.2026, stretch 27.10 12:00 to 28.10 23:30.
  final event = Event(
    id: 'e1',
    name: 'כנס חורף',
    startDate: DateTime(2026, 10, 27),
    endDate: DateTime(2026, 10, 28),
    startTime: '19:00',
    endTime: '23:00',
    teamEndTime: '23:30',
    assemblyTime: '12:00',
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

  final dana = memberNamed('m1', 'דנה כהן');
  final yossi = memberNamed('m2', 'יוסי מזרחי');

  // Dana's hours: 27.10 14:00-23:00.
  final danaHours = WallInterval(
    DateTime.utc(2026, 10, 27, 14),
    DateTime.utc(2026, 10, 27, 23),
  );

  final danaAssignment = Assignment(
    id: 'a1',
    eventId: 'e1',
    teamMemberId: 'm1',
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    customStartAt: '2026-10-27T14:00',
    customEndAt: '2026-10-27T23:00',
    createdAt: now,
    updatedAt: now,
    teamMember: dana,
  );

  Future<_MockAssignmentBloc> pumpScreen(
    WidgetTester tester, {
    Assignment? occupant,
    WallInterval? slotHours,
    List<AssignmentSlot> incomingOtherSlots = const [],
    WallInterval? incomingHours,
    List<TeamMember> team = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    FilterPersistence.assignmentFilterIndex = 0;
    FilterPersistence.showPastEvents = false;
    FilterPersistence.selectedAssignmentCategoryIds = {};
    FilterPersistence.selectedAssignmentLabelIds = {};

    final slot = AssignmentSlot(
      event: event,
      role: role,
      slotIndex: 0,
      currentAssignment: occupant,
      availableMembers: [if (occupant != null) dana, yossi],
    );
    final assignmentBloc = _MockAssignmentBloc()
      ..slotHours = slotHours
      ..incomingOtherSlots = incomingOtherSlots
      ..incomingHours = incomingHours;
    whenListen(
      assignmentBloc,
      Stream<AssignmentState>.empty(),
      initialState: AssignmentSlotsLoaded([slot], membersLoaded: true),
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
              value: _FakeTeamRepository(team),
            ),
          ],
          child: const MaterialApp(home: AssignmentListScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return assignmentBloc;
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.byType(MemberPickerField));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  group('the hours step', () {
    testWidgets(
        'replacing an occupant who has hours asks, and stages the choice',
        (tester) async {
      final bloc = await pumpScreen(
        tester,
        occupant: danaAssignment,
        slotHours: danaHours,
      );

      await pick(tester, 'יוסי מזרחי');

      expect(find.byType(ReplacementHoursDialog), findsOneWidget);
      expect(find.text('⏰ לדנה היו שעות מותאמות'), findsOneWidget);
      expect(bloc.staged, isEmpty);

      await tester.tap(find.text('לשמור את השעות של דנה'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'אישור'));
      await tester.pumpAndSettle();

      final change = bloc.staged.single;
      expect(change.member, yossi);
      expect(change.slot.slotIndex, 0);
      expect(change.setsCustomHours, isTrue);
      expect(change.customStartAt, '2026-10-27T14:00');
      expect(change.customEndAt, '2026-10-27T23:00');
    });

    testWidgets('ביטול keeps the previous occupant: nothing is staged',
        (tester) async {
      final bloc = await pumpScreen(
        tester,
        occupant: danaAssignment,
        slotHours: danaHours,
      );

      await pick(tester, 'יוסי מזרחי');
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      expect(find.byType(ReplacementHoursDialog), findsNothing);
      expect(bloc.staged, isEmpty);
      expect(
        find.descendant(
            of: find.byType(MemberPickerField),
            matching: find.text('דנה כהן')),
        findsOneWidget,
      );
    });

    testWidgets('no hours anywhere: staged at once, without hours',
        (tester) async {
      final bloc = await pumpScreen(tester);

      await pick(tester, 'יוסי מזרחי');

      expect(find.byType(ReplacementHoursDialog), findsNothing);
      final change = bloc.staged.single;
      expect(change.member, yossi);
      expect(change.setsCustomHours, isFalse);
      expect(change.customStartAt, isNull);
    });

    testWidgets(
        'an incoming member with hours on another role is asked too, and the '
        'event\'s hours are staged as none', (tester) async {
      final otherRole = AssignmentSlot(
        event: event,
        role: role,
        slotIndex: 1,
        currentAssignment: null,
        availableMembers: const [],
      );
      final bloc = await pumpScreen(
        tester,
        incomingOtherSlots: [otherRole],
        incomingHours: WallInterval(
          DateTime.utc(2026, 10, 28, 8),
          DateTime.utc(2026, 10, 28, 12),
        ),
      );

      await pick(tester, 'יוסי מזרחי');

      expect(find.text('⏰ ליוסי יש שעות מותאמות באירוע'), findsOneWidget);
      expect(find.text('השעות יחולו על כל התפקידים של יוסי באירוע'),
          findsOneWidget);
      expect(find.text('השעות הקיימות של יוסי'), findsOneWidget);

      await tester.tap(find.text('שעות האירוע הרגילות'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'אישור'));
      await tester.pumpAndSettle();

      final change = bloc.staged.single;
      expect(change.setsCustomHours, isTrue);
      expect(change.customStartAt, isNull);
      expect(change.customEndAt, isNull);
    });
  });

  group('"בעלי מגבלות"', () {
    // Ron cannot work on 28.10 (free in dana's hours on 27.10); michal cannot
    // work on 27.10 (blocked in them too).
    final ron = memberNamed('m3', 'רון שלו',
        constraints: [unavailable(DateTime(2026, 10, 28))]);
    final michal = memberNamed('m4', 'מיכל אור',
        constraints: [unavailable(DateTime(2026, 10, 27))]);

    Future<void> openConstrained(WidgetTester tester) async {
      await tester.tap(find.byType(MemberPickerField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('בעלי מגבלות / לא זמינים'));
      await tester.pumpAndSettle();
    }

    Finder hintIn(String name) => find.descendant(
          of: find.widgetWithText(ListTile, name),
          matching: find.text('פנוי בשעות של דנה'),
        );

    testWidgets('marks who is free during the previous occupant\'s hours',
        (tester) async {
      await pumpScreen(
        tester,
        occupant: danaAssignment,
        slotHours: danaHours,
        team: [ron, michal],
      );

      await openConstrained(tester);

      expect(find.widgetWithText(ListTile, 'רון שלו'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'מיכל אור'), findsOneWidget);
      expect(hintIn('רון שלו'), findsOneWidget);
      expect(hintIn('מיכל אור'), findsNothing);
      final hint = tester.widget<Text>(hintIn('רון שלו'));
      expect(hint.style?.color, Colors.green.shade700);
      expect(hint.style?.fontSize, 12);
    });

    testWidgets('no hint when the slot has no hours', (tester) async {
      await pumpScreen(
        tester,
        occupant: danaAssignment.copyWith(
          customStartAt: () => null,
          customEndAt: () => null,
        ),
        team: [ron, michal],
      );

      await openConstrained(tester);

      expect(find.widgetWithText(ListTile, 'רון שלו'), findsOneWidget);
      expect(find.textContaining('פנוי בשעות של'), findsNothing);
    });

    testWidgets('"שבץ בכל זאת" runs the hours step too', (tester) async {
      final bloc = await pumpScreen(
        tester,
        occupant: danaAssignment,
        slotHours: danaHours,
        team: [ron, michal],
      );

      await openConstrained(tester);
      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'רון שלו'),
        matching: find.text('שבץ בכל זאת'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('⏰ לדנה היו שעות מותאמות'), findsOneWidget);
      await tester.tap(find.text('לשמור את השעות של דנה'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'אישור'));
      await tester.pumpAndSettle();

      final change = bloc.staged.single;
      expect(change.member, ron);
      expect(change.customStartAt, '2026-10-27T14:00');
    });
  });
}
