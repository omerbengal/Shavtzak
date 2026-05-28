import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/logger.dart';
import 'package:shavtzak/presentation/widgets/swipeable_page_view.dart';
// ^ BottomNavWithDebugTrigger is exported from here

Future<void> _pumpBar(
  WidgetTester tester, {
  required int initialIndex,
  required void Function(int) onTap,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: BottomNavWithDebugTrigger(
        currentIndex: initialIndex,
        onTap: onTap,
        tabRoutes: const [
          '/user/assignments',
          '/user/constraints',
          '/user/checklist',
        ],
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment), label: 'האירועים שלי'),
          BottomNavigationBarItem(
              icon: Icon(Icons.block), label: 'המגבלות שלי'),
          BottomNavigationBarItem(
              icon: Icon(Icons.checklist), label: 'צ\'קליסט'),
        ],
        userDisplay: 'Boss',
        isAdmin: false,
        env: 'prod',
        miniFabHeroTag: 'debug-share-mini-fab-user',
        type: BottomNavigationBarType.fixed,
      ),
    ),
  ));
}

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  testWidgets('user-shell: short tap still navigates', (tester) async {
    int? tappedIndex;
    await _pumpBar(tester, initialIndex: 0, onTap: (i) => tappedIndex = i);
    await tester.tap(find.byIcon(Icons.block));
    await tester.pump();
    expect(tappedIndex, 1);
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('user-shell: long-press tab reveals mini-FAB', (tester) async {
    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final tabCenterX = (size.width / 3) * 0.5;
    final tabCenterY = size.height - 28;
    await tester.longPressAt(Offset(tabCenterX, tabCenterY));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets('user-shell: mini-FAB tap copies logs', (tester) async {
    Logger.action('precondition');
    final List<MethodCall> calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });

    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.longPressAt(Offset(size.width / 6, size.height - 28));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.bug_report));
    await tester.pump();

    final setData = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    expect((setData.arguments as Map)['text'],
        contains('=== Shavtzak Debug Log ==='));
    expect(
      DebugLogger.instance.events
          .where((e) => e.name == 'debugShareLogsCopied'),
      hasLength(1),
    );
  });
}
