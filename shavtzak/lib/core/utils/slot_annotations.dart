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

/// Maps a role's stored annotations onto its current empty gaps by EXACT index
/// only: a note shows on its own slot, or not at all. A note whose slot no longer
/// exists (index >= requiredCount, e.g. after a quota reduction / row delete) is
/// NOT drifted onto another free gap — a note belongs to its slot and is deleted
/// with it (see [computeSlotAnnotationNormalization]). A note on an in-quota
/// FILLED slot stays dormant (not a current gap, excluded here).
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
  // Exact matches only: a note whose stored index is a current empty gap shows
  // there. Nothing drifts — an out-of-range note (index >= requiredCount) has no
  // slot, so it is left out here and deleted by computeSlotAnnotationNormalization.
  for (final gap in gaps) {
    final ann = byIndex[gap];
    if (ann != null) {
      result[gap] = (annotation: ann, sourceKey: slotAnnotationKey(roleKey, gap));
    }
  }
  return result;
}

/// One normalization write for [computeSlotAnnotationNormalization]: upsert
/// [value] at [key] (deleting [staleKey] in the same write when set), or delete
/// [key] when [value] is null.
typedef SlotAnnotationWrite = ({String key, SlotAnnotation? value, String? staleKey});

/// The writes that reconcile a role's stored annotations with the current quota
/// + filled slots, so the DB matches what [reconcileGapAnnotations] displays:
/// - a note whose slot no longer exists (index >= quota — a quota reduction or
///   row delete) is DELETED from the DB; a note belongs to its slot and dies
///   with it (nothing drifts onto another row),
/// - a note on an in-quota FILLED slot is KEPT untouched (dormant carry-back),
/// - a note on its own in-quota EMPTY gap is KEPT at its key.
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

  // Keys that sit on a current empty gap (exact match) are valid — keep them.
  // With drift gone, a resolved sourceKey always equals the stored key, so this
  // is simply "which stored notes are still on a live gap".
  final validKeys = reconcileGapAnnotations(
          eventSlotAnnotations, roleKey, requiredCount, filled)
      .values
      .map((r) => r.sourceKey)
      .toSet();

  final writes = <SlotAnnotationWrite>[];
  storedForRole.forEach((k, v) {
    if (validKeys.contains(k)) return; // on its own gap → keep
    final idx = parseSlotAnnotationKey(k)!.slotIndex;
    final dormantOnFilled = idx < requiredCount && filled.contains(idx);
    if (dormantOnFilled) return; // keep dormant carry-back copy
    writes.add((key: k, value: null, staleKey: null)); // slot gone → delete
  });
  return writes;
}

/// After TARGETED row-deletions remove [deletedIndices] from a role that had
/// [oldQuota] slots, repack the surviving notes to follow their rows — the note
/// parallel of `_reindexRoleAfterDeletion`. Returns the writes (rewrite/delete)
/// that turn the stored notes into that layout.
///
/// CRUCIAL: it packs the same way the assignment reindex does — surviving
/// FILLED slots ([filledIndices]) contiguous from 0, then surviving EMPTY slots
/// after them. A gap note lives on an empty slot, so it lands after the packed
/// assignments; without this a note could collide onto a filled slot (a stray
/// dormant note). With no assignments (the pure-empty case) this is just a
/// plain shift-up. A deleted row's note is dropped.
///
/// This is what makes "swipe-delete a row, keep the right note" work.
/// Contrast [computeSlotAnnotationNormalization], which only deletes notes that
/// fell out of range (correct for "remove the LAST row" — an event-form
/// decrement — but it deletes the highest note regardless of WHICH row you
/// removed, and never shifts).
List<SlotAnnotationWrite> computeNoteReindexAfterDeletion(
  Map<String, SlotAnnotation> eventSlotAnnotations,
  String roleKey,
  int oldQuota,
  Set<int> deletedIndices,
  Set<int> filledIndices,
) {
  if (deletedIndices.isEmpty || oldQuota <= 0) return const [];

  final byIndex = <int, SlotAnnotation>{};
  eventSlotAnnotations.forEach((k, v) {
    final p = parseSlotAnnotationKey(k);
    if (p != null && p.roleKey == roleKey && !v.isEmpty) {
      byIndex[p.slotIndex] = v;
    }
  });

  // Surviving old indices split filled-vs-empty, mirroring the assignment
  // reindex: filled slots pack contiguous onto new indices 0..k-1, then the
  // empty slots onto k..newQuota-1. Each surviving slot carries its own note.
  final survivingFilled = [
    for (var i = 0; i < oldQuota; i++)
      if (filledIndices.contains(i) && !deletedIndices.contains(i)) i,
  ];
  final survivingEmpty = [
    for (var i = 0; i < oldQuota; i++)
      if (!filledIndices.contains(i) && !deletedIndices.contains(i)) i,
  ];
  final k = survivingFilled.length;
  final newQuota = k + survivingEmpty.length;

  final desired = <int, SlotAnnotation?>{}; // new index -> its note
  for (var p = 0; p < survivingFilled.length; p++) {
    desired[p] = byIndex[survivingFilled[p]];
  }
  for (var p = 0; p < survivingEmpty.length; p++) {
    desired[k + p] = byIndex[survivingEmpty[p]];
  }

  final writes = <SlotAnnotationWrite>[];
  // Touch every old in-range index: [0, newQuota) take the repacked note; the
  // rest (freed by the deletion) are cleared.
  for (var idx = 0; idx < oldQuota; idx++) {
    final oldNote = byIndex[idx];
    final newNote = idx < newQuota ? desired[idx] : null;
    if (oldNote == newNote) continue; // unchanged at this index
    writes.add(
        (key: slotAnnotationKey(roleKey, idx), value: newNote, staleKey: null));
  }
  return writes;
}
