import {test} from 'node:test';
import assert from 'node:assert';
import {FieldValue} from 'firebase-admin/firestore';
import {buildSlotAnnotationMerge} from './slot_annotations';

test('upsert writes only the one key under slotAnnotations', () => {
  const merge = buildSlotAnnotationMerge('medic#2', {note: 'C', labelId: 'L2'});
  assert.deepStrictEqual(merge, {
    slotAnnotations: {'medic#2': {note: 'C', labelId: 'L2'}},
  });
});

test('clear (null value) writes a delete sentinel for the key', () => {
  const merge = buildSlotAnnotationMerge('medic#2', null);
  const inner = (merge.slotAnnotations as Record<string, unknown>)['medic#2'];
  assert.ok(FieldValue.delete().isEqual(inner as never));
});

test('staleKey adds a second delete sentinel (self-heal)', () => {
  const merge = buildSlotAnnotationMerge(
    'medic#1', {note: 'x', labelId: null}, 'medic#3');
  const inner = merge.slotAnnotations as Record<string, unknown>;
  assert.deepStrictEqual(inner['medic#1'], {note: 'x', labelId: null});
  assert.ok(FieldValue.delete().isEqual(inner['medic#3'] as never));
});

test('staleKey equal to key is ignored', () => {
  const merge = buildSlotAnnotationMerge('medic#1', {note: 'x', labelId: null}, 'medic#1');
  const inner = merge.slotAnnotations as Record<string, unknown>;
  assert.deepStrictEqual(inner, {'medic#1': {note: 'x', labelId: null}});
});
