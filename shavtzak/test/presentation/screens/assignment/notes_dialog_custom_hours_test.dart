// The notes dialog of the admin assignments screen and the assignment row, as
// far as custom hours go: the switch, the fields, the warning about
// constraints, what is staged on שמור, and the line the row shows.
//
// Pumps the real AssignmentListScreen over a stubbed AssignmentBloc (the same
// harness as assignment_staged_delete_overlay_test.dart): the bloc's own
// staging is covered by stage_custom_hours_test.dart, here only what the
// dialog sends to it is under test.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
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
import 'package:shavtzak/presentation/widgets/custom_hours_fields.dart';

class _MockAssignmentBloc extends MockBloc<AssignmentEvent, AssignmentState>
    implements AssignmentBloc {
  /// Events the screen dispatched (see assignment_staged_delete_overlay_test.dart
  /// for why `add` is overridden instead of verified).
  final List<AssignmentEvent> addedEvents = [];

  /// What the dialog is told about the member's other roles in the event.
  List<AssignmentSlot> otherSlots = const [];

  @override
  void add(AssignmentEvent event) {
    addedEvents.add(event);
  }

  @override
  List<AssignmentSlot> otherSlotsOfSameMember(AssignmentSlot slot) =>
      otherSlots;

  List<StageNotesChange> get staged =>
      addedEvents.whereType<StageNotesChange>().toList();
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

void main() {
  final now = DateTime(2026, 7, 1);

  TeamMember memberWith({List<DateConstraint> constraints = const []}) =>
      TeamMember(
        id: 'm1',
        name: 'יוסי כהן',
        isActive: true,
        isPermanent: true,
        constraints: constraints,
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'unique-m1',
      );

  // One day, 1.7.2026: assembly 17:00 to team end 22:00.
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

  Assignment assignmentFor(
    TeamMember member, {
    String notes = '',
    String? customStartAt,
    String? customEndAt,
  }) =>
      Assignment(
        id: 'a1',
        eventId: 'e1',
        teamMemberId: 'm1',
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: notes,
        customStartAt: customStartAt,
        customEndAt: customEndAt,
        createdAt: now,
        updatedAt: now,
        teamMember: member,
      );

  Future<_MockAssignmentBloc> pumpScreen(
    WidgetTester tester, {
    required Assignment assignment,
    List<AssignmentSlot> otherSlots = const [],
  }) async {
    FilterPersistence.assignmentFilterIndex = 0;
    FilterPersistence.showPastEvents = false;
    FilterPersistence.selectedAssignmentCategoryIds = {};
    FilterPersistence.selectedAssignmentLabelIds = {};

    final slot = AssignmentSlot(
      event: event,
      role: role,
      slotIndex: 0,
      currentAssignment: assignment,
      availableMembers: [assignment.teamMember!],
    );
    final assignmentBloc = _MockAssignmentBloc()..otherSlots = otherSlots;
    whenListen(
      assignmentBloc,
      Stream<AssignmentState>.empty(),
      initialState: AssignmentSlotsLoaded([slot]),
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
    return assignmentBloc;
  }

  Future<void> openNotesDialog(WidgetTester tester) async {
    // RTL: a negative drag is the notes swipe (see the delete-overlay test).
    await tester.drag(
      find.byKey(const ValueKey('slot_e1_medic_0')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('הערות לשיבוץ'), findsOneWidget);
  }

  Finder hoursTimeField(int index) => find
      .descendant(
        of: find.byType(CustomHoursFields),
        matching: find.byType(TextFormField),
      )
      .at(index);

  Future<void> tapSave(WidgetTester tester) async {
    // The screen has its own save bar; this is the dialog's button.
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'שמור'),
    ));
    await tester.pumpAndSettle();
  }

  bool switchValue(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value;

  group('the switch and the fields', () {
    testWidgets('an assignment without hours opens with the switch off',
        (tester) async {
      await pumpScreen(tester, assignment: assignmentFor(memberWith()));
      await openNotesDialog(tester);

      expect(find.text('שעות מותאמות ליוסי'), findsOneWidget);
      expect(switchValue(tester), isFalse);
      expect(find.byType(CustomHoursFields), findsNothing);
      expect(find.textContaining('השעות יחולו על כל התפקידים'), findsNothing);
    });

    testWidgets('switching on shows the fields opened on the event hours',
        (tester) async {
      await pumpScreen(tester, assignment: assignmentFor(memberWith()));
      await openNotesDialog(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(switchValue(tester), isTrue);
      expect(find.byType(CustomHoursFields), findsOneWidget);
      expect(tester.widget<TextFormField>(hoursTimeField(0)).controller!.text,
          '17:00');
      expect(tester.widget<TextFormField>(hoursTimeField(1)).controller!.text,
          '22:00');
      expect(find.text('שעות האירוע: 1.7 17:00–22:00'), findsOneWidget);
    });

    testWidgets('an assignment with hours opens with them filled in',
        (tester) async {
      await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(),
          customStartAt: '2026-07-01T18:30',
          customEndAt: '2026-07-01T21:00',
        ),
      );
      await openNotesDialog(tester);

      expect(switchValue(tester), isTrue);
      expect(tester.widget<TextFormField>(hoursTimeField(0)).controller!.text,
          '18:30');
      expect(tester.widget<TextFormField>(hoursTimeField(1)).controller!.text,
          '21:00');
    });

    testWidgets('hours that cannot be read count as none: switch off',
        (tester) async {
      await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(),
          customStartAt: 'not a moment',
          customEndAt: '2026-07-01T21:00',
        ),
      );
      await openNotesDialog(tester);

      expect(switchValue(tester), isFalse);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(hoursTimeField(0)).controller!.text,
          '17:00');
    });

    testWidgets('a member holding other roles gets the all-roles note',
        (tester) async {
      final member = memberWith();
      final other = AssignmentSlot(
        event: event,
        role: role,
        slotIndex: 1,
        currentAssignment: assignmentFor(member),
        availableMembers: const [],
      );
      await pumpScreen(
        tester,
        assignment: assignmentFor(member),
        otherSlots: [other],
      );
      await openNotesDialog(tester);

      expect(find.text('השעות יחולו על כל התפקידים של יוסי באירוע'),
          findsOneWidget);
    });
  });

  group('שמור', () {
    testWidgets('with the switch off stages the notes and sends no hours',
        (tester) async {
      final bloc =
          await pumpScreen(tester, assignment: assignmentFor(memberWith()));
      await openNotesDialog(tester);

      await tapSave(tester);

      final staged = bloc.staged.single;
      expect(staged.customStartAt, isNull);
      expect(staged.customEndAt, isNull);
      // The dialog always decides the hours: null/null clears them.
      expect(staged.setsCustomHours, isTrue);
      expect(find.text('הערות לשיבוץ'), findsNothing);
    });

    testWidgets('with the switch on stages the hours as wall moments',
        (tester) async {
      final bloc =
          await pumpScreen(tester, assignment: assignmentFor(memberWith()));
      await openNotesDialog(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tester.enterText(hoursTimeField(0), '1830');
      await tester.enterText(hoursTimeField(1), '2100');
      await tester.pump();
      await tapSave(tester);

      final staged = bloc.staged.single;
      expect(staged.customStartAt, '2026-07-01T18:30');
      expect(staged.customEndAt, '2026-07-01T21:00');
      expect(staged.setsCustomHours, isTrue);
    });

    testWidgets('switching the hours off sends both null', (tester) async {
      final bloc = await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(),
          customStartAt: '2026-07-01T18:30',
          customEndAt: '2026-07-01T21:00',
        ),
      );
      await openNotesDialog(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.byType(CustomHoursFields), findsNothing);
      await tapSave(tester);

      final staged = bloc.staged.single;
      expect(staged.customStartAt, isNull);
      expect(staged.customEndAt, isNull);
      expect(staged.setsCustomHours, isTrue);
    });

    testWidgets('a departure before the arrival keeps the dialog open',
        (tester) async {
      final bloc =
          await pumpScreen(tester, assignment: assignmentFor(memberWith()));
      await openNotesDialog(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tester.enterText(hoursTimeField(1), '1600');
      await tester.pump();
      await tapSave(tester);

      expect(bloc.staged, isEmpty);
      expect(find.text('הערות לשיבוץ'), findsOneWidget);
      expect(find.text('העזיבה חייבת להיות אחרי ההגעה'), findsOneWidget);
    });

    testWidgets('a half-typed time keeps the dialog open', (tester) async {
      final bloc =
          await pumpScreen(tester, assignment: assignmentFor(memberWith()));
      await openNotesDialog(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tester.enterText(hoursTimeField(1), '21:');
      await tester.pump();
      await tapSave(tester);

      expect(bloc.staged, isEmpty);
      expect(find.text('הערות לשיבוץ'), findsOneWidget);
    });
  });

  group('constraints inside the hours', () {
    DateConstraint dayConstraint(ConstraintStatus status) => DateConstraint(
          id: 'c1',
          startDate: DateTime(2026, 7, 1),
          status: status,
          constraintType: ConstraintType.unavailability,
        );

    testWidgets(
        'an approved one asks first; ביטול keeps the dialog open, '
        'שמור בכל זאת stages the hours', (tester) async {
      final bloc = await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(constraints: [dayConstraint(ConstraintStatus.approved)]),
        ),
      );
      await openNotesDialog(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tapSave(tester);

      expect(find.text('⚠️ התנגשות עם אילוצים'), findsOneWidget);
      expect(find.text('⚠️ מתנגש עם אילוץ מאושר של יוסי: 1.7 (כל היום)'),
          findsOneWidget);
      expect(bloc.staged, isEmpty);

      await tester.tap(find.text('ביטול').last);
      await tester.pumpAndSettle();
      expect(find.text('⚠️ התנגשות עם אילוצים'), findsNothing);
      expect(find.text('הערות לשיבוץ'), findsOneWidget);
      expect(bloc.staged, isEmpty);

      await tapSave(tester);
      await tester.tap(find.text('שמור בכל זאת'));
      await tester.pumpAndSettle();

      expect(find.text('הערות לשיבוץ'), findsNothing);
      final staged = bloc.staged.single;
      expect(staged.customStartAt, '2026-07-01T17:00');
      expect(staged.customEndAt, '2026-07-01T22:00');
    });

    testWidgets('a pending one is named as pending', (tester) async {
      await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(constraints: [dayConstraint(ConstraintStatus.pending)]),
        ),
      );
      await openNotesDialog(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tapSave(tester);

      expect(
          find.text('⚠️ מתנגש עם אילוץ ממתין לאישור של יוסי: 1.7 (כל היום)'),
          findsOneWidget);
    });

    testWidgets('with the hours off there is nothing to ask', (tester) async {
      final bloc = await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(constraints: [dayConstraint(ConstraintStatus.approved)]),
        ),
      );
      await openNotesDialog(tester);

      await tapSave(tester);

      expect(find.text('⚠️ התנגשות עם אילוצים'), findsNothing);
      expect(bloc.staged, hasLength(1));
    });

    testWidgets('hours that miss the constraint are not asked about',
        (tester) async {
      final bloc = await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(
            constraints: [
              DateConstraint(
                id: 'c2',
                startDate: DateTime(2026, 7, 1),
                startTime: '06:00',
                endTime: '08:00',
                constraintType: ConstraintType.unavailability,
              ),
            ],
          ),
        ),
      );
      await openNotesDialog(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tapSave(tester);

      expect(find.text('⚠️ התנגשות עם אילוצים'), findsNothing);
      expect(bloc.staged, hasLength(1));
    });
  });

  group('the row', () {
    testWidgets('shows the hours as the first line, in the specified style',
        (tester) async {
      await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(),
          notes: 'מגיע מהעבודה',
          customStartAt: '2026-07-01T18:30',
          customEndAt: '2026-07-01T21:00',
        ),
      );

      final line = find.text('שעות מותאמות: 1.7 18:30–21:00');
      expect(line, findsOneWidget);
      final style = tester.widget<Text>(line).style!;
      expect(style.fontSize, 11);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.color, Colors.indigo.shade800);
      // Above the notes card.
      expect(tester.getTopLeft(line).dy,
          lessThan(tester.getTopLeft(find.textContaining('מגיע מהעבודה')).dy));
    });

    testWidgets('hours alone are enough to show the line', (tester) async {
      await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(),
          customStartAt: '2026-07-01T18:30',
          customEndAt: '2026-07-02T02:00',
        ),
      );

      expect(find.text('שעות מותאמות: 1.7 18:30 – 2.7 02:00'),
          findsOneWidget);
    });

    testWidgets('no hours, no line', (tester) async {
      await pumpScreen(
        tester,
        assignment: assignmentFor(memberWith(), notes: 'הערה'),
      );

      expect(find.textContaining('שעות מותאמות'), findsNothing);
    });

    testWidgets('hours that cannot be read show no line', (tester) async {
      await pumpScreen(
        tester,
        assignment: assignmentFor(
          memberWith(),
          customStartAt: '2026-07-01T21:00',
          customEndAt: '2026-07-01T18:30',
        ),
      );

      expect(find.textContaining('שעות מותאמות'), findsNothing);
    });
  });
}
