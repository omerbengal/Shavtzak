import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/bloc/assignment/models/staged_assignment_change.dart';

StagedAssignmentChange _base({bool del = false, bool add = false}) =>
    StagedAssignmentChange(
      slotKey: 'e1_medic_0', eventId: 'e1', roleType: 'medic', slotIndex: 0,
      desiredMemberId: 'm1', desiredNotes: '', desiredSemanticLabelId: null,
      desiredAltPhone: null, desiredCustomStartAt: null, desiredCustomEndAt: null,
      baselineAssignmentId: 'a1', baselineMemberId: 'm1',
      baselineNotes: '', baselineSemanticLabelId: null, baselineAltPhone: null,
      baselineCustomStartAt: null, baselineCustomEndAt: null,
      desiredAssignmentId: 'a1', stagedAtMillis: 1000, markedForDeletion: del,
      isManualAdd: add,
    );

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
        desiredCustomStartAt: null,
        desiredCustomEndAt: null,
        baselineAssignmentId: null,
        baselineMemberId: null,
        baselineNotes: '',
        baselineSemanticLabelId: null,
        baselineAltPhone: null,
        baselineCustomStartAt: null,
        baselineCustomEndAt: null,
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
      desiredCustomStartAt: null,
      desiredCustomEndAt: null,
      baselineAssignmentId: 'a1',
      baselineMemberId: 'm2', // matches desired
      baselineNotes: '', // matches desired
      baselineSemanticLabelId: null, // diverges from desired
      baselineAltPhone: null,
      baselineCustomStartAt: null,
      baselineCustomEndAt: null,
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
      desiredCustomStartAt: null,
      desiredCustomEndAt: null,
      baselineAssignmentId: 'a1',
      baselineMemberId: 'm2', // matches desired
      baselineNotes: '', // matches desired
      baselineSemanticLabelId: null,
      baselineAltPhone: null, // diverges from desired
      baselineCustomStartAt: null,
      baselineCustomEndAt: null,
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
      desiredCustomStartAt: '2026-11-03T09:00',
      desiredCustomEndAt: '2026-11-03T17:00',
      baselineAssignmentId: 'a-old-2',
      baselineMemberId: 'm-baseline-3',
      baselineNotes: 'baseline note',
      baselineSemanticLabelId: 'lbl-0',
      baselineAltPhone: '052-9876543',
      baselineCustomStartAt: '2026-11-02T20:00',
      baselineCustomEndAt: '2026-11-03T12:00',
      desiredAssignmentId: 'a-new-4',
      stagedAtMillis: 2000,
    );
    final restoredFull = StagedAssignmentChange.fromJson(fullFull.toJson());
    expect(restoredFull, fullFull);
  });

  test('markedForDeletion round-trips through json', () {
    final json = _base(del: true).toJson();
    expect(json['markedForDeletion'], true);
    expect(StagedAssignmentChange.fromJson(json).markedForDeletion, true);
  });

  test('fromJson defaults markedForDeletion to false when absent', () {
    final json = _base().toJson()..remove('markedForDeletion');
    expect(StagedAssignmentChange.fromJson(json).markedForDeletion, false);
  });

  test('isManualAdd round-trips through json', () {
    final json = _base(add: true).toJson();
    expect(json['isManualAdd'], true);
    expect(StagedAssignmentChange.fromJson(json).isManualAdd, true);
  });

  test('fromJson defaults isManualAdd to false when absent', () {
    final json = _base().toJson()..remove('isManualAdd');
    expect(StagedAssignmentChange.fromJson(json).isManualAdd, false);
  });

  test('matchesBaseline is false for a deletion even when desired == baseline', () {
    // desired member == baseline member, but a deletion must NOT auto-clean.
    expect(_base(del: true).matchesBaseline, false);
    expect(_base(del: false).matchesBaseline, true);
  });

  group('custom hours', () {
    StagedAssignmentChange withHours({
      String? desiredStart,
      String? desiredEnd,
      String? baselineStart,
      String? baselineEnd,
    }) =>
        StagedAssignmentChange(
          slotKey: 'e1_medic_0',
          eventId: 'e1',
          roleType: 'medic',
          slotIndex: 0,
          desiredMemberId: 'm1',
          desiredNotes: '',
          desiredSemanticLabelId: null,
          desiredAltPhone: null,
          desiredCustomStartAt: desiredStart,
          desiredCustomEndAt: desiredEnd,
          baselineAssignmentId: 'a1',
          baselineMemberId: 'm1',
          baselineNotes: '',
          baselineSemanticLabelId: null,
          baselineAltPhone: null,
          baselineCustomStartAt: baselineStart,
          baselineCustomEndAt: baselineEnd,
          desiredAssignmentId: 'a1',
          stagedAtMillis: 1000,
        );

    test(
        'an old cache with no hour keys reads both desired and baseline hours '
        'as null, and still matches its baseline', () {
      final oldCache = _base().toJson()
        ..remove('desiredCustomStartAt')
        ..remove('desiredCustomEndAt')
        ..remove('baselineCustomStartAt')
        ..remove('baselineCustomEndAt');

      final restored = StagedAssignmentChange.fromJson(oldCache);

      expect(restored.desiredCustomStartAt, isNull);
      expect(restored.desiredCustomEndAt, isNull);
      expect(restored.baselineCustomStartAt, isNull);
      expect(restored.baselineCustomEndAt, isNull);
      expect(restored.matchesBaseline, isTrue);
    });

    test('desired hours that differ from the baseline make the change dirty',
        () {
      final unchanged = withHours(
        desiredStart: '2026-11-03T09:00',
        desiredEnd: '2026-11-03T17:00',
        baselineStart: '2026-11-03T09:00',
        baselineEnd: '2026-11-03T17:00',
      );
      expect(unchanged.matchesBaseline, isTrue);

      expect(
        withHours(
          desiredStart: '2026-11-03T10:00',
          desiredEnd: '2026-11-03T17:00',
          baselineStart: '2026-11-03T09:00',
          baselineEnd: '2026-11-03T17:00',
        ).matchesBaseline,
        isFalse,
        reason: 'a different start',
      );
      expect(
        withHours(
          desiredStart: '2026-11-03T09:00',
          desiredEnd: '2026-11-03T18:00',
          baselineStart: '2026-11-03T09:00',
          baselineEnd: '2026-11-03T17:00',
        ).matchesBaseline,
        isFalse,
        reason: 'a different end',
      );
      expect(
        withHours(
          baselineStart: '2026-11-03T09:00',
          baselineEnd: '2026-11-03T17:00',
        ).matchesBaseline,
        isFalse,
        reason: 'hours cleared by the admin',
      );
      expect(
        withHours(
          desiredStart: '2026-11-03T09:00',
          desiredEnd: '2026-11-03T17:00',
        ).matchesBaseline,
        isFalse,
        reason: 'hours added by the admin',
      );
    });

    test('toJson/fromJson keeps all four hour fields', () {
      final original = withHours(
        desiredStart: '2026-11-03T10:00',
        desiredEnd: '2026-11-03T18:00',
        baselineStart: '2026-11-03T09:00',
        baselineEnd: '2026-11-03T17:00',
      );
      final json = original.toJson();

      expect(json['desiredCustomStartAt'], '2026-11-03T10:00');
      expect(json['desiredCustomEndAt'], '2026-11-03T18:00');
      expect(json['baselineCustomStartAt'], '2026-11-03T09:00');
      expect(json['baselineCustomEndAt'], '2026-11-03T17:00');
      expect(StagedAssignmentChange.fromJson(json), original);
    });

    test('copyWith sets, clears and keeps the desired hours; never the baseline',
        () {
      final base = withHours(
        desiredStart: '2026-11-03T09:00',
        desiredEnd: '2026-11-03T17:00',
        baselineStart: '2026-11-03T09:00',
        baselineEnd: '2026-11-03T17:00',
      );

      final moved = base.copyWith(
        desiredCustomStartAt: () => '2026-11-03T10:00',
        desiredCustomEndAt: () => '2026-11-03T16:00',
      );
      expect(moved.desiredCustomStartAt, '2026-11-03T10:00');
      expect(moved.desiredCustomEndAt, '2026-11-03T16:00');
      expect(moved.baselineCustomStartAt, '2026-11-03T09:00');
      expect(moved.baselineCustomEndAt, '2026-11-03T17:00');

      final cleared = base.copyWith(
        desiredCustomStartAt: () => null,
        desiredCustomEndAt: () => null,
      );
      expect(cleared.desiredCustomStartAt, isNull);
      expect(cleared.desiredCustomEndAt, isNull);
      expect(cleared.baselineCustomStartAt, '2026-11-03T09:00');

      final untouched = base.copyWith(desiredNotes: 'x');
      expect(untouched.desiredCustomStartAt, '2026-11-03T09:00');
      expect(untouched.desiredCustomEndAt, '2026-11-03T17:00');
    });

    test('props differ when only one hour field differs', () {
      final a = withHours(
        desiredStart: '2026-11-03T09:00',
        desiredEnd: '2026-11-03T17:00',
        baselineStart: '2026-11-03T09:00',
        baselineEnd: '2026-11-03T17:00',
      );
      expect(a, isNot(a.copyWith(desiredCustomEndAt: () => '2026-11-03T18:00')));
      expect(
          a, isNot(a.copyWith(desiredCustomStartAt: () => '2026-11-03T10:00')));
      expect(
          a,
          isNot(withHours(
            desiredStart: '2026-11-03T09:00',
            desiredEnd: '2026-11-03T17:00',
            baselineStart: '2026-11-03T08:00',
            baselineEnd: '2026-11-03T17:00',
          )));
      expect(
          a,
          isNot(withHours(
            desiredStart: '2026-11-03T09:00',
            desiredEnd: '2026-11-03T17:00',
            baselineStart: '2026-11-03T09:00',
            baselineEnd: '2026-11-03T16:00',
          )));
    });
  });
}
