import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/bloc/assignment/models/staged_assignment_change.dart';

void main() {
  StagedAssignmentChange fill() => StagedAssignmentChange(
        slotKey: 'e1_medic_0',
        eventId: 'e1',
        roleType: 'medic',
        slotIndex: 0,
        desiredMemberId: 'm2',
        desiredNotes: '',
        desiredSemanticLabelId: null,
        desiredAltPhone: null,
        baselineAssignmentId: null,
        baselineMemberId: null,
        baselineNotes: '',
        baselineSemanticLabelId: null,
        baselineAltPhone: null,
        desiredAssignmentId: 'new-a1',
        stagedAtMillis: 1000,
      );

  test('slotKeyFor composes the canonical key', () {
    expect(StagedAssignmentChange.slotKeyFor('e1', 'medic', 0), 'e1_medic_0');
  });

  test('isClear is true only when desiredMemberId is null', () {
    expect(fill().isClear, isFalse);
    expect(fill().copyWith(desiredMemberId: () => null).isClear, isTrue);
  });

  test('matchesBaseline detects a revert to the original DB state', () {
    // fill over an empty slot never matches its (empty) baseline
    expect(fill().matchesBaseline, isFalse);
    // a swap back to the same member + same notes DOES match baseline
    final swap = fill().copyWith(
      baselineAssignmentId: () => 'a1',
      baselineMemberId: () => 'm2',
      desiredMemberId: () => 'm2',
    );
    expect(swap.matchesBaseline, isTrue);
  });

  test('toJson/fromJson round-trips every field', () {
    final original = fill();
    final restored = StagedAssignmentChange.fromJson(original.toJson());
    expect(restored, original);
  });
}
