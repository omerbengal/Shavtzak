// The ש.מ.פ. clipboard row for one member: tab-separated cells, the start and
// end dates being the event's unless the member has custom hours in it.
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/widgets/shamap_export_dialog.dart';

final DateTime _stamp = DateTime(2026, 10, 1);

TeamMember _member(String id, String name) => TeamMember(
      id: id,
      name: name,
      isActive: true,
      isPermanent: true,
      constraints: const [],
      roleCapabilities: const {},
      createdAt: _stamp,
      updatedAt: _stamp,
      uniqueKey: 'uk-$id',
    );

Event _event({String id = 'e1', DateTime? end}) => Event(
      id: id,
      name: 'כנס חורף',
      startDate: DateTime(2026, 10, 27),
      endDate: end ?? DateTime(2026, 10, 28),
      startTime: '19:00',
      endTime: '22:30',
      assemblyTime: '12:00',
      requiresArmed: false,
      roleRequirements: const {'medic': 1},
      createdAt: _stamp,
      updatedAt: _stamp,
    );

Assignment _assignment({
  required String memberId,
  String eventId = 'e1',
  String id = 'a1',
  String roleType = 'medic',
  String? customStartAt,
  String? customEndAt,
}) =>
    Assignment(
      id: id,
      eventId: eventId,
      teamMemberId: memberId,
      roleType: roleType,
      slotIndex: 0,
      status: AssignmentStatus.confirmed,
      notes: '',
      customStartAt: customStartAt,
      customEndAt: customEndAt,
      createdAt: _stamp,
      updatedAt: _stamp,
    );

void main() {
  final dana = _member('dana', 'דנה כהן לוי');

  group('shamapLine', () {
    test('without hours: the cells and the event\'s own dates, as before', () {
      expect(
        shamapLine(
            dana, _event(), [_assignment(memberId: 'dana')], 'היכל התרבות'),
        '\tדנה\tכהן לוי\tהיכל התרבות\t\t\t27/10/2026\t28/10/2026',
      );
    });

    test('with no assignments at all: the event\'s dates', () {
      expect(
        shamapLine(dana, _event(), const [], 'מקום'),
        '\tדנה\tכהן לוי\tמקום\t\t\t27/10/2026\t28/10/2026',
      );
    });

    test('hours on day 1 of 2: start and end are both day 1', () {
      final line = shamapLine(
        dana,
        _event(),
        [
          _assignment(
            memberId: 'dana',
            customStartAt: '2026-10-27T14:00',
            customEndAt: '2026-10-27T23:00',
          ),
        ],
        'מקום',
      );

      expect(line, '\tדנה\tכהן לוי\tמקום\t\t\t27/10/2026\t27/10/2026');
    });

    test('hours on day 2 of 2: start and end are both day 2', () {
      final line = shamapLine(
        dana,
        _event(),
        [
          _assignment(
            memberId: 'dana',
            customStartAt: '2026-10-28T09:00',
            customEndAt: '2026-10-28T20:00',
          ),
        ],
        'מקום',
      );

      expect(line, endsWith('\t28/10/2026\t28/10/2026'));
    });

    test('hours across both days: both days', () {
      final line = shamapLine(
        dana,
        _event(),
        [
          _assignment(
            memberId: 'dana',
            customStartAt: '2026-10-27T14:00',
            customEndAt: '2026-10-28T02:00',
          ),
        ],
        'מקום',
      );

      expect(line, endsWith('\t27/10/2026\t28/10/2026'));
    });

    test('hours ending exactly at midnight end on the day before', () {
      final line = shamapLine(
        dana,
        _event(),
        [
          _assignment(
            memberId: 'dana',
            customStartAt: '2026-10-27T18:00',
            customEndAt: '2026-10-28T00:00',
          ),
        ],
        'מקום',
      );

      expect(line, endsWith('\t27/10/2026\t27/10/2026'));
    });

    test('hours reaching outside the event\'s dates are written as they are',
        () {
      final line = shamapLine(
        dana,
        _event(),
        [
          _assignment(
            memberId: 'dana',
            customStartAt: '2026-10-26T20:00',
            customEndAt: '2026-10-27T02:00',
          ),
        ],
        'מקום',
      );

      expect(line, endsWith('\t26/10/2026\t27/10/2026'));
    });

    test('the first usable window among the member\'s roles', () {
      final line = shamapLine(
        dana,
        _event(),
        [
          _assignment(memberId: 'dana', id: 'a1', roleType: 'medic'),
          _assignment(
            memberId: 'dana',
            id: 'a2',
            roleType: 'driver',
            customStartAt: '2026-10-28T09:00',
            customEndAt: '2026-10-28T20:00',
          ),
        ],
        'מקום',
      );

      expect(line, endsWith('\t28/10/2026\t28/10/2026'));
    });

    test('hours that cannot be read leave the event\'s dates', () {
      final line = shamapLine(
        dana,
        _event(),
        [
          _assignment(
            memberId: 'dana',
            customStartAt: '2026-10-27T23:00',
            customEndAt: '2026-10-27T14:00',
          ),
        ],
        'מקום',
      );

      expect(line, endsWith('\t27/10/2026\t28/10/2026'));
    });

    test('another member\'s hours and another event\'s hours do not count', () {
      final line = shamapLine(
        dana,
        _event(),
        [
          _assignment(
            memberId: 'gal',
            id: 'a1',
            customStartAt: '2026-10-27T14:00',
            customEndAt: '2026-10-27T23:00',
          ),
          _assignment(
            memberId: 'dana',
            id: 'a2',
            eventId: 'other',
            customStartAt: '2026-10-27T14:00',
            customEndAt: '2026-10-27T23:00',
          ),
        ],
        'מקום',
      );

      expect(line, endsWith('\t27/10/2026\t28/10/2026'));
    });

    test('tabs and new lines in the location never break the cells', () {
      final line = shamapLine(
        _member('gal', 'גל'),
        _event(),
        const [],
        ' אולם\tא\nקומה 2 ',
      );

      expect(line, '\tגל\t\tאולם א קומה 2\t\t\t27/10/2026\t28/10/2026');
    });
  });
}
