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

  test('didPop resets with the destination route name', () {
    final obs = DebugRouteObserver();
    obs.didPop(route('/admin/events'), route('/admin/team-members'));
    expect(DebugLogger.instance.events.single.name, '/admin/team-members');
  });

  test('null route name falls back to "<unknown>"', () {
    final obs = DebugRouteObserver();
    obs.didPush(
      MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      null,
    );
    expect(DebugLogger.instance.events.single.name, '<unknown>');
  });
}
