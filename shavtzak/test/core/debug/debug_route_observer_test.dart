import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/debug_route_observer.dart';
import 'package:shavtzak/core/debug/log_event.dart';

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  PageRoute<dynamic> route(String name) =>
      MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
        settings: RouteSettings(name: name),
      );

  test('didPush resets the buffer with the new route name', () {
    final obs = DebugRouteObserver();
    obs.didPush(route('/admin/events'), route('/admin/team-members'));
    final ev = DebugLogger.instance.events;
    expect(ev, hasLength(1));
    expect(ev.single.type, LogEventType.nav);
    expect(ev.single.name, '/admin/events');
  });

  test('didReplace resets with the replacement route name', () {
    final obs = DebugRouteObserver();
    obs.didReplace(
      newRoute: route('/admin/assignments'),
      oldRoute: route('/admin/events'),
    );
    expect(DebugLogger.instance.events.single.name, '/admin/assignments');
  });

  test('didPop of a PageRoute (page back-nav) resets to the revealed page', () {
    final obs = DebugRouteObserver();
    obs.didPop(
      MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
        settings: const RouteSettings(name: '/admin/events'),
      ),
      MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
        settings: const RouteSettings(name: '/admin/team-members'),
      ),
    );
    final ev = DebugLogger.instance.events;
    expect(ev, hasLength(1));
    expect(ev.single.type, LogEventType.nav);
    expect(ev.single.name, '/admin/team-members');
  });

  test('null route name falls back to "<unknown>"', () {
    final obs = DebugRouteObserver();
    obs.didPush(
      MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      null,
    );
    expect(DebugLogger.instance.events.single.name, '<unknown>');
  });

  testWidgets('didPush on a DialogRoute does NOT reset the buffer',
      (tester) async {
    // Seed an event so we can detect a reset (which would clear it)
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.utc(2026, 5, 28),
      type: LogEventType.action,
      name: 'precondition',
      context: const {},
    ));

    // Pump a host so we have a real BuildContext to construct DialogRoute
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        capturedContext = ctx;
        return const SizedBox.shrink();
      }),
    ));

    final dialogRoute = DialogRoute<void>(
      context: capturedContext,
      builder: (_) => const SizedBox.shrink(),
    );
    final pageRoute = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
      settings: const RouteSettings(name: '/x'),
    );

    final obs = DebugRouteObserver();
    obs.didPush(dialogRoute, pageRoute);

    // Buffer should still contain the precondition event — no reset happened
    expect(DebugLogger.instance.events.map((e) => e.name),
        contains('precondition'));
  });

  test('didPush on a ModalBottomSheetRoute does NOT reset', () {
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.utc(2026, 5, 28),
      type: LogEventType.action,
      name: 'precondition',
      context: const {},
    ));
    final sheetRoute = ModalBottomSheetRoute<void>(
      builder: (_) => const SizedBox.shrink(),
      isScrollControlled: false,
    );
    final pageRoute = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
      settings: const RouteSettings(name: '/x'),
    );
    final obs = DebugRouteObserver();
    obs.didPush(sheetRoute, pageRoute);
    expect(DebugLogger.instance.events.map((e) => e.name),
        contains('precondition'));
  });

  test('didPop of a ModalBottomSheetRoute (revealing a page) does NOT reset',
      () {
    // Reproduces the production bug: closing a dialog/sheet was wiping the
    // buffer because the guard checked previousRoute (the page beneath)
    // instead of route (the popup being dismissed).
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.utc(2026, 5, 28),
      type: LogEventType.action,
      name: 'precondition',
      context: const {},
    ));
    final sheetRoute = ModalBottomSheetRoute<void>(
      builder: (_) => const SizedBox.shrink(),
      isScrollControlled: false,
    );
    final pageBeneath = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
      settings: const RouteSettings(name: '/user/assignments'),
    );
    final obs = DebugRouteObserver();
    // route = the sheet being popped; previousRoute = the page revealed
    obs.didPop(sheetRoute, pageBeneath);
    // Buffer must still contain 'precondition' — dismissing a sheet must
    // NOT reset.
    expect(DebugLogger.instance.events.map((e) => e.name),
        contains('precondition'));
  });

  testWidgets('didPop of a DialogRoute (revealing a page) does NOT reset',
      (tester) async {
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.utc(2026, 5, 28),
      type: LogEventType.action,
      name: 'precondition',
      context: const {},
    ));
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        capturedContext = ctx;
        return const SizedBox.shrink();
      }),
    ));
    final dialogRoute = DialogRoute<void>(
      context: capturedContext,
      builder: (_) => const SizedBox.shrink(),
    );
    final pageBeneath = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
      settings: const RouteSettings(name: '/user/assignments'),
    );
    final obs = DebugRouteObserver();
    obs.didPop(dialogRoute, pageBeneath);
    expect(DebugLogger.instance.events.map((e) => e.name),
        contains('precondition'));
  });
}
