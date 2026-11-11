// What an event has ("מה יש באירוע"): a short list of named items, each with
// an optional emoji. Stored on the event doc as `items: [{name, emoji}]`.

export interface EventItemDoc {
  name: string;
  emoji: string | null;
}

const MAX_NAME_LENGTH = 40;
// Code points, not UTF-16 units: a cut never splits a surrogate pair. Enough
// for a skin-toned or ZWJ emoji.
const MAX_EMOJI_CODE_POINTS = 8;

/**
 * The items an event payload carries, cleaned for storage.
 *
 * `undefined` (the key is absent: an old build's save) stays `undefined` so
 * the partial update keeps the stored items. Anything that is not a list
 * clears them. Names are trimmed and cut to 40 characters; blank names and
 * repeats of an earlier name are dropped. An emoji is trimmed, an empty one
 * is null.
 */
export function normalizeEventItems(value: unknown): EventItemDoc[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value)) return [];

  const seen = new Set<string>();
  const items: EventItemDoc[] = [];
  for (const raw of value) {
    if (raw == null || typeof raw !== 'object') continue;
    const record = raw as Record<string, unknown>;
    const name = typeof record['name'] === 'string'
      ? record['name'].trim().slice(0, MAX_NAME_LENGTH).trim()
      : '';
    if (name.length === 0 || seen.has(name)) continue;
    seen.add(name);
    const emojiText = typeof record['emoji'] === 'string'
      ? Array.from(record['emoji'].trim()).slice(0, MAX_EMOJI_CODE_POINTS).join('')
      : '';
    items.push({name, emoji: emojiText.length === 0 ? null : emojiText});
  }
  return items;
}
