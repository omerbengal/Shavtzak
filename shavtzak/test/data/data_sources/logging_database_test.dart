import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/data/data_sources/logging_database.dart';
import 'package:shavtzak/domain/entities/event.dart';

import 'logging_database_test.mocks.dart';

@GenerateMocks([DatabaseInterface])
void main() {
  late MockDatabaseInterface inner;
  late LoggingDatabase decorator;

  setUp(() {
    DebugLogger.instance.debugClearForTests();
    inner = MockDatabaseInterface();
    decorator = LoggingDatabase(inner);
  });

  test('one-shot read records DB_START then DB_END with count + ok', () async {
    when(inner.getEvents()).thenAnswer((_) async => <Event>[]);

    final result = await decorator.getEvents();

    verify(inner.getEvents()).called(1);
    final events = DebugLogger.instance.events;
    expect(
      events.map((e) => e.type),
      containsAllInOrder([LogEventType.dbStart, LogEventType.dbEnd]),
    );
    expect(events.last.context['ok'], true);
    expect(events.last.context['count'], result.length);
    expect(events.last.duration, isNotNull);
  });

  test('one-shot read that throws records DB_START then DB_ERROR', () async {
    when(inner.getEvents()).thenThrow(StateError('boom'));

    await expectLater(decorator.getEvents(), throwsStateError);

    final events = DebugLogger.instance.events;
    expect(
      events.map((e) => e.type),
      containsAllInOrder([LogEventType.dbStart, LogEventType.dbError]),
    );
    expect(events.last.context['error'], contains('StateError'));
  });

  test('stream watch records DB_START then DB_STREAM_EMIT per emission',
      () async {
    final ctl = StreamController<List<Event>>();
    final start = DateTime.utc(2026, 5, 18);
    final end = start.add(const Duration(days: 7));
    when(inner.watchEventsByDateRange(start, end))
        .thenAnswer((_) => ctl.stream);

    final subscription =
        decorator.watchEventsByDateRange(start, end).listen((_) {});

    ctl.add(<Event>[]);
    await Future<void>.delayed(Duration.zero);

    final types = DebugLogger.instance.events.map((e) => e.type).toList();
    expect(types, contains(LogEventType.dbStart));
    expect(types, contains(LogEventType.dbStreamEmit));

    await subscription.cancel();
    await ctl.close();
  });

  test('write returning void records DB_START then DB_END (no count)',
      () async {
    final ev = Event(
      id: 'e1',
      name: 'Test',
      startDate: DateTime.utc(2026, 5, 18),
      endDate: DateTime.utc(2026, 5, 18),
      startTime: '10:00',
      endTime: '12:00',
      assemblyTime: '09:30',
      requiresArmed: false,
      roleRequirements: const {},
      createdAt: DateTime.utc(2026, 5, 18),
      updatedAt: DateTime.utc(2026, 5, 18),
    );
    when(inner.insertEvent(ev)).thenAnswer((_) async {});

    await decorator.insertEvent(ev);

    verify(inner.insertEvent(ev)).called(1);
    final events = DebugLogger.instance.events;
    expect(events.last.type, LogEventType.dbEnd);
    expect(events.last.context['ok'], true);
    expect(events.last.context.containsKey('count'), false);
  });

  test('stream subscription cancellation records DB_END with disposed: true',
      () async {
    final ctl = StreamController<List<Event>>();
    final start = DateTime.utc(2026, 5, 18);
    final end = start.add(const Duration(days: 7));
    when(inner.watchEventsByDateRange(start, end))
        .thenAnswer((_) => ctl.stream);

    final subscription =
        decorator.watchEventsByDateRange(start, end).listen((_) {});
    await Future<void>.delayed(Duration.zero); // let subscription engage
    await subscription.cancel();
    await Future<void>.delayed(Duration.zero); // let cancellation propagate

    final disposedEvent = DebugLogger.instance.events
        .firstWhere((e) =>
            e.type == LogEventType.dbEnd && e.context['disposed'] == true);
    expect(disposedEvent.name, 'watchEventsByDateRange');
    expect(disposedEvent.duration, isNotNull);
    await ctl.close();
  });

  test('updateTeamMemberPasscode redacts the raw passcode value', () async {
    when(inner.updateTeamMemberPasscode('m_1', 'secret123', 9))
        .thenAnswer((_) async {});

    await decorator.updateTeamMemberPasscode('m_1', 'secret123', 9);

    // No LogEvent's context should contain the raw passcode value anywhere.
    for (final ev in DebugLogger.instance.events) {
      for (final value in ev.context.values) {
        expect(value, isNot(contains('secret123')),
            reason:
                'Raw passcode leaked in ${ev.type} context entry: $value');
      }
    }
    // The length signal should be preserved.
    final startEv = DebugLogger.instance.events
        .firstWhere((e) => e.type == LogEventType.dbStart);
    expect(startEv.context.values, contains(9));
  });
}
