import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';

// The generated mocks of the reconcile test already hold MockDatabaseInterface
// and MockDriveService; reuse them rather than generating a second copy.
import 'event_repository_reconcile_test.mocks.dart';

/// Duplicating an event sends its batch with `bypassAvailability`: the admin
/// reviewed the dialog's list, so the backend must not overrule what they
/// chose to keep.
void main() {
  late MockDatabaseInterface db;
  late MockDriveService drive;
  late EventRepository repo;

  final original = _event('original', DateTime(2026, 11, 3));
  final copy = _event('copy', DateTime(2026, 11, 10));

  setUp(() {
    db = MockDatabaseInterface();
    drive = MockDriveService();
    repo = EventRepository(db, driveService: drive);
    when(drive.isInitialized).thenReturn(false);
    when(db.insertEvent(any)).thenAnswer((_) async {});
    when(db.insertAssignmentsBatch(
      any,
      bypassAvailability: anyNamed('bypassAvailability'),
    )).thenAnswer((_) async {});
  });

  test('duplicateEvent sends the batch with bypassAvailability', () async {
    await repo.duplicateEvent(original, copy, [_assignment('a1', 'm1')]);

    verify(db.insertAssignmentsBatch(any, bypassAvailability: true))
        .called(1);
  });

  test('duplicateEvent copies every assignment onto the new event', () async {
    await repo.duplicateEvent(
        original, copy, [_assignment('a1', 'm1'), _assignment('a2', 'm2')]);

    final sent = verify(db.insertAssignmentsBatch(
      captureAny,
      bypassAvailability: true,
    )).captured.single as List<Assignment>;
    expect(sent.map((a) => a.teamMemberId), ['m1', 'm2']);
    expect(sent.every((a) => a.eventId == copy.id), isTrue);
  });

  test('duplicateEventWithAssignmentIds sends the batch with '
      'bypassAvailability', () async {
    final idMap = await repo
        .duplicateEventWithAssignmentIds(original, copy, [_assignment('a1', 'm1')]);

    verify(db.insertAssignmentsBatch(any, bypassAvailability: true))
        .called(1);
    expect(idMap.keys, ['a1']);
    expect(idMap['a1']!.eventId, copy.id);
  });
}

Assignment _assignment(String id, String memberId) {
  final now = DateTime(2026, 10, 1);
  return Assignment(
    id: id,
    eventId: 'original',
    teamMemberId: memberId,
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
  );
}

Event _event(String id, DateTime day) {
  final now = DateTime(2026, 10, 1);
  return Event(
    id: id,
    name: 'אירוע',
    startDate: day,
    endDate: day,
    startTime: '19:00',
    endTime: '22:00',
    assemblyTime: '18:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 2},
    createdAt: now,
    updatedAt: now,
  );
}
