class EventAssignmentsShareData {
  final String eventName;
  final String dateLine;
  final String timeLine;
  final String participantsLine;
  final String locationLine;
  final String eventNoteLine;
  final List<EventAssignmentsShareSection> sections;
  final List<EventAssignmentsShareNote> notes;

  const EventAssignmentsShareData({
    required this.eventName,
    required this.dateLine,
    required this.timeLine,
    this.participantsLine = '',
    required this.locationLine,
    this.eventNoteLine = '',
    required this.sections,
    required this.notes,
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
  final int? noteNumber;

  const EventAssignmentsShareRow({
    required this.memberName,
    this.noteNumber,
  });
}

class EventAssignmentsShareNote {
  final int number;
  final String memberName;
  final String text;

  const EventAssignmentsShareNote({
    required this.number,
    required this.memberName,
    required this.text,
  });
}

enum EventAssignmentsGroupingMode {
  role,
  label,
}
