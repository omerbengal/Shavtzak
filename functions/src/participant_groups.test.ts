import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeParticipantGroups} from './participant_groups';

test('an old-client payload with only participantCount becomes one unlabeled group', () => {
  assert.deepEqual(normalizeParticipantGroups(undefined, 500), [
    {label: null, count: 500},
  ]);
});

test('a participantGroups array passes through, trimming labels', () => {
  assert.deepEqual(
    normalizeParticipantGroups(
      [
        {label: '  בוקר  ', count: 500},
        {label: '', count: 700},
      ],
      null,
    ),
    [
      {label: 'בוקר', count: 500},
      {label: null, count: 700},
    ],
  );
});

test('the array wins over a stale legacy scalar', () => {
  assert.deepEqual(
    normalizeParticipantGroups([{label: null, count: 600}], 500),
    [{label: null, count: 600}],
  );
});

test('an empty array stays empty and does not fall back to the scalar', () => {
  assert.deepEqual(normalizeParticipantGroups([], 500), []);
});

test('malformed entries are dropped, not thrown on', () => {
  assert.deepEqual(
    normalizeParticipantGroups(
      [
        {label: 'תקין', count: 100},
        {label: 'ללא כמות'},
        {label: 'שלילי', count: -5},
        {label: 'לא מספר', count: 'abc'},
        null,
      ],
      null,
    ),
    [{label: 'תקין', count: 100}],
  );
});

test('counts are floored to integers', () => {
  assert.deepEqual(normalizeParticipantGroups([{label: null, count: 12.7}], null), [
    {label: null, count: 12},
  ]);
});

test('the array is clamped to 10 groups', () => {
  const many = Array.from({length: 14}, (_, i) => ({label: null, count: i}));
  assert.equal(normalizeParticipantGroups(many, null).length, 10);
});

test('nothing set yields no groups', () => {
  assert.deepEqual(normalizeParticipantGroups(undefined, null), []);
});

test('zero is a legal count', () => {
  assert.deepEqual(normalizeParticipantGroups([{label: null, count: 0}], null), [
    {label: null, count: 0},
  ]);
});
