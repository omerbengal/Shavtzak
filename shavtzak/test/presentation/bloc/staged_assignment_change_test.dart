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

    // Strengthen: members equal to baseline, but desiredNotes diverges
    final notesDiverge = swap.copyWith(desiredNotes: 'different note');
    expect(notesDiverge.matchesBaseline, isFalse,
        reason: 'should detect diverged notes');

    // Strengthen: members equal to baseline, but desiredSemanticLabelId diverges
    final labelDiverge = StagedAssignmentChange(
      slotKey: 'e1_medic_0',
      eventId: 'e1',
      roleType: 'medic',
      slotIndex: 0,
      desiredMemberId: 'm2',
      desiredNotes: '',
      desiredSemanticLabelId: 'lbl-1', // diverges
      desiredAltPhone: null,
      baselineAssignmentId: 'a1',
      baselineMemberId: 'm2', // matches desired
      baselineNotes: '', // matches desired
      baselineSemanticLabelId: null, // diverges from desired
      baselineAltPhone: null,
      desiredAssignmentId: 'new-a1',
      stagedAtMillis: 1000,
    );
    expect(labelDiverge.matchesBaseline, isFalse,
        reason: 'should detect diverged label');

    // Strengthen: members equal to baseline, but desiredAltPhone diverges
    final altPhoneDiverge = StagedAssignmentChange(
      slotKey: 'e1_medic_0',
      eventId: 'e1',
      roleType: 'medic',
      slotIndex: 0,
      desiredMemberId: 'm2',
      desiredNotes: '',
      desiredSemanticLabelId: null,
      desiredAltPhone: '050-1234567', // diverges
      baselineAssignmentId: 'a1',
      baselineMemberId: 'm2', // matches desired
      baselineNotes: '', // matches desired
      baselineSemanticLabelId: null,
      baselineAltPhone: null, // diverges from desired
      desiredAssignmentId: 'new-a1',
      stagedAtMillis: 1000,
    );
    expect(altPhoneDiverge.matchesBaseline, isFalse,
        reason: 'should detect diverged alt phone');
  });

  test('toJson/fromJson round-trips every field', () {
    final original = fill();
    final restored = StagedAssignmentChange.fromJson(original.toJson());
    expect(restored, original);

    // Strengthen: add round-trip with every field non-null and distinct
    final fullFull = StagedAssignmentChange(
      slotKey: 'e2_paramedic_5',
      eventId: 'e2',
      roleType: 'paramedic',
      slotIndex: 5,
      desiredMemberId: 'm-desired-1',
      desiredNotes: 'desired note',
      desiredSemanticLabelId: 'lbl-1',
      desiredAltPhone: '050-1234567',
      baselineAssignmentId: 'a-old-2',
      baselineMemberId: 'm-baseline-3',
      baselineNotes: 'baseline note',
      baselineSemanticLabelId: 'lbl-0',
      baselineAltPhone: '052-9876543',
      desiredAssignmentId: 'a-new-4',
      stagedAtMillis: 2000,
    );
    final restoredFull = StagedAssignmentChange.fromJson(fullFull.toJson());
    expect(restoredFull, fullFull);
  });
}
