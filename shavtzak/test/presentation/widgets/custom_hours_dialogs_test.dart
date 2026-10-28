// The two small dialogs the custom-hours feature added or widened:
// CustomHoursConflictDialog (the warning before saving hours that overlap a
// constraint) and DualCalendarDatePicker.highlightLegend.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/widgets/custom_hours_conflict_dialog.dart';
import 'package:shavtzak/presentation/widgets/date_picker_dialog.dart';

void main() {
  group('CustomHoursConflictDialog', () {
    Future<Future<bool>> open(
      WidgetTester tester,
      List<String> lines,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (c) {
            context = c;
            return const Scaffold();
          }),
        ),
      );
      final result = CustomHoursConflictDialog.show(context, lines: lines);
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('shows the title, one text per line and both buttons',
        (tester) async {
      final result = await open(tester, [
        '⚠️ מתנגש עם אילוץ מאושר של דנה: 28.10 (כל היום)',
        '⚠️ מתנגש עם אילוץ ממתין לאישור של דנה: 29.10 (כל היום)',
      ]);

      expect(find.text('⚠️ התנגשות עם אילוצים'), findsOneWidget);
      expect(find.text('⚠️ מתנגש עם אילוץ מאושר של דנה: 28.10 (כל היום)'),
          findsOneWidget);
      expect(
          find.text('⚠️ מתנגש עם אילוץ ממתין לאישור של דנה: 29.10 (כל היום)'),
          findsOneWidget);
      expect(find.text('ביטול'), findsOneWidget);
      expect(find.text('שמור בכל זאת'), findsOneWidget);

      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('שמור בכל זאת answers true', (tester) async {
      final result = await open(tester, ['⚠️ שורה']);

      await tester.tap(find.text('שמור בכל זאת'));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
    });

    testWidgets('a dismissed dialog answers false', (tester) async {
      final result = await open(tester, ['⚠️ שורה']);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
    });
  });

  group('DualCalendarDatePicker.highlightLegend', () {
    Future<void> pump(WidgetTester tester, {String? legend}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DualCalendarDatePicker(
              isSingleDate: true,
              title: 'בחר תאריך',
              highlightedDates: {DateTime(2026, 11, 27)},
              highlightLegend: legend,
            ),
          ),
        ),
      );
    }

    testWidgets('null keeps the original red-frame text', (tester) async {
      await pump(tester);

      expect(find.text('מסגרת אדומה = יש אירוע בתאריך זה'), findsOneWidget);
    });

    testWidgets('a given legend replaces it', (tester) async {
      await pump(tester, legend: 'מסגרת = תחילת האירוע וסופו');

      expect(find.text('מסגרת = תחילת האירוע וסופו'), findsOneWidget);
      expect(find.text('מסגרת אדומה = יש אירוע בתאריך זה'), findsNothing);
    });
  });
}
