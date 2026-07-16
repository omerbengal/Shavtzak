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

    verify(db.saveAssignmentsBatch(
      creates: argThat(hasLength(1), named: 'creates'),
      updates: argThat(hasLength(1), named: 'updates'),
      deletes: ['d1'],
    )).called(1);
  });
}
