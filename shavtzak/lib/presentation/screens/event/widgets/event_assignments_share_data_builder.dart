import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/assignment_label.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/role.dart';
import '../../../widgets/map_location_picker.dart';
import 'event_assignments_share_models.dart';

class EventAssignmentsShareDataBuilder {
  static EventAssignmentsShareData build({
    required Event event,
    required List<Assignment> assignments,
    required List<Role> activeRoles,
    required List<AssignmentLabel> labels,
    required EventAssignmentsGroupingMode groupingMode,
  }) {
    final notes = <EventAssignmentsShareNote>[];
    var nextNoteNumber = 1;

    EventAssignmentsShareRow buildRow(Assignment assignment) {
      final memberName = assignment.teamMember!.name;
      final trimmedNote = assignment.notes.trim();
      int? noteNumber;

      if (trimmedNote.isNotEmpty) {
        noteNumber = nextNoteNumber++;
        notes.add(
          EventAssignmentsShareNote(
            number: noteNumber,
            memberName: memberName,
            text: trimmedNote,
          ),
        );
      }

      return EventAssignmentsShareRow(
        memberName: memberName,
        noteNumber: noteNumber,
      );
    }

    final labeledAssignments = _applyAssignmentLabels(assignments, labels)
        .where((assignment) => assignment.teamMember != null)
        .toList();
    final sections = groupingMode == EventAssignmentsGroupingMode.label
        ? _buildLabelSections(
            activeRoles,
            labeledAssignments,
            buildRow,
          )
        : _buildRoleSections(
            activeRoles,
            labeledAssignments,
            buildRow,
          );

    return EventAssignmentsShareData(
      eventName: event.name,
      dateLine: _formatEventDatesHebrew(event),
      timeLine: _formatTimeFields(event),
      participantsLine: _formatParticipantsLine(event),
      locationLine: _formatLocationLine(event.location),
      eventNoteLine: event.comments.trim(),
      sections: sections,
      notes: notes,
    );
  }

  static List<Assignment> _applyAssignmentLabels(
    List<Assignment> assignments,
    List<AssignmentLabel> labels,
  ) {
    if (assignments.isEmpty || labels.isEmpty) {
      return assignments;
    }

    final labelsById = {
      for (final label in labels) label.id: label,
    };

    return assignments.map((assignment) {
      return assignment.copyWith(
        semanticLabel: () => assignment.semanticLabelId == null
            ? null
            : labelsById[assignment.semanticLabelId!],
      );
    }).toList();
  }

  static List<EventAssignmentsShareSection> _buildRoleSections(
    List<Role> activeRoles,
    List<Assignment> assignments,
    EventAssignmentsShareRow Function(Assignment assignment) buildRow,
  ) {
    final assignmentsByRole = <String, List<Assignment>>{};
    for (final assignment in assignments) {
      assignmentsByRole.putIfAbsent(assignment.roleType, () => []);
      assignmentsByRole[assignment.roleType]!.add(assignment);
    }

    final sections = <EventAssignmentsShareSection>[];
    for (final role in activeRoles) {
      final roleAssignments = assignmentsByRole[role.key];
      if (roleAssignments == null || roleAssignments.isEmpty) {
        continue;
      }

      sections.add(
        EventAssignmentsShareSection(
          title: role.hebrewName,
          rows: _sortAssignmentsWithinRoleGroup(roleAssignments)
              .map(buildRow)
              .toList(),
        ),
      );
    }

    return sections;
  }

  static List<EventAssignmentsShareSection> _buildLabelSections(
    List<Role> activeRoles,
    List<Assignment> assignments,
    EventAssignmentsShareRow Function(Assignment assignment) buildRow,
  ) {
    final assignmentsByLabel = <AssignmentLabel, List<Assignment>>{};
    final unlabeledAssignments = <Assignment>[];

    for (final assignment in assignments) {
      final label = assignment.semanticLabel;
      if (label == null) {
        unlabeledAssignments.add(assignment);
        continue;
      }

      assignmentsByLabel.putIfAbsent(label, () => []);
      assignmentsByLabel[label]!.add(assignment);
    }

    final orderedLabels = assignmentsByLabel.keys.toList()
      ..sort((a, b) {
        final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
        if (bySortOrder != 0) return bySortOrder;
        return a.hebrewName.compareTo(b.hebrewName);
      });

    final sections = <EventAssignmentsShareSection>[
      for (final label in orderedLabels)
        _buildLabelSection(
          title: label.hebrewName,
          assignments: assignmentsByLabel[label]!,
          activeRoles: activeRoles,
          buildRow: buildRow,
        ),
    ];

    if (unlabeledAssignments.isNotEmpty) {
      sections.add(
        _buildLabelSection(
          title: 'ללא לייבל',
          assignments: unlabeledAssignments,
          activeRoles: activeRoles,
          buildRow: buildRow,
        ),
      );
    }

    return sections
        .where(
            (section) => section.children.isNotEmpty || section.rows.isNotEmpty)
        .toList();
  }

  static EventAssignmentsShareSection _buildLabelSection({
    required String title,
    required List<Assignment> assignments,
    required List<Role> activeRoles,
    required EventAssignmentsShareRow Function(Assignment assignment) buildRow,
  }) {
    final roleSections = <EventAssignmentsShareSection>[];

    for (final role in activeRoles) {
      final roleAssignments = assignments
          .where((assignment) => assignment.roleType == role.key)
          .toList();
      if (roleAssignments.isEmpty) {
        continue;
      }

      roleSections.add(
        EventAssignmentsShareSection(
          title: role.hebrewName,
          rows: _sortAssignmentsAlphabetically(roleAssignments)
              .map(buildRow)
              .toList(),
        ),
      );
    }

    return EventAssignmentsShareSection(
      title: title,
      children: roleSections,
    );
  }

  static List<Assignment> _sortAssignmentsWithinRoleGroup(
    List<Assignment> assignments,
  ) {
    final sortedAssignments = List<Assignment>.from(assignments);
    sortedAssignments.sort((a, b) {
      final aLabel = a.semanticLabel;
      final bLabel = b.semanticLabel;

      if (aLabel == null && bLabel != null) return 1;
      if (aLabel != null && bLabel == null) return -1;
      if (aLabel != null && bLabel != null) {
        final bySortOrder = aLabel.sortOrder.compareTo(bLabel.sortOrder);
        if (bySortOrder != 0) return bySortOrder;

        final byLabelName = aLabel.hebrewName.compareTo(bLabel.hebrewName);
        if (byLabelName != 0) return byLabelName;
      }

      final byName = a.teamMember!.name.compareTo(b.teamMember!.name);
      if (byName != 0) return byName;

      final bySlotIndex = a.slotIndex.compareTo(b.slotIndex);
      if (bySlotIndex != 0) return bySlotIndex;

      return a.id.compareTo(b.id);
    });
    return sortedAssignments;
  }

  static List<Assignment> _sortAssignmentsAlphabetically(
    List<Assignment> assignments,
  ) {
    final sortedAssignments = List<Assignment>.from(assignments);
    sortedAssignments.sort((a, b) {
      final byName = a.teamMember!.name.compareTo(b.teamMember!.name);
      if (byName != 0) return byName;

      final byRole = a.roleType.compareTo(b.roleType);
      if (byRole != 0) return byRole;

      final bySlotIndex = a.slotIndex.compareTo(b.slotIndex);
      if (bySlotIndex != 0) return bySlotIndex;

      return a.id.compareTo(b.id);
    });
    return sortedAssignments;
  }

  static String _formatEventDatesHebrew(Event event) {
    final isSameDay = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    if (isSameDay) {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} '
          '${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)}';
    }

    return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} '
        '${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)} - '
        'יום ${_getFullHebrewDayName(event.endDate.weekday)} '
        '${event.endDate.day} ב${_getHebrewMonthName(event.endDate.month)}';
  }

  static String _formatTimeFields(Event event) {
    final parts = <String>[];

    if (event.assemblyTime.isNotEmpty) {
      parts.add('התייצבות - ${event.assemblyTime}');
    }
    if (event.startTime.isNotEmpty) {
      parts.add('התכנסות קהל - ${event.startTime}');
    }
    if (event.actualShowStartTime.isNotEmpty) {
      parts.add('תחילת מופע - ${event.actualShowStartTime}');
    }
    if (event.endTime.isNotEmpty) {
      parts.add('סיום מופע משוער - ${event.endTime}');
    }
    if (event.teamEndTime.isNotEmpty) {
      parts.add('סיום צוות משוער - ${event.teamEndTime}');
    }

    return parts.join(' | ');
  }

  static String _formatParticipantsLine(Event event) {
    final summary = event.participantsSummary;
    if (summary == null) {
      return '';
    }
    return 'כמות משתתפים: $summary';
  }

  static String _getFullHebrewDayName(int weekday) {
    const days = [
      '',
      'שני',
      'שלישי',
      'רביעי',
      'חמישי',
      'שישי',
      'שבת',
      'ראשון',
    ];
    return days[weekday];
  }

  static String _getHebrewMonthName(int month) {
    const months = [
      '',
      'ינואר',
      'פברואר',
      'מרץ',
      'אפריל',
      'מאי',
      'יוני',
      'יולי',
      'אוגוסט',
      'ספטמבר',
      'אוקטובר',
      'נובמבר',
      'דצמבר',
    ];
    return months[month];
  }

  static String _formatLocationLine(String location) {
    final displayLocation = _formatLocationForDisplay(location).trim();
    if (displayLocation.isEmpty) {
      return '';
    }
    return 'מיקום: $displayLocation';
  }

  static String _formatLocationForDisplay(String location) {
    if (location.contains('||')) {
      final strippedLocation = MapLocationResult.stripCoordinates(location);
      return strippedLocation.isNotEmpty ? strippedLocation : location;
    }
    return location;
  }
}
