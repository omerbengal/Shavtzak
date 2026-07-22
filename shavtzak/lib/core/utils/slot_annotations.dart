import '../../domain/entities/slot_annotation.dart';

/// The Event.slotAnnotations map key for one slot. Role keys never contain '#'.
String slotAnnotationKey(String roleKey, int slotIndex) => '$roleKey#$slotIndex';

/// Inverse of [slotAnnotationKey]; null for malformed keys. Splits on the LAST
/// '#' so a role key is preserved verbatim.
({String roleKey, int slotIndex})? parseSlotAnnotationKey(String key) {
  final hash = key.lastIndexOf('#');
  if (hash <= 0 || hash == key.length - 1) return null;
  final slot = int.tryParse(key.substring(hash + 1));
  if (slot == null || slot < 0) return null;
  return (roleKey: key.substring(0, hash), slotIndex: slot);
}

/// Indices in [0, requiredCount) that no assignment occupies, ascending.
List<int> emptySlotIndicesForRole(
    int requiredCount, Iterable<int> filledSlotIndices) {
  final filled = filledSlotIndices.toSet();
  return [
    for (var i = 0; i < requiredCount; i++)
      if (!filled.contains(i)) i,
  ];
}

/// An annotation resolved onto a concrete gap index, remembering the stored key
/// it came from (which may differ from the gap after drift — see the design
/// spec §10). `sourceKey` lets the editor self-heal a drifted key.
typedef ResolvedGapAnnotation = ({SlotAnnotation annotation, String sourceKey});

/// Maps a role's stored annotations onto its ACTUAL current gaps so a note
/// never silently vanishes when slots renumber. Exact index matches win; any
/// leftover (drifted) annotations fill the remaining gaps in ascending order.
/// A note on an in-quota FILLED slot stays dormant (excluded from the result);
/// only out-of-range annotations drift onto a free gap.
Map<int, ResolvedGapAnnotation> reconcileGapAnnotations(
  Map<String, SlotAnnotation> eventSlotAnnotations,
  String roleKey,
  int requiredCount,
  Iterable<int> filledSlotIndices,
) {
  final gaps = emptySlotIndicesForRole(requiredCount, filledSlotIndices);
  if (gaps.isEmpty) return const {};

  // This role's non-empty annotations, by their stored slot index.
  final byIndex = <int, SlotAnnotation>{};
  eventSlotAnnotations.forEach((key, value) {
    final parsed = parseSlotAnnotationKey(key);
    if (parsed != null && parsed.roleKey == roleKey && !value.isEmpty) {
      byIndex[parsed.slotIndex] = value;
    }
  });
  if (byIndex.isEmpty) return const {};

  final result = <int, ResolvedGapAnnotation>{};
  final claimed = <int>{};

  // 1) Exact matches: annotation whose stored index is a current gap.
  for (final gap in gaps) {
    final ann = byIndex[gap];
    if (ann != null) {
      result[gap] = (annotation: ann, sourceKey: slotAnnotationKey(roleKey, gap));
      claimed.add(gap);
    }
  }
  // 2) Only OUT-OF-RANGE annotations (index >= requiredCount — the slot no longer
  // exists after a quota reduction) drift onto a free gap. A note on an
  // in-range FILLED slot stays DORMANT: it is the carry-back copy for THAT
  // specific slot and must not surface on another gap (that would double it
  // alongside the assignment's own carried-over note).
  final leftover =
      (byIndex.keys.where((idx) => idx >= requiredCount).toList()..sort());
  final freeGaps = gaps.where((g) => !claimed.contains(g)).toList();
  for (var i = 0; i < leftover.length && i < freeGaps.length; i++) {
    final idx = leftover[i];
    result[freeGaps[i]] =
        (annotation: byIndex[idx]!, sourceKey: slotAnnotationKey(roleKey, idx));
  }
  return result;
}

/// One normalization write for [computeSlotAnnotationNormalization]: upsert
/// [value] at [key] (deleting [staleKey] in the same write when set), or delete
/// [key] when [value] is null.
typedef SlotAnnotationWrite = ({String key, SlotAnnotation? value, String? staleKey});

/// The writes that reconcile a role's stored annotations with the current quota
/// + filled slots, so the DB keys match what [reconcileGapAnnotations] displays:
/// - a note that drifted onto a different gap is re-keyed to that gap (old key
///   deleted via staleKey),
/// - a note with no surviving gap (a true orphan) is deleted,
/// - a note on an in-quota FILLED slot is KEPT untouched (dormant carry-back).
/// Empty list when nothing needs changing. Pure — the caller performs the writes.
List<SlotAnnotationWrite> computeSlotAnnotationNormalization(
  Map<String, SlotAnnotation> eventSlotAnnotations,
  String roleKey,
  int requiredCount,
  Iterable<int> filledSlotIndices,
) {
  final filled = filledSlotIndices.toSet();
  final storedForRole = <String, SlotAnnotation>{};
  eventSlotAnnotations.forEach((k, v) {
    final parsed = parseSlotAnnotationKey(k);
    if (parsed != null && parsed.roleKey == roleKey && !v.isEmpty) {
      storedForRole[k] = v;
    }
  });
  if (storedForRole.isEmpty) return const [];

  final reconciled =
      reconcileGapAnnotations(eventSlotAnnotations, roleKey, requiredCount, filled);

  final writes = <SlotAnnotationWrite>[];
  final sourceKeys = <String>{};
  // Rule 1: re-key any annotation whose reconciled gap differs from its stored key.
  reconciled.forEach((gapIndex, resolved) {
    sourceKeys.add(resolved.sourceKey);
    final canonicalKey = slotAnnotationKey(roleKey, gapIndex);
    if (canonicalKey != resolved.sourceKey) {
      writes.add((key: canonicalKey, value: resolved.annotation, staleKey: resolved.sourceKey));
    }
  });
  // Rules 2 & 3: delete true orphans; keep dormant-on-filled untouched.
  storedForRole.forEach((k, v) {
    if (sourceKeys.contains(k)) return; // moved/kept via re-key above
    final idx = parseSlotAnnotationKey(k)!.slotIndex;
    final dormantOnFilled = idx < requiredCount && filled.contains(idx);
    if (dormantOnFilled) return; // keep dormant carry-back copy
    writes.add((key: k, value: null, staleKey: null)); // orphan → delete
  });
  return writes;
}
