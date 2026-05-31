import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/data/repositories/assignment_label_repository.dart';
import 'package:shavtzak/domain/entities/assignment_label.dart';

import 'assignment_label_repository_test.mocks.dart';

AssignmentLabel _label(String id, {int sortOrder = 0}) {
  final now = DateTime.utc(2026, 5, 28);
  return AssignmentLabel(
    id: id,
    key: id,
    hebrewName: id,
    color: '#FF0000',
    sortOrder: sortOrder,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}

@GenerateMocks([DatabaseInterface])
void main() {
  late MockDatabaseInterface mockDb;
  late StreamController<List<AssignmentLabel>> controller;
  late AssignmentLabelRepository repo;

  setUp(() {
    mockDb = MockDatabaseInterface();
    controller = StreamController<List<AssignmentLabel>>.broadcast();
    when(mockDb.watchAssignmentLabels()).thenAnswer((_) => controller.stream);
    repo = AssignmentLabelRepository(mockDb);
  });

  tearDown(() async {
    await controller.close();
  });

  test('one shared underlying subscription feeds multiple listeners', () async {
    // Subscribe twice to the public stream.
    final sub1 = repo.watchAssignmentLabels().listen((_) {});
    final sub2 = repo.watchAssignmentLabels().listen((_) {});

    // Pump the event loop so subscriptions engage.
    await Future<void>.delayed(Duration.zero);

    // Only ONE underlying Firestore subscription should be created.
    verify(mockDb.watchAssignmentLabels()).called(1);

    await sub1.cancel();
    await sub2.cancel();
  });

  test('real-time change propagates to ALL listeners without reload', () async {
    final received1 = <List<AssignmentLabel>>[];
    final received2 = <List<AssignmentLabel>>[];

    final sub1 = repo.watchAssignmentLabels().listen(received1.add);
    final sub2 = repo.watchAssignmentLabels().listen(received2.add);
    await Future<void>.delayed(Duration.zero);

    final labelA = _label('a', sortOrder: 0);
    final labelB = _label('b', sortOrder: 1);

    // Initial DB emission.
    controller.add([labelA]);
    await Future<void>.delayed(Duration.zero);

    expect(received1.last, contains(labelA));
    expect(received2.last, contains(labelA));

    // A live change in the DB (label added) on the SAME underlying stream.
    controller.add([labelA, labelB]);
    await Future<void>.delayed(Duration.zero);

    // Both consumers reflect the change instantly, no reload.
    expect(received1.last, containsAll([labelA, labelB]));
    expect(received2.last, containsAll([labelA, labelB]));

    await sub1.cancel();
    await sub2.cancel();
  });

  test('late subscriber immediately gets the latest value (no flicker)',
      () async {
    final labelA = _label('a', sortOrder: 0);

    final received1 = <List<AssignmentLabel>>[];
    final sub1 = repo.watchAssignmentLabels().listen(received1.add);
    await Future<void>.delayed(Duration.zero);

    controller.add([labelA]);
    await Future<void>.delayed(Duration.zero);
    expect(received1.last, contains(labelA));

    // Late subscriber joins AFTER the emission.
    final received2 = <List<AssignmentLabel>>[];
    final sub2 = repo.watchAssignmentLabels().listen(received2.add);
    await Future<void>.delayed(Duration.zero);

    // It immediately receives the replayed latest value, with no new push.
    expect(received2, isNotEmpty);
    expect(received2.last, contains(labelA));

    await sub1.cancel();
    await sub2.cancel();
  });

  test('repeated calls return the SAME stream object (stable identity)', () {
    expect(
      identical(
        repo.watchAssignmentLabels(),
        repo.watchAssignmentLabels(),
      ),
      isTrue,
    );
  });
}
