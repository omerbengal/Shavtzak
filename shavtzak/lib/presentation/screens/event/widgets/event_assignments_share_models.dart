class EventAssignmentsShareData {
  final String eventName;
  final String dateLine;

  /// `התייצבות - 17:00`, '' without an assembly time.
  final String assemblyLine;

  /// The other times: audience, show start, show end, team end.
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
    this.assemblyLine = '',
    required this.timeLine,
    this.participantsLine = '',
    required this.locationLine,
    this.eventNoteLine = '',
    this.itemsLine,
    this.missingRolesLine,
    required this.sections,
  });

  /// The lines under the event's name:
  /// 1. day and date | assembly | location
  /// 2. audience | show start | show end | team end
  /// 3. participants
  /// Empty parts and lines are left out.
  List<String> get detailLines => [
        for (final line in [
          [dateLine, assemblyLine, locationLine]
              .where((part) => part.trim().isNotEmpty)
              .join(' | '),
          timeLine,
          participantsLine,
        ])
          if (line.trim().isNotEmpty) line,
      ];
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

  /// Who this row is, and the number to call them on (their own phone, else
  /// the assignment's alternative one). Only the "מי איתי" view uses them.
  final String? memberId;
  final String? phoneNumber;

  const EventAssignmentsShareRow({
    required this.memberName,
    this.noteText,
    this.memberId,
    this.phoneNumber,
  });
}

enum EventAssignmentsGroupingMode {
  role,
  label,
}
