import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';

void main() {
  test('a persistent operation never expires', () {
    final op = PendingOperation(
      id: 'op1',
      type: PendingOperationType.createAssignment,
      slotKey: 'e1_medic_0',
      timestamp: DateTime(2000), // ancient
      persistent: true,
    );
    expect(op.isExpired, isFalse);
  });

  test('a non-persistent operation still expires after 5 minutes', () {
    final op = PendingOperation(
      id: 'op1',
      type: PendingOperationType.createAssignment,
      slotKey: 'e1_medic_0',
      timestamp: DateTime(2000),
    );
    expect(op.isExpired, isTrue);
  });
}
