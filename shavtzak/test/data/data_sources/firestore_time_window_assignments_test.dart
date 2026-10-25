// End-to-end tests (against a fake Firestore) for
// FirestoreDatabase.watchAssignmentsInTimeWindow following the window's events.
//
// Background (prod, 2026-10-25): the stream read the window's event ids ONCE
// when it subscribed and only ever listened to assignments of those events. An
// event created after /admin/assignments was opened showed up (the events
// stream is live) but its assignments never arrived — a successful save kept
// showing empty slots, the admin re-entered the same people and the backend
// rejected the second save as "כבר משובץ/ת לתפקיד זה באירוע".

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/models/assignment_model.dart';
import 'package:shavtzak/data/models/event_model.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 1, 1);
  final windowStart = DateTime(2026, 5, 1);
  final windowEnd = DateTime(2026, 8, 1);

  late FakeFirebaseFirestore fake;
  late FirestoreDatabase db;

  setUp(() {
    fake = FakeFirebaseFirestore();
    db = FirestoreDatabase(firestore: fake);
  });

  tearDown(() async {
    await db.close();
  });

  Event eventFor(String id, {DateTime? day}) {
    final d = day ?? DateTime(2026, 6, 1);
    return Event(
      id: id,
      name: 'event-$id',
      startDate: DateTime(d.year, d.month, d.day, 9),
      endDate: DateTime(d.year, d.month, d.day, 17),
      startTime: '09:00',
      endTime: '17:00',
      assemblyTime: '08:30',
      requiresArmed: false,
      roleRequirements: const {'medic': 1},
      createdAt: now,
      updatedAt: now,
    );
  }

  Assignment assignmentFor(String id, String eventId) => Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: 'm1',
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: now,
        updatedAt: now,
      );

  Future<void> seedEvent(Event e) =>
      fake.collection('events').doc(e.id).set(EventModel.fromEntity(e).toFirestore());
  Future<void> seedAssignment(Assignment a) => fake
      .collection('assignments')
      .doc(a.id)
      .set(AssignmentModel.fromEntity(a).toFirestore());

  Set<String> ids(List<Assignment> list) => list.map((a) => a.id).toSet();

  test('picks up assignments of an event created after subscribing', () async {
    await seedEvent(eventFor('e1'));
    await seedAssignment(assignmentFor('a1', 'e1'));

    final emissions = <Set<String>>[];
    final sub = db
        .watchAssignmentsInTimeWindow(windowStart, windowEnd)
        .listen((list) => emissions.add(ids(list)));

    await pumpUntil(() => emissions.any((e) => e.contains('a1')));

    await seedEvent(eventFor('e2'));
    await seedAssignment(assignmentFor('a2', 'e2'));

    await pumpUntil(() => emissions.isNotEmpty && emissions.last.containsAll({'a1', 'a2'}));
    expect(emissions.last, {'a1', 'a2'});
    await sub.cancel();
  });

  test('a window that starts empty follows the first event created in it',
      () async {
    final emissions = <Set<String>>[];
    final sub = db
        .watchAssignmentsInTimeWindow(windowStart, windowEnd)
        .listen((list) => emissions.add(ids(list)));

    await pumpUntil(() => emissions.isNotEmpty);
    expect(emissions.last, isEmpty);

    await seedEvent(eventFor('e1'));
    await seedAssignment(assignmentFor('a1', 'e1'));

    await pumpUntil(() => emissions.last.contains('a1'));
    expect(emissions.last, {'a1'});
    await sub.cancel();
  });

  test('drops assignments of an event moved out of the window', () async {
    await seedEvent(eventFor('e1'));
    await seedEvent(eventFor('e2'));
    await seedAssignment(assignmentFor('a1', 'e1'));
    await seedAssignment(assignmentFor('a2', 'e2'));

    final emissions = <Set<String>>[];
    final sub = db
        .watchAssignmentsInTimeWindow(windowStart, windowEnd)
        .listen((list) => emissions.add(ids(list)));

    await pumpUntil(() => emissions.isNotEmpty && emissions.last.length == 2);

    await seedEvent(eventFor('e2', day: DateTime(2026, 12, 1)));

    await pumpUntil(() => emissions.last.length == 1);
    expect(emissions.last, {'a1'});
    await sub.cancel();
  });

  test('keeps more than 30 events (several whereIn chunks) complete', () async {
    for (var i = 0; i < 35; i++) {
      await seedEvent(eventFor('e$i'));
      await seedAssignment(assignmentFor('a$i', 'e$i'));
    }

    final emissions = <Set<String>>[];
    final sub = db
        .watchAssignmentsInTimeWindow(windowStart, windowEnd)
        .listen((list) => emissions.add(ids(list)));

    await pumpUntil(() => emissions.isNotEmpty && emissions.last.length == 35);

    await seedEvent(eventFor('new'));
    await seedAssignment(assignmentFor('aNew', 'new'));

    await pumpUntil(() => emissions.last.contains('aNew'));
    expect(emissions.last.length, 36);
    await sub.cancel();
  });
}

Future<void> pumpUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within 5s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
