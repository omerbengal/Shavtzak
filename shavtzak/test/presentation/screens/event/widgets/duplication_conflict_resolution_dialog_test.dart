import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
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
  Set<String>? result;
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

  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = DuplicationRequiresConflictResolution(
      originalEvent: original,
      proposedEvent: proposed,
      assignmentInfos: [locked, keepable],
      roleQuotas: const {'medic': 2},
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
    expect(result, {'a-locked'});
  });
}

Assignment _assignment(String id, String memberName, DateTime now) {
  return Assignment(
    id: id,
    eventId: 'original',
    teamMemberId: 'member-$id',
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
    teamMember: TeamMember(
      id: 'member-$id',
      name: memberName,
      isActive: true,
      isPermanent: true,
      constraints: const [],
      roleCapabilities: const {'medic': true},
      createdAt: now,
      updatedAt: now,
      uniqueKey: 'key-$id',
    ),
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
