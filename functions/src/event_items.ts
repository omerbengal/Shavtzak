// What an event has ("מה יש באירוע"): a short list of named items, each with
// an optional emoji. Stored on the event doc as `items: [{name, emoji}]`.

export interface EventItemDoc {
  name: string;
  emoji: string | null;
}

// Counted in graphemes (what a person sees as one character), like the
// form's limit, so a cut never splits an emoji.
const MAX_NAME_GRAPHEMES = 40;
const MAX_EMOJI_GRAPHEMES = 1;

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
 * clears them. Names are trimmed and cut to 40 graphemes; blank names and
 * repeats of an earlier name are dropped. An emoji is trimmed, an empty one
 * is null, and only its first grapheme is kept (one emoji, as the form asks).
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
      ? firstGraphemes(record['name'].trim(), MAX_NAME_GRAPHEMES).trim()
      : '';
    if (name.length === 0 || seen.has(name)) continue;
    seen.add(name);
    const emojiText = typeof record['emoji'] === 'string'
      ? firstGraphemes(record['emoji'].trim(), MAX_EMOJI_GRAPHEMES)
      : '';
    items.push({name, emoji: emojiText.length === 0 ? null : emojiText});
  }
  return items;
}
