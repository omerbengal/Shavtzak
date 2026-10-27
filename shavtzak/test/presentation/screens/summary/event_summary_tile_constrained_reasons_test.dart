// The summary screen's "בעלי מגבלות / לא זמינים" list: a member blocked by a
// constraint who is ALSO assigned to another event the same day gets both
// reason lines, same-day first (spec: "If a member has more than one reason,
// all reasons are shown, same-day first").
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/repositories/assignment_label_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/assignment_label.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/role/role_bloc.dart';
import 'package:shavtzak/presentation/bloc/role/role_event.dart';
import 'package:shavtzak/presentation/bloc/role/role_state.dart';
import 'package:shavtzak/presentation/bloc/team/team_bloc.dart';
import 'package:shavtzak/presentation/bloc/team/team_event.dart';
import 'package:shavtzak/presentation/bloc/team/team_state.dart';
import 'package:shavtzak/presentation/screens/summary/widgets/event_summary_tile.dart';

class _MockRoleBloc extends MockBloc<RoleEvent, RoleState>
    implements RoleBloc {}

class _MockTeamBloc extends MockBloc<TeamEvent, TeamState>
    implements TeamBloc {}

class _NoLabels implements AssignmentLabelRepository {
  @override
  Stream<List<AssignmentLabel>> watchAssignmentLabels() =>
      Stream.value(const <AssignmentLabel>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 1, 1);
  final day = DateTime(2026, 11, 10);

  Event eventOnDay(String id, String name) => Event(
        id: id,
        name: name,
        startDate: day,
        endDate: day,
        assemblyTime: '17:00',
        startTime: '19:00',
        endTime: '21:00',
        requiresArmed: false,
        roleRequirements: const {'medic': 1},
        createdAt: now,
        updatedAt: now,
      );

  TeamMember member(String id, String name, DateConstraint? constraint) =>
      TeamMember(
        id: id,
        name: name,
        isActive: true,
        isPermanent: true,
        constraints: [if (constraint != null) constraint],
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'key-$id',
      );

  final staffed = eventOnDay('x1', 'כנס חורף');
  final other = eventOnDay('y1', 'הופעה בחיפה');

  // Blocked by an approved whole-day constraint AND booked on [other].
  final blocked = member(
    'm1',
    'אבי כהן',
    DateConstraint(
      id: 'c1',
      startDate: day,
      status: ConstraintStatus.approved,
      constraintType: ConstraintType.unavailability,
    ),
  );

  late _MockRoleBloc roleBloc;
  late _MockTeamBloc teamBloc;

  setUp(() {
    roleBloc = _MockRoleBloc();
    teamBloc = _MockTeamBloc();
    whenListen(
      roleBloc,
      const Stream<RoleState>.empty(),
      initialState: RolesLoaded([
        Role(
          id: 'role-medic',
          key: 'medic',
          hebrewName: 'חובש',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ]),
    );
    whenListen(
      teamBloc,
      const Stream<TeamState>.empty(),
      initialState: TeamLoaded([blocked]),
    );
  });

  testWidgets(
      'a constraint-blocked member booked elsewhere the same day shows the '
      'same-day line first, then the constraint line', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepositoryProvider<AssignmentLabelRepository>.value(
        value: _NoLabels(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<RoleBloc>.value(value: roleBloc),
            BlocProvider<TeamBloc>.value(value: teamBloc),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EventSummaryTile(
                  data: EventSummaryData(
                    event: staffed,
                    filledSlots: 0,
                    totalSlots: 1,
                    missingRoles: const {'medic': 1},
                    checklistItems: const [],
                  ),
                  allAssignments: [
                    Assignment(
                      id: 'a1',
                      eventId: other.id,
                      teamMemberId: blocked.id,
                      roleType: 'medic',
                      slotIndex: 0,
                      status: AssignmentStatus.confirmed,
                      notes: '',
                      createdAt: now,
                      updatedAt: now,
                    ),
                  ],
                  allEvents: [staffed, other],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Expand the tile, open the slot's dropdown, open the constrained list.
    await tester.tap(find.text('כנס חורף'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('בעלי מגבלות / לא זמינים').last);
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('אבי כהן'),
      matching: find.byType(ListTile),
    );
    expect(row, findsOneWidget);

    final lines = tester
        .widgetList<Text>(find.descendant(
          of: row,
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .where((data) => data != 'אבי כהן' && data != 'שבץ בכל זאת')
        .toList();
    expect(lines, [
      'משובצ/ת ב: הופעה בחיפה',
      'אילוץ מאושר: 10.11 (כל היום)',
    ]);
  });
}
