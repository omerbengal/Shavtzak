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
  // Interleave valid entries with malformed ones (reusing the shapes from the
  // 'malformed entries are dropped' case above) so a regression that clamps on
  // the RAW index instead of the count of VALID pushes shows up as a length/
  // content mismatch instead of passing by coincidence.
  const malformed: unknown[] = [null, {}, {count: 'x'}, {count: -1}];
  const many: unknown[] = [];
  for (let i = 0; i < 20; i++) {
    many.push({label: null, count: i});
    many.push(malformed[i % malformed.length]);
  }

  const result = normalizeParticipantGroups(many, null);
  assert.equal(result.length, 10);
  assert.deepEqual(
    result.map((group) => group.count),
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  );
});

test('nothing set yields no groups', () => {
  assert.deepEqual(normalizeParticipantGroups(undefined, null), []);
});

test('zero is a legal count', () => {
  assert.deepEqual(normalizeParticipantGroups([{label: null, count: 0}], null), [
    {label: null, count: 0},
  ]);
});
