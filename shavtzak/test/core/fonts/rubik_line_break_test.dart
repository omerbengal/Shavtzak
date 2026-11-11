import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app's font must give the line break a glyph of no width.
///
/// Rubik as downloaded has no glyph for a line break, so the text engine
/// gives it the font's "missing glyph" box, 0.695 of the font size wide. On a
/// right-to-left line that box sits at the line's left end, and the engine
/// reports every letter of that line that much to the right of where it
/// paints it. In a Hebrew text field that put the caret inside a letter,
/// drew the selection over the wrong letter and took clicks a letter or two
/// off, on every line that ends with Enter.
///
/// `assets/fonts/Rubik-*.ttf` therefore carry an empty zero-width glyph for
/// U+000A and U+000D (`tool/patch_font_line_break.py`). This test fails if
/// the files are ever replaced with fresh downloads.
void main() {
  const weights = {
    'Regular': FontWeight.w400,
    'Medium': FontWeight.w500,
    'Bold': FontWeight.w700,
  };

  setUpAll(() async {
    final loader = FontLoader('Rubik');
    for (final name in weights.keys) {
      final bytes = File('assets/fonts/Rubik-$name.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  for (final MapEntry(key: name, value: weight) in weights.entries) {
    for (final lineBreak in const ['\n', '\r\n']) {
      final label = lineBreak == '\n' ? 'Enter' : 'a Windows line break';
      test(
          'Rubik $name: a Hebrew line ending with $label is measured where it is painted',
          () {
        // Two identical lines; only the first ends with a line break.
        const line = 'שלום עולם';
        final painter = TextPainter(
          text: TextSpan(
            text: '$line$lineBreak$line',
            style: TextStyle(
              fontFamily: 'Rubik',
              fontSize: 16,
              fontWeight: weight,
            ),
          ),
          textDirection: TextDirection.rtl,
        )..layout(maxWidth: 400);
        addTearDown(painter.dispose);

        TextBox letter(int offset) => painter
            .getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1))
            .single;
        final secondLine = line.length + lineBreak.length;
        for (var i = 0; i < line.length; i++) {
          final first = letter(i);
          final second = letter(secondLine + i);
          expect(
            first.right,
            closeTo(second.right, 1.0),
            reason: 'letter $i of the line that ends with $label sits '
                '${(first.right - second.right).toStringAsFixed(1)} px away '
                'from the same letter on the line that does not',
          );
        }
      });
    }
  }
}
