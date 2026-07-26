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

    test('an out-of-range note is NOT surfaced on another gap (no drift)', () {
      // a0 stored at index 2, but quota is 2 so slot 2 no longer exists. It does
      // NOT drift onto a free gap — it belongs to slot 2, which is gone, so it
      // surfaces nowhere (and computeSlotAnnotationNormalization deletes it).
      final res = reconcileGapAnnotations({'medic#2': a0}, 'medic', 2, {});
      expect(res, isEmpty);
    });

    test('a note on an in-quota FILLED slot stays dormant (does not surface on another gap)', () {
      // a0 stored at index 0 which is FILLED → dormant carry-back copy for that
      // slot; must NOT re-home onto the empty gap at index 1.
      final res = reconcileGapAnnotations({'medic#0': a0}, 'medic', 2, {0});
      expect(res, isEmpty);
    });

    test('each note maps to its own gap by exact index', () {
      final res = reconcileGapAnnotations(
        {'medic#0': a0, 'medic#2': a2}, 'medic', 3, {1});
      // gaps = [0,2]; a0 exact→0, a2 exact→2
      expect(res[0]!.annotation, a0);
      expect(res[2]!.annotation, a2);
    });

    test('out-of-range notes never fill lower gaps (no drift)', () {
      const a = SlotAnnotation(note: 'a', labelId: 'L');
      const b = SlotAnnotation(note: 'b');
      // Quota 3 (gaps [0,1,2], none filled); both stored indices (5,7) are
      // out-of-range. They belong to slots 5/7, which don't exist, so they
      // surface on NO gap — a note never drifts down onto a free lower slot.
      final res = reconcileGapAnnotations(
          {'medic#7': b, 'medic#5': a}, 'medic', 3, {});
      expect(res, isEmpty);
    });
  });

  group('computeSlotAnnotationNormalization', () {
    const a = SlotAnnotation(note: 'a', labelId: 'L');
    const b = SlotAnnotation(note: 'b');

    test('an out-of-range note is DELETED, not re-keyed onto a free gap', () {
      // medic#1 with quota 1: slot 1 is gone. It is deleted from the DB (a note
      // belongs to its slot) rather than drifting onto the free medic#0.
      final writes = computeSlotAnnotationNormalization(
          {'medic#1': a}, 'medic', 1, {});
      expect(writes, [(key: 'medic#1', value: null, staleKey: null)]);
    });

    test('orphan delete: a note with no surviving gap is deleted', () {
      final writes = computeSlotAnnotationNormalization(
          {'medic#0': a, 'medic#1': b}, 'medic', 1, {});
      expect(writes, [(key: 'medic#1', value: null, staleKey: null)]);
    });

    test('dormant-on-filled note is kept untouched (no-op)', () {
      final writes = computeSlotAnnotationNormalization(
          {'medic#0': a}, 'medic', 2, {0});
      expect(writes, isEmpty);
    });

    test('no drift, no orphan: nothing to do (no-op)', () {
      final writes = computeSlotAnnotationNormalization(
          {'medic#0': a, 'medic#1': b}, 'medic', 2, {});
      expect(writes, isEmpty);
    });

    test('out-of-range annotation is deleted (even with a free lower gap)', () {
      // medic#2 with quota 2: gaps [0,1] are free, but the note belongs to the
      // now-gone slot 2, so it is deleted rather than drifting onto medic#0.
      final writes = computeSlotAnnotationNormalization(
          {'medic#2': a}, 'medic', 2, {});
      expect(writes, [(key: 'medic#2', value: null, staleKey: null)]);
    });

    test('multiple out-of-range notes are ALL deleted (none drift down)', () {
      // Quota shrunk to 1 (only gap 0 survives); both medic#2 and medic#3 are
      // out-of-range. Neither drifts onto the free medic#0 — both are deleted.
      final ops = computeSlotAnnotationNormalization(
          {'medic#3': b, 'medic#2': a}, 'medic', 1, {});
      expect(ops, unorderedEquals([
        (key: 'medic#2', value: null, staleKey: null),
        (key: 'medic#3', value: null, staleKey: null),
      ]));
    });

    test('quota 0 deletes every stored note for the role', () {
      // requiredCount 0 → no valid slots at all → every stored note for the
      // role is a true orphan (there is no gap it could ever drift onto).
      final ops =
          computeSlotAnnotationNormalization({'medic#0': a}, 'medic', 0, {});
      expect(ops, [(key: 'medic#0', value: null, staleKey: null)]);
    });

    test('annotations of other roles are ignored', () {
      final writes = computeSlotAnnotationNormalization(
          {'guard#0': a}, 'medic', 1, {});
      expect(writes, isEmpty);
    });
  });

  // Model B (visual-order-preserving): a note shifts up purely by the number of
  // deleted rows BELOW it — the SAME mapping the assignment reindex uses — so it
  // needs no filled/empty distinction and can never collide onto a filled slot.
  // The filled+empty INTERACTION (rows and their notes moving in lockstep) is
  // verified end-to-end in assignment_bloc_staging_test.dart.
  group('computeNoteReindexAfterDeletion', () {
    const nA = SlotAnnotation(note: 'A');
    const nB = SlotAnnotation(note: 'B');
    const nC = SlotAnnotation(note: 'C');

    test('delete the FIRST of two rows: the 2nd note shifts up to row 0', () {
      // The reported bug: [row0="123", row1="456"], swipe-delete row 0 -> keep
      // "456" on the single remaining row.
      final writes = computeNoteReindexAfterDeletion(
          {'medic#0': nA, 'medic#1': nB}, 'medic', 2, {0});
      expect(writes, unorderedEquals([
        (key: 'medic#0', value: nB, staleKey: null),
        (key: 'medic#1', value: null, staleKey: null),
      ]));
    });

    test('delete the LAST of two rows: the 1st note stays put', () {
      final writes = computeNoteReindexAfterDeletion(
          {'medic#0': nA, 'medic#1': nB}, 'medic', 2, {1});
      expect(writes, [(key: 'medic#1', value: null, staleKey: null)]);
    });

    test('delete a MIDDLE row of three: rows below shift up', () {
      // [A,B,C] delete row 1 -> [A,C]
      final writes = computeNoteReindexAfterDeletion(
          {'medic#0': nA, 'medic#1': nB, 'medic#2': nC}, 'medic', 3, {1});
      expect(writes, unorderedEquals([
        (key: 'medic#1', value: nC, staleKey: null),
        (key: 'medic#2', value: null, staleKey: null),
      ]));
    });

    test('delete the FIRST of three rows: both below shift up', () {
      // [A,B,C] delete row 0 -> [B,C]
      final writes = computeNoteReindexAfterDeletion(
          {'medic#0': nA, 'medic#1': nB, 'medic#2': nC}, 'medic', 3, {0});
      expect(writes, unorderedEquals([
        (key: 'medic#0', value: nB, staleKey: null),
        (key: 'medic#1', value: nC, staleKey: null),
        (key: 'medic#2', value: null, staleKey: null),
      ]));
    });

    test('delete TWO rows at once: survivors compact', () {
      // [A,B,C] delete rows 0 and 1 -> [C]
      final writes = computeNoteReindexAfterDeletion(
          {'medic#0': nA, 'medic#1': nB, 'medic#2': nC}, 'medic', 3, {0, 1});
      expect(writes, unorderedEquals([
        (key: 'medic#0', value: nC, staleKey: null),
        (key: 'medic#1', value: null, staleKey: null),
        (key: 'medic#2', value: null, staleKey: null),
      ]));
    });

    test('delete an EMPTY row (no note) above a noted row: the note shifts up',
        () {
      // row 0 empty, row 1 = B; delete row 0 -> [B].
      final writes = computeNoteReindexAfterDeletion(
          {'medic#1': nB}, 'medic', 2, {0});
      expect(writes, unorderedEquals([
        (key: 'medic#0', value: nB, staleKey: null),
        (key: 'medic#1', value: null, staleKey: null),
      ]));
    });

    test('delete a noted row whose only survivor is empty: the note is dropped',
        () {
      // row 0 = A, row 1 empty; delete row 0 -> [] (A gone, nothing to shift).
      final writes = computeNoteReindexAfterDeletion(
          {'medic#0': nA}, 'medic', 2, {0});
      expect(writes, [(key: 'medic#0', value: null, staleKey: null)]);
    });

    test('delete an EMPTY last row (no notes disturbed): no writes', () {
      final writes = computeNoteReindexAfterDeletion(
          {'medic#0': nA}, 'medic', 2, {1});
      expect(writes, isEmpty);
    });

    test('no deletions → no writes', () {
      final writes = computeNoteReindexAfterDeletion(
          {'medic#0': nA, 'medic#1': nB}, 'medic', 2, {});
      expect(writes, isEmpty);
    });

    test(
        'a note shifts up regardless of a filled row between it and the '
        'deletion (filled/empty is irrelevant to the note math under Model B)',
        () {
      // [empty+A@0, filled@1 (no note), empty+C@2] delete row 0: A dropped,
      // C shifts 2 -> 1 (following its row up past the filled row).
      final writes = computeNoteReindexAfterDeletion(
          {'medic#0': nA, 'medic#2': nC}, 'medic', 3, {0});
      expect(writes, unorderedEquals([
        (key: 'medic#0', value: null, staleKey: null), // A dropped
        (key: 'medic#1', value: nC, staleKey: null), // C shifts up to 1
        (key: 'medic#2', value: null, staleKey: null), // old C slot cleared
      ]));
    });

    // stagedByIndex: the layout that shifts is what the ADMIN SEES (DB overlaid
    // with notes staged in the same batch), while the writes are still diffed
    // against the stored map. Without this the repack was blind to a staged
    // note, which then got written at its pre-shift key.
    group('with staged (unsaved) notes overlaid', () {
      test('a note staged ABOVE the deletion shifts down into the freed row',
          () {
        // Stored [A@0, B@1], staged C@2, delete row 1 -> [A, C].
        final writes = computeNoteReindexAfterDeletion(
            {'medic#0': nA, 'medic#1': nB}, 'medic', 3, {1},
            stagedByIndex: {2: nC});
        expect(writes, unorderedEquals([
          (key: 'medic#1', value: nC, staleKey: null),
        ]));
      });

      test('a note staged ON the deleted row is dropped with it', () {
        // Stored [B@1, C@2], staged A@0, delete row 0 -> [B, C].
        final writes = computeNoteReindexAfterDeletion(
            {'medic#1': nB, 'medic#2': nC}, 'medic', 3, {0},
            stagedByIndex: {0: nA});
        expect(writes, unorderedEquals([
          (key: 'medic#0', value: nB, staleKey: null),
          (key: 'medic#1', value: nC, staleKey: null),
          (key: 'medic#2', value: null, staleKey: null),
        ]));
      });

      test('a staged DELETE (null) hides the stored note it overlays', () {
        // Stored [A@0, B@1]; the admin staged "clear row 0" AND deleted row 1.
        // Layout pre-deletion is [(none), B]; after -> [(none)] so A is cleared.
        final writes = computeNoteReindexAfterDeletion(
            {'medic#0': nA, 'medic#1': nB}, 'medic', 2, {1},
            stagedByIndex: {0: null});
        expect(writes, unorderedEquals([
          (key: 'medic#0', value: null, staleKey: null),
          (key: 'medic#1', value: null, staleKey: null),
        ]));
      });

      test('a staged note equal to the stored one produces no extra write', () {
        // Stored [A@0, B@1], staged A@0 again (re-typed identically), delete
        // row 1 -> [A]: only the freed top slot is cleared.
        final writes = computeNoteReindexAfterDeletion(
            {'medic#0': nA, 'medic#1': nB}, 'medic', 2, {1},
            stagedByIndex: {0: nA});
        expect(writes, [(key: 'medic#1', value: null, staleKey: null)]);
      });

      test('an empty-note staged value is treated as "no note"', () {
        final writes = computeNoteReindexAfterDeletion(
            {'medic#0': nA}, 'medic', 2, {1},
            stagedByIndex: {0: const SlotAnnotation(note: '')});
        expect(writes, [(key: 'medic#0', value: null, staleKey: null)]);
      });
    });
  });
}
