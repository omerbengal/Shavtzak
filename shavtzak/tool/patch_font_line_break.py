#!/usr/bin/env python3
"""Give the app's fonts an empty, zero-width glyph for the line break.

Rubik as downloaded has no glyph for a line break (U+000A) or a carriage
return (U+000D). Flutter's text engine then gives the line break the font's
"missing glyph" box, 0.695 of the font size wide. On a right-to-left line
that box sits at the line's left end, and every letter of the line is
reported that much to the right of where it is painted. In a Hebrew text
field the caret then sits inside a letter, the selection covers the wrong
letter and a click lands a letter or two off, on every line that ends with
Enter. `test/core/fonts/rubik_line_break_test.dart` guards it.

Run it again after replacing a font file with a fresh download:

    pip install fonttools
    python3 tool/patch_font_line_break.py            # from shavtzak/

Only the new glyph and its two character-map entries are added; every
existing glyph, width and line metric is written back unchanged. A file that
already has the glyph is left alone.
"""
import pathlib
import sys

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph

CODES = (0x000A, 0x000D)  # line feed, carriage return
GLYPH = 'linebreak'
FONTS = ('Rubik-Regular.ttf', 'Rubik-Medium.ttf', 'Rubik-Bold.ttf')


def patch(path: pathlib.Path) -> str:
    # No recalculation: bounding box, flags and timestamp stay as they were.
    font = TTFont(path, recalcBBoxes=False, recalcTimestamp=False)
    best = font.getBestCmap()
    if all(font['hmtx'][best[code]][0] == 0 for code in CODES if code in best) \
            and all(code in best for code in CODES):
        return 'already has it'
    if GLYPH not in font.getGlyphOrder():
        font.setGlyphOrder(font.getGlyphOrder() + [GLYPH])
        font['glyf'][GLYPH] = Glyph()  # no outline
        font['hmtx'][GLYPH] = (0, 0)  # advance 0, left side bearing 0
    for table in font['cmap'].tables:
        if table.isUnicode():
            for code in CODES:
                table.cmap[code] = GLYPH
    font.save(path)
    return 'patched'


def main() -> int:
    fonts_dir = pathlib.Path(__file__).resolve().parent.parent / 'assets' / 'fonts'
    for name in FONTS:
        print(f'{name}: {patch(fonts_dir / name)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
