// The "constraints that collide with the event" dialog judges a member who is
// assigned with custom hours against those hours. It reads the event's
// assignments once from the live stream; when that read fails or times out it
// falls back to judging everyone against the whole event rather than blocking.
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/team/team_bloc.dart';
import 'package:shavtzak/presentation/bloc/team/team_event.dart';
import 'package:shavtzak/presentation/bloc/team/team_state.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_constraint_collisions_dialog.dart';

class _MockTeamBloc extends MockBloc<TeamEvent, TeamState>
    implements TeamBloc {}

/// Only the one method the dialog calls.
class _FakeAssignmentRepository implements AssignmentRepository {
  _FakeAssignmentRepository(this.stream);

  final Stream<List<Assignment>> stream;

  @override
  Stream<List<Assignment>> watchAssignmentsByEvent(String eventId) => stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 1, 1);
  final day1 = DateTime(2026, 11, 5);
  final day2 = DateTime(2026, 11, 6);

  // A two-day event with no times: its stretch is the two whole days.
  final event = Event(
    id: 'e1',
    name: 'אירוע דו יומי',
    startDate: day1,
    endDate: day2,
    startTime: '',
    endTime: '',
    assemblyTime: '',
    requiresArmed: false,
    roleRequirements: const {'medic': 2},
    createdAt: now,
    updatedAt: now,
  );

  TeamMember member(String id, String name) => TeamMember(
        id: id,
        name: name,
        isActive: true,
        isPermanent: true,
        constraints: [
          DateConstraint(
            id: 'c-$id',
            startDate: day2,
            status: ConstraintStatus.approved,
            constraintType: ConstraintType.unavailability,
          ),
        ],
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'key-$id',
      );

  // Dana is assigned with day-1 hours; Ron is not assigned at all. Both have
  // an approved whole-day constraint on day 2.
  final dana = member('m1', 'דנה');
  final ron = member('m2', 'רון');

  final danaDay1Only = Assignment(
    id: 'a1',
    eventId: 'e1',
    teamMemberId: 'm1',
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    customStartAt: '2026-11-05T09:00',
    customEndAt: '2026-11-05T17:00',
    createdAt: now,
    updatedAt: now,
  );

  late _MockTeamBloc teamBloc;

  setUp(() {
    teamBloc = _MockTeamBloc();
    whenListen(
      teamBloc,
      const Stream<TeamState>.empty(),
      initialState: TeamLoaded([dana, ron]),
    );
  });

  Future<void> open(WidgetTester tester, Stream<List<Assignment>> stream) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepositoryProvider<AssignmentRepository>.value(
        value: _FakeAssignmentRepository(stream),
        child: BlocProvider<TeamBloc>.value(
          value: teamBloc,
          child: MaterialApp(
            home: Scaffold(
              body: EventConstraintCollisionsDialog(event: event),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'a member assigned with day-1 hours is not listed for a day-2 '
      'constraint; an unassigned member is', (tester) async {
    await open(tester, Stream.value([danaDay1Only]));
    await tester.pump();

    expect(find.text('רון'), findsOneWidget);
    expect(find.text('דנה'), findsNothing);
  });

  testWidgets('a failed read falls back to the whole event for everyone',
      (tester) async {
    await open(tester, Stream.error(StateError('offline')));
    await tester.pump();

    expect(find.text('רון'), findsOneWidget);
    expect(find.text('דנה'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'a read that never answers shows a spinner, then falls back to the '
      'whole event after the timeout', (tester) async {
    final never = StreamController<List<Assignment>>();
    addTearDown(never.close);
    await open(tester, never.stream);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('רון'), findsNothing);

    await tester.pump(eventAssignmentsReadTimeout + const Duration(seconds: 1));

    expect(find.text('רון'), findsOneWidget);
    expect(find.text('דנה'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('readEventAssignmentsOnce', () {
    test('returns the first emit', () async {
      final result = await readEventAssignmentsOnce(
        _FakeAssignmentRepository(Stream.value([danaDay1Only])),
        'e1',
      );

      expect(result.map((a) => a.id), ['a1']);
    });

    test('returns an empty list when the stream ends without an emit',
        () async {
      final result = await readEventAssignmentsOnce(
        _FakeAssignmentRepository(const Stream.empty()),
        'e1',
      );

      expect(result, isEmpty);
    });

    test('returns an empty list when the stream errors', () async {
      final result = await readEventAssignmentsOnce(
        _FakeAssignmentRepository(Stream.error(StateError('offline'))),
        'e1',
      );

      expect(result, isEmpty);
    });

    test('returns an empty list when the first emit is too slow', () async {
      final never = StreamController<List<Assignment>>();
      addTearDown(never.close);

      final result = await readEventAssignmentsOnce(
        _FakeAssignmentRepository(never.stream),
        'e1',
        timeout: const Duration(milliseconds: 20),
      );

      expect(result, isEmpty);
    });
  });
}
