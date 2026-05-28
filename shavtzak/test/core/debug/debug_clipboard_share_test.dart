import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_clipboard_share.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/logger.dart';

Future<void> _pumpHost(WidgetTester tester,
    {required Future<void> Function(BuildContext) onTap}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => onTap(context),
          child: const Text('go'),
        ),
      ),
    ),
  ));
}

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  testWidgets('copies formatted buffer to clipboard and records action',
      (tester) async {
    Logger.action('precondition'); // seed a single buffer event
    final List<MethodCall> calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });

    await _pumpHost(tester, onTap: (ctx) async {
      await copyDebugLogsToClipboard(
        ctx,
        currentRouteForShare: '/admin/events',
        userDisplay: 'Boss',
        isAdmin: true,
        env: 'prod',
      );
    });

    await tester.tap(find.text('go'));
    await tester.pump();

    final setData = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    final payload = (setData.arguments as Map)['text'] as String;
    expect(payload, contains('=== Shavtzak Debug Log ==='));
    expect(payload, contains('precondition'));

    // Logger.action('debugShareLogsCopied', ...) was recorded
    final copied = DebugLogger.instance.events
        .where((e) => e.name == 'debugShareLogsCopied');
    expect(copied, hasLength(1));
    expect(copied.single.context['eventCount'], 1);

    // Success snackbar shown
    expect(find.textContaining('הלוג הועתק ללוח'), findsOneWidget);
  });

  testWidgets('records warning + shows error snackbar when clipboard throws',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'denied');
      }
      return null;
    });

    await _pumpHost(tester, onTap: (ctx) async {
      await copyDebugLogsToClipboard(
        ctx,
        currentRouteForShare: '/admin/events',
        userDisplay: '-',
        isAdmin: true,
        env: 'prod',
      );
    });

    await tester.tap(find.text('go'));
    await tester.pump();

    // Logger.warning recorded
    final warnings = DebugLogger.instance.events
        .where((e) => e.name == 'clipboardFailed');
    expect(warnings, hasLength(1));
    expect(warnings.single.context['code'], 'denied');

    // Error snackbar shown
    expect(find.text('שגיאה בהעתקה ללוח'), findsOneWidget);

    // No success Logger.action recorded
    expect(
        DebugLogger.instance.events
            .where((e) => e.name == 'debugShareLogsCopied'),
        isEmpty);
  });

  testWidgets('formats payload with "-" when userDisplay is null',
      (tester) async {
    String? capturedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        capturedText = (call.arguments as Map)['text'] as String;
      }
      return null;
    });

    await _pumpHost(tester, onTap: (ctx) async {
      await copyDebugLogsToClipboard(
        ctx,
        currentRouteForShare: '/admin/events',
        userDisplay: null,
        isAdmin: false,
        env: 'prod',
      );
    });

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(capturedText, isNotNull);
    expect(capturedText!, contains('User: -'));
  });
}
