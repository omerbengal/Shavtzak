// What an event has ("מה יש באירוע").
//
// The items are a managed list, like the categories: `utilities/Lists`
// field `EventItems`, each {id, name, emoji|null, sortOrder, isArchived,
// createdAt, updatedAt}, changed through the `eventItem.*` mutations.
//
// An event stores which of them it has, and for each whether it shows on
// the event's picture and on the calendar picture:
// `items: [{itemId, showInEventExport, showInCalendarExport}]`.

import {TaskError} from './tasks';

export interface EventItemChoiceDoc {
  itemId: string;
  showInEventExport: boolean;
  showInCalendarExport: boolean;
}

// Counted in graphemes (what a person sees as one character), like the
// form's limit, so a cut never splits an emoji.
const MAX_NAME_GRAPHEMES = 40;

const graphemes = new Intl.Segmenter(undefined, {granularity: 'grapheme'});

function firstGraphemes(text: string, count: number): string {
  let result = '';
  let taken = 0;
  for (const {segment} of graphemes.segment(text)) {
    if (taken === count) break;
    result += segment;
    taken += 1;
  }
  return result;
}

/**
 * The items an event payload carries, cleaned for storage.
 *
 * `undefined` (the key is absent: an old build's save) stays `undefined` so
 * the partial update keeps the stored items. Anything that is not a list
 * clears them. Entries without an item id and repeats of an earlier id are
 * dropped; a switch that is not `false` is on.
 */
export function normalizeEventItemChoices(value: unknown): EventItemChoiceDoc[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value)) return [];

  const seen = new Set<string>();
  const choices: EventItemChoiceDoc[] = [];
  for (const raw of value) {
    if (raw == null || typeof raw !== 'object') continue;
    const record = raw as Record<string, unknown>;
    const itemId = typeof record['itemId'] === 'string' ? record['itemId'].trim() : '';
    if (itemId.length === 0 || seen.has(itemId)) continue;
    seen.add(itemId);
    choices.push({
      itemId,
      showInEventExport: record['showInEventExport'] !== false,
      showInCalendarExport: record['showInCalendarExport'] !== false,
    });
  }
  return choices;
}

/**
 * A catalogue item as the client sent it, cleaned: name trimmed and cut to
 * 40 graphemes, emoji trimmed to its first grapheme (null when blank).
 * Refused (400) without an id or a name.
 */
export function normalizeEventItemDoc(value: unknown): Record<string, unknown> {
  if (value == null || typeof value !== 'object') throw new TaskError(400, 'eventItem is required');
  const record = value as Record<string, unknown>;
  const id = typeof record['id'] === 'string' ? record['id'].trim() : '';
  if (id.length === 0) throw new TaskError(400, 'eventItem.id is required');
  const name = typeof record['name'] === 'string'
    ? firstGraphemes(record['name'].trim(), MAX_NAME_GRAPHEMES).trim()
    : '';
  if (name.length === 0) throw new TaskError(400, 'eventItem.name is required');
  const emoji = typeof record['emoji'] === 'string' ? firstGraphemes(record['emoji'].trim(), 1) : '';
  return {
    ...record,
    id,
    name,
    emoji: emoji.length === 0 ? null : emoji,
    sortOrder: typeof record['sortOrder'] === 'number' ? record['sortOrder'] : 0,
    isArchived: record['isArchived'] === true,
  };
}

export interface EventItemCatalogueChange {
  items: Array<Record<string, unknown>>;
  entityId: string;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
}

/**
 * One `eventItem.*` mutation applied to the catalogue: insert / update (a
 * whole item under `eventItem`), delete (archive) / restore /
 * permanentlyDelete (by `eventItemId`).
 */
export function applyEventItemCatalogueMutation(
  catalogue: Array<Record<string, unknown>>,
  operation: string,
  payload: Record<string, unknown>,
  nowIso: string,
): EventItemCatalogueChange {
  if (operation === 'eventItem.insert' || operation === 'eventItem.update') {
    const item = normalizeEventItemDoc(payload['eventItem']);
    const id = item['id'] as string;
    const before = catalogue.find((entry) => entry['id'] === id) ?? null;
    if (operation === 'eventItem.insert') {
      if (before != null) throw new TaskError(409, 'eventItem already exists');
      return {items: [...catalogue, item], entityId: id, before: null, after: item};
    }
    if (before == null) throw new TaskError(404, 'eventItem not found');
    return {
      items: catalogue.map((entry) => (entry['id'] === id ? item : entry)),
      entityId: id,
      before,
      after: item,
    };
  }

  const id = typeof payload['eventItemId'] === 'string' ? payload['eventItemId'] : '';
  if (id.length === 0) throw new TaskError(400, 'eventItemId is required');
  const before = catalogue.find((entry) => entry['id'] === id) ?? null;
  switch (operation) {
    case 'eventItem.permanentlyDelete':
      return {items: catalogue.filter((entry) => entry['id'] !== id), entityId: id, before, after: null};
    case 'eventItem.delete':
    case 'eventItem.restore': {
      const items = catalogue.map((entry) => entry['id'] !== id
        ? entry
        : {...entry, isArchived: operation === 'eventItem.delete', updatedAt: nowIso});
      return {items, entityId: id, before, after: items.find((entry) => entry['id'] === id) ?? null};
    }
    default:
      throw new TaskError(400, `Unknown operation ${operation}`);
  }
}
