import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/slot_annotations.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';

void main() {
  group('slotAnnotationKey / parse', () {
    test('builds and parses round-trip', () {
      final key = slotAnnotationKey('entryScreening', 2);
      expect(key, 'entryScreening#2');
      final parsed = parseSlotAnnotationKey(key);
      expect(parsed?.roleKey, 'entryScreening');
      expect(parsed?.slotIndex, 2);
    });
    test('parse rejects malformed keys', () {
      expect(parseSlotAnnotationKey('noindex'), isNull);
      expect(parseSlotAnnotationKey('#3'), isNull);
      expect(parseSlotAnnotationKey('role#'), isNull);
      expect(parseSlotAnnotationKey('role#x'), isNull);
    });
  });

  group('emptySlotIndicesForRole', () {
    test('returns the [0,required) indices not filled, ascending', () {
      expect(emptySlotIndicesForRole(3, {1}), [0, 2]);
      expect(emptySlotIndicesForRole(2, {0, 1}), isEmpty);
      expect(emptySlotIndicesForRole(2, {}), [0, 1]);
    });
  });

  group('reconcileGapAnnotations', () {
    const a0 = SlotAnnotation(note: 'B', labelId: 'L0');
    const a2 = SlotAnnotation(note: 'C', labelId: 'L2');

    test('maps an annotation onto its exact gap index', () {
      final res = reconcileGapAnnotations(
        {'medic#2': a2}, 'medic', 3, {0, 1});
      expect(res[2]!.annotation, a2);
      expect(res[2]!.sourceKey, 'medic#2');
      expect(res.containsKey(0), isFalse);
    });

    test('ignores annotations of other roles and empty ones', () {
      final res = reconcileGapAnnotations(
        {'other#0': a0, 'medic#0': const SlotAnnotation()}, 'medic', 2, {});
      expect(res, isEmpty);
    });

    test('drifted annotation (index now filled) surfaces on a remaining gap', () {
      // a0 stored at index 0, but index 0 is filled → must not vanish; it
      // lands on the first free gap (index 1) so the note stays visible.
      final res = reconcileGapAnnotations({'medic#0': a0}, 'medic', 2, {0});
      expect(res[1]!.annotation, a0);
      expect(res[1]!.sourceKey, 'medic#0');
    });

    test('exact matches win before drifted ones fill leftovers', () {
      final res = reconcileGapAnnotations(
        {'medic#0': a0, 'medic#2': a2}, 'medic', 3, {1});
      // gaps = [0,2]; a0 exact→0, a2 exact→2
      expect(res[0]!.annotation, a0);
      expect(res[2]!.annotation, a2);
    });
  });
}
