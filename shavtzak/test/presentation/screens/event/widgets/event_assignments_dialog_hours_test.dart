// The admin's event assignments dialog shows a member's own hours as a line
// above the notes box; members without hours look as they always did.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/repositories/assignment_label_repository.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/assignment_label.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/role/role_bloc.dart';
import 'package:shavtzak/presentation/bloc/role/role_event.dart';
import 'package:shavtzak/presentation/bloc/role/role_state.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_dialog.dart';

class _MockRoleBloc extends MockBloc<RoleEvent, RoleState>
    implements RoleBloc {}

class _FakeAssignmentRepository extends Mock implements AssignmentRepository {
  @override
  Stream<List<Assignment>> watchAssignmentsByEvent(String eventId) =>
      const Stream.empty();
}

class _FakeAssignmentLabelRepository extends Mock
    implements AssignmentLabelRepository {
  @override
  Stream<List<AssignmentLabel>> watchAssignmentLabels() =>
      Stream.value(const <AssignmentLabel>[]);
}

final DateTime _stamp = DateTime(2026, 10, 1);

TeamMember _member(String id, String name) => TeamMember(
      id: id,
      name: name,
      isActive: true,
      isPermanent: true,
      constraints: const [],
      roleCapabilities: const {},
      createdAt: _stamp,
      updatedAt: _stamp,
      uniqueKey: 'uk-$id',
    );

final Event _event = Event(
  id: 'e1',
  name: 'כנס חורף',
  startDate: DateTime(2026, 10, 27),
  endDate: DateTime(2026, 10, 28),
  startTime: '19:00',
  endTime: '22:30',
  assemblyTime: '12:00',
  requiresArmed: false,
  roleRequirements: const {'medic': 2},
  createdAt: _stamp,
  updatedAt: _stamp,
);

Assignment _assignment(
  String id,
  TeamMember member, {
  String notes = '',
  String? customStartAt,
  String? customEndAt,
}) =>
    Assignment(
      id: id,
      eventId: 'e1',
      teamMemberId: member.id,
      roleType: 'medic',
      slotIndex: 0,
      status: AssignmentStatus.confirmed,
      notes: notes,
      customStartAt: customStartAt,
      customEndAt: customEndAt,
      createdAt: _stamp,
      updatedAt: _stamp,
      teamMember: member,
    );

void main() {
  final medic = Role(
    id: 'medic',
    key: 'medic',
    hebrewName: 'חובש/ת',
    sortOrder: 0,
    createdAt: _stamp,
    updatedAt: _stamp,
  );

  late _MockRoleBloc roleBloc;

  setUp(() {
    roleBloc = _MockRoleBloc();
    whenListen(
      roleBloc,
      const Stream<RoleState>.empty(),
      initialState: RolesLoaded([medic]),
    );
  });

  Future<void> pumpDialog(
    WidgetTester tester,
    List<Assignment> assignments,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AssignmentRepository>.value(
                value: _FakeAssignmentRepository()),
            RepositoryProvider<AssignmentLabelRepository>.value(
                value: _FakeAssignmentLabelRepository()),
          ],
          child: BlocProvider<RoleBloc>.value(
            value: roleBloc,
            child: Scaffold(
              body: EventAssignmentsDialog.withAssignments(
                event: _event,
                assignments: assignments,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a member with hours shows them directly above the notes box',
      (tester) async {
    await pumpDialog(tester, [
      _assignment(
        'a1',
        _member('m1', 'דני'),
        notes: 'מביא ציוד',
        customStartAt: '2026-10-27T14:00',
        customEndAt: '2026-10-27T23:00',
      ),
    ]);

    final hours = find.text("שעות: יום ג' 14:00–23:00");
    final notes = find.textContaining('הערות לשיבוץ');
    expect(hours, findsOneWidget);
    expect(notes, findsOneWidget);
    expect(tester.getTopLeft(hours).dy, lessThan(tester.getTopLeft(notes).dy));
  });

  testWidgets(
      'members without hours, or with hours that cannot be read, '
      'get no hours line', (tester) async {
    await pumpDialog(tester, [
      _assignment('a1', _member('m1', 'דני')),
      _assignment(
        'a2',
        _member('m2', 'רותי'),
        customStartAt: '2026-10-27T23:00',
        customEndAt: '2026-10-27T14:00',
      ),
    ]);

    expect(find.text('דני'), findsOneWidget);
    expect(find.text('רותי'), findsOneWidget);
    expect(find.textContaining('שעות:'), findsNothing);
  });
}
