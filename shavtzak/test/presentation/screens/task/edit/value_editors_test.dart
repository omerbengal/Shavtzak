import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/task/edit/value_editors.dart';

void main() {
  group('TextValueEditor, several lines of Hebrew', () {
    // The first line ends with Enter, and the word picked is in its middle.
    const text = 'אחת שתיים שלוש\nארבע';
    const word = 'שתיים';

    Future<RenderEditable> pumpEditor(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: TextValueEditor(
                  initial: text,
                  multiline: true,
                  onChanged: (_) {},
                  onSubmit: () {},
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return tester.allRenderObjects.whereType<RenderEditable>().single;
    }

    testWidgets('a selected word is highlighted, and nothing beside it',
        (tester) async {
      // Flutter's default highlight on an iPhone and in Safari stretches a
      // selection towards the line's edge. In right-to-left text that
      // stretch misfires: one word selected in the middle of a line was
      // highlighted all the way to the field's left edge, over the words
      // after it. (Off the web the stretching style is the default too, so
      // this runs here as it does on an iPhone.)
      final editable = await pumpEditor(tester);
      final start = text.indexOf(word);
      final selection =
          TextSelection(baseOffset: start, extentOffset: start + word.length);

      final boxes = editable.getBoxesForSelection(selection);

      expect(boxes, hasLength(1), reason: 'one box: the word itself');
      // The word is neither first nor last on its line, so its box touches
      // neither edge of the text.
      final lineWidth = editable.size.width;
      expect(boxes.single.left, greaterThan(40));
      expect(boxes.single.right, lessThan(lineWidth - 40));
    });
  });
}
