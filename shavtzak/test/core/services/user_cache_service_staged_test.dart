import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns null when nothing cached', () async {
    expect(await UserCacheService().getPendingAssignmentChanges(), isNull);
  });

  test(
      'round-trips a JSON payload string (Task 12: a wrapper object carrying '
      'changes + baselineQuota, not a bare list)', () async {
    final service = UserCacheService();
    final payload = jsonEncode({
      'changes': [
        {'slotKey': 'e1_medic_0', 'desiredMemberId': 'm2', 'slotIndex': 0},
        {'slotKey': 'e1_medic_1', 'desiredMemberId': null, 'slotIndex': 1},
      ],
      'baselineQuota': {'e1_medic': 2},
    });
    await service.savePendingAssignmentChanges(payload);
    expect(await service.getPendingAssignmentChanges(), payload);
  });

  test('clear removes the cached changes', () async {
    final service = UserCacheService();
    await service.savePendingAssignmentChanges(jsonEncode({
      'changes': [
        {'slotKey': 'e1_medic_0'}
      ],
      'baselineQuota': {},
    }));
    await service.clearPendingAssignmentChanges();
    expect(await service.getPendingAssignmentChanges(), isNull);
  });
}
