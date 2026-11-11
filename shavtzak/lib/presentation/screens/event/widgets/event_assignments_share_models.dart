class EventAssignmentsShareData {
  final String eventName;
  final String dateLine;
  final String timeLine;
  final String participantsLine;
  final String locationLine;
  final String eventNoteLine;

  /// `באירוע זה יש: …` (see eventItemsSentence), null when the event has none.
  final String? itemsLine;

  /// `תפקידים חסרים: 1 נהג | 3 צלם`, null when every quota is filled.
  final String? missingRolesLine;
  final List<EventAssignmentsShareSection> sections;

  const EventAssignmentsShareData({
    required this.eventName,
    required this.dateLine,
    required this.timeLine,
    this.participantsLine = '',
    required this.locationLine,
    this.eventNoteLine = '',
    this.itemsLine,
    this.missingRolesLine,
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
