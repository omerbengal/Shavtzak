// End-to-end tests (against a fake Firestore) for the live relation cache in
// FirestoreDatabase.
//
// Background: the assignment `watchX` streams hydrate relations via
// _populateAssignmentRelations. It used to do per-read one-shot `whereIn`
// `.get()`s — and on the live web setup that members get intermittently parked
// ~24s, freezing the who-is-with-me dialog. Now population is a synchronous
// in-memory join against caches kept live by long-lived listeners
// (watchEvents/watchTeamMembers/watchAssignmentLabels), each reading the full
// collection. No one-shot gets in the read path.
//
// These tests prove the join works through the real stream/asyncMap/cache path
// (FirestoreDatabase is constructed with a fake Firestore — possible now that
// BackendApiService is created lazily, so the ctor no longer touches Firebase).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/models/assignment_model.dart';
import 'package:shavtzak/data/models/event_model.dart';
import 'package:shavtzak/data/models/team_member_model.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 1, 1);

  late FakeFirebaseFirestore fake;
  late FirestoreDatabase db;

  setUp(() {
    fake = FakeFirebaseFirestore();
    db = FirestoreDatabase(firestore: fake);
  });

  tearDown(() async {
    await db.close(); // cancels the relation-cache listeners
  });

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

  Event eventFor(String id) => Event(
        id: id,
        name: 'event-$id',
        startDate: DateTime(2026, 6, 1, 9, 0),
        endDate: DateTime(2026, 6, 1, 17, 0),
        startTime: '09:00',
        endTime: '17:00',
        assemblyTime: '08:30',
        requiresArmed: false,
        roleRequirements: const {'medic': 1},
        createdAt: now,
        updatedAt: now,
      );

  Assignment assignmentFor(String id, String eventId, String memberId) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: now,
        updatedAt: now,
      );

  Future<void> seedMember(TeamMember m) => fake
      .collection('teamMembers')
      .doc(m.id)
      .set(TeamMemberModel.fromEntity(m).toFirestore());
  Future<void> seedEvent(Event e) =>
      fake.collection('events').doc(e.id).set(EventModel.fromEntity(e).toFirestore());
  Future<void> seedAssignment(Assignment a) => fake
      .collection('assignments')
      .doc(a.id)
      .set(AssignmentModel.fromEntity(a).toFirestore());

  test(
    'watchAssignmentsByEvent populates teamMember + event from the live cache',
    () async {
      await seedMember(memberFor('m1', 'דני'));
      await seedEvent(eventFor('e1'));
      await seedAssignment(assignmentFor('a1', 'e1', 'm1'));

      final emitted = await db
          .watchAssignmentsByEvent('e1')
          .firstWhere((list) => list.isNotEmpty)
          .timeout(const Duration(seconds: 5));

      expect(emitted, hasLength(1));
      expect(emitted.first.teamMember?.name, 'דני',
          reason: 'member must be hydrated from the live cache, not a get');
      expect(emitted.first.event?.id, 'e1');
    },
  );

  test(
    'watchAssignmentsByPerson hydrates each assignment via the cache join',
    () async {
      await seedMember(memberFor('m1', 'דני'));
      await seedEvent(eventFor('e1'));
      await seedEvent(eventFor('e2'));
      await seedAssignment(assignmentFor('a1', 'e1', 'm1'));
      await seedAssignment(assignmentFor('a2', 'e2', 'm1'));

      final emitted = await db
          .watchAssignmentsByPerson('m1')
          .firstWhere((list) => list.length == 2)
          .timeout(const Duration(seconds: 5));

      expect(emitted.every((a) => a.teamMember?.name == 'דני'), isTrue);
      expect(emitted.map((a) => a.event?.id).toSet(), {'e1', 'e2'});
    },
  );

  test(
    'a dangling team-member FK leaves teamMember null (no hang, no throw)',
    () async {
      // Assignment references a member that does not exist.
      await seedEvent(eventFor('e1'));
      await seedAssignment(assignmentFor('a1', 'e1', 'ghost'));

      final emitted = await db
          .watchAssignmentsByEvent('e1')
          .firstWhere((list) => list.isNotEmpty)
          .timeout(const Duration(seconds: 5));

      expect(emitted, hasLength(1));
      expect(emitted.first.teamMember, isNull);
      expect(emitted.first.event?.id, 'e1');
    },
  );
}
