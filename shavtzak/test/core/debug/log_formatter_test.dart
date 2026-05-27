import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/core/debug/log_formatter.dart';

LogEvent _e({
  required LogEventType type,
  required String name,
  Map<String, Object?> context = const {},
  Duration? duration,
  int second = 0,
}) =>
    LogEvent(
      timestamp: DateTime.utc(2026, 5, 18, 14, 30, second),
      type: type,
      name: name,
      context: context,
      duration: duration,
    );

void main() {
  group('formatBuffer', () {
    test('renders header with user, env, route, captured, events count', () {
      final out = formatBuffer(
        events: const [],
        userDisplay: 'Boss',
        isAdmin: true,
        env: 'prod',
        currentRoute: '/admin/assignments',
        capturedAt: DateTime.utc(2026, 5, 18, 14, 30, 0, 123),
      );
      expect(out, contains('=== Shavtzak Debug Log ==='));
      expect(out, contains('User: Boss (admin)'));
      expect(out, contains('Env: prod'));
      expect(out, contains('Route: /admin/assignments'));
      expect(out, contains('Captured: 2026-05-18T14:30:00.123Z'));
      expect(out, contains('Events: 0'));
    });

    test('non-admin user is rendered without (admin)', () {
      final out = formatBuffer(
        events: const [],
        userDisplay: 'Joe',
        isAdmin: false,
        env: 'test',
        currentRoute: '/test/admin/events',
        capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('User: Joe |'));
      expect(out, isNot(contains('(admin)')));
    });

    test('renders one line per event with type, name, context', () {
      final out = formatBuffer(
        events: [
          _e(type: LogEventType.action, name: 'openMemberModal',
              context: const {'memberId': 'm_abc', 'isPermanent': false}),
        ],
        userDisplay: '-',
        isAdmin: true,
        env: 'prod',
        currentRoute: '/x',
        capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('] ACTION openMemberModal'));
      expect(out, contains('memberId: m_abc'));
      expect(out, contains('isPermanent: false'));
    });

    test('renders duration in ms for events that carry one', () {
      final out = formatBuffer(
        events: [
          _e(
            type: LogEventType.dbEnd,
            name: 'getEvents',
            context: const {'count': 12, 'ok': true},
            duration: const Duration(milliseconds: 152),
          ),
        ],
        userDisplay: '-', isAdmin: true, env: 'prod',
        currentRoute: '/x', capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('DB_END getEvents'));
      expect(out, contains('(152 ms)'));
    });

    test('truncates a single field longer than 200 chars', () {
      final long = 'x' * 500;
      final out = formatBuffer(
        events: [
          _e(type: LogEventType.warning, name: 'huge',
              context: {'blob': long}),
        ],
        userDisplay: '-', isAdmin: true, env: 'prod',
        currentRoute: '/x', capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('…(truncated)'));
      expect(out.length, lessThan(2000));
    });

    test('never contains a raw note value when redact was used', () {
      final out = formatBuffer(
        events: [
          _e(type: LogEventType.blocDispatch, name: 'AssignmentBloc ← Update',
              context: const {'note': '<6 chars>'}),
        ],
        userDisplay: '-', isAdmin: true, env: 'prod',
        currentRoute: '/x', capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('<6 chars>'));
      expect(out, isNot(contains('secret')));
    });
  });
}
