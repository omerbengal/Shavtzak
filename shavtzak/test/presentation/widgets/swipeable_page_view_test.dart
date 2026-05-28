import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/logger.dart';

// NOTE: SwipeablePageView likely takes a StatefulNavigationShell argument
// that is not trivial to construct in isolation. The cleanest test path
// is to extract the "tab-trigger menu" widget into its own internal
// stateful widget that doesn't depend on the navigation shell, then test
// THAT widget here. See Step 3 — the implementation introduces the public
// widget `BottomNavWithDebugTrigger` that the tests exercise.
//
// If you choose to keep the logic inline in SwipeablePageView, this test
// file becomes more complex (you need a fake navigation shell). The
// recommended approach below assumes the helper widget extraction.

import 'package:shavtzak/presentation/widgets/swipeable_page_view.dart';

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
          '/admin/team-members',
          '/admin/events',
          '/admin/assignments',
          '/admin/checklist',
        ],
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'צוות'),
          BottomNavigationBarItem(icon: Icon(Icons.event), label: 'אירועים'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'שיבוצים'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'צ׳ק־ליסט'),
        ],
        userDisplay: 'Boss',
        isAdmin: true,
        env: 'prod',
        miniFabHeroTag: 'debug-share-mini-fab-admin',
      ),
    ),
  ));
}

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  testWidgets('short tap on a tab still navigates', (tester) async {
    int? tappedIndex;
    await _pumpBar(tester,
        initialIndex: 0, onTap: (i) => tappedIndex = i);
    await tester.tap(find.byIcon(Icons.event));
    await tester.pump();
    expect(tappedIndex, 1);
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('long-press a tab reveals the mini-FAB', (tester) async {
    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    // Long-press at the horizontal center of tab index 1 (events)
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final tabCenterX = (size.width / 4) * 1.5;
    final tabCenterY = size.height - 28; // roughly inside the nav bar
    await tester.longPressAt(Offset(tabCenterX, tabCenterY));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets('mini-FAB tap copies logs to clipboard + records action',
      (tester) async {
    Logger.action('precondition');
    final List<MethodCall> calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });

    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final tabCenterX = (size.width / 4) * 0.5;
    final tabCenterY = size.height - 28;
    await tester.longPressAt(Offset(tabCenterX, tabCenterY));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.bug_report));
    await tester.pump();

    final setData = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    final payload = (setData.arguments as Map)['text'] as String;
    expect(payload, contains('=== Shavtzak Debug Log ==='));
    expect(payload, contains('precondition'));

    expect(
      DebugLogger.instance.events
          .where((e) => e.name == 'debugShareLogsCopied'),
      hasLength(1),
    );
  });

  testWidgets('mini-FAB auto-dismisses after 4 seconds', (tester) async {
    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.longPressAt(Offset(size.width / 2, size.height - 28));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('second long-press on the same tab dismisses the mini-FAB',
      (tester) async {
    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final pos = Offset((size.width / 4) * 0.5, size.height - 28);
    await tester.longPressAt(pos);
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    await tester.longPressAt(pos);
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });
}
