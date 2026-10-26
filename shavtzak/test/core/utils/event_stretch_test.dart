// What the shared case table (test/domain/event_conflict_cases_test.dart)
// doesn't pin: the interval type itself, how many intervals a recurring
// constraint yields, the strict time parser and the DST night.
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

void main() {
  group('WallInterval.overlaps', () {
    final evening = WallInterval(
        DateTime.utc(2026, 12, 1, 17), DateTime.utc(2026, 12, 1, 22));

    test('touching at either end is not an overlap', () {
      expect(
          evening.overlaps(WallInterval(
              DateTime.utc(2026, 12, 1, 15), DateTime.utc(2026, 12, 1, 17))),
          isFalse);
      expect(
          evening.overlaps(WallInterval(
              DateTime.utc(2026, 12, 1, 22), DateTime.utc(2026, 12, 1, 23))),
          isFalse);
    });

    test('one shared minute is an overlap, both ways', () {
      final other = WallInterval(
          DateTime.utc(2026, 12, 1, 21, 59), DateTime.utc(2026, 12, 1, 23));
      expect(evening.overlaps(other), isTrue);
      expect(other.overlaps(evening), isTrue);
    });

    test('an interval inside the other overlaps', () {
      expect(
          evening.overlaps(WallInterval(
              DateTime.utc(2026, 12, 1, 18), DateTime.utc(2026, 12, 1, 19))),
          isTrue);
    });
  });

  group('constraintIntervalsNear', () {
    test(
        'a weekly Wednesday over a Tuesday–Wednesday stretch yields one '
        'interval, on the Wednesday', () {
      // 2026-10-27 is a Tuesday.
      final stretch = eventStretch(_event(
        DateTime(2026, 10, 27),
        DateTime(2026, 10, 28),
        assemblyTime: '18:00',
        teamEndTime: '23:00',
      ));
      final weekly = DateConstraint(
        id: 'weekly',
        startDate: DateTime(2026, 10, 1),
        constraintType: ConstraintType.unavailability,
        startTime: '18:00',
        endTime: '20:00',
        repeatType: RepeatType.weekly,
        repeatDay: DateTime.wednesday,
        repeatEndDate: DateTime(2026, 12, 31),
      );

      expect(constraintIntervalsNear(weekly, stretch), [
        WallInterval(
            DateTime.utc(2026, 10, 28, 18), DateTime.utc(2026, 10, 28, 20)),
      ]);
    });

    test(
        'a daily constraint yields one interval per day from the day before '
        'the stretch to its last day', () {
      final stretch = eventStretch(_event(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 2),
        assemblyTime: '18:00',
        teamEndTime: '10:00',
      ));
      final daily = DateConstraint(
        id: 'daily',
        startDate: DateTime(2026, 10, 1),
        constraintType: ConstraintType.unavailability,
        repeatType: RepeatType.daily,
        repeatEndDate: DateTime(2026, 12, 31),
      );

      expect(constraintIntervalsNear(daily, stretch), [
        WallInterval(DateTime.utc(2026, 11, 30), DateTime.utc(2026, 12, 1)),
        WallInterval(DateTime.utc(2026, 12, 1), DateTime.utc(2026, 12, 2)),
        WallInterval(DateTime.utc(2026, 12, 2), DateTime.utc(2026, 12, 3)),
      ]);
    });

    test(
        'a one-time constraint over several days is one interval from its '
        'start time on the first day to its end time on the last', () {
      final stretch = eventStretch(_event(
          DateTime(2026, 10, 2), DateTime(2026, 10, 2),
          assemblyTime: '09:00', teamEndTime: '12:00'));
      final span = DateConstraint(
        id: 'span',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 3),
        constraintType: ConstraintType.unavailability,
        startTime: '17:00',
        endTime: '11:00',
      );

      expect(constraintIntervalsNear(span, stretch), [
        WallInterval(
            DateTime.utc(2026, 10, 1, 17), DateTime.utc(2026, 10, 3, 11)),
      ]);
    });
  });

  group('eventStretch', () {
    test(
        'a stretch on the DST-end night (2026-10-25) from 20:00 to 02:00 '
        'lasts exactly 6 hours', () {
      final stretch = eventStretch(_event(
          DateTime(2026, 10, 25), DateTime(2026, 10, 25),
          assemblyTime: '20:00', teamEndTime: '02:00'));

      expect(stretch.start, DateTime.utc(2026, 10, 25, 20));
      expect(stretch.end, DateTime.utc(2026, 10, 26, 2));
      expect(stretch.end.difference(stretch.start), const Duration(hours: 6));
    });

    test(
        'a show ending past midnight with no team end rolls to the next '
        'morning, so 23:00–23:59 that day blocks (E1 as the spec states it)',
        () {
      // The table's B1 has a show end of 23:30, which the old app rule read
      // first; this pins the literal E1 shape, show end 01:00, which the old
      // per-day minutes comparison judged free.
      final event = _event(DateTime(2026, 12, 7), DateTime(2026, 12, 7),
          startTime: '20:00', endTime: '01:00');
      final constraint = DateConstraint(
        id: 'late',
        startDate: DateTime(2026, 12, 7),
        constraintType: ConstraintType.unavailability,
        startTime: '23:00',
        endTime: '23:59',
      );
      final member = TeamMember(
        id: 'm1',
        name: 'חבר',
        isActive: true,
        isPermanent: true,
        constraints: [constraint],
        roleCapabilities: const {},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        uniqueKey: 'k1',
      );

      expect(
          eventStretch(event),
          WallInterval(
              DateTime.utc(2026, 12, 7, 20), DateTime.utc(2026, 12, 8, 1)));
      expect(member.isAvailableForEventWithTime(event), isFalse);
    });

    test('moments are UTC wall-clock values', () {
      final stretch = eventStretch(_event(
          DateTime(2026, 12, 1), DateTime(2026, 12, 1),
          assemblyTime: '17:00', teamEndTime: '22:00'));

      expect(stretch.start.isUtc, isTrue);
      expect(stretch.end.isUtc, isTrue);
    });
  });

  group('wallTimeMinutes', () {
    test('reads two-digit HH:mm from 00:00 to 23:59', () {
      expect(wallTimeMinutes('00:00'), 0);
      expect(wallTimeMinutes('09:05'), 9 * 60 + 5);
      expect(wallTimeMinutes('23:59'), 23 * 60 + 59);
    });

    test('anything else is missing, never a throw', () {
      for (final value in [
        null,
        '',
        '24:00',
        '23:60',
        '9:00',
        '16:00 ',
        ' 16:00',
        '16:0',
        '16-00',
        'ab:cd',
        '١٦:٠٠',
      ]) {
        expect(wallTimeMinutes(value), isNull, reason: '"$value"');
      }
    });
  });

  group('formatWallMoment', () {
    test("writes 'yyyy-MM-ddTHH:mm' from the wall-clock fields", () {
      expect(
          formatWallMoment(DateTime.utc(2026, 3, 7, 4, 5)), '2026-03-07T04:05');
      expect(formatWallMoment(DateTime.utc(2026, 12, 31, 23, 59)),
          '2026-12-31T23:59');
    });
  });
}

Event _event(
  DateTime startDate,
  DateTime endDate, {
  String assemblyTime = '',
  String startTime = '',
  String endTime = '',
  String teamEndTime = '',
}) {
  final now = DateTime(2026, 1, 1);
  return Event(
    id: 'e1',
    name: 'אירוע',
    startDate: startDate,
    endDate: endDate,
    assemblyTime: assemblyTime,
    startTime: startTime,
    endTime: endTime,
    teamEndTime: teamEndTime,
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}
