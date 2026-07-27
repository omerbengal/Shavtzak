/**
 * Pure RFC 5545 rendering for the personal calendar feed. This module holds no
 * Firestore or Express dependencies so every rule below is unit-testable.
 */

/** Escapes a value for an RFC 5545 TEXT property (section 3.3.11). */
export function escapeIcsText(value: string): string {
  return value
    // Backslash must be escaped first, or the escapes added below get
    // double-escaped in turn.
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r\n/g, '\\n')
    .replace(/[\r\n]/g, '\\n');
}

/**
 * Folds a content line to 75 octets (section 3.1). The limit is octets, not
 * characters: Hebrew is two octets per character in UTF-8, so folding on
 * character boundaries both under-folds and can split a multi-byte sequence.
 */
export function foldIcsLine(line: string): string {
  const bytes = Buffer.from(line, 'utf8');
  if (bytes.length <= 75) {
    return line;
  }

  const segments: string[] = [];
  let start = 0;
  // The first line gets 75 octets; continuation lines spend one on the
  // leading space that marks them as continuations.
  let limit = 75;

  while (start < bytes.length) {
    let end = Math.min(start + limit, bytes.length);
    // Walk back off any UTF-8 continuation byte (10xxxxxx) so we always cut
    // on a character boundary.
    while (end > start && end < bytes.length && (bytes[end] & 0xc0) === 0x80) {
      end -= 1;
    }
    segments.push(bytes.subarray(start, end).toString('utf8'));
    start = end;
    limit = 74;
  }

  return segments.join('\r\n ');
}
