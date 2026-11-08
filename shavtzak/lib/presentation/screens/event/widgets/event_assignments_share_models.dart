class EventAssignmentsShareData {
  final String eventName;
  final String dateLine;
  final String timeLine;
  final String participantsLine;
  final String locationLine;
  final String eventNoteLine;
  final List<EventAssignmentsShareSection> sections;

  const EventAssignmentsShareData({
    required this.eventName,
    required this.dateLine,
    required this.timeLine,
    this.participantsLine = '',
    required this.locationLine,
    this.eventNoteLine = '',
    required this.sections,
  });
}

class EventAssignmentsShareSection {
  final String title;
  final List<EventAssignmentsShareRow> rows;
  final List<EventAssignmentsShareSection> children;

  const EventAssignmentsShareSection({
    required this.title,
    this.rows = const [],
    this.children = const [],
  });

  bool get hasChildren => children.isNotEmpty;
}

class EventAssignmentsShareRow {
  final String memberName;

  /// The member's note (custom hours and/or the assignment note), shown
  /// right under the name.
  final String? noteText;

  const EventAssignmentsShareRow({
    required this.memberName,
    this.noteText,
  });
}

enum EventAssignmentsGroupingMode {
  role,
  label,
}
