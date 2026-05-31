import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/core/debug/search_action_logger.dart';

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  test('coalesces rapid keystrokes into one debounced filter:search',
      () async {
    final log = SearchActionLogger('teamMembers');
    log.onQueryChanged('d');
    log.onQueryChanged('da');
    log.onQueryChanged('dan'); // 3 chars, last value wins
    // Before the debounce elapses, nothing is logged.
    expect(DebugLogger.instance.events, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final ev = DebugLogger.instance.events;
    expect(ev, hasLength(1));
    expect(ev.single.type, LogEventType.action);
    expect(ev.single.name, 'filter:search');
    expect(ev.single.context['field'], 'teamMembers');
    expect(ev.single.context['queryLen'], '<3 chars>');
    expect(ev.single.context.containsKey('cleared'), false);
    log.dispose();
  });

  test('empty query logs cleared (not queryLen) and never the raw text',
      () async {
    final log = SearchActionLogger('events');
    log.onQueryChanged('secret');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    log.onQueryChanged(''); // cleared
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final last = DebugLogger.instance.events.last;
    expect(last.context['cleared'], true);
    expect(last.context.containsKey('queryLen'), false);
    // The raw query text must never appear in any recorded context.
    for (final e in DebugLogger.instance.events) {
      expect(e.context.values, isNot(contains('secret')));
    }
    log.dispose();
  });

  test('dispose cancels a pending debounce (no log fires)', () async {
    final log = SearchActionLogger('x');
    log.onQueryChanged('abc');
    log.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(DebugLogger.instance.events, isEmpty);
  });
}
