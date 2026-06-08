// Widget tests for EventTeamMembersDialog (the "מי איתי / who-is-with-me"
// dialog), opened from /user/assignments.
//
// Bug (confirmed by two live prod debug logs): opening this dialog could freeze
// on a spinner for ~30s. Root cause was in the dialog's FETCH LOGIC — it gated
// first paint on an awaited one-shot getAssignmentsByEvent(): a server-first
// Firestore .get() that can park for ~30s on a transport hiccup, while the
// watchAssignmentsByEvent LISTENER on the SAME connection kept emitting in
// ~100ms. Three staggered opens in one log all unblocked at the same instant
// (head-of-line blocking released by the SDK's ~30s recovery) — proving it was
// the blocking get, not bandwidth. Every other assignment view paints from a
// stream; this one didn't.
//
// Fix: the dialog is now stream-first — it dispatches LoadAssignmentsByEvent
// (which subscribes to watchAssignmentsByEvent) and renders from that stream,
// with NO blocking one-shot get.
//
// These tests lock that contract in:
//   * data renders from the watchAssignmentsByEvent stream, and
//   * the dialog NEVER calls the one-shot getAssignmentsByEvent().

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/data/repositories/role_repository.dart';
import 'package:shavtzak/data/repositories/team_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/role/role_bloc.dart';
import 'package:shavtzak/presentation/bloc/role/role_event.dart';
import 'package:shavtzak/presentation/bloc/role/role_state.dart';
import 'package:shavtzak/presentation/widgets/event_team_members_dialog.dart';

import 'event_team_members_dialog_test.mocks.dart';

@GenerateMocks([
  AssignmentRepository,
  EventRepository,
  TeamRepository,
  RoleRepository,
])
class MockRoleBloc extends MockBloc<RoleEvent, RoleState> implements RoleBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventId = 'evt-1';
  final now = DateTime(2026, 1, 1);

  late MockAssignmentRepository assignmentRepo;
  late MockEventRepository eventRepo;
  late MockTeamRepository teamRepo;
  late MockRoleRepository roleRepo;
  late MockRoleBloc roleBloc;
  late StreamController<List<Assignment>> eventAssignmentStream;
  late AssignmentBloc assignmentBloc;

  TeamMember memberFor(String id, String name) => TeamMember(
        id: id,
        name: name,
        isActive: true,
        constraints: const [],
        roleCapabilities: const {},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'uk-$id',
      );

  Assignment assignmentFor(String id, TeamMember member) => Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: member.id,
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: now,
        updatedAt: now,
        teamMember: member,
      );

  final medicRole = Role(
    id: 'medic',
    key: 'medic',
    hebrewName: 'חובש',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    assignmentRepo = MockAssignmentRepository();
    eventRepo = MockEventRepository();
    teamRepo = MockTeamRepository();
    roleRepo = MockRoleRepository();

    // Single-subscription controller buffers events added before the bloc
    // subscribes, so the test has no add()-before-listen race.
    eventAssignmentStream = StreamController<List<Assignment>>();
    when(assignmentRepo.watchAssignmentsByEvent(any))
        .thenAnswer((_) => eventAssignmentStream.stream);

    assignmentBloc = AssignmentBloc(
      assignmentRepo,
      eventRepo,
      teamRepo,
      roleRepo,
      null, // CalendarSyncBloc is optional
    );

    // The dialog's list needs a RolesLoaded ancestor to map role keys → names.
    roleBloc = MockRoleBloc();
    whenListen(
      roleBloc,
      const Stream<RoleState>.empty(),
      initialState: RolesLoaded([medicRole]),
    );
  });

  tearDown(() async {
    await eventAssignmentStream.close();
    await assignmentBloc.close();
    await roleBloc.close();
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RoleBloc>.value(
          value: roleBloc,
          child: EventTeamMembersDialog(
            eventId: eventId,
            currentUserId: 'me-not-them',
            eventName: 'אירוע בדיקה',
            assignmentBloc: assignmentBloc,
          ),
        ),
      ),
    );
  }

  // The bloc handler (emit.forEach over a real StreamController) settles via
  // real microtasks that tester.pump() alone won't flush — drive them under
  // runAsync, then pump to rebuild the tree with the settled bloc state.
  Future<void> emitAssignments(
    WidgetTester tester,
    List<Assignment> data,
  ) async {
    await tester.runAsync(() async {
      eventAssignmentStream.add(data);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'renders team members from the watchAssignmentsByEvent stream '
    '(no blocking one-shot get)',
    (tester) async {
      await pumpDialog(tester);

      // First frame: spinner, stream has not emitted yet.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // The listener delivers the event's assignments (cache-first in prod).
      await emitAssignments(
          tester, [assignmentFor('a1', memberFor('tm1', 'דני'))]);

      expect(find.text('דני'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Core contract of the fix: data comes from the LISTENER, and first paint
      // is NEVER gated on the server-first one-shot get that caused the freeze.
      verify(assignmentRepo.watchAssignmentsByEvent(eventId)).called(1);
      verifyNever(assignmentRepo.getAssignmentsByEvent(any));
    },
  );

  testWidgets(
    'shows the empty state when the stream reports no assignments',
    (tester) async {
      await pumpDialog(tester);
      await tester.pump();

      await emitAssignments(tester, const []);

      expect(find.text('אין חברי צוות נוספים באירוע'), findsOneWidget);
      verifyNever(assignmentRepo.getAssignmentsByEvent(any));
    },
  );
}
