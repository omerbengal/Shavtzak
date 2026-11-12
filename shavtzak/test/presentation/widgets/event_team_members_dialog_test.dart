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
import 'package:shavtzak/domain/entities/event.dart';
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

  TeamMember memberFor(String id, String name, {String? phone}) => TeamMember(
        id: id,
        name: name,
        isActive: true,
        constraints: const [],
        roleCapabilities: const {},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'uk-$id',
        phoneNumber: phone,
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

  final event = Event(
    id: eventId,
    name: 'אירוע בדיקה',
    startDate: DateTime(2026, 10, 27),
    endDate: DateTime(2026, 10, 27),
    startTime: '19:00',
    endTime: '22:30',
    assemblyTime: '18:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RoleBloc>.value(
          value: roleBloc,
          child: EventTeamMembersDialog(
            event: event,
            currentUserId: 'me',
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

  testWidgets('shows the export picture, no search box', (tester) async {
    await pumpDialog(tester);
    await tester.pump();
    await emitAssignments(tester, [
      assignmentFor('a1', memberFor('tm1', 'דני')).copyWith(
        notes: 'מביא ציוד',
        customStartAt: () => '2026-10-27T19:00',
        customEndAt: () => '2026-10-27T21:00',
      ),
    ]);

    expect(find.byKey(const Key('who-is-with-me-picture')), findsOneWidget);
    expect(find.text('אירוע בדיקה'), findsOneWidget); // the picture's header
    expect(find.text('חובש'), findsOneWidget);
    expect(find.textContaining('מביא ציוד'), findsOneWidget);
    expect(find.textContaining('שעות'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the viewer\'s own row reads "אני"', (tester) async {
    await pumpDialog(tester);
    await tester.pump();
    await emitAssignments(tester, [
      assignmentFor('a1', memberFor('me', 'אני עצמי', phone: '050')),
      assignmentFor('a2', memberFor('tm2', 'רותי', phone: '052')),
    ]);

    expect(find.text('אני'), findsOneWidget);
    expect(find.text('אני עצמי'), findsNothing);
    // Own row does not call.
    expect(find.byKey(const ValueKey('call-me')), findsNothing);
    expect(find.byKey(const ValueKey('call-tm2')), findsOneWidget);
  });

  testWidgets('tapping a row asks before calling; cancel calls nobody',
      (tester) async {
    await pumpDialog(tester);
    await tester.pump();
    await emitAssignments(tester, [
      assignmentFor('a1', memberFor('tm1', 'דני', phone: '0501234567')),
    ]);

    await tester.tap(find.byKey(const ValueKey('call-tm1')));
    await tester.pumpAndSettle();
    expect(find.text('להתקשר לדני?'), findsOneWidget);
    expect(find.text('0501234567'), findsOneWidget);

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-call')), findsNothing);
  });

  testWidgets('a member with no phone (and no alternative) is not tappable',
      (tester) async {
    await pumpDialog(tester);
    await tester.pump();
    await emitAssignments(tester, [
      assignmentFor('a1', memberFor('tm1', 'דני')),
      assignmentFor('a2', memberFor('tm2', 'רותי'))
          .copyWith(alternativePhoneNumber: () => '0529999999'),
    ]);

    expect(find.byKey(const ValueKey('call-tm1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('call-tm2')));
    await tester.pumpAndSettle();
    expect(find.text('0529999999'), findsOneWidget);
  });

  testWidgets('a big event fits on one phone screen, no scrolling',
      (tester) async {
    await pumpDialog(tester);
    await tester.pump();
    await emitAssignments(tester, [
      for (var i = 0; i < 30; i++)
        assignmentFor('a$i', memberFor('tm$i', 'חבר צוות $i')),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsNothing);
    final picture =
        tester.getRect(find.byKey(const Key('who-is-with-me-picture')));
    expect(picture.top, greaterThanOrEqualTo(0));
    expect(picture.bottom, lessThanOrEqualTo(844));
    expect(picture.left, greaterThanOrEqualTo(0));
    expect(picture.right, lessThanOrEqualTo(390));
  });

  testWidgets('a tall event still fills the popup\'s width', (tester) async {
    await pumpDialog(tester);
    await tester.pump();
    await emitAssignments(tester, [
      for (var i = 0; i < 40; i++)
        assignmentFor('a$i', memberFor('tm$i', 'חבר צוות $i')),
    ]);

    expect(tester.takeException(), isNull);
    final picture =
        tester.getRect(find.byKey(const Key('who-is-with-me-picture')));
    // 390 screen − 2×6 popup margin − 2×4 popup padding = 370, centred.
    expect(picture.width, moreOrLessEquals(370, epsilon: 2));
    expect(picture.left, moreOrLessEquals(390 - picture.right, epsilon: 1));
    expect(picture.bottom, lessThanOrEqualTo(844));
  });

  testWidgets('follows the assignments live', (tester) async {
    await pumpDialog(tester);
    await tester.pump();
    await emitAssignments(
        tester, [assignmentFor('a1', memberFor('tm1', 'דני'))]);
    expect(find.text('דני'), findsOneWidget);

    await emitAssignments(
        tester, [assignmentFor('a1', memberFor('tm3', 'משה'))]);
    expect(find.text('דני'), findsNothing);
    expect(find.text('משה'), findsOneWidget);
  });
}
