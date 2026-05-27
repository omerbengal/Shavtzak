import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/log_event.dart';

void main() {
  group('LogEvent', () {
    test('constructs with required fields', () {
      final now = DateTime.utc(2026, 5, 18, 14, 30);
      final e = LogEvent(
        timestamp: now,
        type: LogEventType.action,
        name: 'openMemberModal',
        context: const {'memberId': 'm_abc'},
      );
      expect(e.timestamp, now);
      expect(e.type, LogEventType.action);
      expect(e.name, 'openMemberModal');
      expect(e.context['memberId'], 'm_abc');
      expect(e.duration, isNull);
    });

    test('optional duration is preserved', () {
      final e = LogEvent(
        timestamp: DateTime.utc(2026, 5, 18),
        type: LogEventType.loadEnd,
        name: 'memberAvailability',
        context: const {},
        duration: const Duration(milliseconds: 152),
      );
      expect(e.duration, const Duration(milliseconds: 152));
    });

    test('context map is unmodifiable from outside', () {
      final e = LogEvent(
        timestamp: DateTime.utc(2026, 5, 18),
        type: LogEventType.action,
        name: 'x',
        context: const {'a': 1},
      );
      expect(() => (e.context as Map)['b'] = 2, throwsUnsupportedError);
    });

    test('LogEventType enum has the documented 13 values', () {
      expect(LogEventType.values, hasLength(13));
      expect(LogEventType.values, containsAll(<LogEventType>[
        LogEventType.nav,
        LogEventType.action,
        LogEventType.blocDispatch,
        LogEventType.blocEmit,
        LogEventType.blocNoEmit,
        LogEventType.blocError,
        LogEventType.dbStart,
        LogEventType.dbEnd,
        LogEventType.dbStreamEmit,
        LogEventType.dbError,
        LogEventType.loadStart,
        LogEventType.loadEnd,
        LogEventType.warning,
      ]));
    });
  });
}
