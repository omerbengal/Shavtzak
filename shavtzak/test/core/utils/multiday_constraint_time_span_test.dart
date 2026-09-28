// A one-time constraint over several days with times set is one continuous
// block: it starts at startTime on its first day and ends at endTime on its
// last day. That is how Google Calendar already renders it; the reported bug
// was that the constraint dialogs refused 17:00 → 11:00 (end "before" start)
// and the conflict checks read the times as a window repeated on every day.
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/utils/constraint_event_overlap.dart';
import 'package:shavtzak/core/utils/time_range_utils.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

final _firstDay = DateTime(2026, 10, 1);
final _middleDay = DateTime(2026, 10, 2);
final _lastDay = DateTime(2026, 10, 3);

/// The reported constraint: from 17:00 on 01/10 until 11:00 on 03/10.
final _span = DateConstraint(
  id: 'span',
  startDate: _firstDay,
  endDate: _lastDay,
  status: ConstraintStatus.approved,
  constraintType: ConstraintType.unavailability,
  startTime: '17:00',
  endTime: '11:00',
);

void main() {
  group('TimeRangeUtils.isValidConstraintTimeRange', () {
    test('accepts an end time before the start time across several days', () {
      expect(
        TimeRangeUtils.isValidConstraintTimeRange('17:00', '11:00',
            spansMultipleDays: true),
        isTrue,
      );
    });

    test('still requires end after start within a single day', () {
      expect(
        TimeRangeUtils.isValidConstraintTimeRange('17:00', '11:00',
            spansMultipleDays: false),
        isFalse,
      );
      expect(
        TimeRangeUtils.isValidConstraintTimeRange('09:00', '17:00',
            spansMultipleDays: false),
        isTrue,
      );
    });

    test('rejects malformed times either way', () {
      expect(
        TimeRangeUtils.isValidConstraintTimeRange('25:00', '11:00',
            spansMultipleDays: true),
        isFalse,
      );
      expect(
        TimeRangeUtils.isValidConstraintTimeRange('17:00', '',
            spansMultipleDays: true),
        isFalse,
      );
    });
  });

  group('DateConstraint.timeWindowOn', () {
    test('first day runs from the start time to midnight', () {
      expect(_span.timeWindowOn(_firstDay), ('17:00', null));
    });

    test('days in between are covered whole', () {
      expect(_span.timeWindowOn(_middleDay), (null, null));
    });

    test('last day runs from midnight to the end time', () {
      expect(_span.timeWindowOn(_lastDay), (null, '11:00'));
    });

    test('a single-day constraint keeps its start–end window', () {
      final single = _span.copyWith(
          endDate: _firstDay, startTime: '09:00', endTime: '12:00');
      expect(single.timeWindowOn(_firstDay), ('09:00', '12:00'));
    });

    test('a recurring constraint repeats its window on every day', () {
      final daily = _span.copyWith(
        startTime: '09:00',
        endTime: '12:00',
        repeatType: RepeatType.daily,
        repeatEndDate: _lastDay,
      );
      expect(daily.timeWindowOn(_middleDay), ('09:00', '12:00'));
    });
  });

  group('constraintOverlapsEvent over a multi-day span', () {
    test('first day: an event before the start time is free', () {
      expect(
        constraintOverlapsEvent(
            constraint: _span, event: _event(_firstDay, '09:00', '12:00')),
        isFalse,
      );
    });

    test('first day: an event after the start time is blocked', () {
      expect(
        constraintOverlapsEvent(
            constraint: _span, event: _event(_firstDay, '18:00', '22:00')),
        isTrue,
      );
    });

    test('middle day: any event is blocked', () {
      expect(
        constraintOverlapsEvent(
            constraint: _span, event: _event(_middleDay, '09:00', '12:00')),
        isTrue,
      );
    });

    test('last day: an event before the end time is blocked', () {
      expect(
        constraintOverlapsEvent(
            constraint: _span, event: _event(_lastDay, '09:00', '10:00')),
        isTrue,
      );
    });

    test('last day: an event after the end time is free', () {
      expect(
        constraintOverlapsEvent(
            constraint: _span, event: _event(_lastDay, '12:00', '15:00')),
        isFalse,
      );
    });
  });

  group('DateConstraint.blocksEventAssignment over a multi-day span', () {
    test('uses the window of the day the event falls on', () {
      expect(_span.blocksEventAssignment(_event(_firstDay, '09:00', '12:00')),
          isFalse);
      expect(_span.blocksEventAssignment(_event(_middleDay, '09:00', '12:00')),
          isTrue);
      expect(_span.blocksEventAssignment(_event(_lastDay, '12:00', '15:00')),
          isFalse);
    });
  });

  group('TeamMember.isAvailableForEventWithTime over a multi-day span', () {
    final member = TeamMember(
      id: 'm1',
      name: 'חבר צוות',
      isActive: true,
      isPermanent: true,
      constraints: [_span],
      roleCapabilities: const {},
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
      uniqueKey: 'key',
    );

    test('blocked on the middle day', () {
      expect(member.isAvailableForEventWithTime(_event(_middleDay, '09:00', '12:00')),
          isFalse);
    });

    test('blocked on the first day after the start time', () {
      expect(member.isAvailableForEventWithTime(_event(_firstDay, '18:00', '22:00')),
          isFalse);
    });

    test('available on the last day after the end time', () {
      expect(member.isAvailableForEventWithTime(_event(_lastDay, '12:00', '15:00')),
          isTrue);
    });
  });

  group('getHighlightedDatesForConstraintRange over a multi-day span', () {
    test('highlights only the days whose events fall inside the span', () {
      final highlighted = getHighlightedDatesForConstraintRange(
        rangeStart: _firstDay,
        rangeEnd: _lastDay,
        constraintStartTime: '17:00',
        constraintEndTime: '11:00',
        events: [
          _event(_firstDay, '09:00', '12:00'),
          _event(_middleDay, '09:00', '12:00'),
          _event(_lastDay, '12:00', '15:00'),
        ],
      );
      expect(highlighted, {_middleDay});
    });
  });
}

/// A one-day event; assembly is half an hour before [startTime].
Event _event(DateTime day, String startTime, String endTime) {
  final minutes = TimeRangeUtils.parseTimeToMinutes(startTime)! - 30;
  return Event(
    id: 'e-${day.day}-$startTime',
    name: 'אירוע',
    startDate: day,
    endDate: day,
    startTime: startTime,
    endTime: endTime,
    assemblyTime: TimeRangeUtils.formatMinutesToTime(minutes),
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );
}
