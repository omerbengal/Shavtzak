import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/event/duplication_custom_hours.dart';

/// The hours each copy carries when an event is duplicated with its custom
/// hours: moved by whole days, and one set per member (the backend refuses a
/// member whose copies differ), except for members flagged
/// `allowMultipleAssignments`.
void main() {
  CopiedHours hours(String start, String end) => (start: start, end: end);

  group('movedCustomHours', () {
    test('moves both ends by the shift, the clock times unchanged', () {
      final result = movedCustomHours(
        [_assignment('a1', 'm1', '2026-12-01T14:00', '2026-12-01T20:00')],
        7,
      );

      expect(result, {
        'a1': hours('2026-12-08T14:00', '2026-12-08T20:00'),
      });
    });

    test('a negative shift moves the hours back', () {
      final result = movedCustomHours(
        [_assignment('a1', 'm1', '2026-12-01T22:00', '2026-12-02T02:00')],
        -3,
      );

      expect(result, {
        'a1': hours('2026-11-28T22:00', '2026-11-29T02:00'),
      });
    });

    test('a move across the end of a month and a year keeps the calendar right',
        () {
      final result = movedCustomHours(
        [_assignment('a1', 'm1', '2026-12-30T14:00', '2026-12-31T02:00')],
        5,
      );

      expect(result, {
        'a1': hours('2027-01-04T14:00', '2027-01-05T02:00'),
      });
    });

    test('an assignment with no hours has no entry', () {
      final result = movedCustomHours([_assignment('a1', 'm1', null, null)], 7);

      expect(result, isEmpty);
    });

    test('hours that cannot be read count as none', () {
      final result = movedCustomHours([
        _assignment('a-garbage', 'm1', 'soon', '2026-12-01T20:00'),
        _assignment(
            'a-backwards', 'm2', '2026-12-01T20:00', '2026-12-01T14:00'),
        _assignment('a-half', 'm3', '2026-12-01T14:00', null),
      ], 7);

      expect(result, isEmpty);
    });

    test(
        'every copy of an ordinary member gets the same hours, also the one '
        'whose source row had none', () {
      final result = movedCustomHours([
        _assignment('a1', 'm1', null, null),
        _assignment('a2', 'm1', '2026-12-01T14:00', '2026-12-01T20:00'),
        _assignment('a3', 'm1', null, null),
      ], 7);

      final moved = hours('2026-12-08T14:00', '2026-12-08T20:00');
      expect(result, {'a1': moved, 'a2': moved, 'a3': moved});
    });

    test(
        'an ordinary member whose rows disagree takes the first usable '
        'hours for all of them', () {
      final result = movedCustomHours([
        _assignment('a1', 'm1', 'garbage', 'garbage'),
        _assignment('a2', 'm1', '2026-12-01T14:00', '2026-12-01T20:00'),
        _assignment('a3', 'm1', '2026-12-01T09:00', '2026-12-01T12:00'),
      ], 7);

      final first = hours('2026-12-08T14:00', '2026-12-08T20:00');
      expect(result, {'a1': first, 'a2': first, 'a3': first});
    });

    test('members are kept apart', () {
      final result = movedCustomHours([
        _assignment('a1', 'm1', '2026-12-01T14:00', '2026-12-01T20:00'),
        _assignment('a2', 'm2', null, null),
        _assignment('a3', 'm3', '2026-12-01T09:00', '2026-12-01T12:00'),
      ], 7);

      expect(result, {
        'a1': hours('2026-12-08T14:00', '2026-12-08T20:00'),
        'a3': hours('2026-12-08T09:00', '2026-12-08T12:00'),
      });
    });

    test(
        'a member flagged allowMultipleAssignments moves each copy by its '
        'own hours', () {
      final pool = _member('pool', allowMultipleAssignments: true);
      final result = movedCustomHours([
        _assignment('a1', 'pool', '2026-12-01T14:00', '2026-12-01T20:00',
            member: pool),
        _assignment('a2', 'pool', '2026-12-01T09:00', '2026-12-01T12:00',
            member: pool),
        _assignment('a3', 'pool', null, null, member: pool),
      ], 7);

      expect(result, {
        'a1': hours('2026-12-08T14:00', '2026-12-08T20:00'),
        'a2': hours('2026-12-08T09:00', '2026-12-08T12:00'),
      });
    });

    group('dropped', () {
      test('an id of an ordinary member drops every copy of theirs', () {
        final result = movedCustomHours(
            [
              _assignment('a1', 'm1', '2026-12-01T14:00', '2026-12-01T20:00'),
              _assignment('a2', 'm1', '2026-12-01T14:00', '2026-12-01T20:00'),
              _assignment('a3', 'm2', '2026-12-01T09:00', '2026-12-01T12:00'),
            ],
            7,
            dropped: {'a2'});

        expect(result, {
          'a3': hours('2026-12-08T09:00', '2026-12-08T12:00'),
        });
      });

      test(
          'an id of a member flagged allowMultipleAssignments drops only '
          'that copy', () {
        final pool = _member('pool', allowMultipleAssignments: true);
        final result = movedCustomHours(
            [
              _assignment('a1', 'pool', '2026-12-01T14:00', '2026-12-01T20:00',
                  member: pool),
              _assignment('a2', 'pool', '2026-12-01T09:00', '2026-12-01T12:00',
                  member: pool),
            ],
            7,
            dropped: {'a1'});

        expect(result, {
          'a2': hours('2026-12-08T09:00', '2026-12-08T12:00'),
        });
      });

      test('an id that matches nothing changes nothing', () {
        final result = movedCustomHours(
          [_assignment('a1', 'm1', '2026-12-01T14:00', '2026-12-01T20:00')],
          7,
          dropped: {'elsewhere'},
        );

        expect(result.keys, ['a1']);
      });
    });
  });
}

Assignment _assignment(
  String id,
  String memberId,
  String? start,
  String? end, {
  TeamMember? member,
}) {
  final now = DateTime(2026, 10, 1);
  return Assignment(
    id: id,
    eventId: 'original',
    teamMemberId: memberId,
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    customStartAt: start,
    customEndAt: end,
    createdAt: now,
    updatedAt: now,
    teamMember: member ?? _member(memberId),
  );
}

TeamMember _member(String id, {bool allowMultipleAssignments = false}) {
  final now = DateTime(2026, 10, 1);
  return TeamMember(
    id: id,
    name: 'חבר $id',
    isActive: true,
    isPermanent: true,
    constraints: const [],
    roleCapabilities: const {'medic': true},
    allowMultipleAssignments: allowMultipleAssignments,
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'key-$id',
  );
}
