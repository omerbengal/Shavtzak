import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';

void main() {
  group('SlotAnnotation', () {
    test('isEmpty is true only when note is blank AND labelId is null', () {
      expect(const SlotAnnotation().isEmpty, isTrue);
      expect(const SlotAnnotation(note: '  ').isEmpty, isTrue);
      expect(const SlotAnnotation(note: 'x').isEmpty, isFalse);
      expect(const SlotAnnotation(labelId: 'L1').isEmpty, isFalse);
    });

    test('value equality via Equatable', () {
      expect(const SlotAnnotation(note: 'a', labelId: 'L1'),
          const SlotAnnotation(note: 'a', labelId: 'L1'));
      expect(const SlotAnnotation(note: 'a'),
          isNot(const SlotAnnotation(note: 'b')));
    });

    test('copyWith can clear labelId via the nullable setter', () {
      const a = SlotAnnotation(note: 'a', labelId: 'L1');
      expect(a.copyWith(labelId: () => null).labelId, isNull);
      expect(a.copyWith(note: 'b').labelId, 'L1'); // unchanged when omitted
    });

    test('JSON round-trips', () {
      const a = SlotAnnotation(note: 'ערב', labelId: 'L2');
      expect(SlotAnnotation.fromJson(a.toJson()), a);
      expect(SlotAnnotation.fromJson(const {'note': 'x'}),
          const SlotAnnotation(note: 'x'));
      expect(SlotAnnotation.fromJson(const {}), const SlotAnnotation());
    });
  });
}
