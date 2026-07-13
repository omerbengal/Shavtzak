import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot.dart';
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot_annotations.dart';

void main() {
  final summer = _event(id: 'summer', name: 'אירוע קיץ', start: DateTime(2026, 7, 12));
  final evening = _event(id: 'evening', name: 'מופע ערב', start: DateTime(2026, 7, 12));
  final medic = _role('medic', 'חובש');
  final commander = _role('commander', 'מפקד אירוע');

  group('annotateSameDayOtherEvents', () {
    test('marks a filled quota slot whose member is in another same-day event',
        () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1'),
      ];

      final result = annotateSameDayOtherEvents(
        slots,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', member: member),
          _assignment(id: 'a2', eventId: 'evening', member: member),
        ],
      );

      expect(result.single.sameDayOtherEvents.map((e) => e.id), ['evening']);
    });

    test('marks off-quota rows too — they are real assignments', () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(
          event: summer,
          role: medic,
          member: member,
          assignmentId: 'a1',
          isOffQuota: true,
        ),
      ];

      final result = annotateSameDayOtherEvents(
        slots,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', member: member),
          _assignment(id: 'a2', eventId: 'evening', member: member),
        ],
      );

      expect(result.single.sameDayOtherEvents.map((e) => e.id), ['evening']);
    });

    test('leaves an unfilled slot alone', () {
      final slots = [_slot(event: summer, role: medic)];

      final result = annotateSameDayOtherEvents(
        slots,
        allEvents: [summer, evening],
        allAssignments: const [],
      );

      expect(result.single.sameDayOtherEvents, isEmpty);
    });

    test('preserves fields set by an earlier pass', () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1')
            .copyWith(hasDoubleAssignment: true, otherRoles: ['מפקד אירוע']),
      ];

      final result = annotateSameDayOtherEvents(
        slots,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', member: member),
          _assignment(id: 'a2', eventId: 'evening', member: member),
        ],
      );

      expect(result.single.hasDoubleAssignment, isTrue);
      expect(result.single.otherRoles, ['מפקד אירוע']);
      expect(result.single.sameDayOtherEvents, isNotEmpty);
    });
  });

  group('annotateDoubleAssignments', () {
    test('flags a member holding two roles in the same event', () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1'),
        _slot(event: summer, role: commander, member: member, assignmentId: 'a2'),
      ];

      final result = annotateDoubleAssignments(slots);

      expect(result[0].hasDoubleAssignment, isTrue);
      expect(result[0].otherRoles, ['מפקד אירוע']);
      expect(result[1].hasDoubleAssignment, isTrue);
      expect(result[1].otherRoles, ['חובש']);
    });

    test('preserves sameDay* fields when flagging (regression: used the raw '
        'constructor and dropped them)', () {
      final member = _member('m1', 'יוסי כהן');
      final other = _member('m2', 'דנה לוי');
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1')
            .copyWith(
          sameDayAssignedMembers: [other],
          sameDayEventInfo: {
            'm2': ['מופע ערב']
          },
        ),
        _slot(event: summer, role: commander, member: member, assignmentId: 'a2'),
      ];

      final result = annotateDoubleAssignments(slots);

      expect(result[0].hasDoubleAssignment, isTrue);
      expect(result[0].sameDayAssignedMembers, [other]);
      expect(result[0].sameDayEventInfo, {
        'm2': ['מופע ערב']
      });
    });

    test('skips members flagged שיבוץ מרובה', () {
      final member = _member('m1', 'יוסי כהן', allowMultipleAssignments: true);
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1'),
        _slot(event: summer, role: commander, member: member, assignmentId: 'a2'),
      ];

      final result = annotateDoubleAssignments(slots);

      expect(result[0].hasDoubleAssignment, isFalse);
      expect(result[1].hasDoubleAssignment, isFalse);
    });

    test('skips off-quota slots', () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(
          event: summer,
          role: medic,
          member: member,
          assignmentId: 'a1',
          isOffQuota: true,
        ),
        _slot(event: summer, role: commander, member: member, assignmentId: 'a2'),
      ];

      final result = annotateDoubleAssignments(slots);

      expect(result[0].hasDoubleAssignment, isFalse);
    });
  });
}

AssignmentSlot _slot({
  required Event event,
  required Role role,
  TeamMember? member,
  String? assignmentId,
  bool isOffQuota = false,
}) {
  return AssignmentSlot(
    event: event,
    role: role,
    slotIndex: 0,
    currentAssignment: member == null
        ? null
        : _assignment(id: assignmentId!, eventId: event.id, member: member,
            roleType: role.key),
    availableMembers: const [],
    isOffQuota: isOffQuota,
  );
}

Event _event({
  required String id,
  required String name,
  required DateTime start,
  DateTime? end,
}) {
  final now = DateTime(2026, 7, 1);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: end ?? start,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}

Role _role(String key, String hebrewName) {
  final now = DateTime(2026, 7, 1);
  return Role(
    id: key,
    key: key,
    hebrewName: hebrewName,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}

TeamMember _member(
  String id,
  String name, {
  bool allowMultipleAssignments = false,
}) {
  final now = DateTime(2026, 7, 1);
  return TeamMember(
    id: id,
    name: name,
    isActive: true,
    isPermanent: true,
    constraints: const [],
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'unique-$id',
    allowMultipleAssignments: allowMultipleAssignments,
  );
}

Assignment _assignment({
  required String id,
  required String eventId,
  required TeamMember member,
  String roleType = 'medic',
}) {
  final now = DateTime(2026, 7, 1);
  return Assignment(
    id: id,
    eventId: eventId,
    teamMemberId: member.id,
    roleType: roleType,
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
    teamMember: member,
  );
}
