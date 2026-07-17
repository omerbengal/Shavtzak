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
    )).thenAnswer((_) async {});
    final repo = AssignmentRepository(db);

    await repo.saveAssignmentsBatch(
      creates: [a('c1')], updates: [a('u1')], deletes: ['d1'],
    );

    final captured = verify(db.saveAssignmentsBatch(
      creates: captureAnyNamed('creates'),
      updates: captureAnyNamed('updates'),
      deletes: captureAnyNamed('deletes'),
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
}
