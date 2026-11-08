import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/widgets/keep_focused_field_visible.dart';

void main() {
  // A dialog whose last field sits near the bottom of a phone-sized window.
  Future<void> pumpDialog(WidgetTester tester, {required bool wrapped}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          wrapped ? KeepFocusedFieldVisible(child: child!) : child!,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  content: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 450),
                        TextField(key: const Key('reason')),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Android browsers: the keyboard shrinks the window, no view inset.
  Future<void> openKeyboardByResize(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('reason')));
    await tester.pump();
    tester.view.physicalSize = const Size(400, 420);
    await tester.pump();
    await tester.pump(KeepFocusedFieldVisible.settle);
    await tester.pumpAndSettle();
  }

  bool fieldFullyVisible(WidgetTester tester) {
    final rect = tester.getRect(find.byKey(const Key('reason')));
    return rect.top >= 0 && rect.bottom <= 420;
  }

  testWidgets('without it the field stays below the shrunken window',
      (tester) async {
    await pumpDialog(tester, wrapped: false);
    await openKeyboardByResize(tester);
    expect(fieldFullyVisible(tester), isFalse);
  });

  testWidgets('scrolls the focused field into view when the window shrinks',
      (tester) async {
    await pumpDialog(tester, wrapped: true);
    await openKeyboardByResize(tester);
    expect(fieldFullyVisible(tester), isTrue);
  });
}
