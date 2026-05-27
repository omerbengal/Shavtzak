import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';

LogEvent _event(int i) => LogEvent(
      timestamp: DateTime.utc(2026, 5, 18).add(Duration(seconds: i)),
      type: LogEventType.action,
      name: 'evt_$i',
      context: {'i': i},
    );

void main() {
  setUp(() {
    DebugLogger.instance.debugClearForTests();
  });

  group('DebugLogger', () {
    test('records events in order', () {
      DebugLogger.instance.record(_event(0));
      DebugLogger.instance.record(_event(1));
      expect(DebugLogger.instance.events.map((e) => e.name),
          ['evt_0', 'evt_1']);
    });

    test('drops oldest event when at capacity', () {
      for (var i = 0; i < DebugLogger.capacity + 5; i++) {
        DebugLogger.instance.record(_event(i));
      }
      final names = DebugLogger.instance.events.map((e) => e.name).toList();
      expect(names, hasLength(DebugLogger.capacity));
      expect(names.first, 'evt_5');
      expect(names.last, 'evt_${DebugLogger.capacity + 4}');
    });

    test('reset clears buffer and records a NAV event', () {
      DebugLogger.instance.record(_event(0));
      DebugLogger.instance.record(_event(1));
      DebugLogger.instance.reset(newRoute: '/admin/events');
      final ev = DebugLogger.instance.events;
      expect(ev, hasLength(1));
      expect(ev.single.type, LogEventType.nav);
      expect(ev.single.name, '/admin/events');
      expect(ev.single.context['reset'], true);
    });

    test('events getter returns an unmodifiable view', () {
      DebugLogger.instance.record(_event(0));
      final ev = DebugLogger.instance.events;
      expect(() => ev.add(_event(1)), throwsUnsupportedError);
    });

    test('record never throws on weird context values', () {
      expect(() {
        DebugLogger.instance.record(LogEvent(
          timestamp: DateTime.now().toUtc(),
          type: LogEventType.action,
          name: 'odd',
          context: {'fn': () {}},
        ));
      }, returnsNormally);
    });
  });
}
