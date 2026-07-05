import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart';
import 'package:shavtzak/presentation/screens/summary/widgets/calendar_share/calendar_share_models.dart';

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

  group('build — weeks mode', () {
    test('pads to full Sunday-start weeks and flags out-of-range days', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 6), // Monday
        rangeEnd: DateTime(2026, 7, 15), // Wednesday
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.mode, CalendarShareMode.weeks);
      expect(data.months, isEmpty);
      expect(data.weeks, hasLength(2));

      final firstDay = data.weeks.first.days.first!;
      expect(firstDay.date, DateTime(2026, 7, 5)); // padded Sunday
      expect(firstDay.inRange, isFalse);

      final lastDay = data.weeks.last.days.last!;
      expect(lastDay.date, DateTime(2026, 7, 18)); // padded Saturday
      expect(lastDay.inRange, isFalse);

      expect(data.weeks.first.days[1]!.inRange, isTrue); // Monday 6.7

      for (final week in data.weeks) {
        expect(week.days, hasLength(7));
        expect(week.days.whereType<CalendarShareDay>(), hasLength(7));
      }
    });

    test('single-day range yields a single week', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 8),
        rangeEnd: DateTime(2026, 7, 8),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.weeks, hasLength(1));
      final inRangeDays = data.weeks.first.days
          .whereType<CalendarShareDay>()
          .where((d) => d.inRange)
          .toList();
      expect(inRangeDays, hasLength(1));
      expect(inRangeDays.single.date, DateTime(2026, 7, 8));
    });

    test('day.isPast is true strictly before today', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 4),
        rangeEnd: DateTime(2026, 7, 6),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final days = <DateTime, CalendarShareDay>{
        for (final w in data.weeks)
          for (final d in w.days)
            if (d != null) d.date: d,
      };
      expect(days[DateTime(2026, 7, 4)]!.isPast, isTrue);
      expect(days[DateTime(2026, 7, 5)]!.isPast, isFalse);
    });

    test('event appears on its day with details', () {
      final data = CalendarShareDataBuilder.build(
        events: [makeEvent(startDate: DateTime(2026, 7, 8))],
        rangeStart: DateTime(2026, 7, 6),
        rangeEnd: DateTime(2026, 7, 15),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final wednesday = data.weeks.first.days[3]!; // index 3 = Wednesday
      expect(wednesday.date, DateTime(2026, 7, 8));
      expect(wednesday.events, hasLength(1));
      expect(wednesday.events.single.name, 'אירוע בדיקה');
      expect(wednesday.events.single.isContinuation, isFalse);
      expect(wednesday.events.single.timeLines, isNotEmpty);
    });

    test('multi-day event: details on first day, continuation after', () {
      final data = CalendarShareDataBuilder.build(
        events: [
          makeEvent(
            startDate: DateTime(2026, 7, 8),
            endDate: DateTime(2026, 7, 10),
          ),
        ],
        rangeStart: DateTime(2026, 7, 6),
        rangeEnd: DateTime(2026, 7, 15),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final week = data.weeks.first;
      expect(week.days[3]!.events.single.isContinuation, isFalse); // 8.7
      expect(week.days[4]!.events.single.isContinuation, isTrue); // 9.7
      expect(week.days[5]!.events.single.isContinuation, isTrue); // 10.7
      expect(week.days[6]!.events, isEmpty); // 11.7
    });

    test('multi-day event starting before range: details on first in-range day',
        () {
      final data = CalendarShareDataBuilder.build(
        events: [
          makeEvent(
            startDate: DateTime(2026, 7, 4),
            endDate: DateTime(2026, 7, 8),
          ),
        ],
        rangeStart: DateTime(2026, 7, 6),
        rangeEnd: DateTime(2026, 7, 15),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final week = data.weeks.first;
      expect(week.days[0]!.events, isEmpty); // 5.7 out of range
      expect(week.days[1]!.events.single.isContinuation, isFalse); // 6.7
      expect(week.days[2]!.events.single.isContinuation, isTrue); // 7.7
      expect(week.days[3]!.events.single.isContinuation, isTrue); // 8.7
    });

    test('deactivated events are excluded', () {
      final data = CalendarShareDataBuilder.build(
        events: [makeEvent(startDate: DateTime(2026, 7, 8), isDeactivated: true)],
        rangeStart: DateTime(2026, 7, 6),
        rangeEnd: DateTime(2026, 7, 15),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      for (final week in data.weeks) {
        for (final day in week.days) {
          expect(day!.events, isEmpty);
        }
      }
    });

    test('events within a day are chronologically ordered', () {
      final late = makeEvent(
        id: 'late',
        name: 'מאוחר',
        startDate: DateTime(2026, 7, 8),
        assemblyTime: '18:00',
        startTime: '19:00',
        endTime: '23:00',
      );
      final early = makeEvent(
        id: 'early',
        name: 'מוקדם',
        startDate: DateTime(2026, 7, 8),
        assemblyTime: '08:00',
        startTime: '09:00',
        endTime: '12:00',
      );
      final data = CalendarShareDataBuilder.build(
        events: [late, early], // intentionally unsorted
        rangeStart: DateTime(2026, 7, 8),
        rangeEnd: DateTime(2026, 7, 8),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final day = data.weeks.first.days
          .whereType<CalendarShareDay>()
          .firstWhere((d) => d.inRange);
      expect(day.events.map((e) => e.name).toList(), ['מוקדם', 'מאוחר']);
    });
  });

  group('build — range title', () {
    test('same month', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 5),
        rangeEnd: DateTime(2026, 7, 31),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.rangeTitle, '5–31 ביולי 2026');
    });

    test('cross month, same year', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.rangeTitle, '20 ביולי – 3 באוגוסט 2026');
    });

    test('cross year', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 12, 15),
        rangeEnd: DateTime(2027, 1, 10),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.rangeTitle, '15 בדצמבר 2026 – 10 בינואר 2027');
    });

    test('single day', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 8),
        rangeEnd: DateTime(2026, 7, 8),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.rangeTitle, '8 ביולי 2026');
    });
  });

  group('build — months mode', () {
    test('one grid per calendar month intersecting the range', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.months,
        today: today,
      );
      expect(data.mode, CalendarShareMode.months);
      expect(data.weeks, isEmpty);
      expect(data.months, hasLength(2));
      expect(data.months[0].title, 'יולי 2026');
      expect(data.months[1].title, 'אוגוסט 2026');
    });

    test('out-of-month cells are null, out-of-range days are dimmed', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.months,
        today: today,
      );
      final july = data.months[0];
      // 2026-07-01 is a Wednesday: Sun/Mon/Tue of the first week are blank.
      expect(july.weeks.first.days[0], isNull);
      expect(july.weeks.first.days[1], isNull);
      expect(july.weeks.first.days[2], isNull);
      expect(july.weeks.first.days[3]!.date, DateTime(2026, 7, 1));
      expect(july.weeks.first.days[3]!.inRange, isFalse); // before 20.7
      // A day inside the picked range:
      final allJulyDays = july.weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .toList();
      expect(
        allJulyDays.firstWhere((d) => d.date == DateTime(2026, 7, 20)).inRange,
        isTrue,
      );
      // Every in-month day belongs to July.
      for (final d in allJulyDays) {
        expect(d.date.month, 7);
      }
    });

    test('events land in the right month grid', () {
      final data = CalendarShareDataBuilder.build(
        events: [
          makeEvent(id: 'jul', name: 'ביולי', startDate: DateTime(2026, 7, 25)),
          makeEvent(id: 'aug', name: 'באוגוסט', startDate: DateTime(2026, 8, 1)),
        ],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.months,
        today: today,
      );
      final julyEvents = data.months[0].weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .expand((d) => d.events)
          .map((e) => e.name)
          .toList();
      final augustEvents = data.months[1].weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .expand((d) => d.events)
          .map((e) => e.name)
          .toList();
      expect(julyEvents, ['ביולי']);
      expect(augustEvents, ['באוגוסט']);
    });

    test('event spanning a month boundary continues into the next grid', () {
      final data = CalendarShareDataBuilder.build(
        events: [
          makeEvent(
            startDate: DateTime(2026, 7, 31),
            endDate: DateTime(2026, 8, 2),
          ),
        ],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.months,
        today: today,
      );
      final jul31 = data.months[0].weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .firstWhere((d) => d.date == DateTime(2026, 7, 31));
      final aug1 = data.months[1].weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .firstWhere((d) => d.date == DateTime(2026, 8, 1));
      expect(jul31.events.single.isContinuation, isFalse);
      expect(aug1.events.single.isContinuation, isTrue);
    });

    test('December→January range wraps the year with correct titles', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 12, 20),
        rangeEnd: DateTime(2027, 1, 5),
        mode: CalendarShareMode.months,
        today: today,
      );
      expect(data.months, hasLength(2));
      expect(data.months[0].title, 'דצמבר 2026');
      expect(data.months[1].title, 'ינואר 2027');
      final januaryDays = data.months[1].weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .toList();
      for (final d in januaryDays) {
        expect(d.date.year, 2027);
        expect(d.date.month, 1);
      }
    });
  });
}
