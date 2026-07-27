import test from 'node:test';
import assert from 'node:assert/strict';
import {escapeIcsText, foldIcsLine} from './calendar_feed';

test('escapeIcsText escapes the RFC 5545 TEXT specials', () => {
  assert.equal(escapeIcsText('a,b'), 'a\\,b');
  assert.equal(escapeIcsText('a;b'), 'a\\;b');
  assert.equal(escapeIcsText('a\\b'), 'a\\\\b');
  assert.equal(escapeIcsText('a\nb'), 'a\\nb');
  assert.equal(escapeIcsText('a\r\nb'), 'a\\nb');
});

test('escapeIcsText escapes the backslash before anything else', () => {
  // A naive implementation that escapes commas first would turn "\," into
  // "\\\\," and corrupt the output.
  assert.equal(escapeIcsText('\\,'), '\\\\\\,');
});

test('escapeIcsText leaves colons and Hebrew untouched', () => {
  assert.equal(escapeIcsText('סינון כניסה: 17:00'), 'סינון כניסה: 17:00');
});

test('foldIcsLine leaves short lines alone', () => {
  assert.equal(foldIcsLine('SUMMARY:קצר'), 'SUMMARY:קצר');
});

test('foldIcsLine folds on octets, not characters', () => {
  // Hebrew is 2 octets per character in UTF-8, so 60 characters is 120 octets
  // and must fold even though the character count is under 75.
  const line = `SUMMARY:${'א'.repeat(60)}`;
  const folded = foldIcsLine(line);
  assert.ok(folded.includes('\r\n '), 'expected the line to be folded');
  for (const segment of folded.split('\r\n')) {
    assert.ok(
      Buffer.from(segment, 'utf8').length <= 75,
      `segment exceeds 75 octets: ${segment}`,
    );
  }
});

test('foldIcsLine never splits a multi-byte character', () => {
  const line = `DESCRIPTION:${'ש'.repeat(200)}`;
  const rejoined = foldIcsLine(line).split('\r\n ').join('');
  assert.equal(rejoined, line);
  assert.ok(!rejoined.includes('�'), 'output contains a replacement char');
});
