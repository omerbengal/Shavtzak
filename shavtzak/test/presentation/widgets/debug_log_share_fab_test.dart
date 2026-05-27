import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/logger.dart';
import 'package:shavtzak/presentation/widgets/debug_log_share_fab.dart';

Future<void> _pumpHost(WidgetTester tester, {required VoidCallback onTap})
    async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: const SizedBox.expand(),
      floatingActionButton: DebugLogShareFab(
        currentRouteForShare: '/admin/events',
        userDisplay: 'Boss',
        isAdmin: true,
        env: 'prod',
        child: FloatingActionButton(
          heroTag: 'host-fab',
          onPressed: onTap,
          child: const Icon(Icons.add),
        ),
      ),
    ),
  ));
}

void main() {
  setUp(() {
    DebugLogger.instance.debugClearForTests();
  });

  testWidgets('a tap still triggers the inner FAB.onPressed', (tester) async {
    var taps = 0;
    await _pumpHost(tester, onTap: () => taps++);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(taps, 1);
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('long-press reveals the mini-FAB', (tester) async {
    await _pumpHost(tester, onTap: () {});
    await tester.longPress(find.byIcon(Icons.add));
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
    await _pumpHost(tester, onTap: () {});
    await tester.longPress(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.bug_report));
    await tester.pump();

    final setData = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    final payload = (setData.arguments as Map)['text'] as String;
    expect(payload, contains('=== Shavtzak Debug Log ==='));
    expect(payload, contains('precondition'));

    expect(
      DebugLogger.instance.events
          .map((e) => e.name)
          .where((n) => n == 'debugShareLogsCopied'),
      hasLength(1),
    );
  });

  testWidgets('mini-FAB auto-dismisses after 4 seconds', (tester) async {
    await _pumpHost(tester, onTap: () {});
    await tester.longPress(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('second long-press hides the mini-FAB', (tester) async {
    await _pumpHost(tester, onTap: () {});
    await tester.longPress(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    await tester.longPress(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });
}
