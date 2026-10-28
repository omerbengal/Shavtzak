// The small helpers around an assignment's custom hours: how they read as
// text, the day arithmetic, the "did this event save move it in time" check
// that decides whether the admin must resolve hours, and the constraint
// warning lines.
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/custom_hours.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

void main() {
  group('formatCustomHours', () {
    test('within one day: the day once, the times joined by a dash', () {
      expect(
        formatCustomHours(WallInterval(
          DateTime.utc(2026, 10, 27, 14),
          DateTime.utc(2026, 10, 27, 23),
        )),
        '27.10 14:00–23:00',
      );
    });

    test('across days: each end names its day', () {
      expect(
        formatCustomHours(WallInterval(
          DateTime.utc(2026, 10, 27, 14),
          DateTime.utc(2026, 10, 28, 2),
        )),
        '27.10 14:00 – 28.10 02:00',
      );
    });

    test('an end at exactly midnight shows as the next day at 00:00', () {
      expect(
        formatCustomHours(WallInterval(
          DateTime.utc(2026, 10, 27, 18),
          DateTime.utc(2026, 10, 28),
        )),
        '27.10 18:00 – 28.10 00:00',
      );
    });

    test('days are not padded, times are', () {
      expect(
        formatCustomHours(WallInterval(
          DateTime.utc(2026, 3, 5, 9, 5),
          DateTime.utc(2026, 3, 5, 10, 0),
        )),
        '5.3 09:05–10:00',
      );
    });
  });

  group('formatWallDay and formatWallTime', () {
    test('a day is d.M with no padding; a time is HH:mm with it', () {
      final moment = DateTime.utc(2026, 3, 5, 9, 7);
      expect(formatWallDay(moment), '5.3');
      expect(formatWallTime(moment), '09:07');
    });

    test('a local date reads the same way', () {
      expect(formatWallDay(DateTime(2026, 10, 27)), '27.10');
    });
  });

  group('firstCustomWindow', () {
    Assignment held(String id, {String? start, String? end}) => Assignment(
          id: id,
          eventId: 'e1',
          teamMemberId: 'm1',
          roleType: 'medic',
          slotIndex: 0,
          status: AssignmentStatus.confirmed,
          notes: '',
          customStartAt: start,
          customEndAt: end,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        );

    test('is the first assignment\'s window, in the order given', () {
      final window = firstCustomWindow([
        held('a1'),
        held('a2', start: '2026-10-27T14:00', end: '2026-10-27T23:00'),
        held('a3', start: '2026-10-28T08:00', end: '2026-10-28T12:00'),
      ]);

      expect(
        window,
        WallInterval(DateTime.utc(2026, 10, 27, 14), DateTime.utc(2026, 10, 27, 23)),
      );
    });

    test('skips hours that cannot be read or end before they start', () {
      final window = firstCustomWindow([
        held('a1', start: 'garbage', end: '2026-10-27T23:00'),
        held('a2', start: '2026-10-27T23:00', end: '2026-10-27T14:00'),
        held('a3', start: '2026-10-28T08:00', end: '2026-10-28T12:00'),
      ]);

      expect(
        window,
        WallInterval(DateTime.utc(2026, 10, 28, 8), DateTime.utc(2026, 10, 28, 12)),
      );
    });

    test('is null when no assignment has usable hours', () {
      expect(firstCustomWindow([held('a1'), held('a2', start: 'x', end: 'y')]),
          isNull);
      expect(firstCustomWindow(const []), isNull);
    });
  });

  group('calendarDaysBetween', () {
    test('the same day is 0, whatever the times', () {
      expect(
        calendarDaysBetween(DateTime(2026, 10, 27, 8), DateTime(2026, 10, 27, 23)),
        0,
      );
    });

    test('counts calendar days, not 24-hour spans', () {
      expect(
        calendarDaysBetween(DateTime(2026, 10, 27, 23), DateTime(2026, 10, 28, 1)),
        1,
      );
    });

    test('is exact across the October DST change', () {
      expect(calendarDaysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
      expect(calendarDaysBetween(DateTime(2026, 10, 20), DateTime(2026, 11, 3)), 14);
    });

    test('is negative when the second day is earlier', () {
      expect(calendarDaysBetween(DateTime(2026, 10, 28), DateTime(2026, 10, 25)), -3);
    });

    test('works across a month and a year', () {
      expect(calendarDaysBetween(DateTime(2026, 12, 30), DateTime(2027, 1, 2)), 3);
    });
  });

  group('memberFirstName', () {
    test('the first whitespace token', () {
      expect(memberFirstName('דנה כהן'), 'דנה');
      expect(memberFirstName('  דנה   בן  כהן '), 'דנה');
      expect(memberFirstName('דנה'), 'דנה');
    });

    test('an empty name is empty', () {
      expect(memberFirstName(''), '');
      expect(memberFirstName('   '), '');
    });
  });

  group('eventTimesChanged', () {
    final base = _event();

    test('the same event has not changed', () {
      expect(eventTimesChanged(base, _event()), isFalse);
    });

    test('only teamEndTime changed', () {
      expect(eventTimesChanged(base, _event(teamEndTime: '23:30')), isTrue);
    });

    for (final (field, changed) in [
      ('assemblyTime', _event(assemblyTime: '16:30')),
      ('startTime', _event(startTime: '19:00')),
      ('actualShowStartTime', _event(actualShowStartTime: '20:15')),
      ('endTime', _event(endTime: '22:30')),
      ('teamEndTime', _event(teamEndTime: '23:30')),
    ]) {
      test('$field alone counts', () {
        expect(eventTimesChanged(base, changed), isTrue);
        expect(eventTimesChanged(changed, base), isTrue);
      });
    }

    test('only the name changed', () {
      expect(eventTimesChanged(base, _event(name: 'שם אחר')), isFalse);
    });

    test('only the location changed', () {
      expect(eventTimesChanged(base, _event(location: 'מקום אחר')), isFalse);
    });

    test('name and location together still do not count', () {
      expect(
        eventTimesChanged(base, _event(name: 'שם אחר', location: 'מקום אחר')),
        isFalse,
      );
    });

    test('other fields never count', () {
      expect(eventTimesChanged(base, _event(comments: 'הערה חדשה')), isFalse);
      expect(eventTimesChanged(base, _event(requiresArmed: true)), isFalse);
    });

    test('startDate moved one day', () {
      expect(
        eventTimesChanged(base, _event(startDate: DateTime(2026, 10, 28))),
        isTrue,
      );
    });

    test('endDate moved one day', () {
      expect(
        eventTimesChanged(base, _event(endDate: DateTime(2026, 10, 28))),
        isTrue,
      );
    });

    test('a different time of day on the same calendar day is not a change', () {
      expect(
        eventTimesChanged(
          _event(startDate: DateTime(2026, 10, 27)),
          _event(startDate: DateTime(2026, 10, 27, 21)),
        ),
        isFalse,
      );
      expect(
        eventTimesChanged(
          _event(endDate: DateTime(2026, 10, 27, 3)),
          _event(endDate: DateTime(2026, 10, 27, 22, 30)),
        ),
        isFalse,
      );
    });

    test('a day is judged by its own calendar fields, not by 24-hour spans', () {
      // 23:00 on the 27th to 01:00 on the 28th is two hours but one day apart.
      expect(
        eventTimesChanged(
          _event(startDate: DateTime(2026, 10, 27, 23)),
          _event(startDate: DateTime(2026, 10, 28, 1)),
        ),
        isTrue,
      );
    });

    test('surrounding spaces in a time are not a change', () {
      expect(
        eventTimesChanged(_event(endTime: '16:00'), _event(endTime: '16:00 ')),
        isFalse,
      );
      expect(
        eventTimesChanged(_event(endTime: ' 16:00'), _event(endTime: '16:00')),
        isFalse,
      );
    });

    test('empty and blank times are the same', () {
      expect(
        eventTimesChanged(
          _event(actualShowStartTime: ''),
          _event(actualShowStartTime: '  '),
        ),
        isFalse,
      );
    });

    test('a time given where there was none counts', () {
      expect(
        eventTimesChanged(
          _event(teamEndTime: ''),
          _event(teamEndTime: '23:00'),
        ),
        isTrue,
      );
      expect(
        eventTimesChanged(
          _event(teamEndTime: '23:00'),
          _event(teamEndTime: '   '),
        ),
        isTrue,
      );
    });
  });

  group('customHoursWarningLines', () {
    // A window that covers 28.10 entirely.
    final window = WallInterval(
      DateTime.utc(2026, 10, 28, 9),
      DateTime.utc(2026, 10, 28, 17),
    );

    test('a pending constraint says it awaits approval, with the first name',
        () {
      final member = _member('דנה כהן', [
        _unavailability(DateTime(2026, 10, 28), ConstraintStatus.pending),
      ]);
      expect(
        customHoursWarningLines(member, window),
        ['⚠️ מתנגש עם אילוץ ממתין לאישור של דנה: 28.10 (כל היום)'],
      );
    });

    test('an approved constraint says approved', () {
      final member = _member('דנה כהן', [
        _unavailability(DateTime(2026, 10, 28), ConstraintStatus.approved,
            startTime: '10:00', endTime: '12:00'),
      ]);
      expect(
        customHoursWarningLines(member, window),
        ['⚠️ מתנגש עם אילוץ מאושר של דנה: 28.10 10:00–12:00'],
      );
    });

    test('one line per blocking constraint, in the member\'s order', () {
      final member = _member('דנה כהן', [
        _unavailability(DateTime(2026, 10, 28), ConstraintStatus.approved,
            startTime: '10:00', endTime: '12:00'),
        _unavailability(DateTime(2026, 10, 28), ConstraintStatus.pending,
            startTime: '15:00', endTime: '16:00'),
      ]);
      expect(customHoursWarningLines(member, window), [
        '⚠️ מתנגש עם אילוץ מאושר של דנה: 28.10 10:00–12:00',
        '⚠️ מתנגש עם אילוץ ממתין לאישור של דנה: 28.10 15:00–16:00',
      ]);
    });

    test('constraints that miss the window, and rejected ones, give no line',
        () {
      final member = _member('דנה כהן', [
        _unavailability(DateTime(2026, 10, 29), ConstraintStatus.approved),
        _unavailability(DateTime(2026, 10, 28), ConstraintStatus.rejected),
        _unavailability(DateTime(2026, 10, 28), ConstraintStatus.approved,
            startTime: '18:00', endTime: '20:00'),
      ]);
      expect(customHoursWarningLines(member, window), isEmpty);
    });

    test('a member with no constraints gives no line', () {
      expect(customHoursWarningLines(_member('דנה כהן', const []), window),
          isEmpty);
    });
  });
}

Event _event({
  String name = 'אירוע',
  String location = '',
  String comments = '',
  bool requiresArmed = false,
  DateTime? startDate,
  DateTime? endDate,
  String assemblyTime = '16:00',
  String startTime = '18:00',
  String actualShowStartTime = '20:00',
  String endTime = '22:00',
  String teamEndTime = '23:00',
}) {
  final now = DateTime(2026, 10, 1);
  return Event(
    id: 'e1',
    name: name,
    location: location,
    comments: comments,
    startDate: startDate ?? DateTime(2026, 10, 27),
    endDate: endDate ?? DateTime(2026, 10, 27),
    assemblyTime: assemblyTime,
    startTime: startTime,
    actualShowStartTime: actualShowStartTime,
    endTime: endTime,
    teamEndTime: teamEndTime,
    requiresArmed: requiresArmed,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}

DateConstraint _unavailability(
  DateTime day,
  ConstraintStatus status, {
  String? startTime,
  String? endTime,
}) {
  return DateConstraint(
    id: 'c-${status.name}-${startTime ?? 'day'}',
    startDate: day,
    endDate: day,
    status: status,
    constraintType: ConstraintType.unavailability,
    startTime: startTime,
    endTime: endTime,
  );
}

TeamMember _member(String name, List<DateConstraint> constraints) {
  final now = DateTime(2026, 10, 1);
  return TeamMember(
    id: 'm1',
    name: name,
    isActive: true,
    isPermanent: true,
    constraints: constraints,
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'k1',
  );
}
