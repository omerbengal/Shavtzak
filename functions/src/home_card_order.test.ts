import test from 'node:test';
import assert from 'node:assert/strict';
import {TaskError} from './tasks';
import {MAX_HOME_CARDS, parseHomeCardOrder} from './home_card_order';

const is400 = (e: unknown) => e instanceof TaskError && e.status === 400;

test('parseHomeCardOrder keeps a list of card ids as sent', () => {
  assert.deepEqual(
    parseHomeCardOrder(['summary', 'personal', 'teamTasks']),
    ['summary', 'personal', 'teamTasks'],
  );
  assert.deepEqual(parseHomeCardOrder([]), []);
});

test('parseHomeCardOrder drops a repeated id, keeping the first', () => {
  assert.deepEqual(parseHomeCardOrder(['a', 'b', 'a']), ['a', 'b']);
});

test('parseHomeCardOrder refuses anything that is not a short list of ids', () => {
  assert.throws(() => parseHomeCardOrder(undefined), is400);
  assert.throws(() => parseHomeCardOrder('personal'), is400);
  assert.throws(() => parseHomeCardOrder(['ok', 3]), is400);
  assert.throws(() => parseHomeCardOrder(['ok', '']), is400);
  assert.throws(() => parseHomeCardOrder(['x'.repeat(41)]), is400);
  assert.throws(
    () => parseHomeCardOrder(Array.from({length: MAX_HOME_CARDS + 1}, (_, i) => `c${i}`)),
    is400,
  );
});
