// The warning shown when a constraint is saved lists the events it touches.
// It judges an event the way the assignment check does: as one continuous
// stretch (assembly on the first day -> team end on the last day), against
// every occurrence of a recurring constraint. See event_stretch.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/utils/constraint_event_overlap.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

void main() {
  group('constraintOverlapsEvent', () {
    test('assembly gap counts (E5)', () {
      // Assembly 17:00, show 19:00-20:30: the member is already at work at
      // 17:30, even though the show has not started.
      final event = _event(
        DateTime(2026, 10, 20),
        assemblyTime: '17:00',
        startTime: '19:00',
        endTime: '20:30',
      );
      final constraint = _constraint(
        DateTime(2026, 10, 20),
        startTime: '17:30',
        endTime: '18:30',
      );

      expect(
        constraintOverlapsEvent(constraint: constraint, event: event),
        isTrue,
      );
    });

    test('a constraint that ends where the assembly begins does not touch it',
        () {
      final event = _event(
        DateTime(2026, 10, 20),
        assemblyTime: '17:00',
        startTime: '19:00',
        endTime: '20:30',
      );
      final constraint = _constraint(
        DateTime(2026, 10, 20),
        startTime: '15:00',
        endTime: '17:00',
      );

      expect(
        constraintOverlapsEvent(constraint: constraint, event: event),
        isFalse,
      );
    });

    test('weekly constraint on its third occurrence (E6)', () {
      // 2026-10-06 is a Tuesday: the constraint's own first day. The event is
      // on the third Tuesday, 2026-10-20.
      final weekly = _constraint(
        DateTime(2026, 10, 6),
        repeatType: RepeatType.weekly,
        repeatDay: DateTime.tuesday,
        repeatEndDate: DateTime(2026, 12, 29),
      );

      expect(
        constraintOverlapsEvent(
          constraint: weekly,
          event: _event(DateTime(2026, 10, 20),
              assemblyTime: '17:00', startTime: '19:00', endTime: '21:00'),
        ),
        isTrue,
      );
      // The day after a Tuesday is free.
      expect(
        constraintOverlapsEvent(
          constraint: weekly,
          event: _event(DateTime(2026, 10, 21),
              assemblyTime: '17:00', startTime: '19:00', endTime: '21:00'),
        ),
        isFalse,
      );
      // So is a Tuesday after the repeat ended.
      expect(
        constraintOverlapsEvent(
          constraint: weekly,
          event: _event(DateTime(2027, 1, 5),
              assemblyTime: '17:00', startTime: '19:00', endTime: '21:00'),
        ),
        isFalse,
      );
    });

    test('a recurring constraint with no repeat end matches nothing', () {
      final open = _constraint(
        DateTime(2026, 10, 6),
        repeatType: RepeatType.weekly,
        repeatDay: DateTime.tuesday,
      );

      expect(
        constraintOverlapsEvent(
          constraint: open,
          event: _event(DateTime(2026, 10, 20),
              assemblyTime: '17:00', startTime: '19:00', endTime: '21:00'),
        ),
        isFalse,
      );
    });

    test('night of a two-day event (E3)', () {
      // 27-28.10, 18:00-23:00. Nobody is free to take a 02:00-04:00 job the
      // night between the two days.
      final event = _event(
        DateTime(2026, 10, 27),
        endDate: DateTime(2026, 10, 28),
        assemblyTime: '17:00',
        startTime: '18:00',
        endTime: '23:00',
      );
      final constraint = _constraint(
        DateTime(2026, 10, 28),
        startTime: '02:00',
        endTime: '04:00',
      );

      expect(
        constraintOverlapsEvent(constraint: constraint, event: event),
        isTrue,
      );
    });

    test('a whole-day constraint on the event day overlaps whatever the hours',
        () {
      final event = _event(
        DateTime(2026, 10, 20),
        assemblyTime: '17:00',
        startTime: '19:00',
        endTime: '20:30',
      );

      expect(
        constraintOverlapsEvent(
          constraint: _constraint(DateTime(2026, 10, 20)),
          event: event,
        ),
        isTrue,
      );
      expect(
        constraintOverlapsEvent(
          constraint: _constraint(DateTime(2026, 10, 21)),
          event: event,
        ),
        isFalse,
      );
    });
  });

  group('getConstraintEventOverlaps', () {
    final constraint = _constraint(
      DateTime(2026, 10, 20),
      startTime: '12:00',
      endTime: '14:00',
    );

    test('an event with an assembly but no show start is judged, not flagged',
        () {
      // Assembly 11:00 to show end 15:00: the stretch is fully known.
      final event = _event(
        DateTime(2026, 10, 20),
        assemblyTime: '11:00',
        startTime: '',
        endTime: '15:00',
      );

      final overlaps =
          getConstraintEventOverlaps(constraint: constraint, events: [event]);

      expect(overlaps, hasLength(1));
      expect(overlaps.single.eventHasMissingTime, isFalse);
      expect(overlaps.single.overlapReason, 'date_time_overlap');
    });

    test('an event with a team end but no show end is judged (E4)', () {
      final event = _event(
        DateTime(2026, 10, 20),
        assemblyTime: '11:00',
        startTime: '12:00',
        endTime: '',
        teamEndTime: '15:00',
      );

      final overlaps =
          getConstraintEventOverlaps(constraint: constraint, events: [event]);

      expect(overlaps.single.eventHasMissingTime, isFalse);
      expect(overlaps.single.overlapReason, 'date_time_overlap');
    });

    test('an event with no end at all falls back to the day edge and says so',
        () {
      final event = _event(
        DateTime(2026, 10, 20),
        assemblyTime: '11:00',
        startTime: '12:00',
        endTime: '',
        teamEndTime: '',
      );

      final overlaps =
          getConstraintEventOverlaps(constraint: constraint, events: [event]);

      expect(overlaps.single.eventHasMissingTime, isTrue);
      expect(overlaps.single.overlapReason, 'missing_event_time');
    });

    test('an event with no assembly and no show start says so', () {
      final event = _event(
        DateTime(2026, 10, 20),
        assemblyTime: '',
        startTime: '',
        endTime: '22:00',
      );

      final overlaps =
          getConstraintEventOverlaps(constraint: constraint, events: [event]);

      expect(overlaps.single.overlapReason, 'missing_event_time');
    });

    test('a time the stretch cannot read counts as missing', () {
      // '24:00' is not a time of day, so the stretch ignores it; the note must
      // appear in exactly the cases where the stretch fell back.
      final event = _event(
        DateTime(2026, 10, 20),
        assemblyTime: '11:00',
        startTime: '12:00',
        endTime: '24:00',
      );

      final overlaps =
          getConstraintEventOverlaps(constraint: constraint, events: [event]);

      expect(overlaps.single.overlapReason, 'missing_event_time');
    });

    test('a constraint without hours never adds the note', () {
      final event = _event(
        DateTime(2026, 10, 20),
        assemblyTime: '',
        startTime: '',
        endTime: '',
      );

      final overlaps = getConstraintEventOverlaps(
        constraint: _constraint(DateTime(2026, 10, 20)),
        events: [event],
      );

      expect(overlaps.single.eventHasMissingTime, isFalse);
      expect(overlaps.single.overlapReason, 'date_time_overlap');
    });

    test('lists only the events it touches, earliest first', () {
      final weekly = _constraint(
        DateTime(2026, 10, 6),
        repeatType: RepeatType.weekly,
        repeatDay: DateTime.tuesday,
        repeatEndDate: DateTime(2026, 12, 29),
      );
      final thirdTuesday = _event(DateTime(2026, 10, 20),
          id: 'third',
          assemblyTime: '17:00',
          startTime: '19:00',
          endTime: '21:00');
      final wednesday = _event(DateTime(2026, 10, 21),
          id: 'wed',
          assemblyTime: '17:00',
          startTime: '19:00',
          endTime: '21:00');
      final firstTuesday = _event(DateTime(2026, 10, 6),
          id: 'first',
          assemblyTime: '17:00',
          startTime: '19:00',
          endTime: '21:00');

      final overlaps = getConstraintEventOverlaps(
        constraint: weekly,
        events: [thirdTuesday, wednesday, firstTuesday],
      );

      expect(overlaps.map((o) => o.event.id), ['first', 'third']);
    });
  });
}

DateConstraint _constraint(
  DateTime date, {
  String? startTime,
  String? endTime,
  RepeatType? repeatType,
  int? repeatDay,
  DateTime? repeatEndDate,
}) {
  return DateConstraint(
    id: 'c1',
    startDate: date,
    status: ConstraintStatus.approved,
    constraintType: ConstraintType.unavailability,
    startTime: startTime,
    endTime: endTime,
    repeatType: repeatType,
    repeatDay: repeatDay,
    repeatEndDate: repeatEndDate,
  );
}

Event _event(
  DateTime startDate, {
  String id = 'e1',
  DateTime? endDate,
  String assemblyTime = '',
  String startTime = '',
  String endTime = '',
  String teamEndTime = '',
}) {
  final now = DateTime(2026, 1, 1);
  return Event(
    id: id,
    name: 'אירוע',
    startDate: startDate,
    endDate: endDate ?? startDate,
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
