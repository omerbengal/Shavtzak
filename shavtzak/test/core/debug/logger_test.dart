import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/core/debug/logger.dart';

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  group('Logger.redact', () {
    test('returns "<N chars>" for non-null strings', () {
      expect(Logger.redact('hello'), '<5 chars>');
      expect(Logger.redact(''), '<0 chars>');
    });

    test('returns "<null>" for null', () {
      expect(Logger.redact(null), '<null>');
    });

    test('never returns the original content', () {
      expect(Logger.redact('secret-token-XYZ'), isNot(contains('secret')));
    });
  });

  group('Logger.action', () {
    test('records a LogEvent with type action and the given name+context', () {
      Logger.action('openMemberModal', {'memberId': 'm_abc'});
      final ev = DebugLogger.instance.events.single;
      expect(ev.type, LogEventType.action);
      expect(ev.name, 'openMemberModal');
      expect(ev.context['memberId'], 'm_abc');
      expect(ev.duration, isNull);
    });

    test('works without explicit context', () {
      Logger.action('x');
      final ev = DebugLogger.instance.events.single;
      expect(ev.context, isEmpty);
    });
  });

  group('Logger.loadingStart / loadingEnd', () {
    test('end computes duration from matching start', () async {
      Logger.loadingStart('memberAvailability', {'memberId': 'm_abc'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      Logger.loadingEnd('memberAvailability');
      final events = DebugLogger.instance.events;
      expect(events, hasLength(2));
      expect(events[0].type, LogEventType.loadStart);
      expect(events[1].type, LogEventType.loadEnd);
      expect(events[1].duration, isNotNull);
      expect(events[1].duration!.inMilliseconds, greaterThanOrEqualTo(20));
      expect(events[1].context['ok'], true);
    });

    test('end without matching start is recorded with unmatched: true', () {
      Logger.loadingEnd('phantom');
      final ev = DebugLogger.instance.events.single;
      expect(ev.type, LogEventType.loadEnd);
      expect(ev.duration, isNull);
      expect(ev.context['unmatched'], true);
    });

    test('end with ok=false records error info', () {
      Logger.loadingStart('op');
      Logger.loadingEnd('op', ok: false, error: 'boom');
      final ev = DebugLogger.instance.events.last;
      expect(ev.context['ok'], false);
      expect(ev.context['error'], 'boom');
    });
  });

  group('Logger.warning', () {
    test('records a warning event', () {
      Logger.warning('AssignmentBloc no-emit', {'reason': 'equatable-equal'});
      final ev = DebugLogger.instance.events.single;
      expect(ev.type, LogEventType.warning);
      expect(ev.name, 'AssignmentBloc no-emit');
      expect(ev.context['reason'], 'equatable-equal');
    });
  });
}
