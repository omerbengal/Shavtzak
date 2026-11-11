import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeEventItems} from './event_items';

test('an absent items key stays absent so an old build keeps the stored items', () => {
  assert.equal(normalizeEventItems(undefined), undefined);
});

test('items are trimmed, emptied emoji become null, blanks and repeats dropped', () => {
  assert.deepEqual(
    normalizeEventItems([
      {name: ' סריקה ', emoji: '🤳🏻'},
      {name: 'להקה', emoji: ''},
      {name: '   '},
      {name: 'סריקה', emoji: 'x'},
      {name: 'חנוכייה', emoji: ' 🕎 '},
      'not an item',
    ]),
    [
      {name: 'סריקה', emoji: '🤳🏻'},
      {name: 'להקה', emoji: null},
      {name: 'חנוכייה', emoji: '🕎'},
    ],
  );
});

test('null or a non-list clears the items', () => {
  assert.deepEqual(normalizeEventItems(null), []);
  assert.deepEqual(normalizeEventItems('x'), []);
  assert.deepEqual(normalizeEventItems([]), []);
});

test('over-long names and emoji are cut', () => {
  const [item] = normalizeEventItems([{name: 'א'.repeat(60), emoji: '🕎'.repeat(20)}])!;
  assert.equal(item.name.length, 40);
  assert.ok(item.emoji!.length <= 16);
});
