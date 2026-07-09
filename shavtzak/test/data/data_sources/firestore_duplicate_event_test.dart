// Tests for FirestoreDatabase.isDuplicateEvent (against a fake Firestore).
//
// Background: duplicate detection had been silently broken. The query paired an
// equality filter on `name` with a range filter on `startDate` (a different
// field), which Firestore can only serve from a composite (name, startDate)
// index that was never created — so it threw FAILED_PRECONDITION on every save
// and both createEvent/updateEvent swallowed the error. The query now filters
// by the startDate day-range only (single-field, no composite index) and
// matches the name in memory. These tests lock in that behaviour.
//
// Note: fake_cloud_firestore does not enforce composite indexes, so it cannot
// reproduce the original FAILED_PRECONDITION. That the index is missing was
// confirmed against the real project's deployed indexes. What these tests
// protect is the day-bucketing + name/exclude matching logic.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/models/event_model.dart';
import 'package:shavtzak/domain/entities/event.dart';

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
    await db.close();
  });

  Event eventFor(String id, String name, DateTime startDate) => Event(
        id: id,
        name: name,
        startDate: startDate,
        endDate: startDate,
        startTime: '09:00',
        endTime: '17:00',
        assemblyTime: '08:30',
        requiresArmed: false,
        roleRequirements: const {'medic': 1},
        createdAt: now,
        updatedAt: now,
      );

  Future<void> seedEvent(Event e) => fake
      .collection('events')
      .doc(e.id)
      .set(EventModel.fromEntity(e).toFirestore());

  test('same name on the same day is a duplicate', () async {
    await seedEvent(eventFor('e1', 'מופע', DateTime(2026, 6, 1, 10, 0)));

    expect(
      await db.isDuplicateEvent('מופע', DateTime(2026, 6, 1, 18, 0)),
      isTrue,
    );
  });

  test('same name on a different day is not a duplicate', () async {
    await seedEvent(eventFor('e1', 'מופע', DateTime(2026, 6, 1, 10, 0)));

    expect(
      await db.isDuplicateEvent('מופע', DateTime(2026, 6, 2, 10, 0)),
      isFalse,
    );
  });

  test('a different name on the same day is not a duplicate', () async {
    await seedEvent(eventFor('e1', 'מופע', DateTime(2026, 6, 1, 10, 0)));

    expect(
      await db.isDuplicateEvent('אירוע אחר', DateTime(2026, 6, 1, 10, 0)),
      isFalse,
    );
  });

  test('no events at all is not a duplicate', () async {
    expect(
      await db.isDuplicateEvent('מופע', DateTime(2026, 6, 1, 10, 0)),
      isFalse,
    );
  });

  test('matches by day regardless of time-of-day within that day', () async {
    // Stored near end of day, queried near start of day — same calendar day.
    await seedEvent(eventFor('e1', 'מופע', DateTime(2026, 6, 1, 23, 30)));

    expect(
      await db.isDuplicateEvent('מופע', DateTime(2026, 6, 1, 0, 15)),
      isTrue,
    );
  });

  test('excluding the event itself is not a self-collision', () async {
    // The only same-name/same-day event is the one being edited.
    await seedEvent(eventFor('e1', 'מופע', DateTime(2026, 6, 1, 10, 0)));

    expect(
      await db.isDuplicateEvent(
        'מופע',
        DateTime(2026, 6, 1, 10, 0),
        excludeEventId: 'e1',
      ),
      isFalse,
    );
  });

  test('another same-name/same-day event still collides when excluding self',
      () async {
    await seedEvent(eventFor('e1', 'מופע', DateTime(2026, 6, 1, 10, 0)));
    await seedEvent(eventFor('e2', 'מופע', DateTime(2026, 6, 1, 14, 0)));

    expect(
      await db.isDuplicateEvent(
        'מופע',
        DateTime(2026, 6, 1, 10, 0),
        excludeEventId: 'e1',
      ),
      isTrue,
    );
  });
}
