import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/task/widgets/stage_panel.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_sheet.dart';

void main() {
  late int closes;
  late int backs;

  Future<void> pumpPanel(
    WidgetTester tester, {
    SheetContent? content,
    bool withBack = false,
    Object viewKey = 'one',
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    closes = 0;
    backs = 0;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: StagePanel(
            viewKey: viewKey,
            content: content,
            onClose: () => closes++,
            onBack: withBack ? () => backs++ : null,
          ),
        ),
      ),
    ));
  }

  const content = SheetContent(
    header: Text('סדנאות'),
    body: Column(children: [Text('גוף השלב'), SizedBox(height: 2000)]),
  );

  testWidgets('new content starts at its top', (tester) async {
    await pumpPanel(tester, content: content);
    await tester.drag(find.text('גוף השלב'), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('גוף השלב').hitTestable(), findsNothing);

    await pumpPanel(tester, content: content, viewKey: 'two');
    await tester.pumpAndSettle();
    expect(find.text('גוף השלב').hitTestable(), findsOneWidget);
  });

  testWidgets('without content it shows the hint', (tester) async {
    await pumpPanel(tester);

    expect(find.byKey(const Key('stage-panel')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('stage-panel-hint')),
        matching: find.text('בחרו שלב בלוח כדי לראות את המשימות שלו'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stage-panel-close')), findsNothing);
  });

  testWidgets('with content it shows the header and a scrolling body',
      (tester) async {
    await pumpPanel(tester, content: content);

    expect(find.text('סדנאות'), findsOneWidget);
    expect(find.text('גוף השלב'), findsOneWidget);
    expect(find.byKey(const Key('stage-panel-hint')), findsNothing);
    expect(
      find.ancestor(
        of: find.text('גוף השלב'),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the X closes', (tester) async {
    await pumpPanel(tester, content: content);

    await tester.tap(find.byKey(const Key('stage-panel-close')));
    expect(closes, 1);
  });

  testWidgets('the back arrow shows only with onBack', (tester) async {
    await pumpPanel(tester, content: content);
    expect(find.byKey(const Key('stage-panel-back')), findsNothing);

    await pumpPanel(tester, content: content, withBack: true);
    await tester.tap(find.byKey(const Key('stage-panel-back')));
    expect(backs, 1);
    expect(closes, 0);
  });
}
