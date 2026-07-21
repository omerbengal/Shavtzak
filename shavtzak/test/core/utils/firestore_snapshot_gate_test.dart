import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/firestore_snapshot_gate.dart';

void main() {
  group('shouldEmitFirestoreSnapshot', () {
    test('skips the cold-start empty-from-cache snapshot', () {
      expect(
        shouldEmitFirestoreSnapshot(isFromCache: true, isEmpty: true),
        isFalse,
      );
    });

    test('forwards a non-empty cache snapshot (warm cache shows immediately)', () {
      expect(
        shouldEmitFirestoreSnapshot(isFromCache: true, isEmpty: false),
        isTrue,
      );
    });

    test('forwards a genuinely-empty server snapshot', () {
      expect(
        shouldEmitFirestoreSnapshot(isFromCache: false, isEmpty: true),
        isTrue,
      );
    });

    test('forwards a non-empty server snapshot', () {
      expect(
        shouldEmitFirestoreSnapshot(isFromCache: false, isEmpty: false),
        isTrue,
      );
    });
  });
}
