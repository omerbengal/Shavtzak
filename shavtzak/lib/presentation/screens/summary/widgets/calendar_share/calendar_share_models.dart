// Pure data snapshot for the events-calendar share card.
//
// Plain immutable classes with no entity/widget/bloc imports — the card
// renders these with zero knowledge of Firestore or domain entities (same
// discipline as EventAssignmentsShareData). They never enter bloc states,
// so Equatable is intentionally not used.

enum CalendarShareMode { weeks, months }

class CalendarShareEvent {
  final String name;

  /// 0–2 lines, e.g. 'התייצבות 15:00–17:00' / 'מופע 17:00–22:30', or a single
  /// 'כל היום'. Empty on continuation days.
  final List<String> timeLines;

  /// Display location with hidden coordinates stripped. Empty when absent or
  /// on continuation days.
  final String locationLine;

  final bool isPast;

  /// True on the 2nd+ visible day of a multi-day event ("(המשך)" rendering).
  final bool isContinuation;

  /// ARGB color of the event's category; null = uncolored (neutral gray block).
  final int? categoryColorValue;

  const CalendarShareEvent({
    required this.name,
    this.timeLines = const [],
    this.locationLine = '',
    required this.isPast,
    this.isContinuation = false,
    this.categoryColorValue,
  });
}

class CalendarShareLegendItem {
  final String name;
  final int colorValue;

  const CalendarShareLegendItem({required this.name, required this.colorValue});
}

class CalendarShareDay {
  final DateTime date;

  /// False for days padding a week/month grid outside the picked range —
  /// rendered dimmed with no events.
  final bool inRange;

  final bool isPast;
  final List<CalendarShareEvent> events;

  const CalendarShareDay({
    required this.date,
    required this.inRange,
    required this.isPast,
    this.events = const [],
  });
}

class CalendarShareWeek {
  /// Exactly 7 entries, index 0 = Sunday. Null = blank cell (months mode,
  /// out-of-month).
  final List<CalendarShareDay?> days;

  const CalendarShareWeek({required this.days});
}

class CalendarShareMonth {
  /// e.g. 'יולי 2026'
  final String title;
  final List<CalendarShareWeek> weeks;

  const CalendarShareMonth({required this.title, required this.weeks});
}

class CalendarShareData {
  /// e.g. '5–31 ביולי 2026'
  final String rangeTitle;
  final CalendarShareMode mode;

  /// Populated in weeks mode; empty in months mode.
  final List<CalendarShareWeek> weeks;

  /// Populated in months mode; empty in weeks mode.
  final List<CalendarShareMonth> months;

  /// Categories (with colors) that appear among in-range events, in category
  /// sortOrder — rendered as a legend on the card.
  final List<CalendarShareLegendItem> legend;

  const CalendarShareData({
    required this.rangeTitle,
    required this.mode,
    this.weeks = const [],
    this.months = const [],
    this.legend = const [],
  });
}
