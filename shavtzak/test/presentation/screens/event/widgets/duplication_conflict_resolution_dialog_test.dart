import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/event/duplication_availability.dart';
import 'package:shavtzak/presentation/bloc/event/event_state.dart';
import 'package:shavtzak/presentation/bloc/role/role_bloc.dart';
import 'package:shavtzak/presentation/bloc/role/role_event.dart';
import 'package:shavtzak/presentation/bloc/role/role_state.dart';
import 'package:shavtzak/presentation/screens/event/widgets/duplication_conflict_resolution_dialog.dart';

class _MockRoleBloc extends MockBloc<RoleEvent, RoleState>
    implements RoleBloc {}

/// A row the backend would refuse even with the bypass (canKeep false) shows
/// its reason and cannot be unticked; a flagged row that can be kept still can.
void main() {
  final now = DateTime(2026, 10, 1);
  final day = DateTime(2026, 11, 10);
  final original = _event('original', now, day);
  final proposed = _event('proposed', now, day);

  late _MockRoleBloc roleBloc;
  DuplicationDialogResult? result;
  var closed = false;

  final locked = AssignmentDuplicationInfo(
    assignment: _assignment('a-locked', 'חבר נעול', now),
    hasAvailabilityConflict: true,
    availabilityReason: 'לא פעיל/ה',
    isInOverQuotaRole: false,
    canKeep: false,
  );
  final keepable = AssignmentDuplicationInfo(
    assignment: _assignment('a-keep', 'חבר גמיש', now),
    hasAvailabilityConflict: true,
    availabilityReason: 'אילוץ ממתין לאישור: 10.11 (כל היום)\n'
        'אילוץ מאושר: 10.11 19:00–21:00',
    isInOverQuotaRole: false,
  );

  setUp(() {
    roleBloc = _MockRoleBloc();
    whenListen(roleBloc, const Stream<RoleState>.empty(),
        initialState: const RoleInitial());
    result = null;
    closed = false;
  });

  Future<void> openDialog(
    WidgetTester tester, {
    List<AssignmentDuplicationInfo>? infos,
    int quota = 2,
  }) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = DuplicationRequiresConflictResolution(
      originalEvent: original,
      proposedEvent: proposed,
      assignmentInfos: infos ?? [locked, keepable],
      roleQuotas: {'medic': quota},
    );

    // The provider sits above MaterialApp: the dialog is a route, not a
    // descendant of the button.
    await tester.pumpWidget(
      BlocProvider<RoleBloc>.value(
        value: roleBloc,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await DuplicationConflictResolutionDialog.show(
                      context, state);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('both rows start marked for removal and show their reasons',
      (tester) async {
    await openDialog(tester);

    expect(find.text('חבר נעול'), findsOneWidget);
    expect(find.text('חבר גמיש'), findsOneWidget);
    expect(find.text('לא פעיל/ה'), findsOneWidget);
    expect(find.textContaining('אילוץ ממתין לאישור: 10.11 (כל היום)'),
        findsOneWidget);
    expect(find.text('יוסר'), findsNWidgets(2));
    expect(find.text('2 יוסרו'), findsOneWidget);
  });

  testWidgets('a keepable row can be unticked and ticked again',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('חבר גמיש'));
    await tester.pump();
    expect(find.text('יוסר'), findsOneWidget);
    expect(find.text('1 ישוכפלו'), findsOneWidget);

    await tester.tap(find.text('חבר גמיש'));
    await tester.pump();
    expect(find.text('יוסר'), findsNWidgets(2));
  });

  testWidgets('a locked row ignores taps and stays marked for removal',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('חבר נעול'));
    await tester.pump();

    expect(find.text('יוסר'), findsNWidgets(2));
    expect(find.text('2 יוסרו'), findsOneWidget);
  });

  testWidgets('confirming returns the locked row even after the keepable one '
      'was kept', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('חבר גמיש'));
    await tester.tap(find.text('חבר נעול'));
    await tester.pump();
    await tester.tap(find.text('צור אירוע משוכפל'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result?.excluded, {'a-locked'});
    expect(result?.hoursDropped, isEmpty);
  });

  testWidgets('cancelling returns nothing', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('with no hours to copy there is no hours section',
      (tester) async {
    await openDialog(tester);

    expect(find.textContaining('שעות מותאמות'), findsNothing);
    expect(find.text('סמן הכל'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  group('custom hours', () {
    // Dana: 1.12 14:00-20:00 moves to 8.12; Avi: a night across two days.
    final dana = _hoursInfo('h-dana', 'דנה כהן');
    final avi = _hoursInfo('h-avi', 'אבי לוי',
        start: '2026-12-01T20:00', end: '2026-12-03T23:30');

    List<bool> ticks(WidgetTester tester) => tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .map((box) => box.value == true)
        .toList();

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.text('צור אירוע משוכפל'));
      await tester.pumpAndSettle();
    }

    testWidgets('the section lists each member once, ticked, with the old '
        'hours struck through and the moved ones under them', (tester) async {
      await openDialog(tester, infos: [dana, avi]);

      expect(find.text('⏰ שעות מותאמות (2)'), findsOneWidget);
      expect(find.text('סמן הכל'), findsOneWidget);
      expect(find.text('דנה כהן · medic'), findsOneWidget);
      expect(find.text('אבי לוי · medic'), findsOneWidget);
      expect(ticks(tester), [true, true]);

      final old = tester.widget<Text>(find.text('1.12 14:00–20:00'));
      expect(old.style?.decoration, TextDecoration.lineThrough);
      expect(find.text('← 8.12 14:00–20:00'), findsOneWidget);
      final oldNight =
          tester.widget<Text>(find.text('1.12 20:00 – 3.12 23:30'));
      expect(oldNight.style?.decoration, TextDecoration.lineThrough);
      expect(find.text('← 8.12 20:00 – 10.12 23:30'), findsOneWidget);
      // Nothing is removed and nothing is dropped until the admin says so.
      expect(find.text('יוסר'), findsNothing);
    });

    testWidgets('confirming with every row ticked drops no hours',
        (tester) async {
      await openDialog(tester, infos: [dana, avi]);

      await confirm(tester);

      expect(closed, isTrue);
      expect(result?.excluded, isEmpty);
      expect(result?.hoursDropped, isEmpty);
    });

    testWidgets('unticking a member puts their id in hoursDropped and says '
        "they get the event's hours", (tester) async {
      await openDialog(tester, infos: [dana, avi]);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(ticks(tester), [false, true]);
      expect(find.text('לא יועתק — יקבל/תקבל את שעות האירוע'),
          findsOneWidget);
      // The moved hours of the unticked member are no longer promised.
      expect(find.text('← 8.12 14:00–20:00'), findsNothing);
      expect(find.text('← 8.12 20:00 – 10.12 23:30'), findsOneWidget);

      await confirm(tester);

      expect(result?.hoursDropped, {'h-dana'});
      expect(result?.excluded, isEmpty);
    });

    testWidgets('tapping a row anywhere toggles it', (tester) async {
      await openDialog(tester, infos: [dana]);

      await tester.tap(find.text('דנה כהן · medic'));
      await tester.pump();
      expect(ticks(tester), [false]);

      await tester.tap(find.text('דנה כהן · medic'));
      await tester.pump();
      expect(ticks(tester), [true]);
    });

    testWidgets('"סמן הכל" ticks every row again', (tester) async {
      await openDialog(tester, infos: [dana, avi]);
      await tester.tap(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      expect(ticks(tester), [false, false]);

      await tester.tap(find.text('סמן הכל'));
      await tester.pump();
      expect(ticks(tester), [true, true]);

      await confirm(tester);
      expect(result?.hoursDropped, isEmpty);
    });

    testWidgets('a member with two assignments is one row, and unticking '
        'drops both', (tester) async {
      final first = _hoursInfo('h-1', 'דנה כהן', memberId: 'dana');
      final second = _hoursInfo('h-2', 'דנה כהן', memberId: 'dana');
      await openDialog(tester, infos: [first, second]);

      expect(find.text('⏰ שעות מותאמות (1)'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await confirm(tester);

      expect(result?.hoursDropped, {'h-1', 'h-2'});
    });

    testWidgets('a member flagged allowMultipleAssignments has a row for each '
        'assignment, and unticking drops only that one', (tester) async {
      final first = _hoursInfo('h-1', 'מילואים',
          memberId: 'pool', allowMultipleAssignments: true);
      final second = _hoursInfo('h-2', 'מילואים',
          memberId: 'pool',
          allowMultipleAssignments: true,
          start: '2026-12-01T09:00',
          end: '2026-12-01T12:00');
      await openDialog(tester, infos: [first, second]);

      expect(find.text('⏰ שעות מותאמות (2)'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await confirm(tester);

      expect(result?.hoursDropped, {'h-2'});
    });

    testWidgets('a member marked for removal in the availability section has '
        'no hours row', (tester) async {
      final flagged = _hoursInfo('h-flagged', 'חבר גמיש',
          flaggedReason: 'אילוץ מאושר: 8.12 (כל היום)');
      await openDialog(tester, infos: [flagged, avi]);

      // Marked for removal from the start: only Avi's hours are listed.
      expect(find.text('⏰ שעות מותאמות (1)'), findsOneWidget);
      expect(find.text('חבר גמיש · medic'), findsNothing);

      // Keeping the member brings their hours row back...
      await tester.tap(find.text('חבר גמיש'));
      await tester.pump();
      expect(find.text('⏰ שעות מותאמות (2)'), findsOneWidget);
      expect(find.text('חבר גמיש · medic'), findsOneWidget);

      // ...and removing them again takes it away.
      await tester.tap(find.text('חבר גמיש'));
      await tester.pump();
      expect(find.text('⏰ שעות מותאמות (1)'), findsOneWidget);
      expect(find.text('חבר גמיש · medic'), findsNothing);
    });

    testWidgets('when every member with hours is marked for removal the '
        'section goes away', (tester) async {
      final flagged = _hoursInfo('h-flagged', 'חבר גמיש',
          flaggedReason: 'אילוץ מאושר: 8.12 (כל היום)');
      await openDialog(tester, infos: [flagged]);

      expect(find.textContaining('שעות מותאמות'), findsNothing);
      expect(find.text('סמן הכל'), findsNothing);
    });

    testWidgets('unticking a member the new hours flag puts them in the '
        'conflicts list kept, with their hours row still there',
        (tester) async {
      // Free during the moved hours, busy 21:00-22:00 of the new event.
      final evening = _hoursInfo('h-evening', 'דנה כהן',
          eventHoursReason: 'אילוץ מאושר: 8.12 21:00–22:00');
      await openDialog(tester, infos: [evening]);
      expect(find.text('מעולה! כל חברי הצוות זמינים'), findsOneWidget);
      expect(find.text('יוסר'), findsNothing);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      // A conflict card now, but nobody was removed: the admin decides.
      expect(find.text('אילוץ מאושר: 8.12 21:00–22:00'), findsOneWidget);
      expect(find.text('מעולה! כל חברי הצוות זמינים'), findsNothing);
      expect(find.text('יוסר'), findsNothing);
      expect(find.text('⏰ שעות מותאמות (1)'), findsOneWidget);
      expect(find.text('לא יועתק — יקבל/תקבל את שעות האירוע'), findsOneWidget);

      await confirm(tester);
      expect(result?.excluded, isEmpty);
      expect(result?.hoursDropped, {'h-evening'});
    });

    testWidgets('the admin can then remove the flagged member from the card, '
        'which takes their hours row away', (tester) async {
      final evening = _hoursInfo('h-evening', 'דנה כהן',
          eventHoursReason: 'אילוץ מאושר: 8.12 21:00–22:00');
      await openDialog(tester, infos: [evening]);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      await tester.tap(find.text('דנה כהן'));
      await tester.pump();

      expect(find.text('יוסר'), findsOneWidget);
      expect(find.textContaining('שעות מותאמות'), findsNothing);

      await confirm(tester);
      expect(result?.excluded, {'h-evening'});
      expect(result?.hoursDropped, {'h-evening'});
    });

    testWidgets('ticking the hours back clears the conflict that unticking '
        'caused', (tester) async {
      final evening = _hoursInfo('h-evening', 'דנה כהן',
          eventHoursReason: 'אילוץ מאושר: 8.12 21:00–22:00');
      await openDialog(tester, infos: [evening]);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text('אילוץ מאושר: 8.12 21:00–22:00'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(find.text('אילוץ מאושר: 8.12 21:00–22:00'), findsNothing);
      expect(find.text('מעולה! כל חברי הצוות זמינים'), findsOneWidget);
      expect(find.text('יוסר'), findsNothing);

      await confirm(tester);
      expect(result?.excluded, isEmpty);
      expect(result?.hoursDropped, isEmpty);
    });

    testWidgets('ticking the hours back lets go of a removal made in the '
        'conflicts list once the member no longer shows there',
        (tester) async {
      // Two copies of one member, both busy 21:00-22:00 of the new event.
      final first = _hoursInfo('h-1', 'דנה כהן',
          memberId: 'dana',
          eventHoursReason: 'אילוץ מאושר: 8.12 21:00–22:00');
      final second = _hoursInfo('h-2', 'דנה כהן',
          memberId: 'dana',
          eventHoursReason: 'אילוץ מאושר: 8.12 21:00–22:00');
      await openDialog(tester, infos: [first, second]);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text('אילוץ מאושר: 8.12 21:00–22:00'), findsNWidgets(2));
      expect(find.text('יוסר'), findsNothing);

      // Remove the first copy in the conflicts list; the second keeps the
      // hours row on show.
      await tester.tap(find.text('דנה כהן').first);
      await tester.pump();
      expect(find.text('יוסר'), findsOneWidget);
      expect(find.text('⏰ שעות מותאמות (1)'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      // Both copies are clear again; the removal nobody can see is gone.
      expect(find.text('מעולה! כל חברי הצוות זמינים'), findsOneWidget);
      expect(find.text('יוסר'), findsNothing);

      await confirm(tester);
      expect(result?.excluded, isEmpty);
      expect(result?.hoursDropped, isEmpty);
    });

    testWidgets('a removal made in the quota section survives unticking and '
        'ticking the hours', (tester) async {
      // Three copies in a role with room for two: one over quota.
      final first = _hoursInfo('h-1', 'דנה כהן',
          memberId: 'dana',
          eventHoursReason: 'אילוץ מאושר: 8.12 21:00–22:00');
      final second = _hoursInfo('h-2', 'דנה כהן',
          memberId: 'dana',
          eventHoursReason: 'אילוץ מאושר: 8.12 21:00–22:00');
      final third = AssignmentDuplicationInfo(
        assignment: _assignment('plain', 'חבר שלישי', DateTime(2026, 10, 1)),
        hasAvailabilityConflict: false,
        isInOverQuotaRole: true,
      );
      await openDialog(tester, infos: [first, second, third]);

      // Open the quota card and remove the first copy there.
      await tester.tap(find.text('3 שיבוצים • 2 מכסה'));
      await tester.pump();
      await tester.tap(find.text('דנה כהן').first);
      await tester.pump();
      expect(find.text('יוסר'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      // The copies are clear again, and the quota removal is still there.
      expect(find.text('מעולה! כל חברי הצוות זמינים'), findsOneWidget);
      expect(find.text('יוסר'), findsOneWidget);

      await confirm(tester);
      expect(result?.excluded, {'h-1'});
      expect(result?.hoursDropped, isEmpty);
    });

    testWidgets('"סמן הכל" leaves the hours of a member marked for removal '
        'as they were', (tester) async {
      final dana = _hoursInfo('h-dana', 'דנה כהן',
          eventHoursReason: 'אילוץ מאושר: 8.12 21:00–22:00');
      final avi = _hoursInfo('h-avi', 'אבי לוי',
          eventHoursReason: 'אילוץ מאושר: 8.12 21:00–22:00');
      await openDialog(tester, infos: [dana, avi]);
      await tester.tap(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();

      // Avi is removed in the conflicts list, so his hours row goes.
      await tester.tap(find.text('אבי לוי'));
      await tester.pump();
      expect(find.text('⏰ שעות מותאמות (1)'), findsOneWidget);

      await tester.tap(find.text('סמן הכל'));
      await tester.pump();

      // Dana is ticked and leaves the conflicts list; Avi, out of sight,
      // stays as he was: still unticked, still in the list.
      expect(find.text('אילוץ מאושר: 8.12 21:00–22:00'), findsOneWidget);
      expect(find.text('אבי לוי'), findsOneWidget);
      expect(find.text('יוסר'), findsOneWidget);

      // Bringing Avi back shows his row unticked.
      await tester.tap(find.text('אבי לוי'));
      await tester.pump();
      expect(find.text('⏰ שעות מותאמות (2)'), findsOneWidget);
      expect(find.text('לא יועתק — יקבל/תקבל את שעות האירוע'), findsOneWidget);

      await confirm(tester);
      expect(result?.excluded, isEmpty);
      expect(result?.hoursDropped, {'h-avi'});
    });

    testWidgets('unticking releases a member the moved hours had flagged, '
        'when the event hours are free', (tester) async {
      final morning = _hoursInfo('h-morning', 'דנה כהן',
          flaggedReason: 'אילוץ מאושר: 8.12 08:00–10:00');
      await openDialog(tester, infos: [morning]);
      // Flagged by the moved hours, so marked for removal.
      expect(find.text('אילוץ מאושר: 8.12 08:00–10:00'), findsOneWidget);
      expect(find.text('יוסר'), findsOneWidget);

      // Keep the member, then give them the event's hours instead.
      await tester.tap(find.text('דנה כהן'));
      await tester.pump();
      expect(find.text('יוסר'), findsNothing);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(find.text('אילוץ מאושר: 8.12 08:00–10:00'), findsNothing);
      expect(find.text('מעולה! כל חברי הצוות זמינים'), findsOneWidget);
      expect(find.text('יוסר'), findsNothing);

      await confirm(tester);
      expect(result?.excluded, isEmpty);
      expect(result?.hoursDropped, {'h-morning'});
    });

    testWidgets('a member freed by unticking enters the conflicts list kept '
        'when the hours are ticked back', (tester) async {
      final morning = _hoursInfo('h-morning', 'דנה כהן',
          flaggedReason: 'אילוץ מאושר: 8.12 08:00–10:00');
      await openDialog(tester, infos: [morning]);
      // Keep the member, then give them the event's hours: they are free.
      await tester.tap(find.text('דנה כהן'));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text('מעולה! כל חברי הצוות זמינים'), findsOneWidget);
      expect(find.text('יוסר'), findsNothing);

      // The moved hours flag them again, but ticking never removes anyone.
      await tester.tap(find.text('סמן הכל'));
      await tester.pump();

      expect(find.text('אילוץ מאושר: 8.12 08:00–10:00'), findsOneWidget);
      expect(find.text('יוסר'), findsNothing);
      expect(find.text('⏰ שעות מותאמות (1)'), findsOneWidget);

      await confirm(tester);
      expect(result?.excluded, isEmpty);
      expect(result?.hoursDropped, isEmpty);
    });

    testWidgets('a ticked row warns about a constraint the moved hours run '
        'into, an unticked one does not', (tester) async {
      final busy = _hoursInfo(
        'h-busy',
        'אבי לוי',
        flaggedReason: 'אילוץ ממתין לאישור: 8.12 (כל היום)',
        constraints: [
          DateConstraint(
            id: 'c1',
            startDate: DateTime(2026, 12, 8),
            status: ConstraintStatus.pending,
            constraintType: ConstraintType.unavailability,
          ),
        ],
      );
      await openDialog(tester, infos: [busy]);
      // Kept by the admin: the row is listed.
      await tester.tap(find.text('אבי לוי'));
      await tester.pump();

      const warning = '⚠️ מתנגש עם אילוץ ממתין לאישור של אבי: 8.12 (כל היום)';
      expect(find.text(warning), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text(warning), findsNothing);
    });
  });
}

Assignment _assignment(
  String id,
  String memberName,
  DateTime now, {
  String? memberId,
  String? start,
  String? end,
  List<DateConstraint> constraints = const [],
  bool allowMultipleAssignments = false,
}) {
  final teamMemberId = memberId ?? 'member-$id';
  return Assignment(
    id: id,
    eventId: 'original',
    teamMemberId: teamMemberId,
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    customStartAt: start,
    customEndAt: end,
    createdAt: now,
    updatedAt: now,
    teamMember: TeamMember(
      id: teamMemberId,
      name: memberName,
      isActive: true,
      isPermanent: true,
      constraints: constraints,
      roleCapabilities: const {'medic': true},
      allowMultipleAssignments: allowMultipleAssignments,
      createdAt: now,
      updatedAt: now,
      uniqueKey: 'key-$teamMemberId',
    ),
  );
}

/// A copy that would carry the source's hours moved seven days on (1.12 to
/// 8.12). By default the member is free in both the moved hours and the new
/// event's own; [flaggedReason] makes the moved hours flag them, and
/// [eventHoursReason] makes only the new event's own hours flag them.
AssignmentDuplicationInfo _hoursInfo(
  String id,
  String memberName, {
  String? memberId,
  String start = '2026-12-01T14:00',
  String end = '2026-12-01T20:00',
  bool allowMultipleAssignments = false,
  String? flaggedReason,
  String? eventHoursReason,
  List<DateConstraint> constraints = const [],
}) {
  return AssignmentDuplicationInfo(
    assignment: _assignment(
      id,
      memberName,
      DateTime(2026, 10, 1),
      memberId: memberId,
      start: start,
      end: end,
      constraints: constraints,
      allowMultipleAssignments: allowMultipleAssignments,
    ),
    hasAvailabilityConflict: flaggedReason != null,
    availabilityReason: flaggedReason,
    isInOverQuotaRole: false,
    movedCustomStartAt: shiftWallMoment(start, 7),
    movedCustomEndAt: shiftWallMoment(end, 7),
    availabilityWithEventHours: eventHoursReason == null
        ? DuplicationAvailability.clear
        : DuplicationAvailability(flagged: true, reasons: [eventHoursReason]),
  );
}

Event _event(String id, DateTime now, DateTime day) {
  return Event(
    id: id,
    name: 'אירוע',
    startDate: day,
    endDate: day,
    startTime: '19:00',
    endTime: '22:00',
    assemblyTime: '18:30',
    requiresArmed: false,
    roleRequirements: const {'medic': 2},
    createdAt: now,
    updatedAt: now,
  );
}
