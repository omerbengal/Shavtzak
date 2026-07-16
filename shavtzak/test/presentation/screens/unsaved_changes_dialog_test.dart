// Widget tests for showUnsavedChangesDialog — the leave-guard reminder
// shown when navigating away from the assignments tab/screen with unsaved
// staged changes. See docs/superpowers/specs/
// 2026-07-15-assignments-staged-save-design.md ("Leave-guard").

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/unsaved_changes_dialog.dart';

void main() {
  /// Pumps a MaterialApp with a single "open" button that shows the dialog
  /// via showUnsavedChangesDialog (mirroring the real call sites), taps it,
  /// and reports the popped [LeaveDecision] through [onResult].
  Future<void> pumpAndOpenDialog(
    WidgetTester tester, {
    required int count,
    required void Function(LeaveDecision? result) onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final result =
                    await showUnsavedChangesDialog(context, count: count);
                onResult(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('showUnsavedChangesDialog', () {
    testWidgets('renders the title and the count in the body text',
        (tester) async {
      await pumpAndOpenDialog(
        tester,
        count: 4,
        onResult: (_) {},
      );

      expect(find.text('שינויי שיבוצים לא נשמרו'), findsOneWidget);
      expect(find.text('יש לך 4 שינויים שלא נשמרו.'), findsOneWidget);
    });

    testWidgets(
        'renders the clarifying subtext beneath צא בלי לשמור', (tester) async {
      await pumpAndOpenDialog(
        tester,
        count: 1,
        onResult: (_) {},
      );

      expect(find.text('צא בלי לשמור'), findsOneWidget);
      expect(
        find.text('השינויים לא נמחקים, ניתן לשמור אחר כך'),
        findsOneWidget,
      );
    });

    testWidgets('tapping שמור והמשך returns LeaveDecision.save',
        (tester) async {
      LeaveDecision? result;
      var callbackInvoked = false;
      await pumpAndOpenDialog(
        tester,
        count: 2,
        onResult: (r) {
          result = r;
          callbackInvoked = true;
        },
      );

      await tester.tap(find.text('שמור והמשך'));
      await tester.pumpAndSettle();

      expect(callbackInvoked, isTrue);
      expect(result, LeaveDecision.save);
    });

    testWidgets('tapping צא בלי לשמור returns LeaveDecision.leave',
        (tester) async {
      LeaveDecision? result;
      var callbackInvoked = false;
      await pumpAndOpenDialog(
        tester,
        count: 2,
        onResult: (r) {
          result = r;
          callbackInvoked = true;
        },
      );

      await tester.tap(find.text('צא בלי לשמור'));
      await tester.pumpAndSettle();

      expect(callbackInvoked, isTrue);
      expect(result, LeaveDecision.leave);
    });

    testWidgets('tapping ביטול returns LeaveDecision.cancel', (tester) async {
      LeaveDecision? result;
      var callbackInvoked = false;
      await pumpAndOpenDialog(
        tester,
        count: 2,
        onResult: (r) {
          result = r;
          callbackInvoked = true;
        },
      );

      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      expect(callbackInvoked, isTrue);
      expect(result, LeaveDecision.cancel);
    });
  });
}
