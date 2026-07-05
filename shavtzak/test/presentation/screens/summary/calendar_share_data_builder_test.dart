import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart';

Event makeEvent({
  String id = 'e1',
  String name = 'אירוע בדיקה',
  DateTime? startDate,
  DateTime? endDate,
  String startTime = '17:00',
  String endTime = '22:30',
  String assemblyTime = '15:00',
  String actualShowStartTime = '',
  String location = 'גן הפסלים||32.794000,34.989600',
  bool isDeactivated = false,
}) {
  final start = startDate ?? DateTime(2026, 7, 15);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: endDate ?? start,
    startTime: startTime,
    endTime: endTime,
    assemblyTime: assemblyTime,
    actualShowStartTime: actualShowStartTime,
    location: location,
    requiresArmed: false,
    roleRequirements: const {},
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    isDeactivated: isDeactivated,
  );
}

// 2026-07-05 is a Sunday.
final today = DateTime(2026, 7, 5);

void main() {
  group('buildShareEvent — time semantics (mirror of calendar sync)', () {
    test('assembly + main lines when all times present', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['התייצבות 15:00–17:00', 'מופע 17:00–22:30']);
    });

    test('actualShowStartTime overrides startTime as separator', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(actualShowStartTime: '18:00'),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['התייצבות 15:00–18:00', 'מופע 18:00–22:30']);
    });

    test('all-day when assemblyTime is empty', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(assemblyTime: ''),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['כל היום']);
    });

    test('all-day when endTime is empty', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(endTime: ''),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['כל היום']);
    });

    test('degraded main line when separator is empty (legacy data)', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(startTime: '', actualShowStartTime: ''),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['מופע עד 22:30']);
    });
  });

  group('buildShareEvent — location, past, continuation', () {
    test('strips hidden coordinates from location', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(),
        today: today,
        isContinuation: false,
      );
      expect(share.locationLine, 'גן הפסלים');
    });

    test('empty location yields empty locationLine', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(location: ''),
        today: today,
        isContinuation: false,
      );
      expect(share.locationLine, '');
    });

    test('isPast is true only when endDate is strictly before today', () {
      final past = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(startDate: DateTime(2026, 7, 4)),
        today: today,
        isContinuation: false,
      );
      final todayEvent = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(startDate: DateTime(2026, 7, 5)),
        today: today,
        isContinuation: false,
      );
      expect(past.isPast, isTrue);
      expect(todayEvent.isPast, isFalse);
    });

    test('continuation carries name only', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(
          startDate: DateTime(2026, 7, 8),
          endDate: DateTime(2026, 7, 10),
        ),
        today: today,
        isContinuation: true,
      );
      expect(share.isContinuation, isTrue);
      expect(share.timeLines, isEmpty);
      expect(share.locationLine, '');
    });
  });
}
