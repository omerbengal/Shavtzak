import test from 'node:test';
import assert from 'node:assert/strict';
import {applyEventItemCatalogueMutation, normalizeEventItemChoices, normalizeEventItemDoc} from './event_items';

test('an absent items key stays absent so an old build keeps the stored items', () => {
  assert.equal(normalizeEventItemChoices(undefined), undefined);
});

test('choices keep their item id and both switches; repeats and id-less entries are dropped', () => {
  assert.deepEqual(
    normalizeEventItemChoices([
      {itemId: 'scan', showInEventExport: true, showInCalendarExport: false},
      {itemId: 'band', showInEventExport: false, showInCalendarExport: true},
      {itemId: 'scan', showInEventExport: false, showInCalendarExport: false},
      {itemId: '  '},
      {name: 'סריקה', emoji: '🤳🏻'},
      'not a choice',
    ]),
    [
      {itemId: 'scan', showInEventExport: true, showInCalendarExport: false},
      {itemId: 'band', showInEventExport: false, showInCalendarExport: true},
    ],
  );
});

test('a choice without its switches shows in both exports', () => {
  assert.deepEqual(normalizeEventItemChoices([{itemId: 'scan'}]), [
    {itemId: 'scan', showInEventExport: true, showInCalendarExport: true},
  ]);
});

test('null or a non-list clears the choices', () => {
  assert.deepEqual(normalizeEventItemChoices(null), []);
  assert.deepEqual(normalizeEventItemChoices('x'), []);
  assert.deepEqual(normalizeEventItemChoices([]), []);
});

const doc = {
  id: 'scan',
  name: ' סריקה ',
  emoji: ' 🤳🏻 ',
  sortOrder: 2,
  isArchived: false,
  createdAt: '2026-11-11T10:00:00.000Z',
  updatedAt: '2026-11-11T10:00:00.000Z',
};

test('a catalogue item is trimmed, its emoji kept to one, a blank emoji is null', () => {
  assert.deepEqual(normalizeEventItemDoc(doc), {...doc, name: 'סריקה', emoji: '🤳🏻'});
  assert.equal(normalizeEventItemDoc({...doc, emoji: '  '}).emoji, null);
  assert.equal(normalizeEventItemDoc({...doc, emoji: '🕎🕎'}).emoji, '🕎');
});

test('a catalogue item name is cut to 40 graphemes without splitting an emoji', () => {
  const family = '👨🏻‍👩🏻‍👧🏻‍👦🏻';
  assert.equal(normalizeEventItemDoc({...doc, name: `${'א'.repeat(38)} ${family}x`}).name, `${'א'.repeat(38)} ${family}`);
  assert.equal(normalizeEventItemDoc({...doc, emoji: family}).emoji, family);
});

test('a catalogue item needs an id and a name', () => {
  assert.throws(() => normalizeEventItemDoc({...doc, id: ''}));
  assert.throws(() => normalizeEventItemDoc({...doc, name: '   '}));
});

const now = '2026-11-12T08:00:00.000Z';
const scan = normalizeEventItemDoc(doc);
const band = normalizeEventItemDoc({...doc, id: 'band', name: 'להקה', emoji: null, sortOrder: 3});

test('insert appends, update replaces by id', () => {
  const inserted = applyEventItemCatalogueMutation([scan], 'eventItem.insert', {eventItem: band}, now);
  assert.deepEqual(inserted.items, [scan, band]);
  assert.equal(inserted.entityId, 'band');

  const updated = applyEventItemCatalogueMutation(inserted.items, 'eventItem.update', {eventItem: {...band, emoji: '🎸'}}, now);
  assert.deepEqual(updated.items, [scan, {...band, emoji: '🎸'}]);
  assert.deepEqual(updated.before, band);
});

test('delete archives, restore brings it back, permanentlyDelete removes it', () => {
  const archived = applyEventItemCatalogueMutation([scan, band], 'eventItem.delete', {eventItemId: 'band'}, now);
  assert.deepEqual(archived.items[1], {...band, isArchived: true, updatedAt: now});

  const restored = applyEventItemCatalogueMutation(archived.items, 'eventItem.restore', {eventItemId: 'band'}, now);
  assert.deepEqual(restored.items[1], {...band, isArchived: false, updatedAt: now});

  const removed = applyEventItemCatalogueMutation(restored.items, 'eventItem.permanentlyDelete', {eventItemId: 'band'}, now);
  assert.deepEqual(removed.items, [scan]);
});

test('inserting an id that exists is refused', () => {
  assert.throws(() => applyEventItemCatalogueMutation([scan], 'eventItem.insert', {eventItem: scan}, now));
});
