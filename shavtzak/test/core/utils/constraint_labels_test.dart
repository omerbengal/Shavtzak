// The one-line wording of a constraint in the "בעלי מגבלות / לא זמינים" lists.
// Dates are d.M, dashes are en-dashes.
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/utils/constraint_labels.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

DateConstraint _constraint({
  required DateTime startDate,
  DateTime? endDate,
  String? startTime,
  String? endTime,
  ConstraintStatus status = ConstraintStatus.approved,
  RepeatType? repeatType,
  int? repeatDay,
  DateTime? repeatEndDate,
}) {
  return DateConstraint(
    id: 'c1',
    startDate: startDate,
    endDate: endDate,
    startTime: startTime,
    endTime: endTime,
    status: status,
    constraintType: ConstraintType.unavailability,
    repeatType: repeatType,
    repeatDay: repeatDay,
    repeatEndDate: repeatEndDate,
  );
}

void main() {
  group('constraintShortLabel, one-time', () {
    test('a single day without hours says the whole day', () {
      expect(
          constraintShortLabel(_constraint(startDate: DateTime(2026, 10, 28))),
          '28.10 (כל היום)');
    });

    test('a single day with hours lists them', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 27),
            startTime: '17:00',
            endTime: '20:00',
          )),
          '27.10 17:00–20:00');
    });

    test('an endDate equal to the start is still a single day', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 28),
            endDate: DateTime(2026, 10, 28),
          )),
          '28.10 (כל היום)');
    });

    test('a range inside one month folds the month', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 27),
            endDate: DateTime(2026, 10, 28),
          )),
          '27–28.10');
    });

    test('a range across a month boundary names both months', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 30),
            endDate: DateTime(2026, 11, 2),
          )),
          '30.10–2.11');
    });

    test('a multi-day range with hours names each end', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 27),
            endDate: DateTime(2026, 10, 28),
            startTime: '17:00',
            endTime: '11:00',
          )),
          '27.10 17:00 – 28.10 11:00');
    });

    test('a bad end date before the start reads as a single day', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 28),
            endDate: DateTime(2026, 10, 27),
          )),
          '28.10 (כל היום)');
    });

    test('one time only is said as from or until', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 27),
            startTime: '17:00',
          )),
          '27.10 מ-17:00');
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 27),
            endTime: '20:00',
          )),
          '27.10 עד 20:00');
    });

    test('a malformed time counts as missing, never throws', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 27),
            startTime: '24:00',
            endTime: '',
          )),
          '27.10 (כל היום)');
    });
  });

  group('constraintShortLabel, recurring', () {
    test('weekly names the weekday and the hours', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 1),
            startTime: '18:00',
            endTime: '20:00',
            repeatType: RepeatType.weekly,
            repeatDay: 2,
            repeatEndDate: DateTime(2026, 12, 31),
          )),
          'כל יום שלישי 18:00–20:00');
    });

    test('daily without hours is just כל יום', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 1),
            repeatType: RepeatType.daily,
            repeatEndDate: DateTime(2026, 12, 31),
          )),
          'כל יום');
    });

    test('monthly names the day of the month', () {
      expect(
          constraintShortLabel(_constraint(
            startDate: DateTime(2026, 10, 1),
            repeatType: RepeatType.monthly,
            repeatDay: 15,
            repeatEndDate: DateTime(2026, 12, 31),
          )),
          'כל 15 לחודש');
    });
  });

  group('constraintStatusLabel', () {
    final day = DateTime(2026, 10, 28);

    test('pending reads אילוץ ממתין לאישור', () {
      expect(
          constraintStatusLabel(
              _constraint(startDate: day, status: ConstraintStatus.pending)),
          'אילוץ ממתין לאישור: 28.10 (כל היום)');
    });

    test('approved reads אילוץ מאושר', () {
      expect(constraintStatusLabel(_constraint(startDate: day)),
          'אילוץ מאושר: 28.10 (כל היום)');
    });
  });
}
