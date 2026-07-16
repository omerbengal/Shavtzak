import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/assignment_save_bar.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int stagedCount,
    required VoidCallback onSave,
    required VoidCallback onDiscardAll,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AssignmentSaveBar(
              stagedCount: stagedCount,
              onSave: onSave,
              onDiscardAll: onDiscardAll,
            ),
          ),
        ),
      ),
    );
  }

  group('AssignmentSaveBar', () {
    testWidgets('clean (stagedCount: 0) shows a disabled Save, no discard-all',
        (tester) async {
      var saveTapped = false;
      var discardTapped = false;

      await pump(
        tester,
        stagedCount: 0,
        onSave: () => saveTapped = true,
        onDiscardAll: () => discardTapped = true,
      );

      // Plain "שמור" label, no count suffix.
      expect(find.text('שמור'), findsOneWidget);
      expect(find.textContaining('שמור ·'), findsNothing);

      // Discard-all is not rendered at all when clean.
      expect(find.text('בטל הכל'), findsNothing);

      // The Save button itself must be disabled (onPressed == null) —
      // presence of the greyed-out button is what "visible but disabled"
      // means, not merely finding the text.
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'שמור'),
      );
      expect(saveButton.onPressed, isNull);

      // Tapping a disabled button must not invoke the callback.
      await tester.tap(find.widgetWithText(ElevatedButton, 'שמור'));
      await tester.pump();
      expect(saveTapped, isFalse);
      expect(discardTapped, isFalse);
    });

    testWidgets(
        'dirty (stagedCount: 3) shows an enabled "שמור · 3" and a working בטל הכל',
        (tester) async {
      var saveTapped = false;
      var discardTapped = false;

      await pump(
        tester,
        stagedCount: 3,
        onSave: () => saveTapped = true,
        onDiscardAll: () => discardTapped = true,
      );

      expect(find.text('שמור · 3'), findsOneWidget);
      expect(find.text('בטל הכל'), findsOneWidget);

      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'שמור · 3'),
      );
      expect(saveButton.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'שמור · 3'));
      await tester.pump();
      expect(saveTapped, isTrue);
      expect(discardTapped, isFalse);

      await tester.tap(find.widgetWithText(OutlinedButton, 'בטל הכל'));
      await tester.pump();
      expect(discardTapped, isTrue);
    });
  });
}
