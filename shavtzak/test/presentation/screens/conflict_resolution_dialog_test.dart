// Widget tests for ConflictResolutionDialog — the Save-time
// conflict-resolution dialog. See docs/superpowers/specs/
// 2026-07-15-assignments-staged-save-design.md ("Resolution dialog (on
// Save)") and lib/presentation/bloc/assignment/models/assignment_conflict.dart.
//
// The dialog is opened the same way production code opens it
// (showDialog<Map<String, ConflictResolution>>), via a Builder button, so
// the popped Navigator result can be captured exactly as
// _onSavePressed does in assignment_list_screen.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/bloc/assignment/models/assignment_conflict.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/conflict_resolution_dialog.dart';

void main() {
  /// Pumps a MaterialApp with a single "open" button that shows the dialog
  /// via showDialog (mirroring _onSavePressed's real call site), taps it,
  /// and reports the popped result through [onResult].
  Future<void> pumpAndOpenDialog(
    WidgetTester tester,
    List<AssignmentConflict> conflicts, {
    required void Function(Map<String, ConflictResolution>? result) onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final result =
                    await showDialog<Map<String, ConflictResolution>>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      ConflictResolutionDialog(conflicts: conflicts),
                );
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

  const slotTaken = AssignmentConflict(
    slotKey: 'e1_medic_0',
    type: AssignmentConflictType.slotTaken,
    description: 'המשרה נתפסה: בינתיים שובץ שם אדם אחר ב-DB.',
  );

  const slotVanished = AssignmentConflict(
    slotKey: 'e1_medic_1',
    type: AssignmentConflictType.slotVanished,
    description: 'המכסה של "חובש" באירוע קטנה, והמשרה ששיבצת אליה כבר לא קיימת.',
  );

  const memberGoneDiscardOnly = AssignmentConflict(
    slotKey: 'e1_medic_2',
    type: AssignmentConflictType.memberGone,
    description: 'החבר ששובץ נמחק לצמיתות מהמערכת.',
    discardOnly: true,
  );

  group('ConflictResolutionDialog', () {
    testWidgets(
        'renders both descriptions for a 2-conflict list, and labels the '
        'slotVanished override "צור מחוץ למכסה" (not "דרוס DB")',
        (tester) async {
      Map<String, ConflictResolution>? result;
      await pumpAndOpenDialog(
        tester,
        [slotTaken, slotVanished],
        onResult: (r) => result = r,
      );

      // Both rows' descriptions are present.
      expect(find.text(slotTaken.description), findsOneWidget);
      expect(find.text(slotVanished.description), findsOneWidget);

      // slotTaken keeps the normal override label; slotVanished swaps it.
      // Exactly one of each confirms neither row leaked the other's label.
      expect(find.text('דרוס DB'), findsOneWidget);
      expect(find.text('צור מחוץ למכסה'), findsOneWidget);

      // Untouched: dialog is still open, no result reported yet.
      expect(result, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets(
        'every non-discardOnly conflict defaults to overrideDb without any interaction',
        (tester) async {
      Map<String, ConflictResolution>? result;
      await pumpAndOpenDialog(
        tester,
        [slotTaken, slotVanished],
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('שמור'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!['e1_medic_0'], ConflictResolution.overrideDb);
      expect(result!['e1_medic_1'], ConflictResolution.overrideDb);
    });

    testWidgets(
        'tapping קח הכל מה-DB then שמור returns BOTH slotKeys mapped to takeDb',
        (tester) async {
      Map<String, ConflictResolution>? result;
      await pumpAndOpenDialog(
        tester,
        [slotTaken, slotVanished],
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('קח הכל מה-DB'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('שמור'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, hasLength(2));
      expect(result!['e1_medic_0'], ConflictResolution.takeDb);
      expect(result!['e1_medic_1'], ConflictResolution.takeDb);
    });

    testWidgets('selecting קח מה-DB on a single row only affects that slotKey',
        (tester) async {
      Map<String, ConflictResolution>? result;
      await pumpAndOpenDialog(
        tester,
        [slotTaken, slotVanished],
        onResult: (r) => result = r,
      );

      // Two rows each render a "קח מה-DB" chip; tap only the first
      // (slotTaken's row, since rows render in list order).
      await tester.tap(find.text('קח מה-DB').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('שמור'));
      await tester.pumpAndSettle();

      expect(result!['e1_medic_0'], ConflictResolution.takeDb);
      // The untouched slotVanished row stays at its overrideDb default.
      expect(result!['e1_medic_1'], ConflictResolution.overrideDb);
    });

    testWidgets('tapping ביטול returns null', (tester) async {
      Map<String, ConflictResolution>? result = const {}; // sentinel
      var callbackInvoked = false;
      await pumpAndOpenDialog(
        tester,
        [slotTaken],
        onResult: (r) {
          result = r;
          callbackInvoked = true;
        },
      );

      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      expect(callbackInvoked, isTrue);
      expect(result, isNull);
    });

    testWidgets(
        'a discardOnly conflict renders the single הבנתי — בטל את השינוי '
        'control (no דרוס DB / קח מה-DB chips) and always resolves to takeDb',
        (tester) async {
      Map<String, ConflictResolution>? result;
      await pumpAndOpenDialog(
        tester,
        [memberGoneDiscardOnly],
        onResult: (r) => result = r,
      );

      expect(find.text('הבנתי — בטל את השינוי'), findsOneWidget);
      expect(find.text('דרוס DB'), findsNothing);
      expect(find.text('קח מה-DB'), findsNothing);

      await tester.tap(find.text('שמור'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, hasLength(1));
      expect(result!['e1_medic_2'], ConflictResolution.takeDb);
    });

    testWidgets(
        'bulk shortcuts leave a discardOnly row pinned to takeDb even after '
        'דרוס הכל',
        (tester) async {
      Map<String, ConflictResolution>? result;
      await pumpAndOpenDialog(
        tester,
        [slotTaken, memberGoneDiscardOnly],
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('דרוס הכל'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('שמור'));
      await tester.pumpAndSettle();

      expect(result!['e1_medic_0'], ConflictResolution.overrideDb);
      // Pinned regardless of the bulk override shortcut.
      expect(result!['e1_medic_2'], ConflictResolution.takeDb);
    });
  });
}
