import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_sheet.dart';

void main() {
  late int closes;
  late int backs;
  late int aboveTaps;

  Future<void> pumpSheet(
    WidgetTester tester, {
    Object viewKey = 'one',
    bool withBack = false,
    int bodyLines = 3,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    closes = 0;
    backs = 0;
    aboveTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ElevatedButton(
                  onPressed: () => aboveTaps++,
                  child: const Text('מעל'),
                ),
              ),
              TaskSheet(
                viewKey: viewKey,
                content: SheetContent(
                  header: const Text('כותרת'),
                  body: Column(
                    children: [
                      for (var i = 0; i < bodyLines; i++)
                        SizedBox(height: 60, child: Text('שורה $i')),
                    ],
                  ),
                ),
                onClose: () => closes++,
                onBack: withBack ? () => backs++ : null,
              ),
            ],
          ),
        ),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('slides up from the bottom as it opens', (tester) async {
    await pumpSheet(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 60));
    final finalTop = 1000 * (1 - TaskStyle.sheetMaxSize);
    final midway = tester.getTopLeft(find.byKey(const Key('task-sheet'))).dy;
    expect(midway, greaterThan(finalTop + 20));

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('task-sheet'))).dy,
        closeTo(finalTop, 2));
  });

  testWidgets('opens all the way up', (tester) async {
    await pumpSheet(tester);

    expect(
      tester.getTopLeft(find.byKey(const Key('task-sheet'))).dy,
      closeTo(1000 * (1 - TaskStyle.sheetMaxSize), 2),
    );
  });

  testWidgets('what is above it stays tappable', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('מעל'));
    expect(aboveTaps, 1);
  });

  testWidgets('the X closes it', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('task-sheet-close')));
    expect(closes, 1);
  });

  testWidgets('the back arrow shows only with onBack', (tester) async {
    await pumpSheet(tester);
    expect(find.byKey(const Key('task-sheet-back')), findsNothing);

    await pumpSheet(tester, withBack: true);
    await tester.tap(find.byKey(const Key('task-sheet-back')));
    expect(backs, 1);
  });

  testWidgets('dragging it down closes it', (tester) async {
    await pumpSheet(tester);

    await tester.drag(
      find.byKey(const Key('task-sheet-handle')),
      const Offset(0, 950),
    );
    await tester.pumpAndSettle();
    expect(closes, 1);
  });

  testWidgets('new content starts at its top', (tester) async {
    await pumpSheet(tester, bodyLines: 40);
    // The first drag grows the sheet to its full height; the second scrolls.
    await tester.drag(find.byKey(const Key('task-sheet-handle')),
        const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.drag(find.text('שורה 5'), const Offset(0, -1500));
    await tester.pumpAndSettle();
    // The body is one box, so scrolled-away lines stay built: test what can
    // be seen.
    expect(find.text('שורה 0').hitTestable(), findsNothing);

    await pumpSheet(tester, viewKey: 'two', bodyLines: 40);
    await tester.pumpAndSettle();
    expect(find.text('שורה 0').hitTestable(), findsOneWidget);
  });
}
