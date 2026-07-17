import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns empty list when nothing cached', () async {
    expect(await UserCacheService().getPendingAssignmentChanges(), isEmpty);
  });

  test('round-trips a list of change maps', () async {
    final service = UserCacheService();
    final changes = [
      {'slotKey': 'e1_medic_0', 'desiredMemberId': 'm2', 'slotIndex': 0},
      {'slotKey': 'e1_medic_1', 'desiredMemberId': null, 'slotIndex': 1},
    ];
    await service.savePendingAssignmentChanges(changes);
    expect(await service.getPendingAssignmentChanges(), changes);
  });

  test('clear removes the cached changes', () async {
    final service = UserCacheService();
    await service.savePendingAssignmentChanges([
      {'slotKey': 'e1_medic_0'}
    ]);
    await service.clearPendingAssignmentChanges();
    expect(await service.getPendingAssignmentChanges(), isEmpty);
  });
}
