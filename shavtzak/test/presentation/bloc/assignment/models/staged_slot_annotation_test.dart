import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';
import 'package:shavtzak/presentation/bloc/assignment/models/staged_slot_annotation.dart';

void main() {
  group('StagedSlotAnnotation', () {
    const a = SlotAnnotation(note: 'x', labelId: 'L');
    StagedSlotAnnotation make({SlotAnnotation? desired, SlotAnnotation? baseline, String? staleKey}) =>
        StagedSlotAnnotation(
          eventId: 'e1', roleType: 'medic', slotIndex: 0,
          desired: desired, baseline: baseline, staleKey: staleKey);

    test('isNoop when desired == baseline and no staleKey', () {
      expect(make(desired: a, baseline: a).isNoop, isTrue);
      expect(make(desired: null, baseline: null).isNoop, isTrue);
      expect(make(desired: a, baseline: null).isNoop, isFalse);
      expect(make(desired: a, baseline: a, staleKey: 'medic#1').isNoop, isFalse); // a move is never a noop
    });

    test('isContentNoop ignores staleKey (a pure re-key IS a content noop)', () {
      expect(make(desired: a, baseline: a).isContentNoop, isTrue);
      expect(make(desired: null, baseline: null).isContentNoop, isTrue);
      expect(make(desired: a, baseline: null).isContentNoop, isFalse);
      // Unlike isNoop: content unchanged but a stale-key move is still a
      // content noop — the user changed nothing (this is what stops a drifted
      // note from lighting up dirty on an unchanged reopen+Save).
      expect(
          make(desired: a, baseline: a, staleKey: 'medic#1').isContentNoop, isTrue);
    });

    test('JSON round-trips (incl. null desired = delete)', () {
      final s = make(desired: null, baseline: a, staleKey: 'medic#1');
      expect(StagedSlotAnnotation.fromJson(s.toJson()), s);
      final t = make(desired: a, baseline: null);
      expect(StagedSlotAnnotation.fromJson(t.toJson()), t);
    });
  });
}
