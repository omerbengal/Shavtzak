import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';

import 'assignment_repository_save_batch_test.mocks.dart';

@GenerateMocks([DatabaseInterface])
void main() {
  Assignment a(String id) => Assignment(
        id: id, eventId: 'e1', teamMemberId: 'm1', roleType: 'medic',
        slotIndex: 0, status: AssignmentStatus.confirmed, notes: '',
        createdAt: DateTime(2026), updatedAt: DateTime(2026),
      );

  test('saveAssignmentsBatch forwards creates/updates/deletes to the database', () async {
    final db = MockDatabaseInterface();
    when(db.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
      eventQuotaBumps: anyNamed('eventQuotaBumps'),
      eventQuotaSets: anyNamed('eventQuotaSets'),
    )).thenAnswer((_) async {});
    final repo = AssignmentRepository(db);

    await repo.saveAssignmentsBatch(
      creates: [a('c1')], updates: [a('u1')], deletes: ['d1'],
    );

    final captured = verify(db.saveAssignmentsBatch(
      creates: captureAnyNamed('creates'),
      updates: captureAnyNamed('updates'),
      deletes: captureAnyNamed('deletes'),
      eventQuotaBumps: anyNamed('eventQuotaBumps'),
      eventQuotaSets: anyNamed('eventQuotaSets'),
    )).captured;
    final creates = captured[0] as List<Assignment>;
    final updates = captured[1] as List<Assignment>;
    final deletes = captured[2] as List<String>;
    expect(creates.single.id, 'c1');   // a swap would make this 'u1'
    expect(updates.single.id, 'u1');
    expect(deletes, ['d1']);
  });

  test(
      'saveAssignmentsBatch does NOT clear the current-assignments cache '
      '(post-save windowed grid must stay populated)', () async {
    final db = MockDatabaseInterface();
    when(db.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
      eventQuotaBumps: anyNamed('eventQuotaBumps'),
      eventQuotaSets: anyNamed('eventQuotaSets'),
    )).thenAnswer((_) async {});
    final repo = AssignmentRepository(db);

    // The live stream seeds this snapshot; the windowed slot-build reads it via
    // getCurrentAssignments().
    repo.cacheCurrentAssignments([a('x1'), a('x2')]);

    await repo.saveAssignmentsBatch(
        creates: [a('c1')], updates: const [], deletes: const []);

    // It must SURVIVE the save. The old clearCache() here emptied it, so the
    // immediately-following post-save RebuildAssignmentSlots built an all-empty
    // grid ("0 משובצים") that never recovered once the DB had settled.
    expect(repo.getCurrentAssignments(), hasLength(2));
  });

  test(
      'updateAssignmentUnchecked bypasses backend availability revalidation '
      '(slot compaction must not re-litigate a forced assignment)', () async {
    final db = MockDatabaseInterface();
    when(db.updateAssignment(any,
            bypassAvailability: anyNamed('bypassAvailability')))
        .thenAnswer((_) async {});
    final repo = AssignmentRepository(db);

    await repo.updateAssignmentUnchecked(a('u1'));

    // This path only ever rewrites slotIndex to close a gap after a quota
    // reduction; the assignment itself already exists and may well have been
    // force-assigned on purpose ("שבץ בכל זאת") to a member who is NOT
    // available for the event. Leaving bypassAvailability at its false default
    // made the backend re-run memberAvailableForEvent on that untouched row
    // and reject the whole compaction with
    // 'חבר/ת הצוות לא זמין/ה לאירוע זה'.
    final bypass = verify(db.updateAssignment(any,
            bypassAvailability: captureAnyNamed('bypassAvailability')))
        .captured
        .single as bool;
    expect(bypass, isTrue);
  });

  test('saveAssignmentsBatch forwards eventQuotaSets to the database', () async {
    final db = MockDatabaseInterface();
    when(db.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
      eventQuotaBumps: anyNamed('eventQuotaBumps'),
      eventQuotaSets: anyNamed('eventQuotaSets'),
    )).thenAnswer((_) async {});
    final repo = AssignmentRepository(db);

    await repo.saveAssignmentsBatch(
      creates: const [],
      updates: const [],
      deletes: const [],
      eventQuotaSets: const [
        (eventId: 'e1', roleType: 'medic', target: 2, expected: 3),
      ],
    );

    final captured = verify(db.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
      eventQuotaBumps: anyNamed('eventQuotaBumps'),
      eventQuotaSets: captureAnyNamed('eventQuotaSets'),
    )).captured.single as List<EventQuotaSet>;
    expect(captured.single.target, 2);
    expect(captured.single.expected, 3);
  });
}
