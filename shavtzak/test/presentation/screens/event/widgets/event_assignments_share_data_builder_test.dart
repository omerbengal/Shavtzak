import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/assignment_label.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/participant_group.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_data_builder.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_models.dart';

void main() {
  group('EventAssignmentsShareDataBuilder', () {
    test('builds role-grouped data with full numbered notes in visual order',
        () {
      final now = DateTime(2026, 5, 4, 10);
      final event = _event(now);
      final roles = [
        _role('commander', 'מפקד אירוע', 0),
        _role('medic', 'חובשים', 1),
      ];
      final assignments = [
        _assignment(
          id: 'a2',
          roleType: 'medic',
          slotIndex: 0,
          member: _member('m2', 'מיכל ישראלי', phoneNumber: '0501111111'),
          notes: 'הערה מלאה שלא מתקצרת גם כאשר היא ארוכה יחסית.',
          alternativePhoneNumber: '0502222222',
          status: AssignmentStatus.pending,
        ),
        _assignment(
          id: 'a1',
          roleType: 'commander',
          slotIndex: 0,
          member: _member('m1', 'נועה כהן'),
          notes: 'מגיעה מהכניסה הראשית.',
        ),
        _assignment(
          id: 'a3',
          roleType: 'medic',
          slotIndex: 1,
          member: _member('m3', 'אורי ברק'),
        ),
      ];

      final data = EventAssignmentsShareDataBuilder.build(
        event: event,
        assignments: assignments,
        activeRoles: roles,
        labels: const [],
        groupingMode: EventAssignmentsGroupingMode.role,
      );

      expect(data.eventName, 'טקס פתיחה');
      expect(data.dateLine, 'יום שני 4 במאי');
      expect(data.timeLine,
          'התייצבות - 17:00 | התכנסות קהל - 18:00 | תחילת מופע - 19:30 | סיום מופע משוער - 22:00');
      expect(data.locationLine, 'מיקום: היכל התרבות');
      expect(data.eventNoteLine, 'נא להביא חולצות ייצוגיות.');
      expect(data.sections.map((section) => section.title),
          ['מפקד אירוע', 'חובשים']);
      expect(data.sections[0].rows.single.memberName, 'נועה כהן');
      expect(data.sections[0].rows.single.noteNumber, 1);
      expect(data.sections[1].rows.map((row) => row.memberName),
          ['אורי ברק', 'מיכל ישראלי']);
      expect(data.sections[1].rows.last.noteNumber, 2);
      expect(
          data.notes
              .map((note) => '${note.number}:${note.memberName}:${note.text}'),
          [
            '1:נועה כהן:מגיעה מהכניסה הראשית.',
            '2:מיכל ישראלי:הערה מלאה שלא מתקצרת גם כאשר היא ארוכה יחסית.',
          ]);
    });

    test('builds label-grouped data with unlabeled assignments last', () {
      final now = DateTime(2026, 5, 4, 10);
      final roles = [_role('medic', 'חובשים', 0)];
      final vip = AssignmentLabel(
        id: 'label-vip',
        key: 'label-vip',
        hebrewName: 'כניסה ראשית',
        color: '#2563EB',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );
      final assignments = [
        _assignment(
          id: 'a1',
          roleType: 'medic',
          slotIndex: 0,
          member: _member('m1', 'נועה כהן'),
          semanticLabelId: vip.id,
        ),
        _assignment(
          id: 'a2',
          roleType: 'medic',
          slotIndex: 1,
          member: _member('m2', 'אורי ברק'),
        ),
      ];

      final data = EventAssignmentsShareDataBuilder.build(
        event: _event(now),
        assignments: assignments,
        activeRoles: roles,
        labels: [vip],
        groupingMode: EventAssignmentsGroupingMode.label,
      );

      expect(data.sections.map((section) => section.title),
          ['כניסה ראשית', 'ללא לייבל']);
      expect(data.sections.first.children.single.title, 'חובשים');
      expect(data.sections.first.children.single.rows.single.memberName,
          'נועה כהן');
      expect(data.sections.last.children.single.rows.single.memberName,
          'אורי ברק');
    });

    test('participants line lists every סבב', () {
      final event = _event(DateTime(2026, 5, 4, 10)).copyWith(
        participantGroups: const [
          ParticipantGroup(label: 'בוקר', count: 500),
          ParticipantGroup(count: 700),
        ],
      );

      final data = EventAssignmentsShareDataBuilder.build(
        event: event,
        assignments: const [],
        activeRoles: const [],
        labels: const [],
        groupingMode: EventAssignmentsGroupingMode.role,
      );

      expect(data.participantsLine, 'כמות משתתפים: בוקר: 500, סבב 2: 700');
    });

    test('participants line is empty when no groups are set', () {
      final data = EventAssignmentsShareDataBuilder.build(
        event: _event(DateTime(2026, 5, 4, 10)),
        assignments: const [],
        activeRoles: const [],
        labels: const [],
        groupingMode: EventAssignmentsGroupingMode.role,
      );

      expect(data.participantsLine, '');
    });
  });
}

Event _event(DateTime now) {
  return Event(
    id: 'event-1',
    name: 'טקס פתיחה',
    startDate: DateTime(2026, 5, 4),
    endDate: DateTime(2026, 5, 4),
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    actualShowStartTime: '19:30',
    location: 'היכל התרבות||32.1,34.8',
    comments: ' נא להביא חולצות ייצוגיות. ',
    requiresArmed: false,
    roleRequirements: const {'commander': 1, 'medic': 2},
    createdAt: now,
    updatedAt: now,
  );
}

Role _role(String key, String hebrewName, int sortOrder) {
  final now = DateTime(2026, 5, 4, 10);
  return Role(
    id: key,
    key: key,
    hebrewName: hebrewName,
    sortOrder: sortOrder,
    createdAt: now,
    updatedAt: now,
  );
}

TeamMember _member(String id, String name, {String? phoneNumber}) {
  final now = DateTime(2026, 5, 4, 10);
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
    phoneNumber: phoneNumber,
  );
}

Assignment _assignment({
  required String id,
  required String roleType,
  required int slotIndex,
  required TeamMember member,
  String notes = '',
  String? semanticLabelId,
  String? alternativePhoneNumber,
  AssignmentStatus status = AssignmentStatus.confirmed,
}) {
  final now = DateTime(2026, 5, 4, 10);
  return Assignment(
    id: id,
    eventId: 'event-1',
    teamMemberId: member.id,
    roleType: roleType,
    slotIndex: slotIndex,
    status: status,
    notes: notes,
    semanticLabelId: semanticLabelId,
    alternativePhoneNumber: alternativePhoneNumber,
    createdAt: now,
    updatedAt: now,
    teamMember: member,
  );
}
