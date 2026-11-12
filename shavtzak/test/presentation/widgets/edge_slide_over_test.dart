import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/widgets/edge_slide_over.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: EdgeSlideOver(
          wide: width >= 1000,
          panelBuilder: (context, close) => Column(children: [
            const Text('panel'),
            TextButton(
              key: const Key('close'),
              onPressed: close,
              child: const Text('x'),
            ),
          ]),
          child: const Scaffold(body: Center(child: Text('screen'))),
        ),
      ),
    ));
  }

  /// The panel's left edge on screen; 0 = covering the screen.
  double panelLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const Key('slide-over-panel'))).dx;

  group('phone', () {
    testWidgets('no handle; nothing of the panel is built while closed',
        (tester) async {
      await pump(tester, width: 400);
      expect(find.byKey(const Key('slide-over-handle')), findsNothing);
      expect(find.text('panel'), findsNothing);
    });

    testWidgets('a swipe from the right edge past a third opens it fully',
        (tester) async {
      await pump(tester, width: 400);
      final gesture = await tester.startGesture(const Offset(395, 400));
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-180, 0));
      await tester.pump();
      // Follows the finger: partly in.
      expect(panelLeft(tester), inExclusiveRange(100, 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(panelLeft(tester), 0);
    });

    testWidgets('a swipe under a third slides it back out', (tester) async {
      await pump(tester, width: 400);
      await tester.dragFrom(const Offset(395, 400), const Offset(-90, 0));
      await tester.pumpAndSettle();
      expect(find.text('panel'), findsNothing);
    });

    testWidgets('a swipe that starts away from the edge does nothing',
        (tester) async {
      await pump(tester, width: 400);
      await tester.dragFrom(const Offset(200, 400), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(find.text('panel'), findsNothing);
    });

    Future<void> open(WidgetTester tester) async {
      await tester.dragFrom(const Offset(395, 400), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(panelLeft(tester), 0);
    }

    testWidgets('a rightward swipe anywhere on it of 15% closes it',
        (tester) async {
      await pump(tester, width: 400);
      await open(tester);
      await tester.dragFrom(const Offset(150, 600), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(find.text('panel'), findsNothing);
    });

    testWidgets('a shorter rightward swipe snaps it back open',
        (tester) async {
      await pump(tester, width: 400);
      await open(tester);
      await tester.dragFrom(const Offset(150, 600), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(panelLeft(tester), 0);
    });

    testWidgets('its close button closes it', (tester) async {
      await pump(tester, width: 400);
      await open(tester);
      await tester.tap(find.byKey(const Key('close')));
      await tester.pumpAndSettle();
      expect(find.text('panel'), findsNothing);
    });
  });

  group('wide', () {
    testWidgets('a "<" box on the right edge, vertically centred, opens it',
        (tester) async {
      await pump(tester, width: 1200);
      final handle = find.byKey(const Key('slide-over-handle'));
      expect(tester.getTopRight(handle).dx, 1200);
      expect(tester.getCenter(handle).dy, 400);
      expect(find.text('panel'), findsNothing);
      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(panelLeft(tester), 0);
      await tester.tap(find.byKey(const Key('close')));
      await tester.pumpAndSettle();
      expect(find.text('panel'), findsNothing);
    });

    testWidgets('no edge swipe', (tester) async {
      await pump(tester, width: 1200);
      await tester.dragFrom(const Offset(1195, 200), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('panel'), findsNothing);
    });
  });
}
