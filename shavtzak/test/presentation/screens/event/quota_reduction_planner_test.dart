// The quota-reduction victim ladder: a reduction always spends the cheapest
// rows first — clean, then noted (admin chooses), then assigned (existing
// dialog chooses). Resolving it at event-form save time is what stops a
// reduction from ever stranding a note (see AssignmentBloc's out-of-quota note
// row, now only a safety net for orphans arriving some other way).

import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';
import 'package:shavtzak/presentation/screens/event/quota_reduction_planner.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  Assignment assignment(int slotIndex, {String roleType = 'medic'}) =>
      Assignment(
        id: 'a$slotIndex',
        eventId: 'e1',
        teamMemberId: 'm$slotIndex',
        roleType: roleType,
        slotIndex: slotIndex,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: now,
        updatedAt: now,
      );

  List<QuotaRow> rowsOf({
    int quota = 4,
    List<Assignment> assignments = const [],
    Map<String, SlotAnnotation> stored = const {},
    Set<int> stagedIndices = const {},
    Map<int, SlotAnnotation> stagedValues = const {},
  }) =>
      classifyRoleRows(
        roleKey: 'medic',
        quota: quota,
        assignments: assignments,
        slotAnnotations: stored,
        stagedNoteIndices: stagedIndices,
        stagedNoteValues: stagedValues,
      );

  RoleReductionPlan planOf(List<QuotaRow> rows, int oldQuota, int newQuota) =>
      planRoleQuotaReduction(
        roleKey: 'medic',
        oldQuota: oldQuota,
        newQuota: newQuota,
        rows: rows,
      );

  group('classifyRoleRows', () {
    test('an empty slot with nothing on it is clean', () {
      final rows = rowsOf(quota: 2);
      expect(rows.map((r) => r.kind),
          [QuotaRowKind.clean, QuotaRowKind.clean]);
    });

    test('a stored note makes the row noted', () {
      final rows = rowsOf(
          quota: 2, stored: {'medic#1': const SlotAnnotation(note: 'A')});
      expect(rows[0].kind, QuotaRowKind.clean);
      expect(rows[1].kind, QuotaRowKind.noted);
      expect(rows[1].annotation!.note, 'A');
      expect(rows[1].annotationIsStaged, isFalse);
    });

    test('an UNSAVED staged note also makes the row noted', () {
      // The whole point of question 1: a note typed but not yet saved must not
      // be binned silently by a quota reduction.
      final rows = rowsOf(
        quota: 2,
        stagedIndices: {1},
        stagedValues: {1: const SlotAnnotation(note: 'draft')},
      );
      expect(rows[1].kind, QuotaRowKind.noted);
      expect(rows[1].annotation!.note, 'draft');
      expect(rows[1].annotationIsStaged, isTrue);
    });

    test('a staged edit shadows the stored note (that is what is on screen)',
        () {
      final rows = rowsOf(
        quota: 2,
        stored: {'medic#1': const SlotAnnotation(note: 'old')},
        stagedIndices: {1},
        stagedValues: {1: const SlotAnnotation(note: 'new')},
      );
      expect(rows[1].annotation!.note, 'new');
      expect(rows[1].annotationIsStaged, isTrue);
    });

    test('a staged CLEAR of a stored note makes the row clean again', () {
      // The admin already asked for that note to go — no need to prompt.
      final rows = rowsOf(
        quota: 2,
        stored: {'medic#1': const SlotAnnotation(note: 'old')},
        stagedIndices: {1}, // staged with no value == delete
      );
      expect(rows[1].kind, QuotaRowKind.clean);
    });

    test('an assigned slot is assigned even if it carries a dormant note', () {
      final rows = rowsOf(
        quota: 2,
        assignments: [assignment(1)],
        stored: {'medic#1': const SlotAnnotation(note: 'dormant')},
      );
      expect(rows[1].kind, QuotaRowKind.assigned);
    });

    test('an empty-string note does not count as a note', () {
      final rows =
          rowsOf(quota: 1, stored: {'medic#0': const SlotAnnotation(note: '')});
      expect(rows[0].kind, QuotaRowKind.clean);
    });
  });

  group('planRoleQuotaReduction — rung 1 (clean rows, silent)', () {
    test('a single clean row absorbs the reduction with no prompt', () {
      final plan = planOf(rowsOf(quota: 4), 4, 3);
      expect(plan.isSilent, isTrue);
      expect(plan.autoDeletedIndices, {3}); // highest clean row
      expect(plan.notedToRemove, 0);
      expect(plan.assignmentsToRemove, 0);
    });

    test('clean rows are spent HIGHEST first, so survivors do not move', () {
      final plan = planOf(rowsOf(quota: 4), 4, 2);
      expect(plan.autoDeletedIndices, {3, 2});
    });

    test('a clean row is preferred over a noted one even when it sits lower',
        () {
      // rows: 0 clean, 1 noted, 2 noted, 3 clean -> removing 1 takes row 3.
      final rows = rowsOf(quota: 4, stored: {
        'medic#1': const SlotAnnotation(note: 'A'),
        'medic#2': const SlotAnnotation(note: 'B'),
      });
      final plan = planOf(rows, 4, 3);
      expect(plan.isSilent, isTrue);
      expect(plan.autoDeletedIndices, {3});
    });

    test('clean rows are preferred over assignments', () {
      final rows = rowsOf(quota: 3, assignments: [assignment(0)]);
      final plan = planOf(rows, 3, 2);
      expect(plan.isSilent, isTrue);
      expect(plan.autoDeletedIndices, {2});
      expect(plan.assignmentsToRemove, 0);
    });

    test('no reduction at all is a no-op', () {
      final plan = planOf(rowsOf(quota: 3), 3, 3);
      expect(plan.isSilent, isTrue);
      expect(plan.autoDeletedIndices, isEmpty);
    });
  });

  group('planRoleQuotaReduction — rung 2 (noted rows, admin chooses)', () {
    test('with no clean rows left, the admin picks which noted row goes', () {
      final rows = rowsOf(quota: 2, stored: {
        'medic#0': const SlotAnnotation(note: 'A'),
        'medic#1': const SlotAnnotation(note: 'B'),
      });
      final plan = planOf(rows, 2, 1);
      expect(plan.needsNoteChoice, isTrue);
      expect(plan.notedToRemove, 1);
      expect(plan.notedCandidates.map((r) => r.slotIndex), [0, 1]);
      expect(plan.autoDeletedIndices, isEmpty);
      expect(plan.assignmentsToRemove, 0);
    });

    test('clean rows are spent first, then the remainder is chosen', () {
      // rows: 0 noted, 1 noted, 2 clean. Remove 2 -> row 2 auto, choose 1 note.
      final rows = rowsOf(quota: 3, stored: {
        'medic#0': const SlotAnnotation(note: 'A'),
        'medic#1': const SlotAnnotation(note: 'B'),
      });
      final plan = planOf(rows, 3, 1);
      expect(plan.autoDeletedIndices, {2});
      expect(plan.notedToRemove, 1);
      expect(plan.notedCandidates.map((r) => r.slotIndex), [0, 1]);
    });

    test('a STAGED note is a candidate like any other', () {
      final rows = rowsOf(
        quota: 2,
        stored: {'medic#0': const SlotAnnotation(note: 'saved')},
        stagedIndices: {1},
        stagedValues: {1: const SlotAnnotation(note: 'draft')},
      );
      final plan = planOf(rows, 2, 1);
      expect(plan.needsNoteChoice, isTrue);
      expect(plan.notedCandidates.map((r) => r.annotation!.note),
          ['saved', 'draft']);
      expect(plan.notedCandidates.last.annotationIsStaged, isTrue);
    });

    test('every noted row goes when the role is zeroed out', () {
      final rows = rowsOf(quota: 2, stored: {
        'medic#0': const SlotAnnotation(note: 'A'),
        'medic#1': const SlotAnnotation(note: 'B'),
      });
      final plan = planOf(rows, 2, 0);
      expect(plan.notedToRemove, 2);
      expect(plan.notedCandidates, hasLength(2));
    });
  });

  group('planRoleQuotaReduction — rung 3 (assignments, existing dialog)', () {
    test('every empty row is consumed and the assignments are delegated', () {
      // rows: 0 assigned, 1 assigned, 2 clean, 3 noted. 4 -> 1 means one
      // assignment must also go.
      final rows = rowsOf(
        quota: 4,
        assignments: [assignment(0), assignment(1)],
        stored: {'medic#3': const SlotAnnotation(note: 'A')},
      );
      final plan = planOf(rows, 4, 1);
      expect(plan.needsAssignmentChoice, isTrue);
      expect(plan.assignmentsToRemove, 1);
      // Both empties go regardless — that is WHY an assignment has to.
      expect(plan.autoDeletedIndices, {2, 3});
      // ...so there is nothing left for the admin to choose between.
      expect(plan.needsNoteChoice, isFalse);
    });

    test('assignments are only touched once every empty row is spent', () {
      final rows = rowsOf(
        quota: 3,
        assignments: [assignment(0)],
        stored: {'medic#2': const SlotAnnotation(note: 'A')},
      );
      // 3 -> 1: rows 1 (clean) and 2 (noted) cover it; the assignment survives.
      final plan = planOf(rows, 3, 1);
      expect(plan.assignmentsToRemove, 0);
      expect(plan.autoDeletedIndices, {1});
      expect(plan.notedToRemove, 1);
    });
  });

  group('shiftedSlotIndex (Model B)', () {
    test('rows below the deletion do not move', () {
      expect(shiftedSlotIndex(0, {2}), 0);
      expect(shiftedSlotIndex(1, {2}), 1);
    });

    test('rows above shift up by the number deleted below them', () {
      expect(shiftedSlotIndex(3, {2}), 2);
      expect(shiftedSlotIndex(5, {1, 3}), 3);
    });

    test('deleting the bottom row moves nothing', () {
      expect(shiftedSlotIndex(0, {3}), 0);
      expect(shiftedSlotIndex(2, {3}), 2);
    });
  });
}
