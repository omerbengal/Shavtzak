import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/rtl_text_field_utils.dart';

void main() {
  group('keepCaretOnItsLine', () {
    const text = 'שלום\nעולם';

    TextEditingValue caret(int offset, [TextAffinity? affinity]) =>
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(
            offset: offset,
            affinity: affinity ?? TextAffinity.downstream,
          ),
        );

    test('a caret leaning back over a line break steps before it', () {
      final fixed = keepCaretOnItsLine(caret(5, TextAffinity.upstream));
      expect(fixed.selection, const TextSelection.collapsed(offset: 4));
      expect(fixed.text, text);
    });

    test('the start of the next line, reached the usual way, stays', () {
      expect(keepCaretOnItsLine(caret(5)), caret(5));
    });

    test('an end of line that is not after a line break stays', () {
      final value = caret(4, TextAffinity.upstream);
      expect(keepCaretOnItsLine(value), value);
    });

    test('a selection of several letters stays', () {
      const value = TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: 2,
          extentOffset: 5,
          affinity: TextAffinity.upstream,
        ),
      );
      expect(keepCaretOnItsLine(value), value);
    });

    test('no selection, and the very start, stay', () {
      const none = TextEditingValue(text: text);
      expect(keepCaretOnItsLine(none), none);
      final start = caret(0, TextAffinity.upstream);
      expect(keepCaretOnItsLine(start), start);
    });
  });

  group('in a Hebrew field of several lines', () {
    // The first line is the short one, so there is empty space to its left.
    const text = 'שלום\nעולם ועוד מילים ארוכות';

    Future<void> pumpField(
        WidgetTester tester, TextEditingController controller) async {
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: TextField(controller: controller, maxLines: null),
              ),
            ),
          ),
        ),
      ));
    }

    /// A point on the first line, in the empty space past its end.
    Offset pastTheFirstLine(WidgetTester tester) {
      final field = tester.getRect(find.byType(EditableText));
      return Offset(field.left + 4, field.top + 6);
    }

    testWidgets('a click past the end of a line puts the caret at its end',
        (tester) async {
      final controller = RtlTextEditingController(text: text);
      addTearDown(controller.dispose);
      await pumpField(tester, controller);

      await tester.tapAt(pastTheFirstLine(tester),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.extentOffset, 'שלום'.length,
          reason: 'the end of the clicked line, not the start of the next');
    });

    testWidgets('the engine alone would put it on the next line',
        (tester) async {
      // Documents what the controller corrects. If this starts failing, the
      // engine was fixed and RtlTextEditingController can go.
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      await pumpField(tester, controller);

      await tester.tapAt(pastTheFirstLine(tester),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(controller.selection.extentOffset, 'שלום'.length + 1);
      expect(controller.selection.affinity, TextAffinity.upstream);
    });
  });
}
