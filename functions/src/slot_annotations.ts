import {FieldValue} from 'firebase-admin/firestore';

export type SlotAnnotationValue = {note: string; labelId: string | null};

/**
 * Builds the nested merge-set payload for one slot annotation. A merge-set with
 * a nested map touches only the listed sub-keys (siblings preserved). `null`
 * value clears the key; an optional `staleKey` (from a drifted stored key) is
 * deleted in the same atomic write so storage self-heals toward display.
 */
export function buildSlotAnnotationMerge(
  key: string,
  value: SlotAnnotationValue | null,
  staleKey?: string | null,
): Record<string, unknown> {
  const inner: Record<string, unknown> = {};
  inner[key] = value === null
    ? FieldValue.delete()
    : {note: value.note, labelId: value.labelId};
  if (staleKey && staleKey !== key) {
    inner[staleKey] = FieldValue.delete();
  }
  return {slotAnnotations: inner};
}
