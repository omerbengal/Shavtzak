import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/services/backend_api_service.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/data/repositories/user_selection_repository.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/domain/entities/vehicle_info.dart';

import 'user_selection_snapshot_test.mocks.dart';

/// A returning member's first screen paints from the snapshot this device
/// kept of them, without a backend round-trip; the backend confirms the
/// session afterwards. The snapshot must therefore come back exactly as saved,
/// belong to the signed-in Firebase user, and go away on sign-out.
@GenerateMocks([FirebaseAuth, User, DatabaseInterface, BackendApiService])
void main() {
  late MockFirebaseAuth auth;
  late MockUser firebaseUser;
  late MockDatabaseInterface database;
  late MockBackendApiService backend;
  late UserCacheService cache;
  late UserSelectionRepository repository;

  final member = TeamMember(
    id: 'member-1',
    name: 'עומר',
    isActive: true,
    isAdmin: true,
    constraints: [
      DateConstraint(
        id: 'c1',
        startDate: DateTime.utc(2026, 10, 1),
        endDate: DateTime.utc(2026, 10, 3),
        note: 'חופשה',
        status: ConstraintStatus.approved,
        constraintType: ConstraintType.unavailability,
      ),
    ],
    roleCapabilities: const {},
    createdAt: DateTime.utc(2025, 1, 1, 8),
    updatedAt: DateTime.utc(2026, 10, 19, 12, 30),
    uniqueKey: 'key-member-1',
    phoneNumber: '0500000000',
    birthday: DateTime.utc(1990, 5, 17),
    canManageTasks: true,
    vehicleInfo: const VehicleInfo(
      vehicleNumber: '12-345-67',
      manufacturer: 'טויוטה',
      model: 'קורולה',
      color: 'לבן',
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = MockFirebaseAuth();
    firebaseUser = MockUser();
    database = MockDatabaseInterface();
    backend = MockBackendApiService();
    cache = UserCacheService();
    when(auth.currentUser).thenReturn(firebaseUser);
    when(firebaseUser.uid).thenReturn('member-1');
    when(auth.signOut()).thenAnswer((_) async {});
    when(backend.signOut()).thenAnswer((_) async {});
    repository = UserSelectionRepository(
      database: database,
      userCacheService: cache,
      backendApiService: backend,
      firebaseAuth: auth,
    );
  });

  test('a saved member comes back exactly as saved', () async {
    await repository.saveMemberSnapshot(member);
    expect(await repository.restoreFromSnapshot(), member);
  });

  test('nothing is restored without a snapshot', () async {
    expect(await repository.restoreFromSnapshot(), isNull);
  });

  test('nothing is restored without a Firebase session', () async {
    await repository.saveMemberSnapshot(member);
    when(auth.currentUser).thenReturn(null);
    expect(await repository.restoreFromSnapshot(), isNull);
  });

  test("another member's snapshot is not restored", () async {
    await repository.saveMemberSnapshot(member);
    when(firebaseUser.uid).thenReturn('member-2');
    expect(await repository.restoreFromSnapshot(), isNull);
  });

  test('an unreadable snapshot is ignored', () async {
    await cache.saveMemberSnapshot('{not json');
    expect(await repository.restoreFromSnapshot(), isNull);
  });

  test('signing out removes the snapshot', () async {
    await repository.saveMemberSnapshot(member);
    await repository.clearUserSelection();
    expect(await cache.getMemberSnapshot(), isNull);
  });

  test('the snapshot never holds a passcode', () async {
    await repository.saveMemberSnapshot(member.copyWith(passcode: '071023'));
    expect(await cache.getMemberSnapshot(), isNot(contains('071023')));
  });

  group('revalidateSession', () {
    test('returns the stored member and refreshes the snapshot', () async {
      final renamed = member.copyWith(name: 'עומר ב');
      when(backend.validateSession()).thenAnswer((_) async => {'ok': true});
      when(database.getTeamMemberById('member-1'))
          .thenAnswer((_) async => renamed);

      expect(await repository.revalidateSession(), renamed);
      expect(await repository.restoreFromSnapshot(), renamed);
    });

    test('returns null when the member is gone', () async {
      when(backend.validateSession()).thenAnswer((_) async => {'ok': true});
      when(database.getTeamMemberById('member-1'))
          .thenAnswer((_) async => null);
      expect(await repository.revalidateSession(), isNull);
    });

    test('lets a network failure through without clearing anything',
        () async {
      await repository.saveMemberSnapshot(member);
      when(backend.validateSession()).thenThrow(const BackendApiException(
        BackendApiService.networkErrorMessage,
        isNetworkError: true,
      ));
      await expectLater(
          repository.revalidateSession(), throwsA(isA<BackendApiException>()));
      expect(await repository.restoreFromSnapshot(), member);
    });
  });

  test('only a 401 or 403 answer counts as a refused session', () {
    bool definitive(Object e) =>
        UserSelectionRepository.isDefinitiveSessionFailure(e);
    expect(definitive(const BackendApiException('x', statusCode: 401)), isTrue);
    expect(definitive(const BackendApiException('x', statusCode: 403)), isTrue);
    expect(definitive(const BackendApiException('x', statusCode: 500)), isFalse);
    expect(
        definitive(const BackendApiException('x', isNetworkError: true)),
        isFalse);
    expect(definitive(Exception('firestore')), isFalse);
  });
}
